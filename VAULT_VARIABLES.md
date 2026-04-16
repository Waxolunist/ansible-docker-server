# Vault Variables Reference

All secrets are stored in Ansible Vault. To edit:

```bash
ansible-vault edit group_vars/web/vault.yml --vault-password-file=.vault_pass
ansible-vault edit group_vars/system/vault.yml --vault-password-file=.vault_pass
```

`.vault_pass` is excluded from version control via `.gitignore` and must be placed manually before running any playbook.

---

## `group_vars/system/vault.yml`

| Variable | Used in | Description |
|---|---|---|
| `vault_ansible_ssh_pass` | `group_vars/system/vars.yml` | SSH password for initial root login during `system.yml` setup |
| `vault_devops_pass` | `roles/system/tasks/main.yml` | Password for the `devops` OS user |
| `vault_server_ip` | `host_vars/sys1/vars.yml` | Public IP address of the IONOS server |

---

## `group_vars/web/vault.yml`

### Infrastructure

| Variable | Used in | Description |
|---|---|---|
| `vault_server_ip` | `host_vars/web1/vars.yml` | Public IP address of the IONOS server |
| `vault_acme_email` | `roles/web/templates/traefik/traefik_yml.j2` | Email address registered with Let's Encrypt for TLS certificates |

### Container Registry

| Variable | Used in | Description |
|---|---|---|
| `vault_registry_http_secret` | `roles/web/templates/registry/registry_yml.j2` | HMAC secret for registry token signing |
| `vault_registry_username` | — | Registry login username |
| `vault_registry_password` | — | Registry login password |

### Authelia (auth gateway)

| Variable | Used in | Description |
|---|---|---|
| `vault_authelia_session_secret` | `roles/web/templates/authelia/authelia_yml.j2` | Session cookie encryption key |
| `vault_authelia_jwt_secret` | `roles/web/templates/authelia/authelia_yml.j2` | JWT signing key for identity tokens |
| `vault_authelia_storage_encryption_key` | `roles/web/templates/authelia/authelia_yml.j2` | Encryption key for the Authelia SQLite database |

### Grafana

| Variable | Used in | Description |
|---|---|---|
| `vault_grafana_pg_user` | `docker-compose_yml.j2`, `grafana_ini.j2`, `backup_databases.j2.sh` | PostgreSQL username for Grafana's own database (`grafana-pg` container) |
| `vault_grafana_pg_password` | `docker-compose_yml.j2`, `grafana_ini.j2`, `backup_databases.j2.sh` | Password for the Grafana PostgreSQL user |
| `vault_smtp_server_user` | `docker-compose_yml.j2` | Gmail address used by Grafana for alert email (`GF_SMTP_USER`) |
| `vault_smtp_server_password` | `docker-compose_yml.j2` | Gmail app password for SMTP (`GF_SMTP_PASSWORD`) |

### PgAdmin

| Variable | Used in | Description |
|---|---|---|
| `vault_pgadmin_default_email` | `docker-compose_yml.j2` | Admin login email for the PgAdmin web UI |
| `vault_pgadmin_default_password` | `docker-compose_yml.j2` | Admin login password for the PgAdmin web UI |

### TimescaleDB

| Variable | Used in | Description |
|---|---|---|
| `vault_timescale_pg_user` | `docker-compose_yml.j2`, `backup_databases.j2.sh`, `timescale/init_roles_sql.j2` | Superuser name for TimescaleDB |
| `vault_timescale_pg_password` | `roles/web/tasks/timescale.yml` (written as Docker secret) | Superuser password for TimescaleDB |
| `vault_timescale_app_rw_password` | `roles/web/templates/timescale/init_roles_sql.j2` | Password for the `app_rw` role (used by the datacollector on the Raspberry Pi) |
| `vault_timescale_grafana_ro_password` | `roles/web/templates/timescale/init_roles_sql.j2` | Password for the `grafana_ro` role (Grafana data source) |

### PhotoPrism

| Variable | Used in | Description |
|---|---|---|
| `vault_photoprism_admin_password` | `docker-compose_yml.j2` | PhotoPrism web UI admin password |
| `vault_photoprism_db_password` | `docker-compose_yml.j2` | Password for the `photoprism` MariaDB user |
| `vault_photoprism_db_root_password` | `docker-compose_yml.j2`, `backup_databases.j2.sh` | MariaDB root password (used for backups) |

### Azure DevOps (CI/CD)

| Variable | Used in | Description |
|---|---|---|
| `vault_azure_token_resource_vm1` | — | Personal access token for the Azure DevOps agent on the server |
| `vault_azure_url` | — | Azure DevOps organisation URL |
| `vault_azure_projectname` | — | Azure DevOps project name |
| `vault_azure_envname` | — | Azure DevOps environment name |
