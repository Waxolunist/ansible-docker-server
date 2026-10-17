#!/bin/bash
#
# Makes Otterwiki pull from its GitHub remote. Otterwiki has no schedule of
# its own, it only pulls when its webhook is called. GitHub calls it on
# every push; this runs hourly from cron to catch failed deliveries, which
# GitHub does not retry. The call goes to the
# container's own nginx, so it does not pass Authelia. The webhook path is
# an HMAC of GIT_REMOTE_PULL_URL keyed with SECRET_KEY, both read from the
# settings file inside the container, so no secret ends up on this side.
#
# Silent on success. The pull itself runs in the background inside
# Otterwiki; a failure shows up in its log as "Pull from remote failed".

docker exec -i web_otterwiki /opt/venv/bin/python3 - <<'PY'
import hashlib
import hmac
import urllib.request

cfg = {}
with open("/config/settings.cfg") as f:
    exec(f.read(), cfg)
webhook_hash = hmac.new(
    cfg["SECRET_KEY"].encode(), cfg["GIT_REMOTE_PULL_URL"].encode(), hashlib.sha256
).hexdigest()
urllib.request.urlopen(f"http://localhost/-/api/v1/pull/{webhook_hash}", timeout=30)
PY
