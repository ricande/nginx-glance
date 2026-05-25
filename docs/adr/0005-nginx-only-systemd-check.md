# ADR-0005: Check `nginx.service` only, not per-app systemd units

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

Many nginx vhosts proxy to app services (Node, etc.) with their own `.service` units. Mapping every `proxy_pass` port to a systemd unit name is fragile and site-specific.

## Decision

- Report **`nginx.service`** state via `systemctl is-active` only
- Infer app health via **`proxy_pass` target ports** (`ss -ltn` listening check)
- Do not maintain a table of `tidvind.service`-style unit names in the script

## Consequences

### Positive

- Generic across static sites and reverse proxies
- No per-project configuration in the repo
- Port down = backend problem visible without naming units

### Negative / trade-offs

- Cannot show “unit failed but port still open” edge cases
- Operators diagnose app issues with `systemctl status` manually

## Alternatives considered

- **Check all related .service files** — rejected; requires curated mapping per host
- **systemd cgroup from port** — rejected; complex, not portable in Bash
