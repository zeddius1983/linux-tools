FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

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
# repo's published GitHub releases as tags ("v2.2.0", "v1.18.35"); the
# installers want the bare version, so the "v" is stripped. Only published
# releases work, which is why the page is releases| rather than a git
# ls-remote list.
#
# OpenCode 1 and 2 have separate installers and neither installs the other:
# /install refuses 2.x ("not an OpenCode 1 release") and only resolves "latest"
# to the newest 1.x; /v2/install downloads from npm (@opencode/cli), where the
# 1.x builds are not published. So pick the installer by major version, and
# send "latest", the non-interactive default, to /v2/install, which resolves
# it to the newest 2.x.
# CACHE_BUST is fresh on every `tools build/setup`, so the network install is
# never satisfied by a stale layer.
#
# Both installers always write to $HOME/.opencode/bin and have no install-dir
# option, so they run against a throwaway HOME and the binary is moved to
# /usr/bin, where `command -pv` (used to resolve exports) looks. (v2 also drops
# an `opencode2` shim there; it is discarded with the throwaway HOME.) They
# need bash, not dash: they use `set -o pipefail`.
ARG CACHE_BUST=0
ARG OPENCODE_RELEASE=latest
RUN echo "==> Installing OpenCode ${OPENCODE_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && version="${OPENCODE_RELEASE#v}" \
    && case "$version" in 0.*|1.*) installer=install ;; *) installer=v2/install ;; esac \
    && curl -fsSL "https://opencode.ai/${installer}" -o /tmp/opencode-install.sh \
    && if [ "$version" = latest ]; then set --; \
       else set -- --version "$version"; fi \
    && HOME=/opt/opencode-install bash /tmp/opencode-install.sh --no-modify-path "$@" \
    && mv /opt/opencode-install/.opencode/bin/opencode /usr/bin/opencode \
    && /usr/bin/opencode --version \
    && rm -rf /opt/opencode-install /tmp/opencode-install.sh

# The release actually installed, as the picker writes it ("v2.2.5"), for the
# dashboard's update check; read back by record_install (lib/commands.sh). 2.x
# prints "opencode v2.2.5" and 1.x a bare "1.18.35", hence the re-prefixing.
RUN mkdir -p /usr/share/linux-tools \
    && v="$(/usr/bin/opencode --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" \
    && test -n "$v" && echo "v$v" > /usr/share/linux-tools/release
