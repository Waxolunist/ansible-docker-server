#!/usr/bin/env python3
"""List the dashboards in Grafana and pull them into the provisioning folder.

    scripts/grafana_dashboards.py list
    scripts/grafana_dashboards.py pull [UID ...]

Run it from anywhere; paths resolve against the repository root.

The Grafana API is reached over SSH: every request runs curl inside the
web_grafana container against localhost:3000, so Authelia is not involved and
nothing new is exposed. The token of the read-only (Viewer) service account
`dashboard-sync` comes from the GRAFANA_TOKEN environment variable or from
`vault_grafana_dashboard_sync_token` in group_vars/web/vault.yml, and is sent
to curl on stdin, never on a command line.

`pull` writes each dashboard into roles/web/files/grafana/provisioning/
dashboards, in the subdirectory named after its Grafana folder (General = top
level), like the provider's foldersFromFilesStructure. An existing file for the
same uid is overwritten in place (moved if the dashboard changed folder); a
dashboard created in the UI becomes a new file. Each file keeps the format
Grafana stores it in: v2 (`dashboard.grafana.app/v2`, metadata + spec) or
classic v1 JSON. Volatile metadata is stripped and the JSON is written with
sorted keys, so `git diff` shows only real changes. Secret values from the
vault are replaced by their @@NAME@@ placeholders before writing.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DASHBOARDS_DIR = REPO / "roles/web/files/grafana/provisioning/dashboards"
VAULT_FILE = REPO / "group_vars/web/vault.yml"
TOKEN_VAR = "vault_grafana_dashboard_sync_token"
# Placeholder -> vault variable. Must match the replace() filters in
# roles/web/tasks/grafana_dashboards.yml, which fill them in on deploy.
PLACEHOLDERS = {"@@PSA_URL@@": "vault_psa_url"}

SSH_HOST = os.environ.get("GRAFANA_SSH_HOST", "devops@v-collaborate.com")
CONTAINER = "web_grafana"
NAMESPACE = "default"  # Kubernetes-style namespace of Grafana org 1
V2_PREFIX = "dashboard.grafana.app/v2"


class ApiError(Exception):
    def __init__(self, path, status, body):
        super().__init__(f"GET {path} -> HTTP {status}: {body[:300]}")
        self.status = status
        self.body = body


def read_vault():
    """Return the top-level `key: value` scalars of the web vault."""
    out = subprocess.run(
        ["ansible-vault", "view", str(VAULT_FILE)],
        cwd=REPO, check=True, capture_output=True, text=True,
    ).stdout
    values = {}
    for line in out.splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
        if not m:
            continue
        value = m.group(2)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[m.group(1)] = value
    return values


class Grafana:
    def __init__(self, token):
        self.token = token
        self.folders = {}

    def get(self, path):
        # A shared SSH connection, so the many small requests don't each pay
        # for a handshake.
        cmd = [
            "ssh", "-o", "BatchMode=yes",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=~/.ssh/cm-grafana-%C",
            "-o", "ControlPersist=60",
            SSH_HOST,
            f"docker exec -i {CONTAINER} curl -sS -H @- -w '\\n%{{http_code}}' "
            f"'http://localhost:3000{path}'",
        ]
        res = subprocess.run(
            cmd, input=f"Authorization: Bearer {self.token}\n",
            capture_output=True, text=True,
        )
        if res.returncode != 0:
            sys.exit(f"ssh/curl failed for {path}: {res.stderr.strip()}")
        body, _, status = res.stdout.rpartition("\n")
        if status != "200":
            raise ApiError(path, status, body)
        return json.loads(body)

    def dashboards(self):
        return self.get("/api/search?type=dash-db&limit=5000")

    def folder_path(self, uid):
        """Folder uid -> relative directory, including parent folders."""
        if uid not in self.folders:
            folder = self.get(f"/api/folders/{uid}")
            titles = [p["title"] for p in folder.get("parents") or []]
            self.folders[uid] = "/".join(safe_name(t) for t in titles + [folder["title"]])
        return self.folders[uid]

    def dashboard(self, uid, prefer_v2):
        """Fetch a dashboard in the format Grafana stores it in."""
        if not prefer_v2:
            try:
                return "v1", self.get(f"/api/dashboards/uid/{uid}")["dashboard"]
            except ApiError as e:
                # The classic API refuses v2 dashboards and names the API
                # version to use instead.
                if e.status != "406":
                    raise
                m = re.search(r"dashboard\.grafana\.app/(v2[0-9a-z]*)/", e.body)
                version = m.group(1) if m else "v2"
        else:
            version = prefer_v2.split("/", 1)[1]
        path = f"/apis/dashboard.grafana.app/{version}/namespaces/{NAMESPACE}/dashboards/{uid}"
        return "v2", self.get(path)


def safe_name(text):
    """Folder titles become directory names, so no path separators."""
    return text.replace("/", "_").strip() or "_"


def slug(title):
    return re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_") or "dashboard"


def file_uid(data):
    if data.get("apiVersion", "").startswith(V2_PREFIX):
        return data["metadata"]["name"]
    return data.get("uid")


def local_files():
    """uid -> (path, apiVersion or None) of the dashboards in the repo."""
    files = {}
    for path in sorted(DASHBOARDS_DIR.rglob("*.json")):
        data = json.loads(path.read_text())
        uid = file_uid(data)
        if uid:
            files[uid] = (path, data.get("apiVersion"))
    return files


def clean(kind, data):
    """Strip what changes on every save, keep what the provider needs."""
    if kind == "v2":
        return {
            "apiVersion": data["apiVersion"],
            "kind": data["kind"],
            "metadata": {"name": data["metadata"]["name"]},
            "spec": data["spec"],
        }
    data = dict(data)
    data.pop("id", None)
    data.pop("version", None)
    return data


def render(data, secrets):
    text = json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    for placeholder, value in secrets.items():
        if value:
            # Replace the value as it appears inside JSON strings.
            text = text.replace(json.dumps(value)[1:-1], placeholder)
    return text


def target_dir(api, item):
    folder_uid = item.get("folderUid")
    if not folder_uid:
        return DASHBOARDS_DIR
    return DASHBOARDS_DIR / api.folder_path(folder_uid)


def cmd_list(api, args, vault):
    files = local_files()
    items = api.dashboards()
    rows = [("UID", "FOLDER", "TITLE", "FILE")]
    for item in sorted(items, key=lambda i: (i.get("folderTitle") or "", i["title"])):
        local = files.pop(item["uid"], None)
        rows.append((
            item["uid"], item.get("folderTitle") or "General", item["title"],
            str(local[0].relative_to(DASHBOARDS_DIR)) if local else "(new)",
        ))
    widths = [max(len(r[i]) for r in rows) for i in range(3)]
    for r in rows:
        print("  ".join(c.ljust(w) for c, w in zip(r, widths)) + "  " + r[3])
    for uid, (path, _) in files.items():
        print(f"only in repo: {path.relative_to(DASHBOARDS_DIR)} ({uid})")


def cmd_pull(api, args, vault):
    secrets = {}
    for placeholder, var in PLACEHOLDERS.items():
        if not vault.get(var):
            sys.exit(f"{var} not found in {VAULT_FILE.name}, refusing to write unscrubbed files")
        secrets[placeholder] = vault[var]

    files = local_files()
    items = api.dashboards()
    if args.uids:
        unknown = set(args.uids) - {i["uid"] for i in items}
        if unknown:
            sys.exit(f"not in Grafana: {', '.join(sorted(unknown))}")
        items = [i for i in items if i["uid"] in args.uids]

    for item in items:
        uid = item["uid"]
        local_path, local_version = files.get(uid, (None, None))
        prefer_v2 = local_version if (local_version or "").startswith(V2_PREFIX) else None
        kind, data = api.dashboard(uid, prefer_v2)
        text = render(clean(kind, data), secrets)

        directory = target_dir(api, item)
        if local_path and local_path.parent == directory:
            path = local_path
        else:
            name = local_path.name if local_path else f"{slug(item['title'])}.json"
            path = directory / name
            if path.exists() and file_uid(json.loads(path.read_text())) != uid:
                path = directory / f"{slug(item['title'])}_{uid}.json"

        rel = path.relative_to(DASHBOARDS_DIR)
        if path.exists() and path.read_text() == text:
            print(f"unchanged  {rel}")
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        if local_path and local_path != path:
            local_path.unlink()
            print(f"moved      {local_path.relative_to(DASHBOARDS_DIR)} -> {rel}")
        else:
            print(f"{'updated' if local_path else 'new':<10} {rel}")

    if not args.uids:
        pulled = {i["uid"] for i in items}
        for uid, (path, _) in files.items():
            if uid not in pulled:
                print(f"only in repo: {path.relative_to(DASHBOARDS_DIR)} ({uid})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="list the dashboards in Grafana and their files")
    pull = sub.add_parser("pull", help="download dashboards into the repository")
    pull.add_argument("uids", nargs="*", metavar="UID", help="only these dashboards")
    args = parser.parse_args()

    token = os.environ.get("GRAFANA_TOKEN")
    vault = read_vault() if not token or args.command == "pull" else {}
    token = token or vault.get(TOKEN_VAR)
    if not token:
        sys.exit(f"no token: set GRAFANA_TOKEN or add {TOKEN_VAR} to the vault")
    api = Grafana(token)
    try:
        {"list": cmd_list, "pull": cmd_pull}[args.command](api, args, vault)
    except ApiError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
