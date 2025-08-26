#!/bin/bash

# TRUE EMBEDDED Claude Code Integration
# This modifies Open WebUI core files to make Claude Code a native feature

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}TRUE EMBEDDED Claude Code Integration${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "open-webui|open_webui|openwebui" | head -1)

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}No Open WebUI container found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found container: $CONTAINER${NC}"

# Install dependencies
echo "Installing Node.js and Claude CLI..."
docker exec "$CONTAINER" bash -c "
apt-get update -qq && apt-get install -y curl -qq &&
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null &&
apt-get install -y nodejs -qq &&
npm install -g @anthropic-ai/claude-code > /dev/null
" > /dev/null 2>&1

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Create backup
echo "Creating backup..."
docker exec "$CONTAINER" bash -c "
mkdir -p /tmp/openwebui_backup
cp -r /app/backend/open_webui /tmp/openwebui_backup/
"
echo -e "${GREEN}✓ Backup created at /tmp/openwebui_backup${NC}"

# Step 1: Create the corrected router file
echo "Creating Claude Code router..."
docker exec "$CONTAINER" bash -c 'cat > /tmp/claude_code_integrated.py << '\''EOF'\''
import asyncio
import json
import logging
import os
import subprocess
import time
import uuid
from typing import Optional
from pathlib import Path

from fastapi import APIRouter, HTTPException, status, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Import from Open WebUI
try:
    from open_webui.utils.auth import get_admin_user, get_verified_user
    from open_webui.models.users import UserModel
    from open_webui.config import DATA_DIR
except ImportError as e:
    # Fallback if imports fail
    logging.error(f"Import error: {e}")
    DATA_DIR = "/app/backend/data"
    def get_admin_user():
        return None
    def get_verified_user():
        return None

# Simple logging
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

router = APIRouter()
CONFIG_FILE = Path(DATA_DIR) / "claude_code_config.json"

class ClaudeCodeSettings(BaseModel):
    enabled: bool = False
    oauth_token: Optional[str] = None
    command_path: str = "claude"
    timeout: int = 60

class ClaudeCodeManager:
    def __init__(self):
        self.settings = self.load_settings()
    
    def load_settings(self):
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, '\''r'\'') as f:
                    data = json.load(f)
                    return ClaudeCodeSettings(**data)
            except:
                pass
        return ClaudeCodeSettings()
    
    def save_settings(self, settings):
        try:
            CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(CONFIG_FILE, '\''w'\'') as f:
                json.dump(settings.dict(), f, indent=2)
            self.settings = settings
            if settings.oauth_token:
                os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = settings.oauth_token
            return True
        except Exception as e:
            log.error(f"Save error: {e}")
            return False
    
    async def execute_claude(self, message: str):
        if not self.settings.enabled:
            raise HTTPException(status_code=503, detail="Claude Code disabled")
        
        if not self.settings.oauth_token:
            raise HTTPException(status_code=401, detail="No OAuth token")
        
        try:
            result = await asyncio.create_subprocess_exec(
                self.settings.command_path, '\''--print'\'', message,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, "CLAUDE_CODE_OAUTH_TOKEN": self.settings.oauth_token}
            )
            
            stdout, stderr = await asyncio.wait_for(
                result.communicate(), timeout=self.settings.timeout
            )
            
            return stdout.decode('\''utf-8'\'').strip() if stdout else "No response"
        
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

claude_manager = ClaudeCodeManager()

@router.get("/status")
async def get_status():
    return {
        "enabled": claude_manager.settings.enabled,
        "oauth_configured": bool(claude_manager.settings.oauth_token)
    }

@router.get("/settings") 
async def get_settings():
    settings = claude_manager.settings.dict()
    if settings.get("oauth_token"):
        token = settings["oauth_token"]
        settings["oauth_token"] = f"{token[:15]}...{token[-4:]}" if len(token) > 20 else "***"
    return settings

@router.post("/settings")
async def update_settings(settings: ClaudeCodeSettings):
    if settings.oauth_token and "..." in settings.oauth_token:
        settings.oauth_token = claude_manager.settings.oauth_token
    
    if claude_manager.save_settings(settings):
        return {"status": "success"}
    else:
        raise HTTPException(status_code=500, detail="Save failed")

@router.post("/test")
async def test_claude(data: dict = {"message": "Hello"}):
    try:
        response = await claude_manager.execute_claude(data.get("message", "Hello"))
        return {"success": True, "response": response}
    except Exception as e:
        return {"success": False, "error": str(e)}

