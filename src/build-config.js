/**
 * Build OpenClaw config from environment variables
 *
 * This script reads environment variables and generates openclaw.json
 * with secure defaults and user-specified settings.
 *
 * Credentials use SecretRef objects where supported (v2026.2.26+, expanded
 * in v2026.3.3 via PR #29580). The gateway resolves these at startup from
 * the entrypoint's environment, then holds them in-memory only. The config
 * file on disk never contains plaintext secrets for SecretRef-capable fields.
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

/**
 * Create a SecretRef object that tells the gateway to resolve a secret
 * from an environment variable at startup.
 */
function secretRef(envVar) {
  return { source: 'env', provider: 'default', id: envVar };
}

const CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || '/data/.openclaw/openclaw.json';
const DEFAULTS_PATH = '/app/config/defaults.json';
const WORKSPACE_DIR = process.env.WORKSPACE_DIR || '/data/workspace';

// LLM Provider API Keys - OpenClaw reads these directly from env
// Listed here so Railway detects them in the UI
const LLM_PROVIDERS = [
  // Major cloud providers
  'ANTHROPIC_API_KEY',
  'OPENAI_API_KEY',
  'GOOGLE_AI_API_KEY',
  // Aggregators/Gateways
  'OPENROUTER_API_KEY',
  'VERCEL_GATEWAY_API_KEY',
  // Generic fallback
  'LLM_API_KEY',
  // Fast inference
  'GROQ_API_KEY',
  'TOGETHER_API_KEY',
  'FIREWORKS_API_KEY',
  // Coding-focused
  'ZAI_API_KEY',
  'KIMI_API_KEY',
  'MOONSHOT_API_KEY',
  'MINIMAX_API_KEY',
  'DEEPSEEK_API_KEY',
  // Other providers
  'XAI_API_KEY',
  'MISTRAL_API_KEY',
  'VENICE_API_KEY',
  'CLOUDFLARE_API_KEY',
  // AWS Bedrock (needs region too)
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_REGION',
];

// Embeddings-capable provider keys (these providers support embeddings natively)
const EMBEDDINGS_NATIVE_KEYS = ['OPENAI_API_KEY', 'GOOGLE_AI_API_KEY'];

const TIER_NAMES = {
  0: 'Personal Assistant',
  1: 'Capable Agent',
  2: 'Power User',
  3: 'Operator',
};

/**
 * Apply security tier overrides to the config.
 * Tier 0 uses defaults.json as-is.
 * Higher tiers progressively unlock more capabilities.
 */
function applySecurityTier(config, tier) {
  config.tools = config.tools || {};

  if (tier === 0) {
    // Tier 0: defaults.json as-is — web + memory_search included, ls-only exec
    config.tools.exec = config.tools.exec || {};
    config.tools.exec.host = 'gateway';
    config.tools.exec.security = 'allowlist';
    config.tools.exec.ask = 'off';
    return;
  }

  if (tier === 1) {
    // Tier 1: same allow/deny as Tier 0, curated exec with expanded allowlist
    config.tools.exec = config.tools.exec || {};
    config.tools.exec.host = 'gateway';
    config.tools.exec.security = 'allowlist';
    config.tools.exec.ask = 'off';
    return;
  }

  if (tier >= 2) {
    // Tier 2+: unlock process, browser, sessions_spawn, agents_list
    config.tools.allow = [
      'read', 'write', 'edit', 'memory_get', 'memory_search',
      'web_search', 'web_fetch', 'exec', 'cron', 'image',
      'process', 'browser', 'sessions_spawn', 'sessions_yield', 'agents_list',
    ];
    config.tools.deny = ['nodes', 'gateway'];

    config.tools.exec = config.tools.exec || {};
    config.tools.exec.host = 'gateway';
    config.tools.exec.security = 'full';
    config.tools.exec.ask = 'off';
    return;
  }
}

/**
 * Auto-configure embeddings for memory_search.
 * If OpenRouter is the only provider, route embeddings through it.
 * If a native embeddings provider exists, let OpenClaw auto-detect.
 */
