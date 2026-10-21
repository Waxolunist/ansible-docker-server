#!/bin/bash
#
# Rebuild the collector's TimescaleDB database (timescale_home) from the
# migrations and copy the data into it (TASK-051).
#
# Since a dump/restore on 2026-04-04 without timescaledb_pre_restore() and
# timescaledb_post_restore(), production has the data in plain tables but no
# hypertables, continuous aggregates, refresh jobs or the views built on them.
# This script builds a fresh database next to it with the collector's alembic
# migrations, copies every table over, refreshes the aggregates, compares the
# two, and swaps the names. The old database stays as <name>_broken_<date>_<time>.
#
# Run it on the Docker host, one phase at a time (docs: how-to/rebuild-the-
# timescale-database.md). Stop the collector on the Pi before "copy" and start
# it after "swap", so no writes go to the old database in between.
#
#   scripts/timescale_rebuild.sh create            new database, same extension versions
#   scripts/timescale_rebuild.sh build < src.tar   alembic upgrade head (collector source as tar)
#   scripts/timescale_rebuild.sh copy              copy all tables, old -> new
#   scripts/timescale_rebuild.sh refresh           refresh continuous aggregates and matviews
#   scripts/timescale_rebuild.sh verify            row counts, foreign keys, Timescale catalog
#   scripts/timescale_rebuild.sh swap              old -> <old>_broken_<date>_<time>, new -> old
#
# Environment:
#   TS_CONTAINER  database container          (default: web_timescaledb)
#   TS_DB         database to rebuild         (default: timescale_home)
#   TS_NEW        name of the new database    (default: timescale_home_new)
#   TS_PASSWORD   password for alembic        (default: the container's
#                 /run/secrets/timescale_superuser_password)
#   PY_IMAGE      image alembic runs in       (default: python:3.14-slim)

set -euo pipefail

TS_CONTAINER="${TS_CONTAINER:-web_timescaledb}"
TS_DB="${TS_DB:-timescale_home}"
TS_NEW="${TS_NEW:-timescale_home_new}"
PY_IMAGE="${PY_IMAGE:-python:3.14-slim}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# psql in the database container. Usage: q DB [psql args...]
q() {
    local db="$1"
    shift
    docker exec -i "$TS_CONTAINER" psql -U "$PGUSER" -d "$db" -X -q -v ON_ERROR_STOP=1 "$@"
}
# One value per line, no headers. Usage: val DB SQL
# (</dev/null: docker exec -i would read the script's stdin, e.g. the tar of build)
val() { q "$1" -tA -c "$2" </dev/null; }

db_exists() { [ "$(val postgres "select count(*) from pg_database where datname = '$1'")" = 1 ]; }

# The public tables of the new database, except alembic_version.
tables() {
    val "$TS_NEW" "select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relkind = 'r' and c.relname <> 'alembic_version'
                   order by 1"
}

# Columns a table has in both databases, in the new table's order, without
# generated columns (the new database computes those itself).
columns() {
    local table="$1" new old
    new="$(val "$TS_NEW" "select attname from pg_attribute where attrelid = 'public.$table'::regclass
                          and attnum > 0 and not attisdropped and attgenerated = '' order by attnum")"
    old="$(val "$TS_DB" "select attname from pg_attribute where attrelid = to_regclass('public.$table')
                         and attnum > 0 and not attisdropped")"
    grep -Fxf <(printf '%s\n' "$old") <(printf '%s\n' "$new") | sed 's/.*/"&"/' | paste -sd, -
}

phase_create() {
    db_exists "$TS_DB" || fail "$TS_DB does not exist"
    db_exists "$TS_NEW" && fail "$TS_NEW exists already; drop it first: DROP DATABASE $TS_NEW"
    local extensions
    # The same extension versions as the old database, so nothing is upgraded
    # on the way (template0: the image installs its newest version in template1).
    extensions="$(val "$TS_DB" "select string_agg(format('create extension %I version %L;', extname, extversion), ' '
                                order by extname = 'timescaledb' desc)
                                from pg_extension where extname <> 'plpgsql'")"
    step "Creating $TS_NEW: $extensions"
    q postgres -c "create database \"$TS_NEW\" template template0"
    q "$TS_NEW" -c "$extensions"
    val "$TS_NEW" "select extname || ' ' || extversion from pg_extension order by 1" | sed 's/^/  /' >&2
}

