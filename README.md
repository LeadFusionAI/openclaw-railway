# OpenClaw Railway Template

> Deploy a security-hardened AI assistant to Railway. Progressive trust, not blind trust.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/template/TEMPLATE_CODE?referralCode=TEMPLATE_CODE)

## Quick Start

1. Click **Deploy on Railway** above
2. Set environment variables:
   - `OPENROUTER_API_KEY` — one key, all models ([get one](https://openrouter.ai/keys))
   - `LLM_PRIMARY_MODEL` — e.g. `openrouter/minimax/MiniMax-M2.5`
   - `TELEGRAM_BOT_TOKEN` — from [@BotFather](https://t.me/BotFather)
   - `TELEGRAM_OWNER_ID` — your user ID (from [@userinfobot](https://t.me/userinfobot))
3. Add a volume mounted at `/data`
4. Deploy — message your bot and start chatting

Works with Telegram, Discord, and Slack. See [config/environment.md](config/environment.md) for all options.

## What You Get

An AI assistant that runs 24/7 on your own infrastructure, connected to your chat apps. It remembers conversations, searches the web, takes notes, schedules reminders — and starts locked down by default.

**Default capabilities (Tier 0):**
- Chat via Telegram, Discord, or Slack
- Read/write workspace files (notes, memory)
- Web search and web page reading
- Scheduled reminders and cron jobs
- Semantic memory search

**Unlock more with a single env var change:**

| Tier | Name | What It Adds |
|------|------|-------------|
| 0 | Personal Assistant | Web, memory, read/write, cron *(default)* |
| 1 | Capable Agent | + curated shell (grep, find, git, wc, sort, uniq) |
| 2 | Power User | + full shell, remote browser, sub-agents |
| 3 | Operator | + unrestricted access (requires SSH) |

Set `SECURITY_TIER=1` and redeploy. That's it. See [docs/TIERS.md](docs/TIERS.md) for details.

## Security

This template wraps OpenClaw with 5 layers of hardening:

1. **Filesystem sandboxing** — `workspaceOnly` restricts all file access to `/data/workspace/`
2. **Process isolation** — Gateway runs with `env -i`, no secrets in `/proc/self/environ`
3. **File permissions** — Config files root-owned 640, behavioral templates read-only 440
4. **Behavioral templates** — Agent identity and guardrails restored from image on every deploy
5. **Log filtering** — Response text stripped from deploy logs

**Benchmarked:** In A/B testing across 4 models, the hardened template blocked 89% of attack vectors vs 34% for vanilla OpenClaw. Same models, same keys, same base image — the only difference is the security template. See [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) for methodology.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 RAILWAY CONTAINER                    │
│                                                      │
│  Health Server (:8080)     Gateway (:18789)         │
│  - /healthz endpoint       - Loopback only          │
│  - Public facing           - Handles channels       │
│                                                      │
│  Config: /data/.openclaw/openclaw.json              │
│  Workspace: /data/workspace                         │
└─────────────────────────────────────────────────────┘
```

Config is generated from environment variables on every deploy — no manual editing required.

## Environment Variables

See [config/environment.md](config/environment.md) for the complete reference.

### Required

| Variable | Description |
|----------|-------------|
| `*_API_KEY` | At least one LLM provider key |
| `*_BOT_TOKEN` | At least one channel token |
| `*_OWNER_ID` | Your user ID for instant access |

### Example

```
OPENROUTER_API_KEY=sk-or-...
LLM_PRIMARY_MODEL=openrouter/minimax/MiniMax-M2.5
TELEGRAM_BOT_TOKEN=123456789:ABC...
TELEGRAM_OWNER_ID=987654321
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Environment Variables](config/environment.md) | All supported env vars |
| [Setup Guide](docs/SETUP.md) | Step-by-step deployment |
| [Security Tiers](docs/TIERS.md) | Unlocking capabilities |
| [Security Model](docs/SECURITY.md) | How protection works |
| [Providers](docs/PROVIDERS.md) | LLM provider configuration |
| [Threat Model](docs/THREAT-MODEL.md) | What can go wrong |

## Updating

Redeploy the container. Config regenerates from your environment variables on every startup — no manual intervention needed.

```bash
railway up
```

Never run `openclaw update` inside the container.

## Contributing

Issues and PRs welcome. If you find a security issue, please open an issue or reach out directly rather than posting exploit details publicly.

## License

[MIT](LICENSE)
