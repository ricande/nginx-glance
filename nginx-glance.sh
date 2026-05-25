#!/usr/bin/env bash
# Nginx Glance — read-only status for all nginx-backed domains.
set -u

NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}"
OUTPUT_MODE="text"
CURL_TIMEOUT=2

# Populated by full checks; used for cache write and health_score
BACKEND_NAMES=()
BACKEND_SERVICES=()
CACHE_FILE=""
SS_LISTEN_SNAPSHOT=""

init_curl_timeout() {
  local raw="${NGINX_GLANCE_CURL_TIMEOUT:-2}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -ge 1 ] && [ "$raw" -le 30 ]; then
    CURL_TIMEOUT="$raw"
  else
    CURL_TIMEOUT=2
  fi
}

# Collected check results (parallel arrays via newline-delimited stores)
DOMAINS=""
DOMAIN_HTTP_OK=()
DOMAIN_HTTP_LINE=()
DOMAIN_HTTP_LEVEL=()
DOMAIN_HTTPS_OK=()
DOMAIN_HTTPS_LINE=()
DOMAIN_HTTPS_LEVEL=()
LISTEN_PORTS=""
LISTEN_PORT_OK=()
BACKENDS=""
BACKEND_OK=()
NGINX_SVC_OK=false
NGINX_SVC_STATUS="unknown"
SYS_LOAD=""
SYS_MEM=""
SYS_DISK=""
HOSTNAME=""
TIMESTAMP=""

usage() {
  cat <<'EOF'
Nginx Glance — read-only local status for nginx-backed sites.

Usage:
  nginx-glance.sh [--text|--json|--help]

Options:
  --text         Human-readable output (default)
  --json         Full machine-readable JSON (curl per domain; writes state cache)
  --sample-json  Lightweight sample for waveform polling (no domain curl; uses cache)
  --help         Show this help

Environment:
  NGINX_SITES_ENABLED        Path to nginx sites-enabled directory
                             (default: /etc/nginx/sites-enabled)
  NGINX_GLANCE_CURL_TIMEOUT  Per-request curl timeout in seconds (1–30, default: 2)
  NGINX_ACCESS_LOG           Access log for per-domain activity in --sample-json
                             (default: /var/log/nginx/access.log, skip if unreadable)
  NGINX_GLANCE_LOG_LINES     Lines of access log to scan per sample (default: 400)

Examples:
  nginx-glance.sh
  nginx-glance.sh --json
  nginx-glance.sh --sample-json
  NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled nginx-glance.sh --json
EOF
}

cache_file_path() {
  local base="${XDG_CACHE_HOME:-$HOME/.cache}"
  printf '%s/nginx-glance/state.json' "$base"
}

capture_listen_snapshot() {
  SS_LISTEN_SNAPSHOT="$(ss -ltn 2>/dev/null | awk '{print $4}' || true)"
}

port_open_in_snapshot() {
  local port="$1"
  [ -n "$port" ] && [ -n "$SS_LISTEN_SNAPSHOT" ] && \
    printf '%s\n' "$SS_LISTEN_SNAPSHOT" | grep -qE "[:.]${port}([[:space:]]|$)"
}

compute_health_score() {
  local nginx_pts=0 domain_pts=0 port_pts=0 backend_pts=0
  local dt dl pt bt healthy

  $NGINX_SVC_OK && nginx_pts=30 || nginx_pts=0

  dt="${CACHE_DOMAINS_TOTAL:-0}"
  healthy="${CACHE_DOMAINS_HEALTHY:-0}"
  if [ "$dt" -gt 0 ] 2>/dev/null; then
    domain_pts=$((healthy * 40 / dt))
  else
    domain_pts=40
  fi

  pt="${CACHE_PORTS_TOTAL:-0}"
  dl="${CACHE_PORTS_LISTENING:-0}"
  if [ "$pt" -gt 0 ] 2>/dev/null; then
    port_pts=$((dl * 15 / pt))
  else
    port_pts=15
  fi

  bt="${CACHE_BACKENDS_TOTAL:-0}"
  bl="${CACHE_BACKENDS_OK:-0}"
  if [ "$bt" -gt 0 ] 2>/dev/null; then
    backend_pts=$((bl * 15 / bt))
  else
    backend_pts=15
  fi

  echo $((nginx_pts + domain_pts + port_pts + backend_pts))
}

health_state_from_score() {
  local score="$1"
  if ! $NGINX_SVC_OK || [ "$score" -lt 40 ]; then
    printf 'error'
  elif [ "$score" -lt 85 ]; then
    printf 'degraded'
  else
    printf 'ok'
  fi
}