function configureEmbeddings(config) {
  const hasNativeEmbeddings = EMBEDDINGS_NATIVE_KEYS.some(k => process.env[k]);

  if (hasNativeEmbeddings) {
    console.log('[build-config] Embeddings: native provider detected, using auto-detection');
    return;
  }

  if (process.env.OPENROUTER_API_KEY) {
    const model = process.env.LLM_EMBEDDING_MODEL || 'openai/text-embedding-3-small';
    config.agents = config.agents || {};
    config.agents.defaults = config.agents.defaults || {};
    config.agents.defaults.memorySearch = {
      provider: 'openai',
      model: model,
      remote: {
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: secretRef('OPENROUTER_API_KEY'),
      },
    };
    console.log(`[build-config] Embeddings: configured via OpenRouter (model: ${model})`);
    return;
  }

  console.log('[build-config] Embeddings: no embeddings-capable provider detected');
  console.log('[build-config] memory_search will use BM25 keyword fallback');
}

/**
 * Auto-configure imageModel for the image tool.
 * Uses LLM_IMAGE_MODEL if set, otherwise falls back to the primary model.
 * If the primary model doesn't support vision, the gateway will return
 * a clear error at invocation time rather than a warning on every turn.
 */
function configureImageModel(config) {
  const imageModel = process.env.LLM_IMAGE_MODEL || process.env.LLM_PRIMARY_MODEL;
  if (!imageModel) {
    console.log('[build-config] Image model: no model available (LLM_PRIMARY_MODEL not set)');
    return;
  }

  config.agents = config.agents || {};
  config.agents.defaults = config.agents.defaults || {};
  config.agents.defaults.imageModel = imageModel;

  if (process.env.LLM_IMAGE_MODEL) {
    console.log(`[build-config] Image model: ${imageModel} (explicit)`);
  } else {
    console.log(`[build-config] Image model: ${imageModel} (from primary)`);
  }
}

/**
 * Write a workspace marker when SECURITY_TIER=3 is set via env var
 * but capped at Tier 2. The agent reads this and guides the user to SSH.
 */
function writeTier3Marker() {
  const markerPath = path.join(WORKSPACE_DIR, '.tier-status');
  const content = `# Tier Status

SECURITY_TIER=3 was set via environment variable, but Tier 3 (Operator) requires SSH access to configure.

Tier 2 (Power User) has been applied instead. This gives you:
- Full shell access, browser automation, sub-agents, process management
- Everything except gateway config, node control, and elevated permissions

To complete the Tier 3 upgrade, SSH into your Railway container:
\`\`\`
railway ssh
\`\`\`

Then follow the Tier 3 setup in docs/TIERS.md — the main additions are:
- Enabling elevated tool permissions
- Configuring node access if needed
- Gateway management access

Your user requested Tier 3. Guide them through the SSH steps when they're ready.
`;
  try {
    fs.writeFileSync(markerPath, content, { mode: 0o644 });
    console.log('[build-config] Wrote .tier-status marker (Tier 3 requested, Tier 2 applied)');
  } catch (err) {
    console.log('[build-config] WARNING: Could not write .tier-status:', err.message);
  }
}

