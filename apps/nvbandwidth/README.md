# nvbandwidth

[NVIDIA nvbandwidth](https://github.com/NVIDIA/nvbandwidth) — a tool for
measuring memory-copy bandwidth across host↔device and device↔device (NVLink /
PCIe) links on NVIDIA GPUs. It runs a battery of copy-engine and kernel-driven
benchmarks and reports per-link and aggregate GB/s.

Packaged as a **build-environment container**: the CUDA toolkit compiles the
binary at image-build time, and the host NVIDIA driver is injected at runtime
via [CDI](https://github.com/cncf-tags/container-device-interface) so the tool
can talk to the real GPUs.

## Host prerequisite (one-time): NVIDIA CDI

Passthrough uses `--device nvidia.com/gpu=all`, which requires a CDI spec on the
host. Generate it once (re-run after every driver update):

```bash
sudo pacman -S nvidia-container-toolkit          # CachyOS / Arch
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Without `/etc/cdi/nvidia.yaml`, `tools setup` fails at container-create time with
podman's `no such device nvidia.com/gpu=all`. Do **not** use
`distrobox create --nvidia` on this host — it hangs in a driver-remount loop.

## Install

```bash
tools setup nvbandwidth
```

## Usage

Run with no arguments to execute the full default test suite across all detected
GPUs:

```bash
nvbandwidth
```

Useful flags (`nvbandwidth -h` for the full list):

| Flag | Purpose |
|---|---|
| `-l`, `--list` | List all available testcases and detected devices |
| `-t NAME`, `--testcase NAME` | Run a specific testcase by name or index (repeatable) |
| `-b MiB`, `--bufferSize MiB` | Copy buffer size (default 512) |
| `-i N`, `--testSamples N` | Iterations per measurement (default 3) |
| `-F FORMAT`, `--format FORMAT` | Output format: `text` (default), `json`, or `perf` |
| `--pair UUID1 UUID2` | Restrict to a single GPU pair |

Examples:

```bash
nvbandwidth -l                                   # list testcases + GPUs
nvbandwidth -t device_to_device_memcpy_read_ce   # one NVLink read test
nvbandwidth -F json > bw.json                    # machine-readable output
```

## P2P / PCIe-switch testcase cheat-sheet

The `device_to_device_*` testcases are the peer-to-peer path — they call
`cudaDeviceEnablePeerAccess` and copy GPU→GPU over whatever transport the driver
picks (NVLink, or PCIe through a switch/bifurcation board like a Broadcom
PEX88096). This is the right tool to validate that a switch board actually
delivers local peer routing. `_ce` = copy-engine initiated, `_sm` = copy-kernel
initiated, `_tma` = TMA (Hopper `sm_90`+ only — unsupported on Ampere/3090).

| Testcase | What it tells you |
|---|---|
| `device_to_device_memcpy_read_ce` | Unidirectional P2P read, copy engine |
| `device_to_device_memcpy_write_ce` | Unidirectional P2P write, copy engine |
| `device_to_device_memcpy_read_sm` | Unidirectional P2P read, SM kernel |
| `device_to_device_memcpy_write_sm` | Unidirectional P2P write, SM kernel |
| `device_to_device_bidirectional_memcpy_read_ce` | Bidirectional P2P read, CE (sum of both dirs) |
| `device_to_device_bidirectional_memcpy_write_ce` | Bidirectional P2P write, CE |
| `device_to_device_bidirectional_memcpy_read_sm` | Bidirectional P2P read, SM |
| `device_to_device_bidirectional_memcpy_write_sm` | Bidirectional P2P write, SM |
| `device_to_device_latency_sm` | P2P round-trip latency, SM |
| `host_to_device_memcpy_ce` / `device_to_host_memcpy_ce` | PCIe host↔device baseline to compare P2P against |

```bash
# Run every P2P bandwidth test in one shot (prefix match):
nvbandwidth -p device_to_device_memcpy
# A single directed read test:
nvbandwidth -t device_to_device_memcpy_read_ce
```

**Ground-truth the transport first.** Before trusting a P2P number, confirm what
link nvbandwidth is actually exercising:

```bash
distrobox-host-exec nvidia-smi topo -m
```

`NV#` = NVLink, `PIX`/`PXB` = through a PCIe switch (this is your PEX88096 path),
`SYS` = up through the CPU root complex (no local switch routing).

**Reading the results — two things that specifically bite consumer GPUs:**

- **GeForce PCIe P2P is disabled in the stock driver.** On RTX 3090/4090,
  `cudaDeviceCanAccessPeer` returns 0 for the PCIe path, so `device_to_device_*`
  falls back to host-staged copies regardless of the switch board — the numbers
  collapse toward (or below) the host↔device baseline. Stock-driver P2P on these
  cards only works over an **NVLink bridge**. To get real PCIe P2P you either need
  datacenter/pro silicon (A100/H100, RTX A-series) or a **patched open kernel
  module** — see [Enabling PCIe P2P on consumer GPUs](#enabling-pcie-p2p-on-consumer-gpus) below.
- **PCIe ACS defeats switch P2P even where P2P is enabled.** ACS on the switch
  downstream ports / root ports redirects peer TLPs up to the root complex. To
  benefit from the PEX88096's local routing, disable ACS (BIOS, or Linux
  `pcie_acs_override=downstream,multifunction`) — at the usual IOMMU-isolation
  cost. A good before/after: run `nvbandwidth -p device_to_device_memcpy` with
  ACS on vs off and watch the bidirectional numbers.

## Enabling PCIe P2P on consumer GPUs

Stock NVIDIA drivers disable PCIe P2P on GeForce cards, so `device_to_device_*`
tests are **waived** (`P2P not supported between any devices`) on a bridge-less
consumer multi-GPU box. A patched **open kernel module** re-enables it by doing
GPU→GPU DMA directly into the peer's BAR1 window.

This is a **host** operation — it replaces the host's NVIDIA kernel modules.
Nothing in the container changes: CDI injects whatever driver the host has loaded,
so after patching + reboot you re-run `nvbandwidth` in the box with **no image
rebuild**.

### Which fork

- **[`aikitoria/open-gpu-kernel-modules`](https://github.com/aikitoria/open-gpu-kernel-modules)**
  — preferred. Its `master` branch tracks specific driver versions (e.g.
  **610.43.03**) and explicitly supports **RTX 3090 (PCIe BAR1 when no NVLink),
  4090, and 5090**. The kernel module version must match the installed userspace
  driver exactly, so pick the branch matching your driver.
- **[`tinygrad/open-gpu-kernel-modules`](https://github.com/tinygrad/open-gpu-kernel-modules)**
  — the original approach, but branches target older drivers and it was validated
  on the 4090; 3090 support is unreliable. Prefer the aikitoria fork if it has a
  branch for your driver version.

> **Do not use the fork's `main` branch** — that's the unmodified upstream
> snapshot with no P2P patch. Use the version-named `master`/branch.

### Steps (host)

1. **Put the IOMMU in passthrough mode.** *Hard requirement* — if the IOMMU is
   translating rather than passthrough, P2P DMA goes through its page tables and
   transfers **fail**. Add to your kernel cmdline:
   - `amd_iommu=on iommu=pt` (AMD CPU) or `intel_iommu=on iommu=pt` (Intel).
   - Adapt to your bootloader — CachyOS is usually **not** GRUB:
     - **GRUB:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`, then `sudo update-grub`.
     - **systemd-boot:** `/etc/kernel/cmdline` (or the entry's `options` line), then regenerate.
     - **Limine:** `/etc/default/limine` or the cmdline in `/boot/limine.conf`.
   - Verify after reboot: `cat /proc/cmdline` shows the flags.
   - **Security note:** `iommu=pt` weakens DMA isolation. Fine on a trusted host;
     avoid on anything running untrusted code or devices.
2. **Confirm the matching userspace driver is installed** (the fork patches only
   the kernel modules; the driver version must match the branch).
3. **Build + install** (install kernel headers matching your running kernel first,
   e.g. `linux-cachyos-headers`):
   ```bash
   git clone https://github.com/aikitoria/open-gpu-kernel-modules
   cd open-gpu-kernel-modules      # version-named branch, NOT `main`
   sudo ./install.sh
   ```
4. **Reboot.**

### Verify

```bash
nvbandwidth -p device_to_device_memcpy   # should now report GB/s, not "P2P not supported"
```

### Gotchas

- **Package updates clobber it.** A pacman `nvidia`/`nvidia-open` upgrade
  reinstalls stock kernel modules and silently disables P2P. Re-run `install.sh`
  (and re-check the version still matches) after any driver update — or pin the
  driver package.
- **ACS still applies.** If P2P works but is slow, disable ACS (see the cheat-sheet
  above) — it forces peer traffic through the root complex regardless of the patch.
- **Resizable BAR / Above-4G Decoding** (BIOS) is recommended so the full VRAM is
  exposed over BAR1 rather than a small aperture.
- **NVLink vs PCIe selection:** with a bridge present the driver prefers NVLink;
  to force the PCIe BAR1 path for testing, add
  `options nvidia NVreg_RegistryDwords="RMForceP2PType=1"` to
  `/etc/modprobe.d/nvidia.conf`.

### Real-world reference: 7-GPU PCIe-switch build

A [detailed LocalLLaMA writeup by u/panchovix](https://www.reddit.com/r/LocalLLaMA/comments/1qeimyi/7_gpus_at_x16_50_and_40_on_am5_with_gen54/)
runs 7 mixed GPUs (2×5090, 2×4090, 3090, A6000, A40) on an AM5 board using the
aikitoria P2P driver plus PCIe switches, including the **Broadcom/PLX PEX88096**
(a 96-lane PCIe 4.0 switch, ~$400 on AliExpress; x16 upstream from the slot, 10
SlimSAS downstream ports, dip-switch selectable `5×x16` / `10×x8` / `20×x4`,
plug-and-play). Key confirmations relevant to a 2×3090 box:

- **Same-gen P2P through the switch bypasses the CPU root complex and beats the
  uplink.** Reported bidirectional `p2pBandwidthLatencyTest` figures with the
  driver enabled: 5090↔5090 **110 GB/s** (via a PCIe 5.0 switch), and the
  4090 pair and the **Ampere trio (A40/A6000/3090) ~52 GB/s** via the PEX88096.
  So two 3090s on a PEX88096 with the patched driver should land in that
  ~50 GB/s bidirectional range — versus the *waived* result you get today.
- **P2P only accelerates same-generation pairs.** Cross-gen (e.g. 5090↔4090,
  4090↔3090) still works but drops to ~15 GB/s (≈PCIe 4.0 x8) with no P2P speedup.
- **`nvidia-smi topo -m` legend in practice:** same-switch same-gen pairs show
  `PIX` (single bridge, no root complex); pairs reached across a *cascaded*
  second switch show `PXB` (multiple bridges); no switch at all shows `PHB`.
- **IOMMU must be passthrough.** A commenter saw bandwidth collapse with the
  IOMMU translating — reinforcing the `iommu=pt` requirement above.
- **NCCL won't P2P across switches by default.** It reports
  `intraNodeP2pSupport 0` and silently routes peer traffic through the CPU; the
  workaround is a hand-edited `NCCL_TOPO_FILE` that presents the GPUs as
  same-switch. (Relevant for vLLM/training, not for llama.cpp.)
- **Where it actually moved the needle:** a 2×5090 SDXL finetune went 24 h
  (1 GPU) → 13 h (P2P, x8/x8) → **8 h (P2P, x16/x16 via switch)**. For inference,
  prompt-processing (PP) scaled strongly with PCIe width while token-generation
  (TG) barely moved.

## Notes

- **NVLink results require ≥2 NVLink-connected GPUs.** On a single-GPU box the
  device↔device NVLink testcases report as unsupported/skipped; the host↔device
  (PCIe) tests still run and are useful on their own.
- The binary is compiled for CUDA architectures `75;80;86;89;90` (Turing →
  Hopper). To target a newer/older GPU, edit `CMAKE_CUDA_ARCHITECTURES` in the
  Dockerfile and re-run `tools setup nvbandwidth`.
- No persistent storage — the tool is stateless; output goes to stdout.
