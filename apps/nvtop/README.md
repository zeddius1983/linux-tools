# nvtop

[nvtop](https://github.com/Syllo/nvtop) — an `htop`-like TUI for GPUs. It shows
per-GPU utilisation, memory, temperature, power, clocks and a scrolling history
graph, plus a live per-process table of who is using the GPU. It is
**multi-vendor**: NVIDIA, AMD (amdgpu), Intel, and more, all in one view.

Packaged from Fedora's `nvtop` package (every backend enabled). AMD/Intel
monitoring works through the `/dev/dri` + `/sys` access Distrobox exposes by
default; NVIDIA monitoring uses NVML from the host driver, injected at runtime
via [CDI](https://github.com/cncf-tags/container-device-interface).

## Host prerequisite (one-time): NVIDIA CDI

The box is created with `--device nvidia.com/gpu=all`, which requires a CDI spec
on the host. Generate it once (re-run after every driver update):

```bash
sudo pacman -S nvidia-container-toolkit          # CachyOS / Arch
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Without `/etc/cdi/nvidia.yaml`, `tools setup` fails at container-create time with
podman's `no such device nvidia.com/gpu=all`. Do **not** use
`distrobox create --nvidia` on this host — it hangs in a driver-remount loop.

> On an AMD/Intel-only machine (no NVIDIA driver) you don't need NVIDIA at all —
> drop the `apps/nvtop/create_flags` file so no CDI device is requested; the
> AMD/Intel backends still work via the default device passthrough.

## Install

```bash
tools setup nvtop
```

## Usage

Launch the TUI (also available from your app menu as **nvtop**):

```bash
nvtop
```

Useful keys inside nvtop:

| Key | Action |
|---|---|
| `F2` / `Setup` | Options menu (choose visible columns, colours, chart layout) |
| `F6` / `Sort` | Pick the process-table sort column |
| `F9` / `Kill` | Send a signal to the selected process |
| `F10` / `Quit` (or `q`) | Exit |
| `+` / `-` | Expand / collapse a GPU's process list |
| `↑` / `↓` | Move the process-table selection |

Useful flags (`nvtop -h` for the full list):

| Flag | Purpose |
|---|---|
| `-d N`, `--delay N` | Refresh every N tenths of a second (e.g. `-d 5` = 0.5 s) |
| `-C`, `--no-color` | Monochrome output |
| `-p`, `--no-plot` | Hide the history graphs |
| `-r`, `--reverse-abs` | Reverse the process sort order |
| `-s`, `--gpu-select` | Comma-separated list of GPU ids to show |

## Notes

- **Multi-vendor in one view.** Unlike `nvidia-smi` / `amdgpu_top`, nvtop shows
  every detected GPU side by side. This box's sibling apps `amdgpu_top` and
  `nvbandwidth` remain useful for vendor-specific deep dives.
- **NVIDIA support is via NVML dlopen.** nvtop loads `libnvidia-ml.so.1` at
  runtime; it comes from the host driver through CDI. If nvtop starts but shows
  no NVIDIA GPU, confirm the CDI spec exists and matches the current driver
  (regenerate with `nvidia-ctk cdi generate` after a driver update).
- No persistent storage — nvtop is stateless; its config (if you save one from
  the Setup menu) lives under `~/.config/nvtop/` on the shared home.