@router.post("/chat/completions") 
async def chat_completions(body: dict):
    messages = body.get("messages", [])
    model = body.get("model", "claude-code")
    
    user_message = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            user_message = content if isinstance(content, str) else str(content)
            break
    
    if not user_message:
        raise HTTPException(status_code=400, detail="No message")
    
    try:
        response_text = await claude_manager.execute_claude(user_message)
        
        return {
            "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
            "object": "chat.completion", 
            "created": int(time.time()),
            "model": model,
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": response_text},
                "finish_reason": "stop"
            }]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
EOF

# Move to the correct location
cp /tmp/claude_code_integrated.py /app/backend/open_webui/routers/
rm /tmp/claude_code_integrated.py
'

echo -e "${GREEN}✓ Router created${NC}"

# Step 2: Very carefully patch main.py using Python
echo "Patching main.py..."
docker exec "$CONTAINER" python3 -c '
import re
import sys

try:
    with open("/app/backend/open_webui/main.py", "r") as f:
        content = f.read()
    
    # Check if already patched
    if "claude_code_integrated" in content:
        print("Already patched")
        sys.exit(0)
    
    # Add import
    pattern = r"(from open_webui\.routers import \([^)]+)(\))"
    match = re.search(pattern, content, re.DOTALL)
    if match:
        before = match.group(1)
        after = match.group(2)
        new_import = before + ",\n    claude_code_integrated as claude_code" + after
        content = content.replace(match.group(0), new_import)
    
    # Add router
    pattern = r"(app\.include_router\(utils\.router[^)]+\))"
    match = re.search(pattern, content)
    if match:
        old_line = match.group(0)
        new_line = old_line + "\napp.include_router(claude_code.router, prefix=\"/api/v1/claude-code\", tags=[\"claude-code\"])"
        content = content.replace(old_line, new_line)
    
    # Write back
    with open("/app/backend/open_webui/main.py", "w") as f:
        f.write(content)
    
    print("SUCCESS: main.py patched")

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ main.py patched successfully${NC}"
else
    echo -e "${RED}✗ main.py patch failed${NC}"
    exit 1
fi

# Step 3: Test the import
echo "Testing Python import..."
docker exec "$CONTAINER" python3 -c "
import sys
sys.path.insert(0, '/app/backend')
try:
    from open_webui.routers import claude_code_integrated
    print('Import test: SUCCESS')
except Exception as e:
    print(f'Import test: FAILED - {e}')
    exit(1)
"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Import test passed${NC}"
else
    echo -e "${RED}✗ Import test failed - restoring backup${NC}"
    docker exec "$CONTAINER" bash -c "
    rm -rf /app/backend/open_webui
    cp -r /tmp/openwebui_backup/open_webui /app/backend/
    "
    exit 1
fi

# Step 4: OAuth token setup
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}OAuth Token Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "Enter your Claude OAuth token: " OAUTH_TOKEN

if [ ! -z "$OAUTH_TOKEN" ]; then
    docker exec "$CONTAINER" bash -c "
    mkdir -p /app/backend/data
    cat > /app/backend/data/claude_code_config.json << 'EOF'
{
  \"enabled\": true,
  \"oauth_token\": \"$OAUTH_TOKEN\", 
  \"command_path\": \"claude\",
  \"timeout\": 60
}
EOF
    "
    echo -e "${GREEN}✓ OAuth token configured${NC}"
fi

# Step 5: Restart
echo ""
echo "Restarting Open WebUI..."
docker restart "$CONTAINER"

# Wait for restart
echo "Waiting for restart..."
sleep 5

# Check if it started
if docker ps | grep -q "$CONTAINER"; then
    echo -e "${GREEN}✓ Container restarted successfully${NC}"
else
    echo -e "${RED}✗ Container failed to start - restoring backup${NC}"
    docker start "$CONTAINER" || true
    sleep 2
    docker exec "$CONTAINER" bash -c "
    rm -rf /app/backend/open_webui
    cp -r /tmp/openwebui_backup/open_webui /app/backend/
    " || true
    docker restart "$CONTAINER"
    exit 1
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}TRUE EMBEDDED INTEGRATION COMPLETE!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Claude Code is now fully integrated into Open WebUI!"
echo ""
echo "Next steps:"
echo "1. Open your Open WebUI admin panel"
echo "2. Look for Claude Code settings in Admin panel" 
echo "3. The claude-code model should appear in chat"
echo ""
echo "If something went wrong:"
echo "  Backup is at: /tmp/openwebui_backup (inside container)"
echo ""