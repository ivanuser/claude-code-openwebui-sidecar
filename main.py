"""
Claude Code Sidecar Service
A standalone API service that provides Claude Code functionality to Open WebUI
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

from fastapi import FastAPI, HTTPException, status
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = FastAPI(
    title="Claude Code Sidecar",
    description="Provides Claude Code CLI capabilities as an API service",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Config(BaseModel):
    """Configuration for Claude Code service"""
    enabled: bool = True
    command_path: str = "claude"
    timeout: int = 60
    oauth_token: Optional[str] = None
    openwebui_url: Optional[str] = None
    api_key: Optional[str] = None  # API key for authentication


# Initialize configuration from environment
config = Config(
    enabled=os.getenv("CLAUDE_CODE_ENABLED", "true").lower() == "true",
    command_path=os.getenv("CLAUDE_CODE_PATH", "claude"),
    timeout=int(os.getenv("CLAUDE_CODE_TIMEOUT", "60")),
    oauth_token=os.getenv("CLAUDE_CODE_OAUTH_TOKEN"),
    openwebui_url=os.getenv("OPENWEBUI_URL"),
    api_key=os.getenv("CLAUDE_CODE_API_KEY")
)


@app.on_event("startup")
async def startup_event():
    """Initialize Claude Code CLI on startup"""
    if config.oauth_token:
        # Set the OAuth token environment variable
        os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = config.oauth_token
        log.info("Claude Code OAuth token configured")
    
    # Test Claude CLI availability
    try:
        result = subprocess.run(
            [config.command_path, "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            log.info(f"Claude Code CLI initialized: {result.stdout.strip()}")
        else:
            log.error(f"Claude Code CLI error: {result.stderr}")
    except Exception as e:
        log.error(f"Failed to initialize Claude Code CLI: {e}")


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "claude-code-sidecar"}


@app.get("/api/v1/models")
async def get_models():
    """Return available Claude Code models"""
    if not config.enabled:
        return {"data": []}
    
    return {
        "data": [{
            "id": "claude-code",
            "name": "Claude Code",
            "object": "model",
            "created": int(time.time()),
            "owned_by": "claude-code-cli",
            "permission": [],
            "root": "claude-code",
            "parent": None
        }]
    }


@app.post("/api/v1/chat/completions")
async def chat_completions(body: dict):
    """
    OpenAI-compatible chat completions endpoint
    This is the main endpoint that Open WebUI will call
    """
    if not config.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Claude Code service is disabled"
        )
    
    # Validate API key if configured
    if config.api_key:
        auth_header = body.get("headers", {}).get("authorization", "")
        if not auth_header or auth_header != f"Bearer {config.api_key}":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid API key"
            )
    
    messages = body.get("messages", [])
    stream = body.get("stream", False)
    model = body.get("model", "claude-code")
    
    # Extract last user message
    user_message = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, list):
                text_parts = []
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        text_parts.append(part.get("text", ""))
                    elif isinstance(part, str):
                        text_parts.append(part)
                user_message = " ".join(text_parts)
            else:
                user_message = content
            break
    
    if not user_message:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No user message found"
        )
    
    log.info(f"Processing message: {user_message[:100]}...")
    
    async def generate_response():
        """Generate response from Claude CLI"""
        try:
            # Execute Claude CLI command
            cmd = [config.command_path, '--print', user_message]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ}
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    result.communicate(),
                    timeout=config.timeout
                )
                
                response_text = ""
                if stdout:
                    response_text = stdout.decode('utf-8').strip()
                
                if not response_text:
                    response_text = "No response from Claude Code CLI."
                
                # Return response in OpenAI format
                if stream:
                    # Stream the response in chunks
                    chunk_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
                    created = int(time.time())
                    
                    # Send content chunks
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
                    
                    # Send final chunk
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
                else:
                    # Return complete response
                    response = {
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
                    yield json.dumps(response)
                
            except asyncio.TimeoutError:
                log.error(f"Claude CLI timed out after {config.timeout}s")
                error_response = {
                    "error": {
                        "message": f"Claude CLI timed out after {config.timeout} seconds",
                        "type": "timeout_error",
                        "code": "timeout"
                    }
                }
                yield json.dumps(error_response)
        
        except Exception as e:
            log.exception(f"Error in Claude Code: {e}")
            error_response = {
                "error": {
                    "message": str(e),
                    "type": "internal_error",
                    "code": "internal_error"
                }
            }
            yield json.dumps(error_response)
    
    if stream:
        return StreamingResponse(
            generate_response(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no"
            }
        )
    else:
        response_gen = generate_response()
        response = ""
        async for chunk in response_gen:
            response = chunk
        
        try:
            parsed = json.loads(response) if response else {}
            return JSONResponse(content=parsed)
        except json.JSONDecodeError:
            return JSONResponse(content={"error": {"message": "Invalid response"}})


@app.post("/api/v1/register")
async def register_with_openwebui(openwebui_url: str, api_key: Optional[str] = None):
    """
    Register this sidecar service with an Open WebUI instance
    This endpoint can be called to automatically configure Open WebUI
    """
    config.openwebui_url = openwebui_url
    if api_key:
        config.api_key = api_key
    
    # TODO: Implement automatic registration with Open WebUI
    # This would involve calling Open WebUI's admin API to add this service
    
    return {
        "status": "success",
        "message": "Service registered",
        "service_url": f"http://{os.getenv('HOSTNAME', 'localhost')}:8100"
    }


@app.get("/api/v1/status")
async def get_status():
    """Get service status"""
    try:
        result = subprocess.run(
            [config.command_path, "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        return {
            "status": "active" if result.returncode == 0 else "error",
            "enabled": config.enabled,
            "version": result.stdout.strip() if result.returncode == 0 else None,
            "error": result.stderr if result.returncode != 0 else None
        }
    except Exception as e:
        return {
            "status": "error",
            "enabled": config.enabled,
            "error": str(e)
        }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8100)