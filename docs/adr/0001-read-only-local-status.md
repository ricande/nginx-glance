# ADR-0001: Read-only local status only

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

Nginx Glance runs on a personal server alongside live nginx sites and application services. Operators need visibility without risk of accidental changes during status checks.

## Decision

The tool is **strictly read-only**:

- Read nginx configuration files under `sites-enabled`
- Use `systemctl is-active` (no start/stop/reload)
- Use `curl -sI` for HTTP probes (no body uploads, no config APIs)
- Use `ss -ltn` for listening sockets
- Never run certbot, npm, or application deploy commands
- Never use `sudo` in normal operation

## Consequences

### Positive

- Safe to run from a desktop widget on a timer
- No coupling to deployment pipelines
- Clear mental model: observe, do not mutate

### Negative / trade-offs

- Cannot fix failures automatically
- Cannot reload nginx or restart apps from this tool
- Some checks (e.g. certificate expiry on disk) are out of scope unless added as separate read-only reads

## Alternatives considered

- **Admin script with reload** — rejected; increases blast radius
- **Full monitoring stack (Prometheus/Grafana)** — rejected for scope; user wanted a lightweight local glance
