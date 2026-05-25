# Nginx Glance

Local status report for all sites handled by nginx. The script is meant for the terminal, KDE/Plasma widgets (e.g. Command Output), and quick troubleshooting — without changing nginx, systemd, certbot, `.env`, or application code.

**Repository:** GitHub — project name `nginx-glance` (use **Code → Clone** on the repo page for the URL).

---

## What this project is

**Nginx Glance** is a read-only Bash script that answers: *“Are my local domains and nginx up right now?”*

It:

- Reads nginx configuration from `/etc/nginx/sites-enabled/` (read-only)
- Checks `nginx.service`
- Tests HTTP and HTTPS for every discovered `server_name`
- Verifies nginx `listen` ports and any `proxy_pass` backends
- Shows simple system info (CPU load, memory, disk)
- Shows **no secrets** (no certificates, `.env`, passwords, or keys)

It is **not** a monitoring platform, not an infrastructure change, and not tied to a single application. All nginx sites are treated equally; backends are shown only when they exist as `proxy_pass` in the configuration.

### Example deployment

| Property | Typical value |
|----------|----------------|
| OS | Linux with systemd (e.g. Kubuntu, Debian, Ubuntu) |
| Reverse proxy | `nginx.service` (ports 80/443) |

Any site file under `/etc/nginx/sites-enabled/` with a `server_name` is checked automatically. Static sites need no `proxy_pass`; app backends appear when nginx proxies to `http://127.0.0.1:<port>`. App systemd units are **not** started or stopped by Nginx Glance — only `nginx.service` and backend ports are checked.

---

## Files and layout

| File | Role |
|------|------|
| `nginx-glance.sh` (in this folder) | **Working copy / source** — edit here |
| `install.sh` | Copies the script to `$HOME/bin` (or `INSTALL_DIR`) |
| `$HOME/bin/nginx-glance.sh` | **Live copy** — run in widget/terminal |

### Installation (fresh clone)

```bash
git clone <repository-clone-url>   # GitHub: Code → Clone
cd nginx-glance
./install.sh
# optional: INSTALL_DIR=~/.local/bin ./install.sh
```

### Update the live script (after source changes)

```bash
cd nginx-glance   # or your local clone
./install.sh
```

---

## Script output

```
Nginx Glance
============
<timestamp>
host: <hostname>

Nginx
-----
✅ nginx.service: active

Domains (HTTP)
--------------
✅ <domain>/: HTTP/1.1 ...

Domains (HTTPS)
---------------
✅ <domain>/: HTTP/1.1 ...

Ports (nginx listen)
--------------------
✅ port 80: listening
✅ port 443: listening

Backends (proxy_pass)        ← only if proxy exists in config
---------------------
✅ port 3000: listening
   → my-app: 127.0.0.1:3000
...

System
------
CPU load: ...
Memory: ...
Disk /: ...
```

### Status icons

| Icon | Meaning |
|------|---------|
| ✅ | OK — service active, port listening, or HTTP 2xx/3xx |
| ⚠️ | Response received but unexpected HTTP status (e.g. 4xx/5xx) |
| ❌ | No response, service inactive, or port not listening |

HTTP **301/302** count as OK (redirect = server is responding).

### Automatic discovery

| nginx source | Used for |
|--------------|----------|
| `server_name` | Domain list (HTTP/HTTPS check on `/`) |
| `listen` | Ports under “Ports (nginx listen)” |
| `proxy_pass` | App backends + port check |

New sites in `sites-enabled` are picked up on the next run. Catch-all `_` is filtered out.

---

## Usage

### Terminal

```bash
~/bin/nginx-glance.sh
# or: $HOME/bin/nginx-glance.sh
```

### KDE / Plasma (Command Output widget)

1. Right-click the desktop → **Add Widgets**
2. Search for **Command Output** or similar
3. Command:

   ```bash
   $HOME/bin/nginx-glance.sh
   ```

4. Refresh interval: **30–60 seconds**

### Requirements (tools on PATH)

`bash`, `curl`, `systemctl`, `ss`, `awk`, `free`, `df` — plus read access to `/etc/nginx/sites-enabled/` for the user running the script.

**Sudo is not required** for normal operation.

---

## Design principles and limits

Rules set at project start:

