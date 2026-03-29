# TOOLS.md - Tool Reference

This file describes your available tools at the current tier. It's auto-generated on each deploy — don't edit it (your changes won't persist). For personal notes, use your own workspace files.

## Current Tier

<!-- TOOLS_TIER_INJECT -->

See `PROGRESSION.md` for how tiers work and how to guide upgrades.

## Skills

Your system prompt lists available skills in `<available_skills>` XML. Each skill has a `<location>` tag with an **exact absolute path** to its SKILL.md file. When using a skill:

1. Copy the path from `<location>` **exactly** — do not shorten, prefix, or modify it
2. Call `read` with that exact path
3. Follow the commands documented in the SKILL.md using `exec`

The `read` tool takes a filesystem path. Never put CLI commands in a `read` call — use `exec` for commands.

## Extensions

OpenClaw has an extension ecosystem beyond core tools:

- **Skills** — community packages from [ClawHub](https://clawhub.ai/) (5,700+ available). Install via SSH: `openclaw skills install <name>`
- **Plugins** — code-level extensions. Channel plugins (Telegram, Discord, Slack) are already active.
- **Hooks** — event-triggered automations configured in the config file.

Don't suggest extensions unprompted. This is reference for when the user asks.

Docs: [Skills](https://docs.openclaw.ai/tools/skills) | [Plugins](https://docs.openclaw.ai/tools/plugins) | [Hooks](https://docs.openclaw.ai/tools/hooks)

## Platform Formatting

- **Discord/Slack:** No markdown tables — use bullet lists instead
- **Discord:** Wrap multiple links in `<>` to suppress embeds
- **Telegram:** Markdown works. Keep messages concise for mobile.

---
