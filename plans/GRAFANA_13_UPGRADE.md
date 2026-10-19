# Grafana 13 Upgrade and v2 Dashboard Provisioning

> **Status: done, 2026-10-19.** Backup in `/backup/grafana_pre13_2026-10-19_163557/`.
> The restore into PostgreSQL 18 matched the row counts of all 86 tables. Grafana is on 13.2.4,
> and the seven Homeassistant dashboards are file-provisioned.
>
> Deviations from the plan:
> - **Startup crash:** Grafana 13 crash-looped on its first start. It could not
>   create its search index because `data/grafana/{alerting,csv,pdf,png,unified-search}`
>   were still owned by `nobody` from older images. With no index, the
>   dashboard migration's count check failed (legacy 15, unified 0).
>   `grafana.yml` now gives these directories and `plugins/` to uid 472. After
>   that, the migration passed on the next start.
> - **Healthcheck:** `start_period` raised to 120s, so autoheal cannot restart
>   Grafana during a migration.
> - **Missing directories:** `provisioning/plugins` and `provisioning/alerting`
>   are created to silence errors on every start.
> - **Plugin updates:** `plugins update-all` updated 10 plugins.
> - **Pre-existing alert error:** the alert rule "e208 Startup" refers to a
>   dashboard uid (`e78023da-…`) that already did not exist before the upgrade,
>   so Grafana logs an error for its annotations.

## Goal

Deploy the seven dashboards in the Grafana folder `Homeassistant` with the
`grafana_dashboards` tag, next to the two that are deployed already. They use
the v2 dashboard schema, which is a hard requirement. Grafana 12.2.8 cannot
provision v2 dashboards from files, and Grafana 13 can, so Grafana is
upgraded first. Its database moves from PostgreSQL 13, which is past
end-of-life, to 18. Everything is backed up before either change.

## Current State

| Item | Value |
|---|---|
| Grafana | `grafana/grafana:12.2.8`, feature toggle `dashboardNewLayouts = true` |
| Database | `grafana-pg`, `postgres:13-alpine` (13.23), `pgdata` 410 MB, mounted at `/var/lib/postgresql/data` |
| Data dir | `/var/docker/data/grafana`, 530 MB (120 MB plugins, `unified-search`, `alerting`, `csv`/`pdf`/`png`) |
| Config dir | `/var/docker/configs/grafana`, 76 KB (`grafana.ini`, provisioning) |
| Nightly backup | `/backup/dump_grafana_<date>.sql.gz` via `backup_databases.sh` at 23:00, last 20 kept |
| Free disk | 81 GB |
| Plugins | 14 community/app plugins, none Angular |

Dashboards in `Homeassistant` (folder uid `cekag6n00voxsd`), all stored as v2:

| uid | Title | Stored as |
|---|---|---|
| `cekyf6g8gyupse` | Solar - Live | v2alpha1 |
| `bekag75iz9on4e` | Solar - Month | v2alpha1 |
| `del1obdfglfy8f` | Solar - Weekly | v2alpha1 |
| `eel1njcu6jocgd` | Solar - Yesterday | v2alpha1 |
| `chs2h7x` | Vehicle - Analysis | v2alpha1 |
| `chw95zv` | Vehicle - Control | v2beta1 |
| `ch6qwwl` | Vehicle - Live | v2alpha1 |

Facts that shape the plan:

- compose runs with `recreate: never`. Only services in
  `recreate_when_changed` are recreated when their definition changes, and
  neither `grafana` nor `grafana-pg` is in it.
- Grafana 13 moves dashboards and folders into unified storage on first
  start. Per the upgrade guide, the only way back is restoring the
  pre-upgrade database backup.
- PostgreSQL 18 is the newest supported release (18.6, supported until
  November 2030; 19 is a release candidate). Grafana supports every release
  PostgreSQL itself still supports.
- From 18 on, the official image keeps its data in
  `/var/lib/postgresql/18/docker`, with the volume at `/var/lib/postgresql`.
  It refuses to start on an older cluster mounted at
  `/var/lib/postgresql/data`. A major upgrade needs a dump and restore into
  a new cluster anyway.

Order: backup → PostgreSQL 18 (Grafana still 12.2.8) → Grafana 13 →
dashboards → docs. Each step is checked before the next, so a problem points
at a single change.

---

## Phase 1: Backup

A one-off backup in its own directory, `/backup/grafana_pre13_<timestamp>/`.
That keeps it out of the nightly cleanup, which deletes all but the newest 20
`dump_grafana_*.sql.gz`.

1. Export every dashboard (15) through the API as JSON, at its stored version,
   to `dashboards/`. This is a readable copy that does not depend on the
   database format.
