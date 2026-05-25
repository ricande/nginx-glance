# ADR-0002: Bash backend with `--text` and `--json` output

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

Users need terminal output and a KDE Plasma widget. The widget should not reimplement health logic in QML.

## Decision

- Single backend: **`nginx-glance.sh`** (Bash)
- **`--text`**: human-readable report (default), emoji status lines
- **`--json`**: structured output for the plasmoid and automation
- **`--help`**: usage and environment variables
- Dependencies limited to common CLI tools (no Python/Node runtime required)

## Consequences

### Positive

- One place to maintain check logic
- Terminal and widget stay in sync
- Easy to test with `NGINX_SITES_ENABLED=./testdata/...`

### Negative / trade-offs

- JSON built in Bash (manual escaping, no schema validator in-repo)
- Bash is less ergonomic than a typed language for complex parsing

## Alternatives considered

- **QML-only checks** — rejected; duplicates logic, harder to test
- **Python helper** — rejected; extra runtime dependency on servers
- **D-Bus to systemd/nginx APIs** — rejected; more moving parts, not needed for local glance