phase_build() {
    db_exists "$TS_NEW" || fail "$TS_NEW does not exist, run create first"
    [ -t 0 ] && fail "build reads the home-data-collector source as a tar on stdin, see the usage"
    local password="${TS_PASSWORD:-}"
    [ -n "$password" ] || password="$(docker exec "$TS_CONTAINER" cat /run/secrets/timescale_superuser_password)"
    step "alembic upgrade head into $TS_NEW ($PY_IMAGE, network of $TS_CONTAINER)"
    # The password goes in through an env file (a pipe), never on a command line.
    docker run --rm -i --network "container:$TS_CONTAINER" --env-file <(printf 'DB_PASS=%s\n' "$password") \
        -e DB_USER="$PGUSER" -e DB_HOST=localhost -e DB_NAME="$TS_NEW" "$PY_IMAGE" bash -c '
            set -euo pipefail
            mkdir /work && cd /work
            tar -xf -
            pip install --quiet --root-user-action=ignore poetry
            poetry config virtualenvs.in-project true
            poetry install --no-interaction --quiet --no-root --only main
            PYTHONPATH=src:. .venv/bin/alembic upgrade head
            PYTHONPATH=src:. .venv/bin/alembic current
        ' 2>&1 | grep -E "Running upgrade|^[0-9a-f]{12}|Error|error" | sed 's/^/  /' >&2
    [ -n "$(val "$TS_NEW" "select version_num from alembic_version")" ] || fail "alembic did not finish"
}

phase_copy() {
    local table cols all
    all="$(tables | sed 's/.*/public."&"/' | paste -sd, -)"
    step "Emptying the tables of $TS_NEW (rows from the migrations are replaced by the old data)"
    q "$TS_NEW" -c "truncate $all restart identity cascade"
    for table in $(tables); do
        if [ -z "$(val "$TS_DB" "select to_regclass('public.$table')")" ]; then
            echo "  $table: not in $TS_DB, left empty" >&2
            continue
        fi
        cols="$(columns "$table")"
        # Foreign keys are not checked while copying (session_replication_role),
        # so the order does not matter; verify checks them afterwards.
        q "$TS_DB" -c "\\copy (select $cols from public.\"$table\") to stdout" </dev/null |
            q "$TS_NEW" -c "set session_replication_role = replica" -c "\\copy public.\"$table\" ($cols) from stdin" ||
            fail "copying $table failed"
        printf '  %-45s %s rows\n' "$table" "$(val "$TS_NEW" "select count(*) from public.\"$table\"")" >&2
    done
    step "Setting the sequences to the copied ids"
    val "$TS_NEW" "select format('select setval(%L, coalesce((select max(%I) from %s), 0) + 1, false);',
                                 s.oid::regclass, a.attname, t.oid::regclass)
                   from pg_class s join pg_depend d on d.objid = s.oid and d.deptype in ('a', 'i')
                   join pg_class t on t.oid = d.refobjid join pg_attribute a on a.attrelid = t.oid and a.attnum = d.refobjsubid
                   join pg_namespace n on n.oid = t.relnamespace
                   where s.relkind = 'S' and n.nspname = 'public'" | q "$TS_NEW" -tA >/dev/null
}

