#!/bin/bash
set -euo pipefail

target=${1:-/var/lib/geoip/dbip-city-lite.mmdb}
directory=$(dirname "$target")
mkdir -p "$directory"
download=$(mktemp "$directory/.dbip.XXXXXX")
trap 'rm -f "$download"' EXIT

for month in "$(date +%Y-%m)" "$(date -d "$(date +%Y-%m-15) -1 month" +%Y-%m)"; do
  if curl -fsSL --max-time 900 "https://download.db-ip.com/free/dbip-city-lite-$month.mmdb.gz" | gunzip > "$download"; then
    python3 -c 'import maxminddb, sys; maxminddb.open_database(sys.argv[1]).get("1.1.1.1")' "$download"
    chmod 0644 "$download"
    mv "$download" "$target"
    echo "installed dbip-city-lite-$month"
    exit 0
  fi
done
echo "no DB-IP city lite database could be downloaded" >&2
exit 1
