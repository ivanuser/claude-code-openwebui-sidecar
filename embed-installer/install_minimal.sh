#!/bin/bash

# Minimal Claude Code Integration - No Core File Modifications
# This approach adds Claude Code without touching main.py or other core files

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Minimal Integration${NC}"
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
apt-get update && apt-get install -y curl &&
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &&
apt-get install -y nodejs &&
npm install -g @anthropic-ai/claude-code
" > /dev/null 2>&1

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Create a standalone API service that runs on a different port
docker exec "$CONTAINER" bash -c 'cat > /app/claude_service.py << '\''EOF'\''
#!/usr/bin/env python3
"""
Standalone Claude Code API Service
Runs on port 8100 alongside Open WebUI
"""

import asyncio
import json
import os
import subprocess
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(title="Claude Code Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
CONFIG_FILE = Path("/app/backend/data/claude_config.json")

class Settings:
    def __init__(self):
        self.load()
    
    def load(self):
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, '\''r'\'') as f:
                    data = json.load(f)
                    self.enabled = data.get("enabled", False)
                    self.oauth_token = data.get("oauth_token", "")
                    self.timeout = data.get("timeout", 60)
            except:
                self.enabled = False
                self.oauth_token = ""
                self.timeout = 60
        else:
            self.enabled = False
            self.oauth_token = ""
            self.timeout = 60
    
    def save(self, enabled=None, oauth_token=None, timeout=None):
        if enabled is not None:
            self.enabled = enabled
        if oauth_token is not None:
            self.oauth_token = oauth_token
        if timeout is not None:
            self.timeout = timeout
        
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, '\''w'\'') as f:
            json.dump({
                "enabled": self.enabled,
                "oauth_token": self.oauth_token,
                "timeout": self.timeout
            }, f, indent=2)

settings = Settings()

@app.get("/")
async def root():
    return {"service": "Claude Code API", "status": "running"}

@app.get("/api/v1/models")
async def get_models():
    if not settings.enabled:
        return {"data": []}
    
    return {
        "data": [{
            "id": "claude-code",
            "name": "Claude Code",
            "object": "model",
            "created": int(time.time()),
            "owned_by": "claude-code-service"
        }]
    }

@app.post("/api/v1/chat/completions")
async def chat_completions(body: dict):
    if not settings.enabled:
        raise HTTPException(status_code=503, detail="Claude Code disabled")
    
    if not settings.oauth_token:
        raise HTTPException(status_code=401, detail="No OAuth token")
    
    messages = body.get("messages", [])
    model = body.get("model", "claude-code")
    
    # Get last user message
    user_message = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, str):
                user_message = content
            break
    
    if not user_message:
        raise HTTPException(status_code=400, detail="No user message")
    
    try:
        # Execute Claude CLI
        result = await asyncio.create_subprocess_exec(
            "claude", "--print", user_message,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, "CLAUDE_CODE_OAUTH_TOKEN": settings.oauth_token}
        )
        
        stdout, stderr = await asyncio.wait_for(
            result.communicate(), timeout=settings.timeout
        )
        
        if stdout:
            response_text = stdout.decode('\''utf-8'\'').strip()
        else:
            response_text = "No response from Claude."
        
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
    
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Request timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/config")
async def get_config():
    return {
        "enabled": settings.enabled,
        "oauth_configured": bool(settings.oauth_token),
        "timeout": settings.timeout
    }

@app.post("/config")
async def update_config(data: dict):
    settings.save(
        enabled=data.get("enabled"),
        oauth_token=data.get("oauth_token"),
        timeout=data.get("timeout")
    )
    return {"status": "success"}

@app.post("/test")
async def test_claude():
    if not settings.oauth_token:
        return {"success": False, "error": "No OAuth token"}
    
    try:
        result = await asyncio.create_subprocess_exec(
            "claude", "--print", "Hello",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, "CLAUDE_CODE_OAUTH_TOKEN": settings.oauth_token}
        )
        
        stdout, stderr = await asyncio.wait_for(result.communicate(), timeout=10)
        
        if stdout:
            return {"success": True, "response": stdout.decode().strip()}
        else:
            return {"success": False, "error": stderr.decode() if stderr else "No output"}
    
    except Exception as e:
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8100)
EOF'

echo -e "${GREEN}✓ Created Claude service${NC}"

# Create startup script
docker exec "$CONTAINER" bash -c 'cat > /app/start_claude.sh << '\''EOF'\''
#!/bin/bash
cd /app
python3 claude_service.py &
echo $! > claude_service.pid
echo "Claude Code service started on port 8100"
EOF
chmod +x /app/start_claude.sh'

# Start the service
echo "Starting Claude Code service..."
docker exec -d "$CONTAINER" bash /app/start_claude.sh

# Wait a moment for it to start
sleep 3

# Test if it's running
if docker exec "$CONTAINER" curl -s http://localhost:8100/ > /dev/null; then
    echo -e "${GREEN}✓ Claude service is running${NC}"
else
    echo -e "${YELLOW}⚠ Service may need a moment to start${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}OAuth Token Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "Enter your Claude OAuth token: " OAUTH_TOKEN

if [ ! -z "$OAUTH_TOKEN" ]; then
    # Configure via API
    docker exec "$CONTAINER" curl -s -X POST http://localhost:8100/config \
        -H "Content-Type: application/json" \
        -d "{\"enabled\": true, \"oauth_token\": \"$OAUTH_TOKEN\"}"
    
    echo -e "${GREEN}✓ OAuth token configured${NC}"
    
    # Test it
    echo "Testing Claude Code..."
    RESULT=$(docker exec "$CONTAINER" curl -s -X POST http://localhost:8100/test)
    echo "Test result: $RESULT"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Claude Code service is running on port 8100 inside the container."
echo ""
echo "Next steps:"
echo "1. In Open WebUI Admin Panel:"
echo "   - Go to Admin Settings > Connections"
echo "   - Add OpenAI API connection:"
echo "   - URL: http://localhost:8100/api/v1"
echo "   - Save"
echo ""
echo "2. The 'claude-code' model should appear in your chat"
echo ""
echo "To manage settings:"
echo "  docker exec $CONTAINER curl http://localhost:8100/config"
echo ""