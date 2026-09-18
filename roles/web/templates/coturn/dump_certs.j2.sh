#!/bin/bash
# Extract the {{ coturn.domain }} certificate from Traefik's acme.json and drop
# it where coturn can read it. coturn has no ACME client of its own and Traefik
# already owns port 80, so Traefik stays the only thing talking to Let's
# Encrypt; this script is the hand-off.
#
# Restarts coturn only when the material actually changed, so the every-night
# cron run is a no-op outside of renewals.
#
# Managed by Ansible -- edit roles/web/templates/coturn/dump_certs.j2.sh.

set -euo pipefail

ACME_JSON="{{ docker.paths.work }}traefik/acme.json"
CERT_DIR="{{ docker.paths.configs }}coturn/certs"
DOMAIN="{{ coturn.domain }}"

# Non-zero so the Ansible retry loop keeps waiting on a fresh host where
# Traefik has not written acme.json yet.
if [ ! -s "$ACME_JSON" ]; then
  echo "acme.json missing or empty at $ACME_JSON -- nothing to dump" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$ACME_JSON" "$DOMAIN" "$TMP_DIR" <<'PY'
import base64, json, sys

acme_path, domain, out_dir = sys.argv[1:4]

with open(acme_path) as fh:
    acme = json.load(fh)

for resolver in acme.values():
    for entry in resolver.get("Certificates") or []:
        main = (entry.get("domain") or {}).get("main")
        sans = (entry.get("domain") or {}).get("sans") or []
        if domain != main and domain not in sans:
            continue
        with open(f"{out_dir}/fullchain.pem", "wb") as fh:
            fh.write(base64.b64decode(entry["certificate"]))
        with open(f"{out_dir}/privkey.pem", "wb") as fh:
            fh.write(base64.b64decode(entry["key"]))
        sys.exit(0)

sys.stderr.write(f"no certificate for {domain} in {acme_path}\n")
sys.exit(1)
PY

changed=0
for f in fullchain.pem privkey.pem; do
  if ! cmp -s "$TMP_DIR/$f" "$CERT_DIR/$f"; then
    changed=1
  fi
done

# Ask the container which uid it actually runs as rather than assuming one --
# the coturn image uses nobody (65534), and an image upgrade could change it.
# The fallback covers the first run, before the container exists.
RUN_UID="$(docker exec web_coturn id -u 2>/dev/null || echo 65534)"
RUN_GID="$(docker exec web_coturn id -g 2>/dev/null || echo 65534)"

if [ "$changed" -eq 1 ]; then
  install -m 0444 -o root -g root "$TMP_DIR/fullchain.pem" "$CERT_DIR/fullchain.pem"
  install -m 0400 -o "$RUN_UID" -g "$RUN_GID" "$TMP_DIR/privkey.pem" "$CERT_DIR/privkey.pem"
else
  # Content is current, but ownership may not be -- a placeholder written by
  # Ansible, or a uid change after an image upgrade. Enforce it either way.
  chown root:root "$CERT_DIR/fullchain.pem"; chmod 0444 "$CERT_DIR/fullchain.pem"
  chown "$RUN_UID:$RUN_GID" "$CERT_DIR/privkey.pem"; chmod 0400 "$CERT_DIR/privkey.pem"
  exit 0
fi

echo "certificate for $DOMAIN updated"

# The container does not exist yet the first time this runs, before
# docker compose has come up -- the files are in place either way.
if docker inspect web_coturn >/dev/null 2>&1; then
  echo "restarting coturn to pick it up"
  docker restart web_coturn
fi
