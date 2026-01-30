/**
 * Hardened OpenClaw Railway Wrapper Server
 *
 * Based on Vignesh's clawdbot-railway-template with key improvements:
 * - Token injection fix for /openclaw/* paths
 * - Rate limiting on /setup/* endpoints
 * - Security headers
 * - SETUP_PASSWORD validation on startup
 * - trustedProxies pre-configured for Railway
 */

import childProcess from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import express from "express";
import httpProxy from "http-proxy";
import * as tar from "tar";

import coreSync from "./core-sync.js";
import security from "./security.js";

// =============================================================================
// Configuration
// =============================================================================

const PORT = Number.parseInt(process.env.OPENCLAW_PUBLIC_PORT ?? process.env.PORT ?? "8080", 10);
const STATE_DIR = process.env.OPENCLAW_STATE_DIR?.trim() || path.join(os.homedir(), ".openclaw");
const WORKSPACE_DIR = process.env.OPENCLAW_WORKSPACE_DIR?.trim() || path.join(STATE_DIR, "workspace");
const CORE_DIR = process.env.OPENCLAW_CORE_DIR?.trim() || path.join("/data", "core");


// Security: Require SETUP_PASSWORD
const SETUP_PASSWORD = process.env.SETUP_PASSWORD?.trim();

// Rate limiting state for /setup/* endpoints
const rateLimitState = new Map();
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 30;

// =============================================================================
// Gateway Token Management
// =============================================================================

function resolveGatewayToken() {
  // 1. Environment variable takes priority
  const envTok = process.env.OPENCLAW_GATEWAY_TOKEN?.trim();
  if (envTok) return envTok;

  // 2. Read from OpenClaw's config file if it exists (persists across redeploys)
  const cfgPath = process.env.OPENCLAW_CONFIG_PATH?.trim() || path.join(STATE_DIR, "openclaw.json");
  try {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
    const cfgToken = cfg?.gateway?.auth?.token?.trim();
    if (cfgToken) {
      console.log("[token] Using token from openclaw.json");
      return cfgToken;
    }
  } catch {
    // Config doesn't exist yet, that's fine
  }

  // 3. Read from our token file (legacy/backup)
  const tokenPath = path.join(STATE_DIR, "gateway.token");
  try {
    const existing = fs.readFileSync(tokenPath, "utf8").trim();
    if (existing) {
      console.log("[token] Using token from gateway.token file");
      return existing;
    }
  } catch {
    // ignore
  }

  // 4. Generate new token only if nothing else exists
  console.log("[token] Generating new gateway token");
  const generated = crypto.randomBytes(32).toString("hex");
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(tokenPath, generated, { encoding: "utf8", mode: 0o600 });
  } catch {
    // best-effort
  }
  return generated;
}

const OPENCLAW_GATEWAY_TOKEN = resolveGatewayToken();
process.env.OPENCLAW_GATEWAY_TOKEN = OPENCLAW_GATEWAY_TOKEN;

const INTERNAL_GATEWAY_PORT = Number.parseInt(process.env.INTERNAL_GATEWAY_PORT ?? "18789", 10);
const INTERNAL_GATEWAY_HOST = process.env.INTERNAL_GATEWAY_HOST ?? "127.0.0.1";
const GATEWAY_TARGET = `http://${INTERNAL_GATEWAY_HOST}:${INTERNAL_GATEWAY_PORT}`;

// OpenClaw CLI entry point
const OPENCLAW_ENTRY = process.env.OPENCLAW_ENTRY?.trim() || "/openclaw/dist/entry.js";
const OPENCLAW_NODE = process.env.OPENCLAW_NODE?.trim() || "node";

function openclawArgs(args) {
  return [OPENCLAW_ENTRY, ...args];
}

function configPath() {
  return process.env.OPENCLAW_CONFIG_PATH?.trim() || path.join(STATE_DIR, "openclaw.json");
}

function isConfigured() {
  try {
    return fs.existsSync(configPath());
  } catch {
    return false;
  }
}

// =============================================================================
// Gateway Process Management
// =============================================================================

