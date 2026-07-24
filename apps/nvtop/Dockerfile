FROM registry.fedoraproject.org/fedora:43

# nvtop is a multi-vendor GPU TUI (NVIDIA / AMD / Intel / …). Fedora's package is
# built with every backend enabled: the NVIDIA backend dlopen()s
# libnvidia-ml.so.1 at runtime (no CUDA/driver needed at build time — the host
# driver, incl. NVML, is injected via CDI at runtime), while the AMD/Intel
# backends read libdrm + /sys/class/drm, which Distrobox exposes by default.
# ncurses is pulled in as a dependency.
RUN dnf -y --nodocs --setopt=install_weak_deps=False install \
      nvtop \
    && dnf clean all && rm -rf /var/cache/dnf/*

CMD ["/bin/bash"]
