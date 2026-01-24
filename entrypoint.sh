#!/bin/bash
set -e

# Fix ownership of home directory (volume mounts as root on first deploy)
if [ ! -w "$HOME" ]; then
    echo "Fixing permissions on $HOME..."
    sudo chown -R clawdbot:clawdbot "$HOME"
fi

# Ensure directories exist
mkdir -p "$HOME/.clawdbot" "$HOME/clawd" "$HOME/.local/bin"

# Start clawdbot gateway
exec clawdbot gateway --port 18789 --bind lan --allow-unconfigured
