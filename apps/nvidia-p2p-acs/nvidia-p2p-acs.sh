#!/usr/bin/env bash
#
# Disable PCIe ACS P2P redirect on every bridge ABOVE each target GPU, so a
# PCIe switch routes GPU<->GPU peer traffic directly instead of bouncing it up to
# the root complex (which yields ~1 GB/s + data corruption).
#
# Bridges are resolved LIVE from the PCIe topology, so this survives PCI
# renumbering (cards added/removed/moved under the switch, BIOS changes) with no
# hardcoded bus addresses. Runs as a systemd oneshot at boot; needs root.
#
# Background: apps/nvidia-p2p-acs/.memory.md (and apps/nvbandwidth/.memory.md).
#
set -u

# GPUs that form the P2P clique, as PCI device IDs (vendor:device), space or
# comma separated. Default 10de:2204 = RTX 3090. Deliberately EXCLUDE cards that
# can't do switch-local P2P (e.g. an RTX 3080 = 10de:2206 on the root complex) —
# a non-P2P GPU in the visible set poisons the whole clique.
P2P_GPU_PCI_IDS="${P2P_GPU_PCI_IDS:-10de:2204}"

mapfile -t gpus < <(
    for id in ${P2P_GPU_PCI_IDS//,/ }; do
        lspci -Dn -d "$id" 2>/dev/null | awk '{print $1}'
    done
)

if [ "${#gpus[@]}" -eq 0 ]; then
    echo "no target GPU (${P2P_GPU_PCI_IDS}) present — nothing to do"
    exit 0
fi

changed=0
for gpu in "${gpus[@]}"; do
    dev=$(realpath "/sys/bus/pci/devices/$gpu" 2>/dev/null) || continue
    # Walk the sysfs ancestry upward: every parent directory named 0000:* is a
    # bridge on the path from the root complex down to this GPU.
    while [[ $dev == *0000:* ]]; do
        bdf=$(basename "$dev")
        if [[ $bdf == 0000:* ]] && setpci -s "$bdf" ECAP_ACS+0x6.w >/dev/null 2>&1; then
            cur=$(setpci -s "$bdf" ECAP_ACS+0x6.w)
            if [[ $cur != 0000 ]]; then
                setpci -s "$bdf" ECAP_ACS+0x6.w=0000
                echo "ACS redirect cleared on $bdf (was $cur)"
                changed=1
            fi
        fi
        dev=$(dirname "$dev")
    done
done

[ "$changed" -eq 0 ] && echo "no ACS redirect bits needed clearing"
exit 0
