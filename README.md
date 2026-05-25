# Nginx Glance

Local, read-only status for sites handled by nginx. Use it in a **terminal**, a **Command Output** widget, or the included **KDE Plasma 6 plasmoid** — without changing nginx, systemd, certbot, `.env`, or application code.

**Repository:** GitHub — project name `nginx-glance` (use **Code → Clone** on the repo page for the URL).

See [CHANGELOG.md](CHANGELOG.md) for version history.

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

## Architecture

```
┌─────────────────────┐     --json/--text      ┌──────────────────────┐
│  nginx-glance.sh    │ ◄───────────────────── │  Terminal / cron /   │
│  (backend, Bash)    │                        │  Command Output      │
└──────────┬──────────┘                        └──────────────────────┘
           │
           │ --json
           ▼
┌─────────────────────┐
│  Plasma 6 plasmoid  │  reads $HOME/bin/nginx-glance.sh --json
│  (QML, thin UI)     │  refresh every 30s
└─────────────────────┘
```

The plasmoid is a **thin UI layer**; all checks live in the Bash script.

---

## Two ways to use it

### A. Terminal / Command Output widget

```bash
~/bin/nginx-glance.sh
~/bin/nginx-glance.sh --text
```

KDE **Command Output** widget command:

```bash
$HOME/bin/nginx-glance.sh --text
```

Refresh every 30–60 seconds.

### B. Native KDE Plasma 6 widget

```bash
./install.sh --plasmoid
```

Then: right-click desktop → **Add Widgets** → **Nginx Glance**.

Runs `$HOME/bin/nginx-glance.sh --json` every 30 seconds — compact green/yellow/red summary and an expanded domain list.

---

## Project layout

| Path | Role |
|------|------|
| `nginx-glance.sh` | Backend collector (`--text` / `--json` / `--help`) |
| `install.sh` | Installs script; checks dependencies; optional `--plasmoid` |
| `plasmoid/metadata.json` | Plasma applet metadata |
| `plasmoid/contents/ui/main.qml` | Widget UI |
| `testdata/nginx-sites-enabled/` | Sample nginx configs for offline tests |
| `README.md` | Documentation |
| `CHANGELOG.md` | Version history |
| `.gitignore` | Ignores local `nginx-glance.zip` |

Live script after install: **`$HOME/bin/nginx-glance.sh`**

---

## Installation

`install.sh` runs **dependency checks first**, then copies the script.

```bash
git clone <repository-clone-url>
cd nginx-glance
./install.sh
```

Checks performed:

1. **Required CLI** — aborts with `apt install` hints if missing  
2. **nginx** — warns if binary not on PATH  
3. **`/etc/nginx/sites-enabled`** — warns if missing  
4. **`nginx.service`** — warns if unit not found  
5. **`kpackagetool6`** — noted when using `--plasmoid`

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
| `--json` | JSON for Plasma widget or automation |
| `--help` | Usage and environment variables |

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `NGINX_SITES_ENABLED` | `/etc/nginx/sites-enabled` | nginx site config directory |

### Examples

```bash
~/bin/nginx-glance.sh
~/bin/nginx-glance.sh --json
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json
```

### Parsing rules (read-only)

**`server_name`** — collected when valid; ignored when:

- `_` (catch-all)
- Wildcards (`*.example.com`)
- Regex (`~...`)
- Variables (`$hostname`)
- Empty tokens

Comments (`# ...`) are stripped before parsing.

**`listen`** — ports from e.g. `listen 80;`, `listen 443 ssl;`, `listen [::]:443 ssl;`, `listen 127.0.0.1:8080;`, `listen *:80;`

**`proxy_pass`** — `http(s)://host:port` only; skips `unix:`, upstream names without port, variables; defaults port 80 (http) / 443 (https).

---

## JSON output (widget)

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
  "domains": [ { "name": "example.com", "http": { "ok": true, "level": "ok", "line": "..." }, "https": { ... } } ],
  "ports": [ { "port": 443, "listening": true } ],
  "backends": [ { "target": "127.0.0.1:3000", "port": 3000, "listening": true } ],
  "system": { "cpu_load": "...", "memory": "...", "disk_root": "..." }
}
```

**Healthy domain** = HTTP and HTTPS both OK (2xx/3xx, including redirects).

---

## Dependencies

| Type | Items |
|------|--------|
| **Required (CLI)** | `bash`, `curl`, `systemctl`, `ss`, `awk`, `sed`, `grep`, `head`, `free`, `df` |
| **Recommended** | `nginx`, `/etc/nginx/sites-enabled`, `nginx.service` |
| **Plasmoid** | `kpackagetool6`, KDE Plasma 6 |

Typical install (Debian/Ubuntu):

```bash
sudo apt install nginx curl iproute2 procps coreutils systemd
# plasmoid dev tools (optional):
sudo apt install plasma-sdk
```

**No sudo** needed to run nginx-glance.

---

## Development and testing

```bash
bash -n nginx-glance.sh
bash -n install.sh
./nginx-glance.sh --text
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json
./install.sh
./install.sh --plasmoid
kpackagetool6 --type Plasma/Applet --install plasmoid
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

---

## Distribution zip (local)

A local archive can be built for offline copy (not tracked in git):

```bash
cd nginx-glance
zip -r nginx-glance.zip \
  README.md CHANGELOG.md nginx-glance.sh install.sh .gitignore \
  plasmoid testdata
```

`nginx-glance.zip` is listed in `.gitignore`.

---

## Design principles

| Does | Does not |
|------|----------|
| Read nginx config | Change nginx |
| `systemctl is-active` | Start/stop services |
| `curl -sI` to local URLs | Run certbot |
| `ss -ltn` for ports | Change `.env` or app code |
| Show system metrics | Expose secrets |
| Check dependencies at install | Require sudo for normal use |
| | Run `npm` |

Health checks use **`/`** per domain. Per-app systemd units are not checked — only `nginx.service` and `proxy_pass` ports.

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| Install aborts on dependencies | Install packages from `install.sh` hints |
| Widget: script missing | Run `./install.sh` |
| Widget: invalid JSON | Run `~/bin/nginx-glance.sh --json` in terminal |
| No domains listed | Check read access to `NGINX_SITES_ENABLED` |
| `kpackagetool6` missing | `sudo apt install plasma-sdk`; install plasmoid manually |

---

## Project history (summary)

| Milestone | Description |
|-----------|-------------|
| **v1.0** | Bash read-only status script, `install.sh`, terminal / Command Output use |
| **v1.1** | `--json`, Plasma 6 plasmoid, test fixtures, improved nginx parsing, dependency checks |
| **Docs** | English README, CHANGELOG, portable `$HOME/bin` install |
| **Privacy** | Generic README (no personal hostnames in repo); git history cleaned |

---

## Optional future work

- [ ] Custom health paths per domain
- [ ] Failure notifications
- [ ] Log history (cron/systemd timer)
- [ ] TLS certificate expiry (read-only)

---

## Quick reference

```bash
./install.sh
./install.sh --plasmoid
~/bin/nginx-glance.sh --text
~/bin/nginx-glance.sh --json
```

---

*KDE Plasma 6 for the native widget; terminal mode works on any Linux host with the listed tools.*
