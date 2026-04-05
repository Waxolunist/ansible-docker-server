# Registry Improvements Plan

## Current State

The Docker Registry is deployed via three files:

- [`registry_yml.j2`](../roles/web/templates/registry/registry_yml.j2) — Registry daemon config
- [`docker-compose_yml.j2`](../roles/web/templates/docker-compose_yml.j2:1-26) — Docker Compose service definition
- [`registry.yml`](../roles/web/tasks/registry.yml) — Ansible provisioning task

The registry currently has basic logging, filesystem storage, Prometheus metrics on a debug port, and Traefik routing — but is missing several production-hardening features.

---

## Proposed Changes

### 1. Add Health Check Configuration (registry config)

**File:** `roles/web/templates/registry/registry_yml.j2`

Add a `health` section to the registry config. The registry supports built-in health checks with configurable storage driver checks and HTTP endpoint checks.

```yaml
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
```

This periodically verifies the storage backend is accessible and marks the registry unhealthy after 3 consecutive failures.

---

### 2. Add Docker Healthcheck (docker-compose)

**File:** `roles/web/templates/docker-compose_yml.j2`

Add a `healthcheck` block to the registry service, similar to how `minecraft` already has one. This uses the registry's built-in `/v2/` endpoint:

```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:{{ registry.port }}/v2/", "||", "exit", "1"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

---

### 3. Pin Registry Image Version

**File:** `roles/web/templates/docker-compose_yml.j2`

Change `registry:2` to `registry:3.0.0` — the latest major version with improved performance, OCI artifact support, and better security defaults.

---

### 4. Add `container_name` for Consistency

**File:** `roles/web/templates/docker-compose_yml.j2`

Every other service has a `container_name`. Add `container_name: web_registry` to match the naming convention.

---

### 5. Add `expose` Directive

**File:** `roles/web/templates/docker-compose_yml.j2`

Add `expose` for the registry port so Traefik can discover it properly:

```yaml
expose:
  - {{ registry.port }}
```

---

### 6. Add `depends_on` for Reverse Proxy

**File:** `roles/web/templates/docker-compose_yml.j2`

The registry is routed through Traefik but doesn't declare a dependency. Add:

```yaml
depends_on:
  - reverse-proxy
```

---

### 7. Enable Delete Support

**File:** `roles/web/templates/registry/registry_yml.j2`

Without delete enabled, you cannot remove images via the API, making cleanup impossible:

```yaml
storage:
  delete:
    enabled: true
  filesystem:
    rootdirectory: /var/lib/registry
```

---

### 8. Add Storage Cache

**File:** `roles/web/templates/registry/registry_yml.j2`

Add an in-memory blob descriptor cache to improve pull performance:

```yaml
storage:
  cache:
    blobdescriptor: inmemory
```

---

### 9. Configure Garbage Collection

**File:** `roles/web/tasks/registry.yml`

Add an Ansible task to set up a cron job for periodic garbage collection. This reclaims disk space from deleted image layers:

```yaml
- name: Registry - Setup garbage collection cron
  cron:
    name: "Registry garbage collection"
    minute: "0"
    hour: "3"
    job: "docker exec web_registry bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged 2>&1 | logger -t registry-gc"
    user: "{{ ansible_user }}"
```

---

### 10. Reduce Log Level to Info

**File:** `roles/web/templates/registry/registry_yml.j2`

Change `level: debug` to `level: info`. Debug logging in production generates excessive log volume and can expose sensitive information.

---

### 11. Add Authelia Authentication Middleware

**File:** `roles/web/templates/docker-compose_yml.j2`

The registry is currently publicly accessible — no `auth@docker` middleware is applied. Other sensitive services like Grafana, Prometheus, and the Traefik dashboard all use Authelia. Add the middleware to the secure router:

```yaml
- traefik.http.routers.registry-secure.middlewares=auth@docker
```

> **Note:** This protects the web UI/API. Docker CLI `docker push`/`pull` authentication would need to be handled separately via the registry's built-in `htpasswd` or token auth if needed.

---

### 12. Fix Timezone Typo (project-wide)

**File:** `roles/web/templates/docker-compose_yml.j2`

`Europa/Vienna` is not a valid POSIX timezone — it should be `Europe/Vienna`. This affects all services in the compose file. While containers may silently fall back to UTC, this should be corrected.

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `roles/web/templates/registry/registry_yml.j2` | Add health section, enable delete, add cache, reduce log level |
| `roles/web/templates/docker-compose_yml.j2` | Add healthcheck, pin version, container_name, expose, depends_on, auth middleware, fix TZ |
| `roles/web/tasks/registry.yml` | Add garbage collection cron task |

---

## Target Registry Config (registry_yml.j2)

```yaml
version: 0.1
log:
  level: info
  formatter: json
  fields:
    service: registry
storage:
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: 0.0.0.0:{{ registry.port }}
  host: https://{{ registry.domain }}
  relativeurls: false
  secret: {{ vault_registry_http_secret }}
  debug:
    addr: 0.0.0.0:5001
    prometheus:
      enabled: true
      path: /metrics
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
```

## Target Docker Compose Registry Service

```yaml
registry:
  image: registry:3.0.0
  container_name: web_registry
  depends_on:
    - reverse-proxy
  expose:
    - {{ registry.port }}
  volumes:
    - "{{ docker.paths.work }}registry:/var/lib/registry"
    - "{{ docker.paths.configs }}registry/config.yml:/etc/docker/registry/config.yml:ro"
    - "{{ docker.paths.logs }}registry:/var/log/docker-registry"
    - "{{ docker.paths.configs }}registry/secrets:/secrets:ro"
  networks:
    - proxy
  labels:
    - traefik.enable=true
    - traefik.docker.network=web_proxy
    - traefik.domain={{ registry.domain }}
    - traefik.http.middlewares.registry-https-redirect.redirectscheme.scheme=https
    - traefik.http.routers.registry-secure.entrypoints=websecure
    - traefik.http.routers.registry-secure.rule=Host(`{{ registry.domain }}`)
    - traefik.http.routers.registry-secure.tls=true
    - traefik.http.routers.registry-secure.tls.certresolver=myresolver
    - traefik.http.routers.registry-secure.middlewares=auth@docker
    - traefik.http.routers.registry.entrypoints=web
    - traefik.http.routers.registry.middlewares=registry-https-redirect
    - traefik.http.routers.registry.rule=Host(`{{ registry.domain }}`)
  environment:
    - TZ=Europe/Vienna
  healthcheck:
    test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:{{ registry.port }}/v2/", "||", "exit", "1"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 10s
  restart: on-failure
```
