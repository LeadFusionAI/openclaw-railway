# =============================================================================
# HARDENED OPENCLAW RAILWAY TEMPLATE
# Multi-stage build with non-root user, pnpm, and Claude CLI
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build OpenClaw from source
# -----------------------------------------------------------------------------
FROM node:22-bookworm AS openclaw-build

# Build dependencies
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known ref (tag/branch). Fall back to main if not specified.
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# -----------------------------------------------------------------------------
# Stage 2: Runtime image (hardened)
# -----------------------------------------------------------------------------
FROM oven/bun:1-debian AS runtime

ENV NODE_ENV=production

# Install runtime dependencies + tools for administration
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    vim-tiny \
    less \
    procps \
    htop \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for openclaw CLI) and pnpm (required for openclaw update)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y nodejs \
  && corepack enable && corepack prepare pnpm@latest --activate \
  && rm -rf /var/lib/apt/lists/*

# Install Tailscale for secure remote access to gateway
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create non-root user with specific UID for security
# Using uid 1001 to avoid conflicts with common system users
RUN groupadd -g 1001 openclaw \
  && useradd -u 1001 -g openclaw -m -s /bin/bash openclaw

# Create data directory structure
RUN mkdir -p /data/.openclaw /data/workspace /data/core \
  && chown -R openclaw:openclaw /data

# Copy built openclaw from build stage
COPY --from=openclaw-build /openclaw /openclaw
RUN chown -R openclaw:openclaw /openclaw

# Create openclaw CLI wrapper that always runs as the openclaw user
# This prevents permission issues when root (SSH) runs openclaw commands
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$(id -u)" = "0" ]; then' \
  '  exec su openclaw -c "node /openclaw/dist/entry.js $*"' \
  'else' \
  '  exec node /openclaw/dist/entry.js "$@"' \
  'fi' \
  > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

# Note: Claude Code CLI can be installed manually via SSH if needed:
#   npm install -g @anthropic-ai/claude-code && claude setup-token

# Set up wrapper application
WORKDIR /app

# Copy wrapper dependencies and install with bun
COPY package.json ./
RUN bun install --production

# Copy wrapper source
COPY src ./src

# Set ownership
RUN chown -R openclaw:openclaw /app

# Copy entrypoint script (runs as root to fix volume permissions, then drops to openclaw)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# NOTE: We do NOT use USER here because entrypoint needs root to fix volume permissions
# The entrypoint script drops privileges to openclaw user after setup

# Environment defaults
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CORE_DIR=/data/core
ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
ENV INTERNAL_GATEWAY_PORT=18789

# Add openclaw user's local bin to PATH (for claude CLI)
ENV PATH="/home/openclaw/.local/bin:/usr/local/bin:${PATH}"

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -sf http://localhost:8080/healthz || exit 1

EXPOSE 8080

# Start via entrypoint (fixes permissions, then drops to openclaw user)
ENTRYPOINT ["/entrypoint.sh"]
