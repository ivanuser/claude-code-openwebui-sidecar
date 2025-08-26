"""
Claude Code Integration Router
Provides native Claude Code CLI integration with admin panel controls
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
from open_webui.config import CACHE_DIR, DATA_DIR
from open_webui.models.users import Users
from open_webui.utils.auth import get_admin_user, get_verified_user
from open_webui.models.users import UserModel
from open_webui.env import SRC_LOG_LEVELS

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)
log.setLevel(SRC_LOG_LEVELS["ROUTERS"])

router = APIRouter()

# Configuration storage
CONFIG_FILE = Path(DATA_DIR) / "claude_code_config.json"


class ClaudeCodeSettings(BaseModel):
    """Claude Code configuration settings"""
    enabled: bool = Field(default=False, description="Enable Claude Code integration")
    oauth_token: Optional[str] = Field(default=None, description="Claude Pro OAuth token")
    command_path: str = Field(default="claude", description="Path to Claude CLI")
    timeout: int = Field(default=60, description="Command timeout in seconds")
    auto_install: bool = Field(default=True, description="Auto-install Claude CLI if missing")
    stream_responses: bool = Field(default=False, description="Enable streaming responses")
    max_context_messages: int = Field(default=10, description="Maximum context messages to send")


class ClaudeCodeInstaller:
    """Handles Claude CLI installation and setup"""
    
    @staticmethod
    async def check_node():
        """Check if Node.js is installed"""
        try:
            result = await asyncio.create_subprocess_exec(
                "node", "--version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await result.communicate()
            return result.returncode == 0, stdout.decode().strip() if stdout else None
        except:
            return False, None
    
    @staticmethod
    async def check_claude_cli():
        """Check if Claude CLI is installed"""
        try:
            result = await asyncio.create_subprocess_exec(
                "claude", "--version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await result.communicate()
            return result.returncode == 0, stdout.decode().strip() if stdout else None
        except:
            return False, None
    
    @staticmethod
    async def install_node():
        """Install Node.js"""
        install_script = """
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        """
        try:
            result = await asyncio.create_subprocess_shell(
                install_script,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await result.communicate()
            return result.returncode == 0
        except:
            return False
    
    @staticmethod
    async def install_claude_cli():
        """Install Claude Code CLI globally"""
        try:
            result = await asyncio.create_subprocess_exec(
                "npm", "install", "-g", "@anthropic-ai/claude-code",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            log.info(f"Claude CLI installation: {stdout.decode()}")
            if stderr:
                log.error(f"Claude CLI installation errors: {stderr.decode()}")
            return result.returncode == 0
        except Exception as e:
            log.error(f"Failed to install Claude CLI: {e}")
            return False


class ClaudeCodeManager:
    """Manages Claude Code configuration and state"""
    
    def __init__(self):
        self.settings = self.load_settings()
    
    def load_settings(self) -> ClaudeCodeSettings:
        """Load settings from file"""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    data = json.load(f)
                    return ClaudeCodeSettings(**data)
            except Exception as e:
                log.error(f"Failed to load Claude Code settings: {e}")
        return ClaudeCodeSettings()
    
    def save_settings(self, settings: ClaudeCodeSettings):
        """Save settings to file"""
        try:
            CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(CONFIG_FILE, 'w') as f:
                json.dump(settings.dict(), f, indent=2)
            self.settings = settings
            
            # Set OAuth token in environment if provided
            if settings.oauth_token:
                os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = settings.oauth_token
            
            return True
        except Exception as e:
            log.error(f"Failed to save Claude Code settings: {e}")
            return False
    
    async def execute_claude(self, message: str, timeout: int = None) -> str:
        """Execute Claude CLI command"""
        if not self.settings.enabled:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Claude Code is disabled"
            )
        
        if not self.settings.oauth_token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Claude Code OAuth token not configured"
            )
        
        timeout = timeout or self.settings.timeout
        cmd = [self.settings.command_path, '--print', message]
        
        try:
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, "CLAUDE_CODE_OAUTH_TOKEN": self.settings.oauth_token}
            )
            
            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=timeout
            )
            
            if stdout:
                return stdout.decode('utf-8').strip()
            elif stderr:
                log.error(f"Claude CLI error: {stderr.decode()}")
                return f"Error: {stderr.decode()}"
            else:
                return "No response from Claude Code CLI."
                
        except asyncio.TimeoutError:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail=f"Claude CLI timed out after {timeout} seconds"
            )
        except Exception as e:
            log.exception(f"Failed to execute Claude CLI: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=str(e)
            )


# Initialize manager
claude_manager = ClaudeCodeManager()


@router.get("/status")
async def get_status(user=Depends(get_admin_user)):
    """Get Claude Code status and installation info"""
    installer = ClaudeCodeInstaller()
    
    # Check Node.js
    node_installed, node_version = await installer.check_node()
    
    # Check Claude CLI
    cli_installed, cli_version = await installer.check_claude_cli()
    
    return {
        "settings": claude_manager.settings.dict(exclude={'oauth_token'}),
        "oauth_configured": bool(claude_manager.settings.oauth_token),
        "node": {
            "installed": node_installed,
            "version": node_version
        },
        "claude_cli": {
            "installed": cli_installed,
            "version": cli_version
        }
    }


@router.get("/settings")
async def get_settings(user=Depends(get_admin_user)):
    """Get Claude Code settings"""
    settings = claude_manager.settings.dict()
    # Mask the OAuth token for security
    if settings.get("oauth_token"):
        token = settings["oauth_token"]
        settings["oauth_token"] = f"{token[:15]}...{token[-4:]}" if len(token) > 20 else "***"
    return settings


@router.post("/settings")
async def update_settings(settings: ClaudeCodeSettings, user=Depends(get_admin_user)):
    """Update Claude Code settings"""
    # Preserve OAuth token if not provided (masked)
    if settings.oauth_token and settings.oauth_token.startswith("sk-ant-oat01-") and "..." in settings.oauth_token:
        settings.oauth_token = claude_manager.settings.oauth_token
    
    # Validate OAuth token format if provided
    if settings.oauth_token and not settings.oauth_token.startswith("sk-ant-oat01-"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OAuth token format. Token should start with 'sk-ant-oat01-'"
        )
    
    # Save settings
    if claude_manager.save_settings(settings):
        return {"status": "success", "message": "Settings updated successfully"}
    else:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save settings"
        )


@router.post("/install")
async def install_claude(user=Depends(get_admin_user)):
    """Install Claude CLI and dependencies"""
    installer = ClaudeCodeInstaller()
    results = {
        "node": {"installed": False, "message": ""},
        "claude_cli": {"installed": False, "message": ""}
    }
    
    # Check/Install Node.js
    node_installed, node_version = await installer.check_node()
    if node_installed:
        results["node"]["installed"] = True
        results["node"]["message"] = f"Already installed ({node_version})"
    else:
        if await installer.install_node():
            results["node"]["installed"] = True
            results["node"]["message"] = "Successfully installed"
        else:
            results["node"]["message"] = "Installation failed - manual installation required"
    
    # Check/Install Claude CLI
    cli_installed, cli_version = await installer.check_claude_cli()
    if cli_installed:
        results["claude_cli"]["installed"] = True
        results["claude_cli"]["message"] = f"Already installed ({cli_version})"
    else:
        if results["node"]["installed"]:
            if await installer.install_claude_cli():
                results["claude_cli"]["installed"] = True
                results["claude_cli"]["message"] = "Successfully installed"
            else:
                results["claude_cli"]["message"] = "Installation failed - run: npm install -g @anthropic-ai/claude-code"
        else:
            results["claude_cli"]["message"] = "Node.js required for installation"
    
    return results


@router.post("/test")
async def test_claude(message: str = "Hello, Claude!", user=Depends(get_admin_user)):
    """Test Claude CLI with a simple message"""
    try:
        response = await claude_manager.execute_claude(message, timeout=10)
        return {"success": True, "response": response}
    except HTTPException as e:
        return {"success": False, "error": e.detail}
    except Exception as e:
        return {"success": False, "error": str(e)}


@router.post("/chat/completions")
async def chat_completions(request: Request, body: dict, user=Depends(get_verified_user)):
    """OpenAI-compatible chat completions endpoint"""
    if not claude_manager.settings.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Claude Code is disabled in settings"
        )
    
    messages = body.get("messages", [])
    stream = body.get("stream", False) and claude_manager.settings.stream_responses
    model = body.get("model", "claude-code")
    
    # Extract conversation context
    context_messages = messages[-claude_manager.settings.max_context_messages:]
    
    # Build conversation prompt
    conversation = []
    for msg in context_messages:
        role = msg.get("role", "")
        content = msg.get("content", "")
        
        if isinstance(content, list):
            text_parts = []
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    text_parts.append(part.get("text", ""))
                elif isinstance(part, str):
                    text_parts.append(part)
            content = " ".join(text_parts)
        
        if role and content:
            conversation.append(f"{role}: {content}")
    
    # Get the last user message
    user_message = conversation[-1].replace("user: ", "") if conversation else "Hello"
    
    log.info(f"Processing Claude Code request from user {user.email}: {user_message[:100]}...")
    
    try:
        response_text = await claude_manager.execute_claude(user_message)
        
        if stream:
            async def generate_stream():
                chunk_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
                created = int(time.time())
                
                # Stream response in chunks
                for i in range(0, len(response_text), 50):
                    chunk = {
                        "id": chunk_id,
                        "object": "chat.completion.chunk",
                        "created": created,
                        "model": model,
                        "choices": [{
                            "index": 0,
                            "delta": {"content": response_text[i:i+50]},
                            "finish_reason": None
                        }]
                    }
                    yield f"data: {json.dumps(chunk)}\n\n"
                
                # Final chunk
                final_chunk = {
                    "id": chunk_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop"
                    }]
                }
                yield f"data: {json.dumps(final_chunk)}\n\n"
                yield "data: [DONE]\n\n"
            
            return StreamingResponse(
                generate_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "X-Accel-Buffering": "no"
                }
            )
        else:
            # Non-streaming response
            return {
                "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": response_text
                    },
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
        log.exception(f"Error in Claude Code chat: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )


# Function/Tool for installation (can be called programmatically)
async def install_claude_code_tool(oauth_token: str = None, auto_enable: bool = True) -> dict:
    """
    Tool to install and configure Claude Code in Open WebUI
    
    Args:
        oauth_token: Claude Pro OAuth token
        auto_enable: Automatically enable after installation
    
    Returns:
        Installation result with status
    """
    installer = ClaudeCodeInstaller()
    results = {"success": False, "steps": {}}
    
    try:
        # Step 1: Check/Install Node.js
        node_ok, node_ver = await installer.check_node()
        if not node_ok:
            node_ok = await installer.install_node()
        results["steps"]["node"] = {"success": node_ok, "version": node_ver}
        
        # Step 2: Check/Install Claude CLI
        cli_ok, cli_ver = await installer.check_claude_cli()
        if not cli_ok and node_ok:
            cli_ok = await installer.install_claude_cli()
        results["steps"]["claude_cli"] = {"success": cli_ok, "version": cli_ver}
        
        # Step 3: Configure settings
        if cli_ok and oauth_token:
            settings = ClaudeCodeSettings(
                enabled=auto_enable,
                oauth_token=oauth_token,
                auto_install=True
            )
            config_ok = claude_manager.save_settings(settings)
            results["steps"]["configuration"] = {"success": config_ok}
            
            # Step 4: Test connection
            if config_ok:
                try:
                    test_response = await claude_manager.execute_claude("Hello", timeout=5)
                    results["steps"]["test"] = {
                        "success": bool(test_response),
                        "response": test_response[:100] if test_response else None
                    }
                except:
                    results["steps"]["test"] = {"success": False}
        
        results["success"] = all(
            step.get("success", False) 
            for step in results["steps"].values()
        )
        
    except Exception as e:
        results["error"] = str(e)
    
    return results