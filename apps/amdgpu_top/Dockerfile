FROM registry.fedoraproject.org/fedora:43

RUN dnf -y --nodocs --setopt=install_weak_deps=False install \
  bash ca-certificates curl \
  vulkan-loader mesa-vulkan-drivers \
  mesa-libGL mesa-libEGL mesa-dri-drivers \
  libdrm libglvnd-glx libglvnd-egl \
  libX11 libXcursor libXi libXrandr libXext libXrender \
  libxkbcommon libxkbcommon-x11 \
  && dnf clean all && rm -rf /var/cache/dnf/*

RUN RPM_URL=$(curl -fsSL https://api.github.com/repos/Umio-Yasuno/amdgpu_top/releases/latest \
    | grep '"browser_download_url"' | grep 'x86_64\.rpm"' \
    | sed 's/.*"browser_download_url": "\([^"]*\)".*/\1/') && \
    dnf install -y "$RPM_URL" && \
    dnf clean all && rm -rf /var/cache/dnf/*

RUN mv /usr/bin/amdgpu_top /usr/bin/amdgpu_top-bin && \
  printf '#!/usr/bin/env bash\nexec /usr/bin/amdgpu_top-bin --dark "$@"\n' \
    > /usr/bin/amdgpu_top && chmod +x /usr/bin/amdgpu_top && \
  printf '#!/usr/bin/env bash\nexec /usr/bin/amdgpu_top-bin --gui "$@"\n' \
    > /usr/bin/amdgpu_top-gui && chmod +x /usr/bin/amdgpu_top-gui

CMD ["/bin/bash"]
