# nginx config parsing

Nginx Glance does **not** run `nginx -t` or include full config resolution. It scans files in `NGINX_SITES_ENABLED` line by line after comment stripping.

## Preprocessing

```bash
sed 's/#.*//'
```

- Inline comments removed
- Empty lines ignored by directive matchers

Files must be **readable** by the user running the script.

## `server_name`

### Collected

Literal hostnames on lines matching:

```nginx
server_name example.com www.example.com;
```

Each token is validated separately.

### Ignored

| Pattern | Example | Reason |
|---------|---------|--------|
| Catch-all | `_` | Default server placeholder |
| Wildcard | `*.example.com` | Not a concrete probe target |
| Regex | `~^www\.example\.com$` | Not supported in Bash probe |
| Variable | `$hostname` | Resolved only inside nginx |
| Empty | *(whitespace only)* | Invalid |

### Implementation

Function: `is_valid_server_name` in `nginx-glance.sh`

## `listen`

### Supported forms

| Config line | Port extracted |
|-------------|----------------|
| `listen 80;` | 80 |
| `listen 443 ssl;` | 443 |
| `listen [::]:443 ssl;` | 443 |
| `listen 127.0.0.1:8080;` | 8080 |
| `listen *:80;` | 80 |

### Skipped

- `listen unix:/path/to.sock;` — no TCP port

Function: `parse_listen_port`

Duplicate ports across files are deduplicated (`sort -nu`).

## `proxy_pass`

### Supported

| Form | Backend recorded |
|------|------------------|
| `proxy_pass http://127.0.0.1:3000;` | `127.0.0.1:3000` |
| `proxy_pass http://localhost:3001;` | `localhost:3001` |
| `proxy_pass https://127.0.0.1:8443;` | `127.0.0.1:8443` |
| `proxy_pass http://127.0.0.1;` | port **80** (http default) |
| `proxy_pass https://127.0.0.1;` | port **443** (https default) |

Host must match `host:port` with numeric port or localhost/name with explicit port.

### Skipped

| Form | Reason |
|------|--------|
| `proxy_pass http://my_upstream;` | No host:port |
| `proxy_pass http://$backend;` | Variable |
| `proxy_pass unix:...` | Unix socket |
| Paths only | `proxy_pass http://127.0.0.1/app/;` — path after host breaks simple parser |

Function: `parse_proxy_backend`

Health of a backend = **TCP listen check** on the port via `ss`, not HTTP to the upstream.

## Test fixtures

| File | Exercises |
|------|-----------|
| `example-static` | Multiple `server_name`, varied `listen` |
| `app-proxy` | http/https proxy_pass, localhost |
| `ignored-names` | `_`, wildcard, regex, `$var` |
| `skipped-proxy` | upstream name, unix, variable |

Run:

```bash
NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled ./nginx-glance.sh --text
```

## Limitations

- No `include` recursion into other directories
- No `map` / `split_clients` awareness
- Multiple `server` blocks append to the same discovery sets
- `default_server` flag on `listen` is not interpreted separately

## Related ADR

- [ADR-0003](adr/0003-discover-from-sites-enabled.md)
