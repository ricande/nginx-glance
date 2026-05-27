# Changelog

## Unreleased

### Added
- `docs/images/plasmoid-overview.png` — screenshot of expanded plasmoid in README and [docs/plasmoid.md](docs/plasmoid.md)

## 1.5.0 — 2026-05-26

### Added
- Per-domain **activity sparklines** in expanded plasmoid view (newest bar on the **right**, history scrolls **left** toward the site name)
- `--sample-json` field `domain_activity[]` — per-domain `activity` 0–100 from cache baseline + nginx access log hits (`NGINX_ACCESS_LOG`, `NGINX_GLANCE_LOG_LINES`)
- State cache includes `domains[]` with `name` and `baseline` for sampling
- Compact plasmoid: bar sparkline for global `health_score` (auto-scaled; “steady” when flat)

### Changed
- Expanded domain row layout: ~38% left column for name/HTTP/HTTPS, waveform zone fills remaining width (scales with widget resize)
- Plasmoid sampling docs and troubleshooting aligned with bar sparklines (not Canvas)

## 1.4.0 — 2026-05-26

### Added
- `--sample-json` — lightweight sampler (no domain curl): `health_score`, `state`, cached summary, live nginx + port/backend socket checks
- State cache at `$XDG_CACHE_HOME/nginx-glance/state.json` (written on each full `--json` run)
- Full JSON includes `health_score` and `state`
- Plasmoid: global health sparkline (~120 samples), 500 ms sampling; full refresh every 20 s

### Changed
- Plasmoid no longer runs full `--json` on the same interval as the waveform (avoids duplicate heavy checks)

## 1.3.1 — 2026-05-26

### Added
- Backend entries include `name` (from nginx `server_name` in the same `server` block as `proxy_pass`) and `service` (process from `ss -ltnp` or well-known port hint)
- Plasmoid expanded view: backend name + target/service row

### Changed
- Text backends section shows `name (port N) · service` when available
- Docs: [docs/status.md](docs/status.md) — project status, fixes, and remaining work

## 1.3.0 — 2026-05-26

### Changed
- Domains grouped by registrable apex (`example.com`, `www.example.com`, subdomains together), sorted A–Z within each group
- Text output: blank line between domain groups in HTTP/HTTPS sections

## 1.2.5 — 2026-05-26

### Fixed
- Plasmoid: inline `compactRepresentation` / `fullRepresentation` (no overlapping root children)
- Plasmoid: expanded view uses `Flickable` + `Column` with `contentHeight` (no `ScrollView` / invalid `ScrollBar` attachments)
- Plasmoid: grey status dot while loading (not red before data arrives)
- Plasmoid: compact timestamp under summary (`Updated HH:MM:SS`), not over the title

### Changed
- Docs: plasmoid install reload (`plasmashell` restart) and layout notes

## 1.2.4 — 2026-05-26

### Fixed
- Plasmoid: expanded view uses `Flickable` instead of `ScrollView` (Plasma 6 applet loader; superseded by 1.2.5 layout)

## 1.2.3 — 2026-05-26

### Fixed
- Plasmoid: use `QQC2.ScrollView` (did not fix Plasma 6 loader — superseded by Flickable)

## 1.2.2 — 2026-05-26

### Fixed
- Plasmoid: exit `127` only shows install hint; other non-zero exits show backend failure
- Plasmoid: resolve home via `StandardPaths.HomeLocation` (Plasma 6), not only `Qt.environment.HOME`
- README: `NGINX_GLANCE_CURL_TIMEOUT` in Environment table

## 1.2.1 — 2026-05-25

### Changed
- Plasmoid: single `commandSource` string for executable DataSource; `refreshRunning` prevents overlapping runs
- Plasmoid UI polish: glanceable compact layout; expanded view less log-like
- `NGINX_GLANCE_CURL_TIMEOUT` (default 2s, range 1–30); curl uses `--connect-timeout` and `--max-time`
- Docs: refresh latency, fast test command, Plasma 6 metadata note
- Removed `X-Plasma-MainScript` from `metadata.json` (Plasma 6 uses `contents/ui/main.qml`)

## 1.2.0 — 2026-05-25

### Added
- **`docs/`** — architecture, backend, parsing, plasmoid, install guides
- **ADRs 0001–0007** — recorded design decisions under `docs/adr/`
- ADR template for future decisions

### Changed
- README links to `docs/` (detailed content moved out of root README)

## 1.1.0 — 2026-05-25

### Added
- **`--json`** output for KDE Plasma 6 plasmoid and automation
- **`--text`** and **`--help`** CLI modes
- **Plasma 6 plasmoid** (`plasmoid/`) — compact + expanded views, 30s refresh
- **`install.sh --plasmoid`** via `kpackagetool6` (graceful fallback with instructions)
- **Dependency checks** in `install.sh` (CLI tools, nginx, sites-enabled, nginx.service)
- **`testdata/nginx-sites-enabled/`** for offline parsing tests
- Configurable **`NGINX_SITES_ENABLED`**

### Improved
- nginx config parsing: strip comments, filter invalid `server_name` values
- `listen` port discovery (IPv4/IPv6, bind address, `*:port`)
- `proxy_pass` discovery (http/https defaults, skip unix/upstreams/variables)
- README in English with terminal + widget workflows

### Project
- Single-script design: `$HOME/bin/nginx-glance.sh` only (no legacy wrappers)
- Portable install: `INSTALL_DIR`, `$HOME/bin` default
- `.gitignore` for local `nginx-glance.zip`

## 1.0.0 — 2026-05-25

### Added
- Initial read-only Bash status script for all nginx-backed domains
- `install.sh` to deploy to `$HOME/bin`
- Terminal and Command Output widget usage
- GitHub repository