function buildConfig() {
  // Start with defaults if they exist
  let config = {};
  if (fs.existsSync(DEFAULTS_PATH)) {
    const defaults = fs.readFileSync(DEFAULTS_PATH, 'utf-8');
    config = JSON.parse(defaults);
  }

  // Ensure structure exists
  config.agents = config.agents || {};
  config.agents.defaults = config.agents.defaults || {};
  config.channels = config.channels || {};
  config.gateway = config.gateway || {};

  // --- Security Tier ---
  const rawTier = parseInt(process.env.SECURITY_TIER || '0', 10);
  const tier = Math.max(0, Math.min(3, isNaN(rawTier) ? 0 : rawTier));
  const effectiveTier = tier === 3 ? 2 : tier;

  if (tier === 3) {
    writeTier3Marker();
  }

  applySecurityTier(config, effectiveTier);

  // Single write to avoid interleaved output
  const tierLines = [
    `[build-config] SECURITY_TIER=${tier} (${TIER_NAMES[tier] || 'Unknown'})`,
    ...(tier === 3 ? [
      '[build-config] WARNING: SECURITY_TIER=3 (Operator) requires SSH to configure',
      '[build-config] Applying Tier 2 (Power User) via env var',
      '[build-config] A .tier-status file will be written to the workspace',
    ] : []),
    `[build-config] Effective tier: ${effectiveTier} (${TIER_NAMES[effectiveTier]})`,
    `[build-config] Tools allowed: ${config.tools?.allow?.join(', ') || 'defaults'}`,
    `[build-config] Tools denied: ${config.tools?.deny?.join(', ') || 'none'}`,
    `[build-config] Exec security: ${config.tools?.exec?.security || 'not set'}, ask: ${config.tools?.exec?.ask || 'not set'}`,
  ];
  process.stdout.write(tierLines.join('\n') + '\n');

  // --- Embeddings ---
  configureEmbeddings(config);

  // --- Image Model ---
  configureImageModel(config);

  // --- Brave Search API Key (for web_search tool) ---
  if (process.env.BRAVE_API_KEY) {
    config.tools = config.tools || {};
    config.tools.web = config.tools.web || {};
    config.tools.web.search = {
      provider: 'brave',
      apiKey: secretRef('BRAVE_API_KEY'),
    };
    // Opt-in LLM-grounded snippets mode (v2026.3.8+)
    if (process.env.BRAVE_SEARCH_MODE === 'llm-context') {
      config.tools.web.search.brave = { mode: 'llm-context' };
      console.log('[build-config] Brave Search: llm-context mode enabled');
    }
    console.log('[build-config] Brave Search: API key configured for web_search');
  }

  // --- LLM Model (required - user must specify) ---
  if (process.env.LLM_PRIMARY_MODEL) {
    config.agents.defaults.model = config.agents.defaults.model || {};
    config.agents.defaults.model.primary = process.env.LLM_PRIMARY_MODEL;
  }

  if (process.env.LLM_FALLBACK_MODELS) {
    config.agents.defaults.model = config.agents.defaults.model || {};
    config.agents.defaults.model.fallbacks = process.env.LLM_FALLBACK_MODELS.split(',').map(s => s.trim());
  }

  if (process.env.LLM_HEARTBEAT_MODEL) {
    config.agents.defaults.heartbeat = config.agents.defaults.heartbeat || {};
    config.agents.defaults.heartbeat.model = process.env.LLM_HEARTBEAT_MODEL;
  }

  // Lightweight heartbeat context (v2026.3.1+) — reduces token usage for cron/heartbeat turns
  if (process.env.LLM_HEARTBEAT_LIGHT_CONTEXT === 'true') {
    config.agents.defaults.heartbeat = config.agents.defaults.heartbeat || {};
    config.agents.defaults.heartbeat.lightContext = true;
    console.log('[build-config] Heartbeat: light context mode enabled (skips bootstrap injection)');
  }

  if (process.env.LLM_SUBAGENT_MODEL) {
    config.agents.defaults.subagents = config.agents.defaults.subagents || {};
    config.agents.defaults.subagents.model = process.env.LLM_SUBAGENT_MODEL;
  }

  // --- Telegram ---
  if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.enabled = true;
    config.channels.telegram.botToken = secretRef('TELEGRAM_BOT_TOKEN');

    if (process.env.TELEGRAM_OWNER_ID) {
      // Telegram user IDs are numeric — parseInt matches what the Bot API sends.
      // Discord/Slack use string IDs, which is correct for their platforms.
      const ownerId = parseInt(process.env.TELEGRAM_OWNER_ID, 10);
      config.channels.telegram.allowFrom = config.channels.telegram.allowFrom || [];
      if (!config.channels.telegram.allowFrom.includes(ownerId)) {
        config.channels.telegram.allowFrom.push(ownerId);
      }
      config.channels.telegram.dmPolicy = 'allowlist';
    } else {
      config.channels.telegram.dmPolicy = 'pairing';
    }

    // Groups require mention by default
    config.channels.telegram.groups = config.channels.telegram.groups || {};
    config.channels.telegram.groups['*'] = { requireMention: true };

    // Streaming mode: off (default), partial, block, progress
    // progress shows tool execution steps in real-time without draft flashing
    if (process.env.STREAMING_MODE) {
      config.channels.telegram.streaming = process.env.STREAMING_MODE;
      console.log(`[build-config] Telegram streaming: ${process.env.STREAMING_MODE}`);
    }

    // Enable the Telegram plugin (separate from channel config)
    config.plugins = config.plugins || {};
    config.plugins.entries = config.plugins.entries || {};
    config.plugins.entries.telegram = { enabled: true };
  }

  // --- Discord ---
  if (process.env.DISCORD_BOT_TOKEN) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.enabled = true;
    config.channels.discord.token = secretRef('DISCORD_BOT_TOKEN');

    if (process.env.DISCORD_OWNER_ID) {
      config.channels.discord.dm = config.channels.discord.dm || {};
      config.channels.discord.dm.allowFrom = config.channels.discord.dm.allowFrom || [];
      if (!config.channels.discord.dm.allowFrom.includes(process.env.DISCORD_OWNER_ID)) {
        config.channels.discord.dm.allowFrom.push(process.env.DISCORD_OWNER_ID);
      }
      config.channels.discord.dmPolicy = 'allowlist';
    } else {
      config.channels.discord.dmPolicy = 'pairing';
    }
  }

  // --- Slack ---
  if (process.env.SLACK_BOT_TOKEN) {
    config.channels.slack = config.channels.slack || {};
    config.channels.slack.enabled = true;
    config.channels.slack.botToken = secretRef('SLACK_BOT_TOKEN');

    if (process.env.SLACK_APP_TOKEN) {
      config.channels.slack.appToken = secretRef('SLACK_APP_TOKEN');
    }

    if (process.env.SLACK_OWNER_ID) {
      config.channels.slack.dm = config.channels.slack.dm || {};
      config.channels.slack.dm.allowFrom = config.channels.slack.dm.allowFrom || [];
      if (!config.channels.slack.dm.allowFrom.includes(process.env.SLACK_OWNER_ID)) {
        config.channels.slack.dm.allowFrom.push(process.env.SLACK_OWNER_ID);
      }
      config.channels.slack.dmPolicy = 'allowlist';
    } else {
      config.channels.slack.dmPolicy = 'pairing';
    }
  }

  // --- Gateway ---
  config.gateway.bind = 'loopback';
  config.gateway.auth = config.gateway.auth || {};

  config.gateway.auth.mode = 'token';
  if (process.env.GATEWAY_TOKEN) {
    config.gateway.auth.token = secretRef('GATEWAY_TOKEN');
  } else {
    // No env var to reference — generate a random token and write it literally.
    // This is acceptable: gateway tokens are internal (loopback-only) and not
    // a high-value secret. A SecretRef requires a stable env var to resolve.
    config.gateway.auth.token = crypto.randomUUID();
  }

  // Required for headless start
  config.gateway.mode = 'local';

  // --- Provider Keys ---
  // LLM provider keys are passed to the gateway via env -i passthrough (from
  // the entrypoint's .secrets.env file). The gateway reads them from its own
  // process.env at startup. We no longer inject them into config.env because:
  //   1. config.env doesn't support SecretRef — values would be plaintext on disk
  //   2. The gateway already reads standard provider env vars from process.env
  //   3. Keeping secrets out of the config file is the whole point of SecretRef
  //
  // config.env is still used for non-secret passthrough vars (timezone, etc).
  config.env = config.env || {};

  // --- Custom Binary Trusted Dirs ---
  // When EXEC_EXTRA_COMMANDS is set, declare /data/bin as a trusted directory
  // so the new safeBinTrustedDirs exec hardening (v2026.2.21+) allows our binaries.
  if (process.env.EXEC_EXTRA_COMMANDS) {
    config.tools = config.tools || {};
    config.tools.exec = config.tools.exec || {};
    config.tools.exec.safeBinTrustedDirs = ['/data/bin'];
    config.tools.exec.pathPrepend = ['/data/bin'];
    console.log('[build-config] Custom binaries: /data/bin added to safeBinTrustedDirs + pathPrepend');
  }

  // --- Extra Environment Keys ---
  // Extra env vars (e.g. for custom binaries) are passed via the entrypoint's
  // .secrets.env file → env -i passthrough. We log which keys were requested
  // but don't inject values into config.env (they'd be plaintext on disk).
  if (process.env.EXTRA_ENV_KEYS) {
    const extraKeys = process.env.EXTRA_ENV_KEYS.split(',').map(s => s.trim()).filter(Boolean);
    for (const key of extraKeys) {
      if (!process.env[key]) {
        console.log(`[build-config] WARNING: EXTRA_ENV_KEYS lists '${key}' but it is not set`);
      }
    }
    console.log(`[build-config] Extra env keys (via env passthrough): ${extraKeys.filter(k => process.env[k]).join(', ') || 'none'}`);
  }

  // --- Timezone Override (v2026.3.13+) ---
  // OPENCLAW_TZ is passed via the entrypoint's .secrets.env → env -i passthrough.
  if (process.env.OPENCLAW_TZ) {
    console.log(`[build-config] Timezone: ${process.env.OPENCLAW_TZ}`);
  }

  // --- Agent Identity ---
  // OpenClaw moved identity under agents.list[] (top-level identity is legacy)
  if (process.env.AGENT_NAME) {
    config.agents.list = config.agents.list || [{ id: 'main' }];
    const mainAgent = config.agents.list.find(a => a.id === 'main') || config.agents.list[0];
    mainAgent.identity = mainAgent.identity || {};
    mainAgent.identity.name = process.env.AGENT_NAME;
  }

  return config;
}

