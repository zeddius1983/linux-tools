# nvidia-p2p-acs

Boot-time systemd service that disables **PCIe ACS redirect** on the bridges above
your P2P GPUs, so a PCIe switch routes GPU↔GPU peer traffic directly instead of
bouncing it up to the root complex.

This is a **host-only** app: it installs a systemd unit + a helper script straight
to the host and builds **no container**.

## Why you want this

For GPU-to-GPU P2P over a PCIe switch (e.g. 2×RTX 3090 behind a Broadcom PEX880xx),
the switch must forward peer TLPs directly between its downstream ports. PCIe
**Access Control Services (ACS)** "P2P Request/Completion Redirect" forces those
transactions *up to the root complex* instead — which collapses bandwidth to
~1 GB/s and, with the IOMMU on, silently corrupts the data.

The catch: with `intel_iommu=on` (or `amd_iommu=on`), the kernel **re-enables ACS
redirect on every boot**, so P2P works after a manual fix but breaks again on the
next reboot. This service re-applies the fix at boot, permanently.

It finds the target GPUs by PCI ID, walks each one's PCIe ancestry, and zeroes the
ACS control register on every ACS-capable parent bridge. Because it resolves the
bridges live from the topology, it is immune to PCI **renumbering** (cards
added/removed/moved under the switch, BIOS changes) — no hardcoded bus addresses.

## Requirements

- **pciutils** (`setpci`, `lspci`) — auto-installed by `install.sh` if missing
  (apt/dnf/pacman/zypper).
- systemd.
- **IOMMU in passthrough mode** (`iommu=pt`) for full P2P bandwidth.
- A P2P-capable GPU setup — pairs with `nvidia-p2p-driver` (the GeForce P2P kernel
  patch) on consumer cards.

## Configuration

The target GPUs default to `10de:2204` (RTX 3090). To target a different clique,
edit the unit after install and reload:

```bash
sudoedit /etc/systemd/system/nvidia-p2p-acs.service   # Environment=P2P_GPU_PCI_IDS=...
sudo systemctl daemon-reload && sudo systemctl restart nvidia-p2p-acs
```

Find your GPU IDs with `lspci -nn | grep -i nvidia` (the `[10de:xxxx]` part).

> **Important:** only include GPUs that can actually do switch-local P2P. A
> non-P2P card in the set (e.g. an RTX 3080 on the CPU root complex) poisons the
> whole clique and drags the good pair down too.

## Install

```bash
tools setup nvidia-p2p-acs
```

Runs `install.sh` on the host: ensures pciutils, installs the script to
`/usr/local/sbin`, the unit to `/etc/systemd/system`, `enable --now`. Prompts for sudo.

## Remove

```bash
tools rm nvidia-p2p-acs
```

## Files

| Path | What |
|---|---|
| `/usr/local/sbin/nvidia-p2p-acs.sh` | the ACS-clearing script |
| `/etc/systemd/system/nvidia-p2p-acs.service` | the boot unit |

## Verify

```bash
journalctl -u nvidia-p2p-acs -b          # lists bridges it cleared
# after a reboot, the switch bridges above the GPUs should read 0000:
for b in $(lspci -D | grep -i bridge | awk '{print $1}'); do
  v=$(sudo setpci -s "$b" ECAP_ACS+0x6.w 2>/dev/null) && echo "$b $v"
done
# authoritative P2P bandwidth (exclude non-P2P GPUs):
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=0,1 nvbandwidth -t device_to_device_memcpy_read_ce
```

## Related

- `nvidia-p2p-driver` — build/install the GeForce P2P-patched kernel module (the
  other half of consumer-GPU P2P).
- `nvidia-cdi-regenerate` — keep the CDI spec fresh for GPU passthrough.
- `nvbandwidth` — measure P2P bandwidth authoritatively.
