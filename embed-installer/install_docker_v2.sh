#!/bin/bash

# Claude Code Docker Embedded Installer V2
# Improved version with better error handling and validation

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Docker Integration Installer V2${NC}"
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

# Create a test to ensure we can execute commands
echo "Testing container access..."
if ! docker exec "$CONTAINER" echo "test" >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot execute commands in container${NC}"
    exit 1
fi

# Function to safely execute in container
exec_in_container() {
    docker exec "$CONTAINER" bash -c "$1"
}

# Check Open WebUI structure
echo "Validating Open WebUI installation..."
if ! exec_in_container "test -f /app/backend/open_webui/main.py"; then
    echo -e "${RED}Error: Open WebUI not found in container at /app/backend/open_webui/${NC}"
    echo "Checking alternative paths..."
    
    # Try to find the correct path
    POSSIBLE_PATHS="/app /opt/open-webui /open-webui"
    for PATH in $POSSIBLE_PATHS; do
        if exec_in_container "test -f $PATH/backend/open_webui/main.py" 2>/dev/null; then
            echo -e "${GREEN}Found Open WebUI at: $PATH${NC}"
            APP_PATH=$PATH
            break
        fi
    done
    
    if [ -z "$APP_PATH" ]; then
        echo -e "${RED}Could not find Open WebUI installation in container${NC}"
        exit 1
    fi
else
    APP_PATH="/app"
fi

echo -e "${GREEN}✓ Open WebUI found at: $APP_PATH${NC}"

# Create comprehensive backup
echo ""
echo "Creating comprehensive backup..."
BACKUP_NAME="claude_backup_$(date +%Y%m%d_%H%M%S)"
exec_in_container "mkdir -p /tmp/$BACKUP_NAME"

# Backup all files we'll modify
exec_in_container "cp -r $APP_PATH/backend/open_webui /tmp/$BACKUP_NAME/open_webui_backup 2>/dev/null || true"
echo -e "${GREEN}✓ Backup created at: /tmp/$BACKUP_NAME${NC}"

# Install dependencies
echo ""
echo "Checking dependencies..."

# Node.js check/install
if exec_in_container "command -v node" >/dev/null 2>&1; then
    NODE_VERSION=$(exec_in_container "node --version")
    echo -e "${GREEN}✓ Node.js installed: $NODE_VERSION${NC}"
else
    echo "Installing Node.js..."
    exec_in_container "apt-get update && apt-get install -y curl"
    exec_in_container "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
    exec_in_container "apt-get install -y nodejs"
    echo -e "${GREEN}✓ Node.js installed${NC}"
fi

