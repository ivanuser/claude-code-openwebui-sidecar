#!/bin/bash
# Quick installer - downloads and runs the appropriate installer

echo "Claude Code Quick Installer"
echo "=========================="
echo ""
echo "Choose installation type:"
echo "1) Docker container (production)"
echo "2) Local installation (development)"
echo ""
read -p "Enter choice [1-2]: " choice

case $choice in
    1)
        echo "Installing into Docker container..."
        curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/install_docker.sh | bash
        ;;
    2)
        echo "Installing locally..."
        curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/install_embedded.py -o install_embedded.py
        python install_embedded.py
        rm install_embedded.py
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac