# Nginx Glance

Local, read-only status for sites handled by nginx. Use it in a **terminal**, a **Command Output** widget, or the included **KDE Plasma 6 plasmoid** — without changing nginx, systemd, certbot, `.env`, or application code.

**Repository:** GitHub — project name `nginx-glance` (use **Code → Clone** on the repo page for the URL).

---

## What this project is

**Nginx Glance** answers: *“Are my local domains and nginx up right now?”*

It:

- Reads nginx configuration from `sites-enabled` (read-only)
- Checks `nginx.service`
- Tests HTTP and HTTPS per discovered `server_name`
- Verifies `listen` ports and `proxy_pass` backends
- Shows light system metrics (CPU load, memory, disk root)
- Exposes **no secrets** (no certs, `.env`, passwords, or keys)

This is **local visibility**, not a monitoring platform. It does not mutate infrastructure.

---

## Two ways to use it

### A. Terminal / Command Output widget

Install the script and run text output:

```bash
~/bin/nginx-glance.sh
~/bin/nginx-glance.sh --text
```

In KDE, add a **Command Output** widget with:

```bash
$HOME/bin/nginx-glance.sh --text
```

Refresh every 30–60 seconds.

### B. Native KDE Plasma 6 widget

Install the plasmoid package (thin UI over the same script):

```bash
./install.sh --plasmoid
```

Then: right-click desktop → **Add Widgets** → **Nginx Glance**.

The widget runs `$HOME/bin/nginx-glance.sh --json` every 30 seconds and shows compact green/yellow/red status plus an expanded domain list.

---

## Project layout

| Path | Role |
|------|------|
| `nginx-glance.sh` | Backend collector (`--text` / `--json`) |
| `install.sh` | Installs script; `--plasmoid` installs widget |
| `plasmoid/` | KDE Plasma 6 applet package |
| `testdata/nginx-sites-enabled/` | Sample configs for offline parsing tests |
| `README.md` | This file |

After install, the live script is `$HOME/bin/nginx-glance.sh`.

---

## Installation

```bash
git clone <repository-clone-url>
cd nginx-glance
./install.sh
```

Optional Plasma widget:

```bash
./install.sh --plasmoid
```

Custom install directory:

```bash
INSTALL_DIR=~/.local/bin ./install.sh
```

---

## Script usage

```bash
nginx-glance.sh [--text|--json|--help]
```

| Option | Description |
|--------|-------------|
| `--text` | Human-readable report (default) |
| `--json` | JSON for the Plasma widget or automation |
| `--help` | Usage and environment variables |

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `NGINX_SITES_ENABLED` | `/etc/nginx/sites-enabled` | nginx site config directory |

### Examples

```bash
# Default (system nginx)
~/bin/nginx-glance.sh

# JSON for widgets / scripts
~/bin/nginx-glance.sh --json

# Parse test fixtures only (no real /etc/nginx required for discovery)
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json
```

### Parsing rules (read-only)

**`server_name`** — collected when valid; ignored when:

- `_` (catch-all placeholder)
- Wildcards (`*.example.com`)
- Regex names (`~...`)
- Variables (`$hostname`)
- Empty tokens

Comments (`# ...`) are stripped before parsing.

**`listen`** — port extracted from forms such as:

- `listen 80;`
- `listen 443 ssl;`
- `listen [::]:443 ssl;`
- `listen 127.0.0.1:8080;`
- `listen *:80;`

**`proxy_pass`** — backends when URL is `http(s)://host:port`; skipped for:

- `unix:` sockets
- upstream names without host:port
- variables (`$...`)
- default port: 80 (http) or 443 (https) if omitted

---

## JSON shape (widget)

```json
{
  "timestamp": "2026-05-25 12:00:00",
  "host": "my-server",
  "config_path": "/etc/nginx/sites-enabled",
  "nginx": { "service": "nginx.service", "status": "active", "ok": true },
  "summary": {
    "domains_total": 3,
    "domains_healthy": 2,
    "domains_unhealthy": 1,
    "ports_listening": 2,
    "ports_missing": 0,
    "backends_ok": 1,
    "backends_missing": 0
  },
  "domains": [ { "name": "example.com", "http": { ... }, "https": { ... } } ],
  "ports": [ { "port": 443, "listening": true } ],
  "backends": [ { "target": "127.0.0.1:3000", "port": 3000, "listening": true } ],
  "system": { "cpu_load": "...", "memory": "...", "disk_root": "..." }
}
```

Domain **healthy** = both HTTP and HTTPS checks OK (2xx/3xx, including redirects).

---

## Development and testing

```bash
# Syntax
bash -n nginx-glance.sh

# Text output
./nginx-glance.sh --text

# JSON + fixtures (parsing without touching /etc/nginx)
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json

# Install locally
./install.sh

# Plasmoid (manual, if install.sh printed instructions)
kpackagetool6 --type Plasma/Applet --install plasmoid
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

Requires **KDE Plasma 6** for the native widget (`X-Plasma-API-Minimum-Version: 6.0`).

### Dependencies

`bash`, `curl`, `systemctl`, `ss`, `awk`, `sed`, `grep`, `free`, `df` — read access to `NGINX_SITES_ENABLED`. **No sudo** for normal use.

---

## Design principles

| Does | Does not |
|------|----------|
| Read nginx config | Change nginx |
| `systemctl is-active` | Start/stop services |
| `curl -sI` to local URLs | Run certbot |
| `ss -ltn` for ports | Change `.env` or app code |
| Show system metrics | Expose secrets |
| | Use `sudo` |
| | Run `npm` |

Health checks use **`/`** per domain. Redirects (301/302) count as OK.

Per-app systemd units are **not** checked — only `nginx.service` and `proxy_pass` ports.

---

## Plasmoid troubleshooting

| Issue | Action |
|-------|--------|
| Widget says install script missing | Run `./install.sh` from the project clone |
| Empty or invalid JSON | Run `~/bin/nginx-glance.sh --json` in a terminal |
| `kpackagetool6` not found | Install KDE dev tools; use manual `kpackagetool6 --install plasmoid` |
| No domains | Check read access to `sites-enabled` |

---

## Remaining ideas (optional)

- [ ] Custom health paths per domain (config file)
- [ ] Notifications on failure
- [ ] Log history via cron/systemd timer
- [ ] TLS certificate expiry (read-only)

---

## Quick reference

```bash
~/bin/nginx-glance.sh --text
~/bin/nginx-glance.sh --json
./install.sh
./install.sh --plasmoid
```

---

*Targets KDE Plasma 6 for the plasmoid; terminal mode works on any Linux host with the listed tools.*
