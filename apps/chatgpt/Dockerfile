FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# curl fetches the .deb below and lets distrobox-host-exec bootstrap host-spawn
# on a fresh box. git is a Recommends of the package (Codex runs git in local
# projects) and the shared $HOME dotfiles need it too. libsecret-1-0 lets
# Electron's safeStorage reach the host keyring over D-Bus instead of falling
# back to a plaintext store. libpulse0 gives audio (voice mode) through the
# host's PulseAudio/PipeWire socket. The Noto fonts cover emoji and CJK, which
# the package's own dependencies do not pull in.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libpulse0 \
    libsecret-1-0 \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# OpenAI ships the .deb at a stable "latest" URL; installing it through apt
# resolves its dependencies, and its postinst adds the signed OpenAI APT repo
# (/etc/apt/sources.list.d/chatgpt.sources), so `sudo apt upgrade` inside the
# box updates the app between rebuilds. Both amd64 and arm64 are published.
RUN arch="$(dpkg --print-architecture)" \
    && curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/chatgpt.deb \
        "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_${arch}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/chatgpt.deb \
    && rm -f /tmp/chatgpt.deb \
    && rm -rf /var/lib/apt/lists/*
