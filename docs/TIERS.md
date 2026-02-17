# Security Tiers

> **For agents:** Your progression guide is at `PROGRESSION.md` in your workspace. It has tier detection, prerequisite checklists, and upgrade walkthroughs.

This template ships with a locked-down default configuration. You can progressively unlock more capabilities as your trust and needs grow.

Tiers 0-2 are configurable via the `SECURITY_TIER` environment variable in Railway — no SSH required. Tier 3 requires SSH access for elevated permissions.

## Setting Your Tier

In Railway's dashboard, add the environment variable:

```
SECURITY_TIER=0   # Personal Assistant (default)
SECURITY_TIER=1   # Capable Agent
SECURITY_TIER=2   # Power User
SECURITY_TIER=3   # Operator (applies Tier 2, guides you to SSH for the rest)
```

Redeploy after changing. The config regenerates automatically.

---

## Tier 0: Personal Assistant (Default)

**What it can do:**
- Chat via Telegram/Discord/Slack
- Read and write files in workspace (markdown notes, memory)
- Fetch and read web pages (`web_fetch`)
- List directory contents (`ls` only — no other shell commands)
- Schedule cron jobs and reminders

**Needs API key:**
- Search the web (`web_search`) — requires `BRAVE_API_KEY`

Note: `memory_search` is auto-configured when using OpenRouter or OpenAI as your LLM provider. No extra setup needed.

**What this looks like in practice:**
- "Remind me to call the dentist Monday at 10am" — cron fires, message appears in Telegram. Done.
- "Every morning at 7am, give me the weather and my top 3 priorities" — agent searches weather, reads your goals files, delivers a daily briefing automatically.
- "I need to decide between these two apartments" — agent builds a comparison framework, asks the right questions, saves the analysis. Months later, "why did I pick that apartment?" gets a real answer.
- "What are the best Italian restaurants near me for a group of 8+?" — agent searches, reads review pages, gives you a shortlist with reasoning instead of 10 blue links.
- "My landlord says I can't have a dog. Is that enforceable in California?" — agent searches tenant law resources, gives you a grounded answer with sources.
- "I'm learning Spanish — quiz me on last week's vocabulary" — agent tracks what you've learned, uses spaced repetition, remembers what you struggle with across sessions.
- You mention your sister's wedding is in June. Three months later, "what do I need to get ready for next month?" — the agent knows about the wedding because it's in memory.

**When this is enough:** You want a thinking partner, research assistant, and personal knowledge base that remembers everything, looks things up, and reminds you about what matters. Most non-technical users will happily live here.

**What's blocked:**
- Shell commands beyond `ls` (exec allowlisted to `ls` only)
- Browser automation (`browser`)
- Process management (`process`)
- Node/device control (`nodes`)
- Sub-agent spawning (`sessions_spawn`)
- Gateway access (`gateway`)

**Config:**

**openclaw.json:**
```json5
{
  tools: {
    allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec", "cron"],
    deny: ["process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"],
    exec: {
      host: "gateway",
      security: "allowlist",
      ask: "off"
    }
  }
}
```

**exec-approvals.json** (deployed to `~/.openclaw/exec-approvals.json`):
```json5
{
  version: 1,
  agents: {
    main: {
      security: "allowlist",
      ask: "off",
      askFallback: "deny",
      allowlist: [
        { pattern: "/usr/bin/ls" },
        { pattern: "/bin/ls" }
      ]
    }
  }
}
```

---

## Tier 1: Capable Agent

Everything in Tier 0, plus curated shell commands with user approval.

**Additional capabilities:**
- Run curated shell commands: `cat`, `head`, `tail`, `grep`, `find`, `wc`, `sort`, `uniq`, `git`
- Agent asks for approval on first use of each new command (`ask: on-miss`)

**What this looks like in practice:**
- You drop a CSV export of your expenses into the workspace. "How much did I spend on dining out last month?" — agent reads and processes the file.
- "Find every time I mentioned pricing in my notes" — agent searches across all your files with exact matching.
- You accidentally delete something from a note. Agent recovers it from git history — your workspace has version control built in.
- "Organize these 30 meeting notes by topic and make an index" — agent reads through files, categorizes, builds a structured overview.
- You export your contacts from your phone as a CSV. "Sort these by last name and remove duplicates" — done.

