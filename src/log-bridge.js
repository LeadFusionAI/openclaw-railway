/**
 * Log Bridge — Gateway stdout passthrough + Tool Observer via session files
 *
 * Two independent functions:
 *
 * 1. STDIN PASSTHROUGH: Reads gateway stdout line by line, forwards lines
 *    containing '[' to stdout with a [gateway] prefix (for Railway logs).
 *    Replaces the old bash `grep --line-buffered '\[' | while read` chain.
 *
 * 2. TOOL OBSERVER (when --observer=true): Watches session .jsonl files for
 *    new tool call entries and batches them to Telegram/Discord via bot API.
 *    The gateway only logs tool events to WebSocket clients, not stdout —
 *    so we read them from the session transcripts instead.
 *
 * Zero dependencies — uses only readline, https, fs, and path.
 *
 * Usage:
 *   openclaw gateway run ... 2>&1 | node log-bridge.js [options]
 *
 * Options (via CLI args):
 *   --observer           Enable tool observer
 *   --channel=telegram   Channel type (telegram|discord)
 *   --token=BOT_TOKEN    Bot token for sending messages
 *   --chat-id=CHAT_ID    Chat/channel ID to send to
 *   --thread-id=ID       Thread/topic ID (optional)
 *   --verbosity=normal   minimal|normal|verbose
 *   --batch-ms=2000      Batch window in ms
 *   --sessions-dir=PATH  Session files directory
 */

import readline from 'node:readline';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------
const args = {};
for (const arg of process.argv.slice(2)) {
  if (arg.startsWith('--')) {
    const eq = arg.indexOf('=');
    if (eq !== -1) {
      args[arg.slice(2, eq)] = arg.slice(eq + 1);
    } else {
      args[arg.slice(2)] = 'true';
    }
  }
}

const OBSERVER_ENABLED = args.observer === 'true';
const CHANNEL = args.channel || 'telegram';
let TOKEN = args.token || '';
if (args['token-file']) {
  try {
    TOKEN = fs.readFileSync(args['token-file'], 'utf-8').trim();
    fs.unlinkSync(args['token-file']); // delete after reading — never persists on disk
  } catch {}
}
const CHAT_ID = args['chat-id'] || '';
const THREAD_ID = args['thread-id'] || '';
const VERBOSITY = args.verbosity || 'normal';
const SESSIONS_DIR = args['sessions-dir'] || '/data/.openclaw/agents/main/sessions';

// ---------------------------------------------------------------------------
// Tool event icons
// ---------------------------------------------------------------------------
const TOOL_ICONS = {
  read: '\u{1F4D6}',
  write: '\u{270F}\uFE0F',
  edit: '\u{270F}\uFE0F',
  apply_patch: '\u{1FA79}',
  exec: '\u26A1',
  web_fetch: '\u{1F310}',
  web_search: '\u{1F50D}',
  memory_get: '\u{1F9E0}',
  memory_search: '\u{1F9E0}',
  cron: '\u23F0',
  image: '\u{1F5BC}\uFE0F',
  browser: '\u{1F310}',
  process: '\u2699\uFE0F',
  sessions_spawn: '\u{1F504}',
  sessions_yield: '\u{1F504}',
  agents_list: '\u{1F4CB}',
};

// ---------------------------------------------------------------------------
// Send tool events immediately — one message per tool call
// ---------------------------------------------------------------------------
function emitEvent(line) {
  sendMessage(line);
}

// ---------------------------------------------------------------------------
// Message sending — Telegram / Discord
// ---------------------------------------------------------------------------
function sendMessage(text) {
  if (CHANNEL === 'telegram') {
    sendTelegram(text);
  } else if (CHANNEL === 'discord') {
    sendDiscord(text);
  }
}

function sendTelegram(text) {
  const payload = JSON.stringify({
    chat_id: CHAT_ID,
    text: text,
    disable_notification: true,
    ...(THREAD_ID ? { message_thread_id: parseInt(THREAD_ID, 10) } : {}),
  });

  const req = https.request({
    hostname: 'api.telegram.org',
    path: `/bot${TOKEN}/sendMessage`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    },
  });

  req.on('error', () => {}); // best-effort, never crash
  req.write(payload);
  req.end();
}

function sendDiscord(text) {
  const hostname = 'discord.com';
  const basePath = `/api/v10/channels/${CHAT_ID}/messages`;
  const payload = JSON.stringify({ content: text });

  const req = https.request({
    hostname,
    path: basePath,
    method: 'POST',
    headers: {
      'Authorization': `Bot ${TOKEN}`,
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    },
  });

  req.on('error', () => {}); // best-effort
  req.write(payload);
  req.end();
}

