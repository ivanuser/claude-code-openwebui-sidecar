#!/bin/bash

# Claude Code Docker Diagnostic Script
# Checks the installation and identifies issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Claude Code Docker Diagnostic${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Get container name
read -p "Enter your Open WebUI container name: " CONTAINER

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}No container specified${NC}"
    exit 1
fi

# Check if container exists and is running
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
    echo -e "${RED}Error: Container '$CONTAINER' not found or not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container found: $CONTAINER${NC}"
echo ""

# Function to check file
check_file() {
    local file=$1
    local description=$2
    
    if docker exec "$CONTAINER" test -f "$file" 2>/dev/null; then
        echo -e "${GREEN}✓ $description exists${NC}"
        return 0
    else
        echo -e "${RED}✗ $description missing${NC}"
        return 1
    fi
}

# Function to check import
check_import() {
    local file=$1
    local import=$2
    local description=$3
    
    if docker exec "$CONTAINER" grep -q "$import" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓ $description${NC}"
        return 0
    else
        echo -e "${RED}✗ $description${NC}"
        return 1
    fi
}

echo "Checking files..."
echo "----------------"

# Check injected files
check_file "/app/backend/open_webui/routers/claude_code_integrated.py" "Claude router"
check_file "/app/src/lib/components/admin/Settings/ClaudeCode.svelte" "Admin panel component"
check_file "/app/src/lib/apis/claudecode.ts" "API client"
check_file "/app/backend/data/claude_code_config.json" "Configuration file"

echo ""
echo "Checking Python imports..."
echo "-------------------------"

# Check main.py
check_import "/app/backend/open_webui/main.py" "claude_code" "main.py has Claude import"
check_import "/app/backend/open_webui/main.py" "claude_code.router" "main.py has Claude router"

# Check if there's a conflict with old version
if docker exec "$CONTAINER" grep -q "claude_code_simple" "/app/backend/open_webui/main.py" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Old claude_code_simple import found - needs fixing${NC}"
fi

echo ""
echo "Checking Python syntax..."
echo "-------------------------"

# Test Python imports
if docker exec "$CONTAINER" python3 -c "import sys; sys.path.insert(0, '/app/backend'); from open_webui.routers import claude_code_integrated" 2>/dev/null; then
    echo -e "${GREEN}✓ Claude router imports correctly${NC}"
else
    echo -e "${RED}✗ Claude router import fails${NC}"
    echo "  Attempting detailed error check..."
    docker exec "$CONTAINER" python3 -c "import sys; sys.path.insert(0, '/app/backend'); from open_webui.routers import claude_code_integrated" 2>&1 | head -10
fi

echo ""
echo "Checking container logs for errors..."
echo "-------------------------------------"

# Get recent error logs
ERROR_COUNT=$(docker logs "$CONTAINER" 2>&1 | tail -100 | grep -c "ERROR\|Exception\|Traceback" || true)

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${RED}Found $ERROR_COUNT errors in recent logs:${NC}"
    docker logs "$CONTAINER" 2>&1 | tail -100 | grep -A2 "ERROR\|Exception\|Traceback" | head -20
else
    echo -e "${GREEN}✓ No errors in recent logs${NC}"
fi

echo ""
echo "Checking Node.js and Claude CLI..."
echo "----------------------------------"

# Check Node.js
if docker exec "$CONTAINER" node --version 2>/dev/null; then
    NODE_VERSION=$(docker exec "$CONTAINER" node --version)
    echo -e "${GREEN}✓ Node.js installed: $NODE_VERSION${NC}"
else
    echo -e "${RED}✗ Node.js not found${NC}"
fi

# Check Claude CLI
if docker exec "$CONTAINER" claude --version 2>/dev/null; then
    CLAUDE_VERSION=$(docker exec "$CONTAINER" claude --version)
    echo -e "${GREEN}✓ Claude CLI installed: $CLAUDE_VERSION${NC}"
else
    echo -e "${RED}✗ Claude CLI not found${NC}"
fi

echo ""
echo "Configuration status..."
echo "----------------------"

# Check config
if docker exec "$CONTAINER" test -f "/app/backend/data/claude_code_config.json" 2>/dev/null; then
    echo -e "${GREEN}✓ Configuration file exists${NC}"
    echo "  Content:"
    docker exec "$CONTAINER" cat "/app/backend/data/claude_code_config.json" 2>/dev/null | head -5
else
    echo -e "${YELLOW}⚠ No configuration file${NC}"
fi

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Diagnostic Summary${NC}"
echo -e "${BLUE}============================================${NC}"

# Provide recommendations
echo ""
echo "Recommendations:"

if docker exec "$CONTAINER" grep -q "claude_code_simple" "/app/backend/open_webui/main.py" 2>/dev/null; then
    echo "1. Fix import conflict - run:"
    echo "   docker exec $CONTAINER sed -i 's/claude_code_simple/claude_code_integrated/g' /app/backend/open_webui/main.py"
    echo "   docker restart $CONTAINER"
fi

if ! docker exec "$CONTAINER" test -f "/app/backend/open_webui/routers/claude_code_integrated.py" 2>/dev/null; then
    echo "1. Re-run the installer to inject missing files"
fi

echo ""
echo "If Open WebUI shows 500 error:"
echo "1. Check detailed Python errors above"
echo "2. Consider using rollback script"
echo "3. Or use the sidecar method instead"
echo ""