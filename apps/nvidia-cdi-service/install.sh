#!/usr/bin/env bash
#
# Install (or uninstall) the nvidia-cdi-service boot service on the HOST.
#
# The service runs `nvidia-ctk cdi generate` on every boot so /etc/cdi/nvidia.yaml
# always matches the currently-installed GPUs (add/remove/move a card, or a
# PCIe-switch re-enumeration, otherwise leaves the spec stale and CDI containers
# fail to start). It also suppresses the toolkit's
# `disable-device-node-modification` hook, which fails under distrobox.
#
# Invoked by `tools setup nvidia-cdi-service` (runs on the host, so sudo has a
# real TTY). `tools rm nvidia-cdi-service` calls `install.sh uninstall`.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT="nvidia-cdi-service.service"
DEST="/etc/systemd/system/${UNIT}"
OLD_UNIT="nvidia-cdi-regenerate.service"   # pre-rename name; migrate away from it

remove_old() {
    # Clean up the pre-rename unit if it's still installed (so we don't run two).
    if [[ -e "/etc/systemd/system/${OLD_UNIT}" ]]; then
        echo "==> Migrating: removing old ${OLD_UNIT}..."
        sudo systemctl disable --now "${OLD_UNIT}" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${OLD_UNIT}"
    fi
}

uninstall() {
    echo "==> Disabling and removing ${UNIT}..."
    sudo systemctl disable --now "${UNIT}" 2>/dev/null || true
    sudo rm -f "${DEST}"
    remove_old
    sudo systemctl daemon-reload
    echo "==> Removed. (Existing /etc/cdi/nvidia.yaml left in place.)"
}

if [[ "${1:-}" == "uninstall" ]]; then
    uninstall
    exit 0
fi

if ! command -v nvidia-ctk >/dev/null 2>&1; then
    echo "WARNING: 'nvidia-ctk' not found on the host." >&2
    echo "  This service needs the NVIDIA Container Toolkit (package: nvidia-container-toolkit)." >&2
    echo "  Debian/Ubuntu: apt install nvidia-container-toolkit" >&2
    echo "  Fedora:        dnf install nvidia-container-toolkit" >&2
    echo "  Arch:          pacman -S nvidia-container-toolkit" >&2
    echo "  The unit installs anyway; it self-skips at boot until nvidia-ctk exists." >&2
    echo "" >&2
fi

remove_old

echo "==> Installing ${UNIT} -> ${DEST}"
sudo install -m 644 "${HERE}/${UNIT}" "${DEST}"
sudo systemctl daemon-reload
sudo systemctl enable --now "${UNIT}"

echo ""
echo "==> Service status:"
systemctl --no-pager --full status "${UNIT}" 2>/dev/null | head -n 12 || true
echo ""
echo "==> Current CDI spec devices:"
grep -E '^\s+name:' /etc/cdi/nvidia.yaml 2>/dev/null | head || echo "  (no /etc/cdi/nvidia.yaml yet — check nvidia-ctk / driver)"
