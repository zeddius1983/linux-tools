# amdgpu_top

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top), a monitor for AMD
GPUs and APUs. It shows usage, VRAM/GTT, clocks, power and temperature, plus
per-process usage. It reads the kernel's amdgpu driver directly, so it needs no
ROCm. The latest release RPM runs in a `fedora:43` Distrobox container, with the
Mesa/Vulkan and X11 libraries its GUI needs.

## Install

```bash
tools setup amdgpu_top
```

No parameters and no `create_flags`: Distrobox already shares `/dev/dri`, which
is all amdgpu_top reads.

## What you get

| Entry | What it does |
|---|---|
| `amdgpu_top` (host `PATH`) | Terminal UI, always started with `--dark` |
| **amdgpu_top** (menu) | The terminal UI in a terminal window |
| **amdgpu_top GUI** (menu) | The graphical version (`--gui`) |

```bash
amdgpu_top                 # full terminal UI
amdgpu_top --smi           # compact nvidia-smi-style summary
amdgpu_top --list          # list detected AMD GPUs
amdgpu_top -i 1            # pick a GPU by instance number when there are several
amdgpu_top -d              # dump device info once and exit
amdgpu_top -J -n 1         # one JSON sample (-s <ms> sets the interval)
amdgpu_top --xdna          # Ryzen AI NPU (XDNA) info
```

The first command after the box has been stopped takes a few seconds while
Distrobox starts it.

## Updating

The image installs the newest GitHub release at build time, so rebuild to
update:

```bash
tools setup amdgpu_top
```

## Notes

- **No persistent state.** amdgpu_top keeps no config or data, so a rebuild loses
  nothing.
- **amd64 only:** the image pulls the release's `x86_64` RPM.
- **Per-process usage** comes from `/proc/<pid>/fdinfo`. Processes in other
  containers and on the host are visible too, because Distrobox shares the host's
  PID namespace.
