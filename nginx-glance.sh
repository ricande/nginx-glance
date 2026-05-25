#!/usr/bin/env bash
# Nginx Glance — read-only status for all nginx-backed domains.
set -u

NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}"
OUTPUT_MODE="text"
CURL_TIMEOUT=2

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
  --text   Human-readable output (default)
  --json   Machine-readable JSON for Plasma widgets
  --help   Show this help

Environment:
  NGINX_SITES_ENABLED        Path to nginx sites-enabled directory
                             (default: /etc/nginx/sites-enabled)
  NGINX_GLANCE_CURL_TIMEOUT  Per-request curl timeout in seconds (1–30, default: 2)

Examples:
  nginx-glance.sh
  nginx-glance.sh --json
  NGINX_SITES_ENABLED=./testdata/nginx-sites-enabled nginx-glance.sh --json
EOF
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

  printf '{'
  printf '"timestamp":"%s",' "$(json_escape "$TIMESTAMP")"
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
}

parse_args() {
  case "${1:-}" in
    ""|--text) OUTPUT_MODE="text" ;;
    --json) OUTPUT_MODE="json" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
}

main() {
  parse_args "${1:-}"
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
