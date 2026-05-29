FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates kmod sudo \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/cyring/CoreFreq /opt/corefreq-src

# Build script: compiles CoreFreq against the host kernel and installs a
# passwordless sudoers entry for insmod/rmmod/daemon-start.
# /lib/modules is shared by Distrobox from the host, so the build symlink
# /lib/modules/$(uname -r)/build resolves to the mounted /usr/src headers.
RUN printf '#!/usr/bin/env bash\n\
set -euo pipefail\n\
KVER=$(uname -r)\n\
if [[ -d "/lib/modules/${KVER}/build" ]]; then\n\
    KBUILD="/lib/modules/${KVER}/build"\n\
elif [[ -d "/usr/src/linux-headers-${KVER}" ]]; then\n\
    KBUILD="/usr/src/linux-headers-${KVER}"\n\
else\n\
    echo "ERROR: kernel headers not found" >&2\n\
    echo "  On host: sudo apt install linux-headers-$(uname -r)" >&2\n\
    exit 1\n\
fi\n\
echo "==> Building CoreFreq for kernel ${KVER} (headers: ${KBUILD})..."\n\
BUILD="$HOME/.local/corefreq-build"\n\
rm -rf "$BUILD" && cp -r /opt/corefreq-src "$BUILD"\n\
cd "$BUILD" && make KERNELDIR="${KBUILD}"\n\
DEST="$HOME/.local/corefreq"\n\
mkdir -p "$DEST"\n\
cp "$BUILD/build/corefreqk.ko" "$BUILD/build/corefreqd" "$BUILD/build/corefreq-cli" "$DEST/"\n\
echo "#!/bin/bash" > "${DEST}/daemon-start"\n\
echo "nohup ${DEST}/corefreqd &>/dev/null &" >> "${DEST}/daemon-start"\n\
chmod +x "${DEST}/daemon-start"\n\
echo "$(whoami) ALL=(ALL) NOPASSWD: /sbin/insmod ${DEST}/corefreqk.ko" > "${DEST}/sudoers"\n\
echo "$(whoami) ALL=(ALL) NOPASSWD: /sbin/rmmod corefreqk" >> "${DEST}/sudoers"\n\
echo "$(whoami) ALL=(ALL) NOPASSWD: ${DEST}/daemon-start" >> "${DEST}/sudoers"\n\
distrobox-host-exec sudo cp "${DEST}/sudoers" /etc/sudoers.d/corefreq\n\
distrobox-host-exec sudo chmod 440 /etc/sudoers.d/corefreq\n\
lsmod | grep -q "^corefreqk " && distrobox-host-exec sudo rmmod corefreqk 2>/dev/null || true\n\
distrobox-host-exec sudo insmod "${DEST}/corefreqk.ko"\n\
echo "==> Done. Run: corefreq-cli"\n\
' > /usr/bin/corefreq-setup && chmod +x /usr/bin/corefreq-setup

# CLI wrapper — loads module and starts daemon on host if needed, then launches CLI
RUN printf '#!/usr/bin/env bash\n\
set -euo pipefail\n\
BIN="$HOME/.local/corefreq/corefreq-cli"\n\
[[ -x "$BIN" ]] || { echo "Not built. Run: corefreq-setup" >&2; exit 1; }\n\
if ! distrobox-host-exec test -d /sys/module/corefreqk; then\n\
    echo "==> Loading corefreqk..." >&2\n\
    distrobox-host-exec sudo insmod "$HOME/.local/corefreq/corefreqk.ko"\n\
fi\n\
if ! distrobox-host-exec pgrep -x corefreqd &>/dev/null; then\n\
    echo "==> Starting corefreqd..." >&2\n\
    distrobox-host-exec sudo "$HOME/.local/corefreq/daemon-start"\n\
    sleep 1\n\
fi\n\
exec "$BIN" "$@"\n\
' > /usr/bin/corefreq-cli && chmod +x /usr/bin/corefreq-cli

CMD ["/bin/bash"]
