# Project Ideas

This file is your reference for what to suggest when getting to know someone new. Don't dump the whole list — pick ONE that fits what you've learned about the person and offer it naturally.

Read their cues from Phase 2 of your bootstrap conversation. Match the project to what they actually care about.

**Important:** Only suggest projects that work at your current tier. Don't dangle capabilities the user doesn't have — that's upselling, not helping. If they need a higher tier, they'll hit the ceiling naturally.

---

# Tier 0 — Personal Assistant Projects

These all work out of the box. No upgrades needed.

---

## For the Busy Professional

### Decision Journal

A running log of important decisions with context, reasoning, and outcomes. You create a `decisions/` folder and log each entry with the situation, options considered, what they chose, and why. Once a month, you review the journal together and look for patterns — are they consistently underweighting certain factors? Avoiding certain types of risk? The value compounds as patterns emerge over months.

**First message from them:** "I have a big decision to make about X"
**What you do:** Create `decisions/YYYY-MM-DD-topic.md` with structured sections. Check in later to record the outcome. At month-end, offer a retrospective.

### Relationship Memory System

A contact database for the people in their life — not a CRM, but a way to remember the human details. Who mentioned a sick parent? Who's launching something in March? Who likes hiking? You maintain `contacts/` with a file per person, updated as details come up in conversation. Before a meeting or catch-up, they can ask you for a refresher on someone.

**First message from them:** "I have a meeting with someone I haven't talked to in a while"
**What you do:** Create `contacts/name.md` with what they tell you. Over time, build out details as they mention people naturally. Offer refreshers before meetings.

---

## For the Reflective Mind

### Weekly Reflection & Pattern Analysis

Every week (or whatever cadence fits), they talk through their week and you capture it in `reflections/`. Not a diary — a structured reflection: what went well, what drained them, what surprised them, what they'd do differently. Over time, you start noticing patterns they can't see from inside their own life. "You've mentioned energy drops on Wednesdays three weeks in a row — what's different about Wednesdays?"

**First message from them:** "It's been a weird week" or "I want to get better at reflection"
**What you do:** Create `reflections/YYYY-WNN.md` with their thoughts. After 4+ entries, start offering pattern observations.

### Health & Nutrition Journal

They tell you what they ate, how they slept, how they felt — you log it in `health/` with dates. Not calorie counting or medical advice, just pattern tracking. "You mentioned feeling foggy three of the last five days — all days where you skipped breakfast." The insight comes from seeing the data laid out over weeks.

**First message from them:** "I've been trying to eat better" or "I want to track how I feel"
**What you do:** Create `health/YYYY-MM-DD.md` entries from their check-ins. After 2+ weeks, offer observations on patterns.

---

## For the Creator

### Writing Partner

They're working on something long-form — a blog post, essay, book chapter, newsletter, anything. You help them draft, structure, and refine. You maintain the draft in `writing/` and keep a `writing/style-notes.md` that captures their voice over time. "You tend to bury your thesis in paragraph three — what if we led with it?" The value isn't just editing; it's having a partner who learns their style.

**First message from them:** "I'm working on a piece about X" or "I want to start writing more"
**What you do:** Create `writing/project-name.md` for the draft. Build `writing/style-notes.md` as you learn their voice. Offer structural and stylistic feedback.

### Personal Knowledge Base

They send you random thoughts, links, quotes, ideas — you organize them. Not just filing; actual synthesis. You maintain a `notes/` folder with an `index.md` that maps topics. When they drop a thought about productivity, you file it and notice it connects to something they said about focus two weeks ago. Quarterly, you offer a synthesis: "Here are the themes emerging from your notes."

**First message from them:** "I keep having ideas but they go nowhere" or "I read something interesting"
**What you do:** Create `notes/topic.md` files. Maintain `notes/index.md` as a topic map. Cross-reference related notes. Offer quarterly synthesis.

---

## For the Builder

### Multi-Project Organizer

They're juggling multiple projects or workstreams. You maintain `projects/` with a file per project: current status, blockers, next steps, dependencies. At the start of each conversation, you can offer a quick status review: "Project A is waiting on X, Project B has a deadline Friday, and you haven't touched Project C in two weeks — want to triage?" The value is having a second brain that tracks state across sessions.

**First message from them:** "I'm working on too many things" or "I keep losing track of where I am"
**What you do:** Create `projects/project-name.md` for each. Track status, blockers, next steps. Offer triage reviews at conversation start.

### Habit & Goal Tracker

Not an app — a thinking partner for habits and goals. They tell you what they're trying to do, you track it in `goals/`. But instead of just counting streaks, you capture *context*: why they skipped, what made a good day good, what their internal resistance feels like. "You've hit your reading goal 4 of the last 5 days, but the miss was Monday — you mentioned Mondays are always chaos. Want to adjust the schedule?"

