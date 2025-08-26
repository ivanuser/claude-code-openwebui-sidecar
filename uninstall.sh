#!/bin/bash

# Claude Code Sidecar Uninstallation Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Claude Code Sidecar Uninstaller${NC}"
echo "================================="
echo ""

read -p "This will stop and remove the Claude Code sidecar container. Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Stopping Claude Code sidecar..."

# Stop and remove container
if docker ps -a | grep -q claude-code-sidecar; then
    docker stop claude-code-sidecar 2>/dev/null || true
    docker rm claude-code-sidecar 2>/dev/null || true
    echo -e "${GREEN}✓ Container removed${NC}"
else
    echo "No container found to remove"
fi

# Remove image
if docker images | grep -q claude-code-sidecar; then
    read -p "Remove Docker image? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rmi claude-code-sidecar:latest 2>/dev/null || true
        echo -e "${GREEN}✓ Image removed${NC}"
    fi
fi

# Backup and remove .env
if [ -f ".env" ]; then
    read -p "Backup .env configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp .env .env.uninstall-backup
        echo -e "${GREEN}✓ Configuration backed up to .env.uninstall-backup${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Uninstallation complete!${NC}"
echo ""
echo "To remove from Open WebUI:"
echo "1. Go to Admin Settings > Connections"
echo "2. Remove the 'Claude Code' connection"
echo ""
echo "To reinstall later, run: ./install.sh"