// ---------------------------------------------------------------------------
// Tool event extraction from session transcript lines
//
// Session .jsonl format (one JSON object per line):
//   {"type":"message","message":{"role":"assistant","content":[
//     {"type":"toolCall","name":"read","arguments":{"file_path":"..."}}
//   ]}}
// ---------------------------------------------------------------------------
function extractToolEvents(jsonLine) {
  try {
    const obj = JSON.parse(jsonLine);
    if (obj.type !== 'message') return [];
    const msg = obj.message;
    if (msg?.role !== 'assistant' || !Array.isArray(msg.content)) return [];

    const events = [];
    for (const block of msg.content) {
      if (block.type !== 'toolCall') continue;
      const toolName = block.name;
      if (!toolName) continue;

      const icon = TOOL_ICONS[toolName] || '\u{1F527}';

      if (VERBOSITY === 'minimal') {
        events.push(`${icon} ${toolName}`);
        continue;
      }

      const summary = formatToolSummary(toolName, block.arguments || {});
      events.push(`${icon} ${toolName}${summary ? ': ' + summary : ''}`);
    }
    return events;
  } catch {
    return [];
  }
}

function formatToolSummary(tool, input) {
  switch (tool) {
    case 'read':
      return truncate(input.file_path || input.path || '', 80);
    case 'write':
    case 'edit':
      return truncate(input.file_path || input.path || '', 80);
    case 'exec': {
      const cmd = input.command || input.cmd || '';
      return truncate(cmd, 100);
    }
    case 'web_fetch':
      return truncate(input.url || '', 100);
    case 'web_search':
      return truncate(input.query || input.q || '', 80);
    case 'memory_search':
      return truncate(input.query || input.q || '', 80);
    case 'memory_get':
      return truncate(input.path || input.key || '', 80);
    case 'apply_patch':
      return '(patch)';
    default: {
      for (const [k, v] of Object.entries(input)) {
        if (typeof v === 'string' && v.length > 0) {
          return truncate(`${k}=${v}`, 80);
        }
      }
      return '';
    }
  }
}

function truncate(str, max) {
  if (str.length <= max) return str;
  return str.slice(0, max - 1) + '\u2026';
}

// ---------------------------------------------------------------------------
// Session file watcher
//
// Watches the sessions directory for .jsonl file changes. When a file grows,
// reads the new lines and checks for tool call events.
// ---------------------------------------------------------------------------
const watchedFiles = new Map(); // filePath -> { size: number }

function tailNewLines(filePath) {
  try {
    const stat = fs.statSync(filePath);
    const prev = watchedFiles.get(filePath);
    const prevSize = prev ? prev.size : stat.size; // skip existing content on first see

    if (!prev) {
      // First time seeing this file — record size, don't read (skip history)
      watchedFiles.set(filePath, { size: stat.size });
      return;
    }

    if (stat.size <= prevSize) {
      // File didn't grow (or was truncated)
      watchedFiles.set(filePath, { size: stat.size });
      return;
    }

    // Read only the new bytes
    const buf = Buffer.alloc(stat.size - prevSize);
    const fd = fs.openSync(filePath, 'r');
    fs.readSync(fd, buf, 0, buf.length, prevSize);
    fs.closeSync(fd);

    watchedFiles.set(filePath, { size: stat.size });

    // Process each new line
    const newContent = buf.toString('utf-8');
    for (const line of newContent.split('\n')) {
      if (!line.trim()) continue;
      const events = extractToolEvents(line);
      for (const ev of events) {
        emitEvent(ev);
      }
    }
  } catch {
    // best-effort — don't crash on file read errors
  }
}

function startSessionWatcher() {
  // Initial scan — record current sizes without reading
  try {
    const files = fs.readdirSync(SESSIONS_DIR);
    for (const f of files) {
      if (!f.endsWith('.jsonl')) continue;
      const fullPath = path.join(SESSIONS_DIR, f);
      try {
        const stat = fs.statSync(fullPath);
        watchedFiles.set(fullPath, { size: stat.size });
      } catch {}
    }
  } catch {}

  // Watch for changes
  try {
    fs.watch(SESSIONS_DIR, { persistent: false }, (eventType, filename) => {
      if (!filename || !filename.endsWith('.jsonl')) return;
      const fullPath = path.join(SESSIONS_DIR, filename);
      tailNewLines(fullPath);
    });
  } catch {}
}

// ---------------------------------------------------------------------------
// STDIN passthrough — read gateway stdout, forward filtered lines to stdout
// ---------------------------------------------------------------------------
const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', (line) => {
  // Pass through lines containing '[' to stdout (Railway logs)
  if (line.includes('[')) {
    process.stdout.write(`[gateway] ${line}\n`);
  }
});

rl.on('close', () => {});

// ---------------------------------------------------------------------------
// Start observer if enabled
// ---------------------------------------------------------------------------
if (OBSERVER_ENABLED && TOKEN && CHAT_ID) {
  startSessionWatcher();
}

// Prevent unhandled errors from crashing the bridge (and killing the gateway pipe)
process.on('uncaughtException', () => {});
process.on('unhandledRejection', () => {});
