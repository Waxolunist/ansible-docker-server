# Wiki TODO

Open items for the Otterwiki rollout at `wiki.v-collaborate.com`. The wiki
itself is described in [ARCHITECTURE.md](../ARCHITECTURE.md#otterwiki).

---

## 1. SMTP for Authelia — done

- [x] `notifier.smtp` through the Gmail account Grafana already uses
      (`submission://smtp.gmail.com:587`, `vault_smtp_server_user`), password
      from the shared `smtp_password` Docker secret.
- [x] Sender set to the Gmail address itself; Gmail rewrites anything else.
- [x] Credentials verified against Gmail before deploying. The startup check
      is disabled afterwards so a revoked app password cannot keep Authelia,
      and every service behind it, from starting.
- [x] Verification mail arrives: tested with a password reset and a
      password change for a test account.

**Decision (revised):** self-service password reset and change are enabled.
The users moved out of the vault into `data/authelia/users/`, owned by
Authelia and managed with `scripts/authelia_user.sh`.

## 2. Push the wiki to a private GitHub repository

**Why:** The nightly tarball in `/backup` lives on the same server. A remote
copy survives losing the server, and the wiki history becomes browsable as a
normal git repo.

- [x] Private repository `Waxolunist/wiki` on the personal account.
- [x] Read-write deploy key for that repository only. The private half is
      `vault_otterwiki_push_private_key` in the vault.
- [x] `GIT_REMOTE_PUSH_*` in
      [`settings_cfg.j2`](../roles/web/templates/otterwiki/settings_cfg.j2);
      the key goes in directly (`GIT_REMOTE_PUSH_PRIVATE_KEY`), like the
      `SECRET_KEY`, so no extra file or mount.
- [x] Documented in [VAULT_VARIABLES.md](../VAULT_VARIABLES.md).
- [ ] After deploying, push the existing history once with the **Push**
      button under Admin → Repository Management, then check that a page
      edit shows up on GitHub.
- [ ] Later, for read-only access by other people: move the repository into
      a free GitHub organization. On a personal account every collaborator
      can push, and any push from outside makes the wiki's pushes fail.

---

## Noticed during setup

- [x] **Inactivity timeout raised from 5 to 30 minutes.** With 5 minutes,
      someone writing a long page without saving could find their session
      gone on save. Every service shares the one `v-collaborate.com` cookie,
      so the longer timeout applies to all of them.
