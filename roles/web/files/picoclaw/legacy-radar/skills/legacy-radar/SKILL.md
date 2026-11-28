---
name: legacy-radar
description: Research run for legacy migration and AI in Germany, Austria and Switzerland, covering news, public tenders, jobs and freelance projects. Writes a dated report and a digest. Use for /legacy-radar or when asked for a radar run.
---

# Legacy Radar

One run collects what is new since the last run (about two days), filters it,
and writes two files. A separate scheduled job posts the digest at 07:00, so
do not post anything yourself during a scheduled run.

All paths are relative to the workspace. Today's date is `date +%Y-%m-%d`.

## Steps

1. Read `state/seen.txt` (one URL per line; create it empty if missing).
   Anything listed there was already reported and is skipped.
2. Tenders, from the APIs (fast, structured; run each once):
   - `sh scripts/ted.sh 3`: EU tenders in Germany, Austria and Liechtenstein,
     IT categories, last 3 days. Columns: date | type | deadline | title |
     buyer | URL. `cn-*` is a call for tenders (open), `can-*` an award, `pin-*`
     a prior notice.
   - `sh scripts/simap.sh 3`: Swiss tenders. Columns: date | type | title |
     buyer | URL. `tender` is open, `award`/`direct_award` is a result.
3. News: run `sh scripts/gnews.sh '<query>'` for each news query in
   `skills/legacy-radar/sources.md` (Austria, Germany and Switzerland in one
   call).
4. Jobs and freelance projects: use `web_search` with the job queries in
   `sources.md`, at most 12 searches in total. Then `web_fetch` only the
   promising results to confirm the posting is live and to read the details.
5. Below-threshold tenders: use `web_search` with the portal queries in
   `sources.md`, at most 4 searches.
6. Keep a hit only if it is about migrating, replacing or modernising an
   existing system (or AI applied to that), is in Germany, Austria or
   Switzerland, and is not in `state/seen.txt`. Awards count as market
   signals (who buys what, who wins), not as leads. Drop pure hardware,
   building or network-equipment tenders.
7. Score each kept hit from 1 to 3: 3 means an open tender or posting that
   directly asks for legacy migration (mainframe, COBOL, Natural/Adabas, PL/I,
   RPG, Oracle Forms, Delphi, VB6, host replacement) or AI-supported code
   migration; 2 means a modernisation or replacement project with a likely
   legacy part; 1 means a market signal or news.
8. Write `reports/<today>.md`, the full report:
   - a header with the date and the counts per section;
   - sections Tenders, Jobs and projects, News and market, each sorted by
     score, then deadline;
   - one bullet per hit: score, title, organisation, country, deadline or
     date, one sentence on why it matters, URL;
   - at the end, a "Sources not reachable" line for every script or search
     that failed.
9. Write `reports/digest.md`, the message posted at 07:00, at most 3500
   characters:
   - first line: `Legacy Radar <today>: <n> tenders, <n> jobs/projects, <n> news`;
   - the hits with score 3 and 2 (at most 12), shortest form: score,
     title, organisation, deadline, URL;
   - one line with the count of score-1 hits and the report file name.
   If nothing new was found, write only the first line and "Nothing new".
10. Append every reported URL to `state/seen.txt`.
11. Reply with one short line: done, the counts, or what failed.

## When asked in the room

A message in the room (not the scheduled run) may ask for a run now: do
steps 1–10, then also post the digest text as your reply. For questions about
earlier hits, read the files in `reports/`.
