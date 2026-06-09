FROM --platform=linux/amd64 docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget \
    libxi6 libxrender1 libxtst6 mesa-utils libfontconfig1 \
    libgtk-3-bin dbus-user-session libxcb-keysyms1 \
    libayatana-appindicator3-1 \
    zsh git git-lfs \
    build-essential cmake \
    python3 python3-pip python3-venv \
    jq unzip zip \
    ripgrep shellcheck \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# docker → host podman bridge (no socket needed)
RUN printf '#!/bin/bash\nexec distrobox-host-exec podman "$@"\n' \
    > /usr/bin/docker && chmod +x /usr/bin/docker

# Make SDKMAN available in login shells (bash + zsh) — installed at runtime to ~/.sdkman
RUN printf '\n[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"\n' \
    >> /etc/bash.bashrc \
    && mkdir -p /etc/zsh \
    && printf '\n[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"\n' \
    >> /etc/zsh/zshrc

# Download and install latest JetBrains Toolbox
RUN TOOLBOX_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['TBA'][0]['downloads']['linux']['link'])") \
    && curl -fL "$TOOLBOX_URL" -o /tmp/jetbrains-toolbox.tar.gz \
    && mkdir -p /opt/jetbrains-toolbox \
    && tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /opt/jetbrains-toolbox --strip-components=1 \
    && rm /tmp/jetbrains-toolbox.tar.gz \
    && chmod -R a+rwX /opt/jetbrains-toolbox

# Wrapper: install tray icon + SDKMAN to shared $HOME on first launch
RUN printf '#!/bin/bash\n\
ICON_SRC=/opt/jetbrains-toolbox/bin/toolbox-tray-color.png\n\
SCALABLE_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"\n\
PNG_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"\n\
mkdir -p "$SCALABLE_DIR" "$PNG_DIR"\n\
cp "$ICON_SRC" "$PNG_DIR/jetbrains-toolbox.png"\n\
cp "$ICON_SRC" "$PNG_DIR/toolbox-tray-color.png"\n\
[[ -f "$SCALABLE_DIR/jetbrains-toolbox.svg" ]] && cp "$SCALABLE_DIR/jetbrains-toolbox.svg" "$SCALABLE_DIR/toolbox-tray-color.svg"\n\
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true\n\
if [[ ! -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then\n\
    curl -s "https://get.sdkman.io" | bash\n\
fi\n\
exec /opt/jetbrains-toolbox/bin/jetbrains-toolbox "$@"\n' \
    > /usr/bin/jetbrains-toolbox && chmod +x /usr/bin/jetbrains-toolbox