write_state_cache() {
  local cache_dir port backend i first=true
  CACHE_FILE="$(cache_file_path)"
  cache_dir="$(dirname "$CACHE_FILE")"
  mkdir -p "$cache_dir" || return 0

  local domain_count=0 healthy=0 unhealthy=0
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    domain_count=$((domain_count + 1))
    i=$((domain_count - 1))
    if [ "${DOMAIN_HTTP_OK[$i]:-0}" = "1" ] && [ "${DOMAIN_HTTPS_OK[$i]:-0}" = "1" ]; then
      healthy=$((healthy + 1))
    else
      unhealthy=$((unhealthy + 1))
    fi
  done <<< "$DOMAINS"
  unhealthy=$((domain_count - healthy))

  local port_ok port_total=0 backend_ok backend_total=0
  port_ok="$(count_ok LISTEN_PORT_OK)"
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    port_total=$((port_total + 1))
  done <<< "$LISTEN_PORTS"

  backend_ok="$(count_ok BACKEND_OK)"
  while IFS= read -r backend; do
    [ -n "$backend" ] || continue
    backend_total=$((backend_total + 1))
  done <<< "$BACKENDS"

  CACHE_DOMAINS_TOTAL=$domain_count
  CACHE_DOMAINS_HEALTHY=$healthy
  CACHE_PORTS_TOTAL=$port_total
  CACHE_PORTS_LISTENING=$port_ok
  CACHE_BACKENDS_TOTAL=$backend_total
  CACHE_BACKENDS_OK=$backend_ok

  local score state cached_epoch
  score="$(compute_health_score)"
  state="$(health_state_from_score "$score")"
  cached_epoch="$(date +%s)"

  {
    printf '{'
    printf '"cached_at":"%s",' "$(json_escape "$TIMESTAMP")"
    printf '"cached_at_epoch":%s,' "$cached_epoch"
    printf '"health_score":%s,' "$score"
    printf '"state":"%s",' "$(json_escape "$state")"
    printf '"nginx_ok":%s,' "$(json_bool "$($NGINX_SVC_OK && echo 1 || echo 0)")"
    printf '"summary":{'
    printf '"domains_total":%s,"domains_healthy":%s,"domains_unhealthy":%s,' \
      "$domain_count" "$healthy" "$unhealthy"
    printf '"ports_listening":%s,"ports_missing":%s,' \
      "$port_ok" "$((port_total - port_ok))"
    printf '"backends_ok":%s,"backends_missing":%s' \
      "$backend_ok" "$((backend_total - backend_ok))"
    printf '},'
    printf '"listen_ports":['
    first=true
    while IFS= read -r port; do
      [ -n "$port" ] || continue
      $first || printf ','
      first=false
      printf '%s' "$port"
    done <<< "$LISTEN_PORTS"
    printf '],'
    printf '"backend_ports":['
    first=true
    while IFS= read -r backend; do
      [ -n "$backend" ] || continue
      $first || printf ','
      first=false
      printf '%s' "${backend##*:}"
    done <<< "$BACKENDS"
    printf '],'
    printf '"domains":['
    first=true
    i=0
    while IFS= read -r domain; do
      [ -n "$domain" ] || continue
      $first || printf ','
      first=false
      baseline=15
      if [ "${DOMAIN_HTTP_OK[$i]:-0}" = "1" ] && [ "${DOMAIN_HTTPS_OK[$i]:-0}" = "1" ]; then
        baseline=100
      elif [ "${DOMAIN_HTTP_OK[$i]:-0}" = "1" ] || [ "${DOMAIN_HTTPS_OK[$i]:-0}" = "1" ]; then
        baseline=55
      fi
      printf '{"name":"%s","baseline":%s}' "$(json_escape "$domain")" "$baseline"
      i=$((i + 1))
    done <<< "$DOMAINS"
    printf ']'
    printf '}\n'
  } >"$CACHE_FILE"
}

emit_domain_activity_array() {
  local cache_file first=true
  cache_file="$(cache_file_path)"

  if ! $CACHE_VALID || [ ! -f "$cache_file" ] || ! command -v python3 >/dev/null 2>&1; then
    printf '[]'
    return
  fi

  NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/var/log/nginx/access.log}"
  NGINX_GLANCE_LOG_LINES="${NGINX_GLANCE_LOG_LINES:-400}"

  python3 - "$cache_file" "$NGINX_ACCESS_LOG" "$NGINX_GLANCE_LOG_LINES" <<'PY'
