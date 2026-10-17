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

**How:**

- [ ] Create a private repository on GitHub, e.g. `Waxolunist/wiki`.
- [ ] Generate an SSH key pair for the wiki and add the public key as a
      **deploy key with write access** to that repository only.
- [ ] Store the private key in the vault (`vault_otterwiki_push_private_key`)
      and write it to a file mounted read-only into the container.
- [ ] Add to [`settings_cfg.j2`](../roles/web/templates/otterwiki/settings_cfg.j2):
      `GIT_REMOTE_PUSH_ENABLED = True`,
      `GIT_REMOTE_PUSH_URL = 'git@github.com:Waxolunist/wiki.git'`,
      `GIT_REMOTE_PUSH_PRIVATE_KEY_FILE = '<mounted path>'`.
      Otterwiki then pushes after every change. The `web_wiki` network is
      not internal, so outbound SSH works.
- [ ] Document the new vault variable in
      [VAULT_VARIABLES.md](../VAULT_VARIABLES.md).

---

## Noticed during setup

- [x] **Inactivity timeout raised from 5 to 30 minutes.** With 5 minutes,
      someone writing a long page without saving could find their session
      gone on save. Every service shares the one `v-collaborate.com` cookie,
      so the longer timeout applies to all of them.
