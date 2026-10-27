FROM registry.fedoraproject.org/fedora:43

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/dnf.sh && rm -rf /tmp/distrobox-deps

# nvtop is a multi-vendor GPU TUI (NVIDIA / AMD / Intel / …). Fedora's package is
# built with every backend enabled: the NVIDIA backend dlopen()s
# libnvidia-ml.so.1 at runtime (no CUDA/driver needed at build time — the host
# driver, incl. NVML, is injected via CDI at runtime), while the AMD/Intel
# backends read libdrm + /sys/class/drm, which Distrobox exposes by default.
# ncurses is pulled in as a dependency. git is for the shared-$HOME dotfiles
# that run in every box (the base already has curl for distrobox-host-exec).
RUN dnf -y --nodocs --setopt=install_weak_deps=False install \
      nvtop git \
    && dnf clean all && rm -rf /var/cache/dnf/*

CMD ["/bin/bash"]
