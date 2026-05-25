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

install_script() {
  mkdir -p "$INSTALL_DIR"
  install -m 755 "$ROOT/nginx-glance.sh" "$TARGET"
  echo "Installed script: $TARGET"
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

install_script

if $INSTALL_PLASMOID; then
  install_plasmoid
fi
