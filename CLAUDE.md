# Hardened Moltbot Railway Template

## Overview

Security-first Moltbot deployment for Railway with hardened defaults. Built to compete with existing templates while prioritizing security, proper auth, and Core sync capabilities.

**Runtime:** Bun (wrapper) + Node.js (Moltbot CLI)
**Key Features:**
- Non-root container (uid 1001)
- Token injection fix for Control UI
- Command execution disabled by default
- Rate limiting on setup endpoints
- 1-year auth tokens via `claude setup-token`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RAILWAY CONTAINER                         │
│                    (oven/bun + node)                         │
│                                                              │
│  ┌─────────────────┐      ┌─────────────────────────────┐   │
│  │  Wrapper Server │      │    Moltbot Gateway          │   │
│  │   (Bun:8080)    │─────▶│     (Node:18789)            │   │
│  │                 │      │                             │   │
│  │  - /setup UI    │      │  - Control UI               │   │
│  │  - /setup/api/* │      │  - WebSocket API            │   │
│  │  - Token inject │      │  - Channel handlers         │   │
│  │  - Rate limit   │      │  - LLM routing              │   │
│  │  - Proxy        │      │                             │   │
│  └─────────────────┘      └─────────────────────────────┘   │
│                                                              │
│  Volume: /data                                               │
│    ├── .moltbot/     (state, config, auth)                  │
│    ├── workspace/    (files created by moltbot)             │
│    └── core/         (Core sync directory)                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Model

### Hardened Defaults

| Setting | Default | Why |
|---------|---------|-----|
| `nodes.run.enabled` | `false` | Prevent arbitrary command execution |
| `gateway.auth.mode` | `token` | Require authentication for all gateway access |
| `gateway.bind` | `loopback` | Only wrapper can reach gateway |
| `dmPolicy` | `pairing` | Require approval for new DM conversations |
| `groupPolicy` | `allowlist` | Explicit approval for group chats |

### Trust Ladder

1. **Setup Password** - Access to /setup UI
2. **Gateway Token** - Access to Control UI and API
3. **Channel Pairing** - Per-user approval for messaging
4. **Command Execution** - Disabled by default, allowlist only

### Rate Limiting

- 30 requests per minute on `/setup/*` endpoints
- Prevents brute-force attacks on setup password

---

## Environment Variables

### Required

```bash
SETUP_PASSWORD=<min-16-chars>  # Protects /setup UI
```

### Auto-Generated

```bash
MOLTBOT_GATEWAY_TOKEN=<32-byte-hex>  # Generated if not set, persisted in /data
```

### Optional

```bash
# Directories
MOLTBOT_STATE_DIR=/data/.moltbot
MOLTBOT_WORKSPACE_DIR=/data/workspace
MOLTBOT_CORE_DIR=/data/core

# Ports
MOLTBOT_PUBLIC_PORT=8080
INTERNAL_GATEWAY_PORT=18789

# Core sync (Phase 2)
GITHUB_TOKEN=ghp_xxx
CORE_REPO=slayga/Core
CORE_BRANCH=main
CORE_SYNC_INTERVAL_MINUTES=15
```

---

## CLI Commands

### Container Access

```bash
# SSH into Railway container
railway shell

# Or via Railway CLI
railway run bash
```

### Auth Setup (1-Year Tokens)

```bash
# Create long-lived Anthropic token
claude setup-token
# Follow browser auth flow, token syncs to Moltbot automatically
```

### Moltbot CLI

```bash
# Status
moltbot status
moltbot health
moltbot models status

# Config
moltbot config get <key>
moltbot config set <key> <value>
moltbot doctor --fix

# Channels
moltbot channels list
moltbot channels add telegram --bot-token <token>
moltbot pairing approve telegram <CODE>

# Security
moltbot security audit
moltbot config get nodes.run.enabled

# Update
moltbot update
```

---

## File Structure

```
moltbot-railway-hardened/
├── CLAUDE.md                 # This file
├── README.md                 # User documentation
├── Dockerfile                # Multi-stage, non-root, Bun + Node
├── railway.toml              # Railway config
├── package.json              # Wrapper dependencies
├── src/
│   ├── server.js            # Bun wrapper server
│   └── setup-app.js         # Client-side setup UI
└── config/
    └── gateway-defaults.json # Hardened defaults (Phase 3)
```

---

## Key Fixes Over Vignesh Template

| Issue | Fix |
|-------|-----|
| Token injection bug | Redirect `/moltbot/*` paths to include `?token=` |
| Runs as root | Non-root `moltbot` user (uid 1001) |
| No pnpm in runtime | Installed for `moltbot update` |
| No Claude CLI | Installed for `claude setup-token` |
| No trustedProxies | Pre-configured for Railway |
| Command execution open | Disabled by default |
| Node.js only | Bun wrapper for performance |

---

## Endpoints

### Health

- `GET /setup/healthz` - Health check (no auth)

### Setup UI

- `GET /setup` - Onboarding wizard (Basic auth with SETUP_PASSWORD)
- `GET /setup/app.js` - Client-side JavaScript

### Setup API

- `GET /setup/api/status` - Configuration status
- `POST /setup/api/run` - Run onboarding
- `POST /setup/api/pairing/approve` - Approve DM pairing
- `POST /setup/api/reset` - Reset configuration
- `GET /setup/api/debug` - Debug info
- `GET /setup/export` - Download backup tarball

### Gateway Proxy

- `/moltbot/*` - Proxied to gateway with token injection
- All other paths - Proxied to gateway

---

## Development

### Local Testing

```bash
# Install dependencies
bun install

# Run locally (needs moltbot installed)
SETUP_PASSWORD=test1234567890123456 bun run src/server.js
```

### Docker Build

```bash
docker build -t moltbot-railway-hardened .
docker run -p 8080:8080 \
  -e SETUP_PASSWORD=test1234567890123456 \
  -v moltbot_data:/data \
  moltbot-railway-hardened
```

---

## Deployment Checklist

- [ ] Set `SETUP_PASSWORD` in Railway Variables (min 16 chars)
- [ ] Deploy and verify `/setup/healthz` returns ok
- [ ] Access `/setup` with password
- [ ] Select auth provider (recommend: Anthropic token via `claude setup-token`)
- [ ] Add Telegram bot token if desired
- [ ] Run onboarding
- [ ] SSH in and run `claude setup-token` for 1-year auth
- [ ] Test Telegram pairing
- [ ] Verify Control UI at `/moltbot`

---

## Core Sync

Git-based bidirectional sync for The Core (Obsidian vault).

### Environment Variables

```bash
GITHUB_TOKEN=ghp_xxx           # GitHub PAT with repo access
CORE_REPO=slayga/Core          # owner/repo format
CORE_BRANCH=main               # Branch to sync (default: main)
CORE_SYNC_INTERVAL_MINUTES=15  # Background sync interval (default: 15, 0 to disable)
```

### API Endpoints

- `GET /setup/api/core/status` - Current sync status and recent commits
- `POST /setup/api/core/init` - Clone and initialize Core repo
- `POST /setup/api/core/sync` - Trigger manual sync (pull + push)
- `POST /setup/api/core/commit` - Commit and push specific changes

### How It Works

1. **Initialize**: Clones the repo to `/data/core`
2. **Background Sync**: Runs every 15 minutes (configurable)
3. **Pull**: Fetches remote changes, rebases local changes
4. **Push**: Commits and pushes local changes
5. **Conflict Resolution**: Accepts remote version on conflicts (preserves remote, logs conflict)

### Usage via Moltbot

Once Core sync is initialized, Moltbot can:
- Read notes from `/data/core/`
- Create/update notes (changes auto-sync)
- Access The Core as a knowledge base

---

## Session Log

### 2025-01-30

- Implemented hardened template based on plan
- Multi-stage Dockerfile with Bun runtime
- Non-root user (uid 1001)
- Token injection fix for Control UI
- Rate limiting on /setup/* endpoints
- Security headers
- Disabled command execution by default
- Added Core sync module with git-based bidirectional sync

---

## References

- Moltbot Docs: https://docs.moltbot.dev/
- Railway Guide: https://docs.moltbot.dev/railway
- Docker Guide: https://docs.moltbot.dev/install/docker
- Vignesh Template: https://github.com/vignesh07/clawdbot-railway-template
