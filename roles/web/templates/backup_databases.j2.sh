#!/bin/bash

cd {{ docker_base_path }}

# Create backup directory if it doesn't exist
mkdir -p /backup

# Generate timestamp for backup files
TIMESTAMP=$(date +%d-%m-%Y_%H_%M_%S)

echo "Starting database backups at $(date)"

# Backup Grafana database
echo "Backing up Grafana database..."
GRAFANA_BACKUP="/backup/dump_grafana_${TIMESTAMP}.sql.gz"
docker compose exec -T grafana-pg pg_dump -c -U '{{ vault_grafana_pg_user }}' -d grafana | gzip -9 > "${GRAFANA_BACKUP}"

# Check if Grafana backup was successful
if [ -s "${GRAFANA_BACKUP}" ]; then
    echo "Grafana backup successful: $(ls -lh "${GRAFANA_BACKUP}")"
else
    echo "ERROR: Grafana backup failed or is empty!"
    rm -f "${GRAFANA_BACKUP}"
fi

# Backup TimescaleDB database
echo "Backing up TimescaleDB database..."
TIMESCALE_BACKUP="/backup/dump_timescale_${TIMESTAMP}.sql.gz"
docker compose exec -T timescaledb pg_dump -c -U '{{ vault_timescale_pg_user }}' -d 'timescale_home' | gzip -9 > "${TIMESCALE_BACKUP}"

# Check if TimescaleDB backup was successful
if [ -s "${TIMESCALE_BACKUP}" ]; then
    echo "TimescaleDB backup successful: $(ls -lh "${TIMESCALE_BACKUP}")"
else
    echo "ERROR: TimescaleDB backup failed or is empty!"
    rm -f "${TIMESCALE_BACKUP}"
fi

# Backup PhotoPrism MariaDB database
echo "Backing up PhotoPrism MariaDB database..."
PHOTOPRISM_BACKUP="/backup/dump_photoprism_${TIMESTAMP}.sql.gz"
docker compose exec -T photoprism-mariadb mariadb-dump -u root -p'{{ vault_photoprism_db_root_password }}' --single-transaction --routines --triggers photoprism | gzip -9 > "${PHOTOPRISM_BACKUP}"

# Check if PhotoPrism backup was successful
if [ -s "${PHOTOPRISM_BACKUP}" ]; then
    echo "PhotoPrism backup successful: $(ls -lh "${PHOTOPRISM_BACKUP}")"
else
    echo "ERROR: PhotoPrism backup failed or is empty!"
    rm -f "${PHOTOPRISM_BACKUP}"
fi

echo "Database backups completed at $(date)"

# Clean up old backups (keep last 7 days)
echo "Cleaning up old backups..."
find /backup -name "dump_grafana_*.sql.gz" -type f -mtime +7 -delete
find /backup -name "dump_timescale_*.sql.gz" -type f -mtime +7 -delete
find /backup -name "dump_photoprism_*.sql.gz" -type f -mtime +7 -delete

echo "Backup cleanup completed"