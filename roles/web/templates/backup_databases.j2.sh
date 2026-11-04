#!/bin/bash

set -o pipefail
umask 077

cd {{ docker_base_path }}

# Create backup directory if it doesn't exist
mkdir -p /backup

# Generate timestamp for backup files
TIMESTAMP=$(date +%d-%m-%Y_%H_%M_%S)

# Track overall backup success for Prometheus textfile collector metric
BACKUP_OK=1
TEXTFILE_DIR="{{ docker.paths.data }}node-exporter"

gzip_has_data() {
    gzip -t "$1" && [ "$(gzip -dc "$1" | head -c 1 | wc -c)" -eq 1 ]
}

check_backup() {
    local label="$1" file="$2" dump_status="$3"
    shift 3
    if [ "${dump_status}" -eq 0 ] && [ -s "${file}" ] && "$@" "${file}" > /dev/null; then
        echo "${label} backup successful: $(ls -lh "${file}")"
    else
        echo "ERROR: ${label} backup failed, is empty or is corrupt!"
        rm -f "${file}"
        BACKUP_OK=0
    fi
}

echo "Starting database backups at $(date)"

# Backup Grafana database
echo "Backing up Grafana database..."
GRAFANA_BACKUP="/backup/dump_grafana_${TIMESTAMP}.sql.gz"
docker compose exec -T grafana-pg pg_dump -c -U '{{ vault_grafana_pg_user }}' -d grafana | gzip -9 > "${GRAFANA_BACKUP}"
DUMP_STATUS=$?
check_backup "Grafana" "${GRAFANA_BACKUP}" "${DUMP_STATUS}" gzip_has_data

# Backup TimescaleDB database
echo "Backing up TimescaleDB database..."
TIMESCALE_BACKUP="/backup/dump_timescale_${TIMESTAMP}.sql.gz"
docker compose exec -T timescaledb pg_dump -Fc --no-owner --no-privileges -U '{{ vault_timescale_pg_user }}' -d 'timescale_home' | gzip -9 > "${TIMESCALE_BACKUP}"
DUMP_STATUS=$?
check_backup "TimescaleDB" "${TIMESCALE_BACKUP}" "${DUMP_STATUS}" gzip_has_data

# Backup PhotoPrism MariaDB database
echo "Backing up PhotoPrism MariaDB database..."
PHOTOPRISM_BACKUP="/backup/dump_photoprism_${TIMESTAMP}.sql.gz"
docker compose exec -T photoprism-mariadb sh -c 'MYSQL_PWD="$(cat /run/secrets/photoprism_db_root_password)" exec mariadb-dump -u root --single-transaction --routines --triggers photoprism' | gzip -9 > "${PHOTOPRISM_BACKUP}"
DUMP_STATUS=$?
check_backup "PhotoPrism" "${PHOTOPRISM_BACKUP}" "${DUMP_STATUS}" gzip_has_data

# Backup Otterwiki (git repository with pages and attachments, plus the
# SQLite database holding drafts and admin preferences). Archived from
# inside the container, where the files are readable regardless of owner.
echo "Backing up Otterwiki..."
OTTERWIKI_BACKUP="/backup/dump_otterwiki_${TIMESTAMP}.tar.gz"
docker compose exec -T otterwiki tar -C /app-data -czf - repository db.sqlite > "${OTTERWIKI_BACKUP}"
DUMP_STATUS=$?
check_backup "Otterwiki" "${OTTERWIKI_BACKUP}" "${DUMP_STATUS}" tar tzf

# Backup the Authelia users database. Users set their own passwords, so it
# exists nowhere else. Read from inside the container, like Otterwiki.
echo "Backing up Authelia users..."
AUTHELIA_USERS_BACKUP="/backup/authelia_users_${TIMESTAMP}.yml"
docker compose exec -T authelia cat /users/users_database.yml > "${AUTHELIA_USERS_BACKUP}"
DUMP_STATUS=$?
check_backup "Authelia users" "${AUTHELIA_USERS_BACKUP}" "${DUMP_STATUS}" test -s

echo "Database backups completed at $(date)"

# Clean up old backups (keep last 20 per database)
echo "Cleaning up old backups..."
ls -t /backup/dump_grafana_*.sql.gz 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -t /backup/dump_timescale_*.sql.gz 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -t /backup/dump_photoprism_*.sql.gz 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -t /backup/dump_otterwiki_*.tar.gz 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -t /backup/authelia_users_*.yml 2>/dev/null | tail -n +21 | xargs -r rm -f

echo "Backup cleanup completed"

# Emit Prometheus textfile metric on full success (atomic write via rename).
if [ "${BACKUP_OK}" = "1" ] && [ -d "${TEXTFILE_DIR}" ]; then
    TMP_METRIC="$(mktemp "${TEXTFILE_DIR}/backup.prom.XXXXXX")"
    {
        echo "# HELP backup_last_success_timestamp_seconds Unix timestamp of the last fully successful database backup run."
        echo "# TYPE backup_last_success_timestamp_seconds gauge"
        echo "backup_last_success_timestamp_seconds $(date +%s)"
    } > "${TMP_METRIC}"
    chmod 0644 "${TMP_METRIC}"
    mv -f "${TMP_METRIC}" "${TEXTFILE_DIR}/backup.prom"
    echo "Wrote backup success metric to ${TEXTFILE_DIR}/backup.prom"
else
    echo "Skipping metric write (BACKUP_OK=${BACKUP_OK}, dir exists: $([ -d "${TEXTFILE_DIR}" ] && echo yes || echo no))"
fi