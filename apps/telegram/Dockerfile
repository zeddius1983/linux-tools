FROM --platform=linux/amd64 ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils \
        libxcb1 libxcb-xinerama0 libxcb-cursor0 libxcb-keysyms1 libxcb-image0 \
        libxcb-shm0 libxcb-icccm4 libxcb-render-util0 libxcb-randr0 \
        libxkbcommon0 libxkbcommon-x11-0 \
        libsm6 libice6 libxext6 libxrender1 libfontconfig1 \
        mesa-utils vulkan-tools \
        libgl1 libgl1-mesa-dri libglx-mesa0 \
        libegl1 libegl-mesa0 libgles2 libopengl0 \
        libdrm2 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fL https://telegram.org/dl/desktop/linux -o /tmp/tdesktop.tar.xz \
    && mkdir -p /opt/Telegram \
    && tar -xf /tmp/tdesktop.tar.xz -C /opt/Telegram --strip-components=1 \
    && rm /tmp/tdesktop.tar.xz

# A wrapper rather than a symlink: it stops Telegram writing a host menu entry
# that points into this box (see the script). It lives in /usr/bin because
# `command -pv`, which resolves exports, does not search /usr/local/bin.
# telegram-box-scheme.desktop is the box-only handler that keeps Telegram from
# taking over the host's tg:// links (see the script).
COPY telegram-desktop /usr/bin/telegram-desktop
COPY telegram-box-scheme.desktop /usr/share/applications/telegram-box-scheme.desktop
RUN chmod 0755 /usr/bin/telegram-desktop \
    && chmod 0644 /usr/share/applications/telegram-box-scheme.desktop
