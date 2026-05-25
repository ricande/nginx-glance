# ADR-0004: Plasma 6 plasmoid as thin UI

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

A native desktop widget is desired on Kubuntu (KDE Plasma 6). Command Output widgets work but are generic and less polished.

## Decision

- Ship a **Plasma/Applet** under `plasmoid/`
- Target **Plasma API 6.0** (`X-Plasma-API-Minimum-Version: 6.0`)
- Widget runs **`$HOME/bin/nginx-glance.sh --json`** every 30 seconds
- Use `org.kde.plasma.plasma5support` executable DataSource for process output
- Compact view: summary counts and nginx status color
- Full view: per-domain HTTP/HTTPS, ports, backends, system line
- Install via `./install.sh --plasmoid` when `kpackagetool6` is available

## Consequences

### Positive

- Native look and feel on Plasma 6
- UI can evolve without changing check semantics
- Falls back to terminal / Command Output if plasmoid not installed

### Negative / trade-offs

- KDE-specific; not portable to GNOME/macOS without rewrite
- Requires installed script at `$HOME/bin/nginx-glance.sh`
- QML depends on Plasma/Kirigami versions

## Alternatives considered

- **Command Output only** — kept as supported path; plasmoid is additive
- **Python/Qt tray app** — rejected; extra dependency stack
- **Web dashboard** — rejected; scope creep, network exposure concerns
