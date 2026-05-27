# Plasma 6 plasmoid

![Expanded Nginx Glance widget](../images/plasmoid-overview.png)

*Example: domain HTTP/HTTPS checks, port listen state, proxy backends, and system footer (local host).*

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
| **Expanded scroll** | `Flickable` + `Column` (`contentHeight` bound — avoids stacked-overlap in `ScrollView`/`ColumnLayout`) |
| **Representations** | Inline `compactRepresentation` / `fullRepresentation` only (no extra root `Item` siblings) |

## UI design goals

The widget should feel **glanceable, calm, compact, and readable** on a desktop or panel:

- **Compact view** — one clear status dot and a short summary line (domains, ports, backends); `Updated HH:MM:SS` under the summary (not over the title); grey dot while loading
- **Expanded view** — structured sections (nginx, domains, ports, backends, system), not a raw log dump; OK shown simply, problems show status text
- **No health logic in QML** — colors and counts come from backend JSON only

## Runtime behavior

1. On load, runs full check: `$HOME/bin/nginx-glance.sh --json`
2. **Full refresh** every **20 seconds** (only if the previous full run has finished)
3. **Waveform sample** every **500 ms** via `$HOME/bin/nginx-glance.sh --sample-json` (cheap; uses state cache)
4. Parses JSON; ring buffers for global health (~**120** samples) and per-domain activity (~**80** samples each)
5. Two executable commands: `--json` (full) and `--sample-json` (waveforms only — never runs full check twice per second)

### Overlapping refreshes

`refreshRunning` / `sampleRunning` prevent overlapping executable jobs. Full refresh waits until the previous `--json` completes; samples use `--sample-json` only.

### Compact view

- Status dot (uses live `state` from sampler when available)
- Short summary: domains healthy/total, ports listening, backends ok
- **Health %** and **bar sparkline** from `health_score` samples (not network traffic)
- Sparkline auto-scales so a steady score still shows visible bars; label **steady** when flat
- Colors: green = ok, neutral = degraded, red = error
- “Updating…” during full backend run
- `Updated HH:MM:SS` under summary (full timestamp in expanded footer)

### Full view

- Vertically stacked sections inside a `Flickable` (scroll when content exceeds widget size)
- Summary line under the title (not `InlineMessage`, to avoid overlap with headings)
- `nginx.service` status
- Per-domain HTTP/HTTPS (OK label or status line) with **activity sparkline**
  - Newest bar anchored at the **right edge** of the waveform zone; older samples appear to the **left** (toward the domain name)
  - Left **text column** (~38% of row width): bold domain name, HTTP, HTTPS — fixed margin so bars never draw over labels
  - Waveform zone uses `Layout.fillWidth` — **stretches and shrinks** when the widget is resized
  - Activity from `domain_activity` in `--sample-json` (access log hits + health baseline)
- Listen ports and backends (site **name**, target, **service** hint, up/down)
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
| Full refresh | 20 seconds between *attempted* full `--json` runs |
| Waveform sample | 500 ms `--sample-json` (no domain curl) |
| Backend runtime (full only) | ~`domains × 2 × NGINX_GLANCE_CURL_TIMEOUT` for curl (sequential) |
| Visible freshness | Summary/domain data updates on full run; waveform updates on each sample |

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
./install.sh --plasmoid
```

`git pull` alone does not update the installed widget. Plasma may keep old QML in memory until you reload:

```bash
systemctl --user restart plasma-plasmashell.service
```

Or remove and re-add the widget on the desktop.

## Development notes

- UI must stay thin: **no health logic in QML**
- JSON schema changes require updating `main.qml` and [backend.md](backend.md)
- Custom `INSTALL_DIR` → symlink to `$HOME/bin/nginx-glance.sh` or edit `commandSource` in QML

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Install ./install.sh” | Run installer from project clone |
| Invalid JSON | Run `~/bin/nginx-glance.sh --json` in terminal |
| `ScrollView is not a type` (old message) | Upgrade plasmoid + restart plasmashell — see [status.md](status.md) |
| Layout overlap / text on title | Fixed in 1.2.5+; reinstall plasmoid and reload shell |
| Widget feels slow | Lower `NGINX_GLANCE_CURL_TIMEOUT`; fewer domains |
| Stale data | Normal if backend run exceeds 30s; wait for loading to clear |
| Widget empty | Check Plasma logs; verify script executable |
| `git pull` but no UI change | Run `./install.sh --plasmoid` and restart `plasma-plasmashell` |

## Related

- [status.md](status.md) — fixed widget issues and upgrade checklist
- [ADR-0004](adr/0004-plasma6-plasmoid-thin-ui.md)
- [ADR-0002](adr/0002-bash-backend-with-json-output.md)
