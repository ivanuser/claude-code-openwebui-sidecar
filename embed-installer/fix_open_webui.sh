#!/bin/bash

# Direct fix for open-webui container - no detection needed
CONTAINER="open-webui"

echo "🔧 Fixing Claude Code imports in container: $CONTAINER"

# Verify container exists
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
    echo "❌ Container 'open-webui' not found"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

echo "✅ Container found, applying fixes..."

# Create the fix script
docker exec "$CONTAINER" bash -c 'cat > /tmp/fix.py << '\''EOF'\''
import os
import re

def fix_main_py():
    filepath = "/app/backend/open_webui/main.py"
    
    with open(filepath, "r") as f:
        content = f.read()
    
    print("Fixing main.py...")
    
    # Remove old claude_code_simple references
    content = content.replace("claude_code_simple as claude_code,", "")
    
    # Add claude_code_integrated if not present
    if "claude_code_integrated as claude_code" not in content:
        # Find import section and add it
        if "from open_webui.routers import (" in content:
            pattern = r"(from open_webui\.routers import \([^)]+)\)"
            match = re.search(pattern, content, re.DOTALL)
            if match:
                imports = match.group(1)
                new_imports = imports + ",\n    claude_code_integrated as claude_code"
                content = content.replace(match.group(0), new_imports + ")")
    
    # Add router if not present
    if "claude_code.router" not in content:
        if "app.include_router(utils.router" in content:
            pattern = r"(app\.include_router\(utils\.router[^)]+\))"
            match = re.search(pattern, content)
            if match:
                old_line = match.group(0)
                new_line = old_line + '\napp.include_router(claude_code.router, prefix="/api/v1/claude-code", tags=["claude-code"])'
                content = content.replace(old_line, new_line)
    
    with open(filepath, "w") as f:
        f.write(content)
    
    print("✅ Fixed main.py")

def fix_models_py():
    filepath = "/app/backend/open_webui/utils/models.py"
    
    try:
        with open(filepath, "r") as f:
            content = f.read()
        
        print("Fixing models.py...")
        
        # Replace imports and usage
        content = content.replace(
            "from open_webui.routers.claude_code_simple import claude_code_config",
            "from open_webui.routers.claude_code_integrated import claude_manager"
        )
        content = content.replace("claude_code_config.enabled", "claude_manager.settings.enabled")
        
        with open(filepath, "w") as f:
            f.write(content)
        
        print("✅ Fixed models.py")
    except:
        print("⚠️ models.py may not need fixing")

def fix_chat_py():
    filepath = "/app/backend/open_webui/utils/chat.py"
    
    try:
        with open(filepath, "r") as f:
            content = f.read()
        
        print("Fixing chat.py...")
        
        content = content.replace(
            "from open_webui.routers.claude_code_simple import chat_completions",
            "from open_webui.routers.claude_code_integrated import chat_completions"
        )
        
        with open(filepath, "w") as f:
            f.write(content)
        
        print("✅ Fixed chat.py")
    except:
        print("⚠️ chat.py may not need fixing")

# Apply all fixes
fix_main_py()
fix_models_py()
fix_chat_py()

print("\n🎉 All fixes applied!")
EOF'

# Run the fix
docker exec "$CONTAINER" python3 /tmp/fix.py

# Clean up
docker exec "$CONTAINER" rm /tmp/fix.py

echo ""
echo "🔄 Restarting container..."
docker restart "$CONTAINER"

echo ""
echo "✅ Fix complete!"
echo "👀 Check if Open WebUI is working now at your URL"
echo ""