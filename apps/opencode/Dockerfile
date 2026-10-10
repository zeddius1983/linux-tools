FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# curl also lets distrobox-host-exec bootstrap host-spawn on a fresh box; git is
# what opencode drives in a project, and the shared $HOME dotfiles need it too.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
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

# OpenCode release selected by wizard/00-release.buildarg, which offers the
# repo's published GitHub releases as tags ("v1.18.35"); the installer wants the
# bare version, so the "v" is stripped. "latest", the non-interactive default,
# lets the installer pick the newest release itself. Only published releases
# work: the repo also carries bare git tags (a 2.0.x line) with no release
# assets, which is why the page is releases| rather than a git ls-remote list.
# CACHE_BUST is fresh on every `tools build/setup`, so the network install is
# never satisfied by a stale layer.
#
# The installer always writes to $HOME/.opencode/bin and has no install-dir
# option, so it runs against a throwaway HOME and the binary is moved to
# /usr/bin, where `command -pv` (used to resolve exports) looks. It needs bash,
# not dash: it uses `set -o pipefail`.
ARG CACHE_BUST=0
ARG OPENCODE_RELEASE=latest
RUN echo "==> Installing OpenCode ${OPENCODE_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh \
    && if [ "${OPENCODE_RELEASE}" = latest ]; then set --; \
       else set -- --version "${OPENCODE_RELEASE#v}"; fi \
    && HOME=/opt/opencode-install bash /tmp/opencode-install.sh --no-modify-path "$@" \
    && mv /opt/opencode-install/.opencode/bin/opencode /usr/bin/opencode \
    && /usr/bin/opencode --version \
    && rm -rf /opt/opencode-install /tmp/opencode-install.sh
