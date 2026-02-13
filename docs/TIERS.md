# Security Tiers

> **For agents:** Your progression guide is at `PROGRESSION.md` in your workspace. It has tier detection, prerequisite checklists, and upgrade walkthroughs.

This template ships with a locked-down default configuration. You can progressively unlock more capabilities as your trust and needs grow.

Each tier is earned by hitting the ceiling naturally — not upsold. When you find yourself needing something your agent can't do yet, that's when to consider the next tier.

## Tier 0: Conversation Only (Default)

**What it can do:**
- Chat via Telegram/Discord/Slack
- Read and write files in workspace (markdown notes, memory)
- List directory contents (`ls` only — no other shell commands)
- Retrieve memories from files (file-based, not semantic search)

**What this looks like in practice:**
- "Help me think through this decision" — agent builds a framework, tracks your reasoning over time
- "Organize my project notes" — agent creates structured markdown, cross-links ideas
- "Remember that I decided X because of Y" — agent stores it, recalls it weeks later
- "Draft this email for me" — agent writes, edits, refines with you
- "Break down this goal into steps" — agent creates a project plan with dependencies

**When this is enough:** You want a thinking partner, writing assistant, or personal knowledge base. You don't need it to look things up or run commands.

**What's blocked:**
- Shell commands beyond `ls` (`exec` is allowlisted to `ls` only)
- Web browsing (`browser`)
- Web fetching (`web_fetch`, `web_search`)
- Semantic memory search (`memory_search` — requires embeddings provider)
- Process management (`process`)
- Node/device control (`nodes`)
- Subagent spawning (`sessions_spawn`)
- Gateway access (`gateway`)

**Config:**
```json5
{
  agents: {
    defaults: {
      tools: {
        allow: ["read", "write", "edit", "memory_get", "exec"],
        deny: ["process", "browser", "nodes", "web_search", "web_fetch", "gateway", "memory_search", "agents_list", "sessions_spawn"]
      }
    }
  },
  tools: {
    exec: {
      security: "allowlist",
      ask: "never",
      allowlist: ["/usr/bin/ls", "/bin/ls"]
    },
    fs: {
      enabled: true,
      blocklist: ["/proc", "/etc", "/root", "/home", ".openclaw", ".ssh", ".aws", ".env"]
    }
  }
}
```

---

## Tier 1: Research Assistant

Enable web search, fetching, and semantic memory search.

**Additional capabilities:**
- Search the web
- Fetch and read web pages
- Semantic memory search (requires an embeddings-capable provider like OpenAI or Gemini)

**What this looks like in practice:**
- "What's the latest on X?" — agent searches the web and summarizes findings
- "Fact-check this claim" — agent looks up sources and reports back
- "Research competitors in this space" — agent compiles a report from multiple sources
- "What does this API do?" — agent reads the documentation for you

**When to upgrade from Tier 0:** You find yourself saying "can you look this up?" or pasting URLs and asking the agent to read them. If you're copy-pasting information into the chat for the agent to process, Tier 1 lets it fetch that information itself.

**How to enable:**

SSH in and edit the config:
```bash
railway ssh
nano /data/.openclaw/openclaw.json
```

Remove `web_search`, `web_fetch`, and `memory_search` from the deny list:
```json5
{
  agents: {
    defaults: {
      tools: {
        allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch"],
        deny: ["exec", "process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"]
      }
    }
  }
}
```

**Note:** `memory_search` uses semantic search powered by embeddings. OpenClaw auto-selects an embeddings provider from your configured API keys (OpenAI, Gemini, Voyage). If your provider doesn't support embeddings (e.g., Groq, OpenRouter), memory search falls back to keyword matching only.

Restart the gateway:
```bash
pkill -f "openclaw gateway"
openclaw gateway run --port 18789 &
```

---

## Tier 2: Developer Tools

Enable restricted shell access for development tasks.

**Additional capabilities:**
- Run whitelisted shell commands (cat, grep, find, git, etc. — `ls` is already available at Tier 0)
- Work with code repositories
- Persistent model changes via `openclaw models set` (no redeploy needed)
- OAuth provider setup (Google AI, etc.)

**What this looks like in practice:**
- "Clone this repo and explain the architecture" — agent runs git, reads code, maps the structure
- "Find all TODO comments in this project" — agent greps through files
- "Set up the DeepSeek model permanently" — agent runs `openclaw models set deepseek/model-name`
- "Show me the last 20 lines of this log" — agent runs tail on the file

**When to upgrade from Tier 1:** You're working on code or technical projects and keep wishing the agent could just run a command instead of telling you what to run. If you find yourself being the agent's hands, Tier 2 gives it (limited) hands of its own.

**How to enable:**

Update the config:
```json5
{
  agents: {
    defaults: {
      tools: {
        allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec"],
        deny: ["process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"]
      }
    }
  },
  tools: {
    exec: {
      security: "allowlist",
      ask: "always",
      allowlist: [
        "/usr/bin/ls",
        "/usr/bin/cat",
        "/usr/bin/head",
        "/usr/bin/tail",
        "/usr/bin/grep",
        "/usr/bin/find",
        "/usr/bin/wc",
        "/usr/bin/sort",
        "/usr/bin/uniq",
        "/usr/bin/git"
      ]
    }
  }
}
```

