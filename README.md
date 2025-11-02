Prerequsits
===========

To use this playbook, ansible must be installed.

First install the community.general collection:

    ansible-galaxy collection install community.general

Preparation
===========

The first time the system initialize playbook should be executed.

    ansible-playbook system.yml --ask-vault-pass

Execute
=======

    ansible-playbook site.yml --ask-vault-pass

You can pass following environment variables via the -e command line option, like 

    ansible-playbook site.yml --ask-vault-pass -e "restart_container=yes"

Following extra parameters are available:

* `restart_container=yes` | default "no"

Motivation
==========

The motivation for the separation of system and site is that system is run with the user root, whereas the site.yml playbook is run with a devops user. The system playbook disables the root login via ssh for security reasons.

Upgrade Timescale
-----------------

After upgrading timescale, probably you have to update the extensions.

Log in in docker:

    docker compose exec timescaledb psql -U timescale -d timescale_home

    ALTER EXTENSION timescaledb UPDATE;
    ALTER EXTENSION timescaledb_toolkit UPDATE;
    SELECT extname, extversion FROM pg_extension;
    CREATE SCHEMA IF NOT EXISTS timescaledb_experimental;
    exit

Restoring backup
================


    cd {{ docker_base_path }}

    # Find the latest backup
    LATEST_BACKUP=$(ls -t /backup/dump_grafana_*.sql.zip | head -1)

    if [ -z "$LATEST_BACKUP" ]; then
        echo "No Grafana backups found in /backup/"
        exit 1
    fi

    echo "Using backup: $LATEST_BACKUP"
    echo "Backup date: $(stat -c %y "$LATEST_BACKUP")"

    # Stop Grafana
    docker compose stop grafana

    # Restore the database
    echo "Restoring database..."
    zcat "$LATEST_BACKUP" | docker compose exec -T grafana-pg psql -U '{{ vault_grafana_pg_user }}' -d grafana

    # Start Grafana
    docker compose start grafana

    echo "Restoration complete!"

TODO
====
- [ ] Container registry
- [ ] Logging