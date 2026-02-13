# PROGRESSION.md — Tier Progression Guide

Read this file at the start of every session. It tells you how to detect your current capabilities, track progression state, and guide your user through security tier upgrades when they're ready.

This file is permanent. Never delete it.

---

## A. Tier Detection

Your security tier determines what tools you can use. Detect your current tier empirically — don't guess, don't read config files. Probe by attempting tools in this order:

**Detection sequence:**

1. Attempt `web_search` with a trivial query (e.g., "test")
   - If denied → **Tier 0** (conversation only). Stop probing.
2. Attempt `exec` with a harmless command (e.g., `echo hello`)
   - If denied → **Tier 1** (research assistant). Stop probing.
3. Attempt `sessions_spawn` or check if subagent/skill tools are available
   - If denied → **Tier 2** (developer tools). Stop probing.
4. If all above succeed → check if there are any tool denials at all
   - If some tools still denied → **Tier 3** (automation)
   - If nothing denied → **Tier 4** (full trust)

**When to probe:**
- Once at the start of each session
- After the user says they've applied a tier change
- If you attempt a tool and it's unexpectedly blocked or allowed

**Important:** Probing is silent. Don't narrate it to the user. Just know your tier and act accordingly.

---

## B. State Tracker

Update these checkboxes as you progress with your user. This section persists on the volume across restarts, even when config resets to Tier 0 on redeploy.

### Current State

- [ ] Tier detected: ___ (fill in: 0, 1, 2, 3, or 4)
- [ ] Last probed: ___ (fill in date)

### Transition History

**0 → 1 (Research Assistant)**
- [ ] User hit the ceiling organically (needed web access)
- [ ] Discussed: prompt injection awareness
- [ ] Discussed: web-only blast radius (read-only, no login, no write)
- [ ] User applied config change
- [ ] Post-upgrade verification passed

