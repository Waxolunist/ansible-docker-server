#!/bin/bash
#
# Restore a TimescaleDB backup (dump_timescale_*.sql.gz from backup_databases.sh)
# into a separate database, with TimescaleDB's catalog intact (TASK-051).
#
# A TimescaleDB dump only restores completely between timescaledb_pre_restore()
# and timescaledb_post_restore(), with the same extension version as the dump.
# Without them, as on 2026-04-04, the data ends up in plain tables and the
# hypertables, continuous aggregates and jobs are lost.
#
# The backup goes into a new database (default timescale_home_restore), never
# over the running one. Check it, then make it the live database with
#   TS_NEW=timescale_home_restore scripts/timescale_rebuild.sh swap
# from the ansible-docker-server repository (the old one is kept).
#
# Usage: restore_timescale.sh [backup_file] [target_database]
#   backup_file      default: the newest non-empty /backup/dump_timescale_*.sql.gz
#   target_database  default: timescale_home_restore (must not exist)

set -euo pipefail

cd {{ docker_base_path }}

# Overridable for a test against another container.
DB_EXEC="${DB_EXEC:-docker compose exec -T timescaledb}"
DB_USER="${DB_USER:-{{ vault_timescale_pg_user }}}"
LIVE_DB="${LIVE_DB:-timescale_home}"

usage() {
    sed -n '3,18p' "$0" | cut -c3-
    exit 1
}

# psql in the database container. Usage: q DB [psql args...]
q() {
    local db="$1"
    shift
    $DB_EXEC psql -U "$DB_USER" -d "$db" -X -q -v ON_ERROR_STOP=1 "$@"
}

case "${1:-}" in -h | --help) usage ;; esac
[ $# -le 2 ] || usage

BACKUP_FILE="${1:-}"
TARGET="${2:-timescale_home_restore}"

if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE="$(find /backup -name 'dump_timescale_*.sql.gz' -size +0c -type f -printf '%T@ %p\n' 2>/dev/null |
        sort -nr | head -1 | cut -d' ' -f2)"
    [ -n "$BACKUP_FILE" ] || { echo "ERROR: no TimescaleDB backup in /backup"; exit 1; }
fi
[ -s "$BACKUP_FILE" ] || { echo "ERROR: backup file missing or empty: $BACKUP_FILE"; exit 1; }

echo "Backup:   $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
echo "Target:   database $TARGET (the live $LIVE_DB is not touched)"

if [ "$(q postgres -tA -c "select count(*) from pg_database where datname = '$TARGET'" </dev/null)" != 0 ]; then
    echo "ERROR: database $TARGET exists already; drop it first: DROP DATABASE $TARGET"
    exit 1
fi

# The extension versions of the live database, which the nightly backups come
# from. A dump does not record them; after an extension upgrade, restoring an
# older backup needs the version it was made with (ALTER EXTENSION afterwards).
TS_VERSION="$(q "$LIVE_DB" -tA -c "select extversion from pg_extension where extname = 'timescaledb'" </dev/null)"
TOOLKIT_VERSION="$(q "$LIVE_DB" -tA -c "select extversion from pg_extension where extname = 'timescaledb_toolkit'" </dev/null || true)"
echo "Versions: timescaledb $TS_VERSION${TOOLKIT_VERSION:+, timescaledb_toolkit $TOOLKIT_VERSION}"

# template0: the image installs its newest TimescaleDB into template1.
q postgres -c "create database \"$TARGET\" template template0" </dev/null
q "$TARGET" -c "create extension timescaledb version '$TS_VERSION'" </dev/null
[ -z "$TOOLKIT_VERSION" ] || q "$TARGET" -c "create extension timescaledb_toolkit version '$TOOLKIT_VERSION'" </dev/null
q "$TARGET" -c "select timescaledb_pre_restore()" </dev/null >/dev/null

echo "Restoring..."
LOG="$(mktemp /tmp/restore_timescale.XXXXXX)"
# Inside the container: the archive (pg_restore -L needs a file) and its table
# of contents without the materialized views' data. pg_restore refreshes those
# with an empty search_path, where their time_bucket() calls fail; they are
# refreshed below instead.
gunzip -c "$BACKUP_FILE" | $DB_EXEC sh -c 'cat > /tmp/restore_timescale.dump'
$DB_EXEC sh -c 'pg_restore -l /tmp/restore_timescale.dump | grep -v "MATERIALIZED VIEW DATA" > /tmp/restore_timescale.list'
# pg_restore fails on the extensions created above ("already exists"), which
# is expected; any other error stops here.
$DB_EXEC pg_restore -U "$DB_USER" -d "$TARGET" --no-owner --no-privileges \
    -L /tmp/restore_timescale.list /tmp/restore_timescale.dump >"$LOG" 2>&1 || true
$DB_EXEC rm -f /tmp/restore_timescale.dump /tmp/restore_timescale.list
if grep -E '^pg_restore: error' "$LOG" | grep -vqE 'extension "timescaledb(_toolkit)?" already exists'; then
    grep -E '^pg_restore: error|^Command was' "$LOG" | head -20
    echo "ERROR: the restore failed (full output: $LOG); $TARGET is incomplete, drop it: DROP DATABASE $TARGET"
    exit 1
fi
rm -f "$LOG"

q "$TARGET" -c "select timescaledb_post_restore()" </dev/null >/dev/null

TABLES="$(q "$TARGET" -tA -c "select count(*) from pg_tables where schemaname = 'public'" </dev/null)"
[ "$TABLES" -gt 0 ] || { echo "ERROR: no tables in $TARGET after the restore"; exit 1; }

echo "Refreshing the materialized views..."
for VIEW in $(q "$TARGET" -tA -c "select format('%I.%I', n.nspname, c.relname) from pg_class c
                                  join pg_namespace n on n.oid = c.relnamespace
                                  where c.relkind = 'm' and n.nspname = 'public' order by c.oid" </dev/null); do
    q "$TARGET" -c "refresh materialized view $VIEW" </dev/null
done

echo ""
q "$TARGET" -tA -c "select (select count(*) from timescaledb_information.hypertables) || ' hypertables, '
                         || (select count(*) from timescaledb_information.continuous_aggregates) || ' continuous aggregates, '
                         || (select count(*) from timescaledb_information.jobs) || ' jobs, '
                         || pg_size_pretty(pg_database_size(current_database()))" </dev/null |
    sed "s/^/Restored $TARGET: /"
echo ""
echo "Check it (e.g. row counts against $LIVE_DB), then switch with"
echo "  TS_NEW=$TARGET scripts/timescale_rebuild.sh swap"
echo "or drop it: DROP DATABASE $TARGET"
