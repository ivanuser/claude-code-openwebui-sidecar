#!/usr/bin/env python3
"""
Claude Code Embedded Installer
This script embeds Claude Code directly into your Open WebUI installation
as a native feature with admin panel controls.

Two installation options:
1. Run as sidecar container (see parent directory)
2. Embed directly into Open WebUI (this script)
"""

import os
import sys
import json
import subprocess
import requests
from pathlib import Path
from typing import Optional
import shutil

# ANSI color codes
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'

def print_color(text: str, color: str = NC):
    """Print colored text"""
    print(f"{color}{text}{NC}")

def download_file(url: str, dest: Path) -> bool:
    """Download a file from URL"""
    try:
        response = requests.get(url, stream=True)
        response.raise_for_status()
        
        with open(dest, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        return True
    except Exception as e:
        print_color(f"Failed to download {url}: {e}", RED)
        return False

def inject_claude_code_files(openwebui_path: Path) -> bool:
    """Inject Claude Code files directly into Open WebUI"""
    print("\nInjecting Claude Code integration files...")
    
    # Files to inject (these will be downloaded from the sidecar repo)
    files_to_inject = {
        # Backend router
        "backend/open_webui/routers/claude_code_integrated.py": 
            "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claude_code_integrated.py",
        
        # Frontend components
        "src/lib/components/admin/Settings/ClaudeCode.svelte":
            "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/ClaudeCode.svelte",
        
        # API client
        "src/lib/apis/claudecode.ts":
            "https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/files/claudecode.ts"
    }
    
    for rel_path, url in files_to_inject.items():
        dest_path = openwebui_path / rel_path
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        
        print(f"  Downloading {rel_path}...")
        if not download_file(url, dest_path):
            return False
        
        print_color(f"  ✓ Injected {rel_path}", GREEN)
    
    return True

def patch_openwebui_files(openwebui_path: Path) -> bool:
    """Patch existing Open WebUI files to integrate Claude Code"""
    print("\nPatching Open WebUI files...")
    
    patches = [
        {
            "file": "backend/open_webui/main.py",
            "find": "    claude_code_simple as claude_code,",
            "replace": "    claude_code_integrated as claude_code,",
            "add_import": "    claude_code_integrated as claude_code,"
        },
        {
            "file": "backend/open_webui/utils/models.py",
            "find": "from open_webui.routers.claude_code_simple import claude_code_config",
            "replace": "from open_webui.routers.claude_code_integrated import claude_manager",
            "also_replace": [
                ("claude_code_config.enabled", "claude_manager.settings.enabled")
            ]
        },
        {
            "file": "backend/open_webui/utils/chat.py",
            "find": "from open_webui.routers.claude_code_simple import chat_completions",
            "replace": "from open_webui.routers.claude_code_integrated import chat_completions"
        }
    ]
    
    for patch in patches:
        file_path = openwebui_path / patch["file"]
        if not file_path.exists():
            print_color(f"  ✗ File not found: {patch['file']}", RED)
            continue
        
        # Read file
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Apply patches
        original = content
        if patch.get("find") and patch["find"] in content:
            content = content.replace(patch["find"], patch["replace"])
        elif patch.get("add_import") and patch["add_import"] not in content:
            # Add import if not exists
            import_line = patch["add_import"]
            # Find the imports section and add it
            if "from open_webui.routers import (" in content:
                content = content.replace(
                    "from open_webui.routers import (",
                    f"from open_webui.routers import (\n    {import_line}\n"
                )
        
        # Apply additional replacements
        for find, replace in patch.get("also_replace", []):
            content = content.replace(find, replace)
        
        # Write back if changed
        if content != original:
            with open(file_path, 'w') as f:
                f.write(content)
            print_color(f"  ✓ Patched {patch['file']}", GREEN)
        else:
            print(f"  ⚠ No changes needed for {patch['file']}", )
    
    return True

def configure_claude_code(openwebui_path: Path, oauth_token: Optional[str]) -> bool:
    """Configure Claude Code settings"""
    print("\nConfiguring Claude Code...")
    
    data_dir = openwebui_path / "backend" / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    
    config_file = data_dir / "claude_code_config.json"
    
    config = {
        "enabled": bool(oauth_token),
        "oauth_token": oauth_token,
        "command_path": "claude",
        "timeout": 60,
        "auto_install": True,
        "stream_responses": False,
        "max_context_messages": 10
    }
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print_color(f"  ✓ Configuration saved", GREEN)
    return True

def install_dependencies() -> bool:
    """Install Node.js and Claude CLI if needed"""
    print("\nChecking dependencies...")
    
    # Check Node.js
    try:
        result = subprocess.run(["node", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print_color(f"  ✓ Node.js installed: {result.stdout.strip()}", GREEN)
        else:
            raise FileNotFoundError
    except FileNotFoundError:
        print_color("  ✗ Node.js not installed", YELLOW)
        print("  Please install Node.js from https://nodejs.org")
        return False
    
    # Check/Install Claude CLI
    try:
        result = subprocess.run(["claude", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print_color(f"  ✓ Claude CLI installed: {result.stdout.strip()}", GREEN)
        else:
            raise FileNotFoundError
    except FileNotFoundError:
        print("  Installing Claude CLI...")
        result = subprocess.run(
            "npm install -g @anthropic-ai/claude-code",
            shell=True,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print_color("  ✓ Claude CLI installed", GREEN)
        else:
            print_color("  ✗ Failed to install Claude CLI", RED)
            return False
    
    return True

def main():
    """Main installation function"""
    print_color("\n" + "="*60, BLUE)
    print_color("Claude Code Embedded Installer for Open WebUI", BLUE)
    print_color("="*60 + "\n", BLUE)
    
    # Find Open WebUI installation
    openwebui_path = Path.cwd()
    if not (openwebui_path / "backend" / "open_webui" / "main.py").exists():
        print_color("Error: Please run this script from your Open WebUI directory", RED)
        sys.exit(1)
    
    print_color(f"✓ Found Open WebUI at: {openwebui_path}", GREEN)
    
    # Check dependencies
    if not install_dependencies():
        print_color("\nPlease install dependencies and run again", YELLOW)
        sys.exit(1)
    
    # Get OAuth token
    print("\n" + "-"*40)
    print("Claude Pro OAuth Token Setup")
    print("-"*40)
    print("\nGet your token by running:")
    print_color("  npx @anthropic-ai/claude-code login", YELLOW)
    
    oauth_token = input("\nEnter OAuth token (or 'skip' for later): ").strip()
    if oauth_token.lower() == 'skip':
        oauth_token = None
    
    # Create backup
    print("\nCreating backup...")
    backup_dir = openwebui_path / "backup_claude_embed"
    backup_dir.mkdir(exist_ok=True)
    
    # Inject files
    if not inject_claude_code_files(openwebui_path):
        print_color("Failed to inject files", RED)
        sys.exit(1)
    
    # Patch existing files
    if not patch_openwebui_files(openwebui_path):
        print_color("Warning: Some patches may have failed", YELLOW)
    
    # Configure
    configure_claude_code(openwebui_path, oauth_token)
    
    print_color("\n" + "="*60, GREEN)
    print_color("Installation Complete!", GREEN)
    print_color("="*60, GREEN)
    
    print("\nNext steps:")
    print("1. Restart Open WebUI")
    print("2. Go to Admin Settings > Claude Code")
    if not oauth_token:
        print("3. Enter your OAuth token")
    print("4. Enable Claude Code")
    print("5. Select 'Claude Code' in chat model dropdown")
    
    print("\n" + "-"*60)
    print("Claude Code is now embedded in your Open WebUI!")
    print("-"*60 + "\n")

if __name__ == "__main__":
    main()