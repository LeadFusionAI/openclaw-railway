# Setup Guide — From Zero to Running

This walkthrough takes you from no accounts to a working AI assistant in about 10 minutes.

## What You'll Set Up

| Thing | Why | Cost |
|-------|-----|------|
| Railway account | Hosts your bot 24/7 | $5/mo ([pricing](https://railway.com/pricing?referralCode=slayga)) |
| OpenRouter API key | Gives the bot access to AI models | Pay per use (~$1-5/mo for light use) |
| Telegram bot | How you talk to it | Free |

**Total cost:** ~$5-10/mo for personal use, depending on how much you chat and which model you pick.

---

## Step 0: Create a Railway Account

[Railway](https://railway.com?referralCode=slayga) is a container hosting platform — it runs your bot in the cloud so it stays online 24/7.

1. Go to [railway.com](https://railway.com?referralCode=slayga) and sign up (GitHub login or email) — the links in this guide include a referral code that gives you **$20 in free Railway credits**
2. Subscribe to the **Hobby plan** ($5/mo)
   - The trial works for testing, but services pause after the free tier limits
   - The Hobby plan includes $5 of resource usage per month — this template typically uses less than that
   - Go to your Railway dashboard → Settings → Billing to upgrade

---

## Step 1: Get an OpenRouter API Key

[OpenRouter](https://openrouter.ai) is a single API that gives you access to models from OpenAI, Anthropic, Google, DeepSeek, MiniMax, and more. One key, all models.

1. Sign up at [openrouter.ai](https://openrouter.ai)
2. Go to [Keys](https://openrouter.ai/keys) and click **Create Key**
3. Copy the key (starts with `sk-or-`)
4. Add credits — $5 is plenty to start. Go to [Account → Credits](https://openrouter.ai/credits)

Save this key somewhere — you'll paste it during deploy.

> **Using a different provider?** See [PROVIDERS.md](PROVIDERS.md) for OpenAI, Anthropic, Google, and other options. OpenRouter is the easiest starting point.

---

## Step 2: Create a Telegram Bot

You'll create a bot on Telegram that your AI assistant speaks through.

1. Open [Telegram](https://telegram.org) (mobile or desktop)
2. Search for **@BotFather** and start a chat
3. Send `/newbot`
4. Follow the prompts — pick a name and username for your bot
5. BotFather gives you a **bot token** (looks like `123456789:ABCdef...`)

Copy the token — you'll need it during deploy.

---

## Step 3: Get Your Telegram User ID

Your user ID tells the bot that you're the owner — you get instant access without needing to pair.

1. Search for **@userinfobot** on Telegram and start a chat
2. It replies immediately with your **user ID** (a number like `987654321`)

Copy this number.

---

## Step 4: Pick a Model

You need to tell the bot which AI model to use. The model name includes the provider prefix.

**Recommended starting model:**

```
openrouter/minimax/MiniMax-M2.5
```

This is fast, cheap, and capable. You can change it anytime — no need to overthink this now.

> Browse models at [openrouter.ai/models](https://openrouter.ai/models). The model ID format is always `openrouter/provider/model-name`.

---

## Step 5: Deploy

You now have everything you need:

| You should have | Example |
|----------------|---------|
| OpenRouter API key | `sk-or-v1-abc123...` |
| Telegram bot token | `123456789:ABCdef...` |
| Your Telegram user ID | `987654321` |
| Model name | `openrouter/minimax/MiniMax-M2.5` |

Click the deploy button:

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/openclaw-railway?referralCode=slayga&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway shows a form with environment variable fields. Fill in:

| Variable | Paste your... |
|----------|---------------|
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `LLM_PRIMARY_MODEL` | Model name (e.g. `openrouter/minimax/MiniMax-M2.5`) |
| `TELEGRAM_BOT_TOKEN` | Bot token from BotFather |
| `TELEGRAM_OWNER_ID` | Your user ID from @userinfobot |

> **Fill these in now, before clicking Deploy.** Railway does not save unfilled variables — if you skip them, you'll need to add them manually in the dashboard later.

Click **Deploy**. The build takes about 2-3 minutes.

---

## Step 6: Message Your Bot

Once Railway shows the deployment as **Active** (green):

1. Open Telegram
2. Find the bot you created (search its username)
3. Send it a message — anything works

It responds immediately. You're the owner (your user ID is pre-approved), so there's no pairing step.

**That's it. Your bot is running.**

---

## What Now?

- **Try it out** — ask questions, have it take notes, set a reminder
- **Change the model** — send `/model` in chat to try a different one for the current session, or update `LLM_PRIMARY_MODEL` in Railway and redeploy for a permanent change
- **Unlock more capabilities** — set `SECURITY_TIER=1` in Railway environment variables and redeploy to add shell commands. See [TIERS.md](TIERS.md)
- **Add web search** — set `BRAVE_API_KEY` in Railway to enable the `web_search` tool. Get a free key at [brave.com/search/api](https://brave.com/search/api/)
- **Invite someone** — they message your bot, get a pairing code, and you approve it (see [Adding Other Users](#adding-other-users) below)

---

<details>
<summary><strong>Alternative: Discord Bot</strong></summary>

Use these steps instead of Steps 2-3 if you prefer Discord.

### Create a Discord Bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application**, give it a name
3. Go to **Bot** → **Add Bot**
4. Copy the **bot token**
5. Under **Privileged Gateway Intents**, enable **Message Content Intent**
6. Go to **OAuth2** → **URL Generator**, select `bot` scope + `Send Messages` permission
7. Open the generated URL to invite the bot to your server

### Get Your Discord User ID

1. Open Discord Settings → **Advanced** → enable **Developer Mode**
2. Right-click your own name → **Copy User ID**

### Deploy Variables

Use these instead of the Telegram variables in Step 5:

| Variable | Value |
|----------|-------|
| `DISCORD_BOT_TOKEN` | Your Discord bot token |
| `DISCORD_OWNER_ID` | Your Discord user ID |

Everything else (OpenRouter key, model) stays the same.

</details>

<details>
<summary><strong>Alternative: Slack Bot</strong></summary>

Use these steps instead of Steps 2-3 if you prefer Slack.

### Create a Slack App

1. Go to [Slack API](https://api.slack.com/apps) → **Create New App** → **From scratch**
2. Under **OAuth & Permissions**, add these Bot Token Scopes:
   - `chat:write`
   - `im:history`
   - `im:read`
   - `im:write`
3. Under **Socket Mode**, enable it and create an **App-Level Token** with `connections:write` scope
4. Under **Event Subscriptions**, enable events and subscribe to `message.im`
5. Install the app to your workspace
6. Copy the **Bot Token** (`xoxb-...`) and **App Token** (`xapp-...`)

### Get Your Slack User ID

1. In Slack, click your profile picture → **Profile**
2. Click the three dots (...) → **Copy member ID**

### Deploy Variables

Use these instead of the Telegram variables in Step 5:

| Variable | Value |
|----------|-------|
| `SLACK_BOT_TOKEN` | Bot token (`xoxb-...`) |
| `SLACK_APP_TOKEN` | App token (`xapp-...`) |
| `SLACK_OWNER_ID` | Your Slack member ID |

Everything else (OpenRouter key, model) stays the same.

</details>

<details>
<summary><strong>Alternative: Deploy from GitHub Fork</strong></summary>

If you prefer to deploy from your own fork instead of the template button:

1. Fork this repository on GitHub
2. In Railway: **New Project** → **Deploy from GitHub repo**
3. Select your fork
4. Add the environment variables manually in the Railway dashboard (Your Service → Variables tab)
5. Railway will build and deploy automatically

This approach gives you full control over the source code and lets you customize the Dockerfile, entrypoint, or workspace templates.

</details>

---

## Changing Settings

Config is regenerated from environment variables on every deploy. To change anything:

1. Go to your Railway dashboard → your service → **Variables** tab
2. Update the variable
3. Click **Redeploy** in the Deployments tab (or run `railway up` from the CLI)

See [config/environment.md](../config/environment.md) for all available variables.

---

## Adding Other Users

Your owner ID is pre-approved. For anyone else:

1. They message your bot
2. The bot sends them a pairing code
3. You approve the code — either:
   - Via SSH: `railway ssh` then `openclaw pairing approve telegram <CODE>`
   - Or ask your bot to approve it (if you have exec commands enabled at Tier 1+)

---

## Troubleshooting

### Bot doesn't respond

1. Check Railway deployment logs for errors (Dashboard → your service → **Deployments** → click the latest → **View Logs**)
2. Verify your bot token is correct (no extra spaces, complete token)
3. Verify your owner ID is correct (should be a number)
4. Make sure you're messaging the bot directly (not in a group)

### "No LLM provider API key set"

Your `OPENROUTER_API_KEY` (or other provider key) isn't set. Add it in Railway Variables and redeploy.

### Gateway won't start

Check the deployment logs. Common causes:
- Missing or invalid API key
- Invalid model name (check the format matches your provider)
- Missing bot token

```bash
# If you have the Railway CLI installed:
railway logs
```

### Build takes too long

First build is ~3 minutes (downloads dependencies + OpenClaw). Subsequent deploys are faster due to Docker layer caching.

---

## Updating

Redeploy the container to get the latest OpenClaw version:

- Click **Redeploy** in the Railway dashboard, or
- Run `railway up` from the CLI

Do not run `openclaw update` inside the container.

---

## Next Steps

- [Security Tiers](TIERS.md) — unlock more capabilities (shell, browser, sub-agents)
- [Providers](PROVIDERS.md) — switch LLM providers or add voice transcription
- [Security Model](SECURITY.md) — understand the 5 layers of protection
- [Environment Variables](../config/environment.md) — full reference for all settings