**Important:** The allowlist uses resolved binary paths. Commands not in the list will be blocked. Chaining (`;`, `&&`, `||`) and redirections are blocked in allowlist mode.

---

## Tier 3: Automation

Enable skills, cron jobs, and more advanced features.

**Additional capabilities:**
- Run skills from ClawHub
- Schedule cron jobs
- Spawn subagents for parallel work

**What this looks like in practice:**
- "Every morning, check my project board and summarize what's due" — agent runs a scheduled task
- "Research these three topics at the same time" — agent spawns subagents for parallel work
- "Set up a daily standup summary" — agent creates a cron job that runs automatically

**When to upgrade from Tier 2:** You're comfortable with what the agent does and want it to work independently — on a schedule, in parallel, or without being prompted. This is where the agent goes from reactive to proactive.

**How to enable:**

Update the config:
```json5
{
  agents: {
    defaults: {
      tools: {
        allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec", "sessions_spawn"],
        deny: ["process", "browser", "nodes", "gateway", "agents_list"]
      },
      subagents: {
        model: "provider/cheap-model",  // Use a cheaper model for subagents
        maxConcurrent: 2
      }
    }
  }
}
```

---

## Tier 4: Full Trust

Remove all restrictions. Only do this if you fully understand the risks.

**What's unlocked:**
- Everything — no tool restrictions, no command allowlists

**When to consider this:** You're running in a fully isolated environment, you understand prompt injection risks, and you need the agent to have unrestricted access. This is for advanced users who are effectively treating the agent as a full system operator.

**Risks:**
- Agent can run any command
- Agent can access browser sessions
- Agent can spawn unlimited subagents
- Agent can modify gateway configuration
- If compromised via prompt injection, attacker has full access

**How to enable:**

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
      ask: "on-miss"  // Only ask for new commands
    },
    elevated: {
      enabled: true
    }
  }
}
```

---

## Per-Channel Overrides

You can set different tiers for different channels. For example, Telegram gets Tier 2 but Discord stays at Tier 0:

```json5
{
  agents: {
    defaults: {
      tools: {
        deny: ["exec", "browser", "process", "nodes", "web_search", "web_fetch"]
      }
    }
  },
  channels: {
    telegram: {
      tools: {
        allow: ["exec", "web_search", "web_fetch"]
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

SSH in and view the current configuration:

```bash
railway ssh
cat /data/.openclaw/openclaw.json
```

Or ask your bot: "What tools do you have access to?"

---

## Recovery Paths

Things go wrong. Here's how to fix them.

### "I deleted something in my workspace"

Your workspace lives on the volume at `/data/workspace`. If you delete files, they're gone — but redeploying the container will restore any template files (like BOOTSTRAP.md) that are missing. Your agent's memory and identity files are only at risk if you manually delete them.

### "I changed the config and now things are broken"

Redeploy the container. The entrypoint regenerates `openclaw.json` from your environment variables on every startup. Whatever you changed gets replaced with a known-good config.

```bash
# Or manually from SSH:
rm /data/.openclaw/openclaw.json
# Then redeploy from Railway dashboard
```

### "I enabled Tier 4 and want to go back"

Redeploy. Config regenerates at Tier 0 defaults from env vars. If you want a different tier, re-apply just that tier's config changes.

### "The agent is doing something I didn't expect"

At Tier 0-1, the agent can't execute commands or access the network (Tier 0) / can only read the web (Tier 1). The blast radius is limited to file changes in the workspace. If you're concerned:

1. Check what tools are active: ask the agent "What tools do you have access to?"
2. Review workspace changes via SSH: `ls -la /data/workspace/`
3. Redeploy to reset config to defaults

### "I want to start completely fresh"

Delete the volume in Railway dashboard and redeploy. This wipes everything — config, workspace, agent memory, identity. You're back to the first-time experience.

---

## Safety Guardrails

When running at higher tiers, keep these in mind:

**Tier 1 (web access):**
- The agent can read any public web page. It cannot log into services or access private content.
- Be cautious about asking it to visit URLs from untrusted sources — web content can contain prompt injection attempts.

**Tier 2 (shell access):**
- The allowlist restricts which commands the agent can run. Review it before enabling.
- `ask: "always"` means the agent must get approval before every command. Only change this if you trust the agent fully.
- Never add `rm`, `curl`, `wget`, or package managers to the allowlist unless you understand the implications.

**Tier 3 (automation):**
- Subagents inherit the parent's tool permissions. If the parent has shell access, so do subagents.
- Cron jobs run unattended. Start with low-risk tasks and review their output before adding more.

**Tier 4 (full trust):**
- Prompt injection is your main risk. Any content the agent reads (web pages, files, messages from other users) could contain instructions that the agent follows.
- Consider whether you actually need Tier 4, or if Tier 2/3 with a broader allowlist would suffice.
