#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="updoot-inator"
SOURCE="$(cd "$(dirname "$0")" && pwd)/$SCRIPT_NAME"

if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}Error: $SCRIPT_NAME not found in current directory${NC}"
    exit 1
fi

echo "Installing $SCRIPT_NAME to $INSTALL_DIR..."

if [ -w "$INSTALL_DIR" ]; then
    ln -sf "$SOURCE" "$INSTALL_DIR/$SCRIPT_NAME"
else
    sudo ln -sf "$SOURCE" "$INSTALL_DIR/$SCRIPT_NAME"
fi

chmod +x "$SOURCE"

echo -e "${GREEN}✔ Installed! Run 'updoot-inator --help' to get started 🎺💀${NC}"