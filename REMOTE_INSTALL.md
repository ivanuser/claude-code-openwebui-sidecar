# Remote Installation Guide

For installing Claude Code on a remote production server running Open WebUI in Docker.

## Method 1: Sidecar Container (SAFEST for Production)

This method runs Claude Code as a separate container - no modifications to your Open WebUI.

### On your production server:

```bash
# SSH to your production server
ssh your-server

# Clone the repository
git clone https://github.com/ivanuser/claude-code-openwebui-sidecar.git
cd claude-code-openwebui-sidecar

# Configure
cp .env.example .env
nano .env  # Add your OAuth token

# Start sidecar
docker-compose up -d

# Configure in Open WebUI Admin
# Add OpenAI connection with URL: http://claude-code-sidecar:8100/api/v1
```

## Method 2: Embedded Integration (Advanced)

⚠️ **WARNING**: This modifies your Open WebUI container. Test first!

### Prerequisites

1. SSH access to your production server
2. Docker access on that server
3. Backup your data first!

### Installation Steps

1. **SSH to your production server**:
```bash
ssh your-server
```

2. **Download and run installer**:
```bash
# Download the installer
curl -O https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/install_docker.sh

# Review the script first!
less install_docker.sh

# Run installer
bash install_docker.sh
```

3. **If something goes wrong - ROLLBACK**:
```bash
# Download rollback script
curl -O https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/rollback_docker.sh

# Run rollback
bash rollback_docker.sh
```

## Important Notes

### For Production Environments:

1. **Always backup first**:
```bash
docker exec your-container tar -czf /tmp/backup.tar.gz /app/backend
docker cp your-container:/tmp/backup.tar.gz ./backup.tar.gz
```

2. **Test on staging first** if possible

3. **The sidecar method is safer** - it doesn't modify your Open WebUI

4. **Monitor logs after installation**:
```bash
docker logs -f your-container
```

### Troubleshooting

If Open WebUI shows 500 error after embedded installation:

1. **Check logs**:
```bash
docker logs your-container --tail 100
```

2. **Run rollback immediately**:
```bash
curl -sL https://raw.githubusercontent.com/ivanuser/claude-code-openwebui-sidecar/master/embed-installer/rollback_docker.sh | bash
```

3. **Use sidecar method instead** - it's isolated and safer

### Getting Your OAuth Token

On your LOCAL machine (not the server):
```bash
npx @anthropic-ai/claude-code login
```

Copy the token that starts with `sk-ant-oat01-` to use during installation.

## Comparison

| Method | Risk | Complexity | Features |
|--------|------|------------|----------|
| **Sidecar** | Low | Easy | Basic integration |
| **Embedded** | Medium | Moderate | Full admin panel |

## Support

If you encounter issues:

1. Check the [Issues](https://github.com/ivanuser/claude-code-openwebui-sidecar/issues) page
2. The sidecar method is always the safest fallback
3. Keep the rollback script handy when using embedded method