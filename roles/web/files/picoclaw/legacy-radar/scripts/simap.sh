#!/bin/sh
set -eu

days="${1:-3}"
since=$(date -d "@$(( $(date +%s) - days * 86400 ))" +%Y-%m-%d)

for term in Migration Ablösung Modernisierung Legacy Mainframe COBOL Altsystem Reengineering; do
  encoded=$(printf '%s' "$term" | sed 's/ö/%C3%B6/g')
  for cpv in 72000000 48000000; do
    wget -qO- -T 60 "https://www.simap.ch/api/publications/v2/project/project-search?lang=de&cpvCodes=$cpv&search=$encoded" |
      sed 's/},{"id":"/}\n{"id":"/g' |
      sed -n 's/^.*{"id":"\([^"]*\)","title":{"de":"\([^"]*\)".*"pubType":"\([^"]*\)".*"publicationDate":"\([^"]*\)".*"procOfficeName":{"de":"\([^"]*\)".*/\4 | \3 | \2 | \5 | https:\/\/www.simap.ch\/de\/project-detail\/\1/p;s/^.*{"id":"\([^"]*\)","title":{"de":"\([^"]*\)".*"publicationDate":"\([^"]*\)","publicationNumber":"[^"]*","pubType":"\([^"]*\)".*"procOfficeName":{"de":"\([^"]*\)".*/\3 | \4 | \2 | \5 | https:\/\/www.simap.ch\/de\/project-detail\/\1/p' |
      awk -F' [|] ' -v since="$since" '$1 >= since'
  done
done | sort -u -r
