# OpenClaw Railway Template

## Overview

Minimal, secure OpenClaw deployment for Railway. Gateway runs on loopback, managed via SSH.

## Setup

1. Deploy to Railway (no environment variables required)
2. SSH in: `railway ssh`
3. Run: `openclaw onboard`
4. Message your bot on Telegram/Discord

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 RAILWAY CONTAINER                    │
│                                                      │
│  Health Server (:8080)     Gateway (:18789)         │
│  - /healthz for Railway    - Runs on loopback       │
│  - No sensitive info       - Handles channels       │
│                            - Runs agents            │
│                                                      │
│  Volume: /data/.openclaw (permissions: 700)         │
└─────────────────────────────────────────────────────┘
```

## Security

- Gateway bound to loopback only (never exposed publicly)
- Config files: 600 permissions (user read/write only)
- State directory: 700 permissions
- Non-root user for all OpenClaw operations
- Health endpoint reveals nothing sensitive

## Files

```
openclaw-railway/
├── Dockerfile        # Multi-stage build
├── railway.toml      # Railway config
├── entrypoint.sh     # Starts gateway + health server
├── config-watcher.sh # Auto-starts gateway after onboard
├── package.json      # No dependencies
└── src/server.js     # Health check only (~30 lines)
```

## Commands

After SSH:

```bash
# Initial setup
openclaw onboard

# Check gateway status
ps aux | grep gateway

# View gateway logs
cat /data/.openclaw/gateway.log

# Restart gateway
pkill -f "openclaw gateway"
openclaw gateway run --port 18789 &
```

## Onboard Options

When running `openclaw onboard`, select:

- **Gateway bind**: Loopback (127.0.0.1)
- **Gateway auth**: Token
- **Gateway token**: Leave blank to generate

## Key Docs

- https://docs.openclaw.ai/start/wizard
- https://docs.openclaw.ai/gateway/security
- https://docs.openclaw.ai/cli/gateway
