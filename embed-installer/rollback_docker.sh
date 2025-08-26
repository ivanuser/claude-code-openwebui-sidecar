#!/bin/bash

# Claude Code Docker Rollback Script
# Removes Claude Code integration from Docker container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}============================================${NC}"
echo -e "${RED}Claude Code Docker Rollback${NC}"
echo -e "${RED}============================================${NC}"
echo ""

# Find container
echo "Enter your Open WebUI container name:"
read -p "Container name: " CONTAINER

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}No container specified${NC}"
    exit 1
fi

# Check if container exists
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
    echo -e "${RED}Error: Container '$CONTAINER' not found or not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found container: $CONTAINER${NC}"
echo ""
echo "This will restore original Open WebUI files and remove Claude Code."
read -p "Continue? (y/n): " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 0
fi

echo ""
echo "Restoring original files..."

# Restore backups
docker exec "$CONTAINER" bash -c "
if [ -f /app/backend/open_webui/main.py.backup ]; then
    cp /app/backend/open_webui/main.py.backup /app/backend/open_webui/main.py
    echo '✓ Restored main.py'
fi

if [ -f /app/backend/open_webui/utils/models.py.backup ]; then
    cp /app/backend/open_webui/utils/models.py.backup /app/backend/open_webui/utils/models.py
    echo '✓ Restored models.py'
fi

if [ -f /app/backend/open_webui/utils/chat.py.backup ]; then
    cp /app/backend/open_webui/utils/chat.py.backup /app/backend/open_webui/utils/chat.py
    echo '✓ Restored chat.py'
fi

# Remove Claude Code files
rm -f /app/backend/open_webui/routers/claude_code_integrated.py
rm -f /app/src/lib/components/admin/Settings/ClaudeCode.svelte
rm -f /app/src/lib/apis/claudecode.ts
rm -f /app/backend/data/claude_code_config.json

echo '✓ Removed Claude Code files'
"

echo ""
echo "Restarting container..."
docker restart "$CONTAINER"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Rollback Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Open WebUI has been restored to its original state."
echo "Container has been restarted."
echo ""