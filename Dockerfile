FROM node:22-slim

# Install basic dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Clawdbot globally (as root, before user switch)
RUN npm install -g clawdbot@latest

# Create app user with sudo access for fixing volume permissions
RUN useradd -m -s /bin/bash clawdbot && \
    echo "clawdbot ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers.d/clawdbot

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to app user
USER clawdbot
WORKDIR /home/clawdbot

# Add .local/bin to PATH for claude and other user-installed binaries
ENV PATH="/home/clawdbot/.local/bin:${PATH}"

# Default port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# Use entrypoint to fix permissions then start gateway
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
