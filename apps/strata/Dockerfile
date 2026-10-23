# Strata: a local LLM server built for Qwen3.8-Flash-Next (and Qwen3.6-35B-A3B).
# https://github.com/Niko1221/Strata
#
# The image carries the Strata *Terminal* only: the `strata` command, a
# relocatable CPython 3.12 and its wheels, unpacked by upstream's own
# install.sh (SHA-256 checked, then the signed release feed verified).
# The GPU engine is NOT baked in: the first `strata launch` (or
# `strata update`) downloads the signed engine package for the detected card
# into ~/.local/share/strata/components, which is in the shared $HOME, so it
# survives `tools setup` rebuilds and is chosen per machine (hip-halo on a
# Strix Halo, rx9070 / rx7900 on Radeon cards, cuda13 / cuda12 on NVIDIA).
#
# Build arg from the setup wizard:
#   wizard/01-release.buildarg -> STRATA_REF  ("latest" or a release tag, e.g. v0.2.3.1)
# The GPU picker (wizard/00-gpu.runtime) only selects create_flags.<value>;
# the image is the same for AMD and NVIDIA.
FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# The system libraries upstream's runtime image adds for its engine packages
# (docker/Dockerfile: the common set plus the FLAVOR=hip set). The CUDA
# packages carry their own cudart/cublas; libcuda comes from the host via CDI.
# curl: install.sh, and distrobox-host-exec's host-spawn bootstrap.
# pciutils: install.sh and the Terminal name the GPU through lspci.
# git: dotfiles run inside every box through the shared $HOME.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git pciutils procps \
       libgomp1 libatomic1 libnuma1 zlib1g \
       libdrm2 libdrm-amdgpu1 libelf1t64 libtinfo6 libpci3 \
    && rm -rf /var/lib/apt/lists/*

# Release to install. "latest" follows GitHub's latest release; a tag pins
# the feed to that release's folder, so install.sh fetches that release's
# install-manifest.txt and checks it against that release's signed feed.
# CACHE_BUST is passed fresh by tools.sh on every build so "latest" is
# re-resolved instead of reusing a cached layer.
ARG CACHE_BUST=0
ARG STRATA_REF=latest
RUN set -e; \
    if [ "$STRATA_REF" = "latest" ]; then \
      feed="https://github.com/Niko1221/Strata/releases/latest/download"; \
    else \
      feed="https://github.com/Niko1221/Strata/releases/download/${STRATA_REF}"; \
    fi; \
    echo "==> Installing the Strata Terminal ${STRATA_REF} (cache-bust: ${CACHE_BUST})"; \
    curl -fsSL -o /tmp/strata-install.sh "${feed}/install.sh"; \
    STRATA_FEED="$feed" STRATA_DATA_DIR=/opt/strata STRATA_BIN_DIR=/opt/strata/bin \
      sh /tmp/strata-install.sh; \
    rm -f /tmp/strata-install.sh; \
    rm -rf /root/.local/share/strata /root/.config/strata /root/.cache; \
    /opt/strata/terminal/current/bin/strata --version

# Wrappers must live in /usr/bin: `command -pv` (used by the bin:/desktop:
# exports) does not search /usr/local/bin.
#   strata         the Terminal itself
#   strata-launch  the desktop entry: `strata launch`'s guided screens in a
#                  terminal window, kept open afterwards so the printed
#                  addresses and any error stay readable
RUN printf '%s\n' \
      '#!/usr/bin/env sh' \
      'exec /opt/strata/terminal/current/bin/strata "$@"' \
      > /usr/bin/strata \
    && printf '%s\n' \
      '#!/usr/bin/env bash' \
      '/usr/bin/strata launch "$@"' \
      'status=$?' \
      'echo' \
      'echo "strata launch exited ($status). The server, if started, keeps running:"' \
      'echo "  strata launch --status    strata monitor    strata launch --stop"' \
      'read -rp "Press Enter to close this window. "' \
      'exit "$status"' \
      > /usr/bin/strata-launch \
    && chmod +x /usr/bin/strata /usr/bin/strata-launch

# The Terminal writes __pycache__ beside its sources on first run, as the
# Distrobox user, not root.
RUN chmod -R a+rwX /opt/strata

CMD ["/bin/bash"]
