# gpu-unlock

<p>
  <img alt="Ubuntu: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[gpu-unlock](https://github.com/Zagitta/gpu-unlock) unlocks tensor arithmetic
throughput on supported NVIDIA Ampere GPUs. The `gpu_unlock` shell command builds
and installs the early-boot kernel module, enables/disables it for the next boot,
and runs a bundled CUDA PyTorch benchmark.

Compilation, firmware generation and PyTorch live in a Docker/Podman image,
managed as `gpu-unlock-box` through Distrobox. The host gets only the compiled
module, generated firmware and boot configuration. There is no host compiler,
Python, PyTorch or DKMS dependency. Host module builds must be repeated after
kernel upgrades.

## Requirements

- An x86_64 host with Distrobox and Podman/Docker, sudo, `kmod`, and kernel headers
  matching each kernel you intend to boot. The host handoff also uses standard
  Bash, GNU tar and coreutils (`sha256sum`, `install`, `mktemp`).
- Arch/CachyOS or Ubuntu/Debian/Mint are the primary build families. The image
  chooses the matching toolchain automatically. Boot integration supports
  mkinitcpio, initramfs-tools and dracut; other distro/kernel combinations still
  need validation.
- A supported GPU. At the pinned revision the active PCI table contains selected
  GA102/GA103/GA104/GA106 cards, including RTX 3080/3090/3090 Ti IDs. GA100 and RTX
  4090 appear in upstream documentation but are absent from that active table.
  Compare `lspci -Dnn` with the [pinned device table](https://github.com/Zagitta/gpu-unlock/blob/6081407b312aa3139a2bed62bdda354f4ffddc1d/kernel/gpu_unlock/recipes.c).
- NVIDIA Container Toolkit and a working `/etc/cdi/nvidia.yaml`, for the bundled
  CUDA benchmark. The box requests `--device nvidia.com/gpu=all`.
- `flatpak` on the host and a working `distrobox-host-exec`, as documented in
  `CLAUDE.md`, for installing artifacts and changing boot settings from the box.
- With enforced Secure Boot signatures, the compiled module must be signed with
  an enrolled key before loading. Automatic key enrollment/signing is not included.

Install matching headers on the host, for example:

```bash
# Ubuntu/Mint (use the intended kernel version if not running it yet):
# sudo apt install linux-headers-$(uname -r)
# CachyOS (match your kernel, e.g. linux-cachyos or linux-cachyos-lts):
# sudo pacman -S linux-cachyos-headers
```

If you installed the earlier native-package prototype, first remove
`gpu-unlock-dkms` and `gpu-unlock-firmware`, remove any `gpu_unlock.targets=`
kernel command-line option, and reboot. This controller refuses those conflicting
configurations so `off` cannot silently leave another opt-in active.

## Install and shell commands

```bash
tools setup gpu-unlock
gpu_unlock install           # build against running host kernel, install with sudo
gpu_unlock status
```

`tools setup` builds the image and exports `gpu_unlock` to `~/.local/bin`. Image
builds need no GPU: they clone upstream commit `6081407b312aa3139a2bed62bdda354f4ffddc1d`
(1.1.0), verify the pinned NVIDIA inputs and generate firmware. Python 3.12.12 and
PyTorch 2.8.0 with CUDA 12.8 are bundled for reproducible before/after runs. The
first image build downloads several GB for the CUDA PyTorch environment.

The Arch image includes Mesa before NVIDIA CDI is attached. This prevents a
first-start package conflict over `libGLX_indirect.so.0`. Setup shows Distrobox
initialization errors and stops if the box cannot start or the command cannot
be exported. After repairing a startup problem, `tools export gpu-unlock`
retries export without reinstalling the host module.

`gpu_unlock install` compiles inside the container against read-only host headers,
then installs artifacts on the host and regenerates its initramfs. A new install
starts disabled. Reinstalling preserves the existing on/off request.

The initramfs backend is recorded on the host and reused for every toggle and
removal. A read-only host preflight selects the backend before compilation or a
sudo prompt. Auto-selection uses an active configured Limine hook, an explicit
`kernel-install` generator setting, or a single available tool. CachyOS's
`update-initramfs` compatibility wrapper is not treated as initramfs-tools.
If multiple independent tools are installed, or generator drop-ins
make selection ambiguous, setup refuses to guess. Select the tool that actually
builds your boot image, for example:

```bash
gpu_unlock install --initramfs dracut
# Other choices: --initramfs mkinitcpio, --initramfs update-initramfs
# CachyOS with an active limine-mkinitcpio hook:
gpu_unlock install --initramfs mkinitcpio
```

`status` prints the recorded backend alongside the next-boot request. Installing
mkinitcpio on a host that boots dracut images does not change the selected backend.
To change an already recorded backend, uninstall the old integration first and
reinstall with the correct explicit option.

Privileged installation captures one archive of the helper and payload, fixes
its SHA256 digest before the sudo password prompt, and verifies a private
root-owned copy before extraction or execution. The helper and module are read
only from that verified snapshot. Installed firmware/license files are root-owned
0644 under app-specific directories, whose mode is 0755; shared parent directory
ownership and permissions are preserved.
An existing shared parent that is user-owned or group/world-writable is refused
until its system metadata is repaired.

Build workspaces and transfer archives are removed on success and failure.
Use `gpu_unlock install --keep-build` to retain a build for troubleshooting.
Workspaces left by older versions are not deleted automatically.

```bash
gpu_unlock install 6.8.0-99-generic  # optional explicit installed kernel version
gpu_unlock on                       # enable all supported cards for next boot
gpu_unlock on 0000:21:00.0,0000:22:00.0  # or select full PCI addresses
gpu_unlock off                      # disable for next boot
gpu_unlock status                   # next-boot setting + current request + logs
```

**Reboot after `on` or `off`.** These commands write a managed modprobe option
file and regenerate boot images. They do not reset a live display GPU or reboot
without you. Bootloader edits are unnecessary for a new installation. A failed
image rebuild restores the previous option and attempts to rebuild again;
resolve any reported rebuild errors before rebooting.

With mkinitcpio, the drop-in places `gpu_unlock` immediately before `nvidia` and
includes its option file. When an active Limine generation hook is detected,
regeneration uses `limine-mkinitcpio` (or `limine-dracut` for that backend) so it
also updates boot entries and works without mkinitcpio presets. Explicit `-c` / preset `_config` configurations ignore
mkinitcpio drop-ins: include this app's drop-in from the custom config, or add the
same MODULES ordering and FILES entry yourself. The initramfs-tools hook includes
the module/firmware/options and loads it in init-top before udev. The dracut module
loads it in pre-udev. Kernels without a compiled module are skipped; run
`gpu_unlock install KERNEL` before booting a new kernel to retain the unlock.
If your dracut configuration restricts the module list explicitly, include
`linux-tools-gpu-unlock` in that list for kernels with a compiled module.

## What it changes

Before NVIDIA initializes a selected GPU, upstream's V67/PLM firmware sequence
permits protected feature writes, sets throughput selectors SS0=`0x88888888` and
SS1=`0x8`, verifies them, performs a PCIe Function Level Reset, then verifies the
handoff to the normal NVIDIA driver. It does not flash the VBIOS or replace the
NVIDIA driver. Loading the module after NVIDIA has bound a card cannot perform
the boot-time unlock.

The intended gain is tensor matrix arithmetic, especially FP16/BF16 with FP32
accumulation. It does not add VRAM, PCIe/NVLink bandwidth or GPU peer-to-peer
support. This is separate from `nvidia-p2p-driver` and `nvidia-acs-service`.
Quantized decoding or other memory-bound workloads may improve much less than
dense matrix multiplication. Upstream attempts to restore the selectors after
suspend to RAM; hibernation is not covered.

## Benchmark before and after

The PyTorch benchmark is already in the box and runs through the exported command.
A normal newly installed system is still locked, so record a baseline first:

```bash
gpu_unlock benchmark --save before.json
# For a specific GPU (find its UUID with nvidia-smi -L):
gpu_unlock benchmark --device GPU-... --save before.json

gpu_unlock on
# Reboot, then verify and run with identical arguments:
gpu_unlock status
gpu_unlock benchmark --save after.json
gpu_unlock compare before.json after.json

# To return to a locked baseline:
gpu_unlock off
# Reboot before benchmarking again.
```

Use a full shutdown/power-on between states if settings surviving a warm reboot
could affect the comparison. `status` reports the module's load-time targets;
look for each selected PCI address reporting `gpu_unlock: unlocked` and a
successful handoff in the kernel log. A module being loaded, or `on` being
configured for next boot, does not establish that the current GPU was unlocked.

Defaults: dense 8192×8192 FP16, BF16 and TF32 matrix multiplication; 20 warm-ups
per dtype, then five samples of 50 operations. `--size 4096`, `--samples 5` and
`--iterations 50` adjust the run. CUDA events time execution with synchronization;
allocations, transfers and numerical checks are outside the timed regions.
Reduced-precision FP16/BF16 reductions are disabled. TF32 uses FP32 inputs with
TF32 math enabled. These are practical PyTorch/cuBLAS results, not an exact
reproduction of upstream's published benchmark.

The command prints median milliseconds and dense TFLOPS (`2*N^3/time`). `--save`
writes JSON with all sample timings, GPU/software metadata, driver/power limit
when `nvidia-smi` is available, current boot request,
a full-output finite check and an 8×8 output spot check against CPU FP64 using
all reduction terms. Compare numerical errors as well as speed; the spot check
is not an exhaustive correctness test. `compare` rejects mismatched GPU/software,
kernel, driver/power metadata or benchmark settings and prints TFLOPS changes and speedup factors.

Keep the same GPU, driver, power limit, cooling, software and background workload.
Monitor with `nvidia-smi -l 1` and check `journalctl -k -b` for NVIDIA Xid errors.
Repeat disabled/enabled/disabled if changes are small. Also measure the real app:
LLM prompt tokens/s and generation tokens/s separately, warm ComfyUI generation
time, or steady-state training step time. `nvbandwidth` measures transfers and
is not the primary benchmark for this arithmetic unlock.

## Remove

```bash
gpu_unlock uninstall          # remove host artifacts and rebuild boot images
# For an older install with no recorded backend and several tools installed:
# gpu_unlock uninstall --initramfs dracut
# Reboot to clear the current GPU state.
tools rm gpu-unlock           # remove the box and exported command
```

Run `uninstall` before removing the box. `tools rm` follows the standard container
lifecycle and does not uninstall host modules. No NVIDIA driver packages are
removed. Legacy kernel options or separate DKMS packages do not block removal;
they are reported for you to manage separately, and firmware used by a separate
DKMS installation is preserved. Benchmark reports and explicitly retained builds
are kept.

## Files and persistence

| Path | Contents |
|---|---|
| `/opt/gpu-unlock-src`, `/opt/gpu-unlock-payload` in the image | Pinned source and generated firmware/licensing |
| `/opt/gpu-unlock-venv` in the image | Bundled CUDA PyTorch environment |
| `${XDG_DATA_HOME:-~/.local/share}/gpu-unlock/builds/` | Temporary build workspaces; removed unless `--keep-build` is set |
| `${XDG_DATA_HOME:-~/.local/share}/gpu-unlock/transfers/` | Temporary data archives; removed after each privileged operation |
| `/var/tmp/linux-tools-gpu-unlock.*` | Private root-owned verified snapshots, removed after each privileged operation |
| `/lib/modules/KERNEL/updates/linux-tools-gpu-unlock/gpu_unlock.ko` | Host module, built separately for each kernel |
| `/usr/lib/firmware/gpu-unlock/`, `/usr/share/licenses/gpu-unlock*` | Generated firmware and license notices |
| `/etc/modprobe.d/zz-linux-tools-gpu-unlock.conf` | Managed next-boot targets; empty means off |
| `/var/lib/linux-tools/gpu-unlock/kernels/` | Installed-kernel markers |
| `/var/lib/linux-tools/gpu-unlock/initramfs-tool` | Explicitly selected or detected backend, reused for regeneration/removal |
| `/etc/mkinitcpio.conf.d/zz-linux-tools-gpu-unlock.conf` | mkinitcpio integration when applicable |
| `/etc/initramfs-tools/hooks/linux-tools-gpu-unlock`, `/etc/initramfs-tools/scripts/init-top/linux-tools-gpu-unlock` | initramfs-tools integration when applicable |
| `/usr/lib/dracut/modules.d/01linux-tools-gpu-unlock/` | dracut integration when applicable |
| Paths supplied to `benchmark --save` | Before/after JSON reports in shared home |

Boot and numerical correctness still need validation on each supported GPU/host
combination; compatibility badges remain untested until those runs succeed.
The Arch image, a CachyOS kernel-module build, real dracut image generation in a
disposable container, and the bundled benchmark on an RTX 3080 have been checked.
The unlock itself has not yet been enabled and verified across a host reboot.
