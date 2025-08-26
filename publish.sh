#!/bin/bash

# Script to publish the Claude Code Sidecar repository to GitHub

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Claude Code Sidecar - GitHub Publisher${NC}"
echo "========================================"
echo ""

# Check if gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}"
    echo "Please run: gh auth login"
    exit 1
fi

# Get GitHub username
GITHUB_USER=$(gh api user --jq .login)
echo "GitHub user: $GITHUB_USER"
echo ""

# Create repository
echo "Creating repository on GitHub..."
gh repo create claude-code-openwebui-sidecar \
    --public \
    --source=. \
    --remote=origin \
    --description="Standalone Docker service that adds Claude Code CLI capabilities to Open WebUI without modifications" \
    --push

echo ""
echo -e "${GREEN}✓ Repository published successfully!${NC}"
echo ""
echo "Repository URL: https://github.com/$GITHUB_USER/claude-code-openwebui-sidecar"
echo ""
echo "Next steps:"
echo "1. Visit your repository: https://github.com/$GITHUB_USER/claude-code-openwebui-sidecar"
echo "2. Add topics: 'open-webui', 'claude', 'docker', 'sidecar'"
echo "3. Share with the Open WebUI community!"
echo ""
echo "To clone on another machine:"
echo "  git clone https://github.com/$GITHUB_USER/claude-code-openwebui-sidecar.git"