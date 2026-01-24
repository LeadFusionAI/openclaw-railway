FROM node:22-slim

# Install basic dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Clawdbot globally (as root, before user switch)
RUN npm install -g clawdbot@latest

# Create app user
RUN useradd -m -s /bin/bash clawdbot

# Switch to app user
USER clawdbot
WORKDIR /home/clawdbot

# Create necessary directories
RUN mkdir -p .clawdbot clawd

# Default port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# Start the gateway
CMD ["clawdbot", "gateway", "--port", "18789", "--bind", "0.0.0.0"]
