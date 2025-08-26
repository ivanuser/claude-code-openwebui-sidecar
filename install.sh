#!/bin/bash

# Claude Code Sidecar Installation Script
# This script helps deploy Claude Code alongside existing Open WebUI installations

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Claude Code Sidecar Installer${NC}"
echo "================================"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."

if ! command_exists docker; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Check for existing Open WebUI installation
echo "Checking for Open WebUI installation..."

# Try to find Open WebUI container
OPENWEBUI_CONTAINER=$(docker ps -q -f name=open-webui 2>/dev/null || true)
OPENWEBUI_NETWORK="open-webui_default"

if [ -z "$OPENWEBUI_CONTAINER" ]; then
    echo -e "${YELLOW}Warning: No running Open WebUI container found${NC}"
    echo "Please ensure Open WebUI is running before continuing."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ Found Open WebUI container${NC}"
    
    # Get Open WebUI URL
    OPENWEBUI_PORT=$(docker port open-webui 2>/dev/null | grep -oP '0.0.0.0:\K[0-9]+' | head -1 || echo "8080")
    OPENWEBUI_URL="http://localhost:${OPENWEBUI_PORT}"
    echo "  Open WebUI URL: $OPENWEBUI_URL"
    
    # Check network
    if docker network inspect $OPENWEBUI_NETWORK >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Found Open WebUI network${NC}"
    else
        OPENWEBUI_NETWORK=$(docker inspect $OPENWEBUI_CONTAINER --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -1)
        echo "  Using network: $OPENWEBUI_NETWORK"
    fi
fi

echo ""

# Configure Claude OAuth Token
echo "Claude Authentication Setup"
echo "---------------------------"

if [ -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${YELLOW}Existing .env file found${NC}"
    read -p "Do you want to reconfigure? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.backup"
        echo "Backed up existing .env to .env.backup"
    else
        echo "Using existing configuration"
        SKIP_CONFIG=true
    fi
fi

if [ "$SKIP_CONFIG" != "true" ]; then
    # Copy example env file
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    
    echo ""
    echo "You need a Claude Pro OAuth token to use Claude Code."
    echo ""
    echo "To get your token:"
    echo "1. Install Claude Code CLI: npm install -g @anthropic-ai/claude-code"
    echo "2. Login: npx @anthropic-ai/claude-code login"
    echo "3. Copy the token that starts with 'sk-ant-oat01-'"
    echo ""
    
    read -p "Enter your Claude OAuth token: " CLAUDE_TOKEN
    
    if [ -z "$CLAUDE_TOKEN" ]; then
        echo -e "${RED}Error: OAuth token is required${NC}"
        exit 1
    fi
    
    # Update .env file
    sed -i "s|CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_TOKEN|" "$SCRIPT_DIR/.env"
    
    # Optional: Configure API key for security
    echo ""
    read -p "Set an API key to secure the service? (recommended) (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        API_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        echo "Generated API key: $API_KEY"
        sed -i "s|CLAUDE_CODE_API_KEY=.*|CLAUDE_CODE_API_KEY=$API_KEY|" "$SCRIPT_DIR/.env"
        echo -e "${YELLOW}Save this API key! You'll need it to configure Open WebUI.${NC}"
    fi
    
    # Set Open WebUI URL if detected
    if [ ! -z "$OPENWEBUI_URL" ]; then
        sed -i "s|OPENWEBUI_URL=.*|OPENWEBUI_URL=$OPENWEBUI_URL|" "$SCRIPT_DIR/.env"
    fi
fi

echo ""
echo "Building and starting Claude Code sidecar..."

# Update docker-compose to use correct network
if [ ! -z "$OPENWEBUI_NETWORK" ]; then
    sed -i "s|name: open-webui_default.*|name: $OPENWEBUI_NETWORK|" "$SCRIPT_DIR/docker-compose.yaml"
fi

# Build and start the container
cd "$SCRIPT_DIR"
if command_exists docker-compose; then
    docker-compose up -d --build
else
    docker compose up -d --build
fi

# Wait for service to be healthy
echo ""
echo "Waiting for service to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -f http://localhost:8100/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Claude Code sidecar is running${NC}"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
    echo -n "."
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}Error: Service failed to start${NC}"
    echo "Check logs with: docker logs claude-code-sidecar"
    exit 1
fi

echo ""
echo "================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo ""
echo "Claude Code sidecar is running at: http://localhost:8100"
echo ""
echo "Next steps:"
echo "1. Open your Open WebUI admin panel"
echo "2. Go to Admin Settings > Connections"
echo "3. Add a new OpenAI API connection with:"
echo "   - Name: Claude Code"
echo "   - API Base URL: http://claude-code-sidecar:8100/api/v1"

if [ ! -z "$API_KEY" ]; then
    echo "   - API Key: $API_KEY"
else
    echo "   - API Key: (leave empty or use any value)"
fi

echo "4. Save and the 'claude-code' model should appear in your chat"
echo ""
echo "Commands:"
echo "  View logs:    docker logs -f claude-code-sidecar"
echo "  Stop service: docker-compose down (in $SCRIPT_DIR)"
echo "  Restart:      docker-compose restart"
echo ""