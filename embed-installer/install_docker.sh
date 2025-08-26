#!/bin/bash

# Claude Code Docker Embedded Installer
# This script installs Claude Code directly into a running Open WebUI Docker container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Docker Integration Installer${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Find Open WebUI container
echo "Searching for Open WebUI container..."
CONTAINER=$(docker ps --format "table {{.Names}}" | grep -E "open-webui|open_webui|openwebui" | head -1 || true)

if [ -z "$CONTAINER" ]; then
    echo -e "${YELLOW}No running Open WebUI container found.${NC}"
    echo "Please specify your container name:"
    read -p "Container name: " CONTAINER
    
    # Verify container exists
    if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
        echo -e "${RED}Error: Container '$CONTAINER' not found or not running${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Found container: $CONTAINER${NC}"

# Function to execute commands in container
exec_in_container() {
    docker exec "$CONTAINER" bash -c "$1"
}

# Function to copy file to container
copy_to_container() {
    local url=$1
    local dest=$2
    
    echo "  Downloading and injecting $dest..."
    
    # Create temp file
    TEMP_FILE=$(mktemp)
    
    # Download file
    if curl -sL "$url" -o "$TEMP_FILE"; then
        # Copy to container
        docker cp "$TEMP_FILE" "$CONTAINER:$dest"
        rm "$TEMP_FILE"
        echo -e "  ${GREEN}✓ Injected $dest${NC}"
        return 0
    else
        rm "$TEMP_FILE"
        echo -e "  ${RED}✗ Failed to download $url${NC}"
        return 1
    fi
}

# Check if Node.js is installed in container
echo ""
echo "Checking dependencies in container..."
if exec_in_container "node --version" >/dev/null 2>&1; then
    NODE_VERSION=$(exec_in_container "node --version")
    echo -e "  ${GREEN}✓ Node.js installed: $NODE_VERSION${NC}"
else
    echo -e "  ${YELLOW}⚠ Node.js not found, installing...${NC}"
    exec_in_container "apt-get update && apt-get install -y curl && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs"
fi

# Check/Install Claude CLI
if exec_in_container "claude --version" >/dev/null 2>&1; then
    CLAUDE_VERSION=$(exec_in_container "claude --version")
    echo -e "  ${GREEN}✓ Claude CLI installed: $CLAUDE_VERSION${NC}"
else
    echo -e "  ${YELLOW}⚠ Claude CLI not found, installing...${NC}"
    exec_in_container "npm install -g @anthropic-ai/claude-code"
fi

# Inject Claude Code files
echo ""
echo "Injecting Claude Code integration files..."

# Backend router
copy_to_container \
    "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claude_code_integrated.py" \
    "/app/backend/open_webui/routers/claude_code_integrated.py"

# Frontend component
exec_in_container "mkdir -p /app/src/lib/components/admin/Settings"
copy_to_container \
    "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/ClaudeCode.svelte" \
    "/app/src/lib/components/admin/Settings/ClaudeCode.svelte"

# API client
exec_in_container "mkdir -p /app/src/lib/apis"
copy_to_container \
    "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claudecode.ts" \
    "/app/src/lib/apis/claudecode.ts"

# Patch Open WebUI files
echo ""
echo "Patching Open WebUI files..."

# Backup original files
echo "  Creating backups..."
exec_in_container "cp /app/backend/open_webui/main.py /app/backend/open_webui/main.py.backup 2>/dev/null || true"
exec_in_container "cp /app/backend/open_webui/utils/models.py /app/backend/open_webui/utils/models.py.backup 2>/dev/null || true"
exec_in_container "cp /app/backend/open_webui/utils/chat.py /app/backend/open_webui/utils/chat.py.backup 2>/dev/null || true"

# Patch main.py - Add import if not exists
echo "  Patching main.py..."
exec_in_container "grep -q 'claude_code_integrated' /app/backend/open_webui/main.py || sed -i '/from open_webui.routers import (/a\    claude_code_integrated as claude_code,' /app/backend/open_webui/main.py"

# Add router if not exists
exec_in_container "grep -q 'claude_code.router' /app/backend/open_webui/main.py || sed -i '/app.include_router(utils.router/a\app.include_router(claude_code.router, prefix=\"/api/v1/claude-code\", tags=[\"claude-code\"])' /app/backend/open_webui/main.py"

# Patch models.py
echo "  Patching models.py..."
exec_in_container "sed -i 's/from open_webui.routers.claude_code_simple import claude_code_config/from open_webui.routers.claude_code_integrated import claude_manager/g' /app/backend/open_webui/utils/models.py 2>/dev/null || true"
exec_in_container "sed -i 's/claude_code_config.enabled/claude_manager.settings.enabled/g' /app/backend/open_webui/utils/models.py 2>/dev/null || true"

# Patch chat.py
echo "  Patching chat.py..."
exec_in_container "sed -i 's/from open_webui.routers.claude_code_simple import chat_completions/from open_webui.routers.claude_code_integrated import chat_completions/g' /app/backend/open_webui/utils/chat.py 2>/dev/null || true"

# Get OAuth token
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Claude Pro OAuth Token Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "To get your token, run locally:"
echo -e "${YELLOW}  npx @anthropic-ai/claude-code login${NC}"
echo ""
read -p "Enter your OAuth token (or 'skip' to configure later): " OAUTH_TOKEN

# Configure Claude Code
if [ "$OAUTH_TOKEN" != "skip" ] && [ ! -z "$OAUTH_TOKEN" ]; then
    echo ""
    echo "Configuring Claude Code..."
    
    # Create config
    CONFIG_JSON=$(cat <<EOF
{
  "enabled": true,
  "oauth_token": "$OAUTH_TOKEN",
  "command_path": "claude",
  "timeout": 60,
  "auto_install": true,
  "stream_responses": false,
  "max_context_messages": 10
}
EOF
)
    
    # Write config to container
    exec_in_container "mkdir -p /app/backend/data"
    echo "$CONFIG_JSON" | docker exec -i "$CONTAINER" bash -c "cat > /app/backend/data/claude_code_config.json"
    
    # Set environment variable
    docker exec "$CONTAINER" bash -c "echo 'export CLAUDE_CODE_OAUTH_TOKEN=$OAUTH_TOKEN' >> ~/.bashrc"
    
    echo -e "${GREEN}✓ OAuth token configured${NC}"
fi

# Restart the container
echo ""
read -p "Restart container now? (y/n): " RESTART

if [[ $RESTART =~ ^[Yy]$ ]]; then
    echo "Restarting container..."
    docker restart "$CONTAINER"
    echo -e "${GREEN}✓ Container restarted${NC}"
fi

# Print success message
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "1. Wait for container to fully start"
echo "2. Open your Open WebUI admin panel"
echo "3. Go to Admin Settings > Claude Code"

if [ "$OAUTH_TOKEN" == "skip" ] || [ -z "$OAUTH_TOKEN" ]; then
    echo "4. Enter your OAuth token"
    echo "5. Enable Claude Code"
else
    echo "4. Verify settings and enable if needed"
fi

echo "5. Select 'Claude Code' from model dropdown in chat"
echo ""
echo -e "${BLUE}Claude Code is now integrated into your Docker container!${NC}"
echo ""

# Provide rollback instructions
echo "To rollback if needed:"
echo "  docker exec $CONTAINER bash -c 'mv /app/backend/open_webui/main.py.backup /app/backend/open_webui/main.py'"
echo "  docker restart $CONTAINER"
echo ""