2. Stop `web_grafana` (keep `grafana-pg` running) so nothing writes while
   files are copied.
3. Dump the `grafana` database twice:
   - `pg_dump -c`, gzipped. This is the same format `restore_grafana.sh`
     takes, and that script accepts an explicit path.
   - `pg_dump -Fc` for the restore into PostgreSQL 18. It is made with the
     version 18 client, run from a temporary `postgres:18-alpine` container
     on the `grafana` network, as PostgreSQL recommends for upgrades.
4. Record row counts of the main tables (`dashboard`, `folder`, `user`,
   `data_source`, `alert_rule`, `api_key`, `preferences`) to compare after the
   restore.
5. `tar czf configs.tar.gz` of `/var/docker/configs/grafana`.
6. `tar czf data.tar.gz` of `/var/docker/data/grafana` without `pgdata`.
   It holds the plugins, alerting state and search index.
7. Verify: `gzip -t` on the dump, `pg_restore --list` on the custom dump,
   `tar tzf` on both archives, and non-zero sizes.

Grafana stays stopped for Phase 2.

## Phase 2: PostgreSQL 13 → 18

### Changes

| File | Change |
|---|---|
| `roles/web/templates/docker-compose_yml.j2` | `grafana-pg` image `postgres:13-alpine` → `postgres:18-alpine`. Volume `{{ docker.paths.data }}grafana/postgres:/var/lib/postgresql`, the layout the 18 image expects. |
| `roles/web/tasks/grafana.yml` | The data directory task creates `grafana/postgres` (`70:70`, `0700`) instead of `grafana/pgdata` |
| `roles/web/vars/main.yml` | Add `grafana-pg` to `recreate_when_changed` |

`pgdata/` stays on disk unchanged. It is the way back, and it gets deleted
in a few weeks.

### Rollout

1. Create `/var/docker/data/grafana/postgres` (`70:70`, `0700`).
2. Start a temporary `postgres:18-alpine` container, outside compose, with:
   - the new directory mounted at `/var/lib/postgresql`,
   - the same user, database and password secret as `grafana-pg`,
   - user `70:70`.

   This runs `initdb`.
3. `pg_restore` the custom dump from Phase 1 into it. Check the error
   output, and compare the row counts with Phase 1.
4. Stop and remove the temporary container.
5. `ansible-playbook web.yml`. It writes the new compose file, and
   `grafana-pg` is recreated on 18 with the restored cluster.

   compose may start Grafana against the old container for a few seconds
   before that. Nothing is lost, since the old cluster has the same data.
   Grafana is restarted afterwards so it reconnects cleanly.
6. Verify:
   - `SELECT version()` reports 18.
   - The row counts match Phase 1.
   - Grafana 12.2.8 is healthy, login works, and dashboards and alerts are
     present.
   - `backup_databases.sh` runs and writes a non-empty dump.

### Rollback

Revert the image and volume in the compose template, then run
`ansible-playbook web.yml`. The old `pgdata/` was only ever stopped, never
changed.

## Phase 3: Upgrade to Grafana 13

### Pre-flight (read-only)

- Pull `grafana/grafana:13.2.4` (latest 13.x) on the server and check it still
  ships `wget`. The compose healthcheck uses it, and if it is missing autoheal
  would restart Grafana every few minutes. If it is gone, switch the
  healthcheck to `curl` or the `grafana` binary.
- Check `grafana.ini` against the 13.0 breaking changes. Known items and
  their impact here:
  - Image renderer plugin removed: not used.
  - `grafana-server` / `grafana-cli` removed: compose uses the image
    entrypoint, so nothing to change.
  - Data source ID APIs disabled: only affects API clients using numeric
    ids. Provisioned data sources use uids.
  - Git Sync migration bug in 13.0.0: `provisioning` flags are not enabled,
    and 13.2.4 is past the fix.

### Changes

| File | Change |
|---|---|
| `roles/web/templates/docker-compose_yml.j2` | `grafana/grafana:12.2.8` → `grafana/grafana:13.2.4` |
| `roles/web/vars/main.yml` | Add `grafana` to `recreate_when_changed`, so this and future version bumps recreate it |

### Rollout

1. Take a fresh `pg_dump -c` of the database on 18. This is the rollback
   point for this phase, taken after the Phase 2 restore and before the
   unified storage migration.
2. `ansible-playbook web.yml`
3. Follow the logs until the unified storage migration finishes, then check
   `unifiedstorage_migration_log` in `grafana-pg`.
4. `docker exec web_grafana grafana cli plugins update-all`, then restart
   Grafana, as the upgrade guide recommends.
