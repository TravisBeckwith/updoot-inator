#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
SCRIPT_FILE="updoot-inator.sh"
LINK_NAME="updoot-inator"
SOURCE="$(cd "$(dirname "$0")" && pwd)/$SCRIPT_FILE"

if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}Error: $SCRIPT_FILE not found in $(dirname "$0")${NC}"
    exit 1
fi

echo "Installing $LINK_NAME to $INSTALL_DIR..."

chmod +x "$SOURCE"

if [ -w "$INSTALL_DIR" ]; then
    ln -sf "$SOURCE" "$INSTALL_DIR/$LINK_NAME"
else
    sudo ln -sf "$SOURCE" "$INSTALL_DIR/$LINK_NAME"
fi

echo -e "${GREEN}✔ Installed! Run '$LINK_NAME --help' to get started 🎺💀${NC}"
