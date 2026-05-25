# ADR-0007: Portable install to `$HOME/bin`

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

The project is published on GitHub and used on personal servers. Install paths should not hardcode a single username or require root for the script itself.

## Decision

- **`install.sh`** copies `nginx-glance.sh` to **`$HOME/bin/nginx-glance.sh`** by default
- Override with **`INSTALL_DIR=/path`** for e.g. `~/.local/bin`
- Plasmoid and docs reference **`$HOME/bin/nginx-glance.sh`**
- No legacy wrapper script names in the repository
- Dependency check runs at install time (see [install-and-dependencies.md](../install-and-dependencies.md))

## Consequences

### Positive

- Works for any user running `./install.sh`
- No sudo required for install (unless user chooses system paths)
- Widget command path is predictable

### Negative / trade-offs

- User must ensure `$HOME/bin` exists and is optional on PATH
- Plasmoid hardcodes home-relative script path (not `INSTALL_DIR` custom locations without manual QML edit)

## Alternatives considered

- **`/usr/local/bin` install** — rejected; needs root, less portable in docs
- **Symlink from repo** — rejected; clone path varies; bin copy is explicit