**When to upgrade from Tier 0:** You have files, exports, or data you want the agent to process — spreadsheets, logs, exported lists, large documents. The agent can read and analyze them but can't at Tier 0.

**How to enable:**
```
SECURITY_TIER=1
```

Redeploy. That's it.

**What changes:**
- Exec allowlist expands from `ls` only to the curated list above
- `ask: on-miss` means the agent prompts for approval the first time it runs each command, then remembers

**exec-approvals.json** (deployed automatically):
```json5
{
  version: 1,
  agents: {
    main: {
      security: "allowlist",
      ask: "on-miss",
      askFallback: "deny",
      allowlist: [
        { pattern: "/usr/bin/ls" },
        { pattern: "/bin/ls" },
        { pattern: "/usr/bin/cat" },
        { pattern: "/usr/bin/head" },
        { pattern: "/usr/bin/tail" },
        { pattern: "/usr/bin/grep" },
        { pattern: "/usr/bin/find" },
        { pattern: "/usr/bin/wc" },
        { pattern: "/usr/bin/sort" },
        { pattern: "/usr/bin/uniq" },
        { pattern: "/usr/bin/git" }
      ]
    }
  }
}
```

**Important:** The allowlist uses resolved binary paths. Commands not in the list are blocked. Chaining (`;`, `&&`, `||`) and redirections are blocked in allowlist mode.

---

## Tier 2: Power User

Everything in Tier 1, plus unrestricted shell, browser, sub-agents, and process management.

**Additional capabilities:**
- Full shell access (any command, with `ask: on-miss` approval)
- Browser automation (remote only — no local Chromium)
- Sub-agent spawning for parallel work
- Process management
- `curl`, `node`, and any other installed binary

**What this looks like in practice:**
- Morning automation: cron at 6:30am — agent checks weather, reads your calendar via API, summarizes overnight emails, posts the whole briefing to Telegram. You wake up to a personalized daily brief.
- "Add 'buy milk' to my Todoist" — agent hits the Todoist API. Your chat becomes your task inbox.
- "Turn off the living room lights" / "Set the thermostat to 72" / "Start the vacuum" — agent sends API calls to Home Assistant, smart plugs, Roborock. One message on Telegram, done.
- "Research the best credit cards for travel, best travel insurance, and best loyalty programs" — three sub-agents working simultaneously, compiled into one comparison doc.
- "Every Friday at 5pm, review my weekly notes and give me a reflection prompt" — agent reads your week's writing and asks thoughtful questions, automatically.
- "Check my email and summarize anything important" — agent hits your email API, reads messages, gives you a digest without opening your inbox.

**When to upgrade from Tier 1:** You want the agent to actually *do things* in the world — interact with services, control smart home devices, automate routines, or work on multiple tasks in parallel.

**How to enable:**
```
SECURITY_TIER=2
```

Redeploy.

**What changes:**
- `process`, `browser`, `sessions_spawn`, `agents_list` moved from deny to allow
- Exec switches from allowlist to full mode
- No exec-approvals file deployed (not needed in full mode)
- `ask: on-miss` still requires approval for new commands

**Browser automation:**

At Tier 2, browser automation uses a remote browser service — no local Chromium is installed in the container. To enable browser tools, you'll need a cloud browser provider. Options include:

- **Browserbase** — `BROWSERBASE_API_KEY` + `BROWSERBASE_PROJECT_ID`
- **Steel** — `STEEL_API_KEY`
- Other remote browser services that provide a WebSocket endpoint

Set the appropriate env vars and the agent will connect to the remote browser automatically.

**Risks to understand:**
- The agent can run any command in the container
- Sub-agents inherit the parent's permissions — if the parent has full exec, so do sub-agents
- Browser automation can interact with web pages (potential prompt injection surface)
- `ask: on-miss` only prompts the first time; after approval, that command runs freely

---

## Tier 3: Operator

Everything in Tier 2, plus elevated permissions, node control, and gateway access. **Requires SSH.**

