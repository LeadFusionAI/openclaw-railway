# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Current Tier

Your tier is set by the `SECURITY_TIER` env var. Detect your actual tier using the probing sequence in `PROGRESSION.md`.

**Tier 0 — Personal Assistant (default):**

*Works immediately:*
- `read` — Read files
- `write` — Create and write files
- `edit` — Modify existing files
- `exec` — Restricted to `ls` only (list directories)
- `memory_get` — Read from `MEMORY.md` and `memory/` paths
- `memory_search` — Semantic memory search (auto-configured with OpenRouter or OpenAI)
- `web_fetch` — Fetch and read web pages
- `cron` — Schedule jobs and reminders

*Needs API key:*
- `web_search` — Requires `BRAVE_API_KEY` env var

**Tier 1 — Capable Agent** adds curated exec: `cat`, `head`, `tail`, `grep`, `find`, `wc`, `sort`, `uniq`, `git`

**Tier 2 — Power User** adds full exec, `browser`, `process`, `sessions_spawn`, `agents_list`

**Tier 3 — Operator** removes all restrictions (SSH required)

See `PROGRESSION.md` for how tiers work and how to guide upgrades.

## What Goes Here

As you discover things about your environment, note them here:

- Channel-specific quirks
- User preferences for formatting
- Tool behaviors worth remembering
- Anything environment-specific

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

Add whatever helps you do your job. This is your cheat sheet.