phase_refresh() {
    local view i
    # The jobs refresh the same views (e.g. refresh_stats_data_smartmeter_energy_
    # with_pricing) and would deadlock with the refreshes below: pause them.
    step "Pausing the background jobs of $TS_NEW"
    val "$TS_NEW" "select count(*) from timescaledb_information.jobs j, lateral alter_job(j.job_id, scheduled => false) where j.job_id >= 1000" |
        sed 's/^/  paused: /' >&2
    for i in $(seq 1 60); do
        [ "$(val "$TS_NEW" "select count(*) from timescaledb_information.job_stats where job_status = 'Running'")" = 0 ] && break
        [ "$i" = 60 ] && fail "jobs still running after 5 minutes"
        sleep 5
    done
    step "Refreshing the continuous aggregates (in creation order, so aggregates on aggregates come last)"
    for view in $(val "$TS_NEW" "select format('%I.%I', user_view_schema, user_view_name)
                                 from _timescaledb_catalog.continuous_agg order by mat_hypertable_id"); do
        q "$TS_NEW" -c "call refresh_continuous_aggregate('$view', null, null)"
        echo "  $view" >&2
    done
    step "Refreshing the materialized views"
    for view in $(val "$TS_NEW" "select format('%I.%I', n.nspname, c.relname) from pg_class c
                                 join pg_namespace n on n.oid = c.relnamespace
                                 where c.relkind = 'm' and n.nspname = 'public' order by c.oid"); do
        q "$TS_NEW" -c "refresh materialized view $view"
        echo "  $view" >&2
    done
    step "Resuming the background jobs"
    val "$TS_NEW" "select count(*) from timescaledb_information.jobs j, lateral alter_job(j.job_id, scheduled => true) where j.job_id >= 1000" |
        sed 's/^/  resumed: /' >&2
}

phase_verify() {
    local table old new failed=0 fk orphans
    step "Row counts, $TS_DB -> $TS_NEW"
    for table in $(tables); do
        new="$(val "$TS_NEW" "select count(*) from public.\"$table\"")"
        old=""
        if [ -n "$(val "$TS_DB" "select to_regclass('public.$table')")" ]; then
            old="$(val "$TS_DB" "select count(*) from public.\"$table\"")"
        fi
        if [ "$old" = "$new" ]; then
            printf '  ok    %-45s %s\n' "$table" "$new" >&2
        else
            printf '  DIFF  %-45s %s -> %s\n' "$table" "${old:-missing}" "$new" >&2
            failed=1
        fi
    done
    step "Foreign keys (not checked during the copy)"
    while IFS='|' read -r fk orphans; do
        [ -n "$fk" ] || continue
        if [ "$orphans" = 0 ]; then
            echo "  ok    $fk" >&2
        else
            echo "  FAIL  $fk: $orphans rows without a parent" >&2
            failed=1
        fi
    done < <(val "$TS_NEW" "select format('select %L || ''|'' || count(*) from %s c where %I is not null and not exists (select from %s p where p.%I = c.%I);',
                                         con.conrelid::regclass || '.' || con.conname, con.conrelid::regclass, a.attname, con.confrelid::regclass, fa.attname, a.attname)
                            from pg_constraint con
                            join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
                            join pg_attribute fa on fa.attrelid = con.confrelid and fa.attnum = con.confkey[1]
                            where con.contype = 'f' and array_length(con.conkey, 1) = 1
                            and con.connamespace = 'public'::regnamespace" | q "$TS_NEW" -tA)
    step "Timescale catalog of $TS_NEW"
    val "$TS_NEW" "select (select count(*) from timescaledb_information.hypertables) || ' hypertables, '
                       || (select count(*) from timescaledb_information.continuous_aggregates) || ' continuous aggregates, '
                       || (select count(*) from timescaledb_information.jobs) || ' jobs, '
                       || (select count(*) from pg_matviews where schemaname = 'public' and not ispopulated) || ' unpopulated matviews'" |
        sed 's/^/  /' >&2
    [ "$failed" = 0 ] || fail "verify found differences"
    echo "  OK" >&2
}

phase_swap() {
    local broken
    broken="${TS_DB}_broken_$(date +%Y%m%d_%H%M)"
    db_exists "$TS_NEW" || fail "$TS_NEW does not exist"
    db_exists "$broken" && fail "$broken exists already"
    step "Renaming $TS_DB -> $broken and $TS_NEW -> $TS_DB"
    # No new connections (Grafana reconnects at once), end the open ones, rename.
    q postgres -tA -c "alter database \"$TS_DB\" allow_connections false" \
               -c "alter database \"$TS_NEW\" allow_connections false" \
               -c "select 'closed ' || count(pg_terminate_backend(pid)) || ' connections' from pg_stat_activity where datname in ('$TS_DB', '$TS_NEW')" \
               -c "alter database \"$TS_DB\" rename to \"$broken\"" \
               -c "alter database \"$TS_NEW\" rename to \"$TS_DB\"" \
               -c "alter database \"$TS_DB\" allow_connections true" 2>&1 |
        grep -v "manually restart any running background workers" | sed 's/^/  /' >&2
    # The background jobs of the rebuilt database (refresh policies) start
    # with its scheduler; restart the workers for it after the rename.
    val "$TS_DB" "select _timescaledb_functions.start_background_workers()" >/dev/null
    echo "  $TS_DB is now the former $TS_NEW; $broken keeps the previous $TS_DB (connections off)." >&2
}

# The comment block at the top, without the "# ".
usage() {
    sed -n '3,31p' "$0" | cut -c3- >&2
    exit 2
}

case "${1:-}" in
    create | build | copy | refresh | verify | swap)
        PGUSER="$(docker exec "$TS_CONTAINER" printenv POSTGRES_USER)" || fail "container $TS_CONTAINER not found"
        "phase_$1"
        ;;
    *) usage ;;
esac
