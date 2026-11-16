FROM node:26-slim

# Install OpenClaw (AI gateway for chat apps), curl for healthchecks,
# git/openssh for the agent's repository work.
# ca-certificates provides the system root CA bundle (/etc/ssl/certs)
# so git/curl can verify TLS server certificates.
# openssl is used by entrypoint.sh to generate a random Gateway token
# when OPENCLAW_GATEWAY_TOKEN is left empty.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client openssl && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g openclaw

# Create a non-root user for security with non-standard UID/GID
# (same UID/GID 1050 as the opencode-web deployment so the same
# host user works for both containers)
RUN groupadd -g 1050 agent && useradd -u 1050 -g agent -m -s /bin/bash agent

# Environment variables
ENV HOME=/home/agent
ENV XDG_CONFIG_HOME=/home/agent/.config
ENV XDG_DATA_HOME=/home/agent/.local/share
ENV XDG_CACHE_HOME=/home/agent/.cache

# Create necessary directories and set permissions
# /home/agent/.openclaw (Gateway state: config, sessions, SQLite)
# and /workspace (agent working directory) must exist in the image so
# that the openclaw-state and openclaw-workspace named volumes are
# initialized with the agent's ownership
# (Docker creates missing volume mount points as root)
RUN mkdir -p /home/agent/.openclaw /home/agent/.ssh /workspace && \
    chown -R agent:agent /home/agent /workspace

# Copy and setup entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to the non-root user
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Exec form: no shell, no env interpolation. The container always listens on
# 18789; the host-side port is configured via the ports mapping in
# docker-compose.yaml (OPENCLAW_PORT). The entrypoint generates
# ~/.openclaw/openclaw.json from the environment before starting.
CMD ["openclaw", "gateway"]

# Expose the fixed internal port (host mapping is set in docker-compose)
EXPOSE 18789