**Additional capabilities:**
- Elevated tool permissions
- Node/device control
- Gateway configuration access
- Everything — no tool restrictions

**When to consider this:** You need the agent to manage its own infrastructure, orchestrate multiple specialized agents, or have completely unrestricted access. Most users never need this tier.

**How to enable:**

Setting `SECURITY_TIER=3` via env var applies Tier 2 and writes a `.tier-status` marker to the workspace. The agent reads this and guides you through the SSH steps.

To complete Tier 3 setup, SSH in:

```bash
railway ssh
nano /data/.openclaw/openclaw.json
```

Set an empty deny list and enable elevated mode:

```json5
{
  agents: {
    defaults: {
      tools: {
        deny: []  // Nothing blocked
      }
    }
  },
  tools: {
    exec: {
      security: "full",
      ask: "on-miss"
    },
    elevated: {
      enabled: true
    }
  }
}
```

Restart the gateway:
```bash
pkill -f "openclaw gateway"
openclaw gateway run --port 18789 &
exit
```

**Risks:**
- Agent can run any command, access browser sessions, spawn unlimited sub-agents
- Agent can modify gateway configuration
- If compromised via prompt injection, attacker has full container access
- API spending has no automatic cap — verify your provider has limits set

---

## Per-Channel Overrides

You can set different capabilities for different channels. For example, Telegram gets Tier 2 capabilities but Discord stays at defaults:

```json5
{
  agents: {
    defaults: {
      tools: {
        deny: ["process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"]
      }
    }
  },
  channels: {
    telegram: {
      tools: {
        allow: ["process", "browser", "sessions_spawn"]
      }
    }
  }
}
```

---

## Per-User Overrides

You can give specific users elevated access:

```json5
{
  tools: {
    elevated: {
      enabled: true,
      allowFrom: {
        telegram: [123456789],  // Only this user can use elevated mode
        discord: ["987654321"]
      }
    }
  }
}
```

---

## Checking Current Config

Ask your bot: "What tools do you have access to?" or "What tier am I on?"

Or SSH in and view directly:
```bash
railway ssh
cat /data/.openclaw/openclaw.json
```

---

## Recovery Paths

Things go wrong. Here's how to fix them.

### "I changed SECURITY_TIER and something broke"

Set `SECURITY_TIER=0` (or remove it entirely) and redeploy. Config regenerates to safe defaults.

### "I did SSH config edits and now things are broken"

Redeploy the container. The entrypoint regenerates `openclaw.json` from your environment variables on every startup. Whatever you changed via SSH gets replaced.

### "I enabled Tier 3 and want to go back"

Set `SECURITY_TIER=0` and redeploy. Config regenerates at Tier 0 defaults.

### "The agent is doing something I didn't expect"

1. Check what tools are active: ask the agent "What tools do you have access to?"
2. Review workspace changes via SSH: `ls -la /data/workspace/`
3. Lower the tier or redeploy to reset

### "I want to start completely fresh"

Delete the volume in Railway dashboard and redeploy. This wipes everything — config, workspace, agent memory, identity. You're back to the first-time experience.

---

## Safety Guardrails

**Tier 0 (web access):**
- The agent can read any public web page. It cannot log into services or access private content.
- Be cautious about asking it to visit URLs from untrusted sources — web content can contain prompt injection attempts.
- The worst case is a confused or misleading response. The agent can't take real-world action based on a malicious page.

**Tier 1 (curated shell):**
- The allowlist restricts which commands the agent can run. Only read-only tools are included.
- `ask: on-miss` means the agent prompts for approval before running a new command type.
- Chaining (`;`, `&&`, `||`) and redirections are blocked.

**Tier 2 (full shell + browser):**
- The agent can run any command in the container. `ask: on-miss` still requires first-time approval.
- Sub-agents inherit permissions. If the parent has full exec, so do sub-agents.
- Browser automation can interact with web pages — be mindful of prompt injection.
- Never add secrets to workspace files the agent can read.

**Tier 3 (operator):**
- Prompt injection is your main risk. Any content the agent reads could contain instructions it follows.
- Consider whether Tier 2 with targeted additions would suffice before going full operator.
- Verify your LLM provider has spending caps configured.
