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
| `vault_authelia_jwt_secret` | `tasks/authelia.yml` | `authelia_jwt_secret` | JWT signing key for password reset identity verification (`identity_validation.reset_password.jwt_secret`) |
| `vault_authelia_session_secret` | `tasks/authelia.yml` | `authelia_session_secret` | Session cookie encryption key |
| `vault_authelia_storage_encryption_key` | `tasks/authelia.yml` | `authelia_storage_encryption_key` | Encryption key for the Authelia SQLite database |

### Grafana

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_grafana_pg_user` | `docker-compose_yml.j2`, `grafana_ini.j2`, `backup_databases.j2.sh` | — | PostgreSQL username for Grafana's own database (`grafana-pg` container) |
| `vault_grafana_pg_password` | `tasks/grafana.yml` | `grafana_pg_password` | Password for the Grafana PostgreSQL user |
| `vault_smtp_server_user` | `docker-compose_yml.j2`, `authelia/authelia_yml.j2` | — | Gmail address used for SMTP by Grafana (`GF_SMTP_USER`) and Authelia (`notifier.smtp.username`, also the sender) |
| `vault_smtp_server_password` | `tasks/grafana.yml` | `smtp_password` | Gmail app password for SMTP, shared by Grafana and Authelia (`AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE`) |
| `vault_psa_url` | `tasks/grafana_dashboards.yml` | — | Base URL of the PSA car controller, without a trailing slash. Fills `@@PSA_URL@@` in the Homeassistant `vehicle_control.json` dashboard (preconditioning buttons). Kept out of the public repository. |
| `vault_psa_vin` | `tasks/grafana_dashboards.yml` | — | VIN of the car (17 characters). Fills `@@PSA_VIN@@` in the preconditioning button URLs of `vehicle_control.json`. Kept out of the public repository. |
| `vault_goe_url` | `tasks/grafana_dashboards.yml`, `grafana/provisioning/datasources/goe.yml.j2` | — | Base URL of the go-e charger behind Traefik on the Pi, without a trailing slash. Fills `@@GOE_URL@@` in `vehicle_control.json` (start/stop charging buttons, live status) and is the only allowed host of the `go-e` Infinity datasource. Kept out of the public repository. |
| `vault_goe_proxy_username` | `grafana/provisioning/datasources/goe.yml.j2` | — | Basic auth user of the go-e Traefik route. Same value as `vault_collector.goe_proxy_username` in the raspberry vault. |
| `vault_goe_proxy_password` | `grafana/provisioning/datasources/goe.yml.j2` | — | Basic auth password of the go-e Traefik route, stored in the `go-e` datasource's `secureJsonData`. Same value as `vault_collector.goe_proxy_password` in the raspberry vault; change both together. |
| `vault_grafana_dashboard_sync_token` | `scripts/grafana_dashboards.py` | — | Token of the Grafana service account `dashboard-sync` (role Viewer), created in the UI under Administration → Service accounts. Used only by the script, which pulls dashboards into the repository over SSH; not deployed. |

### TimescaleDB

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_timescale_pg_user` | `docker-compose_yml.j2`, `backup_databases.j2.sh`, `timescale/init_roles_sql.j2` | — | Superuser name for TimescaleDB |
| `vault_timescale_pg_password` | `tasks/timescale.yml` | `timescale_superuser_password` | Superuser password for TimescaleDB |
| `vault_timescale_app_rw_password` | `timescale/init_roles_sql.j2` | — | Password for the `app_rw` role (datacollector on the Raspberry Pi) |
| `vault_timescale_grafana_ro_password` | `timescale/init_roles_sql.j2`, `tasks/postgres_exporter.yml` | `timescale_grafana_ro_password` | Password for the `grafana_ro` role — used by Grafana as a data source and by `postgres-exporter` to read `pg_stat_activity` |
| `vault_timescale_sql_exporter_password` | `timescale/sql_exporter_role_sql.j2`, `sql_exporter/sql_exporter_yml.j2` | — | Password for the read-only `sql_exporter` role, used by `sql-exporter` to read the newest row of each watched `data_*` table. Generate with `openssl rand -hex 24` |

