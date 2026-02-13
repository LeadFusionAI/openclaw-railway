# Tools & Extensions

Reference for your current tool access and OpenClaw's extension ecosystem.

## Current Tool Access

Your available tools depend on your security tier. To check what you have:
- Try using a tool — if it's blocked, you'll get a clear error
- Read `docs/TIERS.md` for what's available at each tier

**Tier 0 (default):**
- `read` — Read files in the workspace
- `write` — Create and write files
- `edit` — Modify existing files
- `memory_get` — Read from `MEMORY.md` and `memory/` paths

**Tier 1 adds:** `memory_search`, `web_search`, `web_read`
**Tier 2 adds:** `exec`, `nodes`, process management
**Tier 3 adds:** Browser, advanced automation
**Tier 4:** Full access

See `PROGRESSION.md` for how to guide your user through tier upgrades.

## Extension Ecosystem

OpenClaw has three extension mechanisms beyond core tools:

### Skills

Community-built knowledge and workflow packages from [ClawHub](https://clawhub.ai/) (5,700+ available). Skills add specialized knowledge or multi-step workflows without code changes.

Install via SSH:
```bash
openclaw skills install <skill-name>
```

Browse available skills at https://clawhub.ai/ or via SSH:
```bash
openclaw skills search <keyword>
```

Docs: https://docs.openclaw.ai/tools/skills

### Plugins

Code-level extensions that add new tool capabilities. Channel plugins (Telegram, Discord, Slack) are already active if configured — they're how messages reach you.

Docs: https://docs.openclaw.ai/tools/plugins

### Hooks

Event-triggered automations that run when specific things happen (message received, session started, etc.). Configured in the OpenClaw config file.

Docs: https://docs.openclaw.ai/tools/hooks

## Notes

- Skills and plugins require SSH to install (user can SSH at any tier via `railway ssh`)
- Don't suggest installing extensions unprompted — wait for the user to ask
- Extension config lives in `/data/.openclaw/openclaw.json` alongside your main config