import json, sys, subprocess

cache_path, log_path, line_limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(cache_path) as f:
    data = json.load(f)
domains = data.get("domains") or []

log_lines = []
try:
    out = subprocess.run(
        ["tail", "-n", str(line_limit), log_path],
        capture_output=True, text=True, timeout=1, check=False,
    )
    if out.returncode == 0:
        log_lines = out.stdout.splitlines()
except (OSError, subprocess.TimeoutExpired):
    log_lines = []

items = []
for entry in domains:
    name = entry.get("name") or ""
    if not name:
        continue
    baseline = int(entry.get("baseline") or 0)
    hits = sum(1 for ln in log_lines if name in ln)
    if hits > 0:
        bump = min(100, hits * 8)
        activity = (baseline * 35 + bump * 65) // 100
    else:
        activity = baseline
    activity = max(5, min(100, activity))
    items.append({"name": name, "activity": activity})

print(json.dumps(items, separators=(",", ":")))
PY
}

load_state_cache() {
  CACHE_FILE="$(cache_file_path)"
  CACHE_VALID=false
  CACHE_AGE_SEC=-1
  CACHE_DOMAINS_TOTAL=0
  CACHE_DOMAINS_HEALTHY=0
  CACHE_PORTS_TOTAL=0
  CACHE_PORTS_LISTENING=0
  CACHE_BACKENDS_TOTAL=0
  CACHE_BACKENDS_OK=0
  CACHE_LISTEN_PORTS=""
  CACHE_BACKEND_PORTS=""

  [ -f "$CACHE_FILE" ] || return 1

  if command -v python3 >/dev/null 2>&1; then
    eval "$(python3 - "$CACHE_FILE" <<'PY'
import json, sys, time
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
s = d.get("summary") or {}
epoch = int(d.get("cached_at_epoch") or 0)
age = int(time.time() - epoch) if epoch else -1
ports = d.get("listen_ports") or []
backs = d.get("backend_ports") or []
print(f"CACHE_VALID=true")
print(f"CACHE_AGE_SEC={age}")
print(f"CACHE_DOMAINS_TOTAL={int(s.get('domains_total') or 0)}")
print(f"CACHE_DOMAINS_HEALTHY={int(s.get('domains_healthy') or 0)}")
print(f"CACHE_PORTS_TOTAL={len(ports)}")
print(f"CACHE_PORTS_LISTENING={int(s.get('ports_listening') or 0)}")
print(f"CACHE_BACKENDS_TOTAL={len(backs)}")
print(f"CACHE_BACKENDS_OK={int(s.get('backends_ok') or 0)}")
print("CACHE_LISTEN_PORTS=" + ",".join(str(p) for p in ports))
print("CACHE_BACKEND_PORTS=" + ",".join(str(p) for p in backs))
PY
)"
    return 0
  fi
  return 1
}

run_sample_checks() {
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
  load_state_cache || true
  check_service_state nginx.service
  capture_listen_snapshot

  local port backend live_ports=0 live_backends=0 pt=0 bt=0

  if [ -n "${CACHE_LISTEN_PORTS:-}" ]; then
    IFS=',' read -ra _listen_ports <<< "$CACHE_LISTEN_PORTS"
    for port in "${_listen_ports[@]}"; do
      [ -n "$port" ] || continue
      pt=$((pt + 1))
      port_open_in_snapshot "$port" && live_ports=$((live_ports + 1))
    done
  fi

  if [ -n "${CACHE_BACKEND_PORTS:-}" ]; then
    IFS=',' read -ra _backend_ports <<< "$CACHE_BACKEND_PORTS"
    for port in "${_backend_ports[@]}"; do
      [ -n "$port" ] || continue
      bt=$((bt + 1))
      port_open_in_snapshot "$port" && live_backends=$((live_backends + 1))
    done
  fi

  CACHE_PORTS_TOTAL=$pt
  CACHE_PORTS_LISTENING=$live_ports
  CACHE_BACKENDS_TOTAL=$bt
  CACHE_BACKENDS_OK=$live_backends
}

