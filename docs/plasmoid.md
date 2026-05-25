# Plasma 6 plasmoid

## Package layout

```
plasmoid/
├── metadata.json          # KPlugin id, Plasma 6 API version
└── contents/ui/main.qml   # Widget UI
```

| Field | Value |
|-------|--------|
| **Plugin Id** | `org.nginxglance.nginxglance` |
| **Name** | Nginx Glance |
| **Minimum Plasma** | 6.0 |
| **Main script** | `ui/main.qml` |

## Runtime behavior

1. On load, runs executable: `$HOME/bin/nginx-glance.sh --json`
2. **Timer** retriggers every **30 seconds**
3. Parses stdout as JSON
4. Updates compact and full representations

### Compact view

- Title + status dot (nginx ok / error / script missing)
- Summary line: domains healthy/total, ports listening, backends ok
- Timestamp

### Full view

- `nginx.service` status
- Per-domain HTTP and HTTPS lines (color by `level`)
- Listen ports
- proxy_pass backends
- System line (CPU, memory, disk)
- Host + timestamp footer

### Colors

| State | Kirigami color |
|-------|----------------|
| OK | `Theme.positiveTextColor` |
| Warn | `Theme.neutralTextColor` |
| Error / missing script | `Theme.negativeTextColor` |

## Data source

Uses `org.kde.plasma.plasma5support` **executable** engine:

```qml
execSource.connectSource(scriptPath, ["--json"])
```

`scriptPath` = `Qt.environment.HOME + "/bin/nginx-glance.sh"`

If exit code `127` or failure with empty stdout → show install hint (`./install.sh`).

## Installation

### Via install script (preferred)

```bash
./install.sh --plasmoid
```

Uses `kpackagetool6` or `kpackagetool-6` if available; otherwise prints manual commands.

### Manual

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
# upgrade after changes:
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

### Add to desktop

Right-click desktop → **Add Widgets** → search **Nginx Glance**

## Development notes

- UI must stay thin: **no health logic in QML**
- JSON schema changes require updating `main.qml` bindings and [backend.md](backend.md)
- Custom `INSTALL_DIR` installs need a symlink or QML path edit (see [ADR-0007](adr/0007-portable-install-to-home-bin.md))

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Install ./install.sh” | Run installer from project clone |
| Invalid JSON | Run `~/bin/nginx-glance.sh --json` in terminal |
| Widget empty | Check Plasma logs; verify script executable |
| Stale data | Default 30s refresh; replug widget |

## Related ADR

- [ADR-0004](adr/0004-plasma6-plasmoid-thin-ui.md)
- [ADR-0002](adr/0002-bash-backend-with-json-output.md)
