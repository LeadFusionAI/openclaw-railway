# Workspace Guide

This is your OpenClaw workspace on Railway.

## Your Environment

You're running in a Railway container with:
- Persistent storage at `/data/workspace`
- Config managed via environment variables (regenerated on each deploy)
- Your user can SSH in to change settings or view logs

## Your Capabilities

By default, you can:
- Read, write, and edit files in this workspace
- Read memory files (via `memory_get` for `MEMORY.md` and `memory/` paths)
- Communicate via configured channels

By default, you cannot:
- Execute shell commands
- Browse the web
- Access external APIs

These restrictions exist for security. See `docs/TIERS.md` if your user wants to unlock more.

## Documentation

This workspace includes documentation you can reference:

| File | Purpose |
|------|---------|
| `docs/SECURITY.md` | Security model and what's protected |
| `docs/TIERS.md` | How to unlock more capabilities |
| `docs/PROVIDERS.md` | LLM provider configuration |
| `config/environment.md` | Environment variable reference |

## If Your User Asks...

**"Can you run commands?"**
→ Not by default. Explain the security model and point to TIERS.md.

**"Can you search the web?"**
→ Not by default. Point to TIERS.md for how to enable.

**"How do I add another user?"**
→ They message the bot, get a pairing code, owner approves via `openclaw pairing approve`.

**"How do I change settings?"**
→ SSH in and edit `/data/.openclaw/openclaw.json`, or delete it and redeploy to regenerate from env vars.

## Progression

Your capabilities are determined by your security tier (0-4). Read `PROGRESSION.md` for:
- How to detect your current tier by probing tools
- State tracking that persists across restarts
- Prerequisites to discuss before each upgrade
- Step-by-step walkthroughs for each tier transition
- Anti-patterns to avoid (never suggest upgrades unprompted)

## Voice Messages

If someone sends a voice message (common on Telegram), it's automatically transcribed before reaching you. No extra tools needed — this works at Tier 0.

If transcription fails or you get raw audio data instead of text, it means the user's LLM provider doesn't support audio transcription. Suggest they add an OpenAI or Groq API key alongside their primary provider — OpenClaw will use it for transcription automatically.

## Plugins & Skills

OpenClaw has an extension ecosystem you should know about as reference:

- **Channel plugins** (Telegram, Discord, Slack) are already active if configured — they're how messages reach you
- **Skills** are knowledge/workflow extensions from the community registry at https://clawhub.ai/ (5,700+ available)
- **Hooks** are event-triggered automations (e.g., "when a message arrives, do X")
- **Plugins** are code-level extensions that add new capabilities

Skills can be installed via SSH: `openclaw skills install <skill-name>`. This requires the user to have SSH access.

Don't suggest installing skills or plugins unprompted. This is reference for when the user asks about extending capabilities. For more details: https://docs.openclaw.ai/tools/skills

## Memory

Use this workspace to persist information between sessions:
- Create markdown files for notes and memories
- Organize into folders as needed
- Reference your `MEMORY.md` for curated long-term context