5. Verify:
   - `/api/health` reports 13.2.4.
   - Login through Authelia works (auth proxy).
   - All 15 dashboards and both folders are present, and the Homeassistant
     dashboards render.
   - Alert rules and contact points are unchanged.
   - No plugin load errors in the logs.

### Rollback

1. Set the image back to `12.2.8` in the compose template.
2. Stop `web_grafana`.
3. Drop and recreate the `grafana` database. A plain `psql` restore over the
   migrated database would leave Grafana 13's new tables behind.
4. Restore the dump from step 1 with `psql`.
5. Restore `data.tar.gz` and `configs.tar.gz` from Phase 1.
6. `ansible-playbook web.yml`.

## Phase 4: Provision the v2 Dashboards

### Test first

Before deploying, run Grafana 13.2.4 locally in OrbStack, using a copy of
the provider configuration and one Homeassistant dashboard file. Confirm:

- The file loads. Open issue
  [#123607](https://github.com/grafana/grafana/issues/123607) reports that
  exported resources do not load in some cases.
- The subdirectory becomes the folder.
- The `uid` is kept.

Only after that does anything reach the server.

### Dashboard files

- Re-export the seven dashboards after the upgrade through the v2 API, so
  all of them are in the version Grafana 13 provisions
  (`apiVersion: dashboard.grafana.app/v2`). The mixed v2alpha1/v2beta1
  versions get normalized on the way.
- Keep `kind`, `apiVersion`, `metadata.name` and `spec`. Drop `status`,
  `resourceVersion`, `generation`, timestamps and annotations. Grafana sets
  those itself.
- `metadata.name` stays the existing uid, so provisioning takes over the
  existing dashboards instead of creating copies, and links keep working.
- Store them in
  `roles/web/files/grafana/provisioning/dashboards/Homeassistant/<title>.json`,
  for example `solar_live.json` and `vehicle_control.json`.

### Provisioning

| File | Change |
|---|---|
| `provider.yml.j2` | `foldersFromFilesStructure: true`, so `Homeassistant/` becomes the folder `Homeassistant`. Files at the top level stay in General as before. |
| `tasks/grafana_dashboards.yml` | Copy the whole dashboards directory, including subdirectories, instead of the top-level `*.json` glob. Also write `provider.yml` here (moved from `grafana.yml`) and register the result. |
| `tasks/main.yml` | Restart Grafana when the provider changed as well as when `grafana.ini` changed. Grafana reads providers only at startup. Give that restart task the `grafana_dashboards` tag too. |

The folder is matched by title. The test has to show that Grafana reuses the
existing folder `cekag6n00voxsd` rather than creating a second
`Homeassistant`. If it does not, the provider gets a second entry with
`folderUid: cekag6n00voxsd`, pointing at a sibling directory.

### Rollout

1. `ansible-playbook web.yml --tags grafana_dashboards`
2. Verify:
   - The seven dashboards show as provisioned in `Homeassistant`, with
     unchanged uids.
   - No duplicate dashboards or folders.
   - The two General dashboards are unaffected.

`allowUiUpdates: true` stays, so the dashboards can still be edited in
Grafana. An edit lives only in the database until it is exported back to the
file, and the next change to the file overwrites it.

## Phase 5: Documentation

- `README.md`:
  - "Deploy only parts": dashboards live in subdirectories by folder, and v2
    dashboards are stored in Kubernetes resource format.
  - How to add a dashboard: Export → V2 Resource → JSON, then save it in the
    folder directory.
- `ARCHITECTURE.md`:
  - Grafana and `grafana-pg` versions in the services table and the Grafana
    section (12.2 → 13.2, PostgreSQL 13 → 18).
  - The `grafana/postgres/` data directory in the directory layout.
  - Provisioned dashboards by folder.
  - The backup from Phase 1 next to the restore procedure.

## Follow-up

- [ ] Delete `/var/docker/data/grafana/pgdata` (PostgreSQL 13) once Grafana 13
  has run without problems for a few weeks.
- [ ] Fix the alert rule "e208 Startup". It is linked to dashboard
  `e78023da-49b6-408f-8cfa-9d56ac3af6ef`, which no longer exists; it was
  already missing before the upgrade. Each evaluation therefore logs
  `Error getting dashboard for alert annotation` (logger
  `ngalert.state.historian`). The fix is one of:
  - Link the rule to the dashboard it belongs to: edit the rule, then
    "Link dashboard and panel".
  - Remove the link, which clears `dashboard_uid` and `panel_id`.
  - Delete the rule if it is no longer needed.

## Out of Scope

- The other General dashboards (Authelia, Host Health, Node Exporter Full and
  others) stay unprovisioned.
