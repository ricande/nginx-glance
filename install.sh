#!/usr/bin/env bash
# Install or update nginx-glance from the project folder.
# Default: $HOME/bin/nginx-glance.sh
# Override: INSTALL_DIR=/custom/path ./install.sh
# Optional: ./install.sh --plasmoid
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"
TARGET="${INSTALL_DIR%/}/nginx-glance.sh"
INSTALL_PLASMOID=false

usage() {
  cat <<EOF
Usage: $0 [--plasmoid]

  (default)   Install nginx-glance.sh to \$HOME/bin
  --plasmoid  Also install the KDE Plasma 6 widget (requires kpackagetool6)
EOF
}

# command -> typical Debian/Ubuntu package (for hints only)
pkg_hint() {
  case "$1" in
    curl) echo "curl" ;;
    systemctl) echo "systemd" ;;
    ss) echo "iproute2" ;;
    free) echo "procps" ;;
    nginx) echo "nginx" ;;
    *) echo "coreutils" ;;
  esac
}

check_dependencies() {
  local cmd missing=()
  local -a required_cmds=(
    bash curl systemctl ss awk sed grep head free df
  )

  echo "Checking dependencies ..."

  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: Missing required commands: ${missing[*]}" >&2
    echo "Install hints (Debian/Ubuntu):" >&2
    local seen="" pkg
    for cmd in "${missing[@]}"; do
      pkg="$(pkg_hint "$cmd")"
      [[ " $seen " == *" $pkg "* ]] && continue
      seen="$seen $pkg"
      echo "  sudo apt install $pkg" >&2
    done
    exit 1
  fi
  echo "  Required CLI tools: OK"

  if command -v nginx >/dev/null 2>&1; then
    echo "  nginx binary: OK ($(command -v nginx))"
  else
    echo "  WARNING: nginx not found on PATH." >&2
    echo "           nginx-glance reads site configs; install with: sudo apt install nginx" >&2
  fi

  if [ -d /etc/nginx/sites-enabled ]; then
    echo "  /etc/nginx/sites-enabled: OK"
  else
    echo "  WARNING: /etc/nginx/sites-enabled not found." >&2
    echo "           Set NGINX_SITES_ENABLED to your sites directory, or install nginx." >&2
  fi

  if systemctl list-unit-files nginx.service >/dev/null 2>&1; then
    echo "  nginx.service unit: OK"
  else
    echo "  WARNING: nginx.service not found in systemd." >&2
    echo "           Service status checks will report unknown until nginx is installed." >&2
  fi

  if $INSTALL_PLASMOID; then
    if command -v kpackagetool6 >/dev/null 2>&1 || command -v kpackagetool-6 >/dev/null 2>&1; then
      echo "  kpackagetool6 (plasmoid): OK"
    else
      echo "  NOTE: kpackagetool6 not found; script will install but plasmoid step needs manual run." >&2
      echo "        Try: sudo apt install plasma-sdk  (or your distro's KDE dev package)" >&2
    fi
  fi

  echo
}

install_script() {
  mkdir -p "$INSTALL_DIR"
  install -m 755 "$ROOT/nginx-glance.sh" "$TARGET"
  echo "Installed script: $TARGET"
  echo "Run: $TARGET --text"
  echo "Or:  $TARGET --json   (Plasma widget, full check)"
  echo "     $TARGET --sample-json   (Plasma waveforms)"
}

install_plasmoid() {
  local tool plasmoid_dir
  plasmoid_dir="$ROOT/plasmoid"

  if [ ! -f "$plasmoid_dir/metadata.json" ]; then
    echo "Plasmoid package not found at: $plasmoid_dir" >&2
    return 1
  fi

  if command -v kpackagetool6 >/dev/null 2>&1; then
    tool=kpackagetool6
  elif command -v kpackagetool-6 >/dev/null 2>&1; then
    tool=kpackagetool-6
  else
    echo "kpackagetool6 not found. Install KDE development tools, then run:"
    echo "  kpackagetool6 --type Plasma/Applet --install $plasmoid_dir"
    echo "Upgrade later with:"
    echo "  kpackagetool6 --type Plasma/Applet --upgrade $plasmoid_dir"
    return 0
  fi

  if "$tool" --type Plasma/Applet --list 2>/dev/null | grep -q 'org.nginxglance.nginxglance'; then
    echo "Upgrading plasmoid via $tool ..."
    "$tool" --type Plasma/Applet --upgrade "$plasmoid_dir"
  else
    echo "Installing plasmoid via $tool ..."
    "$tool" --type Plasma/Applet --install "$plasmoid_dir"
  fi
  echo "Plasmoid installed. Add widget: Nginx Glance"
}

for arg in "$@"; do
  case "$arg" in
    --plasmoid) INSTALL_PLASMOID=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

check_dependencies
install_script

if $INSTALL_PLASMOID; then
  install_plasmoid
fi