emit_sample_json() {
  local score state
  run_sample_checks
  score="$(compute_health_score)"
  state="$(health_state_from_score "$score")"

  printf '{'
  printf '"mode":"sample",'
  printf '"timestamp":"%s",' "$(json_escape "$TIMESTAMP")"
  printf '"health_score":%s,' "$score"
  printf '"state":"%s",' "$(json_escape "$state")"
  printf '"nginx_ok":%s,' "$(json_bool "$($NGINX_SVC_OK && echo 1 || echo 0)")"
  printf '"cache_valid":%s,' "$(json_bool "$($CACHE_VALID && echo 1 || echo 0)")"
  printf '"cache_age_sec":%s,' "${CACHE_AGE_SEC:--1}"
  printf '"summary":{'
  local du=0
  du=$((CACHE_DOMAINS_TOTAL - CACHE_DOMAINS_HEALTHY))
  [ "$du" -lt 0 ] && du=0
  printf '"domains_total":%s,"domains_healthy":%s,"domains_unhealthy":%s,' \
    "${CACHE_DOMAINS_TOTAL:-0}" \
    "${CACHE_DOMAINS_HEALTHY:-0}" \
    "$du"
  printf '"ports_listening":%s,"ports_missing":%s,' \
    "${CACHE_PORTS_LISTENING:-0}" \
    "$((CACHE_PORTS_TOTAL - CACHE_PORTS_LISTENING))"
  printf '"backends_ok":%s,"backends_missing":%s' \
    "${CACHE_BACKENDS_OK:-0}" \
    "$((CACHE_BACKENDS_TOTAL - CACHE_BACKENDS_OK))"
  printf '},'
  printf '"ports_up":%s,"ports_total":%s,' \
    "${CACHE_PORTS_LISTENING:-0}" "${CACHE_PORTS_TOTAL:-0}"
  printf '"backends_up":%s,"backends_total":%s,' \
    "${CACHE_BACKENDS_OK:-0}" "${CACHE_BACKENDS_TOTAL:-0}"
  printf '"domain_activity":'
  emit_domain_activity_array
  printf '}\n'
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

json_bool() {
  [ "${1:-0}" = "1" ] && printf 'true' || printf 'false'
}

strip_comments() {
  sed 's/#.*//'
}

nginx_site_files() {
  local f
  [ -d "$NGINX_SITES_ENABLED" ] || return 0
  for f in "$NGINX_SITES_ENABLED"/*; do
    [ -r "$f" ] || continue
    printf '%s\n' "$f"
  done
}

is_valid_server_name() {
  local name="$1"
  [ -n "$name" ] || return 1
  [ "$name" = "_" ] && return 1
  [[ "$name" == *'$'* ]] && return 1
  [[ "$name" == *'*'* ]] && return 1
  [[ "$name" == ~* ]] && return 1
  return 0
}

# Apex key for grouping: example.com, www.example.com, api.example.com → example.com
domain_apex_key() {
  local d="$1"
  local host="${d#www.}"
  local IFS='.'
  local -a parts=()
  read -ra parts <<< "$host"
  local n=${#parts[@]}
  if [ "$n" -le 2 ]; then
    printf '%s\n' "$host"
  else
    printf '%s\n' "${parts[$((n - 2))]}.${parts[$((n - 1))]}"
  fi
}

# Sort rank within a group: apex (0), www (1), other subdomains (2)
domain_sort_rank() {
  local d="$1"
  local apex
  apex="$(domain_apex_key "$d")"
  if [ "$d" = "$apex" ]; then
    echo 0
  elif [ "$d" = "www.${apex}" ]; then
    echo 1
  else
    echo 2
  fi
}

# Order: by apex alphabetically, then apex → www → subdomains A–Z
sort_domains_ordered() {
  local domain apex rank
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    apex="$(domain_apex_key "$domain")"
    rank="$(domain_sort_rank "$domain")"
    printf '%s\t%s\t%s\n' "$apex" "$rank" "$domain"
  done | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3 | cut -f3-
}

discover_domains() {
  local f line part raw=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*server_name[[:space:]]+ ]] || continue
      line="${line#*server_name}"
      line="${line%;*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      for part in $line; do
        is_valid_server_name "$part" && printf '%s\n' "$part"
      done
    done < <(strip_comments < "$f")
  done < <(nginx_site_files) | LC_ALL=C sort -u | sort_domains_ordered
}

parse_listen_port() {
  local line="$1"
  local rest port
  line="${line#*listen}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*;//;s/[[:space:]]*$//')"
  [ -z "$line" ] && return 1
  [[ "$line" == unix:* ]] && return 1

  if [[ "$line" =~ \[::\]:([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$line" =~ ^[^:]+:([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$line" =~ ^\*:([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$line" =~ ^([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$line" =~ ^([0-9]+)[[:space:]] ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

discover_listen_ports() {
  local f line port
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*listen[[:space:]] ]] || continue
      port="$(parse_listen_port "$line" || true)"
      [ -n "${port:-}" ] && printf '%s\n' "$port"
    done < <(strip_comments < "$f")
  done < <(nginx_site_files) | sort -nu
}

parse_proxy_backend() {
  local line="$1"
  local target scheme hostport host port
  [[ "$line" =~ ^[[:space:]]*proxy_pass[[:space:]]+([^[:space:];]+) ]] || return 1
  target="${BASH_REMATCH[1]}"
  [[ "$target" == *'$'* ]] && return 1
  [[ "$target" == unix:* ]] && return 1
  [[ "$target" =~ ^https?:// ]] || return 1

  scheme="${target%%://*}"
  hostport="${target#*://}"
  hostport="${hostport%%/*}"
  hostport="${hostport%%\?*}"

  [[ "$hostport" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]] || \
  [[ "$hostport" =~ ^localhost:[0-9]+$ ]] || \
  [[ "$hostport" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]] || return 1

  host="${hostport%%:*}"
  port="${hostport##*:}"
  if [ "$host" = "$port" ]; then
    if [ "$scheme" = "https" ]; then
      port="443"
    else
      port="80"
    fi
  fi

  printf '%s:%s\n' "$host" "$port"
}

known_port_service() {
  case "$1" in
    5432|5433) echo "PostgreSQL" ;;
    3306|3307) echo "MySQL/MariaDB" ;;
    6379) echo "Redis" ;;
    27017) echo "MongoDB" ;;
    1433) echo "MSSQL" ;;
    1521) echo "Oracle" ;;
    9200) echo "Elasticsearch" ;;
    5672) echo "RabbitMQ" ;;
    *) return 1 ;;
  esac
}

listener_process_name() {
  local port="$1"
  local line proc
  line="$(ss -ltnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | head -1 || true)"
  [ -z "$line" ] && return 1
  if [[ "$line" =~ users:\(\(\"([^\"]+)\" ]]; then
    proc="${BASH_REMATCH[1]}"
    # ss output may truncate long command names mid-token (strip trailing " (…")
    if [[ "$proc" == *" ("* ]] && [[ "$proc" != *")"* ]]; then
      proc="${proc%% (*}"
    fi
    proc="$(echo "$proc" | sed 's/[[:space:]]*$//')"
    [ -n "$proc" ] && printf '%s\n' "$proc" && return 0
  fi
  return 1
}

backend_service_label() {
  local port="$1"
  local label
  label="$(listener_process_name "$port" 2>/dev/null || true)"
  [ -n "$label" ] && printf '%s\n' "$label" && return 0
  known_port_service "$port" || true
}

merge_name_list() {
  local existing="$1"
  local add="$2"
  local part combined="" seen="|"
  local -a parts=()
  [ -n "$existing" ] && IFS=',' read -ra parts <<< "$existing"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$part" ] && continue
    [[ "$seen" == *"|${part}|"* ]] && continue
    seen="${seen}${part}|"
    combined="${combined:+$combined, }$part"
  done
  IFS=',' read -ra parts <<< "$add"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$part" ] && continue
    [[ "$seen" == *"|${part}|"* ]] && continue
    seen="${seen}${part}|"
    combined="${combined:+$combined, }$part"
  done
  printf '%s\n' "$combined"
}

# Prints: target<TAB>names (comma-separated server_name from same server block)
discover_proxy_backends() {
  local f line backend part block_label merged
  declare -A backend_names=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local -a block_names=()
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*server[[:space:]]*\{ ]]; then
        block_names=()
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]*server_name[[:space:]]+ ]]; then
        block_names=()
        line="${line#*server_name}"
        line="${line%;*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        for part in $line; do
          is_valid_server_name "$part" && block_names+=("$part")
        done
        continue
      fi
      [[ "$line" =~ ^[[:space:]]*proxy_pass[[:space:]] ]] || continue
      backend="$(parse_proxy_backend "$line" || true)"
      [ -z "${backend:-}" ] && continue
      if [ "${#block_names[@]}" -gt 0 ]; then
        block_label="$(IFS=','; echo "${block_names[*]}")"
      else
        block_label=""
      fi
      if [ -n "${backend_names[$backend]:-}" ]; then
        backend_names[$backend]="$(merge_name_list "${backend_names[$backend]}" "$block_label")"
      else
        backend_names[$backend]="$block_label"
      fi
    done < <(strip_comments < "$f")
  done < <(nginx_site_files)

  for backend in "${!backend_names[@]}"; do
    printf '%s\t%s\n' "$backend" "${backend_names[$backend]}"
  done | LC_ALL=C sort -t "$(printf '\t')" -k1,1
}

check_service_state() {
  local name="$1"
  local status
  status="$(systemctl is-active "$name" 2>/dev/null || true)"
  NGINX_SVC_STATUS="${status:-unknown}"
  [ "$NGINX_SVC_STATUS" = "active" ] && NGINX_SVC_OK=true || NGINX_SVC_OK=false
}

url_level_from_line() {
  local line="$1"
  if [ -z "$line" ]; then
    echo "error"
  elif echo "$line" | grep -qE 'HTTP/[0-9.]+ 2[0-9][0-9]|HTTP/[0-9.]+ 3[0-9][0-9]'; then
    echo "ok"
  else
    echo "warn"
  fi
}

check_url_line() {
  local url="$1"
  curl -sI \
    --connect-timeout "$CURL_TIMEOUT" \
    --max-time "$CURL_TIMEOUT" \
    "$url" 2>/dev/null | tr -d '\r' | head -1 || true
}

check_port_listening() {
  local port="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
}

run_checks() {
  local domain port backend line level i ok_count
  local http_line https_line

  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
  HOSTNAME="$(hostname -s 2>/dev/null || hostname)"

  check_service_state nginx.service

  DOMAINS="$(discover_domains)"
  DOMAIN_HTTP_OK=()
  DOMAIN_HTTP_LINE=()
  DOMAIN_HTTP_LEVEL=()
  DOMAIN_HTTPS_OK=()
  DOMAIN_HTTPS_LINE=()
  DOMAIN_HTTPS_LEVEL=()

  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    http_line="$(check_url_line "http://${domain}/")"
    https_line="$(check_url_line "https://${domain}/")"
    level="$(url_level_from_line "$http_line")"
    DOMAIN_HTTP_LINE+=("$http_line")
    DOMAIN_HTTP_LEVEL+=("$level")
    [ "$level" = "ok" ] && DOMAIN_HTTP_OK+=(1) || DOMAIN_HTTP_OK+=(0)

    level="$(url_level_from_line "$https_line")"
    DOMAIN_HTTPS_LINE+=("$https_line")
    DOMAIN_HTTPS_LEVEL+=("$level")
    [ "$level" = "ok" ] && DOMAIN_HTTPS_OK+=(1) || DOMAIN_HTTPS_OK+=(0)
  done <<< "$DOMAINS"

  LISTEN_PORTS="$(discover_listen_ports)"
  LISTEN_PORT_OK=()
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    check_port_listening "$port" && LISTEN_PORT_OK+=(1) || LISTEN_PORT_OK+=(0)
  done <<< "$LISTEN_PORTS"

  BACKENDS=""
  BACKEND_NAMES=()
  BACKEND_SERVICES=()
  BACKEND_OK=()
  while IFS=$'\t' read -r backend backend_name; do
    [ -n "$backend" ] || continue
    BACKENDS="${BACKENDS:+$BACKENDS$'\n'}$backend"
    BACKEND_NAMES+=("${backend_name:-}")
    port="${backend##*:}"
    BACKEND_SERVICES+=("$(backend_service_label "$port" || true)")
    check_port_listening "$port" && BACKEND_OK+=(1) || BACKEND_OK+=(0)
  done < <(discover_proxy_backends)

  SYS_LOAD="$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo 'n/a')"
  SYS_MEM="$(free -h 2>/dev/null | awk '/Mem:/ {print $3 " used / " $2 " total"}' || echo 'n/a')"
  SYS_DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}' || echo 'n/a')"
}

count_ok() {
  local arr_name="$1"
  local -n arr="$arr_name"
  local n=0 i
  for i in "${!arr[@]}"; do
    [ "${arr[$i]}" = "1" ] && n=$((n + 1))
  done
  echo "$n"
}

emit_text() {
  local domain port backend i n_domains domain_total http_ok https_ok

  echo "Nginx Glance"
  echo "============"
  echo "$TIMESTAMP"
  echo "host: $HOSTNAME"
  echo "config: $NGINX_SITES_ENABLED"
  echo

  echo "Nginx"
  echo "-----"
  if $NGINX_SVC_OK; then
    echo "✅ nginx.service: active"
  else
    echo "❌ nginx.service: $NGINX_SVC_STATUS"
  fi
  echo

  echo "Domains (HTTP)"
  echo "--------------"
  i=0
  {
    local prev_apex="" cur_apex=""
    while IFS= read -r domain; do
      [ -n "$domain" ] || continue
      cur_apex="$(domain_apex_key "$domain")"
      if [ -n "$prev_apex" ] && [ "$cur_apex" != "$prev_apex" ]; then
        echo
      fi
      prev_apex="$cur_apex"
      line="${DOMAIN_HTTP_LINE[$i]:-}"
      level="${DOMAIN_HTTP_LEVEL[$i]:-error}"
      case "$level" in
        ok)   echo "✅ ${domain}/: ${line:-no response}" ;;
        warn) echo "⚠️  ${domain}/: ${line:-no response}" ;;
        *)    echo "❌ ${domain}/: no response" ;;
      esac
      i=$((i + 1))
    done <<< "$DOMAINS"
  }
  echo

  echo "Domains (HTTPS)"
  echo "---------------"
  i=0
  {
    local prev_apex="" cur_apex=""
    while IFS= read -r domain; do
      [ -n "$domain" ] || continue
      cur_apex="$(domain_apex_key "$domain")"
      if [ -n "$prev_apex" ] && [ "$cur_apex" != "$prev_apex" ]; then
        echo
      fi
      prev_apex="$cur_apex"
      line="${DOMAIN_HTTPS_LINE[$i]:-}"
      level="${DOMAIN_HTTPS_LEVEL[$i]:-error}"
      case "$level" in
        ok)   echo "✅ ${domain}/: ${line:-no response}" ;;
        warn) echo "⚠️  ${domain}/: ${line:-no response}" ;;
        *)    echo "❌ ${domain}/: no response" ;;
      esac
      i=$((i + 1))
    done <<< "$DOMAINS"
  }
  echo

  echo "Ports (nginx listen)"
  echo "--------------------"
  i=0
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    if [ "${LISTEN_PORT_OK[$i]:-0}" = "1" ]; then
      echo "✅ port $port: listening"
    else
      echo "❌ port $port: not listening"
    fi
    i=$((i + 1))
  done <<< "$LISTEN_PORTS"
  echo

  if [ -n "$BACKENDS" ]; then
    echo "Backends (proxy_pass)"
    echo "---------------------"
    i=0
    while IFS= read -r backend; do
      [ -n "$backend" ] || continue
      port="${backend##*:}"
      name="${BACKEND_NAMES[$i]:-}"
      service="${BACKEND_SERVICES[$i]:-}"
      label="$port"
      [ -n "$name" ] && label="${name} (port ${port})"
      [ -n "$service" ] && label="${label} · ${service}"
      if [ "${BACKEND_OK[$i]:-0}" = "1" ]; then
        echo "✅ ${label}: listening"
      else
        echo "❌ ${label}: not listening"
      fi
      echo "   → ${backend}"
      i=$((i + 1))
    done <<< "$BACKENDS"
    echo
  fi

  echo "System"
  echo "------"
  echo "CPU load: $SYS_LOAD"
  echo "Memory: $SYS_MEM"
  echo "Disk /: $SYS_DISK"
}

emit_json() {
  local domain port backend i first=true
  local domain_count http_ok https_ok healthy unhealthy
  local port_ok port_missing backend_ok backend_missing

  domain_count=0
  healthy=0
  unhealthy=0
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    domain_count=$((domain_count + 1))
    i=$((domain_count - 1))
    if [ "${DOMAIN_HTTP_OK[$i]:-0}" = "1" ] && [ "${DOMAIN_HTTPS_OK[$i]:-0}" = "1" ]; then
      healthy=$((healthy + 1))
    else
      unhealthy=$((unhealthy + 1))
    fi
  done <<< "$DOMAINS"

  port_ok="$(count_ok LISTEN_PORT_OK)"
  port_missing=0
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    port_missing=$((port_missing + 1))
  done <<< "$LISTEN_PORTS"
  port_missing=$((port_missing - port_ok))

  backend_ok="$(count_ok BACKEND_OK)"
  backend_missing=0
  while IFS= read -r backend; do
    [ -n "$backend" ] || continue
    backend_missing=$((backend_missing + 1))
  done <<< "$BACKENDS"
  backend_missing=$((backend_missing - backend_ok))

  CACHE_DOMAINS_TOTAL=$domain_count
  CACHE_DOMAINS_HEALTHY=$healthy
  CACHE_PORTS_TOTAL=$((port_ok + port_missing))
  CACHE_PORTS_LISTENING=$port_ok
  CACHE_BACKENDS_TOTAL=$((backend_ok + backend_missing))
  CACHE_BACKENDS_OK=$backend_ok
  local health_score health_state
  health_score="$(compute_health_score)"
  health_state="$(health_state_from_score "$health_score")"

  printf '{'
  printf '"timestamp":"%s",' "$(json_escape "$TIMESTAMP")"
  printf '"health_score":%s,' "$health_score"
  printf '"state":"%s",' "$(json_escape "$health_state")"
  printf '"host":"%s",' "$(json_escape "$HOSTNAME")"
  printf '"config_path":"%s",' "$(json_escape "$NGINX_SITES_ENABLED")"
  if $NGINX_SVC_OK; then
    printf '"nginx":{"service":"nginx.service","status":"%s","ok":true},' "$(json_escape "$NGINX_SVC_STATUS")"
  else
    printf '"nginx":{"service":"nginx.service","status":"%s","ok":false},' "$(json_escape "$NGINX_SVC_STATUS")"
  fi
  printf '"summary":{'
  printf '"domains_total":%s,"domains_healthy":%s,"domains_unhealthy":%s,' \
    "$domain_count" "$healthy" "$unhealthy"
  printf '"ports_listening":%s,"ports_missing":%s,' "$port_ok" "$port_missing"
  printf '"backends_ok":%s,"backends_missing":%s' "$backend_ok" "$backend_missing"
  printf '},'

  printf '"domains":['
  first=true
  i=0
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    $first || printf ','
    first=false
    printf '{'
    printf '"name":"%s",' "$(json_escape "$domain")"
    printf '"http":{"ok":%s,"level":"%s","line":"%s"},' \
      "$(json_bool "${DOMAIN_HTTP_OK[$i]:-0}")" \
      "$(json_escape "${DOMAIN_HTTP_LEVEL[$i]:-error}")" \
      "$(json_escape "${DOMAIN_HTTP_LINE[$i]:-}")"
    printf '"https":{"ok":%s,"level":"%s","line":"%s"}' \
      "$(json_bool "${DOMAIN_HTTPS_OK[$i]:-0}")" \
      "$(json_escape "${DOMAIN_HTTPS_LEVEL[$i]:-error}")" \
      "$(json_escape "${DOMAIN_HTTPS_LINE[$i]:-}")"
    printf '}'
    i=$((i + 1))
  done <<< "$DOMAINS"
  printf '],'

  printf '"ports":['
  first=true
  i=0
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    $first || printf ','
    first=false
    printf '{"port":%s,"listening":%s}' "$port" "$(json_bool "${LISTEN_PORT_OK[$i]:-0}")"
    i=$((i + 1))
  done <<< "$LISTEN_PORTS"
  printf '],'

  printf '"backends":['
  first=true
  i=0
  while IFS= read -r backend; do
    [ -n "$backend" ] || continue
    $first || printf ','
    first=false
    printf '{"target":"%s","port":%s,"name":"%s","service":"%s","listening":%s}' \
      "$(json_escape "$backend")" "${backend##*:}" \
      "$(json_escape "${BACKEND_NAMES[$i]:-}")" \
      "$(json_escape "${BACKEND_SERVICES[$i]:-}")" \
      "$(json_bool "${BACKEND_OK[$i]:-0}")"
    i=$((i + 1))
  done <<< "$BACKENDS"
  printf '],'

  printf '"system":{"cpu_load":"%s","memory":"%s","disk_root":"%s"}' \
    "$(json_escape "$SYS_LOAD")" \
    "$(json_escape "$SYS_MEM")" \
    "$(json_escape "$SYS_DISK")"
  printf '}\n'
  write_state_cache
}

parse_args() {
  case "${1:-}" in
    ""|--text) OUTPUT_MODE="text" ;;
    --json) OUTPUT_MODE="json" ;;
    --sample-json) OUTPUT_MODE="sample-json" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
}

main() {
  parse_args "${1:-}"
  if [ "$OUTPUT_MODE" = "sample-json" ]; then
    emit_sample_json
    return
  fi
  if [ ! -d "$NGINX_SITES_ENABLED" ]; then
    echo "nginx-glance: directory not found: $NGINX_SITES_ENABLED" >&2
    exit 1
  fi
  init_curl_timeout
  run_checks
  case "$OUTPUT_MODE" in
    text) emit_text ;;
    json) emit_json ;;
  esac
}

main "$@"
