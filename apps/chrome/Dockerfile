# Chrome is published for amd64 only, so pin the platform: on an arm64 host this
# needs qemu-user-static binfmt on the host, but it keeps the image honest.
FROM --platform=linux/amd64 docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# curl/gnupg fetch the signing key below; curl also lets distrobox-host-exec
# bootstrap host-spawn on a fresh box. libpulse0/libasound2t64 give Chrome
# audio through the host's PulseAudio/PipeWire socket. git is here because the
# shared $HOME dotfiles (zsh + starship) run inside this box too.
# The fonts matter: Chrome's own dependencies only pull fonts-liberation, so
# without these emoji render as tofu and CJK pages fall back to nothing.
# libpci3 is not optional: without it Chrome cannot read the GPU's PCI IDs and
# chrome://gpu reports VENDOR=0x0000 DEVICE=0x0000, which breaks the render-node
# matching its VA-API setup depends on (see README).
# libva + mesa-va-drivers make VA-API video decode available; vainfo diagnoses it.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    libpci3 \
    libpulse0 \
    libasound2t64 \
    libva2 \
    libva-drm2 \
    mesa-va-drivers \
    vainfo \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
    http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*
