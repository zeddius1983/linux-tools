FROM registry.fedoraproject.org/fedora:43

# vulkan-loader: memtest_vulkan dlopen()s libvulkan.so.1 at runtime (it uses the
#   erupt bindings and links against no Vulkan library at all), so the loader is
#   a hard runtime dependency rather than something the binary drags in itself.
# mesa-vulkan-drivers: the RADV (AMD) and ANV (Intel) ICDs, plus lavapipe. NVIDIA
#   has no package here on purpose — its ICD and libraries come from the host
#   driver through CDI, see create_flags.nvidia.
# vulkan-tools: vulkaninfo, for answering "which ICDs does the box actually see"
#   when a GPU is missing from the device menu. Deliberately not exported to the
#   host (see exports) — run it with `distrobox enter memtest_vulkan-box`.
# tar + xz: unpack the release tarball. curl + ca-certificates: fetch it, and
#   bootstrap host-spawn for distrobox-host-exec.
# git: dotfiles run inside every box via the shared $HOME.
RUN dnf -y --nodocs --setopt=install_weak_deps=False install \
      vulkan-loader mesa-vulkan-drivers vulkan-tools \
      tar xz curl ca-certificates git \
    && dnf clean all && rm -rf /var/cache/dnf/*

# Pinned rather than wizard-picked: upstream has published three releases in four
# years, and only these carry a Linux binary at all (the `support` release holds
# Windows DLLs, and the v0.4.1 tag has no release attached). A version picker
# would be three choices, two of them older asset-naming schemes. Bumping is a
# one-line edit here; if upstream ever gets active again, a wizard/NN-release
# .buildarg page reading this ARG is a drop-in addition.
#
# No CACHE_BUST: the URL is pinned, so caching this layer is correct.
ARG MEMTEST_VERSION=v0.5.0
RUN set -e; \
    url="https://github.com/GpuZelenograd/memtest_vulkan/releases/download/${MEMTEST_VERSION}/memtest_vulkan-${MEMTEST_VERSION}_DesktopLinux_X86_64.tar.xz"; \
    echo "==> Downloading ${url}"; \
    curl -fsSL "$url" | tar -xJ -C /usr/bin memtest_vulkan; \
    chmod +x /usr/bin/memtest_vulkan

# The tool parses no command-line arguments whatsoever. Verbose mode is switched
# on by finding the string "verbose" in the name it was invoked as — so the way
# to offer it is a second name for the same binary, not a wrapper passing a flag.
RUN ln -s memtest_vulkan /usr/bin/memtest_vulkan_verbose

CMD ["/bin/bash"]
