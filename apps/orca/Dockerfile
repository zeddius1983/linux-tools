FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

# curl fetches the .deb below and lets distrobox-host-exec bootstrap host-spawn
# on a fresh box. git is what Orca's worktrees and agents run on, and the shared
# $HOME dotfiles need it too. libpulse0 gives Chromium audio through the host's
# PulseAudio/PipeWire socket. The Noto fonts cover emoji and CJK, which the
# package's own dependencies do not pull in. (libsecret-1-0, for Electron
# safeStorage on the host keyring, is already in the package's Depends.) jq is
# for the agents run in Orca's terminals, which run inside this box: Claude Code's
# ~/.claude/statusline.sh parses its JSON input with jq, and without it the
# status line loses the model, tokens and 5h/7d usage segments.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    libpulse0 \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# gh, from GitHub's own APT repo: Orca's Tasks view and its per-worktree PR, review
# and CI status all go through the GitHub CLI, and onboarding flags it as missing.
# It authenticates from the shared ~/.config/gh, so a host `gh auth login` carries over.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Orca release selected by wizard/00-release.buildarg: a desktop tag ("v1.4.245")
# or "latest". stablyai/orca also publishes mobile-android-v* pre-releases, which
# the page's tag-match| hides and /releases/latest never resolves to (it skips
# pre-releases). The asset name carries the bare version, so "latest" is first
# resolved to its tag through the /releases/latest redirect, without an API call.
# CACHE_BUST is fresh on every `tools build/setup`, so "latest" is never
# satisfied by a stale layer.
#
# Installing the .deb through apt resolves its Depends. Its postinst links
# /usr/bin/orca-ide to the bundled CLI (resources/bin/orca-ide, Electron in Node
# mode), which is what `bin:orca-ide` exports; the GUI is /opt/Orca/orca-ide,
# reached through the package's orca-ide.desktop (`app:orca-ide`).
# The desktop entry also claims text/markdown, text/csv and
# text/tab-separated-values; those are dropped so exporting Orca does not make
# it a candidate (or, with nothing else installed, the default) for opening
# every Markdown file on the host. The orca:// scheme handler is kept.
ARG CACHE_BUST=0
ARG ORCA_RELEASE=latest
RUN echo "==> Installing Orca ${ORCA_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in amd64|arm64) ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac \
    && tag="$ORCA_RELEASE" \
    && if [ "$tag" = latest ]; then \
         tag="$(curl --proto '=https' --tlsv1.2 -fsSLI -o /dev/null -w '%{url_effective}' \
                https://github.com/stablyai/orca/releases/latest)" \
         && tag="${tag##*/releases/tag/}"; \
       fi \
    && case "$tag" in v[0-9]*) ;; \
         *) echo "not an Orca desktop release: '$tag'" >&2; exit 1 ;; esac \
    && echo "==> Orca ${tag} (${arch})" \
    && curl --proto '=https' --tlsv1.2 -fSL --retry 3 -o /tmp/orca.deb \
        "https://github.com/stablyai/orca/releases/download/${tag}/orca-ide_${tag#v}_${arch}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/orca.deb \
    && rm -f /tmp/orca.deb \
    && rm -rf /var/lib/apt/lists/* \
    && test -x /usr/bin/orca-ide \
    && sed -i -e 's@^MimeType=.*@MimeType=x-scheme-handler/orca;@' \
              -e 's@^Exec=/opt/Orca/orca-ide@Exec=/usr/bin/orca-ide-launch@' \
        /usr/share/applications/orca-ide.desktop \
    && grep -q '^Exec=/usr/bin/orca-ide-launch ' /usr/share/applications/orca-ide.desktop

# Tray icon (orca-tray) showing that Orca's terminal daemon is still running
# after the window closes, with a Quit Completely item; Orca draws none on
# Linux. The menu entry's Exec is pointed at orca-ide-launch above, which starts the
# tray next to the window. PyGObject comes from the system python3. The icon is
# staged into $HOME by the tray at startup, because the panel that draws it runs
# on the host.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-gi gir1.2-gtk-3.0 \
        gir1.2-ayatanaappindicator3-0.1 libayatana-appindicator3-1 \
    && rm -rf /var/lib/apt/lists/*
COPY icon.png /usr/share/orca-tray/orca-tray.png
COPY orca-ide-launch orca-tray /usr/bin/
RUN chmod 755 /usr/bin/orca-ide-launch /usr/bin/orca-tray
