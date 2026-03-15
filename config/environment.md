# Environment Variables

This document lists all environment variables the template supports. Set these in Railway's dashboard before deploying.

## Required (at least one LLM provider)

You need at least one LLM provider API key for the agent to function.

**Recommended: Start with OpenRouter.** One API key gives you access to models from every major provider (OpenAI, Anthropic, Google, MiniMax, DeepSeek, Meta, and more). No custom config needed — just set the key and pick a model. Get a key at https://openrouter.ai/keys

| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | **Recommended** — access to all major models via one key |
| `LLM_API_KEY` | Generic fallback - used if no specific provider key is set |

### Direct Provider Keys

If you prefer to use a provider directly (or need voice transcription), set their key instead. These all work at Tier 0 with just an env var — no SSH needed.

| Variable | Provider | Notes |
|----------|----------|-------|
| `OPENAI_API_KEY` | OpenAI (GPT) | Also enables voice transcription |
| `ANTHROPIC_API_KEY` | Anthropic (Claude) | |
| `GOOGLE_AI_API_KEY` | Google AI Studio (Gemini) | |
| `GROQ_API_KEY` | Groq | Fast inference, also enables voice transcription |
| `TOGETHER_API_KEY` | Together AI | |
| `FIREWORKS_API_KEY` | Fireworks AI | |
| `DEEPSEEK_API_KEY` | DeepSeek | |
| `XAI_API_KEY` | xAI (Grok) | |
| `MISTRAL_API_KEY` | Mistral | |
| `VENICE_API_KEY` | Venice AI (privacy-focused) | |
| `CLOUDFLARE_API_KEY` | Cloudflare AI | |
| `ZAI_API_KEY` | Z.AI | |
| `KIMI_API_KEY` | Kimi Coding | |
| `MOONSHOT_API_KEY` | Moonshot AI (Kimi) | |

### Providers That Need Custom Config (Tier 2+)

These providers require SSH access to configure custom endpoints or complete OAuth flows. They won't work with just an env var at Tier 0.

| Provider | Why |
|----------|-----|
| MiniMax (coding plan) | Uses Anthropic-compatible endpoint (`api.minimax.io/anthropic`) — needs `models.providers` custom config |
| Google Vertex AI | Requires `gcloud` OAuth flow |
| Google Gemini CLI | Requires device-code OAuth |
| Qwen Portal | Requires device-code OAuth |
| GitHub Copilot | Requires token auth flow |

