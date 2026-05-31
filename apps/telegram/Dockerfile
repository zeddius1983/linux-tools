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
    && rm /tmp/tdesktop.tar.xz \
    && ln -sf /opt/Telegram/Telegram /usr/bin/telegram-desktop
