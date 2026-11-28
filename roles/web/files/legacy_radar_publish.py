import os
import re
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path

REPOSITORY = Path("/app-data/repository")
FOLDER = "legacy radar"
INDEX = f"{FOLDER}.md"
REPORT_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")
AUTHOR = ["-c", "user.name=Legacy Radar", "-c", "user.email=legacy-radar@picoclaw"]


def log(message):
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} legacy-radar-publish: {message}", flush=True)


def read_reports():
    reports = {}
    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as archive:
        for member in archive:
            match = REPORT_NAME.match(os.path.basename(member.name))
            if member.isfile() and match:
                reports[match.group(1)] = archive.extractfile(member).read().decode()
    return reports


def settings():
    values = {}
    with open("/config/settings.cfg") as f:
        exec(f.read(), values)
    return values["GIT_REMOTE_PUSH_URL"], values["GIT_REMOTE_PUSH_PRIVATE_KEY"]


def git(*args, env):
    return subprocess.run(
        ["git", *args], cwd=REPOSITORY, env=env, check=True, capture_output=True, text=True
    ).stdout.strip()


def is_ancestor(older, newer, env):
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", older, newer], cwd=REPOSITORY, env=env
    ).returncode == 0


def counts(text):
    for line in text.splitlines():
        if line.startswith("**Counts:**"):
            return line.removeprefix("**Counts:**").strip()
    return ""


def index_page():
    folder = REPOSITORY / FOLDER
    dates = sorted((p.stem for p in folder.glob("*.md") if REPORT_NAME.match(p.name)), reverse=True)
    lines = [
        "# Legacy Radar",
        "",
        "Research reports on legacy migration and AI in Germany, Austria and Switzerland: "
        "public tenders, jobs and freelance projects, news. PicoClaw's Legacy Radar agent "
        "writes one report every second day; each is published here unchanged.",
        "",
        "## Reports",
        "",
    ]
    for date in dates:
        summary = counts((folder / f"{date}.md").read_text())
        suffix = f": {summary}" if summary else ""
        lines.append(f"- [[{date}|Legacy Radar/{date}]]{suffix}")
    return "\n".join(lines) + "\n"


def write_if_changed(path, text):
    if path.exists() and path.read_text() == text:
        return False
    path.parent.mkdir(exist_ok=True)
    path.write_text(text)
    return True


def main():
    reports = read_reports()
    url, key = settings()
    with tempfile.NamedTemporaryFile("w", delete=False) as key_file:
        key_file.write(key.strip() + "\n")
    os.chmod(key_file.name, 0o600)
    env = {
        **os.environ,
        "GIT_SSH_COMMAND": f"ssh -i {key_file.name} -o IdentitiesOnly=yes "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
    }
    try:
        git("fetch", "--quiet", url, "main", env=env)
        if not is_ancestor("FETCH_HEAD", "HEAD", env):
            if not is_ancestor("HEAD", "FETCH_HEAD", env):
                log("the wiki and GitHub have diverged, nothing published")
                return 1
            git("merge", "--ff-only", "--quiet", "FETCH_HEAD", env=env)

        changed = [d for d, text in sorted(reports.items()) if write_if_changed(REPOSITORY / FOLDER / f"{d}.md", text)]
        write_if_changed(REPOSITORY / INDEX, index_page())
        git("add", "--", FOLDER, INDEX, env=env)
        if git("diff", "--cached", "--name-only", env=env):
            git(*AUTHOR, "commit", "--quiet", "-m", f"Legacy Radar: publish {', '.join(changed) or 'index'}", env=env)
            log(f"committed {', '.join(changed) or 'index'}")

        if git("rev-parse", "HEAD", env=env) != git("rev-parse", "FETCH_HEAD", env=env):
            git("push", "--quiet", url, "HEAD:main", env=env)
            log("pushed to GitHub")
    except subprocess.CalledProcessError as error:
        log(f"git {' '.join(error.cmd[1:3])} failed: {error.stderr.strip()}")
        return 1
    finally:
        os.unlink(key_file.name)
    return 0


sys.exit(main())
