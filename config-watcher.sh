#!/bin/bash
# Config watcher - starts gateway when onboard creates config
# Uses file locking to prevent race conditions

CONFIG_FILE="/data/.openclaw/openclaw.json"
LOCK_FILE="/data/.openclaw/.watcher.lock"

# Acquire exclusive lock
exec 200>"$LOCK_FILE"
flock -x 200 || exit 1

# Wait for config file to be created by onboard
while [ ! -f "$CONFIG_FILE" ]; do
  sleep 2
done

# Validate it's a regular file (not symlink)
if [ -L "$CONFIG_FILE" ]; then
  echo "[watcher] ERROR: Config is a symlink, refusing to proceed" >&2
  exit 1
fi

# Secure permissions immediately
chmod 600 "$CONFIG_FILE"
chown openclaw:openclaw "$CONFIG_FILE"

# Start gateway
echo "[watcher] Config detected, starting gateway..."
su openclaw -c "cd /data/workspace && nohup openclaw gateway run \
  --port 18789 \
  > /data/.openclaw/gateway.log 2>&1 &"

echo "[watcher] Gateway started"
