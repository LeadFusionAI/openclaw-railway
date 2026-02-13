# LLM Providers

Configure your preferred LLM provider via environment variables.

## Setting Up a Provider

1. Get an API key from your chosen provider
2. Set the corresponding environment variable in Railway
3. Optionally set `LLM_PRIMARY_MODEL` to specify which model to use

## Supported Providers

| Provider | Environment Variable | Example Model Format | Voice |
|----------|---------------------|---------------------|-------|
| OpenRouter | `OPENROUTER_API_KEY` | `openrouter/provider/model` | No |
| Groq | `GROQ_API_KEY` | `groq/model-name` | Yes |
| Together AI | `TOGETHER_API_KEY` | `together/org/model` | No |
| Venice AI | `VENICE_API_KEY` | `venice/model-name` | No |
| Google AI | `GOOGLE_AI_API_KEY` | `google/model-name` | No |
| Mistral | `MISTRAL_API_KEY` | `mistral/model-name` | No |
| OpenAI | `OPENAI_API_KEY` | `openai/model-name` | Yes |
| Anthropic | `ANTHROPIC_API_KEY` | `anthropic/model-name` | No |
| xAI | `XAI_API_KEY` | `xai/model-name` | No |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek/model-name` | No |
| Cloudflare | `CLOUDFLARE_API_KEY` | `cloudflare/model-name` | No |

> **Voice column:** Indicates whether the provider supports automatic voice message transcription (e.g., Telegram voice notes). If your primary provider doesn't support voice, add an OpenAI or Groq key alongside it — OpenClaw will use it for transcription automatically. Deepgram (`DEEPGRAM_API_KEY`) also supports voice but is a dedicated transcription service, not a general LLM provider.

## Model Configuration

### Primary Model

Set via environment variable:
```
LLM_PRIMARY_MODEL=provider/model-name
```

### Task-Specific Models (Tier 2+)

Use different models for different tasks to optimize cost/performance:

```
LLM_PRIMARY_MODEL=provider/smart-model
LLM_HEARTBEAT_MODEL=provider/cheap-model
LLM_SUBAGENT_MODEL=provider/balanced-model
```

### Fallback Models

Comma-separated list of fallbacks if primary fails:

```
LLM_FALLBACK_MODELS=provider1/model1,provider2/model2
```

## Changing Models

There are three ways to change your model, depending on what you need:

### 1. `/model` in chat (temporary)

Type `/model` in Telegram/Discord/Slack to see available models and switch. This is great for experimenting, but **only lasts for the current session** — it resets when the conversation ends.

### 2. Railway environment variable (permanent, requires redeploy)

Change `LLM_PRIMARY_MODEL` in Railway Dashboard → Variables, then redeploy. This is the simplest way to make a permanent change at Tier 0.

### 3. `openclaw models set` via SSH (permanent, no redeploy — Tier 2+)

```bash
railway ssh
openclaw models set provider/model-name
```

This writes to a separate models config file and takes effect immediately without restarting. Requires SSH access (Tier 2+).

## Multiple Providers

You can set multiple provider API keys. The agent will use whichever provider matches the model you specify.

## OAuth Providers

Some providers (e.g., Google AI via Vertex, Gemini CLI) use OAuth instead of API keys. These require SSH access to complete the authentication flow (generate URLs, paste redirect codes), so they're only practical at Tier 2+.

API-key providers work at all tiers.

## Cost Considerations

Costs vary significantly by provider, model, and how much you use the agent. There's no universal answer to "how much will this cost?"

**What you should do:**
- Check your provider's pricing page before choosing a model
- Set spending limits or alerts in your provider's dashboard — most providers support this
- Monitor your usage for the first few days to establish a baseline

**Cost optimization:**
- Use a cheaper/faster model for `LLM_HEARTBEAT_MODEL` (periodic check-ins don't need your smartest model)
- Use a balanced model for `LLM_SUBAGENT_MODEL` (Tier 3) — subagents do focused tasks, not open-ended conversation
- Aggregators like OpenRouter let you compare pricing across providers for the same model family

## Troubleshooting

### "API key not found"
Ensure the environment variable is set in Railway Dashboard.

### "Model not found" / "Unknown model"
Check the model name format matches your provider's expectations. OpenClaw validates models against an internal registry — very new models may not be recognized until OpenClaw updates. At Tier 2+, you can define custom models via `models.providers` in the config. See [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers) for details.

### Switching providers
Update the environment variable and redeploy, or SSH in and update the config.

## Further Reading

- [OpenClaw Providers Docs](https://docs.openclaw.ai/providers)
- [OpenClaw Configuration](https://docs.openclaw.ai/gateway/configuration)
