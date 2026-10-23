# Firewall

The VPS has no host firewall (`INPUT` policy `ACCEPT`, `DOCKER-USER` empty).
What reaches it from the internet is decided by the provider's firewall
policy (IONOS Cloud Panel), which is configured by hand. This file is the
intended state of that policy; keep both in step.

| Port | Protocol | Service | Allowed from | Notes |
|---|---|---|---|---|
| 22 | TCP | sshd | anywhere | Key login only, `AllowUsers devops`, fail2ban (`hardening.yml`) |
| 80 | TCP | Traefik | anywhere | Redirects to HTTPS |
| 443 | TCP | Traefik | anywhere | All web services, plus SSH wrapped in TLS (`ssh.v-collaborate.com`) |
| 3478 | TCP + UDP | coturn | anywhere | STUN/TURN |
| 5349 | TCP + UDP | coturn | anywhere | TURN over TLS/DTLS |
| 49152–49200 | UDP | coturn | anywhere | TURN relay range |
| 51820 | UDP | WireGuard (`wg0`) | anywhere | Silent without a valid key; the Pi's tunnel to TimescaleDB (`wireguard.yml`) |
| 25565 | TCP | Minecraft | closed | Open it only while the server is in use |

Not allowed from the internet, although something listens on all interfaces:

| Port | What | Why it stays closed |
|---|---|---|
| 5355 | LLMNR (systemd-resolved) | Local name resolution only |
| 9641 | coturn metrics | Scraped by Prometheus over `docker.host` |

TimescaleDB is not in either table: it is published only on the WireGuard
address (`10.8.0.1:5432`), so it is unreachable from the internet whatever
the provider's policy says. A laptop reaches it through an SSH tunnel
(`ssh -N -L 5432:10.8.0.1:5432 v-collaborate.com`).

Check from a machine outside the VPS:

```bash
for p in 22 80 443 3478 5349 5355 5432 9641 25565; do
  nc -z -G 3 v-collaborate.com $p >/dev/null 2>&1 && echo "$p open" || echo "$p closed"
done
```

On 2026-10-23 this matched the table: 22, 80, 443, 3478 and 5349 open, the
rest closed. UDP ports cannot be checked this way; for 51820, a recent
handshake on the Pi (`sudo wg show wg0 latest-handshakes`) shows it is open.
