#!/bin/bash

# Claude Code Docker Embedded Installer V3
# Fixed compatibility issues and logging problems

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Docker Integration Installer V3${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Auto-detect container
CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "open-webui|open_webui|openwebui" | head -1)

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}No Open WebUI container found running${NC}"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

echo -e "${GREEN}✓ Found container: $CONTAINER${NC}"

# Test access
if ! docker exec "$CONTAINER" echo "test" >/dev/null 2>&1; then
    echo -e "${RED}Cannot access container${NC}"
    exit 1
fi

# Validate Open WebUI
if ! docker exec "$CONTAINER" test -f "/app/backend/open_webui/main.py"; then
    echo -e "${RED}Open WebUI not found at expected location${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Open WebUI validated${NC}"

# Install dependencies
echo ""
echo "Installing dependencies..."

# Check Node.js
if ! docker exec "$CONTAINER" command -v node >/dev/null 2>&1; then
    echo "Installing Node.js..."
    docker exec "$CONTAINER" bash -c "
        apt-get update && apt-get install -y curl &&
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &&
        apt-get install -y nodejs
    "
fi

# Check Claude CLI
if ! docker exec "$CONTAINER" command -v claude >/dev/null 2>&1; then
    echo "Installing Claude CLI..."
    docker exec "$CONTAINER" npm install -g @anthropic-ai/claude-code
fi

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Create corrected integration files directly in container
echo ""
echo "Creating integration files..."

# Create the corrected router file directly
docker exec "$CONTAINER" bash -c 'cat > /app/backend/open_webui/routers/claude_code_integrated.py << '\''EOF'\''
"""
Claude Code Integration Router - Fixed for Open WebUI compatibility
"""

import asyncio
import json
import logging
import os
import subprocess
import time
import uuid
from typing import Optional, Dict, Any
from pathlib import Path

from fastapi import APIRouter, HTTPException, status, Depends, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field
from open_webui.utils.auth import get_admin_user, get_verified_user
from open_webui.models.users import UserModel

# Fixed logging setup - no dependency on SRC_LOG_LEVELS
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

router = APIRouter()

# Configuration storage
try:
    from open_webui.config import DATA_DIR
except ImportError:
    DATA_DIR = "/app/backend/data"

CONFIG_FILE = Path(DATA_DIR) / "claude_code_config.json"

class ClaudeCodeSettings(BaseModel):
    enabled: bool = Field(default=False)
    oauth_token: Optional[str] = Field(default=None)
    command_path: str = Field(default="claude")
    timeout: int = Field(default=60)
    auto_install: bool = Field(default=True)
    stream_responses: bool = Field(default=False)
    max_context_messages: int = Field(default=10)

