# Nginx Glance — documentation

Index of project documentation. Start with the [root README](../README.md) for quick start; use this folder for deeper detail.

## Guides

| Document | Description |
|----------|-------------|
| [architecture.md](architecture.md) | Components, data flow, boundaries |
| [backend.md](backend.md) | `nginx-glance.sh` modes, JSON schema, runtime |
| [parsing.md](parsing.md) | How nginx config is read and filtered |
| [plasmoid.md](plasmoid.md) | KDE Plasma 6 widget package |
| [install-and-dependencies.md](install-and-dependencies.md) | `install.sh`, dependencies, deployment |

## Architecture Decision Records (ADR)

| ADR | Title |
|-----|--------|
| [0001](adr/0001-read-only-local-status.md) | Read-only local status only |
| [0002](adr/0002-bash-backend-with-json-output.md) | Bash backend with `--text` and `--json` |
| [0003](adr/0003-discover-from-sites-enabled.md) | Discover sites from `sites-enabled` |
| [0004](adr/0004-plasma6-plasmoid-thin-ui.md) | Plasma 6 plasmoid as thin UI |
| [0005](adr/0005-nginx-only-systemd-check.md) | Check `nginx.service` only, not per-app units |
| [0006](adr/0006-health-check-root-path.md) | Health checks use `/` for all domains |
| [0007](adr/0007-portable-install-to-home-bin.md) | Portable install to `$HOME/bin` |

New ADRs: copy [adr/template.md](adr/template.md), use the next number, add a row to the table above.

## Related

- [CHANGELOG.md](../CHANGELOG.md) — release notes
- [testdata/](../testdata/nginx-sites-enabled/) — sample configs for parsing tests
