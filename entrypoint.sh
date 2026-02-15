#!/bin/bash
# =============================================================================
# OpenClaw Railway Entrypoint
# Builds config from env vars, starts gateway, then health server
# =============================================================================

set -e

echo "[entrypoint] Starting OpenClaw Railway..."

# -----------------------------------------------------------------------------
# 1. Create data directories with secure permissions
# -----------------------------------------------------------------------------
mkdir -p /data/.openclaw /data/workspace
chmod 700 /data/.openclaw
chown -R openclaw:openclaw /data

echo "[entrypoint] Data directories ready"

# -----------------------------------------------------------------------------
# 2. Copy workspace templates (only files that don't already exist)
# -----------------------------------------------------------------------------
if [ -d "/app/workspace-templates" ]; then
  for tmpl in /app/workspace-templates/*; do
    basename="$(basename "$tmpl")"
    if [ ! -e "/data/workspace/$basename" ]; then
      echo "[entrypoint] Copying template: $basename"
      cp -r "$tmpl" "/data/workspace/$basename"
      chown -R openclaw:openclaw "/data/workspace/$basename"
    fi
  done
fi

# Copy docs to workspace for agent discovery
if [ -d "/app/docs" ] && [ ! -d "/data/workspace/docs" ]; then
  echo "[entrypoint] Copying documentation to workspace..."
  cp -r /app/docs /data/workspace/
  chown -R openclaw:openclaw /data/workspace/docs
fi

# -----------------------------------------------------------------------------
# 3. Deploy exec-approvals (allowlist for Tier 0 — ls only)
#    Note: exec-approvals.json lives at ~/.openclaw/ (user home), NOT $OPENCLAW_STATE_DIR
# -----------------------------------------------------------------------------
APPROVALS_SRC="/app/config/exec-approvals.json"
APPROVALS_HOME="/home/openclaw/.openclaw/exec-approvals.json"

if [ -f "$APPROVALS_SRC" ]; then
  echo "[entrypoint] Deploying exec-approvals..."
  mkdir -p /home/openclaw/.openclaw
  cp "$APPROVALS_SRC" "$APPROVALS_HOME"
  chmod 600 "$APPROVALS_HOME"
  chown -R openclaw:openclaw /home/openclaw/.openclaw
fi

# -----------------------------------------------------------------------------
# 4. Build config from environment variables (always regenerate)
# -----------------------------------------------------------------------------
CONFIG_FILE="/data/.openclaw/openclaw.json"

# Always regenerate config from env vars to pick up changes
echo "[entrypoint] Building config from environment variables..."
node /app/src/build-config.js

# -----------------------------------------------------------------------------
# 5. Start OpenClaw gateway (if configured)
# -----------------------------------------------------------------------------
start_gateway() {
  echo "[entrypoint] Starting gateway..."

  # Ensure config has secure permissions
  chmod 600 "$CONFIG_FILE"
  chown openclaw:openclaw "$CONFIG_FILE"

  # Start gateway in background, streaming logs to stdout/stderr
  su openclaw -c "cd /data/workspace && openclaw gateway run --port 18789 2>&1 | while read line; do echo \"[gateway] \$line\"; done" &
  GATEWAY_PID=$!

  sleep 3

  if kill -0 $GATEWAY_PID 2>/dev/null; then
    echo "[entrypoint] Gateway running (PID: $GATEWAY_PID)"
  else
    echo "[entrypoint] ERROR: Gateway exited immediately"
    exit 1
  fi
}

if [ -f "$CONFIG_FILE" ]; then
  start_gateway
else
  echo "[entrypoint] No config generated (missing required env vars)"
  echo "[entrypoint] Set LLM provider key + channel token, then redeploy"
  echo "[entrypoint] Or SSH in and run: openclaw onboard"

  # Start config watcher as fallback for manual onboard
  nohup /app/config-watcher.sh > /dev/null 2>&1 &
  disown
fi

# -----------------------------------------------------------------------------
# 6. Start health check server (drops to openclaw user)
# -----------------------------------------------------------------------------
echo "[entrypoint] Starting health server..."
exec su openclaw -c "cd /app && node src/server.js"