class ClaudeCodeManager:
    def __init__(self):
        self.settings = self.load_settings()
    
    def load_settings(self) -> ClaudeCodeSettings:
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, '\''r'\'') as f:
                    data = json.load(f)
                    return ClaudeCodeSettings(**data)
            except Exception as e:
                log.error(f"Failed to load settings: {e}")
        return ClaudeCodeSettings()
    
    def save_settings(self, settings: ClaudeCodeSettings):
        try:
            CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(CONFIG_FILE, '\''w'\'') as f:
                json.dump(settings.dict(), f, indent=2)
            self.settings = settings
            if settings.oauth_token:
                os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = settings.oauth_token
            return True
        except Exception as e:
            log.error(f"Failed to save settings: {e}")
            return False
    
    async def execute_claude(self, message: str, timeout: int = None) -> str:
        if not self.settings.enabled:
            raise HTTPException(status_code=503, detail="Claude Code disabled")
        
        if not self.settings.oauth_token:
            raise HTTPException(status_code=401, detail="No OAuth token configured")
        
        timeout = timeout or self.settings.timeout
        cmd = [self.settings.command_path, '\''--print'\'', message]
        
        try:
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, "CLAUDE_CODE_OAUTH_TOKEN": self.settings.oauth_token}
            )
            
            stdout, stderr = await asyncio.wait_for(
                result.communicate(), timeout=timeout
            )
            
            if stdout:
                return stdout.decode('\''utf-8'\'').strip()
            else:
                return "No response from Claude Code CLI."
                
        except Exception as e:
            log.error(f"Claude execution failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))

# Initialize manager
claude_manager = ClaudeCodeManager()

@router.get("/status")
async def get_status(user=Depends(get_admin_user)):
    return {
        "settings": claude_manager.settings.dict(exclude={'\''oauth_token'\''}),
        "oauth_configured": bool(claude_manager.settings.oauth_token)
    }

@router.get("/settings")
async def get_settings(user=Depends(get_admin_user)):
    settings = claude_manager.settings.dict()
    if settings.get("oauth_token"):
        token = settings["oauth_token"]
        settings["oauth_token"] = f"{token[:15]}...{token[-4:]}" if len(token) > 20 else "***"
    return settings

@router.post("/settings")
async def update_settings(settings: ClaudeCodeSettings, user=Depends(get_admin_user)):
    if settings.oauth_token and "..." in settings.oauth_token:
        settings.oauth_token = claude_manager.settings.oauth_token
    
    if claude_manager.save_settings(settings):
        return {"status": "success"}
    else:
        raise HTTPException(status_code=500, detail="Failed to save")

@router.post("/test")
async def test_claude(message: str = "Hello, Claude!", user=Depends(get_admin_user)):
    try:
        response = await claude_manager.execute_claude(message, timeout=10)
        return {"success": True, "response": response}
    except Exception as e:
        return {"success": False, "error": str(e)}

@router.post("/chat/completions")
async def chat_completions(request: Request, body: dict, user=Depends(get_verified_user)):
    if not claude_manager.settings.enabled:
        raise HTTPException(status_code=503, detail="Claude Code disabled")
    
    messages = body.get("messages", [])
    model = body.get("model", "claude-code")
    
    # Get last user message
    user_message = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, list):
                text_parts = [part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"]
                user_message = " ".join(text_parts)
            else:
                user_message = content
            break
    
    if not user_message:
        raise HTTPException(status_code=400, detail="No user message")
    
    log.info(f"Claude request from {user.email}: {user_message[:100]}...")
    
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
            }],
            "usage": {
                "prompt_tokens": len(user_message.split()),
                "completion_tokens": len(response_text.split()),
                "total_tokens": len(user_message.split()) + len(response_text.split())
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        log.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
EOF'

echo -e "${GREEN}✓ Router created${NC}"

# Create minimal admin component
docker exec "$CONTAINER" bash -c 'mkdir -p /app/src/lib/components/admin/Settings'
docker exec "$CONTAINER" bash -c 'cat > /app/src/lib/components/admin/Settings/ClaudeCode.svelte << '\''EOF'\''
<script>
  import { onMount } from '\''svelte'\'';
  
  let enabled = false;
  let oauthToken = '\'\'\'\'';
  let testResult = '\'\'\'\'';
  let loading = false;
  
  async function saveSettings() {
    loading = true;
    try {
      const response = await fetch('\''/api/v1/claude-code/settings'\'', {
        method: '\''POST'\'',
        headers: { '\''Content-Type'\'': '\''application/json'\'' },
        body: JSON.stringify({ enabled, oauth_token: oauthToken })
      });
      if (response.ok) {
        alert('\''Settings saved!'\'');
      }
    } catch (err) {
      alert('\''Error saving settings'\'');
    }
    loading = false;
  }
  
  async function testClaude() {
    try {
      const response = await fetch('\''/api/v1/claude-code/test'\'', { method: '\''POST'\'' });
      const result = await response.json();
      testResult = result.success ? result.response : result.error;
    } catch (err) {
      testResult = '\''Test failed: '\'' + err;
    }
  }
</script>

<div class="p-4">
  <h2 class="text-lg font-semibold mb-4">Claude Code Integration</h2>
  
  <div class="space-y-4">
    <label class="flex items-center">
      <input type="checkbox" bind:checked={enabled} class="mr-2">
      Enable Claude Code
    </label>
    
    <div>
      <label class="block text-sm font-medium mb-1">OAuth Token</label>
      <input 
        type="password" 
        bind:value={oauthToken}
        placeholder="sk-ant-oat01-..."
        class="w-full p-2 border rounded"
      >
      <p class="text-xs text-gray-600 mt-1">
        Get token: npx @anthropic-ai/claude-code login
      </p>
    </div>
    
    <button 
      on:click={saveSettings} 
      disabled={loading}
      class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
    >
      {loading ? '\''Saving...'\'' : '\''Save Settings'\''}
    </button>
    
    {#if enabled && oauthToken}
      <div class="border-t pt-4">
        <button 
          on:click={testClaude}
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700"
        >
          Test Claude Code
        </button>
        {#if testResult}
          <pre class="mt-2 p-2 bg-gray-100 rounded text-sm">{testResult}</pre>
        {/if}
      </div>
    {/if}
  </div>
</div>
EOF'

echo -e "${GREEN}✓ Admin component created${NC}"

# Simple API client
docker exec "$CONTAINER" bash -c 'mkdir -p /app/src/lib/apis'
docker exec "$CONTAINER" bash -c 'cat > /app/src/lib/apis/claudecode.ts << '\''EOF'\''
const WEBUI_API_BASE_URL = '\''/api/v1'\'';

export const getClaudeCodeStatus = async (token = '\'\'\'\'') => {
  const response = await fetch(`${WEBUI_API_BASE_URL}/claude-code/status`);
  return await response.json();
};

export const updateClaudeCodeSettings = async (token = '\'\'\'\'', settings) => {
  const response = await fetch(`${WEBUI_API_BASE_URL}/claude-code/settings`, {
    method: '\''POST'\'',
    headers: { '\''Content-Type'\'': '\''application/json'\'' },
    body: JSON.stringify(settings)
  });
  return await response.json();
};

export const testClaudeCode = async (token = '\'\'\'\'', message = '\''Hello'\'') => {
  const response = await fetch(`${WEBUI_API_BASE_URL}/claude-code/test`);
  return await response.json();
};
EOF'

echo -e "${GREEN}✓ API client created${NC}"

# Now patch main.py safely
echo ""
echo "Patching main.py..."

docker exec "$CONTAINER" python3 -c "
import re

# Read main.py
with open('/app/backend/open_webui/main.py', 'r') as f:
    content = f.read()

# Add import if not present
if 'claude_code_integrated as claude_code' not in content:
    # Find import section
    pattern = r'(from open_webui\.routers import \([^)]+)\)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        imports = match.group(1)
        new_imports = imports + ',\n    claude_code_integrated as claude_code'
        content = content.replace(match.group(0), new_imports + ')')

# Add router if not present
if 'claude_code.router' not in content:
    # Find where to add router
    if 'app.include_router(utils.router' in content:
        pattern = r'(app\.include_router\(utils\.router[^)]+\))'
        match = re.search(pattern, content)
        if match:
            old_line = match.group(0)
            new_line = old_line + '\napp.include_router(claude_code.router, prefix=\"/api/v1/claude-code\", tags=[\"claude-code\"])'
            content = content.replace(old_line, new_line)

# Write back
with open('/app/backend/open_webui/main.py', 'w') as f:
    f.write(content)

print('✓ main.py patched')
"

# Get OAuth token
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}OAuth Token Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "Enter OAuth token (or 'skip'): " OAUTH_TOKEN

if [ "$OAUTH_TOKEN" != "skip" ] && [ ! -z "$OAUTH_TOKEN" ]; then
    # Create config
    docker exec "$CONTAINER" bash -c "
    mkdir -p /app/backend/data
    cat > /app/backend/data/claude_code_config.json << EOF
{
  \"enabled\": false,
  \"oauth_token\": \"$OAUTH_TOKEN\",
  \"command_path\": \"claude\",
  \"timeout\": 60,
  \"auto_install\": true,
  \"stream_responses\": false,
  \"max_context_messages\": 10
}
EOF
    "
    echo -e "${GREEN}✓ OAuth token configured${NC}"
fi

echo ""
echo "Restarting container..."
docker restart "$CONTAINER"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "1. Wait for container to start"
echo "2. Go to Admin Settings > Claude Code"
echo "3. Enable Claude Code"
echo "4. Test the integration"
echo ""