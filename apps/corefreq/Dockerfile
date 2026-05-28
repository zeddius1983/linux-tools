FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates kmod sudo \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/cyring/CoreFreq /opt/corefreq-src

# Build script: compiles CoreFreq against the host kernel, installs systemd service.
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
echo "[Unit]" > "${DEST}/corefreq.service"\n\
echo "Description=CoreFreq daemon" >> "${DEST}/corefreq.service"\n\
echo "After=local-fs.target" >> "${DEST}/corefreq.service"\n\
echo "" >> "${DEST}/corefreq.service"\n\
echo "[Service]" >> "${DEST}/corefreq.service"\n\
echo "ExecStartPre=-/sbin/insmod ${DEST}/corefreqk.ko" >> "${DEST}/corefreq.service"\n\
echo "ExecStart=${DEST}/corefreqd" >> "${DEST}/corefreq.service"\n\
echo "ExecStopPost=-/sbin/rmmod corefreqk" >> "${DEST}/corefreq.service"\n\
echo "Restart=on-failure" >> "${DEST}/corefreq.service"\n\
echo "RestartSec=3" >> "${DEST}/corefreq.service"\n\
echo "" >> "${DEST}/corefreq.service"\n\
echo "[Install]" >> "${DEST}/corefreq.service"\n\
echo "WantedBy=multi-user.target" >> "${DEST}/corefreq.service"\n\
distrobox-host-exec sudo cp "${DEST}/corefreq.service" /etc/systemd/system/corefreq.service\n\
distrobox-host-exec sudo systemctl daemon-reload\n\
distrobox-host-exec sudo systemctl enable corefreq\n\
distrobox-host-exec sudo systemctl restart corefreq\n\
echo "==> Done. CoreFreq service enabled and started."\n\
' > /usr/bin/corefreq-setup && chmod +x /usr/bin/corefreq-setup

# CLI wrapper — corefreqd is managed by the systemd service, just exec the CLI
RUN printf '#!/usr/bin/env bash\n\
set -euo pipefail\n\
BIN="$HOME/.local/corefreq/corefreq-cli"\n\
[[ -x "$BIN" ]] || { echo "Not built. Run: corefreq-setup" >&2; exit 1; }\n\
exec "$BIN" "$@"\n\
' > /usr/bin/corefreq-cli && chmod +x /usr/bin/corefreq-cli

CMD ["/bin/bash"]
