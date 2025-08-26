# Claude Code for Open WebUI

Two ways to add Claude Code CLI capabilities to your Open WebUI:

## 🚀 Choose Your Installation Method

| Feature | Sidecar Container | Embedded Integration |
|---------|------------------|---------------------|
| **Modifies Open WebUI** | ❌ No | ✅ Yes |
| **Admin Panel Controls** | ❌ No | ✅ Yes |
| **Separate Container** | ✅ Yes | ❌ No |
| **Easy Uninstall** | ✅ Yes | ⚠️ Manual |
| **Resource Usage** | Higher (2 containers) | Lower (1 container) |
| **Best For** | Production, Multiple instances | Single instance, Full control |

### Option 1: 🐳 Sidecar Container
Run Claude Code as a separate Docker service alongside Open WebUI. No modifications to your Open WebUI installation required.

### Option 2: 🔧 Embedded Integration
Install Claude Code directly into Open WebUI with admin panel controls, settings management, and native UI integration.

## Features

- ✨ **Two Installation Options** - Choose sidecar or embedded based on your needs
- 🎛️ **Admin Panel Controls** (Embedded) - Full settings management in Open WebUI admin
- 🔌 **OpenAI-Compatible API** - Works with Open WebUI's model system
- 🐳 **Docker Support** - Easy deployment with Docker Compose
- 🔒 **Secure** - OAuth token authentication
- 🚀 **Claude Pro Support** - Requires Claude Pro subscription
- 💬 **Full Chat Support** - Complete conversation context handling

## Prerequisites

- Docker and Docker Compose installed
- Running Open WebUI instance
- Claude Pro subscription with OAuth token

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/claude-code-openwebui-sidecar.git
cd claude-code-openwebui-sidecar
```

### 2. Get Your Claude OAuth Token

```bash
# Install Claude Code CLI globally
npm install -g @anthropic-ai/claude-code

# Login to get your OAuth token
npx @anthropic-ai/claude-code login

# Copy the token that starts with 'sk-ant-oat01-'
```

### 3. Run the Installer

```bash
./install.sh
```

The installer will:
- Check for existing Open WebUI installation
- Configure your Claude OAuth token
- Set up the Docker container
- Provide instructions for Open WebUI configuration

### 4. Configure Open WebUI

1. Open your Open WebUI admin panel
2. Go to **Admin Settings > Connections**
3. Add a new OpenAI API connection:
   - **Name**: Claude Code
   - **API Base URL**: `http://claude-code-sidecar:8100/api/v1`
   - **API Key**: (use the generated key from installation or leave empty)
4. Save the connection

### 5. Start Chatting

Select "Claude Code" from the model dropdown in your chat interface and start using Claude with code execution capabilities!

## Option 2: Embedded Integration Installation

### For Docker Deployments (Production)

One-line installer for Docker containers:

```bash
curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/install_docker.sh | bash
```

This will:
- Auto-detect your Open WebUI container
- Install Node.js and Claude CLI in the container
- Inject Claude Code files
- Configure OAuth token
- Restart container

### For Local Installations (Development)

```bash
cd /path/to/your/open-webui
curl -O https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/install_embedded.py
python install_embedded.py
```

### 3. Follow the Prompts

The installer will:
- Check for Node.js and Claude CLI
- Inject Claude Code files into Open WebUI
- Set up admin panel components
- Configure OAuth token

### 4. Access Admin Panel

After restarting Open WebUI:
1. Go to **Admin Settings > Claude Code**
2. Enter your OAuth token if not done during installation
3. Enable Claude Code
4. Configure settings as needed

### 5. Use Claude Code

Select "Claude Code" from the model dropdown in any chat!

---

## Option 1: Sidecar Container Installation (Manual)

### 1. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and add your Claude OAuth token:

```env
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

### 2. Start the Service

```bash
docker-compose up -d
```

### 3. Configure in Open WebUI

Add as an OpenAI API connection with:
- API Base URL: `http://claude-code-sidecar:8100/api/v1`

## Configuration Options

All configuration is done through environment variables in the `.env` file:

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Your Claude Pro OAuth token (required) | - |
| `CLAUDE_CODE_API_KEY` | API key to secure the service | - |
| `OPENWEBUI_URL` | URL of your Open WebUI instance | `http://localhost:8080` |
| `CLAUDE_CODE_ENABLED` | Enable/disable the service | `true` |
| `CLAUDE_CODE_TIMEOUT` | Timeout for Claude commands (seconds) | `60` |
| `CLAUDE_CODE_PATH` | Path to Claude CLI binary | `claude` |
| `CLAUDE_WORKING_DIR` | Working directory for file access | `./workspace` |

## Architecture

The sidecar runs as a separate Docker container that:
1. Exposes an OpenAI-compatible API on port 8100
2. Translates requests to Claude Code CLI commands
3. Returns responses in OpenAI format
4. Connects to Open WebUI's Docker network

```
┌─────────────────┐         ┌──────────────────┐
│   Open WebUI    │ ──API──> │  Claude Sidecar  │
│   (Port 8080)   │ <──JSON─ │   (Port 8100)    │
└─────────────────┘         └──────────────────┘
                                      │
                                      ▼
                              ┌──────────────────┐
                              │  Claude CLI      │
                              │  (via OAuth)     │
                              └──────────────────┘
```

## Troubleshooting

### Service won't start

Check the logs:
```bash
docker logs claude-code-sidecar
```

### Claude Code not appearing in model list

1. Ensure the service is running: `docker ps | grep claude-code`
2. Verify the connection in Open WebUI settings
3. Check network connectivity between containers

### Authentication errors

1. Verify your OAuth token is valid
2. Ensure the token is properly set in `.env`
3. Try re-authenticating with `npx @anthropic-ai/claude-code login`

### Connection refused errors

Ensure both containers are on the same Docker network:
```bash
docker network inspect open-webui_default
```

## Commands

```bash
# View logs
docker logs -f claude-code-sidecar

# Stop the service
docker-compose down

# Restart the service
docker-compose restart

# Update and rebuild
git pull
docker-compose up -d --build

# Check service health
curl http://localhost:8100/health
```

## API Endpoints

The sidecar provides these OpenAI-compatible endpoints:

- `GET /api/v1/models` - List available models
- `POST /api/v1/chat/completions` - Chat completions
- `GET /api/v1/status` - Service status
- `GET /health` - Health check

## Security Considerations

1. **API Key Protection**: Always use an API key in production environments
2. **Network Isolation**: The service should only be accessible from Open WebUI
3. **Token Security**: Keep your Claude OAuth token secure and never commit it to git
4. **Port Exposure**: Only expose port 8100 if necessary for debugging

## Development

### Building Locally

```bash
docker build -t claude-code-sidecar .
```

### Running Tests

```bash
# Test the API
curl -X POST http://localhost:8100/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-code",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Open WebUI](https://github.com/open-webui/open-webui) for the amazing interface
- [Anthropic](https://anthropic.com) for Claude and Claude Code CLI
- Community contributors

## Support

For issues, questions, or suggestions, please open an issue on GitHub.

---

**Note**: This is an unofficial integration. Claude Code and Anthropic are trademarks of Anthropic, PBC.