# Claude CLI check/install
if exec_in_container "command -v claude" >/dev/null 2>&1; then
    CLAUDE_VERSION=$(exec_in_container "claude --version" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Claude CLI installed: $CLAUDE_VERSION${NC}"
else
    echo "Installing Claude CLI..."
    exec_in_container "npm install -g @anthropic-ai/claude-code"
    echo -e "${GREEN}✓ Claude CLI installed${NC}"
fi

# Download integration files
echo ""
echo "Downloading integration files..."

# Create temp directory on host
TEMP_DIR=$(mktemp -d)
echo "Using temp directory: $TEMP_DIR"

# Download files
echo "  Downloading claude_code_integrated.py..."
curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claude_code_integrated.py \
    -o "$TEMP_DIR/claude_code_integrated.py"

echo "  Downloading ClaudeCode.svelte..."
curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/ClaudeCode.svelte \
    -o "$TEMP_DIR/ClaudeCode.svelte"

echo "  Downloading claudecode.ts..."
curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claudecode.ts \
    -o "$TEMP_DIR/claudecode.ts"

# Copy files to container
echo ""
echo "Injecting files into container..."

# Backend router
docker cp "$TEMP_DIR/claude_code_integrated.py" "$CONTAINER:$APP_PATH/backend/open_webui/routers/"
echo -e "${GREEN}✓ Injected backend router${NC}"

# Frontend component
exec_in_container "mkdir -p $APP_PATH/src/lib/components/admin/Settings"
docker cp "$TEMP_DIR/ClaudeCode.svelte" "$CONTAINER:$APP_PATH/src/lib/components/admin/Settings/"
echo -e "${GREEN}✓ Injected admin panel component${NC}"

# API client
exec_in_container "mkdir -p $APP_PATH/src/lib/apis"
docker cp "$TEMP_DIR/claudecode.ts" "$CONTAINER:$APP_PATH/src/lib/apis/"
echo -e "${GREEN}✓ Injected API client${NC}"

# Clean up temp dir
rm -rf "$TEMP_DIR"

# Now patch the Python files carefully
echo ""
echo "Patching Open WebUI files..."

# Create a Python script to do the patching (more reliable than sed)
cat << 'PYTHON_SCRIPT' > /tmp/patch_script.py
#!/usr/bin/env python3
import sys
import re

def patch_main_py(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Check if already patched
        if 'claude_code_integrated' in content:
            print("main.py already patched")
            return True
        
        # Add import
        import_pattern = r'(from open_webui\.routers import \([\s\S]*?)(utils,)'
        if re.search(import_pattern, content):
            content = re.sub(
                import_pattern,
                r'\1claude_code_integrated as claude_code,\n    \2',
                content
            )
        
        # Add router
        router_pattern = r'(app\.include_router\(utils\.router.*?\))'
        if re.search(router_pattern, content):
            content = re.sub(
                router_pattern,
                r'\1\napp.include_router(claude_code.router, prefix="/api/v1/claude-code", tags=["claude-code"])',
                content
            )
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        print("✓ Patched main.py")
        return True
    except Exception as e:
        print(f"Error patching main.py: {e}")
        return False

def patch_models_py(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Check if it needs patching
        if 'claude_code_integrated' in content:
            print("models.py already patched")
            return True
        
        # Only patch if the old version exists
        if 'claude_code_simple' in content:
            content = content.replace(
                'from open_webui.routers.claude_code_simple import claude_code_config',
                'from open_webui.routers.claude_code_integrated import claude_manager'
            )
            content = content.replace(
                'claude_code_config.enabled',
                'claude_manager.settings.enabled'
            )
            
            with open(filepath, 'w') as f:
                f.write(content)
            print("✓ Patched models.py")
        else:
            print("⚠ models.py doesn't have Claude Code references")
        
        return True
    except Exception as e:
        print(f"Error patching models.py: {e}")
        return False

def patch_chat_py(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Check if it needs patching
        if 'claude_code_integrated' in content:
            print("chat.py already patched")
            return True
        
        # Only patch if the old version exists
        if 'claude_code_simple' in content:
            content = content.replace(
                'from open_webui.routers.claude_code_simple import chat_completions',
                'from open_webui.routers.claude_code_integrated import chat_completions'
            )
            
            with open(filepath, 'w') as f:
                f.write(content)
            print("✓ Patched chat.py")
        else:
            print("⚠ chat.py doesn't have Claude Code references")
        
        return True
    except Exception as e:
        print(f"Error patching chat.py: {e}")
        return False

if __name__ == "__main__":
    import os
    app_path = os.environ.get('APP_PATH', '/app')
    
    success = True
    success &= patch_main_py(f"{app_path}/backend/open_webui/main.py")
    success &= patch_models_py(f"{app_path}/backend/open_webui/utils/models.py")
    success &= patch_chat_py(f"{app_path}/backend/open_webui/utils/chat.py")
    
    sys.exit(0 if success else 1)
PYTHON_SCRIPT

# Copy and run the patch script
docker cp /tmp/patch_script.py "$CONTAINER:/tmp/"
if exec_in_container "APP_PATH=$APP_PATH python3 /tmp/patch_script.py"; then
    echo -e "${GREEN}✓ Successfully patched Open WebUI files${NC}"
else
    echo -e "${RED}✗ Failed to patch some files${NC}"
    echo "You may need to manually edit the files or use the rollback script"
fi

# Clean up
rm /tmp/patch_script.py
exec_in_container "rm /tmp/patch_script.py"

# OAuth token configuration
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Claude Pro OAuth Token Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "To get your token, run locally:"
echo -e "${YELLOW}  npx @anthropic-ai/claude-code login${NC}"
echo ""
read -p "Enter your OAuth token (or 'skip' to configure later): " OAUTH_TOKEN

if [ "$OAUTH_TOKEN" != "skip" ] && [ ! -z "$OAUTH_TOKEN" ]; then
    echo ""
    echo "Configuring Claude Code..."
    
    # Create config
    CONFIG_JSON=$(cat <<EOF
{
  "enabled": false,
  "oauth_token": "$OAUTH_TOKEN",
  "command_path": "claude",
  "timeout": 60,
  "auto_install": true,
  "stream_responses": false,
  "max_context_messages": 10
}
EOF
)
    
    # Write config
    exec_in_container "mkdir -p $APP_PATH/backend/data"
    echo "$CONFIG_JSON" | docker exec -i "$CONTAINER" bash -c "cat > $APP_PATH/backend/data/claude_code_config.json"
    
    echo -e "${GREEN}✓ OAuth token configured (disabled by default for safety)${NC}"
fi

# Test the integration
echo ""
echo "Testing integration..."
if exec_in_container "python3 -c 'from open_webui.routers import claude_code_integrated'" 2>/dev/null; then
    echo -e "${GREEN}✓ Integration test passed${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify integration - may need container restart${NC}"
fi

# Restart option
echo ""
read -p "Restart container now? (recommended) (y/n): " RESTART

if [[ $RESTART =~ ^[Yy]$ ]]; then
    echo "Restarting container..."
    docker restart "$CONTAINER"
    echo -e "${GREEN}✓ Container restarted${NC}"
    
    # Wait for it to come up
    echo "Waiting for container to be healthy..."
    sleep 10
fi

# Final instructions
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "1. Open your Open WebUI admin panel"
echo "2. Go to Admin Settings > Claude Code"
echo "3. Enable Claude Code"
echo "4. Test with a simple message"
echo ""
echo "If you encounter issues:"
echo "1. Check logs: docker logs $CONTAINER --tail 100"
echo "2. Rollback if needed:"
echo "   curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/rollback_docker.sh | bash"
echo ""
echo "Backup location: /tmp/$BACKUP_NAME (inside container)"
echo ""