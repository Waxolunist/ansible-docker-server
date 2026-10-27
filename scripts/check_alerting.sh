#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tests="$repo/tests/alerting"
rendered="$tests/rendered"
prometheus_image="$(grep -o 'prom/prometheus:v[0-9.]*' "$repo/roles/web/templates/docker-compose_yml.j2")"
alertmanager_image="$(grep -o 'prom/alertmanager:v[0-9.]*' "$repo/roles/web/templates/docker-compose_yml.j2")"

promtool() {
  docker run --rm -v "$tests:/t:ro" -w /t --entrypoint promtool "$prometheus_image" "$@"
}

amtool() {
  docker run --rm -v "$rendered/alertmanager:/etc/alertmanager:ro" --entrypoint amtool "$alertmanager_image" "$@"
}

expect_route() {
  local expected="$1"
  shift
  amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml --verify.receivers="$expected" "$@" >/dev/null \
    || { echo "route for $* is not $expected"; exit 1; }
}

echo "== render templates and check labels and annotations"
render_log="$(cd "$tests" && ansible-playbook render.yml 2>&1)" || { echo "$render_log"; exit 1; }
grep -o '"msg": ".*alert rules checked.*"' <<<"$render_log"

echo "== promtool check config and rules"
docker run --rm -v "$rendered/prometheus:/etc/prometheus:ro" --entrypoint promtool "$prometheus_image" \
  check config --lint=all --lint-fatal /etc/prometheus/prometheus.yml

echo "== promtool test rules"
promtool test rules alerts_test.yml

echo "== amtool check-config and routes"
amtool check-config /etc/alertmanager/alertmanager.yml
expect_route "null" alertname=Watchdog area=infra severity=info
expect_route infra alertname=PiUnreachable area=infra severity=critical
expect_route car alertname=PsaLoginLost area=car severity=critical
expect_route energy alertname=GridImportHigh area=energy severity=warning
expect_route data alertname=DataStale_data_power_live area=data severity=warning
expect_route security alertname=Test area=security severity=warning
expect_route infra alertname=NoArea
echo "routes OK"
