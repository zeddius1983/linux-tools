#!/usr/bin/env bash
#
# Install (or uninstall) the nvidia-p2p-acs boot service on the HOST.
#
# The service clears PCIe ACS "P2P Request/Completion Redirect" on every bridge
# above the target GPUs at each boot, so a PCIe switch routes GPU<->GPU peer
# traffic directly (~52 GB/s on 2×RTX 3090 over a PEX880xx) instead of bouncing it
# to the root complex (~1 GB/s + data corruption). Needed on hosts with the IOMMU
# enabled, which re-enables ACS redirect on every boot.
#
# Invoked by `tools setup nvidia-p2p-acs` (runs on the host, so sudo has a real
# TTY). `tools rm nvidia-p2p-acs` calls `install.sh uninstall`.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="nvidia-p2p-acs.sh"
UNIT="nvidia-p2p-acs.service"
SCRIPT_DEST="/usr/local/sbin/${SCRIPT}"
UNIT_DEST="/etc/systemd/system/${UNIT}"

uninstall() {
    echo "==> Disabling and removing ${UNIT}..."
    sudo systemctl disable --now "${UNIT}" 2>/dev/null || true
    sudo rm -f "${UNIT_DEST}" "${SCRIPT_DEST}"
    sudo systemctl daemon-reload
    echo "==> Removed. (ACS bits are restored to firmware defaults on next reboot.)"
}

ensure_pciutils() {
    command -v setpci >/dev/null 2>&1 && return 0
    echo "==> 'setpci' not found — installing pciutils..."
    if   command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y pciutils
    elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y pciutils
    elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm pciutils
    elif command -v zypper  >/dev/null 2>&1; then sudo zypper install -y pciutils
    else
        echo "ERROR: could not detect a package manager to install pciutils." >&2
        echo "  Install 'pciutils' (provides setpci/lspci) manually, then re-run." >&2
        exit 1
    fi
}

if [[ "${1:-}" == "uninstall" ]]; then
    uninstall
    exit 0
fi

ensure_pciutils

echo "==> Installing ${SCRIPT} -> ${SCRIPT_DEST}"
sudo install -m 755 "${HERE}/${SCRIPT}" "${SCRIPT_DEST}"

echo "==> Installing ${UNIT} -> ${UNIT_DEST}"
sudo install -m 644 "${HERE}/${UNIT}" "${UNIT_DEST}"
sudo systemctl daemon-reload
sudo systemctl enable --now "${UNIT}"

echo ""
echo "==> Service log (bridges cleared this run):"
journalctl -u "${UNIT}" -b --no-pager 2>/dev/null | tail -n 12 || true
echo ""
cat <<'NOTE'
==> NOTE: this assumes the target GPUs are 10de:2204 (RTX 3090). For a different
    clique, edit Environment=P2P_GPU_PCI_IDS in
    /etc/systemd/system/nvidia-p2p-acs.service and `sudo systemctl daemon-reload`.
    Requires IOMMU passthrough (iommu=pt) for full P2P bandwidth.
NOTE
