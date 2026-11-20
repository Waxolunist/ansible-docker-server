#!/usr/bin/env python3
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time

DB = "/var/lib/fail2ban/fail2ban.sqlite3"
PERMANENT_END = 4102444800


def client(*args):
    return subprocess.run(["fail2ban-client", *args], capture_output=True, text=True, check=True).stdout


def jails():
    listed = re.search(r"Jail list:\s*(.*)", client("status")).group(1)
    return [name.strip() for name in listed.split(",") if name.strip()]


def jail_counts(jail):
    status = client("status", jail)
    def number(label):
        return int(re.search(rf"{label}:\s*(\d+)", status).group(1))
    return number("Currently failed"), number("Currently banned"), number("Total banned")


def current_bans(now):
    with sqlite3.connect(f"file:{DB}?mode=ro", uri=True) as db:
        rows = db.execute("SELECT jail, ip, timeofban, bantime, bancount FROM bips").fetchall()
    for jail, ip, start, duration, count in rows:
        end = PERMANENT_END if duration < 0 else start + duration
        if end > now:
            yield jail, ip, start, end, count


def label(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render(now):
    lines = [
        "# HELP fail2ban_jail_failing Addresses with failures below maxretry, per jail.",
        "# TYPE fail2ban_jail_failing gauge",
        "# HELP fail2ban_jail_banned Addresses banned right now, per jail.",
        "# TYPE fail2ban_jail_banned gauge",
        "# HELP fail2ban_jail_bans_since_start Bans since fail2ban last started, per jail.",
        "# TYPE fail2ban_jail_bans_since_start gauge",
    ]
    for jail in jails():
        failing, banned, total = jail_counts(jail)
        lines += [
            f'fail2ban_jail_failing{{jail="{label(jail)}"}} {failing}',
            f'fail2ban_jail_banned{{jail="{label(jail)}"}} {banned}',
            f'fail2ban_jail_bans_since_start{{jail="{label(jail)}"}} {total}',
        ]
    lines += [
        "# HELP fail2ban_ban_start_timestamp_seconds When the current ban of an address began.",
        "# TYPE fail2ban_ban_start_timestamp_seconds gauge",
        "# HELP fail2ban_ban_end_timestamp_seconds When the current ban of an address ends.",
        "# TYPE fail2ban_ban_end_timestamp_seconds gauge",
        "# HELP fail2ban_ban_count How often the address has been banned in this jail, counting the current ban.",
        "# TYPE fail2ban_ban_count gauge",
    ]
    for jail, ip, start, end, count in current_bans(now):
        labels = f'jail="{label(jail)}",ip="{label(ip)}"'
        lines += [
            f"fail2ban_ban_start_timestamp_seconds{{{labels}}} {start}",
            f"fail2ban_ban_end_timestamp_seconds{{{labels}}} {end}",
            f"fail2ban_ban_count{{{labels}}} {count}",
        ]
    lines += [
        "# HELP fail2ban_metrics_timestamp_seconds When these metrics were written.",
        "# TYPE fail2ban_metrics_timestamp_seconds gauge",
        f"fail2ban_metrics_timestamp_seconds {int(now)}",
    ]
    return "\n".join(lines) + "\n"


def write(directory, text):
    os.makedirs(directory, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=directory, prefix=".fail2ban.", suffix=".tmp")
    with os.fdopen(handle, "w") as file:
        file.write(text)
    os.chmod(temporary, 0o644)
    os.replace(temporary, os.path.join(directory, "fail2ban.prom"))


if __name__ == "__main__":
    write(sys.argv[1], render(time.time()))
