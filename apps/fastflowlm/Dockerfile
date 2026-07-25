FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ca-certificates/curl: release downloads + distrobox-host-exec bootstrap.
# software-properties-common + gnupg: add-apt-repository for the AMD XRT PPA.
# git: dotfiles run inside every box via the shared $HOME.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl gnupg git software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# AMD XRT userspace comes from the lemonade-team PPA. Only the *userspace*
# half is installed here — the amdxdna kernel driver lives on the host
# (in-tree on kernel 7.0+, or amdxdna-dkms); a container cannot supply it.
RUN add-apt-repository -y ppa:lemonade-team/stable \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       libxrt2 libxrt-npu2 libxrt-utils-npu \
    && rm -rf /var/lib/apt/lists/*

# Release to install. "latest" resolves the newest GitHub release at build
# time; the interactive setup wizard offers the last 10 tags (FLM_REF).
# CACHE_BUST is passed fresh by tools.sh on every build so this layer re-runs
# instead of reusing a stale cached download; the apt layers above stay cached.
ARG CACHE_BUST=0
ARG FLM_REF=latest
RUN set -e; \
    api="https://api.github.com/repos/FastFlowLM/FastFlowLM/releases"; \
    if [ "$FLM_REF" = "latest" ]; then api="$api/latest"; else api="$api/tags/$FLM_REF"; fi; \
    echo "==> Resolving FastFlowLM release ${FLM_REF} (cache-bust: ${CACHE_BUST})"; \
    url="$(curl -fsSL "$api" \
        | grep -o '"browser_download_url": *"[^"]*ubuntu24\.04_amd64\.deb"' \
        | sed 's/.*"browser_download_url": *"//;s/"$//' | head -1)"; \
    [ -n "$url" ] || { echo "no ubuntu24.04 .deb asset for ref ${FLM_REF}" >&2; exit 1; }; \
    echo "==> Downloading ${url}"; \
    curl -fsSL -o /tmp/fastflowlm.deb "$url"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/fastflowlm.deb; \
    rm -f /tmp/fastflowlm.deb; \
    rm -rf /var/lib/apt/lists/*

# The .deb ships /usr/bin/flm -> /opt/fastflowlm/bin/flm, so `bin:flm` exports
# cleanly. Runtime state (models, config) lives under $HOME and is therefore
# shared with the host by Distrobox.

# Host-prerequisite checker. The NPU stack straddles the container boundary:
# XRT userspace is in here, the amdxdna driver / firmware / IOMMU / memlock
# limits are all host-side, so a single "why is my NPU not working" answer
# needs to read both sides. Must live in /usr/bin for `command -pv`.
COPY flm-doctor /usr/bin/flm-doctor
RUN chmod +x /usr/bin/flm-doctor

CMD ["/bin/bash"]
