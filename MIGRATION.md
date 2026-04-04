# Migration: HostEurope → IONOS

Dieses Dokument beschreibt die vollständige Migration des Ansible-Docker-Servers von HostEurope (Dedicated Server) zu IONOS. Die Anleitung ist in sieben Phasen gegliedert und enthält einen Rollback-Plan, IONOS-spezifische Hinweise sowie eine abschließende Checkliste.

## Inhaltsverzeichnis

- [Übersicht](#übersicht)
- [Voraussetzungen](#voraussetzungen)
- [Debian 13 (Trixie) Kompatibilität](#debian-13-trixie-kompatibilität)
- [Phase 1: Server vorbereiten](#phase-1-server-vorbereiten)
- [Phase 2: Ansible-Konfiguration anpassen](#phase-2-ansible-konfiguration-anpassen)
- [Phase 3: Server provisionieren](#phase-3-server-provisionieren)
- [Phase 4: Daten migrieren](#phase-4-daten-migrieren)
- [Phase 5: DNS umstellen](#phase-5-dns-umstellen)
- [Phase 6: Verifizierung](#phase-6-verifizierung)
- [Phase 7: Alten Server abschalten](#phase-7-alten-server-abschalten)
- [Rollback-Plan](#rollback-plan)
- [IONOS-spezifische Hinweise](#ionos-spezifische-hinweise)
- [Checkliste](#checkliste)

---

## Übersicht

### Was wird migriert?

Der gesamte Ansible-Docker-Server mit **12 containerisierten Diensten** wird von einem HostEurope Dedicated Server (`lvps178-77-98-179.dedicated.hosteurope.de`, IP: `178.77.98.179`) auf einen neuen IONOS Server migriert.

### Warum migrieren?

- **Leistungsupgrade** — Mehr CPU-Kerne (6 statt bisher weniger), mehr RAM und Speicherplatz
- **Modernisierung** — Upgrade auf Debian 13 (Trixie)
- **Zuverlässigkeit** — IONOS bietet eine stabile Infrastruktur mit deutschem Rechenzentrum
- **Verwaltung** — IONOS Cloud Panel für einfache Server- und Firewall-Verwaltung

### Server-Vergleich

| Eigenschaft | Alter Server (HostEurope) | Neuer Server (IONOS) |
|-------------|--------------------------|----------------------|
| **Hoster** | HostEurope | IONOS |
| **Typ** | Dedicated Server | VPS / Dedicated Server |
| **OS** | Debian (älter) | Debian 13 (Trixie) |
| **CPU** | — | 6 Cores |
| **RAM** | — | 8 GB |
| **Disk** | — | 240 GB |
| **IP** | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| **Hostname** | `lvps178-77-98-179.dedicated.hosteurope.de` | — |

### Betroffene Dienste

| # | Dienst | Image | Funktion |
|---|--------|-------|----------|
| 1 | Traefik | `traefik:v2.11` | Reverse Proxy, TLS-Terminierung |
| 2 | Prometheus | `prom/prometheus:v2.50.0` | Metriken-Sammlung |
| 3 | Node Exporter | `prom/node-exporter:v1.7.0` | Host-Metriken |
| 4 | Authelia | `authelia/authelia:4` | SSO / Authentifizierung |
| 5 | Grafana | `grafana/grafana:12.2` | Dashboards & Visualisierung |
| 6 | Grafana-PG | `postgres:13-alpine` | PostgreSQL für Grafana |
| 7 | pgAdmin | `dpage/pgadmin4:8.3` | Datenbank-Verwaltung |
| 8 | Minecraft | `itzg/minecraft-server:latest` | Spielserver |
| 9 | TimescaleDB | `timescale/timescaledb-ha:pg16` | Zeitreihen-Datenbank |
| 10 | Docker Registry | `registry:2` | Container-Registry |
| 11 | PhotoPrism | `photoprism/photoprism:latest` | Fotoverwaltung |
| 12 | PhotoPrism-MariaDB | `mariadb:10.11` | MariaDB für PhotoPrism |

### Betroffene Domains

- `v-collaborate.com` mit Subdomains: `proxy`, `auth`, `metrics`, `graph`, `pgadmin`, `registry`, `photos`, `me`
- `christian.sterzl.info`

### Datenverzeichnisse

| Verzeichnis | Inhalt |
|-------------|--------|
| `/var/docker/` | Basis-Verzeichnis für alle Docker-Daten (configs, data, work, logs, images) |
| `/backup/` | Tägliche Datenbank-Backups (Cron um 23:00 Uhr) |

### Exponierte Ports

| Port | Dienst | Protokoll |
|------|--------|-----------|
| 80 | Traefik | HTTP → HTTPS Redirect |
| 443 | Traefik | HTTPS |
| 5432 | TimescaleDB | PostgreSQL |
| 25565 | Minecraft | Minecraft Server |

---

## Voraussetzungen

Bevor mit der Migration begonnen wird, müssen folgende Voraussetzungen erfüllt sein:

### Accounts & Zugänge

- [ ] **IONOS Account mit Server** — Server bereits bestellt (VPS oder Dedicated Server)
- [ ] **SSH-Schlüsselpaar** — Das vorhandene RSA-Schlüsselpaar (`~/.ssh/id_rsa` / `~/.ssh/id_rsa.pub`) wird verwendet. Dieses wird von der System-Rolle automatisch auf dem Server für den `devops`-Benutzer hinterlegt (siehe [`roles/system/tasks/main.yml`](roles/system/tasks/main.yml:15)).
  ```bash
  # Prüfen ob der Schlüssel vorhanden ist:
  ls -la ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
  ```
- [ ] **Ansible Vault Passwort** — Zugriff auf das Vault-Passwort für verschlüsselte Variablen
- [ ] **DNS-Provider Zugang** — Verwaltungszugang für `v-collaborate.com` und `christian.sterzl.info`

### Tools (lokal installiert)

- [ ] **Ansible** — Bereits vorhanden (dieses Projekt)
- [ ] **ansible-vault** — Für verschlüsselte Variablen
- [ ] **rsync** — Für Datenmigration

### Zeitplanung

- **Geschätzte Gesamtdauer**: 2–4 Stunden (exkl. DNS-Propagation)
- **Empfohlener Zeitpunkt**: Wochenende oder Abendstunden (minimale Auswirkung)
- **DNS-Propagation**: Bis zu 24–48 Stunden (mit niedrigem TTL deutlich schneller)

---

## Debian 13 (Trixie) Kompatibilität

Die Ansible-Rollen wurden bereits für Debian 13 (Trixie) angepasst. Folgende **6 Änderungen** wurden durchgeführt:

### 1. Docker APT-Repository Codename-Fallback

Da Docker möglicherweise noch kein offizielles Repository für `trixie` bereitstellt, wurde ein automatischer Fallback auf `bookworm` implementiert.

**Datei:** [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml)

```yaml
- name: Check if Docker repo exists for this codename
  uri:
    url: "https://download.docker.com/linux/debian/dists/{{ distribution_codename.stdout }}/Release"
    method: HEAD
    status_code: [200, 404]
  register: docker_repo_check

- name: Set Docker repo codename (fallback to bookworm if not available)
  set_fact:
    docker_repo_codename: "{{ distribution_codename.stdout if docker_repo_check.status == 200 else 'bookworm' }}"
```

### 2. pip durch apt python3-docker ersetzt (PEP 668)

Debian 13 erzwingt PEP 668 (extern verwaltete Python-Umgebungen). Die Installation von Python-Paketen über `pip` ist nicht mehr erlaubt. Stattdessen wird `python3-docker` über apt installiert.

**Datei:** [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml)

```yaml
# Vorher (entfernt):
# - name: Install docker python packages
#   pip:
#     name:
#       - docker
#       - docker-compose

# Nachher:
- name: Install Docker Python SDK via apt
  apt:
    name: python3-docker
    state: present
```

### 3. Python 2 Alternativen entfernt

Python 2 ist unter Debian 13 nicht mehr verfügbar. Die `update-alternatives`-Einträge für Python 2 wurden entfernt.

**Datei:** [`roles/debian/tasks/main.yml`](roles/debian/tasks/main.yml)

### 4. Docker Experimental-Flag entfernt

Das `experimental`-Flag in der Docker-Daemon-Konfiguration ist unter neueren Docker-Versionen nicht mehr nötig und wurde entfernt.

**Datei:** [`roles/docker/templates/daemon_json.j2`](roles/docker/templates/daemon_json.j2)

```json
{
    "metrics-addr": "{{ docker_ip_address }}:9323"
}
```

### 5. aptitude-Installation entfernt

`aptitude` wird unter Debian 13 nicht mehr standardmäßig benötigt und wurde aus der Debian-Rolle entfernt.

**Datei:** [`roles/debian/tasks/main.yml`](roles/debian/tasks/main.yml)

### 6. Debian-Codename auf Trixie gesetzt

**Datei:** [`roles/debian/vars/main.yml`](roles/debian/vars/main.yml)

```yaml
---
  codename: trixie
```

> **Hinweis**: Alle Änderungen sind bereits im Repository eingepflegt. Es sind keine weiteren Anpassungen für Debian 13 erforderlich.

---

## Phase 1: Server vorbereiten

### 1.1 SSH-Zugang testen

Der IONOS Server ist bereits bestellt. SSH-Verbindung mit dem Root-Passwort testen:

```bash
ssh root@<NEUE_IP_ADRESSE>

# Debian-Version prüfen
cat /etc/os-release
# Erwartete Ausgabe: Debian GNU/Linux 13 (trixie)
```

### 1.2 IONOS Firewall konfigurieren

Im **IONOS Cloud Panel** unter **Netzwerk → Firewall** die folgenden Regeln konfigurieren:

| Richtung | Protokoll | Port | Quelle | Beschreibung |
|----------|-----------|------|--------|--------------|
| Eingehend | TCP | 22 | 0.0.0.0/0 | SSH |
| Eingehend | TCP | 80 | 0.0.0.0/0 | HTTP (Traefik) |
| Eingehend | TCP | 443 | 0.0.0.0/0 | HTTPS (Traefik) |
| Eingehend | TCP | 5432 | 0.0.0.0/0 | PostgreSQL / TimescaleDB |
| Eingehend | TCP | 25565 | 0.0.0.0/0 | Minecraft |

> **Tipp**: Port 5432 (TimescaleDB) sollte idealerweise nur für bekannte IP-Adressen freigegeben werden, nicht für `0.0.0.0/0`. Die Quell-IP entsprechend einschränken.

### 1.3 SSH-Key hinterlegen (optional)

Der SSH-Key wird automatisch durch das System-Playbook (Phase 3) für den `devops`-Benutzer hinterlegt. Falls gewünscht, kann der RSA-Key vorab auch für `root` hinterlegt werden, um die Passwort-Eingabe beim ersten Playbook-Lauf zu vermeiden:

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<NEUE_IP_ADRESSE>
```

> **Hinweis**: Das System-Playbook verbindet sich initial als `root` mit dem Vault-Passwort (`vault_ansible_ssh_pass`). Der RSA-Key (`~/.ssh/id_rsa.pub`) wird dann automatisch für den `devops`-Benutzer deployt.

---

## Phase 2: Ansible-Konfiguration anpassen

Es müssen **zwei Dateien** angepasst werden. Alle anderen Konfigurationen (Domains, Container, Passwörter, Service-Einstellungen) bleiben unverändert.

> **Hinweis**: [`roles/debian/vars/main.yml`](roles/debian/vars/main.yml) ist bereits auf `trixie` aktualisiert — keine Änderung nötig.

### 2.1 hosts.yml — Server-Adresse aktualisieren

Die neue IP-Adresse des IONOS-Servers eintragen:

**Vorher:**
```yaml
---
  all:
    hosts:
      sys1: 
        ansible_host: lvps178-77-98-179.dedicated.hosteurope.de 
      web1: 
        ansible_host: lvps178-77-98-179.dedicated.hosteurope.de
    children:
      system:
        hosts:
          sys1:
      web:
        hosts:
          web1:
```

**Nachher:**
```yaml
---
  all:
    hosts:
      sys1: 
        ansible_host: <NEUE_IP_ADRESSE>
      web1: 
        ansible_host: <NEUE_IP_ADRESSE>
    children:
      system:
        hosts:
          sys1:
      web:
        hosts:
          web1:
```

> **Hinweis**: `<NEUE_IP_ADRESSE>` durch die tatsächliche IP-Adresse des neuen IONOS-Servers ersetzen.

### 2.2 group_vars/system/vault.yml — Root-Passwort aktualisieren

Das Root-Passwort des neuen IONOS-Servers in der Vault-Datei hinterlegen:

```bash
# Vault-Datei bearbeiten
ansible-vault edit group_vars/system/vault.yml
```

Die Variable `vault_ansible_ssh_pass` auf das Root-Passwort des neuen IONOS-Servers setzen:

```yaml
vault_ansible_ssh_pass: <NEUES_ROOT_PASSWORT>
```

> **Hinweis**: Das Root-Passwort ist bereits vorhanden (bei der IONOS-Bestellung festgelegt oder per E-Mail zugesendet).

### 2.3 Änderungen committen (optional)

```bash
# Änderungen in einem separaten Branch vornehmen
git checkout -b migration/ionos

git add hosts.yml
git commit -m "chore: update hosts.yml for IONOS migration"

# Vault-Änderungen separat (bereits verschlüsselt)
git add group_vars/system/vault.yml
git commit -m "chore: update vault for new IONOS server credentials"
```

---

## Phase 3: Server provisionieren

### 3.1 SSH-Fingerprint akzeptieren

Beim ersten Verbindungsaufbau den SSH-Fingerprint des neuen Servers akzeptieren:

```bash
ssh root@<NEUE_IP_ADRESSE>
# Fingerprint bestätigen mit 'yes'
# Verbindung testen, dann wieder trennen
exit
```

Alternativ den alten Fingerprint entfernen (falls die IP bereits bekannt ist):

```bash
ssh-keygen -R <NEUE_IP_ADRESSE>
```

### 3.2 System-Playbook ausführen

Das System-Playbook erstellt den `devops`-Benutzer, konfiguriert SSH-Hardening und sperrt den Root-Zugang:

```bash
ansible-playbook system.yml --ask-vault-pass
```

**Erwartete Aktionen:**
- Benutzer `devops` wird erstellt
- SSH-Key wird für `devops` hinterlegt
- Passwordless Sudo wird konfiguriert
- SSH-Passwort-Authentifizierung wird deaktiviert
- Root-Login wird deaktiviert

> **Achtung**: Nach diesem Schritt ist der Root-Login per SSH nicht mehr möglich! Stelle sicher, dass der SSH-Key für den `devops`-Benutzer korrekt funktioniert.

### 3.3 Site-Playbook ausführen

Das Site-Playbook installiert Docker, erstellt die Verzeichnisstruktur und deployt alle 12 Container:

```bash
ansible-playbook site.yml --ask-vault-pass
```

**Erwartete Aktionen:**
- Debian-Grundkonfiguration (apt update, Tools installieren)
- Docker CE Installation mit allen Plugins (inkl. Trixie→Bookworm Fallback für APT-Repo)
- Python Docker SDK via apt (PEP 668 konform)
- Verzeichnisstruktur unter `/var/docker/` erstellen
- `docker-compose.yml` generieren und deployen
- Alle 12 Container starten
- Cron-Jobs einrichten (Backup, Health-Check)

### 3.4 Verifizierung

```bash
ssh devops@<NEUE_IP_ADRESSE> 'docker ps'
```

**Erwartete Ausgabe** — Alle 12 Container sollten den Status `Up` haben:

```
NAMES                STATUS          PORTS
reverse-proxy        Up X minutes    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
prometheus           Up X minutes
node-exporter        Up X minutes
authelia              Up X minutes
grafana              Up X minutes
grafana-pg           Up X minutes
pgadmin              Up X minutes
minecraft            Up X minutes    0.0.0.0:25565->25565/tcp
timescaledb          Up X minutes    0.0.0.0:5432->5432/tcp
registry             Up X minutes
photoprism           Up X minutes
photoprism-mariadb   Up X minutes
```

> **Hinweis**: Die Container laufen zu diesem Zeitpunkt mit leeren Datenbanken und ohne Daten. Die Datenmigration erfolgt in Phase 4.

---

## Phase 4: Daten migrieren

### 4.1 Container auf dem ALTEN Server stoppen

```bash
ssh devops@178.77.98.179 'cd /var/docker && docker compose down'
```

### 4.2 Finales Backup auf dem alten Server erstellen

```bash
ssh devops@178.77.98.179

# Container kurz starten für Datenbank-Backup
cd /var/docker
docker compose start grafana-pg timescaledb photoprism-mariadb

# Warten bis Container bereit sind
sleep 10

# Backup-Skript ausführen
sudo /var/docker/backup_databases.sh

# Container wieder stoppen
docker compose down

# Backup prüfen
ls -la /backup/
```

### 4.3 Daten per rsync übertragen

`rsync` unterstützt keinen direkten Transfer zwischen zwei Remote-Hosts. Stattdessen per SSH auf den **neuen Server** verbinden und die Daten vom alten Server **pullen**:

#### Voraussetzung: SSH-Agent-Forwarding nutzen

Da auf dem alten Server die Passwort-Authentifizierung deaktiviert ist, kann kein neuer SSH-Key vom neuen Server aus hinterlegt werden. Stattdessen wird **SSH-Agent-Forwarding** verwendet — der lokale SSH-Key wird durch die SSH-Verbindung zum neuen Server weitergeleitet und ermöglicht so den Zugriff auf den alten Server.

```bash
# Sicherstellen, dass der SSH-Agent lokal läuft und der Key geladen ist
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Prüfen ob der Key geladen ist
ssh-add -l
```

#### Daten übertragen

Mit Agent-Forwarding (`-A`) auf den neuen Server verbinden und die Daten vom alten Server pullen:

```bash
# Mit Agent-Forwarding auf den neuen Server verbinden
ssh -A devops@<NEUE_IP_ADRESSE>

# Anwendungsdaten
rsync -avz --progress devops@178.77.98.179:/var/docker/data/ /var/docker/data/

# Arbeitsdaten (Traefik-Zertifikate, Registry-Daten, PhotoPrism-Fotos)
rsync -avz --progress devops@178.77.98.179:/var/docker/work/ /var/docker/work/

# Datenbank-Backups
rsync -avz --progress devops@178.77.98.179:/backup/ /backup/
```

> **Hinweis**: Da die Zielverzeichnisse auf dem neuen Server lokal sind, funktioniert rsync korrekt. Die Daten werden direkt vom alten Server über SSH gezogen.

> **Alternative**: Falls kein SSH-Key zwischen den Servern eingerichtet werden kann, können die Daten über den lokalen Rechner als Zwischenstation übertragen werden (erst herunterladen, dann hochladen).

### 4.4 Berechtigungen korrigieren

```bash
ssh devops@<NEUE_IP_ADRESSE>

# Allgemeine Berechtigungen
sudo chown -R devops:docker /var/docker/data/
sudo chown -R devops:docker /var/docker/work/
sudo chown -R devops:devops /backup/

# Spezielle Berechtigungen für einzelne Dienste

# Grafana läuft als UID 472
sudo chown -R 472:472 /var/docker/data/grafana/

# Prometheus läuft als UID 65534 (nobody)
sudo chown -R 65534:65534 /var/docker/data/prometheus/

# pgAdmin läuft als UID 5050
sudo chown -R 5050:5050 /var/docker/data/pgadmin/

# PhotoPrism läuft als UID 1000
sudo chown -R 1000:1000 /var/docker/data/photoprism/
sudo chown -R 1000:1000 /var/docker/work/photoprism/

# Traefik acme.json muss 600 sein
sudo chmod 600 /var/docker/work/traefik/acme.json
```

### 4.5 Container auf dem neuen Server starten

```bash
ssh devops@<NEUE_IP_ADRESSE>

cd /var/docker
docker compose up -d

# Status prüfen
docker ps --format "table {{.Names}}\t{{.Status}}"

# Logs auf Fehler prüfen
docker compose logs --tail=50
```

### 4.6 Datenbanken wiederherstellen (falls nötig)

Falls die Datenbanken nicht korrekt starten, können die Backups wiederhergestellt werden:

```bash
# Grafana-Datenbank wiederherstellen
sudo /var/docker/restore_grafana.sh

# TimescaleDB wiederherstellen
LATEST_TS=$(ls -t /backup/dump_timescale_*.sql.gz | head -1)
zcat "$LATEST_TS" | docker exec -i timescaledb psql -U <TIMESCALE_USER> -d <TIMESCALE_DB>

# PhotoPrism-MariaDB wiederherstellen
LATEST_PP=$(ls -t /backup/dump_photoprism_*.sql.gz | head -1)
zcat "$LATEST_PP" | docker exec -i photoprism-mariadb mariadb -u root -p<ROOT_PASSWORD> photoprism
```

> **Hinweis**: Die Datenbank-Credentials befinden sich verschlüsselt in [`group_vars/web/vault.yml`](group_vars/web/vault.yml). Mit `ansible-vault view group_vars/web/vault.yml` können sie eingesehen werden.

---

## Phase 5: DNS umstellen

### 5.1 TTL vorab reduzieren (1–2 Tage vor Migration)

**Vor** der eigentlichen Migration den TTL-Wert aller DNS-Einträge auf einen niedrigen Wert setzen, um die Propagationszeit zu minimieren:

```
TTL: 300 (5 Minuten)
```

> **Wichtig**: Diese Änderung mindestens **24–48 Stunden vor** der Migration durchführen, damit der alte TTL-Wert abgelaufen ist.

### 5.2 DNS-Einträge aktualisieren

Folgende **10 A-Records** müssen auf die neue IP-Adresse des IONOS-Servers geändert werden:

| Typ | Name | Alter Wert | Neuer Wert |
|-----|------|------------|------------|
| A | `v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `proxy.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `auth.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `metrics.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `graph.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `pgadmin.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `registry.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `photos.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `me.v-collaborate.com` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |
| A | `christian.sterzl.info` | `178.77.98.179` | `<NEUE_IP_ADRESSE>` |

### 5.3 DNS-Propagation prüfen

```bash
# Alle Domains prüfen
for domain in v-collaborate.com proxy.v-collaborate.com auth.v-collaborate.com \
  metrics.v-collaborate.com graph.v-collaborate.com pgadmin.v-collaborate.com \
  registry.v-collaborate.com photos.v-collaborate.com me.v-collaborate.com \
  christian.sterzl.info; do
  echo "=== $domain ==="
  dig +short A "$domain"
  echo ""
done
```

**Erwartete Ausgabe**: Alle Domains sollten die neue IONOS-IP (`<NEUE_IP_ADRESSE>`) zurückgeben.

### 5.4 Globale Propagation prüfen

Online-Tools zur Überprüfung der weltweiten DNS-Propagation:

- [whatsmydns.net](https://www.whatsmydns.net/)
- [dnschecker.org](https://www.dnschecker.org/)

### 5.5 TTL wieder erhöhen

Nach erfolgreicher Migration und Verifizierung den TTL-Wert wieder auf einen normalen Wert setzen:

```
TTL: 3600 (1 Stunde) oder 86400 (24 Stunden)
```

---

## Phase 6: Verifizierung

### 6.1 Container-Status

```bash
ssh devops@<NEUE_IP_ADRESSE>

# Alle 12 Container müssen laufen
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -c "Up"
# Erwartete Ausgabe: 12
```

### 6.2 Dienste-Checkliste

Jeden Dienst einzeln prüfen:

| # | Dienst | URL / Test | Erwartetes Ergebnis |
|---|--------|-----------|---------------------|
| 1 | **Traefik** | `https://proxy.v-collaborate.com` | Dashboard erreichbar (nach Authelia-Login) |
| 2 | **Authelia** | `https://auth.v-collaborate.com` | Login-Seite wird angezeigt |
| 3 | **Prometheus** | `https://metrics.v-collaborate.com` | Prometheus-UI erreichbar (nach Login) |
| 4 | **Node Exporter** | `docker logs node-exporter` | Metriken werden gesammelt |
| 5 | **Grafana** | `https://graph.v-collaborate.com` | Dashboards mit historischen Daten |
| 6 | **Grafana-PG** | `docker logs grafana-pg` | PostgreSQL läuft ohne Fehler |
| 7 | **pgAdmin** | `https://pgadmin.v-collaborate.com` | Login-Seite wird angezeigt |
| 8 | **Minecraft** | Minecraft-Client → `<NEUE_IP_ADRESSE>:25565` | Verbindung zum Server möglich |
| 9 | **TimescaleDB** | `psql -h <NEUE_IP_ADRESSE> -p 5432 -U <USER>` | Datenbankverbindung erfolgreich |
| 10 | **Docker Registry** | `https://registry.v-collaborate.com/v2/_catalog` | JSON-Antwort mit Repository-Liste |
| 11 | **PhotoPrism** | `https://photos.v-collaborate.com` | Fotobibliothek mit Bildern |
| 12 | **PhotoPrism-MariaDB** | `docker logs photoprism-mariadb` | MariaDB läuft ohne Fehler |

### 6.3 Let's Encrypt Zertifikate

Traefik stellt automatisch neue Let's Encrypt-Zertifikate aus. Prüfen:

```bash
# Zertifikat für eine Domain prüfen
echo | openssl s_client -servername proxy.v-collaborate.com \
  -connect <NEUE_IP_ADRESSE>:443 2>/dev/null | openssl x509 -noout -dates -subject

# Alle Subdomains prüfen
for domain in proxy.v-collaborate.com auth.v-collaborate.com \
  metrics.v-collaborate.com graph.v-collaborate.com \
  pgadmin.v-collaborate.com registry.v-collaborate.com \
  photos.v-collaborate.com; do
  echo "=== $domain ==="
  echo | openssl s_client -servername "$domain" \
    -connect <NEUE_IP_ADRESSE>:443 2>/dev/null | openssl x509 -noout -dates
  echo ""
done
```

> **Hinweis**: Falls die Zertifikate vom alten Server migriert wurden (`/var/docker/work/traefik/acme.json`), werden diese zunächst verwendet. Traefik erneuert sie automatisch vor Ablauf. Falls Probleme auftreten, die `acme.json` löschen und Traefik neu starten:
> ```bash
> ssh devops@<NEUE_IP_ADRESSE>
> sudo rm /var/docker/work/traefik/acme.json
> docker restart reverse-proxy
> ```

### 6.4 Prometheus-Targets prüfen

```bash
ssh devops@<NEUE_IP_ADRESSE>

# Prometheus-Targets prüfen
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'
# Alle Targets sollten "health": "up" zeigen
```

### 6.5 Backup-Cron prüfen

```bash
ssh devops@<NEUE_IP_ADRESSE>

# Cron-Jobs des devops-Benutzers anzeigen
crontab -l

# Erwartete Einträge:
# */5 * * * * /var/docker/start.sh        (Health-Check)
# 0 23 * * * /var/docker/backup_databases.sh  (Datenbank-Backup)

# Backup-Skript manuell testen
sudo /var/docker/backup_databases.sh

# Prüfen ob Backups erstellt wurden
ls -la /backup/
```

### 6.6 Monitoring prüfen

In Grafana (`https://graph.v-collaborate.com`):
- Dashboards laden korrekt
- Datenquellen sind verbunden
- Historische Daten sind vorhanden (falls Prometheus-Daten migriert wurden)

---

## Phase 7: Alten Server abschalten

### 7.1 Übergangsphase

- Den alten HostEurope-Server **mindestens 2 Wochen** nach der DNS-Umstellung weiterlaufen lassen
- In dieser Zeit regelmäßig prüfen, ob noch Traffic auf dem alten Server ankommt:
  ```bash
  ssh devops@178.77.98.179
  docker logs reverse-proxy --since 24h 2>&1 | grep -c "HTTP"
  ```
- Wenn kein Traffic mehr eingeht, kann der alte Server abgeschaltet werden

### 7.2 Finales Backup vom alten Server

```bash
# Letztes vollständiges Backup erstellen
ssh devops@178.77.98.179

# Datenbank-Backup
sudo /var/docker/backup_databases.sh

# Gesamtes Docker-Verzeichnis sichern (lokal)
rsync -avz --progress devops@178.77.98.179:/var/docker/ ./final-backup-hosteurope/docker/
rsync -avz --progress devops@178.77.98.179:/backup/ ./final-backup-hosteurope/backup/
```

### 7.3 HostEurope-Vertrag kündigen

- Kündigungsfrist des HostEurope-Vertrags prüfen
- Kündigung rechtzeitig einreichen
- **Empfehlung**: Erst kündigen, wenn die Migration mindestens 2 Wochen stabil läuft

### 7.4 Zeitplan-Empfehlung

| Zeitpunkt | Aktion |
|-----------|--------|
| Tag 0 | Migration durchführen (Phase 1–6) |
| Tag 1–14 | Beide Server parallel betreiben, neuen Server überwachen |
| Tag 14 | Alten Server herunterfahren (Container stoppen) |
| Tag 14–30 | Alten Server als Notfall-Backup behalten |
| Tag 30+ | HostEurope-Vertrag kündigen |

---

## Rollback-Plan

Falls während oder nach der Migration Probleme auftreten, kann jederzeit auf den alten Server zurückgewechselt werden.

### Sofort-Rollback (vor DNS-Umstellung)

Wenn DNS noch nicht umgestellt wurde:

1. **Keine Aktion nötig** — Der alte Server läuft weiterhin und bedient alle Anfragen
2. Ansible-Konfiguration zurücksetzen:
   ```bash
   git checkout main -- hosts.yml
   ansible-vault edit group_vars/system/vault.yml
   # vault_ansible_ssh_pass auf altes Passwort zurücksetzen
   ```

### Rollback nach DNS-Umstellung

Wenn DNS bereits auf den neuen Server zeigt, aber Probleme auftreten:

1. **DNS zurücksetzen** — Alle A-Records wieder auf `178.77.98.179` ändern
2. **Container auf dem alten Server starten**:
   ```bash
   ssh devops@178.77.98.179
   cd /var/docker
   docker compose up -d
   ```
3. **Warten auf DNS-Propagation** — Bei TTL 300 dauert dies maximal 5 Minuten
4. **Ursache auf dem neuen Server analysieren** und beheben

### Rollback-Voraussetzungen

- ⚠️ **Alten Server NICHT abschalten**, bevor die Migration vollständig verifiziert ist
- ⚠️ **Alten Server NICHT kündigen**, bevor mindestens 2 Wochen stabiler Betrieb auf dem neuen Server bestätigt ist
- ⚠️ **DNS-TTL niedrig halten** (300 Sekunden) während der gesamten Übergangsphase

---

## IONOS-spezifische Hinweise

### IONOS Cloud Panel Firewall

Die IONOS Firewall wird über das **Cloud Panel** konfiguriert:

1. Einloggen unter [my.ionos.de](https://my.ionos.de)
2. **Server & Cloud** → Server auswählen
3. **Netzwerk** → **Firewall-Richtlinien**
4. Regeln hinzufügen (siehe [Phase 1.2](#12-ionos-firewall-konfigurieren))

| Eigenschaft | IONOS Firewall |
|-------------|----------------|
| Ebene | Netzwerk (vor dem Server) |
| Verwaltung | Cloud Panel (Web-Oberfläche) |
| Stateful | Ja |
| Kosten | Im Server-Preis enthalten |

> **Hinweis**: Die IONOS Firewall ergänzt iptables/nftables auf dem Server. Für maximale Sicherheit sollten beide Ebenen konfiguriert sein.

### IONOS DNS (falls IONOS als DNS-Provider)

Falls die Domains bei IONOS verwaltet werden, können die DNS-Einträge direkt im IONOS Cloud Panel geändert werden:

1. **Domains & SSL** → Domain auswählen
2. **DNS** → A-Records bearbeiten
3. Alle 10 A-Records auf die neue IP-Adresse ändern (siehe [Phase 5.2](#52-dns-einträge-aktualisieren))

> **Vorteil**: DNS-Änderungen bei IONOS werden in der Regel innerhalb weniger Minuten wirksam.

### IONOS Backup / Snapshot

IONOS bietet verschiedene Backup-Möglichkeiten:

#### Server-Snapshots

- Im Cloud Panel unter **Server** → **Snapshots** erstellen
- Erfasst den gesamten Server-Zustand (Disk-Image)
- **Empfehlung**: Vor größeren Änderungen einen Snapshot erstellen

#### Automatische Backups

- Aktivierung im Cloud Panel unter **Server** → **Backups**
- Tägliche automatische Backups auf Server-Ebene
- Ergänzt die bestehenden Datenbank-Backups (Cron um 23:00 Uhr)

> **Hinweis**: IONOS-Snapshots und -Backups ersetzen **nicht** die täglichen Datenbank-Backups via `backup_databases.sh`, da sie den gesamten Server-Zustand erfassen und nicht granular wiederherstellbar sind.

### IONOS API (optional)

IONOS bietet eine REST-API für Automatisierung:

- **Dokumentation**: [developer.ionos.com](https://developer.ionos.com)
- **API-Token**: Im Cloud Panel unter **Benutzerverwaltung** → **API-Token** erstellen
- **Anwendungsfälle**: Server-Management, Firewall-Regeln, DNS-Verwaltung

```bash
# Beispiel: Server-Status abfragen
curl -s -H "Authorization: Bearer <API_TOKEN>" \
  https://api.ionos.com/cloudapi/v6/datacenters | python3 -m json.tool
```

> **Hinweis**: Die API-Nutzung ist optional und für die Migration nicht erforderlich.

---

## Checkliste

### Vorbereitung

- [ ] IONOS Account vorhanden und Server bestellt
- [ ] SSH-Schlüsselpaar vorhanden (`~/.ssh/id_rsa` + `~/.ssh/id_rsa.pub`)
- [ ] Ansible Vault Passwort griffbereit
- [ ] DNS-Provider Zugangsdaten griffbereit (für `v-collaborate.com` und `christian.sterzl.info`)
- [ ] Lokales Ansible Setup funktioniert (`ansible`, `ansible-vault`)
- [ ] Migrationszeitpunkt festgelegt
- [ ] DNS-TTL auf 300 Sekunden reduziert (24–48h vorher)

### Debian 13 Kompatibilität

- [ ] Docker APT-Repo Codename-Fallback implementiert
- [ ] pip durch apt `python3-docker` ersetzt (PEP 668)
- [ ] Python 2 Alternativen entfernt
- [ ] Docker Experimental-Flag entfernt
- [ ] aptitude-Installation entfernt
- [ ] Codename auf `trixie` gesetzt

### Phase 1: Server vorbereiten

- [ ] SSH-Zugang getestet: `ssh root@<NEUE_IP_ADRESSE>`
- [ ] IONOS Firewall konfiguriert (Ports 22, 80, 443, 5432, 25565)
- [ ] Neue IP-Adresse notiert: `_______________`

### Phase 2: Ansible anpassen

- [ ] [`hosts.yml`](hosts.yml) — `ansible_host` auf neue IP geändert
- [ ] [`group_vars/system/vault.yml`](group_vars/system/vault.yml) — Root-Passwort aktualisiert
- [ ] [`roles/debian/vars/main.yml`](roles/debian/vars/main.yml) — bereits auf `trixie` ✓
- [ ] Änderungen committet (optional)

### Phase 3: Provisionierung

- [ ] SSH-Fingerprint des neuen Servers akzeptiert
- [ ] `ansible-playbook system.yml --ask-vault-pass` erfolgreich
- [ ] SSH-Login als `devops` funktioniert
- [ ] `ansible-playbook site.yml --ask-vault-pass` erfolgreich
- [ ] Alle 12 Container laufen (`docker ps` zeigt 12 Container mit Status `Up`)

### Phase 4: Datenmigration

- [ ] Container auf dem alten Server gestoppt
- [ ] Finales Datenbank-Backup auf dem alten Server erstellt
- [ ] `/var/docker/data/` per rsync übertragen
- [ ] `/var/docker/work/` per rsync übertragen (inkl. Traefik-Zertifikate, Registry-Daten)
- [ ] `/backup/` per rsync übertragen
- [ ] Berechtigungen auf dem neuen Server korrigiert (Grafana UID 472, Prometheus UID 65534, pgAdmin UID 5050, PhotoPrism UID 1000)
- [ ] Container auf dem neuen Server gestartet
- [ ] Alle 12 Container laufen ohne Fehler
- [ ] Datenbanken wiederhergestellt (falls nötig)

### Phase 5: DNS-Umstellung

- [ ] A-Record `v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `proxy.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `auth.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `metrics.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `graph.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `pgadmin.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `registry.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `photos.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `me.v-collaborate.com` → `<NEUE_IP_ADRESSE>`
- [ ] A-Record `christian.sterzl.info` → `<NEUE_IP_ADRESSE>`
- [ ] DNS-Propagation mit `dig` verifiziert
- [ ] Globale Propagation geprüft (whatsmydns.net)

### Phase 6: Verifizierung

- [ ] Traefik-Dashboard erreichbar (`proxy.v-collaborate.com`)
- [ ] Authelia-Login funktioniert (`auth.v-collaborate.com`)
- [ ] Prometheus erreichbar (`metrics.v-collaborate.com`)
- [ ] Node Exporter sammelt Metriken
- [ ] Grafana mit Dashboards und Daten (`graph.v-collaborate.com`)
- [ ] Grafana-PG (PostgreSQL) läuft
- [ ] pgAdmin erreichbar (`pgadmin.v-collaborate.com`)
- [ ] Minecraft-Server erreichbar (Port 25565)
- [ ] TimescaleDB erreichbar (Port 5432)
- [ ] Docker Registry erreichbar (`registry.v-collaborate.com`)
- [ ] PhotoPrism mit Fotos (`photos.v-collaborate.com`)
- [ ] PhotoPrism-MariaDB läuft
- [ ] Let's Encrypt Zertifikate gültig (alle Subdomains)
- [ ] Prometheus-Targets alle `up`
- [ ] Cron-Jobs aktiv (Backup + Health-Check)
- [ ] Backup-Skript manuell getestet
- [ ] Redirect `me.v-collaborate.com` → LinkedIn
- [ ] Redirect `christian.sterzl.info` → LinkedIn

### Phase 7: Abschluss

- [ ] Alter Server läuft parallel (mindestens 2 Wochen)
- [ ] Kein Traffic mehr auf dem alten Server
- [ ] Finales Backup vom alten Server erstellt und lokal gesichert
- [ ] DNS-TTL wieder auf Normalwert erhöht
- [ ] Alter Server heruntergefahren
- [ ] HostEurope-Vertrag gekündigt
- [ ] Git-Branch gemergt (falls verwendet)

---

*Erstellt: April 2025 — Aktualisiert: April 2026 — Siehe auch [`ARCHITECTURE.md`](ARCHITECTURE.md) für die vollständige Systemarchitektur.*
