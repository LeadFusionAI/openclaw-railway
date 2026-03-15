/**
 * Log Bridge — Gateway stdout processor with optional Tool Observer
 *
 * Replaces the bash `grep --line-buffered '\[' | while read` pipe chain with
 * a single Node.js process that:
 *
 * 1. Passes through all gateway log lines to stdout (for Railway logs)
 * 2. When TOOL_OBSERVER_ENABLED, extracts tool call events and batches
 *    them to Telegram/Discord via the bot API
 *
 * Zero dependencies — uses only readline, https, and process.stdin.
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
 */

import readline from 'node:readline';
import https from 'node:https';

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
const TOKEN = args.token || '';
const CHAT_ID = args['chat-id'] || '';
const THREAD_ID = args['thread-id'] || '';
const VERBOSITY = args.verbosity || 'normal';
const BATCH_MS = parseInt(args['batch-ms'] || '2000', 10);

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
// Event batching
// ---------------------------------------------------------------------------
let eventBatch = [];
let batchTimer = null;

function flushBatch() {
  batchTimer = null;
  if (eventBatch.length === 0) return;

  const lines = eventBatch.splice(0);
  const header = '\u{1F527} Tool Activity\n\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501';
  const body = lines.join('\n');
  const message = `${header}\n${body}`;

  sendMessage(message);
}

function queueEvent(line) {
  eventBatch.push(line);
  if (!batchTimer) {
    batchTimer = setTimeout(flushBatch, BATCH_MS);
  }
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
// Log line parsing — extract tool events from gateway JSON logs
// ---------------------------------------------------------------------------
function tryParseToolEvent(line) {
  // Only attempt JSON parse on lines that look like JSON objects
  if (!line.startsWith('{')) return null;

  try {
    const obj = JSON.parse(line);

    // Flexible detection: check multiple possible field names the gateway
    // might use for tool call events. This will be validated on first deploy
    // with observer enabled.
    const toolName = obj.tool || obj.toolName || obj.toolCall?.name
      || (obj.event === 'tool_call' ? obj.name : null)
      || (obj.type === 'tool_call' ? obj.name : null);

    if (!toolName) return null;

    const icon = TOOL_ICONS[toolName] || '\u{1F527}';

    if (VERBOSITY === 'minimal') {
      return `${icon} ${toolName}`;
    }

    // Extract a one-line summary of the tool input
    const input = obj.input || obj.args || obj.toolCall?.input || obj.params || {};
    const summary = formatToolSummary(toolName, input);

    if (VERBOSITY === 'verbose') {
      const duration = obj.duration || obj.durationMs;
      const status = obj.status || obj.result?.status;
      const extras = [
        duration ? `${duration}ms` : '',
        status ? `[${status}]` : '',
      ].filter(Boolean).join(' ');
      return `${icon} ${toolName}: ${summary}${extras ? ` (${extras})` : ''}`;
    }

    // normal
    return `${icon} ${toolName}: ${summary}`;
  } catch {
    return null;
  }
}

function formatToolSummary(tool, input) {
  if (typeof input === 'string') {
    return truncate(input, 80);
  }

  switch (tool) {
    case 'read':
      return input.path || input.file || '(file)';
    case 'write':
    case 'edit':
      return input.path || input.file || '(file)';
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
      return input.path || input.key || '';
    case 'apply_patch':
      return '(patch)';
    default: {
      // Generic: show first string-valued field
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
// Main — read stdin line by line, pass through + optionally observe
// ---------------------------------------------------------------------------
const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', (line) => {
  // Always pass through to stdout (Railway logs)
  // Filter like the old grep: only lines containing '['
  if (line.includes('[')) {
    process.stdout.write(`[gateway] ${line}\n`);
  }

  // Observer: parse and queue tool events
  if (OBSERVER_ENABLED && TOKEN && CHAT_ID) {
    const event = tryParseToolEvent(line);
    if (event) {
      queueEvent(event);
    }
  }
});

rl.on('close', () => {
  // Flush any remaining events before exit
  if (batchTimer) {
    clearTimeout(batchTimer);
    batchTimer = null;
  }
  if (eventBatch.length > 0) {
    flushBatch();
  }
});

// Prevent unhandled errors from crashing the bridge (and killing the gateway pipe)
process.on('uncaughtException', () => {});
process.on('unhandledRejection', () => {});
