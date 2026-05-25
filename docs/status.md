# Project status

Living overview of what is **done**, what was **fixed** (especially Plasma widget issues), and what is **left to do**. For release-by-release notes see [CHANGELOG.md](../CHANGELOG.md).

**Current version:** 1.3.1 (see [CHANGELOG](../CHANGELOG.md))

---

## Done (shipped)

### Backend (`nginx-glance.sh`)

| Area | Status |
|------|--------|
| Read-only discovery from `NGINX_SITES_ENABLED` | ✅ |
| `server_name`, `listen`, `proxy_pass` parsing | ✅ |
| HTTP/HTTPS checks on `/` per domain | ✅ |
| `nginx.service` via systemd | ✅ |
| Listen ports + backend port listening (`ss`) | ✅ |
| `--text`, `--json`, `--help` | ✅ |
| `NGINX_GLANCE_CURL_TIMEOUT` (1–30 s) | ✅ |
| Domain grouping by apex + alphabetical order | ✅ (since 1.3.0) |
| Backend labels: `name` from `server_name`, `service` from `ss`/known ports | ✅ (since 1.3.1) |

### Installer

| Area | Status |
|------|--------|
| Deploy to `$HOME/bin` (or `INSTALL_DIR`) | ✅ |
| Dependency checks (CLI, nginx, sites-enabled, unit) | ✅ |
| `./install.sh --plasmoid` via `kpackagetool6` | ✅ |

### Plasma 6 plasmoid

| Area | Status |
|------|--------|
| Compact summary (dot, domains/ports/backends counts) | ✅ |
| Expanded scrollable detail (domains, ports, backends, system) | ✅ |
| 30 s refresh; no overlapping backend runs | ✅ |
| Home path via `StandardPaths` | ✅ |
| Exit `127` → install hint; other errors → backend failure | ✅ |

### Documentation & packaging

| Area | Status |
|------|--------|
| `docs/` guides + ADRs 0001–0007 | ✅ |
| `testdata/nginx-sites-enabled/` | ✅ |
| Local `nginx-glance.zip` recipe (gitignored) | ✅ |

---

## Fixed (issues resolved)

### Plasma widget load & layout (2026-05-26)

| Symptom | Cause | Resolution |
|---------|--------|------------|
| `ScrollView is not a type` | `QQC2.ScrollView` / bare `ScrollView` not available in applet QML engine | `PlasmaExtras.Representation` + `Flickable` + `Column`; no `PC.ScrollView` in plasmoid |
| `Non-existent attached object` (line ~237) | `ScrollBar.vertical: PC.ScrollBar` on `Flickable` | Removed; scroll via wheel/trackpad |
| Extra content drawn over title | Compact and full views as duplicate root children + bad `ScrollView` layout | Inline `compactRepresentation` / `fullRepresentation` only; `contentHeight` on `Column` |
| Red status dot on startup | Empty JSON treated as nginx failure | Grey dot while loading (`isBusy`); green/red only with data |
| Thin `2026` text over title | Full timestamp rendered outside text column | `Updated HH:MM:SS` under summary in compact view |
| Widget not updating after `git pull` | Plasma caches QML; install does not run automatically | Documented: `./install.sh --plasmoid` + restart `plasma-plasmashell` or re-add widget |

### Backend & UX (earlier)

| Item | Resolution |
|------|------------|
| Overlapping plasmoid refreshes | `refreshRunning` + single `commandSource` |
| Wrong home path in Plasma 6 | `StandardPaths.HomeLocation` |
| Domains scattered in output | Apex grouping + sort (1.3.0) |
| Backends only showed `host:port` | `name` + `service` on backend entries (1.3.1) |

---

## Remaining / not planned yet

### Product ideas (from README roadmap)

| Item | Notes |
|------|--------|
| Custom health path per domain | Today: always `/` ([ADR-0006](adr/0006-health-check-root-path.md)) |
| Failure notifications | No alerting; would need external wrapper on `--json` |
| Log / history over time | Single snapshot only; no persistence |
| TLS certificate expiry (read-only) | Not implemented |

### Known limitations (by design)

| Limitation | Detail |
|------------|--------|
| No per-app systemd units | Only `nginx.service` ([ADR-0005](adr/0005-nginx-only-systemd-check.md)) |
| No `nginx -t` / config validation | Parse-only |
| Backends only from `proxy_pass` | Standalone DB ports (e.g. PostgreSQL on 5432) not listed unless proxied |
| Process names from `ss` | Often empty without elevated permissions; falls back to port hints (5432 → PostgreSQL, etc.) |
| Apex grouping heuristic | Last two labels (`example.com`); not a full public-suffix list |
| Sequential curl | Large domain lists × timeout can exceed 30 s widget interval |

### Optional improvements (not scheduled)

- [ ] Separate section for common local DB/service ports without `proxy_pass`
- [ ] Panel-optimized compact layout (horizontal form factor)
- [ ] Automated tests in CI (parsing fixtures + JSON schema)
- [ ] i18n for plasmoid strings (currently mixed EN UI + `qsTr` hooks)

---

## Upgrade checklist (operators)

After `git pull`:

```bash
cd nginx-glance
./install.sh              # updates ~/bin/nginx-glance.sh
./install.sh --plasmoid   # updates ~/.local/share/plasma/plasmoids/...
systemctl --user restart plasma-plasmashell.service   # or remove & re-add widget
```

Verify:

```bash
~/bin/nginx-glance.sh --text
~/bin/nginx-glance.sh --json | python3 -m json.tool
```

---

## Related

- [CHANGELOG.md](../CHANGELOG.md)
- [README.md](../README.md)
- [plasmoid.md](plasmoid.md) — widget behaviour and troubleshooting
- [backend.md](backend.md) — JSON schema including `backends[].name` / `service`
