#!/bin/bash

# Claude Code Import Fix Script
# Fixes the Python imports in Open WebUI files

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Import Fix${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Get container name
read -p "Enter your Open WebUI container name: " CONTAINER

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}No container specified${NC}"
    exit 1
fi

# Check container
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
    echo -e "${RED}Error: Container '$CONTAINER' not found or not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container found: $CONTAINER${NC}"

# Create a comprehensive fix script
cat << 'PYTHON_FIX' > /tmp/fix_imports.py
#!/usr/bin/env python3
import os
import re

def fix_main_py():
    filepath = "/app/backend/open_webui/main.py"
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        print("Fixing main.py...")
        
        # Remove any old claude_code_simple references
        content = content.replace('claude_code_simple as claude_code,', '')
        content = content.replace('claude_code_simple,', '')
        
        # Add the correct import if not present
        if 'claude_code_integrated as claude_code' not in content:
            # Find the import block
            import_pattern = r'(from open_webui\.routers import \([^)]+)\)'
            match = re.search(import_pattern, content, re.DOTALL)
            if match:
                imports_block = match.group(1)
                if 'claude_code' not in imports_block:
                    # Add to the end of imports
                    new_imports = imports_block + ',\n    claude_code_integrated as claude_code'
                    content = content.replace(match.group(0), new_imports + ')')
        
        # Add router if not present
        if 'claude_code.router' not in content:
            # Find where to add router
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
        
        # Replace imports
        content = content.replace(
            'from open_webui.routers.claude_code_simple import claude_code_config',
            'from open_webui.routers.claude_code_integrated import claude_manager'
        )
        
        # Replace usage
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
        
        # Replace import
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
    print("Applying comprehensive fixes...")
    
    success = True
    success &= fix_main_py()
    success &= fix_models_py()
    success &= fix_chat_py()
    
    if success:
        print("\n✓ All fixes applied successfully")
    else:
        print("\n⚠ Some fixes may have failed")
    
    print("\nTesting imports...")
    try:
        import sys
        sys.path.insert(0, '/app/backend')
        from open_webui.routers import claude_code_integrated
        print("✓ Import test passed")
    except Exception as e:
        print(f"✗ Import test failed: {e}")
PYTHON_FIX

# Copy and run the fix
echo "Applying comprehensive fixes..."
docker cp /tmp/fix_imports.py "$CONTAINER:/tmp/"
docker exec "$CONTAINER" python3 /tmp/fix_imports.py

# Clean up
rm /tmp/fix_imports.py
docker exec "$CONTAINER" rm /tmp/fix_imports.py

echo ""
echo "Restarting container..."
docker restart "$CONTAINER"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Fix Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "The container has been restarted with fixed imports."
echo "Please check if Open WebUI is working now."
echo ""