function main() {
  // Always regenerate config from env vars (Railway controls config via env vars)

  // Check for minimum requirements
  const hasChannel = [
    'TELEGRAM_BOT_TOKEN',
    'DISCORD_BOT_TOKEN',
    'SLACK_BOT_TOKEN',
  ].some(key => process.env[key]);

  if (!hasChannel) {
    console.log('[build-config] WARNING: No channel configured');
    console.log('[build-config] Set at least one of: TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, SLACK_BOT_TOKEN');
  }

  // Check for LLM provider
  const hasLLM = LLM_PROVIDERS.some(key => process.env[key]);
  if (!hasLLM) {
    console.log('[build-config] WARNING: No LLM provider configured');
    console.log('[build-config] Set at least one of:', LLM_PROVIDERS.join(', '));
  }

  // Check for model selection (required)
  if (!process.env.LLM_PRIMARY_MODEL) {
    console.log('[build-config] WARNING: LLM_PRIMARY_MODEL not set');
    console.log('[build-config] You must specify a model matching your provider.');
    console.log('[build-config] Format: LLM_PRIMARY_MODEL=provider/model-name');
    console.log('[build-config] Check your provider docs for available model IDs.');
    console.log('[build-config] See docs/environment.md for provider links.');
  }

  const config = buildConfig();

  // Ensure directory exists
  const configDir = path.dirname(CONFIG_PATH);
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
  }

  // Write config with secure permissions
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), { mode: 0o600 });

  // Debug: print full config structure
  // SecretRef fields show as { source: "env", provider: "default", id: "KEY_NAME" }
  // which is safe to log (it's a reference, not the secret itself).
  // Only the gateway auth token needs redaction when it's a literal (random UUID).
  const debugConfig = JSON.parse(JSON.stringify(config));
  if (debugConfig.gateway?.auth?.token && typeof debugConfig.gateway.auth.token === 'string') {
    debugConfig.gateway.auth.token = '[REDACTED-RANDOM]';
  }

  // Single write to avoid interleaved output with gateway/entrypoint logs
  const summary = [
    `[build-config] Generated config at ${CONFIG_PATH}`,
    `[build-config] Channels configured: ${Object.keys(config.channels || {}).join(', ') || 'none'}`,
    `[build-config] Gateway auth mode: ${config.gateway?.auth?.mode || 'not set'}`,
    `[build-config] Gateway token set: ${config.gateway?.auth?.token ? 'yes' : 'no'}`,
    `[build-config] Full config:`,
    JSON.stringify(debugConfig, null, 2),
  ].join('\n');
  process.stdout.write(summary + '\n');
}

main();
