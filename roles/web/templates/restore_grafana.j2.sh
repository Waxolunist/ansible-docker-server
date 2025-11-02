#!/bin/bash

cd {{ docker_base_path }}

# Function to display usage
usage() {
    echo "Usage: $0 [backup_file]"
    echo "  backup_file: Optional path to specific backup file"
    echo "  If no file specified, will use the most recent backup"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use latest backup"
    echo "  $0 /backup/dump_grafana_02-11-2025_14_30_45.sql.gz"
    exit 1
}

# Function to find the latest backup
find_latest_backup() {
    LATEST=$(find /backup -name "dump_grafana_*.sql.gz" -size +0c -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2)
    echo "$LATEST"
}

# Parse command line arguments
BACKUP_FILE=""
if [ $# -eq 1 ]; then
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
    fi
    BACKUP_FILE="$1"
elif [ $# -gt 1 ]; then
    echo "ERROR: Too many arguments"
    usage
fi

# Determine which backup to use
if [ -z "$BACKUP_FILE" ]; then
    echo "Finding latest backup..."
    BACKUP_FILE=$(find_latest_backup)
    
    if [ -z "$BACKUP_FILE" ]; then
        echo "ERROR: No valid Grafana backups found in /backup/"
        echo "Available files:"
        ls -la /backup/dump_grafana_* 2>/dev/null || echo "  No backup files found"
        exit 1
    fi
    
    echo "Using latest backup: $BACKUP_FILE"
else
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "ERROR: Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    if [ ! -s "$BACKUP_FILE" ]; then
        echo "ERROR: Backup file is empty: $BACKUP_FILE"
        exit 1
    fi
    
    echo "Using specified backup: $BACKUP_FILE"
fi

# Display backup information
echo "Backup file: $BACKUP_FILE"
echo "Backup size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"
echo "Backup date: $(stat -c %y "$BACKUP_FILE")"
echo ""

# Confirm restoration
read -p "Are you sure you want to restore Grafana database from this backup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restoration cancelled."
    exit 0
fi

echo "Starting Grafana database restoration..."

# Check if containers are running
if ! docker compose ps grafana-pg | grep -q "Up"; then
    echo "ERROR: grafana-pg container is not running"
    echo "Please start the containers first: docker compose up -d"
    exit 1
fi

# Stop Grafana service
echo "Stopping Grafana service..."
docker compose stop grafana

# Wait for graceful shutdown
sleep 3

# Restore the database
echo "Restoring database from backup..."
if zcat "$BACKUP_FILE" | docker compose exec -T grafana-pg psql -U '{{ vault_grafana_pg_user }}' -d grafana; then
    echo "Database restoration successful!"
else
    echo "ERROR: Database restoration failed!"
    echo "Starting Grafana anyway..."
    docker compose start grafana
    exit 1
fi

# Start Grafana service
echo "Starting Grafana service..."
docker compose start grafana

# Wait for Grafana to start
echo "Waiting for Grafana to start..."
sleep 10

# Check if Grafana is running
if docker compose ps grafana | grep -q "Up"; then
    echo "SUCCESS: Grafana restoration completed successfully!"
    echo ""
    echo "You can now:"
    echo "  - Check Grafana logs: docker compose logs grafana"
    echo "  - Access Grafana web interface"
    echo "  - Verify your dashboards and data sources are restored"
else
    echo "WARNING: Grafana may not have started properly"
    echo "Check logs with: docker compose logs grafana"
fi

echo ""
echo "Restoration process completed at $(date)"