| Does | Does not |
|------|----------|
| Read nginx config | Change nginx |
| `systemctl is-active` (read-only) | Start/stop services |
| `curl -sI` to public URLs | Run certbot |
| `ss -ltn` for ports | Change `.env` or app code |
| Show system metrics | Show secrets or certificate contents |
| | Run `npm` |
| | Use `sudo` (unless absolutely necessary) |

Health checks use **`/`** for all domains. Redirects (301/302) still count as “responding”.

The script does **not** check separate systemd units per app (e.g. `my-app.service`) — only `nginx.service` plus any `proxy_pass` ports.

---

## Project history

### Step 1 — Inventory (read-only)

- Mapped host, tools, and active services
- Verified nginx and backend ports
- Listed all `server_name` values in nginx
- Tested HTTP/HTTPS with `curl` — no configuration changes

### Steps 2–4 — First script (`~/bin`)

- Created `~/bin/` and install script
- Built status script with service, URL, port, and system sections
- `chmod +x` and test runs

### Iterations after feedback

1. **Broader scope** — from a single-app focus to all nginx domains
2. **Dynamic ports** — removed hardcoded 3000/3001; ports from `listen` and `proxy_pass`
3. **Service section** — only `nginx.service` (no app-specific unit names in main logic)
4. **Domain discovery** — fixed reading `sites-enabled` (per file, not `grep -rh` on symlinks)
5. **Naming** — main script: `nginx-glance.sh` (single script file)
6. **Layout** — source in project folder, portable `install.sh` (`$HOME/bin`)
7. **GitHub** — published as `nginx-glance`

### Delivered

- Working local status script with no infrastructure changes
- KDE command-output widget compatibility
- Documentation (this README)
- Git repo with `nginx-glance.sh`, `install.sh`, `README.md`

---

## Remaining work

### Manual (user)

- [ ] **KDE widget** — add Command Output with `nginx-glance.sh` and chosen refresh interval
- [ ] **PATH (optional)** — add `~/bin` to PATH to run without a full path:
  ```bash
  # in ~/.bashrc or ~/.profile
  export PATH="$HOME/bin:$PATH"
  ```

### Optional improvements (not implemented)

- [x] **Git** — repository on GitHub
- [ ] **Custom health paths** — e.g. `/se` for some domains (config file, no nginx change)
- [ ] **App systemd checks** — optional section mapping `proxy_pass` port → known `.service` names (maintenance list)
- [ ] **Notifications** — on ❌: desktop notice, email, or webhook (extra script/cron)
- [ ] **Log history** — systemd timer or cron writing output to `~/logs/nginx-glance.log`
- [ ] **Desktop/panel integration** — `.desktop` file or Plasma data engine
- [ ] **Compact layout** — single-line mode for small panels
- [ ] **TLS/cert expiry** — read-only certificate date check (no certbot)

### Known limitations

- Domains must be active `server_name` entries in `sites-enabled` (commented lines ignored)
- `default` / `_` is not tested as a domain
- External DNS/CDN is not tested — `curl` uses names resolved on the server
- Short timeouts (5 s) may cause false ❌ under brief load

---

## Troubleshooting

| Problem | Possible cause | Action |
|---------|----------------|--------|
| No domains listed | Cannot read `/etc/nginx/sites-enabled/` | `ls -la /etc/nginx/sites-enabled/` as your user |
| ❌ on HTTPS but site works in browser | Local vs external DNS differs | Test `curl -sI https://domain/` on the server |
| ❌ proxy port | App service down | `systemctl status <app>.service` (manual, outside script) |
| ⚠️ HTTP 4xx/5xx | App or nginx rule | Check nginx error log and app logs |
| Widget shows nothing | Wrong command or not executable | `chmod +x ~/bin/nginx-glance.sh` |

---

## Quick reference

```bash
# Run status
~/bin/nginx-glance.sh

# Domains nginx knows about (manual)
grep -h server_name /etc/nginx/sites-enabled/* | grep -v '_'

# Is nginx active?
systemctl is-active nginx.service
```

---

## Related paths (server)

| Path | Contents |
|------|----------|
| `/etc/nginx/sites-enabled/` | Active nginx sites (symlinks) |
| `/etc/nginx/sites-available/` | Site config sources |
| `$HOME/bin/nginx-glance.sh` | Live script (installed via `install.sh`) |
| Clone of `nginx-glance` | Source, `install.sh`, this README |

---

*Last updated: 2026-05-25 — GitHub repo, portable install, `nginx-glance.sh` only as live script.*
