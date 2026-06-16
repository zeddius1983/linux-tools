FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code via the official native-binary install script.
# Run with an overridden HOME so the installer's $HOME/.local/bin/claude symlink
# lands in a build-time directory, then dereference it into /usr/bin/ (a path
# Distrobox's home-overlay does not hide at runtime).
RUN mkdir -p /opt/claude-install \
    && HOME=/opt/claude-install bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    && cp -L /opt/claude-install/.local/bin/claude /usr/bin/claude \
    && chmod +x /usr/bin/claude \
    && rm -rf /opt/claude-install
