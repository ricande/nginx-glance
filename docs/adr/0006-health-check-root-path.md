# ADR-0006: Health checks use `/` for all domains

- **Status:** Accepted
- **Date:** 2026-05-25

## Context

Applications expose different entry paths (`/`, `/se`, `/api/health`). Per-site path configuration adds maintenance and was tied to specific projects in early versions.

## Decision

- Probe **`http://<domain>/`** and **`https://<domain>/`** for every discovered `server_name`
- Treat **301/302** as healthy (redirect means the stack responded)
- Treat **2xx/3xx** status lines from `curl -sI` as OK in summary logic

## Consequences

### Positive

- One rule for all vhosts
- Works for static sites and apps that redirect `/` → locale path
- Simple JSON domain model

### Negative / trade-offs

- `/` may 404 while `/api/health` is fine — reported as warn/error
- Custom paths would need a future config file (see optional roadmap)

## Alternatives considered

- **Per-domain path map in repo** — rejected; not generic for GitHub distribution
- **Follow redirects with curl `-L` for final status** — not chosen; first-line status of redirect is enough for “responds”
