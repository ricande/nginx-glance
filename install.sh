#!/usr/bin/env bash
# Install or update the live script from the project folder.
# Default: $HOME/bin/nginx-glance.sh
# Override: INSTALL_DIR=/custom/path ./install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"
TARGET="${INSTALL_DIR%/}/nginx-glance.sh"

mkdir -p "$INSTALL_DIR"
install -m 755 "$ROOT/nginx-glance.sh" "$TARGET"
echo "Installed: $TARGET"
