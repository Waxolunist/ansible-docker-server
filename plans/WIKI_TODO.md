# Wiki TODO

Open items for the Otterwiki rollout at `wiki.v-collaborate.com`. The wiki
itself is described in [ARCHITECTURE.md](../ARCHITECTURE.md#otterwiki).

---

## 1. SMTP for Authelia

**Why:** Authelia's notifier writes to `work/authelia/notification.txt` on
the server. Users cannot reset a forgotten password themselves, and every new
wiki user has to be handed a password by the admin. 2FA enrollment also
sends a verification mail, so this is a prerequisite for requiring 2FA later.

**How:**

- [ ] Replace the `notifier.filesystem` block in
      [`authelia_yml.j2`](../roles/web/templates/authelia/authelia_yml.j2)
      with `notifier.smtp`. The Gmail account Grafana already uses can be
      reused: `smtp.gmail.com:587`, user `vault_smtp_server_user`.
- [ ] Pass the password as a Docker secret: add the existing `smtp_password`
      secret to the `authelia` service and set
      `AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=/run/secrets/smtp_password`.
- [ ] Set `notifier.smtp.sender`. Gmail rewrites the From address to the
      authenticated account unless the sender is a verified alias.
- [ ] Test a password reset from `auth.v-collaborate.com`.

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

- [ ] **5-minute inactivity timeout.** Authelia's `session.inactivity: 300`
      applies to the wiki too. Someone writing a long page for more than five
      minutes without saving may find their session gone on save. Ticking
      "Remember me" at login avoids it; raising the timeout is the
      alternative, but Authelia 4.37 has one session config for all services.
- [ ] **Authelia 4.37.2 is old.** 4.38 renamed several config keys
      (`server.address`, `session.cookies`, `identity_validation`) and should
      be upgraded deliberately rather than with a version bump.
