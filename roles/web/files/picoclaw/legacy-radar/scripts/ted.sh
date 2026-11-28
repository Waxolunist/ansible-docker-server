#!/bin/sh
set -eu

days="${1:-3}"
terms=""
for term in Legacy Altsystem Altsysteme Altanwendung Ablösung Modernisierung Migration COBOL PL/I Mainframe Großrechner Natural Adabas AS/400 "Oracle Forms" Reengineering; do
  terms="${terms:+$terms OR }FT ~ \\\"$term\\\""
done
query="($terms) AND classification-cpv IN (72000000 48000000) AND buyer-country IN (DEU AUT LIE) AND publication-date >= today(-$days)"
body=$(printf '{"query":"%s","fields":["notice-title","buyer-name","buyer-country","publication-date","deadline-receipt-tender-date-lot","notice-type"],"limit":100}' "$query")

wget -qO- -T 60 --header 'Content-Type: application/json' --post-data "$body" \
  https://api.ted.europa.eu/v3/notices/search |
  awk '
    function grab(text, pattern, skip,    value) {
      if (!match(text, pattern)) return ""
      value = substr(text, RSTART + skip, RLENGTH - skip)
      sub(/"$/, "", value)
      return value
    }
    function field(notice, name,    start, rest, end, block) {
      start = index(notice, "\"" name "\":")
      if (start == 0) return ""
      rest = substr(notice, start + length(name) + 3)
      end = index(rest, "}")
      if (substr(rest, 1, 1) == "[") end = index(rest, "]")
      block = substr(rest, 1, end)
      if (match(block, /"deu":\["?[^"\]]*/)) return grab(block, "\"deu\":\\[?\"[^\"]*\"", 8)
      if (match(block, /"eng":/)) return grab(block, "\"eng\":\\[?\"[^\"]*\"", 8)
      return grab(block, "\"[^\"]*\"", 1)
    }
    {
      depth = 0; notice = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        if (depth >= 2) notice = notice c
        if (c == "}") {
          depth--
          if (depth == 1 && notice != "") {
            number = grab(notice, "\"publication-number\":\"[^\"]*\"", 22)
            date = substr(grab(notice, "\"publication-date\":\"[^\"]*\"", 20), 1, 10)
            kind = grab(notice, "\"notice-type\":\"[^\"]*\"", 15)
            deadline = substr(grab(notice, "\"deadline-receipt-tender-date-lot\":\\[\"[^\"]*\"", 37), 1, 10)
            title = field(notice, "notice-title")
            sub(/^[^–]*– [^–]*– /, "", title)
            buyer = field(notice, "buyer-name")
            printf "%s | %s | deadline %s | %s | %s | https://ted.europa.eu/de/notice/-/detail/%s\n", date, kind, (deadline == "" ? "-" : deadline), title, buyer, number
            notice = ""
          }
        }
      }
    }'