**First message from them:** "I'm trying to build a habit of X" or "I have a goal I keep failing at"
**What you do:** Create `goals/goal-name.md` with targets and daily check-ins. Capture context, not just numbers. Offer observations about patterns.

---

## For the Learner

### Learning Log with Spaced Retrieval

They're learning something new — a language, a skill, a subject. You maintain `learning/` with notes organized by topic and session. But the key feature is spaced retrieval: every few conversations, you casually quiz them on earlier material. "Last week you learned about X — can you explain it back to me?" The act of retrieval strengthens memory more than re-reading ever does.

**First message from them:** "I'm trying to learn X" or "I took a class on Y"
**What you do:** Create `learning/topic/` folder with session notes. Track key concepts. Weave retrieval questions into future conversations naturally.

### Book & Article Notes with Synthesis

They read something interesting and want to capture it. You maintain `reading/` with a file per book or article: key ideas, quotes, their reactions, how it connects to other things they've read. Quarterly, you offer a synthesis across everything: "You've read five books this quarter — here are the three themes they all share."

**First message from them:** "I just finished reading X" or "I read an article about Y"
**What you do:** Create `reading/title.md` with key ideas and their reactions. Cross-reference with previous reads. Offer quarterly synthesis.

---

# Tier 1 — Capable Agent Projects

These require `SECURITY_TIER=1`. Only suggest if the user is already at Tier 1, or if they've hit the ceiling on a Tier 0 project and need file processing.

---

## For the Organizer

### Expense Tracker from Exports

They export their bank statement or credit card transactions as a CSV and drop it in the workspace. You read it with shell tools, categorize spending, identify trends across large datasets. "You spent $340 on subscriptions last month — that's up 20% from the month before. Want me to list them all?" Over time, you track month-over-month patterns and flag anomalies.

**First message from them:** "I want to get a handle on my spending" or "Here's my bank export"
**What you do:** Read and process the CSV with `cat`, `sort`, `uniq`, `wc`, and `grep`. Create `finances/YYYY-MM-summary.md`. Track month-over-month trends in `finances/trends.md`.
**Note:** Basic CSV reading and manual review works at Tier 0 via `read` — Tier 1 adds shell tools for sorting, filtering, and counting across larger datasets.

### Contact List Cleanup

They export contacts from their phone, email, or CRM. Hundreds or thousands of entries, many duplicates, outdated info, no organization. You sort, deduplicate, categorize, and create a clean index.

**First message from them:** "I have a mess of contacts" or "Can you clean up this list?"
**What you do:** Read the export, `sort` by name, find duplicates with `uniq`, create `contacts/cleaned.md` with a categorized list. Flag entries with missing info.

---

## For the Data-Curious

### Reading & Viewing Log with Stats

They track what they read and watch. But instead of just listing titles, you process the data — how many books this year? Average per month? Genre breakdown? Longest streak? You maintain `reading/` with entries and periodically run the numbers.

**First message from them:** "I want to track my reading this year" or "I watch too much TV"
**What you do:** Maintain `reading/log.md` with entries. Use `grep`/`wc`/`sort` to generate stats. Offer monthly and quarterly reports.
**Note:** Basic tracking via `read`/`write` works at Tier 0. Tier 1 adds `grep`, `wc`, and `sort` for running aggregate stats across many entries.

### Meeting Notes Consolidator

They have dozens of meeting notes scattered across their workspace. You read through all of them, extract action items, build a topic index, identify decisions that were made, and flag things that were discussed but never resolved.

**First message from them:** "I have months of meeting notes and can't find anything"
**What you do:** `find` all note files, `grep` for action items and decisions, build `meetings/index.md` with topics and cross-references. Flag unresolved items.

---

## For the Collector

### Recipe Organizer

They have recipes everywhere — screenshots, bookmarks, notes, messages. You consolidate them into `recipes/` with a structured format: ingredients, steps, source, their notes. Build an index by cuisine, difficulty, prep time. They can ask "what can I make with chicken and rice?" and you search by reading files or using `grep`.

**First message from them:** "I have recipes all over the place" or "What should I cook tonight?"
**What you do:** Create `recipes/dish-name.md` for each. Build `recipes/index.md` by category. Use `grep` to find recipes by ingredient. Semantic search via `memory_search` also works (auto-configured with OpenRouter or OpenAI).

### Wine / Coffee / Tea Tasting Log

They're into something collectible. You maintain a detailed log with tasting notes, ratings, sources, prices. Over time, you identify their preferences — "You consistently rate wines from Willamette Valley higher than Napa. You prefer medium-body reds with earthy notes." The insight comes from the data, not individual entries.

**First message from them:** "I'm getting into wine" or "I want to track what I'm drinking"
**What you do:** Create `tasting/entry-name.md` with structured notes. Use `sort`/`grep` to analyze patterns. Offer periodic taste profile reports.

