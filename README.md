# Nginx Glance

Local, read-only status for sites handled by nginx. Use it in a **terminal**, a **Command Output** widget, or the included **KDE Plasma 6 plasmoid** — without changing nginx, systemd, certbot, `.env`, or application code.

**Repository:** GitHub — project name `nginx-glance` (use **Code → Clone** on the repo page for the URL).

See [CHANGELOG.md](CHANGELOG.md) for version history.

**Full documentation:** [docs/](docs/README.md) — architecture, parsing, plasmoid, install, and [ADRs](docs/adr/).

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

High-level: Bash backend → `--text` (terminal) or `--json` (Plasma widget). Details: [docs/architecture.md](docs/architecture.md).

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

Runs `$HOME/bin/nginx-glance.sh --json` every 30 seconds — compact summary and an expanded domain list (domains grouped and sorted; see [parsing.md](docs/parsing.md)).

After upgrading the widget: `./install.sh --plasmoid`, then restart `plasma-plasmashell` or re-add the widget (`git pull` alone is not enough).

---

## Project layout

| Path | Role |
|------|------|
| `nginx-glance.sh` | Backend collector (`--text` / `--json` / `--help`) |
| `install.sh` | Installs script; checks dependencies; optional `--plasmoid` |
| `plasmoid/metadata.json` | Plasma applet metadata |
| `plasmoid/contents/ui/main.qml` | Widget UI |
| `testdata/nginx-sites-enabled/` | Sample nginx configs for offline tests |
| `docs/` | Architecture, guides, [ADRs](docs/adr/) |
| `README.md` | Quick start (this file) |
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

Dependency checks run first — see [docs/install-and-dependencies.md](docs/install-and-dependencies.md).

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
| `NGINX_GLANCE_CURL_TIMEOUT` | `2` | Per-request curl timeout in seconds (1–30) |

### Examples

```bash
~/bin/nginx-glance.sh
~/bin/nginx-glance.sh --json
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json
```

Parsing rules: [docs/parsing.md](docs/parsing.md). JSON schema: [docs/backend.md](docs/backend.md).

---

## Development and testing

```bash
bash -n nginx-glance.sh
bash -n install.sh
./nginx-glance.sh --text
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json

# Fast JSON check (1s curl timeout per request)
NGINX_GLANCE_CURL_TIMEOUT=1 \
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled \
./nginx-glance.sh --json | python3 -m json.tool

./install.sh
./install.sh --plasmoid
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

Widget polls every **30s**; backend runtime depends on domain count and `NGINX_GLANCE_CURL_TIMEOUT` — see [docs/backend.md](docs/backend.md) and [docs/plasmoid.md](docs/plasmoid.md).

---

## Distribution zip (local)

```bash
zip -r nginx-glance.zip README.md CHANGELOG.md docs nginx-glance.sh install.sh .gitignore plasmoid testdata
```

`nginx-glance.zip` is in `.gitignore`.

---

## Design principles

Read-only, local-first, no sudo. Rationale: [docs/adr/](docs/adr/).

---

## Documentation index

| Topic | Document |
|-------|----------|
| Overview | [docs/README.md](docs/README.md) |
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Backend / JSON | [docs/backend.md](docs/backend.md) |
| Config parsing | [docs/parsing.md](docs/parsing.md) |
| Plasma widget | [docs/plasmoid.md](docs/plasmoid.md) |
| Install & deps | [docs/install-and-dependencies.md](docs/install-and-dependencies.md) |
| Decisions (ADR) | [docs/adr/](docs/adr/) |

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
