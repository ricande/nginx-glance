# ADR-0003: Discover sites from `sites-enabled`

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

nginx virtual hosts are enabled via symlinks in `/etc/nginx/sites-enabled/`. Operators add new sites there; the tool should pick them up without a maintained domain list.

## Decision

- Read all readable files in **`NGINX_SITES_ENABLED`** (default `/etc/nginx/sites-enabled`)
- Parse `server_name`, `listen`, and `proxy_pass` directives from those files
- Strip `#` comments before parsing
- Ignore catch-all and non-literal names (see [parsing.md](../parsing.md))
- Do not parse `nginx.conf` includes recursively (sites-enabled is the source of truth for vhosts)

## Consequences

### Positive

- New enabled sites appear on next run automatically
- Matches Debian/Ubuntu nginx layout
- Testable with `testdata/nginx-sites-enabled/`

### Negative / trade-offs

- Unusual layouts (only `conf.d/`, no sites-enabled) need `NGINX_SITES_ENABLED` override
- Duplicate `server_name` across files may produce duplicate checks
- Does not validate nginx syntax (`nginx -t` is out of scope)

## Alternatives considered

- **Hardcoded domain list** — rejected; high maintenance, project-specific
- **Query nginx API** — rejected; nginx has no standard status API without extra modules
- **Parse `nginx -T` dump** — rejected; requires sudo/root on many systems
