FROM registry.fedoraproject.org/fedora:43

RUN dnf -y --nodocs --setopt=install_weak_deps=False install \
  bash ca-certificates curl wget xdg-utils \
  fuse fuse-libs libappindicator-gtk3 \
  vulkan-loader vulkan-tools mesa-vulkan-drivers mesa-dri-drivers \
  libdrm libglvnd-glx libglvnd-egl libX11 libXext libXrender libXrandr \
  libXfixes libXi libXcursor libXdamage libXtst libxkbcommon \
  gtk3 nss alsa-lib cups-libs libgbm at-spi2-atk \
  libatomic libstdc++ libgcc \
  radeontop procps-ng \
  && dnf clean all && rm -rf /var/cache/dnf/*

RUN mkdir -p /opt/lmstudio /usr/local/bin

RUN curl -fL \
  https://lmstudio.ai/download/latest/linux/x64 \
  -o /opt/lmstudio/LM-Studio.AppImage && \
  chmod +x /opt/lmstudio/LM-Studio.AppImage

RUN printf '#!/usr/bin/env bash\nexec /opt/lmstudio/LM-Studio.AppImage "$@"\n' \
  > /usr/local/bin/lmstudio && \
  chmod +x /usr/local/bin/lmstudio

RUN mkdir -p /usr/share/applications && \
  printf '[Desktop Entry]\nName=LM Studio\nExec=lmstudio %%U\nIcon=lmstudio\nTerminal=false\nType=Application\nCategories=Development;\nMimeType=x-scheme-handler/lmstudio;\n' \
  > /usr/share/applications/lmstudio.desktop

CMD ["/bin/bash"]
