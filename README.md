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

    ansible-playbook site.yml --vault-password-file .vault_pass

You can pass following environment variables via the -e command line option, like 

    ansible-playbook site.yml --ask-vault-pass -e "restart_container=yes"

Following extra parameters are available:

* `restart_container=yes` | default "no"

Deploy only parts
-----------------

Without `--tags`, the playbook deploys everything, as above. To run just one part, pass its tag:

    ansible-playbook web.yml --tags grafana_dashboards

| Tag | Deploys |
|---|---|
| `grafana_dashboards` | The dashboards in `roles/web/files/grafana/provisioning/dashboards/` and their provider |

Grafana rescans its dashboards directory every 30 seconds, so changes show up without a restart. Only a change to the provider restarts Grafana.

### Adding a Grafana dashboard

A subdirectory is the Grafana folder of the same title, for example `Homeassistant/`. Files at the top level go to General. No task needs to change.

1. In Grafana, open the dashboard's Export dialog.
2. For v2 dashboards (dynamic dashboards), set Model to **V2 Resource** and Format to **JSON**. Keep `apiVersion`, `kind`, `metadata.name` and `spec`, and remove the rest of `metadata` and `status`.
3. Save it as `<folder>/<name>.json`, then run `ansible-playbook web.yml --tags grafana_dashboards`.

`metadata.name` is the dashboard uid. Keeping it makes Grafana take over the existing dashboard instead of creating a copy.

This repository is public. Replace internal hostnames or other private values in a dashboard with a placeholder such as `@@PSA_URL@@`, put the value in the vault, and add a matching `replace` to the "Grafana - Write dashboards" task in `roles/web/tasks/grafana_dashboards.yml`. The files are not Jinja templates, because Grafana JSON is full of `{{ }}`.

Motivation
==========

The motivation for the separation of system and site is that system is run with the user root, whereas the site.yml playbook is run with a devops user. The system playbook disables the root login via ssh for security reasons.

Upgrade Timescale
-----------------

The image tag in `roles/web/templates/docker-compose_yml.j2` is pinned to an exact
PostgreSQL minor and TimescaleDB version (`pg16.15-ts2.31.0`), so an upgrade is a
deliberate tag change. Pick the newest `pg<major>.<minor>-ts<version>` tag on Docker Hub
and read the TimescaleDB changelog from the running version to the target first.

1. Take a full backup with `backup_databases.sh`. An extension update can't be undone in
   place; rollback is a restore.
2. Render the new compose file and recreate only the database container:

       docker compose up -d --no-deps timescaledb

3. Update the extensions in every database that has them (`timescale_home` and
   `postgres`). `-X` skips `~/.psqlrc`, so `ALTER EXTENSION timescaledb UPDATE` is the
   first command of the session, as TimescaleDB requires:

       docker compose exec timescaledb psql -X -U timescale -d timescale_home

       ALTER EXTENSION timescaledb UPDATE;
       ALTER EXTENSION timescaledb_toolkit UPDATE;
       CREATE SCHEMA IF NOT EXISTS timescaledb_experimental;
       SELECT extname, extversion FROM pg_extension;
       \q

   Repeat with `-d postgres`.

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