To use these, SSH in at Tier 2+ and configure via `models.providers` in the config. See [Model Providers](https://docs.openclaw.ai/concepts/model-providers) for details.

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

Example: `LLM_PRIMARY_MODEL=openrouter/minimax/MiniMax-M2.5`

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

### Changing Models Later

- **Quick experiment:** Use `/model` in chat to try a different model for the current session (resets when the session ends)
- **Permanent change:** Update `LLM_PRIMARY_MODEL` here and redeploy
- **Permanent without redeploy:** SSH in and run `openclaw models set provider/model-name` (Tier 2+)

See [PROVIDERS.md](../docs/PROVIDERS.md) for more details.

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

## Voice Messages

If your users send voice messages (common on Telegram), OpenClaw automatically transcribes them. Transcription uses your existing LLM provider key — no extra setup needed if your provider supports audio.

**Providers that support voice transcription:**

| Provider | Key | Notes |
|----------|-----|-------|
| OpenAI | `OPENAI_API_KEY` | Uses Whisper-based transcription |
| Groq | `GROQ_API_KEY` | Built-in Whisper support |
| Deepgram | `DEEPGRAM_API_KEY` | Requires separate key |

**Providers that do NOT support voice transcription:**
OpenRouter, Together AI, Venice AI, Mistral, xAI, Cloudflare, Google AI, Anthropic, DeepSeek

If voice messages aren't being transcribed, your provider likely doesn't support audio. Add an OpenAI or Groq key alongside your primary provider to enable it — OpenClaw will use it for transcription automatically.

## Gateway

| Variable | Description | Default |
|----------|-------------|---------|
| `GATEWAY_TOKEN` | Authentication token for gateway | Auto-generated |
| `GATEWAY_PORT` | Port for gateway (internal) | `18789` |

## Security Tier

Control your agent's capabilities via environment variable. No SSH needed for Tiers 0-2.

| Variable | Description | Default |
|----------|-------------|---------|
| `SECURITY_TIER` | Security tier level: `0`, `1`, `2`, or `3` | `0` |

| Tier | Name | What It Adds |
|------|------|-------------|
| 0 | Personal Assistant | Web search/fetch, memory, read/write, ls, cron, apply_patch, image |
| 1 | Capable Agent | + curated exec (find, wc, sort, uniq, git) |
| 2 | Power User | + full exec, browser (remote), sub-agents, process management |
| 3 | Operator | SSH only. Applies Tier 2 via env var, guides you to SSH for the rest |

Setting `SECURITY_TIER=3` via env var applies Tier 2 and writes a marker file so the agent can guide you through the SSH steps for the remaining Tier 3 config.

See [TIERS.md](../docs/TIERS.md) for full details on each tier.

## Embeddings / Semantic Memory

Semantic memory search (`memory_search`) requires an embeddings provider. The template auto-configures this when possible.

| Variable | Description | Default |
|----------|-------------|---------|
| `LLM_EMBEDDING_MODEL` | Override the default embedding model | `openai/text-embedding-3-small` |

**Auto-configuration logic:**
- If `OPENAI_API_KEY` or `GOOGLE_AI_API_KEY` is set → embeddings auto-detected natively (no config needed)
- If only `OPENROUTER_API_KEY` is set → embeddings routed through OpenRouter using `openai/text-embedding-3-small` (or your `LLM_EMBEDDING_MODEL` override)
- If no embeddings-capable provider → falls back to BM25 keyword matching (still works, just less precise)

**To use a specific embedding model through OpenRouter:**
```
LLM_EMBEDDING_MODEL=openai/text-embedding-3-large
```

## Custom Binaries

Install custom tools to `/data/bin/` (persists on the Railway volume across redeploys). SSH in once to install, then set env vars so the entrypoint wires permissions and credentials automatically on every deploy.

| Variable | Description | Example |
|----------|-------------|---------|
| `EXEC_EXTRA_COMMANDS` | Comma-separated binary names to add to exec allowlist | `core-edge,my-tool` |
| `EXTRA_ENV_KEYS` | Comma-separated env var names to pass through to the gateway | `CORE_URL,CORE_API_KEY` |

Binaries must be installed at `/data/bin/<name>`. The entrypoint adds `/data/bin/` to the gateway's PATH and appends each binary to exec-approvals so the agent can use them. At Tier 2+, exec is unrestricted so `EXEC_EXTRA_COMMANDS` has no effect (but `EXTRA_ENV_KEYS` still works).

## Web Search

The `web_search` tool is available at all tiers but requires a Brave Search API key to function. Without it, the tool is in the allow list but calls will fail at runtime.

| Variable | Description |
|----------|-------------|
| `BRAVE_API_KEY` | Brave Search API key — enables `web_search` tool. Get one at https://brave.com/search/api/ |
| `BRAVE_SEARCH_MODE` | Set to `llm-context` for LLM-grounded snippets with source metadata (v2026.3.8+). Default: standard mode |

## Tool Observer

See what your agent is doing in real-time. When enabled, tool call events (read, write, exec, web_fetch, etc.) are batched and sent to your Telegram topic or Discord thread as silent notifications.

| Variable | Description | Default |
|----------|-------------|---------|
| `TOOL_OBSERVER_ENABLED` | Enable tool observer | `false` |
| `TOOL_OBSERVER_CHAT_ID` | Chat/channel ID to send events to | Owner ID |
| `TOOL_OBSERVER_THREAD_ID` | Telegram topic or Discord thread ID | None |
| `TOOL_OBSERVER_VERBOSITY` | `minimal` (tool name only), `normal` (with summary), `verbose` (with duration/status) | `normal` |
| `TOOL_OBSERVER_BATCH_MS` | Batch window before sending (ms) | `2000` |

**Recommended setup:** Create a dedicated Telegram topic (thread) for tool activity so it doesn't clutter your main chat. Set `TOOL_OBSERVER_THREAD_ID` to that topic's ID.

**Note:** Enabling the observer forces gateway log level to `info` with JSON output. This increases log volume in Railway but is required for the observer to see tool events.

## Optional

| Variable | Description |
|----------|-------------|
| `AGENT_NAME` | Display name for your agent |
| `WORKSPACE_DIR` | Workspace directory path |
| `LLM_HEARTBEAT_LIGHT_CONTEXT` | Set to `true` to skip bootstrap-file injection during heartbeat/cron turns — reduces token usage. Useful when heartbeats only need `HEARTBEAT.md` context |

---

## Quick Start Examples

### Recommended (OpenRouter + Telegram)

```
OPENROUTER_API_KEY=sk-or-...
LLM_PRIMARY_MODEL=openrouter/minimax/MiniMax-M2.5
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
```

### With Curated Shell Access (Tier 1)

```
OPENROUTER_API_KEY=sk-or-...
LLM_PRIMARY_MODEL=openrouter/minimax/MiniMax-M2.5
SECURITY_TIER=1
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
```

### Full Power (Tier 2 + Voice)

```
OPENROUTER_API_KEY=sk-or-...
GROQ_API_KEY=gsk_...
LLM_PRIMARY_MODEL=openrouter/anthropic/claude-sonnet-4
SECURITY_TIER=2
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
LLM_PRIMARY_MODEL=openrouter/minimax/MiniMax-M2.5
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_OWNER_ID=987654321
DISCORD_BOT_TOKEN=MTIz...
DISCORD_OWNER_ID=123456789012345678
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_OWNER_ID=U01234567
```
