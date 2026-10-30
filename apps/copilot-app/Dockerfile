FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

# curl fetches the .deb below and lets distrobox-host-exec bootstrap host-spawn
# on a fresh box. git is required by the app (it clones and works in local
# repositories) and the shared $HOME dotfiles need it too. libsecret-1-0 lets
# the login token reach the host keyring over D-Bus. libasound2t64 is linked by
# the binary (notification sounds, voice) but missing from the package's Depends,
# so it would not start without it. libasound2-plugins plus /etc/asound.conf send
# ALSA's default device to the host's PulseAudio/PipeWire socket (distrobox shares
# $XDG_RUNTIME_DIR); without them ALSA has no device in the box, so there are no
# sounds and voice input finds no microphone. The Noto fonts cover emoji and
# CJK, which the package's own dependencies do not pull in.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libasound2t64 \
    libasound2-plugins \
    libsecret-1-0 \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && printf 'pcm.!default pulse\nctl.!default pulse\n' > /etc/asound.conf

# GitHub publishes the .deb on github/app's latest release (x64 and arm64).
# Installing it through apt resolves its Depends (WebKitGTK 4.1, GTK 3,
# ayatana-appindicator). CACHE_BUST is fresh on every `tools build/setup`, so a
# rebuild picks up a new release instead of reusing the cached layer.
# The package names its desktop entry "GitHub Copilot.desktop"; it is renamed to
# github.desktop so the `app:github` export lands at copilot-app-box-github.desktop,
# the path tools.sh post-processes (Name, Icon).
ARG CACHE_BUST=0
RUN echo "==> Installing GitHub Copilot app (cache-bust: ${CACHE_BUST})" \
    && case "$(dpkg --print-architecture)" in \
         amd64) arch=x64 ;; arm64) arch=arm64 ;; \
         *) echo "unsupported architecture" >&2; exit 1 ;; \
       esac \
    && curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/copilot-app.deb \
        "https://github.com/github/app/releases/latest/download/GitHub-Copilot-linux-${arch}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/copilot-app.deb \
    && rm -f /tmp/copilot-app.deb \
    && rm -rf /var/lib/apt/lists/* \
    && mv "/usr/share/applications/GitHub Copilot.desktop" /usr/share/applications/github.desktop \
    && sed -i 's/^Categories=$/Categories=Development;/' /usr/share/applications/github.desktop
