FROM --platform=linux/amd64 docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    libxi6 libxrender1 libxtst6 mesa-utils libfontconfig1 \
    libgtk-3-bin dbus-user-session libxcb-keysyms1 \
    libayatana-appindicator3-1 \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Download and install latest JetBrains Toolbox
RUN TOOLBOX_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['TBA'][0]['downloads']['linux']['link'])") \
    && curl -fL "$TOOLBOX_URL" -o /tmp/jetbrains-toolbox.tar.gz \
    && mkdir -p /opt/jetbrains-toolbox \
    && tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /opt/jetbrains-toolbox --strip-components=1 \
    && rm /tmp/jetbrains-toolbox.tar.gz \
    && chmod -R a+rwX /opt/jetbrains-toolbox

# Wrapper: install tray icon to shared $HOME on every launch.
RUN printf '#!/bin/bash\n\
ICON_SRC=/opt/jetbrains-toolbox/bin/toolbox-tray-color.png\n\
SCALABLE_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"\n\
PNG_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"\n\
mkdir -p "$SCALABLE_DIR" "$PNG_DIR"\n\
cp "$ICON_SRC" "$PNG_DIR/jetbrains-toolbox.png"\n\
cp "$ICON_SRC" "$PNG_DIR/toolbox-tray-color.png"\n\
[[ -f "$SCALABLE_DIR/jetbrains-toolbox.svg" ]] && cp "$SCALABLE_DIR/jetbrains-toolbox.svg" "$SCALABLE_DIR/toolbox-tray-color.svg"\n\
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true\n\
exec /opt/jetbrains-toolbox/bin/jetbrains-toolbox "$@"\n' \
    > /usr/bin/jetbrains-toolbox && chmod +x /usr/bin/jetbrains-toolbox
