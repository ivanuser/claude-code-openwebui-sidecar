#!/bin/bash

# Quick Fix - Auto-detects container or uses provided name
CONTAINER=${1:-$(docker ps --format "{{.Names}}" | grep -E "open-webui|open_webui|openwebui" | head -1)}

if [ -z "$CONTAINER" ]; then
    echo "Usage: $0 [container_name]"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    exit 1
fi

echo "Using container: $CONTAINER"

# Create fix script
cat << 'PYTHON_FIX' > /tmp/fix_imports.py
import os
import re

def fix_main_py():
    filepath = "/app/backend/open_webui/main.py"
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        print("Fixing main.py...")
        
        # Remove old references
        content = content.replace('claude_code_simple as claude_code,', '')
        content = content.replace('claude_code_simple,', '')
        
        # Add correct import if not present
        if 'claude_code_integrated as claude_code' not in content:
            import_pattern = r'(from open_webui\.routers import \([^)]+)\)'
            match = re.search(import_pattern, content, re.DOTALL)
            if match:
                imports_block = match.group(1)
                if 'claude_code' not in imports_block:
                    new_imports = imports_block + ',\n    claude_code_integrated as claude_code'
                    content = content.replace(match.group(0), new_imports + ')')
        
        # Add router if not present
        if 'claude_code.router' not in content:
            router_pattern = r'(app\.include_router\(utils\.router[^)]+\))'
            match = re.search(router_pattern, content)
            if match:
                router_line = match.group(0)
                new_router = router_line + '\napp.include_router(claude_code.router, prefix="/api/v1/claude-code", tags=["claude-code"])'
                content = content.replace(router_line, new_router)
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        print("✓ Fixed main.py")
        return True
        
    except Exception as e:
        print(f"Error fixing main.py: {e}")
        return False

def fix_models_py():
    filepath = "/app/backend/open_webui/utils/models.py"
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        print("Fixing models.py...")
        
        content = content.replace(
            'from open_webui.routers.claude_code_simple import claude_code_config',
            'from open_webui.routers.claude_code_integrated import claude_manager'
        )
        
        content = content.replace('claude_code_config.enabled', 'claude_manager.settings.enabled')
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        print("✓ Fixed models.py")
        return True
        
    except Exception as e:
        print(f"Error fixing models.py: {e}")
        return False

def fix_chat_py():
    filepath = "/app/backend/open_webui/utils/chat.py"
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        print("Fixing chat.py...")
        
        content = content.replace(
            'from open_webui.routers.claude_code_simple import chat_completions',
            'from open_webui.routers.claude_code_integrated import chat_completions'
        )
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        print("✓ Fixed chat.py")
        return True
        
    except Exception as e:
        print(f"Error fixing chat.py: {e}")
        return False

if __name__ == "__main__":
    print("Applying fixes...")
    
    success = True
    success &= fix_main_py()
    success &= fix_models_py() 
    success &= fix_chat_py()
    
    if success:
        print("\n✓ All fixes applied")
    else:
        print("\n⚠ Some fixes failed")
PYTHON_FIX

# Apply fix
echo "Applying comprehensive fixes to $CONTAINER..."
docker cp /tmp/fix_imports.py "$CONTAINER:/tmp/"
docker exec "$CONTAINER" python3 /tmp/fix_imports.py

# Clean up
rm /tmp/fix_imports.py
docker exec "$CONTAINER" rm /tmp/fix_imports.py

echo ""
echo "Restarting container..."
docker restart "$CONTAINER"

echo ""
echo "✅ Fix complete! Container restarted."
echo "Check if Open WebUI is working now."