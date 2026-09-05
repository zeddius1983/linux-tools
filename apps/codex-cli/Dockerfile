FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bubblewrap \
    git \
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
