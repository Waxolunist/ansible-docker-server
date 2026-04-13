# Security Hardening Plan — IONOS Dedicated Server

## Context

This plan addresses security hardening of the `ansible-docker-server` infrastructure. The audit found **6 critical**, **8 high**, and **7 medium** severity issues. All changes go through Ansible playbooks/templates — no direct SSH modifications.

**Key files to modify:**
- `roles/web/templates/docker-compose_yml.j2` — container definitions
- `roles/web/templates/traefik/traefik_yml.j2` — reverse proxy config
- `roles/web/templates/grafana/grafana_ini.j2` — dashboard auth
- `roles/web/templates/backup_databases.j2.sh` — backup script
- `roles/web/templates/authelia/authelia_yml.j2` — auth gateway
- `roles/system/tasks/main.yml` — SSH and OS hardening
- `roles/web/tasks/main.yml` — cron jobs and deployment tasks

---

## 1. Host-Level Hardening

### 1a. SSH hardening (`roles/system/tasks/main.yml`)
Current state: password auth disabled, root login disabled, key-based auth. Missing several settings.

**Add to sshd_config via lineinfile tasks:**
- `AllowUsers devops` — restrict to known user
- `ClientAliveInterval 300` / `ClientAliveCountMax 2` — drop idle sessions
- `LoginGraceTime 30` — limit pre-auth window
- `X11Forwarding no` — disable unused feature
- `PermitEmptyPasswords no` — explicit deny
- `MaxAuthTries 3` — limit auth attempts per connection

### 1b. Install fail2ban (`roles/system/tasks/main.yml` or new `roles/system/tasks/fail2ban.yml`)
- Install `fail2ban` package
- Configure jail for `sshd` (ban after 3 failures, 1-hour ban)
- Template a Traefik access-log jail if Traefik access logs are enabled later

### 1c. Automated security updates
- Install `unattended-upgrades` and configure for security-only updates
- Template `/etc/apt/apt.conf.d/50unattended-upgrades`

### 1d. Firewall — IONOS Cloud Panel (manual)
- **CRITICAL:** Restrict port 5432 to the Raspberry Pi's public IP only (currently open to 0.0.0.0/0)
- Document allowed source IPs for each exposed port in a `FIREWALL.md`

### 1e. Vault password rotation
- Rotate vault password, store new `.vault_pass` **outside** the repo (e.g., `~/.ansible/vault_pass`) and reference via `ansible.cfg` `vault_password_file`
- Verify `.vault_pass` remains in `.gitignore`

---

## 2. Docker Daemon & Shared Infrastructure

### 2a. Docker daemon (`roles/docker/templates/daemon_json.j2`)
- Add `"live-restore": true` — keep containers running during daemon restart
- Add `"no-new-privileges": true` — default deny privilege escalation
- Add `"userland-proxy": false` — use iptables directly (performance + security)

### 2b. Docker socket proxy (already good)
- Socket mounted `:ro`, POST disabled, only CONTAINERS/NETWORKS/EVENTS allowed
- **No changes needed** — this is well configured

---

## 3. Per-Container Hardening

### 3a. Traefik (reverse-proxy)

**File:** `roles/web/templates/traefik/traefik_yml.j2`

| Issue | Fix |
|---|---|
| `api.insecure: true` | Set `insecure: false`; access dashboard only via Traefik route with Authelia middleware |
| No TLS version pinning | Add `tls.options.default.minVersion: VersionTLS12` and strong cipher suites |
| No security headers | Add a `securityHeaders` middleware with HSTS (max-age 63072000, includeSubDomains), X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy strict-origin-when-cross-origin, Permissions-Policy |
| No rate limiting | Add `rateLimit` middleware (average: 100, burst: 200) — apply globally or per-service |

