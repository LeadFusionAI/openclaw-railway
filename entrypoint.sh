#!/bin/bash
# =============================================================================
# OpenClaw Railway Entrypoint
# Runs as root to fix volume permissions, starts gateway, then health server
# =============================================================================

set -e

echo "[entrypoint] Starting OpenClaw Railway..."

# -----------------------------------------------------------------------------
# 1. Create data directories with secure permissions
# -----------------------------------------------------------------------------
mkdir -p /data/.openclaw /data/workspace /data/core
chmod 700 /data/.openclaw
chown -R openclaw:openclaw /data

echo "[entrypoint] Data directories ready"

# -----------------------------------------------------------------------------
# 2. Start OpenClaw gateway (if configured)
# -----------------------------------------------------------------------------
CONFIG_FILE="/data/.openclaw/openclaw.json"

start_gateway() {
  echo "[entrypoint] Starting gateway..."

  # Ensure config has secure permissions
  chmod 600 "$CONFIG_FILE"
  chown openclaw:openclaw "$CONFIG_FILE"

  su openclaw -c "cd /data/workspace && nohup openclaw gateway run \
    --port 18789 \
    > /data/.openclaw/gateway.log 2>&1 &"

  sleep 2

  if pgrep -f "openclaw gateway" > /dev/null; then
    echo "[entrypoint] Gateway started"
  else
    echo "[entrypoint] WARNING: Gateway failed to start, check /data/.openclaw/gateway.log"
  fi
}

if [ -f "$CONFIG_FILE" ]; then
  start_gateway
else
  echo "[entrypoint] No config found - run 'openclaw onboard' via SSH"
  echo "[entrypoint] Starting config watcher..."
  nohup /app/config-watcher.sh > /dev/null 2>&1 &
  disown
fi

# -----------------------------------------------------------------------------
# 3. Start health check server (drops to openclaw user)
# -----------------------------------------------------------------------------
echo "[entrypoint] Starting health server..."
exec su openclaw -c "cd /app && bun run src/server.js"
