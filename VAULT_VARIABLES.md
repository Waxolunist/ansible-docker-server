# Vault Variables Reference

All secrets are stored in Ansible Vault. To edit:

```bash
ansible-vault edit group_vars/web/vault.yml --vault-password-file=.vault_pass
ansible-vault edit group_vars/system/vault.yml --vault-password-file=.vault_pass
```

`.vault_pass` is excluded from version control via `.gitignore` and must be placed manually before running any playbook.

---

## `group_vars/system/vault.yml`

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_ansible_ssh_pass` | `group_vars/system/vars.yml` | — | SSH password for initial root login during `system.yml` setup |
| `vault_devops_pass` | `roles/system/tasks/main.yml` | — | Password for the `devops` OS user |
| `vault_server_ip` | `host_vars/sys1/vars.yml` | — | Public IP address of the IONOS server |

---

## `group_vars/web/vault.yml`

### Infrastructure

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_server_ip` | `host_vars/web1/vars.yml` | — | Public IP address of the IONOS server |
| `vault_acme_email` | `traefik/traefik_yml.j2` | — | Email registered with Let's Encrypt for TLS certificates |

### Container Registry

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_registry_http_secret` | `registry/registry_yml.j2` | — | HMAC secret for registry token signing |

### Authelia (auth gateway)

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_authelia_jwt_secret` | `tasks/authelia.yml` | `authelia_jwt_secret` | JWT signing key for identity tokens |
| `vault_authelia_session_secret` | `tasks/authelia.yml` | `authelia_session_secret` | Session cookie encryption key |
| `vault_authelia_storage_encryption_key` | `tasks/authelia.yml` | `authelia_storage_encryption_key` | Encryption key for the Authelia SQLite database |

### Grafana

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_grafana_pg_user` | `docker-compose_yml.j2`, `grafana_ini.j2`, `backup_databases.j2.sh` | — | PostgreSQL username for Grafana's own database (`grafana-pg` container) |
| `vault_grafana_pg_password` | `tasks/grafana.yml` | `grafana_pg_password` | Password for the Grafana PostgreSQL user |
| `vault_smtp_server_user` | `docker-compose_yml.j2` | — | Gmail address used by Grafana for SMTP (`GF_SMTP_USER`) |
| `vault_smtp_server_password` | `tasks/grafana.yml` | `smtp_password` | Gmail app password for SMTP |

### PgAdmin

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_pgadmin_default_email` | `docker-compose_yml.j2` | — | Admin login email (no `_FILE` variant in pgAdmin) |
| `vault_pgadmin_default_password` | `tasks/pgadmin.yml` | `pgadmin_default_password` | Admin login password for the PgAdmin web UI |

### TimescaleDB

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_timescale_pg_user` | `docker-compose_yml.j2`, `backup_databases.j2.sh`, `timescale/init_roles_sql.j2` | — | Superuser name for TimescaleDB |
| `vault_timescale_pg_password` | `tasks/timescale.yml` | `timescale_superuser_password` | Superuser password for TimescaleDB |
| `vault_timescale_app_rw_password` | `timescale/init_roles_sql.j2` | — | Password for the `app_rw` role (datacollector on the Raspberry Pi) |
| `vault_timescale_grafana_ro_password` | `timescale/init_roles_sql.j2` | — | Password for the `grafana_ro` role (Grafana data source) |

### PhotoPrism

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_photoprism_admin_password` | `docker-compose_yml.j2` | — | PhotoPrism web UI admin password (no `_FILE` support in PhotoPrism) |
| `vault_photoprism_db_password` | `tasks/photoprism.yml`, `docker-compose_yml.j2` | `photoprism_db_password` | MariaDB user password — secret used by MariaDB; PhotoPrism side still uses env var |
| `vault_photoprism_db_root_password` | `tasks/photoprism.yml`, `backup_databases.j2.sh` | `photoprism_db_root_password` | MariaDB root password (used for backups) |