### PhotoPrism

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_photoprism_admin_password` | `docker-compose_yml.j2` | — | PhotoPrism web UI admin password (no `_FILE` support in PhotoPrism) |
| `vault_photoprism_db_password` | `tasks/photoprism.yml`, `docker-compose_yml.j2` | `photoprism_db_password` | MariaDB user password — secret used by MariaDB; PhotoPrism side still uses env var |
| `vault_photoprism_db_root_password` | `tasks/photoprism.yml`, `backup_databases.j2.sh` | `photoprism_db_root_password` | MariaDB root password (used for backups) |

### Alerting (Alertmanager → Matrix)

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_matrix_alerts_user` | `matrix_receiver/config_yml.j2` | — | Matrix ID of the bot that posts the alerts, e.g. `@alerts:<conduit domain>` |
| `vault_matrix_alerts_token` | `matrix_receiver/config_yml.j2` | — | Access token of that bot, from its login on Conduit |
| `vault_matrix_alerts_receiver_password` | `matrix_receiver/config_yml.j2`, `tasks/matrix_receiver.yml` | `matrix_receiver_password` | Basic auth password Alertmanager uses for the bridge (user `alertmanager`). Generate with `openssl rand -hex 24` |
| `vault_matrix_room_infra`, `vault_matrix_room_data`, `vault_matrix_room_energy`, `vault_matrix_room_car`, `vault_matrix_room_security` | `matrix_receiver/config_yml.j2` | — | Room ID of each area's alert room (`!` plus a hash in room version 12, Conduit's default), quoted in the vault because YAML reads a leading `!` as a tag. Areas may share a room. Setup: home_docs how-to "Set up the Matrix bot and the alert rooms" |
| `vault_matrix_alerts_mention_users` | `matrix_receiver/config_yml.j2` | — | Optional list of Matrix IDs mentioned in every critical message, so their phones ring. Defaults to none |
| `vault_psa_url` | `prometheus/alerts_yml.j2` | — | Also linked in the `PsaLoginLost` description as the controller's config page |

### PicoClaw (AI assistant)

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_picoclaw_crypto_passphrase` | `picoclaw/config_json.j2` | — | Passphrase for Matrix E2E encryption key storage |

### Code-Server

No vault variables required. code-server's own authentication is disabled (`auth: none` in `configs/code-server/config.yaml`); authentication is handled entirely by Authelia forward auth at the Traefik layer.


### coturn (STUN/TURN)

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_coturn_password` | `coturn/turnserver_conf.j2` | — | Long-term TURN credential for the `hhfh` user, handed to game clients alongside `turn:turn.v-collaborate.com`. Generate with `openssl rand -base64 32` |

### WireGuard

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_wireguard_private_key` | `wireguard/templates/wg_conf.j2` | — | The VPS's WireGuard private key (`/etc/wireguard/wg0.conf`). Generate with `wg genkey`; its public key goes into the raspberry vault as `vault_wireguard_server_public_key` |
| `vault_wireguard_pi_public_key` | `group_vars/web/vars.yml` | — | The Pi's public key (peer `10.8.0.2`); the private key is in the raspberry vault |

### Otterwiki

| Variable | Used in | Docker secret | Description |
|---|---|---|---|
| `vault_otterwiki_secret_key` | `otterwiki/settings_cfg.j2` | — | Flask session and CSRF signing key (Otterwiki reads no `_FILE` variant). Generate with `openssl rand -hex 32` |
| `vault_otterwiki_push_private_key` | `otterwiki/settings_cfg.j2` | — | Private half of the read-write deploy key on `github.com/Waxolunist/wiki`, used to push the wiki repository. To replace it: `ssh-keygen -t ed25519 -N "" -f key`, add `key.pub` as a deploy key with write access, and put `key` into the vault as a block scalar (`\|`) |
