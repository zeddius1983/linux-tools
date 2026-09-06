FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bubblewrap \
    git \
    python3 \
    python3-tomlkit \
    jq \
    tmux \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Codex release selected by wizard/00-release.buildarg. "latest" follows the
# standalone installer's stable channel for non-interactive builds too.
# CACHE_BUST is fresh on every `tools build/setup`, so the network install is
# never satisfied by a stale container-build layer.
ARG CACHE_BUST=0
ARG CODEX_RELEASE=latest
RUN echo "==> Installing Codex ${CODEX_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && mkdir -p /opt/codex-install \
    && curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/codex-install.sh \
    && HOME=/opt/codex-install CODEX_HOME=/opt/codex \
       CODEX_INSTALL_DIR=/usr/bin CODEX_RELEASE="${CODEX_RELEASE}" \
       CODEX_NON_INTERACTIVE=true sh /tmp/codex-install.sh \
    && /usr/bin/codex --version \
    && rm -rf /opt/codex-install /tmp/codex-install.sh

# Optional host integrations, wired up by the setup wizard
# (wizard/01-statusline.packages). Writes to ~/.codex/ on the host via the
# shared home; see codex-cli-install for what it touches.
#
# The tmux status line ships as data under /usr/share and is copied into
# ~/.codex/ by the installer, mirroring how claude-code bundles statusline.sh.
# codex-tmux itself is an exported command, so it must live in /usr/bin —
# `command -pv` (used to resolve exports) does not search /usr/local/bin.
COPY codex-cli-install /usr/bin/codex-cli-install
COPY codex-tmux /usr/bin/codex-tmux
COPY codex-statusline.sh codex-tmux.conf /usr/share/codex-cli/
RUN chmod +x /usr/bin/codex-cli-install /usr/bin/codex-tmux \
    && chmod 0644 /usr/share/codex-cli/codex-tmux.conf \
    && chmod 0755 /usr/share/codex-cli/codex-statusline.sh