**File:** `roles/web/templates/docker-compose_yml.j2` (Traefik labels)
- Chain `securityHeaders` + `rateLimit` + `authelia` middlewares on all routers
- Add `mem_limit: 512M` and `cpus: 1.0`
- Add `read_only: true` with tmpfs for `/tmp`

### 3b. TimescaleDB

| Issue | Fix |
|---|---|
| Port 5432 exposed to host (and internet) | Remove `ports: - "5432:5432"` — access only via `grafana` Docker network. Raspberry Pi connects through a WireGuard/SSH tunnel instead of direct port exposure |
| Credentials in env vars | Move to Docker secrets or `.env` file with mode 0600 mounted as volume |
| No health check | Add `pg_isready` health check like grafana-pg |
| Single superuser for everything | Create separate Ansible-managed roles: `app_rw` (datacollector), `grafana_ro` (Grafana), `admin` (backups) |

- Add `mem_limit: 1G`, `cpus: 2.0`

### 3c. Grafana

**File:** `roles/web/templates/grafana/grafana_ini.j2`

| Issue | Fix |
|---|---|
| `auth.proxy` whitelist empty | Set `whitelist = 172.18.0.0/16` (Docker proxy network CIDR) |
| `auto_assign_org_role = Editor` | Change to `Viewer` — grant Editor explicitly per user |
| SMTP credentials in config | Use env vars `GF_SMTP_USER` / `GF_SMTP_PASSWORD` from Docker secrets |

- Add `mem_limit: 512M`, `cpus: 1.0`

### 3d. Grafana-PG (Postgres for Grafana)

- Already has health check — good
- Add `mem_limit: 256M`, `cpus: 0.5`
- Credentials already vaulted — acceptable

### 3e. Prometheus

| Issue | Fix |
|---|---|
| `user: root` | Remove — Prometheus image runs as `nobody` by default; fix volume ownership instead |
| No resource limits | Add `mem_limit: 1G`, `cpus: 1.0` |
| 100-day retention | Keep, but add Prometheus disk-usage alert |
| Stale `cryptoreport` target | Remove or comment out the `cryptocurrency:6150` scrape job |

- Add `read_only: true` with tmpfs for `/tmp` and named volume for `/prometheus`

### 3f. Node-Exporter

- Already minimal exposure (internal network only)
- Add `mem_limit: 128M`, `cpus: 0.25`
- Add `read_only: true`

### 3g. cAdvisor

| Issue | Fix |
|---|---|
| `privileged: true` | Replace with explicit capabilities: `--cap-add SYS_PTRACE`, `--cap-add DAC_READ_SEARCH` and required device mounts |

- Add `mem_limit: 256M`, `cpus: 0.5`
- Add `read_only: true` with tmpfs for `/tmp`

### 3h. Authelia

**File:** `roles/web/templates/authelia/authelia_yml.j2`

| Issue | Fix |
|---|---|
| `christian.sterzl` uses SHA-512 | Regenerate password hash with Argon2id (`authelia crypto hash generate argon2`) |
| User database in plaintext template | Move to vaulted template or generate at deploy time from vault vars |

- Add `mem_limit: 256M`, `cpus: 0.5`
- Add `read_only: true` with tmpfs for `/tmp`

### 3i. Registry

- Already behind Authelia — good
- Add `mem_limit: 256M`, `cpus: 0.5`

### 3j. PgAdmin

- Already behind Authelia — good
- Add `mem_limit: 512M`, `cpus: 0.5`
- Consider: is PgAdmin needed in production? If only used occasionally, keep it stopped by default

### 3k. PhotoPrism + MariaDB

| Issue | Fix |
|---|---|
| `security_opt: seccomp:unconfined, apparmor:unconfined` on both containers | Create a custom seccomp profile for PhotoPrism (allow TensorFlow syscalls) instead of disabling entirely. For MariaDB, remove `seccomp:unconfined` — it shouldn't need it |
| `photoprism:latest` tag | Pin to specific version (e.g., `photoprism/photoprism:231128`) |

