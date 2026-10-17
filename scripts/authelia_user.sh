#!/bin/bash
#
# Manages the Authelia users on the web server. Authelia owns the users
# database (users reset their own passwords), so users are added and
# disabled here rather than in Ansible. Authelia watches the file and picks
# up every change within seconds, without a restart.
#
#   authelia_user.sh list
#   authelia_user.sh add <username> <email> <display name> <group>...
#   authelia_user.sh groups <username> <group>...
#   authelia_user.sh disable <username>
#   authelia_user.sh enable <username>
#   authelia_user.sh delete <username>
#
# A new user gets a random password, printed once. Either hand it over, or
# let the user set their own via "Reset password" on the login page.
#
# Groups: admins and Viewer reach every protected service, WIKI_USER and
# WIKI_ADMIN the wiki (see roles/web/vars/main.yml).

set -euo pipefail

# ssh joins its arguments into one remote command line, so quote each one.
ssh devops@v-collaborate.com "python3 - $(printf '%q ' "$@")" <<'PY'
import os
import re
import shutil
import subprocess
import sys

import yaml

PATH = "/var/docker/data/authelia/users/users_database.yml"
USAGE = """usage:
  authelia_user.sh list
  authelia_user.sh add <username> <email> <display name> <group>...
  authelia_user.sh groups <username> <group>...
  authelia_user.sh disable <username>
  authelia_user.sh enable <username>
  authelia_user.sh delete <username>"""


def fail(message):
    sys.exit(f"error: {message}")


def load():
    if not os.path.exists(PATH):
        return {"users": {}}
    with open(PATH, encoding="utf-8") as f:
        db = yaml.safe_load(f) or {}
    db["users"] = db.get("users") or {}
    return db


def save(db):
    data = yaml.safe_dump(db, allow_unicode=True, sort_keys=False, width=1000)
    if os.path.exists(PATH):
        shutil.copy2(PATH, PATH + ".bak")
    # Write a temporary file and rename it over the database. Rewriting in
    # place fires two events (truncate, write); Authelia reloads on the first
    # and ignores the second for a cooldown, so it could load an empty file.
    # The rename fires one. Authelia watches the directory, so it keeps
    # watching the new file.
    tmp = PATH + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, PATH)


def user(db, name):
    if name not in db["users"]:
        fail(f"no user {name}")
    return db["users"][name]


def check_groups(db, groups):
    # A misspelt group silently grants nothing, so point out unknown ones.
    known = {g for u in db["users"].values() for g in u.get("groups") or []}
    for group in groups:
        if known and group not in known:
            print(f"warning: no other user is in group {group}")


def random_password_hash():
    out = subprocess.run(
        ["docker", "exec", "authelia", "authelia", "crypto", "hash", "generate", "argon2",
         "--random", "--random.length", "20", "--random.charset", "alphanumeric"],
        check=True, capture_output=True, text=True,
    ).stdout
    password = re.search(r"^Random Password: (\S+)$", out, re.M)
    digest = re.search(r"^Digest: (\S+)$", out, re.M)
    if not password or not digest:
        fail(f"unexpected output from authelia crypto hash generate:\n{out}")
    return password.group(1), digest.group(1)


def cmd_list(db):
    if not os.path.exists(PATH):
        fail(f"{PATH} does not exist")
    rows = [("USER", "NAME", "EMAIL", "GROUPS", "")]
    for name, u in db["users"].items():
        rows.append((name, u.get("displayname", ""), u.get("email", ""),
                     ",".join(u.get("groups") or []), "DISABLED" if u.get("disabled") else ""))
    widths = [max(len(r[i]) for r in rows) for i in range(4)]
    for r in rows:
        print("  ".join(c.ljust(w) for c, w in zip(r, widths)), r[4])


def cmd_add(db, name, email, displayname, *groups):
    if not groups:
        fail("give at least one group")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", name):
        fail("username may only contain a-z, 0-9, '.', '_' and '-'")
    if name in db["users"]:
        fail(f"user {name} exists already")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        fail(f"not an email address: {email}")
    check_groups(db, groups)
    password, digest = random_password_hash()
    db["users"][name] = {
        "displayname": displayname,
        "password": digest,
        "email": email,
        "groups": list(groups),
    }
    save(db)
    print(f"Added {name}. Initial password: {password}")
    print("The user can also set their own via \"Reset password\" on the login page.")


def cmd_groups(db, name, *groups):
    if not groups:
        fail("give at least one group")
    check_groups(db, groups)
    user(db, name)["groups"] = list(groups)
    save(db)
    print(f"Groups of {name}: {', '.join(groups)}")


def cmd_disable(db, name):
    u = user(db, name)
    if u.get("disabled"):
        print(f"{name} is disabled already")
        return
    u["disabled"] = True
    save(db)
    print(f"Disabled {name}. Open sessions end within a minute.")


def cmd_enable(db, name):
    u = user(db, name)
    if not u.pop("disabled", False):
        print(f"{name} is not disabled")
        return
    save(db)
    print(f"Enabled {name}")


def storage(*args):
    return subprocess.run(
        ["docker", "exec", "authelia", "authelia", "storage", "user", *args,
         "--config", "/config/configuration.yml"],
        capture_output=True, text=True,
    )


def cmd_delete(db, name):
    user(db, name)
    del db["users"][name]
    save(db)
    print(f"Deleted {name}. Open sessions end within a minute.")
    # 2FA devices live in Authelia's database, not the users file, and would
    # carry over to anyone later given the same username.
    totp = storage("totp", "delete", name)
    if totp.returncode == 0:
        print(f"Removed the TOTP configuration of {name}")
    elif "no TOTP configuration" not in totp.stdout + totp.stderr:
        print(f"warning: could not remove the TOTP configuration:\n{totp.stderr or totp.stdout}")
    webauthn = storage("webauthn", "delete", name, "--all")
    if webauthn.returncode != 0:
        print(f"warning: could not remove the WebAuthn credentials:\n{webauthn.stderr or webauthn.stdout}")


COMMANDS = {
    "list": (cmd_list, 0, 0),
    "add": (cmd_add, 4, None),
    "groups": (cmd_groups, 2, None),
    "disable": (cmd_disable, 1, 1),
    "enable": (cmd_enable, 1, 1),
    "delete": (cmd_delete, 1, 1),
}

args = sys.argv[1:]
if not args or args[0] not in COMMANDS:
    sys.exit(USAGE)
func, least, most = COMMANDS[args[0]]
rest = args[1:]
if len(rest) < least or (most is not None and len(rest) > most):
    sys.exit(USAGE)
func(load(), *rest)
PY
