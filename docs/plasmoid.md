# Plasma 6 plasmoid

## Package layout

```
plasmoid/
├── metadata.json          # KPlugin id, Plasma 6 API version
└── contents/ui/main.qml   # Widget entry (Plasma 6 default path)
```

| Field | Value |
|-------|--------|
| **Plugin Id** | `org.nginxglance.nginxglance` |
| **Name** | Nginx Glance |
| **Minimum Plasma** | 6.0 |
| **Entry QML** | `contents/ui/main.qml` (no `X-Plasma-MainScript` — Plasma 6 resolves this automatically) |
| **Expanded scroll** | `Flickable` (not `QQC2.ScrollView` — unavailable in applet loader) |

## UI design goals

The widget should feel **glanceable, calm, compact, and readable** on a desktop or panel:

- **Compact view** — one clear status dot and a short summary line (domains, ports, backends); timestamp subdued; “Updating…” while a run is in flight
- **Expanded view** — structured sections (nginx, domains, ports, backends, system), not a raw log dump; OK shown simply, problems show status text
- **No health logic in QML** — colors and counts come from backend JSON only

## Runtime behavior

1. On load, runs: `$HOME/bin/nginx-glance.sh --json` (single command string for the DataSource)
2. **Timer** requests a new run every **30 seconds** — only if the previous run has finished
3. Parses stdout as JSON; updates compact and full views

### Overlapping refreshes

`refreshRunning` prevents starting a new backend process while the previous executable job is still active. The timer fires every 30s, but `refreshStatus()` returns early until `onNewData` calls `finishRefresh()`.

### Compact view

- Status dot (nginx / error / missing script)
- Short summary: domains healthy/total, ports listening, backends ok
- “Updating…” during backend run
- Timestamp (muted)

### Full view

- Summary inline message
- `nginx.service` status
- Per-domain HTTP/HTTPS (OK label or status line)
- Listen ports and backends
- System line + host/timestamp footer

### Colors

| State | Kirigami color |
|-------|----------------|
| OK | `Theme.positiveTextColor` |
| Warn | `Theme.neutralTextColor` |
| Error / missing script | `Theme.negativeTextColor` |

## Refresh latency

| Layer | Interval / duration |
|-------|---------------------|
| Widget timer | 30 seconds between *attempted* runs |
| Backend runtime | ~`domains × 2 × NGINX_GLANCE_CURL_TIMEOUT` for curl (sequential) |
| Visible freshness | When JSON returns — may be later than the timer tick if the backend is still running |

Example: 7 domains, 2s timeout → up to ~28s curl time; the widget will not stack parallel runs.

Tune backend speed with `NGINX_GLANCE_CURL_TIMEOUT` (see [backend.md](backend.md)).

## Data source

Uses `org.kde.plasma.plasma5support` **executable** engine:

```qml
import QtCore

readonly property string homePath: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    // with file:// stripped; falls back to Qt.environment.HOME if needed
readonly property string commandSource: homePath + "/bin/nginx-glance.sh --json"
```

`Qt.environment.HOME` alone is **not** relied on in Plasma 6 QML — use `StandardPaths.HomeLocation` first.

`disconnectSource()` and `onNewData` `sourceName` comparisons use the **same** `commandSource` string.

| Exit code | UI message |
|-----------|------------|
| `127` | Script not found → run `./install.sh` |
| Other non-zero | Backend failure (exit code shown) |
| `0` | Parse JSON and update views |

## Installation

### Via install script (preferred)

```bash
./install.sh --plasmoid
```

Uses `kpackagetool6` or `kpackagetool-6` if available; otherwise prints manual commands.

### Manual

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

### Add to desktop

Right-click desktop → **Add Widgets** → search **Nginx Glance**

## Fast local testing

Backend only (widget uses the same JSON):

```bash
NGINX_GLANCE_CURL_TIMEOUT=1 \
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled \
~/bin/nginx-glance.sh --json | python3 -m json.tool
```

After QML changes:

```bash
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

## Development notes

- UI must stay thin: **no health logic in QML**
- JSON schema changes require updating `main.qml` and [backend.md](backend.md)
- Custom `INSTALL_DIR` → symlink to `$HOME/bin/nginx-glance.sh` or edit `commandSource` in QML

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Install ./install.sh” | Run installer from project clone |
| Invalid JSON | Run `~/bin/nginx-glance.sh --json` in terminal |
| Widget feels slow | Lower `NGINX_GLANCE_CURL_TIMEOUT`; fewer domains |
| Stale data | Normal if backend run exceeds 30s; wait for “Updating…” to clear |
| Widget empty | Check Plasma logs; verify script executable |

## Related ADR

- [ADR-0004](adr/0004-plasma6-plasmoid-thin-ui.md)
- [ADR-0002](adr/0002-bash-backend-with-json-output.md)