- Add `mem_limit: 2G` (PhotoPrism), `mem_limit: 512M` (MariaDB)

### 3l. Minecraft

| Issue | Fix |
|---|---|
| `itzg/minecraft-server:latest` | Pin to specific version |
| Port 25565 open to internet | Acceptable for game server, but consider IP allowlist if player base is known |

- Already has `mem_limit: 2048M` — good

### 3m. Autoheal

| Issue | Fix |
|---|---|
| `willfarrell/autoheal:latest` | Pin to specific version (e.g., `willfarrell/autoheal:1.9.0`) |

- Add `mem_limit: 64M`, `cpus: 0.1`

---

## 4. Backup Hardening

**File:** `roles/web/templates/backup_databases.j2.sh`

| Issue | Fix |
|---|---|
| Credentials templated into script | Use `.pgpass` file (mode 0600) for PostgreSQL; use `--defaults-file` for MariaDB |
| Backups unencrypted | Pipe through `gpg --symmetric --batch --passphrase-file /var/docker/.backup_key` |
| No offsite copy | Add `rclone sync /backup remote:backups/` step (configure rclone for B2/S3) |
| No integrity check | Add `gzip -t` before cleanup |
| No logging | Redirect output to `/var/docker/logs/backup.log` with timestamps |
| Script mode 0755 | Change to `0700` — only owner needs execute |

**File:** `roles/web/tasks/main.yml` (cron)
- Add `MAILTO=` or pipe to logger for failure alerts

---

## 5. Logging & Monitoring

### 5a. Cron job logging
- Redirect `start.sh` and `backup_databases.sh` output to `/var/docker/logs/`
- Add logrotate config for `/var/docker/logs/*.log`

### 5b. Traefik access logs
- Enable `accessLog` in `traefik_yml.j2` writing to a file (for fail2ban and audit)

### 5c. Prometheus alerts (new file: `roles/web/templates/prometheus/alerts_yml.j2`)
- Certificate expiry < 14 days
- Container restart count > 3 in 15 minutes
- Disk usage > 85%
- Backup file age > 36 hours

---

## Implementation Order

**Phase 1 — Critical (do first):**
1. Restrict port 5432 via IONOS firewall (manual)
2. Fix Grafana proxy auth whitelist
3. Set Traefik `api.insecure: false`
4. Rotate vault password, move `.vault_pass` out of repo
5. Add fail2ban

**Phase 2 — High priority:**
6. Add security headers middleware to Traefik
7. Add rate limiting middleware
8. Pin all `latest` image tags
9. Remove `user: root` from Prometheus
10. Replace cAdvisor `privileged: true` with capabilities
11. Encrypt backups + move credentials to `.pgpass`
12. Add resource limits to all containers
13. SSH hardening additions

**Phase 3 — Medium priority:**
14. Remove PhotoPrism seccomp/apparmor disable (custom profile)
15. Migrate Authelia user to Argon2id
16. Enable Traefik access logs
17. Add Prometheus alerting rules
18. Set up offsite backups
19. Install unattended-upgrades
20. Add logrotate configuration

---

## Verification

After each phase, run:
```bash
# Deploy changes
ansible-playbook site.yml

# Verify containers are healthy
ssh devops@<server> "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Test Traefik headers
curl -I https://graph.v-collaborate.com  # check HSTS, X-Frame-Options, etc.

# Test rate limiting
ab -n 200 -c 10 https://graph.v-collaborate.com/  # should see 429s

# Test port 5432 is restricted
nmap -p 5432 <server-ip>  # should show filtered from non-allowed IPs

# Test Grafana auth bypass
curl -H "Remote-User: admin" http://<grafana-internal-ip>:3000/api/org  # should fail

# Verify backups are encrypted
file /backup/dump_*.sql.gz.gpg  # should show GPG encrypted

# Check fail2ban is active
ssh devops@<server> "sudo fail2ban-client status sshd"
```