let gatewayProc = null;
let gatewayStarting = null;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitForGatewayReady(opts = {}) {
  const timeoutMs = opts.timeoutMs ?? 20_000;
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${GATEWAY_TARGET}/openclaw`, { method: "GET" });
      if (res) return true;
    } catch {
      // not ready
    }
    await sleep(250);
  }
  return false;
}

async function startGateway() {
  if (gatewayProc) return;
  if (!isConfigured()) throw new Error("Gateway cannot start: not configured");

  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.mkdirSync(WORKSPACE_DIR, { recursive: true });

  const args = [
    "gateway",
    "run",
    "--bind", "loopback",
    "--port", String(INTERNAL_GATEWAY_PORT),
    "--auth", "token",
    "--token", OPENCLAW_GATEWAY_TOKEN,
  ];

  gatewayProc = childProcess.spawn(OPENCLAW_NODE, openclawArgs(args), {
    stdio: "inherit",
    env: {
      ...process.env,
      OPENCLAW_STATE_DIR: STATE_DIR,
      OPENCLAW_WORKSPACE_DIR: WORKSPACE_DIR,
    },
  });

  gatewayProc.on("error", (err) => {
    console.error(`[gateway] spawn error: ${String(err)}`);
    gatewayProc = null;
  });

  gatewayProc.on("exit", (code, signal) => {
    console.error(`[gateway] exited code=${code} signal=${signal}`);
    gatewayProc = null;
  });
}

async function ensureGatewayRunning() {
  if (!isConfigured()) return { ok: false, reason: "not configured" };
  if (gatewayProc) return { ok: true };
  if (!gatewayStarting) {
    gatewayStarting = (async () => {
      await startGateway();
      const ready = await waitForGatewayReady({ timeoutMs: 20_000 });
      if (!ready) {
        throw new Error("Gateway did not become ready in time");
      }
    })().finally(() => {
      gatewayStarting = null;
    });
  }
  await gatewayStarting;
  return { ok: true };
}

async function restartGateway() {
  if (gatewayProc) {
    try {
      gatewayProc.kill("SIGTERM");
    } catch {
      // ignore
    }
    await sleep(750);
    gatewayProc = null;
  }
  return ensureGatewayRunning();
}

// =============================================================================
// Security Middleware
// =============================================================================

function securityHeaders(req, res, next) {
  // Security headers
  res.set("X-Content-Type-Options", "nosniff");
  res.set("X-Frame-Options", "DENY");
  res.set("X-XSS-Protection", "1; mode=block");
  res.set("Referrer-Policy", "strict-origin-when-cross-origin");

  // Remove powered-by header
  res.removeHeader("X-Powered-By");

  next();
}

function rateLimit(req, res, next) {
  const ip = req.ip || req.socket.remoteAddress || "unknown";
  const now = Date.now();

  // Clean old entries
  for (const [key, data] of rateLimitState.entries()) {
    if (now - data.windowStart > RATE_LIMIT_WINDOW_MS) {
      rateLimitState.delete(key);
    }
  }

  let state = rateLimitState.get(ip);
  if (!state || now - state.windowStart > RATE_LIMIT_WINDOW_MS) {
    state = { windowStart: now, count: 0 };
    rateLimitState.set(ip, state);
  }

  state.count++;

  if (state.count > RATE_LIMIT_MAX_REQUESTS) {
    return res.status(429).json({
      error: "Too many requests",
      retryAfter: Math.ceil((state.windowStart + RATE_LIMIT_WINDOW_MS - now) / 1000),
    });
  }

  next();
}

function requireSetupAuth(req, res, next) {
  if (!SETUP_PASSWORD) {
    return res
      .status(500)
      .type("text/plain")
      .send("SETUP_PASSWORD is not set. Set it in Railway Variables before using /setup.");
  }

  const header = req.headers.authorization || "";
  const [scheme, encoded] = header.split(" ");
  if (scheme !== "Basic" || !encoded) {
    res.set("WWW-Authenticate", 'Basic realm="OpenClaw Setup"');
    security.auditAuth(false, { reason: "no_credentials", ip: req.ip, path: req.path });
    return res.status(401).send("Auth required");
  }
  const decoded = Buffer.from(encoded, "base64").toString("utf8");
  const idx = decoded.indexOf(":");
  const password = idx >= 0 ? decoded.slice(idx + 1) : "";
  if (password !== SETUP_PASSWORD) {
    res.set("WWW-Authenticate", 'Basic realm="OpenClaw Setup"');
    security.auditAuth(false, { reason: "invalid_password", ip: req.ip, path: req.path });
    return res.status(401).send("Invalid password");
  }
  security.auditAuth(true, { ip: req.ip, path: req.path });
  return next();
}

// =============================================================================
// Token Injection Middleware (FIXES THE BUG)
// =============================================================================

/**
 * Injects the gateway token into /openclaw/* requests that don't have one.
 * This fixes the token injection bug where the Control UI links don't work.
 */
function injectToken(req, res, next) {
  // Only apply to /openclaw paths
  if (!req.path.startsWith("/openclaw")) {
    return next();
  }

  // If token already present in query, pass through
  if (req.query.token) {
    return next();
  }

  // For HTML requests (browser navigation), redirect with token
  const acceptHeader = req.get("Accept") || "";
  if (acceptHeader.includes("text/html") && req.method === "GET") {
    const separator = req.url.includes("?") ? "&" : "?";
    const newUrl = `${req.url}${separator}token=${OPENCLAW_GATEWAY_TOKEN}`;
    return res.redirect(302, newUrl);
  }

  // For API requests, add token to query
  req.query.token = OPENCLAW_GATEWAY_TOKEN;
  next();
}

// =============================================================================
// Express App
// =============================================================================

const app = express();
app.disable("x-powered-by");
app.set("trust proxy", true); // Trust Railway's proxy

// Global middleware
app.use(securityHeaders);
app.use(express.json({ limit: "1mb" }));

// Health endpoint (no auth required)
app.get("/setup/healthz", (_req, res) => res.json({ ok: true, timestamp: new Date().toISOString() }));

// Rate limit on /setup/* routes
app.use("/setup", rateLimit);

// =============================================================================
// Setup UI Routes
// =============================================================================

app.get("/setup/app.js", requireSetupAuth, (_req, res) => {
  res.type("application/javascript");
  res.send(fs.readFileSync(path.join(process.cwd(), "src", "setup-app.js"), "utf8"));
});

app.get("/setup", requireSetupAuth, (_req, res) => {
  res.type("html").send(`<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>OpenClaw Setup</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; margin: 2rem; max-width: 900px; background: #0a0a0a; color: #e5e5e5; }
    .card { border: 1px solid #333; border-radius: 12px; padding: 1.25rem; margin: 1rem 0; background: #141414; }
    label { display:block; margin-top: 0.75rem; font-weight: 600; color: #a5a5a5; }
    input, select { width: 100%; padding: 0.6rem; margin-top: 0.25rem; background: #1a1a1a; border: 1px solid #333; color: #e5e5e5; border-radius: 6px; }
    button { padding: 0.8rem 1.2rem; border-radius: 10px; border: 0; background: #2563eb; color: #fff; font-weight: 700; cursor: pointer; }
    button:hover { background: #1d4ed8; }
    code { background: #1f1f1f; padding: 0.1rem 0.3rem; border-radius: 6px; color: #10b981; }
    a { color: #60a5fa; }
    .muted { color: #666; }
    .warning { background: #451a03; border: 1px solid #92400e; padding: 1rem; border-radius: 8px; margin: 1rem 0; }
    h1 { color: #f97316; }
    h2 { color: #e5e5e5; margin-bottom: 0.5rem; }
  </style>
</head>
<body>
  <h1>OpenClaw Setup</h1>
  <p class="muted">Hardened OpenClaw deployment with security-first defaults.</p>

  <div class="card warning">
    <strong>Security Notice:</strong> This instance runs with hardened defaults.
    Command execution is disabled. Configure the trust ladder carefully.
  </div>

  <div class="card">
    <h2>Status</h2>
    <div id="status">Loading...</div>
    <div style="margin-top: 0.75rem">
      <a href="/openclaw" target="_blank">Open OpenClaw UI</a>
      &nbsp;|&nbsp;
      <a href="/setup/export" target="_blank">Download backup (.tar.gz)</a>
    </div>
  </div>

  <div class="card">
    <h2>1) Model/auth provider</h2>
    <p class="muted">Select your LLM provider and authentication method.</p>
    <label>Provider group</label>
    <select id="authGroup"></select>

    <label>Auth method</label>
    <select id="authChoice"></select>

    <label>Key / Token (if required)</label>
    <input id="authSecret" type="password" placeholder="Paste API key / token if applicable" />

    <label>Wizard flow</label>
    <select id="flow">
      <option value="quickstart">quickstart</option>
      <option value="advanced">advanced</option>
      <option value="manual">manual</option>
    </select>
  </div>

  <div class="card">
    <h2>2) Optional: Channels</h2>
    <p class="muted">Add messaging channels. You can also add these later in the OpenClaw UI.</p>

    <label>Telegram bot token (optional)</label>
    <input id="telegramToken" type="password" placeholder="123456:ABC..." />
    <div class="muted" style="margin-top: 0.25rem">
      Get from BotFather: message <code>@BotFather</code> on Telegram, run <code>/newbot</code>.
    </div>

    <label>Discord bot token (optional)</label>
    <input id="discordToken" type="password" placeholder="Bot token" />
    <div class="muted" style="margin-top: 0.25rem">
      Enable <strong>MESSAGE CONTENT INTENT</strong> in Bot settings or the bot will crash.
    </div>

    <label>Slack bot token (optional)</label>
    <input id="slackBotToken" type="password" placeholder="xoxb-..." />

    <label>Slack app token (optional)</label>
    <input id="slackAppToken" type="password" placeholder="xapp-..." />
  </div>

  <div class="card">
    <h2>3) Run onboarding</h2>
    <button id="run">Run setup</button>
    <button id="pairingApprove" style="background:#374151; margin-left:0.5rem">Approve pairing</button>
    <button id="gatewayRestart" style="background:#374151; margin-left:0.5rem">Restart gateway</button>
    <button id="reset" style="background:#7f1d1d; margin-left:0.5rem">Reset setup</button>
    <pre id="log" style="white-space:pre-wrap; background: #0a0a0a; padding: 1rem; border-radius: 8px; margin-top: 1rem; max-height: 400px; overflow-y: auto;"></pre>
  </div>

  <div class="card">
    <h2>4) Core Sync (Optional)</h2>
    <p class="muted">Sync your Obsidian vault (The Core) via Git. Requires environment variables: <code>GITHUB_TOKEN</code>, <code>CORE_REPO</code></p>
    <div id="coreStatus" style="margin: 0.75rem 0; padding: 0.5rem; background: #1a1a1a; border-radius: 6px;">Loading...</div>
    <button id="coreInit" style="background:#059669;">Initialize Core</button>
    <button id="coreSync" style="background:#374151; margin-left:0.5rem">Sync Now</button>
    <div id="coreCommits" style="margin-top: 0.75rem;"></div>
  </div>

  <script src="/setup/app.js"></script>
</body>
</html>`);
});

// =============================================================================
// Setup API Routes
// =============================================================================

function runCmd(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const proc = childProcess.spawn(cmd, args, {
      ...opts,
      env: {
        ...process.env,
        OPENCLAW_STATE_DIR: STATE_DIR,
        OPENCLAW_WORKSPACE_DIR: WORKSPACE_DIR,
      },
    });

    let out = "";
    proc.stdout?.on("data", (d) => (out += d.toString("utf8")));
    proc.stderr?.on("data", (d) => (out += d.toString("utf8")));

    proc.on("error", (err) => {
      out += `\n[spawn error] ${String(err)}\n`;
      resolve({ code: 127, output: out });
    });

    proc.on("close", (code) => resolve({ code: code ?? 0, output: out }));
  });
}

app.get("/setup/api/status", requireSetupAuth, async (_req, res) => {
  const version = await runCmd(OPENCLAW_NODE, openclawArgs(["--version"]));
  const channelsHelp = await runCmd(OPENCLAW_NODE, openclawArgs(["channels", "add", "--help"]));

  const authGroups = [
    { value: "anthropic", label: "Anthropic", hint: "Claude Code CLI + API key", options: [
      { value: "claude-cli", label: "Anthropic token (Claude Code CLI)" },
      { value: "token", label: "Anthropic token (paste setup-token)" },
      { value: "apiKey", label: "Anthropic API key" }
    ]},
    { value: "openai", label: "OpenAI", hint: "Codex OAuth + API key", options: [
      { value: "codex-cli", label: "OpenAI Codex OAuth (Codex CLI)" },
      { value: "openai-codex", label: "OpenAI Codex (ChatGPT OAuth)" },
      { value: "openai-api-key", label: "OpenAI API key" }
    ]},
    { value: "google", label: "Google", hint: "Gemini API key + OAuth", options: [
      { value: "gemini-api-key", label: "Google Gemini API key" },
      { value: "google-antigravity", label: "Google Antigravity OAuth" },
      { value: "google-gemini-cli", label: "Google Gemini CLI OAuth" }
    ]},
    { value: "openrouter", label: "OpenRouter", hint: "API key", options: [
      { value: "openrouter-api-key", label: "OpenRouter API key" }
    ]},
    { value: "ai-gateway", label: "Vercel AI Gateway", hint: "API key", options: [
      { value: "ai-gateway-api-key", label: "Vercel AI Gateway API key" }
    ]},
    { value: "moonshot", label: "Moonshot AI", hint: "Kimi K2 + Kimi Code", options: [
      { value: "moonshot-api-key", label: "Moonshot AI API key" },
      { value: "kimi-code-api-key", label: "Kimi Code API key" }
    ]},
    { value: "synthetic", label: "Synthetic", hint: "Anthropic-compatible (multi-model)", options: [
      { value: "synthetic-api-key", label: "Synthetic API key" }
    ]},
  ];

  res.json({
    configured: isConfigured(),
    gatewayTarget: GATEWAY_TARGET,
    openclawVersion: version.output.trim(),
    channelsAddHelp: channelsHelp.output,
    authGroups,
    security: {
      setupPasswordSet: Boolean(SETUP_PASSWORD),
      gatewayTokenSet: Boolean(OPENCLAW_GATEWAY_TOKEN),
      nonRootUser: process.getuid?.() !== 0,
    },
    coreSync: coreSync.getStatus(),
  });
});

function buildOnboardArgs(payload) {
  const args = [
    "onboard",
    "--non-interactive",
    "--accept-risk",
    "--json",
    "--no-install-daemon",
    "--skip-health",
    "--workspace", WORKSPACE_DIR,
    "--gateway-bind", "loopback",
    "--gateway-port", String(INTERNAL_GATEWAY_PORT),
    "--gateway-auth", "token",
    "--gateway-token", OPENCLAW_GATEWAY_TOKEN,
    "--flow", payload.flow || "quickstart"
  ];

  if (payload.authChoice) {
    args.push("--auth-choice", payload.authChoice);

    const secret = (payload.authSecret || "").trim();
    const map = {
      "openai-api-key": "--openai-api-key",
      "apiKey": "--anthropic-api-key",
      "openrouter-api-key": "--openrouter-api-key",
      "ai-gateway-api-key": "--ai-gateway-api-key",
      "moonshot-api-key": "--moonshot-api-key",
      "kimi-code-api-key": "--kimi-code-api-key",
      "gemini-api-key": "--gemini-api-key",
      "synthetic-api-key": "--synthetic-api-key",
    };
    const flag = map[payload.authChoice];
    if (flag && secret) {
      args.push(flag, secret);
    }

    if (payload.authChoice === "token" && secret) {
      args.push("--token-provider", "anthropic", "--token", secret);
    }
  }

  return args;
}

app.post("/setup/api/run", requireSetupAuth, async (req, res) => {
  try {
    if (isConfigured()) {
      await ensureGatewayRunning();
      return res.json({ ok: true, output: "Already configured.\nUse Reset setup if you want to rerun onboarding.\n" });
    }

    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.mkdirSync(WORKSPACE_DIR, { recursive: true });

    const payload = req.body || {};
    const onboardArgs = buildOnboardArgs(payload);
    const onboard = await runCmd(OPENCLAW_NODE, openclawArgs(onboardArgs));

    let extra = "";
    const ok = onboard.code === 0 && isConfigured();

    if (ok) {
      // Apply hardened gateway defaults from config file
      try {
        const defaultsPath = path.join(process.cwd(), "config", "gateway-defaults.json");
        const defaults = JSON.parse(fs.readFileSync(defaultsPath, "utf8"));

        // Apply security defaults
        if (defaults.nodes?.run) {
          await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "nodes.run.enabled", String(defaults.nodes.run.enabled)]));
          if (defaults.nodes.run.denylist) {
            await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "nodes.run.denylist", JSON.stringify(defaults.nodes.run.denylist)]));
          }
        }

        if (defaults.security?.auditLog) {
          await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "security.auditLog", JSON.stringify(defaults.security.auditLog)]));
        }

        if (defaults.security?.cogSec) {
          await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "security.cogSec", JSON.stringify(defaults.security.cogSec)]));
        }

        extra += "\n[security] Applied hardened defaults from gateway-defaults.json\n";
        security.auditLog({ type: "config_init", severity: "info", message: "Applied hardened gateway defaults" });
      } catch (err) {
        extra += `\n[security] Warning: Could not load gateway-defaults.json: ${err.message}\n`;
      }

      // Set core gateway configuration
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "gateway.auth.mode", "token"]));
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "gateway.auth.token", OPENCLAW_GATEWAY_TOKEN]));
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "gateway.bind", "loopback"]));
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "gateway.port", String(INTERNAL_GATEWAY_PORT)]));

      // SECURITY: Disable command execution by default (redundant but explicit)
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "nodes.run.enabled", "false"]));

      // SECURITY: Set trustedProxies for Railway
      await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "gateway.trustedProxies", '["127.0.0.1", "::1"]']));

      const channelsHelp = await runCmd(OPENCLAW_NODE, openclawArgs(["channels", "add", "--help"]));
      const helpText = channelsHelp.output || "";
      const supports = (name) => helpText.includes(name);

      // Configure channels if provided
      if (payload.telegramToken?.trim()) {
        if (!supports("telegram")) {
          extra += "\n[telegram] skipped (not supported in this build)\n";
        } else {
          const token = payload.telegramToken.trim();
          const cfgObj = {
            enabled: true,
            dmPolicy: "pairing",
            botToken: token,
            groupPolicy: "allowlist",
            streamMode: "partial",
          };
          const set = await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "channels.telegram", JSON.stringify(cfgObj)]));
          extra += `\n[telegram] configured (exit=${set.code})\n`;
        }
      }

      if (payload.discordToken?.trim()) {
        if (!supports("discord")) {
          extra += "\n[discord] skipped (not supported in this build)\n";
        } else {
          const token = payload.discordToken.trim();
          const cfgObj = {
            enabled: true,
            token,
            groupPolicy: "allowlist",
            dm: { policy: "pairing" },
          };
          const set = await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "channels.discord", JSON.stringify(cfgObj)]));
          extra += `\n[discord] configured (exit=${set.code})\n`;
        }
      }

      if (payload.slackBotToken?.trim() || payload.slackAppToken?.trim()) {
        if (!supports("slack")) {
          extra += "\n[slack] skipped (not supported in this build)\n";
        } else {
          const cfgObj = {
            enabled: true,
            botToken: payload.slackBotToken?.trim() || undefined,
            appToken: payload.slackAppToken?.trim() || undefined,
          };
          const set = await runCmd(OPENCLAW_NODE, openclawArgs(["config", "set", "--json", "channels.slack", JSON.stringify(cfgObj)]));
          extra += `\n[slack] configured (exit=${set.code})\n`;
        }
      }

      await restartGateway();
    }

    return res.status(ok ? 200 : 500).json({
      ok,
      output: `${onboard.output}${extra}`,
    });
  } catch (err) {
    console.error("[/setup/api/run] error:", err);
    return res.status(500).json({ ok: false, output: `Internal error: ${String(err)}` });
  }
});

app.get("/setup/api/debug", requireSetupAuth, async (_req, res) => {
  const v = await runCmd(OPENCLAW_NODE, openclawArgs(["--version"]));
  const help = await runCmd(OPENCLAW_NODE, openclawArgs(["channels", "add", "--help"]));
  res.json({
    wrapper: {
      node: process.version,
      port: PORT,
      stateDir: STATE_DIR,
      workspaceDir: WORKSPACE_DIR,
      coreDir: CORE_DIR,
      configPath: configPath(),
      gatewayTokenSet: Boolean(OPENCLAW_GATEWAY_TOKEN),
      setupPasswordSet: Boolean(SETUP_PASSWORD),
      nonRootUser: process.getuid?.() !== 0,
      uid: process.getuid?.(),
    },
    openclaw: {
      entry: OPENCLAW_ENTRY,
      node: OPENCLAW_NODE,
      version: v.output.trim(),
      channelsAddHelpIncludesTelegram: help.output.includes("telegram"),
    },
  });
});

app.post("/setup/api/pairing/approve", requireSetupAuth, async (req, res) => {
  const { channel, code } = req.body || {};
  if (!channel || !code) {
    return res.status(400).json({ ok: false, error: "Missing channel or code" });
  }
  const r = await runCmd(OPENCLAW_NODE, openclawArgs(["pairing", "approve", String(channel), String(code)]));
  return res.status(r.code === 0 ? 200 : 500).json({ ok: r.code === 0, output: r.output });
});

app.post("/setup/api/reset", requireSetupAuth, async (_req, res) => {
  try {
    fs.rmSync(configPath(), { force: true });
    res.type("text/plain").send("OK - deleted config file. You can rerun setup now.");
  } catch (err) {
    res.status(500).type("text/plain").send(String(err));
  }
});

app.post("/setup/api/gateway/restart", requireSetupAuth, async (_req, res) => {
  try {
    if (!isConfigured()) {
      return res.status(400).json({ ok: false, error: "Not configured yet" });
    }
    await restartGateway();
    res.json({ ok: true, message: "Gateway restarted" });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.get("/setup/api/gateway/status", requireSetupAuth, async (_req, res) => {
  const running = gatewayProc !== null;
  const configured = isConfigured();
  res.json({
    configured,
    running,
    target: GATEWAY_TARGET,
    pid: gatewayProc?.pid || null,
  });
});

app.get("/setup/export", requireSetupAuth, async (_req, res) => {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.mkdirSync(WORKSPACE_DIR, { recursive: true });

  res.setHeader("content-type", "application/gzip");
  res.setHeader(
    "content-disposition",
    `attachment; filename="openclaw-backup-${new Date().toISOString().replace(/[:.]/g, "-")}.tar.gz"`,
  );

  const stateAbs = path.resolve(STATE_DIR);
  const workspaceAbs = path.resolve(WORKSPACE_DIR);

  const dataRoot = "/data";
  const underData = (p) => p === dataRoot || p.startsWith(dataRoot + path.sep);

  let cwd = "/";
  let paths = [stateAbs, workspaceAbs].map((p) => p.replace(/^\//, ""));

  if (underData(stateAbs) && underData(workspaceAbs)) {
    cwd = dataRoot;
    paths = [
      path.relative(dataRoot, stateAbs) || ".",
      path.relative(dataRoot, workspaceAbs) || ".",
    ];
  }

  const stream = tar.c(
    {
      gzip: true,
      portable: true,
      noMtime: true,
      cwd,
      onwarn: () => {},
    },
    paths,
  );

  stream.on("error", (err) => {
    console.error("[export]", err);
    if (!res.headersSent) res.status(500);
    res.end(String(err));
  });

  stream.pipe(res);
});

// =============================================================================
// Core Sync API Routes
// =============================================================================

app.get("/setup/api/core/status", requireSetupAuth, async (_req, res) => {
  try {
    const status = coreSync.getStatus();
    if (status.initialized) {
      const commits = await coreSync.getRecentCommits(5);
      res.json({ ...status, recentCommits: commits });
    } else {
      res.json(status);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/setup/api/core/init", requireSetupAuth, async (_req, res) => {
  try {
    const result = await coreSync.initializeCore();
    // Start background sync after initialization
    coreSync.startSyncInterval();
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/setup/api/core/sync", requireSetupAuth, async (_req, res) => {
  try {
    const result = await coreSync.syncCore();
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post("/setup/api/core/commit", requireSetupAuth, async (req, res) => {
  try {
    const { message, files } = req.body || {};
    if (!message) {
      return res.status(400).json({ success: false, error: "Message required" });
    }
    const result = await coreSync.commitChanges(message, files || []);
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// =============================================================================
// Security API Routes
// =============================================================================

app.get("/setup/api/security/audit", requireSetupAuth, async (_req, res) => {
  const auditLogPath = path.join(STATE_DIR, "audit.log");

  try {
    if (!fs.existsSync(auditLogPath)) {
      return res.json({ entries: [], message: "No audit log yet" });
    }

    const content = fs.readFileSync(auditLogPath, "utf8");
    const lines = content.trim().split("\n").filter(Boolean);
    const entries = lines.slice(-100).map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return { raw: line };
      }
    });

    res.json({ entries: entries.reverse() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/setup/api/security/analyze", requireSetupAuth, async (req, res) => {
  const { text } = req.body || {};
  if (!text) {
    return res.status(400).json({ error: "Text required" });
  }

  const result = security.analyzeCogSec(text, { source: "manual_analysis" });
  res.json(result);
});

// =============================================================================
// Proxy to Gateway
// =============================================================================

const proxy = httpProxy.createProxyServer({
  target: GATEWAY_TARGET,
  ws: true,
  xfwd: true,
});

proxy.on("error", (err, _req, _res) => {
  console.error("[proxy]", err);
});

// Token injection for /openclaw/* paths
app.use(injectToken);

// Catch-all route
app.use(async (req, res) => {
  if (!isConfigured() && !req.path.startsWith("/setup")) {
    return res.redirect("/setup");
  }

  if (isConfigured()) {
    try {
      await ensureGatewayRunning();
    } catch (err) {
      return res.status(503).type("text/plain").send(`Gateway not ready: ${String(err)}`);
    }
  }

  return proxy.web(req, res, { target: GATEWAY_TARGET });
});

// =============================================================================
// Server Startup
// =============================================================================

// Validate SETUP_PASSWORD on startup
if (!SETUP_PASSWORD) {
  console.error("[SECURITY] SETUP_PASSWORD is not set!");
  console.error("[SECURITY] Set SETUP_PASSWORD in Railway Variables before deploying.");
  console.error("[SECURITY] The /setup endpoint will return 500 until this is fixed.");
}

if (SETUP_PASSWORD && SETUP_PASSWORD.length < 16) {
  console.warn("[SECURITY] SETUP_PASSWORD is less than 16 characters. Consider using a stronger password.");
}

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`[wrapper] OpenClaw Hardened Template`);
  console.log(`[wrapper] Listening on :${PORT}`);
  console.log(`[wrapper] State dir: ${STATE_DIR}`);
  console.log(`[wrapper] Workspace dir: ${WORKSPACE_DIR}`);
  console.log(`[wrapper] Core dir: ${CORE_DIR}`);
  console.log(`[wrapper] Gateway target: ${GATEWAY_TARGET}`);
  console.log(`[wrapper] Gateway token: ${OPENCLAW_GATEWAY_TOKEN ? "(set)" : "(missing)"}`);
  console.log(`[wrapper] Setup password: ${SETUP_PASSWORD ? "(set)" : "(MISSING - SECURITY ISSUE)"}`);
  console.log(`[wrapper] Running as UID: ${process.getuid?.() ?? "unknown"}`);

  // Start Core sync if already initialized
  if (coreSync.isInitialized()) {
    console.log(`[wrapper] Core sync initialized, starting background sync...`);
    coreSync.startSyncInterval();
  } else {
    console.log(`[wrapper] Core sync not initialized (configure CORE_REPO and GITHUB_TOKEN)`);
  }
});

server.on("upgrade", async (req, socket, head) => {
  if (!isConfigured()) {
    socket.destroy();
    return;
  }
  try {
    await ensureGatewayRunning();
  } catch {
    socket.destroy();
    return;
  }
  proxy.ws(req, socket, head, { target: GATEWAY_TARGET });
});

process.on("SIGTERM", () => {
  console.log("[wrapper] SIGTERM received, shutting down...");
  coreSync.stopSyncInterval();
  try {
    if (gatewayProc) gatewayProc.kill("SIGTERM");
  } catch {
    // ignore
  }
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log("[wrapper] SIGINT received, shutting down...");
  coreSync.stopSyncInterval();
  try {
    if (gatewayProc) gatewayProc.kill("SIGTERM");
  } catch {
    // ignore
  }
  process.exit(0);
});
