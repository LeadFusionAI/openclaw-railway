# Security Model

This template ships with secure defaults. This document explains what's protected and how.

## The Three Security Layers

OpenClaw has three complementary security mechanisms:

| Layer | What It Does | Works on Railway? |
|-------|--------------|-------------------|
| **Tool Policy** | Controls which tools agents can use | Yes |
| **Sandbox** | Isolates execution in Docker containers | No (requires Docker-in-Docker) |
| **Elevated Mode** | Escape hatch for host exec when sandboxed | Yes (disabled by default) |

Since Railway doesn't support Docker-in-Docker, this template relies on **Tool Policy** and **Linux File Permissions** as the primary security mechanisms.

## Default Configuration (Tier 0)

Out of the box, your agent can:
- Chat via messaging channels
- Read/write files in the workspace
- Fetch and read web pages
- Search memories (auto-configured with OpenRouter/OpenAI)
- List directories (`ls` only)
- Schedule cron jobs

Everything else is blocked:

```json5
{
  agents: {
    defaults: {
      tools: {
        allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec", "cron"],
        deny: ["process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"]
      }
    }
  }
}
```

### Filesystem Protection

OpenClaw's Docker-based filesystem sandbox (`tools.fs` blocklist) is not available on Railway — the gateway rejects `tools.fs` as an unrecognized config key. Instead, this template uses **Linux file permissions** to protect sensitive paths:

| Path | Owner | Perms | Agent can read? | Agent can write? |
|------|-------|-------|-----------------|------------------|
| `/data/.openclaw/openclaw.json` | root:openclaw | 640 | Yes (gateway needs this) | **No** |
| `/data/.openclaw/` directory | root:openclaw | 750 | Traverse only | **No** (can't create files) |
| `/home/openclaw/.openclaw/` | root:openclaw | 750 | Traverse only | **No** |
| `exec-approvals.json` | root:openclaw | 640 | Yes | **No** |
| `/data/workspace/` | openclaw:openclaw | 755 | Yes | Yes |
| `/proc/self/environ` | (process UID) | 400 | Yes (known limitation) | No |

**How it works:** The entrypoint runs as root, generates the config, then changes ownership to `root:openclaw` with group-read permissions. The gateway (running as `openclaw`) can read the config at startup, but the agent's `write` tool gets EACCES when trying to overwrite it. This blocks the privilege escalation attack where the agent rewrites `openclaw.json` to grant itself blocked tools.

**Known limitation:** The agent can read `/proc/self/environ` which contains environment variables including API keys. This cannot be blocked without upstream OpenClaw changes (tools run in the same process as the gateway). Mitigation: non-essential secrets are scrubbed from the environment after config generation, and the agent's behavioral instructions prohibit reading sensitive paths.

## What Each Blocked Tool Does

| Tool | Risk | Why It's Blocked |
|------|------|------------------|
| `exec` | Critical | Run arbitrary shell commands |
| `process` | Critical | Manage background processes, bypass approval |
| `browser` | High | Access logged-in sessions, run JavaScript |
| `nodes` | High | Camera/screen capture, device control |
| `web_search` | Medium | External network access |
| `web_fetch` | Medium | Fetch arbitrary URLs |
| `gateway` | Critical | Modify gateway configuration |
| `agents_list` | Medium | Enumerate other agents |
| `memory_search` | Low | Semantic search requires embeddings provider |
| `sessions_spawn` | Medium | Create unlimited subagents |

## Access Control

### Owner Allowlist

When you set `TELEGRAM_OWNER_ID` (or Discord/Slack equivalent), you're added to the allowlist. You can message the bot immediately without pairing.

### Pairing for Others

Anyone else who messages the bot gets a pairing code. They must share it with you, and you approve via SSH:

```bash
openclaw pairing approve telegram <CODE>
```

Or set `dmPolicy: "allowlist"` and manually add user IDs.

### Session Isolation

Each user gets their own conversation context:

```json5
{
  session: {
    dmScope: "per-channel-peer"
  }
}
```

User A cannot see User B's conversation history.

## Gateway Security

The gateway is bound to loopback only:

```json5
{
  gateway: {
    bind: "loopback",
    auth: { mode: "token" }
  }
}
```

This means:
- Gateway is not accessible from outside the container
- Token authentication required for any connection
- Health endpoint (`/healthz`) reveals nothing sensitive

## What Railway Protects

Railway's container provides hard boundaries:

| Protection | Description |
|------------|-------------|
| Container isolation | Agent cannot escape to Railway host |
| Network isolation | No access to other Railway services |
| Volume isolation | `/data` is your persistent storage only |
| Secret injection | Env vars injected at runtime, not stored in image |

## What Railway Cannot Protect

| Risk | Mitigation |
|------|------------|
| Prompt injection | Tool policy limits blast radius |
| API key theft | Config file write-locked; env vars partially scrubbed; behavioral instructions prohibit reading secrets |
| Data exfiltration | No network tools by default |
| Resource exhaustion | Railway's resource limits apply |

## Unlocking More Capabilities

See [TIERS.md](TIERS.md) for how to progressively enable:
- Web search (Tier 1)
- Shell access with allowlist (Tier 2)
- Automation and subagents (Tier 3)
- Full trust (Tier 4)

## Security Audit

SSH in and run:

```bash
openclaw security audit --deep
```

This checks for common misconfigurations.

## Dangerous Configurations

**Never do these:**

| Configuration | Risk |
|---------------|------|
| `gateway.bind: "lan"` | Exposes gateway to network |
| `gateway.bind: "0.0.0.0"` | Exposes gateway to internet |
| `dmPolicy: "open"` | Anyone can use your bot |
| `tools.deny: []` | All tools available |
| `elevated.enabled: true` | Host exec escape available |
| API keys in config file | Stored on disk, potentially leaked |

## Environment Variables

API keys and tokens should always be set as Railway environment variables, not in `openclaw.json`. Railway encrypts these at rest and injects them at runtime.

See [config/environment.md](../config/environment.md) for the full list.

## Further Reading

- [OpenClaw Security Docs](https://docs.openclaw.ai/gateway/security)
- [Tool Policy vs Sandbox vs Elevated](https://docs.openclaw.ai/gateway/sandbox-vs-tool-policy-vs-elevated)
- [Threat Model](THREAT-MODEL.md)
