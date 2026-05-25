# Backend (`nginx-glance.sh`)

## Entry points

```bash
nginx-glance.sh [--text|--json|--help]
```

| Flag | Behavior |
|------|----------|
| *(none)* | Same as `--text` |
| `--text` | Human-readable sections with ✅ ⚠️ ❌ |
| `--json` | Single JSON object on stdout |
| `--help` | Usage; exits 0 |

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_SITES_ENABLED` | `/etc/nginx/sites-enabled` | Directory of enabled site config files |
| `NGINX_GLANCE_CURL_TIMEOUT` | `2` | Per-request curl timeout in seconds (integer **1–30**) |

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

The Plasma widget **polls every 30 seconds**, but **fresh data appears only after the backend finishes**. If a run is still in progress, the widget skips starting another until the current run completes (see [plasmoid.md](plasmoid.md)).

Lower timeout for snappier local panels:

```bash
NGINX_GLANCE_CURL_TIMEOUT=1 ~/bin/nginx-glance.sh --json
```

## Text output sections

1. Header (title, timestamp, host, config path)
2. Nginx (`nginx.service`)
3. Domains (HTTP)
4. Domains (HTTPS)
5. Ports (nginx listen)
6. Backends (proxy_pass) — omitted if none
7. System (load, memory, disk)

## JSON schema

Top-level fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | Local time `YYYY-MM-DD HH:MM:SS` |
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

### Port / backend entry

```json
{ "port": 443, "listening": true }
{ "target": "127.0.0.1:3000", "port": 3000, "listening": true }
```

## Dependencies (runtime)

`bash`, `curl`, `systemctl`, `ss`, `awk`, `sed`, `grep`, `head`, `free`, `df`

Checked at install time — see [install-and-dependencies.md](install-and-dependencies.md).

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
