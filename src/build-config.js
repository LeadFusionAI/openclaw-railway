/**
 * Build OpenClaw config from environment variables
 *
 * This script reads environment variables and generates openclaw.json
 * with secure defaults and user-specified settings.
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || '/data/.openclaw/openclaw.json';
const DEFAULTS_PATH = '/app/config/defaults.json';

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

  // --- LLM Model (required - user must specify) ---
  if (process.env.LLM_PRIMARY_MODEL) {
    config.agents.defaults.model = config.agents.defaults.model || {};
    config.agents.defaults.model.primary = process.env.LLM_PRIMARY_MODEL;
  }

  if (process.env.LLM_FALLBACK_MODELS) {
    config.agents.defaults.model = config.agents.defaults.model || {};
    config.agents.defaults.model.fallbacks = process.env.LLM_FALLBACK_MODELS.split(',').map(s => s.trim());
  }

  // --- Telegram ---
  if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.enabled = true;
    config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;

    if (process.env.TELEGRAM_OWNER_ID) {
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

    // Enable the Telegram plugin (separate from channel config)
    config.plugins = config.plugins || {};
    config.plugins.entries = config.plugins.entries || {};
    config.plugins.entries.telegram = { enabled: true };
  }

  // --- Discord ---
  if (process.env.DISCORD_BOT_TOKEN) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.enabled = true;
    config.channels.discord.token = process.env.DISCORD_BOT_TOKEN;

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
    config.channels.slack.botToken = process.env.SLACK_BOT_TOKEN;

    if (process.env.SLACK_APP_TOKEN) {
      config.channels.slack.appToken = process.env.SLACK_APP_TOKEN;
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

  // Generate a random token if none provided (required for token auth mode)
  const gatewayToken = process.env.GATEWAY_TOKEN || crypto.randomUUID();
  config.gateway.auth.mode = 'token';
  config.gateway.auth.token = gatewayToken;

  // Required for headless start
  config.gateway.mode = 'local';

  // --- Agent Identity ---
  if (process.env.AGENT_NAME) {
    config.identity = config.identity || {};
    config.identity.name = process.env.AGENT_NAME;
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
  console.log('[build-config] Generated config at', CONFIG_PATH);

  // Log key config values for debugging (not sensitive data)
  console.log('[build-config] Channels configured:', Object.keys(config.channels || {}).join(', ') || 'none');
  console.log('[build-config] Gateway auth mode:', config.gateway?.auth?.mode || 'not set');
  console.log('[build-config] Gateway token set:', config.gateway?.auth?.token ? 'yes' : 'no');

  // Debug: print full config structure (redact secrets)
  const debugConfig = JSON.parse(JSON.stringify(config));
  if (debugConfig.channels?.telegram?.botToken) {
    debugConfig.channels.telegram.botToken = '[REDACTED]';
  }
  if (debugConfig.gateway?.auth?.token) {
    debugConfig.gateway.auth.token = '[REDACTED]';
  }
  console.log('[build-config] Full config:', JSON.stringify(debugConfig, null, 2));
}

main();