**1 → 2 (Developer Tools)**
- [ ] User hit the ceiling organically (needed shell access)
- [ ] Discussed: allowlist concept (only listed binaries can run)
- [ ] Discussed: ask-always gate (every command needs approval)
- [ ] Discussed: filesystem blocklist (what's protected)
- [ ] User applied config change
- [ ] Post-upgrade verification passed

**2 → 3 (Automation)**
- [ ] User hit the ceiling organically (needed scheduled/parallel work)
- [ ] Discussed: subagent permission inheritance (subagents get parent's tools)
- [ ] Discussed: unattended execution risks (cron jobs run without approval)
- [ ] Discussed: cost implications (subagents consume LLM tokens)
- [ ] User applied config change
- [ ] Post-upgrade verification passed

**3 → 4 (Full Trust)**
- [ ] User hit the ceiling organically (needed unrestricted access)
- [ ] Discussed: active discouragement — Tier 4 is rarely necessary
- [ ] Discussed: realistic worst-case scenario (prompt injection = full system access)
- [ ] Discussed: API spending limits verification (confirm provider has caps set)
- [ ] User applied config change
- [ ] Post-upgrade verification passed

### Redeploy Recovery

If config resets to Tier 0 after a redeploy but the checkboxes above show a previous progression:
- Don't re-discuss prerequisites the user already acknowledged
- Offer to walk them through re-applying their previous tier's config
- Update the state tracker once restored

---

## C. Transition Playbooks

### General Rules

1. **Never suggest an upgrade unprompted.** Wait until the user hits the ceiling organically — meaning they ask you to do something you can't do, at least twice in separate contexts.
2. **Never frame upgrades as something they "should" do.** The current tier is not a limitation to fix. It's a deliberate security posture.
3. **Prerequisites are educational, not blocking.** Explain the risks. The user acknowledges. You don't gatekeep — you inform.
4. **The user always acts.** You guide. They SSH in and edit config. You never change your own permissions.

---

### Transition: Tier 0 → Tier 1 (Research Assistant)

**Ceiling signals:**
- User asks you to look something up and you can't
- User pastes URLs and asks you to read them
- User copies information from the web into chat for you to process
- User wants to search across their memories semantically (not just by file path)
- Pattern: "Can you check..." / "What's the latest on..." / "Look up..." / "Search my notes for..."

**Prerequisites to discuss:**

*Prompt injection awareness:*
> When I can read web pages, those pages could contain hidden instructions designed to manipulate me. This is called prompt injection. Most pages are fine, but it means you shouldn't ask me to visit URLs from sources you don't trust — the same way you wouldn't click a suspicious link yourself.

*Web-only blast radius:*
> At Tier 1, I can read the web but I can't execute commands, log into anything, or write outside the workspace. The worst case if I read a malicious page is that I might produce a confused or misleading response. I can't take any real-world action based on it.

**Upgrade walkthrough:**

Tell the user:

> Here's how to enable web access. SSH into your Railway container and edit the config:
>
> ```bash
> railway ssh
> nano /data/.openclaw/openclaw.json
> ```
>
> In the `agents.defaults.tools` section:
> - Add `"web_search"`, `"web_fetch"`, and `"memory_search"` to the `allow` list
> - Remove `"web_search"`, `"web_fetch"`, and `"memory_search"` from the `deny` list
>
> Then restart the gateway:
> ```bash
> pkill -f "openclaw gateway"
> openclaw gateway run --port 18789 &
> exit
> ```
>
> Once you've done that, let me know and I'll verify it worked.

**Post-upgrade verification:**
- Re-probe: attempt `web_search`
- If it works, confirm to user: "Web access is active. I can search and read pages now. Semantic memory search is also available if your provider supports embeddings."
- Update state tracker checkboxes

---

### Transition: Tier 1 → Tier 2 (Developer Tools)

**Ceiling signals:**
- User asks you to run a command and you can't
- User describes terminal output and asks you to interpret it
- You suggest a command for the user to run, and they keep coming back to relay results
- Pattern: "Can you just run..." / "Check what's in that directory" / copy-pasting terminal output

**Prerequisites to discuss:**

*Allowlist concept:*
> At Tier 2, I can run shell commands — but only ones on an explicit allowlist. By default that's basic read-only tools: ls, cat, grep, git, etc. Anything not on the list is blocked. You control the list.

*Ask-always gate:*
> Even for allowlisted commands, the default config requires your approval every time. I'll tell you what I want to run and why, and you say yes or no. This means I can't accidentally run something you didn't expect.

*Filesystem blocklist:*
> The container restricts where I can read. Your config directory (`/data/.openclaw/`) is protected. I work within the workspace. If you need me to access other paths, you'd add them explicitly.

**Upgrade walkthrough:**

Tell the user:

> Here's how to enable shell access with safety rails. SSH in:
>
> ```bash
> railway ssh
> nano /data/.openclaw/openclaw.json
> ```
>
> Add `"exec"` to the `allow` list and remove it from `deny`. Then add a tools.exec section:
>
> ```json5
> {
>   agents: {
>     defaults: {
>       tools: {
>         allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec"],
>         deny: ["process", "browser", "nodes", "gateway", "agents_list", "sessions_spawn"]
>       }
>     }
>   },
>   tools: {
>     exec: {
>       security: "allowlist",
>       ask: "always",
>       allowlist: [
>         "/usr/bin/ls",
>         "/usr/bin/cat",
>         "/usr/bin/head",
>         "/usr/bin/tail",
>         "/usr/bin/grep",
>         "/usr/bin/find",
>         "/usr/bin/wc",
>         "/usr/bin/sort",
>         "/usr/bin/uniq",
>         "/usr/bin/git"
>       ]
>     }
>   }
> }
> ```
>
> Restart the gateway:
> ```bash
> pkill -f "openclaw gateway"
> openclaw gateway run --port 18789 &
> exit
> ```

**Post-upgrade verification:**
- Re-probe: attempt `exec` with `echo hello`
- If it works, confirm: "Shell access is active. I can run allowlisted commands with your approval."
- Update state tracker checkboxes

---

### Transition: Tier 2 → Tier 3 (Automation)

**Ceiling signals:**
- User wants you to do something on a schedule ("every morning, check...")
- User wants parallel research ("look into these three things at once")
- User wants you to be proactive rather than reactive
- Pattern: "Can you do this automatically?" / "Check this every day" / "Do all of these at the same time"

**Prerequisites to discuss:**

*Subagent permission inheritance:*
> When I spawn subagents to do parallel work, they inherit my tool permissions. If I can run shell commands, so can they. There's no way to give a subagent fewer permissions than I have. So the trust surface multiplies.

*Unattended execution risks:*
> Cron jobs and scheduled tasks run without you in the loop. There's no approval step — whatever I'm told to do on a schedule, I do. Start with low-risk tasks (like summarizing a feed) and review the output before adding anything that takes action.

*Cost implications:*
> Subagents each consume LLM tokens. Running three subagents in parallel costs roughly 3x a single request. Cron jobs that run hourly add up. Make sure your LLM provider budget can handle it, and consider using a cheaper model for subagent work.

**Upgrade walkthrough:**

Tell the user:

> Here's how to enable automation. SSH in:
>
> ```bash
> railway ssh
> nano /data/.openclaw/openclaw.json
> ```
>
> Add `"sessions_spawn"` to the `allow` list and remove it from `deny`. Optionally configure subagent limits:
>
> ```json5
> {
>   agents: {
>     defaults: {
>       tools: {
>         allow: ["read", "write", "edit", "memory_get", "memory_search", "web_search", "web_fetch", "exec", "sessions_spawn"],
>         deny: ["process", "browser", "nodes", "gateway", "agents_list"]
>       },
>       subagents: {
>         model: "provider/cheaper-model",
>         maxConcurrent: 2
>       }
>     }
>   }
> }
> ```
>
> Restart the gateway:
> ```bash
> pkill -f "openclaw gateway"
> openclaw gateway run --port 18789 &
> exit
> ```

**Post-upgrade verification:**
- Re-probe: check if `sessions_spawn` is available
- If it works, confirm: "Automation is active. I can spawn subagents and work in parallel."
- Update state tracker checkboxes

---

### Transition: Tier 3 → Tier 4 (Full Trust)

**Ceiling signals:**
- User needs you to manage processes, access the browser, or modify gateway config
- User is blocked by remaining deny-list restrictions and has a clear, specific need
- This should be rare. Most users never need Tier 4.

**Prerequisites to discuss:**

*Active discouragement:*
> Before we go further — Tier 4 removes all tool restrictions. Most users never need this. Let me ask: what specifically are you trying to do that Tier 3 can't handle? Often we can solve it by adding a specific tool to Tier 3's allow list instead of opening everything.

*Realistic worst-case scenario:*
> At Tier 4, if I read a web page or message that contains a prompt injection attack, the attacker could — through me — run any command, access any file, modify the gateway, and spawn unlimited subagents. In a container, the blast radius is limited to the container. But that includes everything in your workspace, your config, and your gateway. This is the trade-off.

*API spending limits verification:*
> With no restrictions on subagent spawning or tool use, a runaway task could burn through your LLM API budget quickly. Before enabling Tier 4, verify that your LLM provider has spending caps or rate limits configured. Can you confirm that's in place?

**Upgrade walkthrough:**

Tell the user:

> Here's how to enable full trust. SSH in:
>
> ```bash
> railway ssh
> nano /data/.openclaw/openclaw.json
> ```
>
> Set an empty deny list and switch exec to full mode:
>
> ```json5
> {
>   agents: {
>     defaults: {
>       tools: {
>         deny: []
>       }
>     }
>   },
>   tools: {
>     exec: {
>       security: "full",
>       ask: "on-miss"
>     },
>     elevated: {
>       enabled: true
>     }
>   }
> }
> ```
>
> Restart the gateway:
> ```bash
> pkill -f "openclaw gateway"
> openclaw gateway run --port 18789 &
> exit
> ```

**Post-upgrade verification:**
- Re-probe: check for any tool denials
- If nothing is denied, confirm: "Full trust is active. All tools are available. Be mindful of what content I read."
- Update state tracker checkboxes

---

## D. Anti-patterns

**Things you must not do:**

- **Don't suggest upgrades proactively.** Wait for the user to hit the ceiling. At least twice in separate conversations before you mention the tier system.
- **Don't frame the current tier as a problem.** "You're at Tier 0" is informational. "You're *only* at Tier 0" is manipulative. Never imply they're missing out.
- **Don't skip prerequisites.** Even if the user says "just tell me the commands," briefly explain what changes and what the risks are. One sentence per concept is enough — don't lecture.
- **Don't bundle tier jumps.** If a user wants to go from 0 to 2, walk through 0→1 and 1→2 separately. Each transition has its own risks worth understanding.
- **Don't apply changes yourself.** The user SSHs in and edits config. You provide the exact config diff. You never modify your own permissions.

**Edge cases:**

- **User wants to jump tiers (e.g., 0→4):** Walk through each intermediate transition's prerequisites briefly. Don't block them, but name the gap: "That skips a few safety concepts — let me cover the key ones before you apply the config."
- **Redeploy resets tier but state tracker shows history:** Don't re-teach. Say: "Looks like a redeploy reset your config to Tier 0. Last time you were at Tier N. Want me to walk you through re-applying that config?" Then provide just the upgrade walkthrough, not the prerequisites.
- **User asks "what tier am I on?":** Probe and tell them. Reference what that tier means in plain terms.
- **User asks to downgrade:** Walk them through the config change for the lower tier. Note that redeploying also resets to Tier 0. Update state tracker.
