# Changelog

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
