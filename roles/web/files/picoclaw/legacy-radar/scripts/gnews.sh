#!/bin/sh
set -eu

query="${1:?query}"
encoded=$(printf '%s' "$query when:3d" | sed 's/ /+/g; s/"/%22/g')
for region in AT:de DE:de CH:de; do
  wget -qO- -T 30 "https://news.google.com/rss/search?q=$encoded&hl=de&gl=${region%%:*}&ceid=$region" |
    tr '\n' ' ' |
    awk -v RS='<item>' 'NR > 1 {
      title = $0; sub(/.*<title>/, "", title); sub(/<\/title>.*/, "", title)
      link = $0; sub(/.*<link>/, "", link); sub(/<\/link>.*/, "", link)
      date = $0; sub(/.*<pubDate>/, "", date); sub(/<\/pubDate>.*/, "", date)
      print date " | " title " | " link
    }' |
    head -15
done | sort -u
