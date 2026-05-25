# Backend (`nginx-glance.sh`)

## Entry points

```bash
nginx-glance.sh [--text|--json|--sample-json|--help]
```

| Flag | Behavior |
|------|----------|
| *(none)* | Same as `--text` |
| `--text` | Human-readable sections with ✅ ⚠️ ❌ |
| `--json` | Single JSON object on stdout; writes state cache |
| `--sample-json` | Lightweight sample JSON (waveform polling; uses cache + live sockets) |
| `--help` | Usage; exits 0 |

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_SITES_ENABLED` | `/etc/nginx/sites-enabled` | Directory of enabled site config files |
| `NGINX_GLANCE_CURL_TIMEOUT` | `2` | Per-request curl timeout in seconds (integer **1–30**) |
| `NGINX_ACCESS_LOG` | `/var/log/nginx/access.log` | Access log for per-domain activity in `--sample-json` (skipped if unreadable) |
| `NGINX_GLANCE_LOG_LINES` | `400` | Tail lines of access log scanned per sample |

Invalid or out-of-range `NGINX_GLANCE_CURL_TIMEOUT` values fall back to **2**.

Each HTTP probe uses:

```bash
curl -sI --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "$url"
```

Exit codes:

- `0` — completed (individual checks may still show failures in output)
- `1` — config directory missing
- `2` — unknown CLI argument

## Execution phases

1. **Discover** — domains, listen ports, proxy backends from config files
2. **Check** — nginx service, URLs, ports, system stats
3. **Emit** — format results as text or JSON

## Refresh latency (runtime)

Domain checks run **sequentially**. Worst-case HTTP phase duration is roughly:

```
domains × 2 protocols × NGINX_GLANCE_CURL_TIMEOUT
```

Example: 5 domains, timeout 2s → up to ~20s spent in curl alone (plus `ss`, `systemctl`, parsing).

The Plasma widget runs a **full** `--json` check about every **20 seconds** and **`--sample-json` every 500 ms**. Domain HTTP/HTTPS data updates only after a full run finishes; waveforms update on each sample (see [plasmoid.md](plasmoid.md)).

Lower timeout for snappier local panels:

```bash
NGINX_GLANCE_CURL_TIMEOUT=1 ~/bin/nginx-glance.sh --json
```

## Text output sections

1. Header (title, timestamp, host, config path)
2. Nginx (`nginx.service`)
3. Domains (HTTP) — grouped by apex domain, blank line between groups
4. Domains (HTTPS) — same order as HTTP
5. Ports (nginx listen)
6. Backends (proxy_pass) — `server_name` label + process/service hint; omitted if none
7. System (load, memory, disk)

## JSON schema

Top-level fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | Local time `YYYY-MM-DD HH:MM:SS` |
| `health_score` | number | 0–100 composite score (full check and sample) |
| `state` | string | `ok` \| `degraded` \| `error` |
| `host` | string | Short hostname |
| `config_path` | string | Value of `NGINX_SITES_ENABLED` |
| `nginx` | object | `service`, `status`, `ok` |
| `summary` | object | Aggregate counts |
| `domains` | array | Per-domain HTTP/HTTPS results |
| `ports` | array | Listen ports and listening state |
| `backends` | array | proxy_pass targets |
| `system` | object | `cpu_load`, `memory`, `disk_root` |

### `summary` fields

| Field | Meaning |
|-------|---------|
| `domains_total` | Count of discovered domains |
| `domains_healthy` | Both HTTP and HTTPS checks OK |
| `domains_unhealthy` | At least one protocol not OK |
| `ports_listening` | Listen ports with open socket |
| `ports_missing` | Listen ports not listening |
| `backends_ok` | Backend ports listening |
| `backends_missing` | Backend ports not listening |

### Backend entry

| Field | Description |
|-------|-------------|
| `target` | `host:port` from `proxy_pass` |
| `port` | TCP port number |
| `name` | `server_name`(s) from the same nginx `server` block (comma-separated if several) |
| `service` | Process name from `ss -ltnp` when visible, else a hint for well-known DB ports (e.g. 5432 → PostgreSQL) |
| `listening` | Whether the port accepts TCP connections locally |

### Domain entry

```json
{
  "name": "example.com",
  "http": { "ok": true, "level": "ok", "line": "HTTP/1.1 301 Moved Permanently" },
  "https": { "ok": true, "level": "ok", "line": "HTTP/1.1 200 OK" }
}
```

`level`: `ok` | `warn` | `error`

- **ok** — response line present and status matches 2xx/3xx
- **warn** — response line present but not 2xx/3xx
- **error** — no response line

### Port entry

```json
{ "port": 443, "listening": true }
```

### Backend entry (example)

```json
{
  "target": "127.0.0.1:3000",
  "port": 3000,
  "name": "app.example.com,www.example.com",
  "service": "next-server",
  "listening": true
}
```

## Dependencies (runtime)

`bash`, `curl`, `systemctl`, `ss`, `awk`, `sed`, `grep`, `head`, `free`, `df`

Checked at install time — see [install-and-dependencies.md](install-and-dependencies.md).

## State cache and sampling

After each full `--json` run, a cache file is written (default: `~/.cache/nginx-glance/state.json`) with summary counts, port lists, and per-domain `baseline` activity scores from the last HTTP/HTTPS check.

`--sample-json` is safe to run every **500 ms** (e.g. from the plasmoid waveform). It:

- Does **not** curl domains
- Reads summary domain counts from cache
- Re-checks `nginx.service` and whether cached listen/backend TCP ports are open (one `ss -ltn` snapshot)

Sample output includes `mode: "sample"`, `health_score`, `state`, `cache_valid`, `cache_age_sec`, `summary`, `ports_up` / `ports_total`, `backends_up` / `backends_total`, and `domain_activity`.

### `domain_activity` entry (sample only)

```json
{ "name": "example.com", "activity": 72 }
```

| Field | Description |
|-------|-------------|
| `name` | `server_name` from cache |
| `activity` | 0–100; blends cached **baseline** (HTTP/HTTPS OK) with recent hits in `NGINX_ACCESS_LOG` |

Baseline: both OK → 100; one OK → 55; neither → 15. If the domain string appears in the tailed access log, activity is boosted (capped at 100). Without a readable log, `activity` equals `baseline` (steady bars until traffic arrives).

### `health_score` weights (full and sample)

| Component | Weight |
|-----------|--------|
| nginx.service active | 30 |
| Domains healthy / total (from cache in sample) | 40 |
| Listen ports up / total (live in sample) | 15 |
| Backend ports up / total (live in sample) | 15 |

`state`: **error** if nginx down or score &lt; 40; **degraded** if score &lt; 85; else **ok**.

## Fast local testing

Parsing and JSON shape without real DNS (curl may fail quickly on fake domains):

```bash
NGINX_GLANCE_CURL_TIMEOUT=1 \
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled \
./nginx-glance.sh --json | python3 -m json.tool
```

## Testing without system nginx

```bash
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --json
```

## Related ADRs

- [ADR-0002](adr/0002-bash-backend-with-json-output.md)
- [ADR-0005](adr/0005-nginx-only-systemd-check.md)
- [ADR-0006](adr/0006-health-check-root-path.md)
