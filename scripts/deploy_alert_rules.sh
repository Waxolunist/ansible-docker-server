#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

"$repo/scripts/check_alerting.sh"
cd "$repo"
ansible-playbook web.yml --tags prometheus_rules "$@"
