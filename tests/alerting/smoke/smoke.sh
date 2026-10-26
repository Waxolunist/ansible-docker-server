#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
"$(cd ../../.. && pwd)/scripts/check_alerting.sh" >/dev/null
sed -n 's/^vault_matrix_alerts_receiver_password: "\(.*\)"$/\1/p' ../test_vars.yml | tr -d '\n' > receiver_password
work="$(mktemp -d)"
trap 'docker compose down -v >/dev/null 2>&1; rm -rf receiver_password "$work"' EXIT
docker compose up -d --wait conduit alertmanager >/dev/null
docker compose up -d matrix-receiver >/dev/null

start="$(date -u -v-20M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-20 min' +%Y-%m-%dT%H:%M:%SZ)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed "s/\"labels\"/\"startsAt\": \"$start\", \"labels\"/" alerts.json > "$work/firing.json"
curl -sf -XPOST -H 'Content-Type: application/json' --data @"$work/firing.json" http://127.0.0.1:19093/api/v2/alerts
echo "posted firing alerts, waiting for group_wait"
sleep 40
curl -sf "http://127.0.0.1:19093/api/v2/alerts?filter=alertname=%22Watchdog%22" | grep -q Watchdog && echo "Alertmanager holds Watchdog"
curl -sf -o /dev/null -w "bridge /metrics: %{http_code}\n" http://127.0.0.1:12345/metrics

sed "s/\"labels\"/\"startsAt\": \"$start\", \"endsAt\": \"$now\", \"labels\"/" alerts.json > "$work/resolved.json"
curl -sf -XPOST -H 'Content-Type: application/json' --data @"$work/resolved.json" http://127.0.0.1:19093/api/v2/alerts
echo "posted resolved alerts, waiting for group_interval"
sleep 320

curl -sf http://127.0.0.1:16167/messages | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    c = m["content"]
    print("---", m["room"])
    print(c.get("body"))
    print("m.mentions:", c.get("m.mentions"))
'
