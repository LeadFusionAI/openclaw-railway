#!/bin/bash
set -e

# Fix ownership of home directory (volume mounts as root on first deploy)
if [ ! -w "$HOME" ]; then
    echo "Fixing permissions on $HOME..."
    sudo chown -R clawdbot:clawdbot "$HOME"
fi

# Ensure directories exist
mkdir -p "$HOME/.clawdbot" "$HOME/clawd" "$HOME/.local/bin"

# Clean up stale lock files from previous runs (container restarts leave these behind)
echo "Cleaning up stale lock files..."
rm -f "$HOME/.clawdbot/"*.lock "$HOME/.clawdbot/gateway.pid" 2>/dev/null || true
rm -f /tmp/clawdbot*.lock 2>/dev/null || true

# Start clawdbot gateway
exec clawdbot gateway --port 18789 --bind lan --allow-unconfigured
