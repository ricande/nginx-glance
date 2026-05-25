# Architecture

## Purpose

Nginx Glance provides **local, read-only visibility** into nginx and the sites it serves. It is not a monitoring platform, log aggregator, or deployment tool.

## Components

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| **Backend** | `nginx-glance.sh` (Bash) | Discover config, run checks, emit `--text` or `--json` |
| **Installer** | `install.sh` | Dependency checks, deploy script, optional plasmoid install |
| **Plasmoid** | QML (Plasma 6) | Display JSON summary; refresh every 30s |
| **Test fixtures** | `testdata/nginx-sites-enabled/` | Offline parsing tests |

## Data flow

```
sites-enabled/*.conf
        │
        ▼ (read-only parse)
┌───────────────────┐
│ nginx-glance.sh   │
│  · domains        │──► curl -sI  http(s)://domain/
│  · listen ports   │──► ss -ltn
│  · proxy_pass     │──► ss -ltn (backend port)
│  · nginx.service  │──► systemctl is-active
│  · system metrics │──► /proc, free, df
└─────────┬─────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
 --text      --json
 (terminal)  (plasmoid / automation)
```

## Boundaries

### In scope

- Literal `server_name` hosts from enabled site files
- HTTP/HTTPS response headers for `/`
- Whether configured TCP ports are listening
- `nginx.service` active state
- CPU load, memory, root filesystem use

### Out of scope

- TLS certificate expiry (future idea)
- Per-application systemd unit names
- nginx config syntax validation (`nginx -t`)
- Remote monitoring or alerting pipelines
- Secrets (.env, keys, cert private material)

## Security model

- Runs as the **desktop user** (same as widget/terminal)
- Requires **read** access to `NGINX_SITES_ENABLED`
- Uses **network loopback/DNS** as resolved on the host for `curl` checks
- **No privilege escalation** in normal paths

See [ADR-0001](adr/0001-read-only-local-status.md).

## Extension points

| Extension | Mechanism today | Future option |
|-----------|-----------------|---------------|
| Custom sites path | `NGINX_SITES_ENABLED` | — |
| Custom health path | — | Config file per domain |
| Notifications | — | Wrapper on `--json` exit/summary |
| Extra metrics | — | New read-only collectors in Bash |

## Related documents

- [backend.md](backend.md)
- [parsing.md](parsing.md)
- [plasmoid.md](plasmoid.md)
- [install-and-dependencies.md](install-and-dependencies.md)