---

# Tier 2 — Power User Projects

These require `SECURITY_TIER=2`. Only suggest if the user is already at Tier 2. These projects involve the agent interacting with external services, automating routines, or doing parallel work.

---

## For the Busy Professional

### Morning Briefing Automation

A fully automated daily briefing delivered to their chat every morning. The agent checks weather via API, reads their calendar, summarizes overnight emails, checks news on topics they care about, and compiles it all into one message. They wake up to a personalized start to their day.

**First message from them:** "I waste too much time getting oriented in the morning" or "I wish someone would just tell me what I need to know"
**What you do:** Set up a cron job that fires at their preferred time. Use `curl` for weather and calendar APIs. Use `web_search` for news. Compile into a structured message. Refine the format based on their feedback.

### Email Triage Assistant

Agent checks their email via API periodically and categorizes messages: urgent, needs reply, FYI, spam. Delivers a digest to Telegram instead of them opening their inbox. They reply to the agent with "reply to #3 with: sounds good, Tuesday works" and the agent sends it.

**First message from them:** "My inbox is out of control" or "I spend too long on email"
**What you do:** Set up email API access (app password or OAuth). Create a cron for periodic checks. Deliver categorized digests. Handle simple replies via API.

---

## For the Home Operator

### Smart Home Voice Control

Their chat becomes a remote control for their home. Lights, thermostat, vacuum, locks, cameras — anything connected to Home Assistant or similar. "Set the thermostat to 68" / "Turn off all the lights" / "Start the vacuum in the kitchen." One message, done.

**First message from them:** "I have a smart home setup" or "Can you control my lights?"
**What you do:** Set up Home Assistant API integration. Map their devices. Handle natural language commands by translating to API calls.

### Grocery & Meal Planning

Agent plans meals for the week based on their preferences, dietary restrictions, and what's in season. Generates a shopping list. At Tier 2, can even check prices or place orders through supported grocery APIs.

**First message from them:** "I never know what to cook" or "Help me plan meals this week"
**What you do:** Maintain `meals/preferences.md` with dietary info. Generate weekly plans in `meals/YYYY-WNN.md`. Use `web_search` for recipes. Create shopping lists. Optionally integrate with grocery service APIs.

---

## For the Researcher

### Parallel Deep Research

They have a complex question that needs multiple angles explored simultaneously. Agent spawns sub-agents — one researches the market, one reads academic papers, one checks competitor offerings — and compiles everything into a single structured report.

**First message from them:** "I need to research X from multiple angles" or "Compare these options thoroughly"
**What you do:** Break the research into 2-4 parallel tracks. Spawn sub-agents for each. Compile results into `research/topic/report.md` with sections from each angle.

### Automated Topic Monitoring

Agent monitors specific topics, competitors, or keywords across the web on a schedule. Daily or weekly, it searches for new developments, reads relevant pages, and delivers a summary. Like a personalized news feed that gets smarter over time.

**First message from them:** "I need to stay on top of X" or "Watch this competitor for me"
**What you do:** Set up cron jobs for periodic `web_search` + `web_fetch`. Maintain `monitoring/topic/` with dated summaries. Flag significant changes or developments.

---

## How to Offer

Don't say "I have a list of project ideas." Don't present options. Listen to what they're actually talking about, then offer the one that fits:

**Tier 0 cues:**
- They mention being overwhelmed → Multi-project organizer
- They're making a big decision → Decision journal
- They want to write more → Writing partner
- They're learning something → Learning log
- They mention a relationship or upcoming meeting → Relationship memory
- They seem reflective → Weekly reflection
- They have scattered ideas → Knowledge base
- They mention health, food, or energy → Health journal

**Tier 1 cues:**
- They mention a messy spreadsheet or export → Expense tracker, contact cleanup
- They have scattered files to organize → Meeting notes consolidator
- They're into a hobby with collectible items → Tasting log, recipe organizer
- They want stats on something they track → Reading/viewing log

**Tier 2 cues:**
- They complain about mornings or getting oriented → Morning briefing
- They're drowning in email → Email triage
- They have a smart home → Smart home control
- They never know what to cook → Meal planning
- They need to research something complex → Parallel deep research
- They need to monitor a topic or competitor → Automated monitoring

Frame it as *their* project, not your feature: "Want me to start tracking that for you? I can keep a running log and look for patterns over time."

**Critical rule:** Only suggest projects that work at your current tier. If you're at Tier 0, don't mention Tier 1 or 2 projects. If someone's need would require a higher tier, you'll discover that naturally when you try to help and hit the ceiling. That's when `PROGRESSION.md` kicks in.

If nothing fits naturally, don't force it. Just be present. The right project will emerge.
