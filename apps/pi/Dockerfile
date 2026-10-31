FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

# curl also lets distrobox-host-exec bootstrap host-spawn on a fresh box; git is
# what Pi drives in a project (and what `pi install git:...` clones with), and
# the shared $HOME dotfiles need it too. ripgrep backs Pi's search.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Pi needs Node >= 22.19; Ubuntu 24.04's nodejs is 18. npm stays in the image
# because Pi runs it at runtime to install `pi install npm:...` packages.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Pi release selected by wizard/00-release.buildarg, which offers the repo's
# published GitHub releases as tags ("v1.4.0"); npm wants the bare version, so
# the "v" is stripped. "latest" is npm's own dist-tag.
# --ignore-scripts is upstream's recommended npm install: Pi needs no
# dependency lifecycle scripts.
# CACHE_BUST is fresh on every `tools build/setup`, so the network install is
# never satisfied by a stale layer.
ARG CACHE_BUST=0
ARG PI_RELEASE=latest
RUN echo "==> Installing Pi ${PI_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_RELEASE#v}" \
    && rm -rf /root/.npm

# The release actually installed, as the picker writes it ("v1.4.0"), for the
# dashboard's update check; read back by record_install (lib/commands.sh).
RUN mkdir -p /usr/share/linux-tools \
    && v="$(node -p "require('$(npm root -g)/@earendil-works/pi-coding-agent/package.json').version")" \
    && test -n "$v" && echo "v$v" > /usr/share/linux-tools/release

# NodeSource sets npm's prefix to /usr, so npm's shim lands at /usr/bin/pi.
# Record where it points and replace it with our launcher, which names
# /usr/bin/node instead of `#!/usr/bin/env node` (see the pi script for why).
RUN mkdir -p /usr/lib/pi \
    && readlink -f /usr/bin/pi > /usr/lib/pi/entrypoint \
    && test -f "$(cat /usr/lib/pi/entrypoint)" \
    && rm /usr/bin/pi
COPY pi /usr/bin/pi
RUN chmod +x /usr/bin/pi && /usr/bin/pi --version
