FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# systemd is here purely for the systemctl client binary -- nothing is ever
# started from it. Ubuntu's base image ships no systemctl at all, and the
# wrappers need it to drive the *host's* user manager over the shared session
# bus (see bridge.sh). jq parses `openclaw dashboard --json`; xdg-utils gives
# xdg-open a home; curl is also what distrobox-host-exec needs to bootstrap its
# host-spawn helper on a fresh box.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    systemd \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# OpenClaw's engines expression is ">=24.16.0 <25 || >=26.1.0" and is enforced
# by a startup guard on every command, so Ubuntu's own nodejs (far older) is not
# an option. 24.x is the LTS line OpenClaw's own Linux installer provisions.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Selected by the wizard/00-release.buildarg page.
ARG OPENCLAW_VERSION=latest

# npm 12 blocks package lifecycle scripts unless they are approved by name, and
# OpenClaw needs its postinstall to run. npm 11.16+ accepts the flag; older npm
# treats it as unknown config and only warns, so the fallback is for the case
# where a future npm rejects it outright rather than warning.
RUN npm install -g "openclaw@${OPENCLAW_VERSION}" --allow-scripts=openclaw \
    || npm install -g "openclaw@${OPENCLAW_VERSION}"

# NodeSource sets npm's prefix to /usr, so the global bin lands at
# /usr/bin/openclaw -- already on the system default PATH that `command -pv`
# searches, so no /usr/local/bin problem for the exports.
#
# Record where npm's shim actually points and then delete it: openclaw-bin
# re-implements it without the `#!/usr/bin/env node` line, which resolves
# through the shared $HOME and picks up another box's exported node. See
# openclaw-bin for the full story.
RUN mkdir -p /usr/lib/openclaw \
    && readlink -f /usr/bin/openclaw > /usr/lib/openclaw/entrypoint \
    && test -f "$(cat /usr/lib/openclaw/entrypoint)" \
    && rm /usr/bin/openclaw

COPY bridge.sh /usr/lib/openclaw/bridge.sh
COPY openclaw openclaw-bin openclaw-gateway openclaw-dashboard openclaw-service openclaw-chat /usr/bin/
RUN chmod +x /usr/bin/openclaw /usr/bin/openclaw-bin /usr/bin/openclaw-gateway \
    /usr/bin/openclaw-dashboard /usr/bin/openclaw-service /usr/bin/openclaw-chat

# Resolve, once at build time, which flag this release uses to decline the
# systemd-service install during onboarding. OpenClaw's own docs use both
# --skip-daemon and --no-install-daemon in different places, so detect instead
# of guessing; an empty file means neither was recognised and the openclaw
# wrapper then injects nothing.
RUN help="$(/usr/bin/openclaw-bin onboard --help 2>&1 || true)"; \
    if printf '%s' "$help" | grep -q -- '--skip-daemon'; then \
        printf '%s' '--skip-daemon' > /usr/lib/openclaw/daemon-skip-flag; \
    elif printf '%s' "$help" | grep -q -- '--no-install-daemon'; then \
        printf '%s' '--no-install-daemon' > /usr/lib/openclaw/daemon-skip-flag; \
    else \
        : > /usr/lib/openclaw/daemon-skip-flag; \
    fi; \
    echo "onboard daemon-skip flag: $(cat /usr/lib/openclaw/daemon-skip-flag)"

CMD ["/bin/bash"]
