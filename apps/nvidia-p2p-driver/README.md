# nvidia-p2p-driver

Builds and installs the **aikitoria GeForce-P2P-patched NVIDIA open kernel modules**
so PCIe peer-to-peer (GPU↔GPU DMA) works on consumer cards (RTX 3090/4090…), which
the stock driver disables.

Uses the repo's **build-environment-container** pattern (like `corefreq`): the module
is compiled inside a container against your running host kernel, then the built `.ko`
files are installed onto the host. The container is a build tool only — nothing runs
in it at boot.

## Why a container per host family

An out-of-tree kernel module must be built with a toolchain matching the one that
built the host kernel:

- **`Dockerfile.arch`** (this host): CachyOS/Arch kernels are **Clang + ThinLTO**, so
  the module is built with the LLVM toolchain (`clang`/`lld`/`llvm`).
- **`Dockerfile.ubuntu`**: Debian/Ubuntu GCC-built kernels.

`tools build` auto-selects via the host's distro family. **You cannot build for a
CachyOS kernel from an Ubuntu/GCC container** — that's the whole reason for the split.

## Requirements

- Matching **kernel headers/build tree** on the host (`/lib/modules/$(uname -r)/build`):
  - Arch/CachyOS: `pacman -S linux-cachyos-headers` (match your kernel)
  - Debian/Ubuntu: `apt install linux-headers-$(uname -r)`
  - Fedora: `dnf install kernel-devel-$(uname -r)`
- The host's installed **nvidia-open driver version must match the fork's pin**
  (`610.43.03` by default). `nvidia-p2p-build` refuses to build on a mismatch.
- For actual P2P bandwidth you also want:
  - `nvidia-p2p-acs` — clears PCIe ACS redirect (for switch-local P2P), and
  - `iommu=pt` on the kernel cmdline.

## Install

```bash
tools setup nvidia-p2p-driver     # builds the Arch/Ubuntu build box
nvidia-p2p-build                  # compile + install modules onto the host
# reboot to load the patched module (the live driver can't be hot-swapped)
```

`nvidia-p2p-build`:
1. Builds `nvidia`, `nvidia-modeset`, `nvidia-drm`, `nvidia-uvm` (+ peermem) against
   your running kernel (auto-uses `LLVM=1` on a Clang kernel).
2. Stages the `.ko`s to `~/.local/nvidia-p2p/`, then installs them to
   `/lib/modules/<kver>/updates/` on the host via `distrobox-host-exec sudo`,
   runs `depmod`, and regenerates the initramfs (`mkinitcpio`/`dracut`/`update-initramfs`).
3. Tells you to reboot.

## Durability (important)

There is **no automatic rebuild**. A kernel or nvidia-open upgrade orphans the patched
module (the new kernel ships only the stock module, and the initramfs bakes it in), so
P2P silently reverts. After any such upgrade:

```bash
nvidia-p2p-build && sudo reboot
```

If the installed driver moves **past** the fork's pinned version, `nvidia-p2p-build`
stops and tells you — bump `P2P_BRANCH` (below) and rebuild the box first.

## Tracking a different driver version

The fork branch is a build arg. To target another driver:

```bash
# edit apps/nvidia-p2p-driver/Dockerfile.arch → ARG P2P_BRANCH=<branch>
tools setup nvidia-p2p-driver
# or one-off:
distrobox-host-exec podman build --build-arg P2P_BRANCH=<branch> \
    -f Dockerfile.arch -t linux-tools/nvidia-p2p-driver:latest .
```

## Storage / files

| Path | What |
|---|---|
| `~/.local/nvidia-p2p/*.ko` | built modules (staging, shared home) |
| `/lib/modules/<kver>/updates/nvidia*.ko` | installed patched modules (host) |

## Verify (after reboot)

```bash
cat /sys/module/nvidia/srcversion        # = the patched build's srcversion
# with nvidia-p2p-acs applied and only P2P GPUs visible:
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=0,1 \
  nvbandwidth -t device_to_device_memcpy_read_ce   # ~26 GB/s on 2×3090 over a switch
```

## Related

- `nvidia-p2p-acs` — the PCIe ACS half of consumer-GPU P2P (required for switch P2P).
- `nvbandwidth` — measure P2P bandwidth; `nvtop` — monitor GPUs.
- Upstream fork: <https://github.com/aikitoria/open-gpu-kernel-modules>
