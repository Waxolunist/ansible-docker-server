#!/bin/sh
set -eu

dir=/root/.picoclaw/workspace/legacy-radar/reports
digest="$dir/digest.md"

if [ ! -f "$digest" ] || [ "$(date -r "$digest" +%Y-%m-%d)" != "$(date +%Y-%m-%d)" ]; then
  echo "Legacy Radar: no report from this morning's run. Last digest: $(date -r "$digest" '+%Y-%m-%d %H:%M' 2>/dev/null || echo none)."
  exit 0
fi
cat "$digest"
printf '\nFull report: https://%s/Legacy%%20Radar/%s\n' "$(cat /root/.picoclaw/workspace/legacy-radar/wiki_host)" "$(date +%Y-%m-%d)"
