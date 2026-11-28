#!/bin/sh
set -eu

script_dir=$(dirname "$0")

docker exec web_picoclaw tar -C /root/.picoclaw/workspace/legacy-radar/reports -cf - . |
  docker exec -i -u www-data -e HOME=/tmp web_otterwiki \
    /opt/venv/bin/python3 -c "$(cat "$script_dir/legacy_radar_publish.py")"
