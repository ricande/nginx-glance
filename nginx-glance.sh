#!/usr/bin/env bash
# Nginx Glance — read-only status for all nginx-backed domains.
set -u

check_service() {
  local name="$1"
  local status
  status="$(systemctl is-active "$name" 2>/dev/null || true)"

  if [ "$status" = "active" ]; then
    echo "✅ $name: active"
  else
    echo "❌ $name: ${status:-unknown}"
  fi
}

check_url() {
  local label="$1"
  local url="$2"
  local line
  line="$(curl -sI --max-time 5 "$url" 2>/dev/null | tr -d '\r' | head -1 || true)"

  if echo "$line" | grep -qE 'HTTP/[0-9.]+ 2[0-9][0-9]|HTTP/[0-9.]+ 3[0-9][0-9]'; then
    echo "✅ $label: $line"
  elif [ -n "$line" ]; then
    echo "⚠️  $label: $line"
  else
    echo "❌ $label: no response"
  fi
}

check_port() {
  local port="$1"
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
    echo "✅ port $port: listening"
  else
    echo "❌ port $port: not listening"
  fi
}

discover_domains() {
  local f
  [ -d /etc/nginx/sites-enabled ] || return 0
  for f in /etc/nginx/sites-enabled/*; do
    [ -r "$f" ] || continue
    grep -E '^[[:space:]]*server_name[[:space:]]+' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*server_name[[:space:]]+//;s/[[:space:]]*;//' \
      | tr ' ' '\n'
  done | grep -vE '^_$' | grep -v '^$' | sort -u
}

discover_listen_ports() {
  local f line port
  [ -d /etc/nginx/sites-enabled ] || return 0
  for f in /etc/nginx/sites-enabled/*; do
    [ -r "$f" ] || continue
    while IFS= read -r line; do
      port=""
      [[ "$line" =~ listen[[:space:]]+([0-9]+) ]] && port="${BASH_REMATCH[1]}"
      [[ "$line" =~ listen[[:space:]]+\[\:\:\]:([0-9]+) ]] && port="${BASH_REMATCH[1]}"
      [ -n "$port" ] && echo "$port"
    done < <(grep -E '^[[:space:]]*listen[[:space:]]+' "$f" 2>/dev/null || true)
  done | sort -nu
}

discover_proxy_backends() {
  local f line site port addr
  [ -d /etc/nginx/sites-enabled ] || return 0
  for f in /etc/nginx/sites-enabled/*; do
    [ -r "$f" ] || continue
    site="$(basename "$f")"
    while IFS= read -r line; do
      if [[ "$line" =~ proxy_pass[[:space:]]+https?://([^:;/]+):?([0-9]*) ]]; then
        addr="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        [ -z "$port" ] && port="80"
        echo "${site}|${addr}:${port}"
      fi
    done < <(grep -E '^[[:space:]]*proxy_pass[[:space:]]+' "$f" 2>/dev/null || true)
  done | sort -u
}

echo "Nginx Glance"
echo "============"
date '+%Y-%m-%d %H:%M:%S'
echo "host: $(hostname -s 2>/dev/null || hostname)"
echo

echo "Nginx"
echo "-----"
check_service nginx.service
echo

echo "Domains (HTTP)"
echo "--------------"
while IFS= read -r domain; do
  [ -n "$domain" ] || continue
  check_url "${domain}/" "http://${domain}/"
done < <(discover_domains)
echo

echo "Domains (HTTPS)"
echo "---------------"
while IFS= read -r domain; do
  [ -n "$domain" ] || continue
  check_url "${domain}/" "https://${domain}/"
done < <(discover_domains)
echo

echo "Ports (nginx listen)"
echo "--------------------"
while IFS= read -r port; do
  [ -n "$port" ] || continue
  check_port "$port"
done < <(discover_listen_ports)
echo

if [ -n "$(discover_proxy_backends || true)" ]; then
  echo "Backends (proxy_pass)"
  echo "---------------------"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    backend="${entry#*|}"
    port="${backend##*:}"
    check_port "$port"
    echo "   → ${backend}"
  done < <(discover_proxy_backends)
  echo
fi

echo "System"
echo "------"
echo "CPU load: $(awk '{print $1, $2, $3}' /proc/loadavg)"
free -h | awk '/Mem:/ {print "Memory: " $3 " used / " $2 " total"}'
df -h / | awk 'NR==2 {print "Disk /: " $3 " used / " $2 " total (" $5 ")"}'
