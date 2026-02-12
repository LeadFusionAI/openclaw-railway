# Environment Variables

This document lists all environment variables the template supports. Set these in Railway's dashboard before deploying.

## Required (at least one LLM provider)

You need at least one LLM provider API key for the agent to function.

| Variable | Description |
|----------|-------------|
| `LLM_API_KEY` | Generic fallback - used if no specific provider key is set |

### Provider-Specific Keys

Set the key for your preferred provider(s). You can set multiple for fallbacks.

**Major Cloud Providers:**
| Variable | Provider |
|----------|----------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `GOOGLE_AI_API_KEY` | Google AI Studio (Gemini) |

**Aggregators/Gateways:**
| Variable | Provider |
|----------|----------|
| `OPENROUTER_API_KEY` | OpenRouter (access many models) |
| `VERCEL_GATEWAY_API_KEY` | Vercel AI Gateway |

**Fast Inference:**
| Variable | Provider |
|----------|----------|
| `GROQ_API_KEY` | Groq |
| `TOGETHER_API_KEY` | Together AI |
| `FIREWORKS_API_KEY` | Fireworks AI |

**Coding-Focused:**
| Variable | Provider |
|----------|----------|
| `ZAI_API_KEY` | Z.AI |
| `KIMI_API_KEY` | Kimi Coding |
| `MOONSHOT_API_KEY` | Moonshot AI (Kimi) |
| `MINIMAX_API_KEY` | MiniMax |
| `DEEPSEEK_API_KEY` | DeepSeek |

**Other Providers:**
| Variable | Provider |
|----------|----------|
| `XAI_API_KEY` | xAI (Grok) |
| `MISTRAL_API_KEY` | Mistral |
| `VENICE_API_KEY` | Venice AI (privacy-focused) |
| `CLOUDFLARE_API_KEY` | Cloudflare AI |

**AWS Bedrock:**
| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_REGION` | AWS region (e.g., us-east-1) |

## Model Selection (Required)

You **must** set `LLM_PRIMARY_MODEL` to match your provider.

| Variable | Purpose |
|----------|---------|
| `LLM_PRIMARY_MODEL` | **Required** - Main model for conversations |
| `LLM_HEARTBEAT_MODEL` | Optional - Cheap model for periodic check-ins |
| `LLM_SUBAGENT_MODEL` | Optional - Model for delegated tasks |
| `LLM_FALLBACK_MODELS` | Optional - Comma-separated fallback list |

### Format

```
LLM_PRIMARY_MODEL=provider/model-name
```

Example: `LLM_PRIMARY_MODEL=groq/llama-3.3-70b-versatile`

### Finding Model Names

Check your provider's documentation for current model IDs:
- **Groq**: https://console.groq.com/docs/models
- **OpenRouter**: https://openrouter.ai/models
- **Anthropic**: https://docs.anthropic.com/en/docs/models
- **OpenAI**: https://platform.openai.com/docs/models
- **Google**: https://ai.google.dev/models
- **DeepSeek**: https://platform.deepseek.com/docs
- **Kimi/Moonshot**: https://platform.moonshot.cn/docs
- **ZAI**: https://docs.zai.dev/models

**Tip:** Start with a fast, cheap model to verify your setup works, then upgrade as needed.

## Channels

### Telegram

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather |
| `TELEGRAM_OWNER_ID` | Your Telegram user ID (get from @userinfobot) - skips pairing |

### Discord

| Variable | Description |
|----------|-------------|
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `DISCORD_OWNER_ID` | Your Discord user ID - skips pairing |

### Slack

| Variable | Description |
|----------|-------------|
| `SLACK_BOT_TOKEN` | Slack bot token (xoxb-...) |
| `SLACK_APP_TOKEN` | Slack app token (xapp-...) |
| `SLACK_OWNER_ID` | Your Slack user ID - skips pairing |

## Gateway

| Variable | Description | Default |
|----------|-------------|---------|
| `GATEWAY_TOKEN` | Authentication token for gateway | Auto-generated |
| `GATEWAY_PORT` | Port for gateway (internal) | `18789` |

## Optional

| Variable | Description |
|----------|-------------|
| `AGENT_NAME` | Display name for your agent |
| `WORKSPACE_DIR` | Workspace directory path |

---

## Quick Start Examples

### Minimal (Groq + Telegram)

```
GROQ_API_KEY=gsk_...
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
```

### Multi-Provider (Smart primary, cheap heartbeat)

```
OPENROUTER_API_KEY=sk-or-...
GROQ_API_KEY=gsk_...
LLM_PRIMARY_MODEL=openrouter/anthropic/claude-sonnet-4
LLM_HEARTBEAT_MODEL=groq/llama-3.1-8b-instant
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
```

### Multiple Channels

```
OPENROUTER_API_KEY=sk-or-...
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
DISCORD_BOT_TOKEN=MTIz...
DISCORD_OWNER_ID=123456789012345678
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_OWNER_ID=U01234567
```
