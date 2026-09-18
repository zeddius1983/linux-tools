# memtest_vulkan

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[memtest_vulkan](https://github.com/GpuZelenograd/memtest_vulkan) — a GPU memory
stress test written in Vulkan compute. It writes patterns across the card's
memory, reads them back, and reports any mismatch immediately with a bit-level
breakdown of which lines went bad. Use it to validate a memory overclock, to
confirm a suspected-faulty card, or as a burn-in after a repair.

Vendor-neutral: anything with a Vulkan 1.1 driver works — AMD, Intel, NVIDIA,
and ARM SoCs. Packaged from the upstream prebuilt Linux x86_64 binary (**v0.5.0**,
pinned) on Fedora 43, which supplies a current Mesa for the AMD (RADV) and Intel
(ANV) ICDs.

## Install

```bash
tools setup memtest_vulkan
```

Setup asks which GPU passthrough to use:

| Choice | What it does | Host prerequisite |
|---|---|---|
| **AMD / Intel** (default) | No extra flags — the `/dev/dri` access Distrobox gives every box is enough | none |
| **NVIDIA (CDI)** | Adds `--device nvidia.com/gpu=all` so the host driver's Vulkan ICD is injected | `/etc/cdi/nvidia.yaml` (below) |

Run non-interactively (scripts, `LT_SKIP_WIZARD`) and you get the **AMD / Intel**
default, which works on every host.

The flag cannot simply be applied unconditionally: on a host with no CDI spec,
`--device nvidia.com/gpu=all` makes the container fail to **start**, which then
surfaces only as `cannot find 'memtest_vulkan' inside container` on every export
lookup. Hence the question at setup time.

### NVIDIA only: generate the host CDI spec (one-time)

Required before picking **NVIDIA (CDI)**; re-run after every driver update, or
install [`nvidia-cdi-service`](../nvidia-cdi-service/README.md) to have it
regenerated at every boot:

```bash
sudo pacman -S nvidia-container-toolkit          # CachyOS / Arch
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Usage

```bash
memtest_vulkan
```

Also available from your app menu as **memtest_vulkan** (opens in a terminal).

The tool has **no option flags and no `--help`**. It is driven by the interactive
menu, by environment variables, and by the name it is invoked as. It does accept
two undocumented positional arguments — it re-execs itself as
`memtest_vulkan <index> <bytes>` to run the actual test in a worker process — but
upstream documents neither, so treat them as an implementation detail rather than
a supported interface.

On start it lists every Vulkan device and waits 10 seconds for you to type an
index, defaulting to device 1:

```
1: Bus=0xC7:00 DevId=0x1586   83GB AMD Radeon 8060S Graphics (RADV GFX1151)
2: Bus=0x00:00 DevId=0x0000   125GB llvmpipe (LLVM 21.1.8, 256 bits)
(first device will be autoselected in 10 seconds)   Override index to test:
```

It then runs a **standard 5-minute test** and stops on its own; press `Ctrl+C`
at any point to finish early, or leave it running longer for a deeper soak. A
clean run ends with:

```
memtest_vulkan: no any errors, testing PASSed.
```

Any error is printed the moment it is found, with the failing address range and
a per-bit histogram — see [upstream's annotated
example](https://github.com/GpuZelenograd/memtest_vulkan#errors_screenshot) for
how to read it.

### Stopping it: `Ctrl+C`, not the window

**`Ctrl+C` in the terminal running the test is the only reliable way to stop it.**
The test itself runs in a worker process *inside* the container, in a different
process tree from the `~/.local/bin/memtest_vulkan` wrapper you launched. Kill or
time out the wrapper — close the terminal window, `timeout 30 memtest_vulkan`,
Ctrl+C'ing a script that invoked it — and the wrapper dies while the worker keeps
going, holding its full allocation with nothing on screen to show for it.

This is the containerised form of [upstream's issue
#11](https://github.com/GpuZelenograd/memtest_vulkan/issues/11), and it is easy
to miss because a ~80 GB allocation on a unified-memory APU shows up as ordinary
RAM usage, not as a GPU process.

If you suspect one is stranded:

```bash
ps -eo pid,etime,args | awk '$3 ~ /^\/usr\/bin\/memtest/'
pkill -f '^/usr/bin/memtest_vulkan'
```

Do not script this tool with `timeout` and assume the test stopped — check.

### Exported commands

| Command | What it does |
|---|---|
| `memtest_vulkan` | The test, as above |
| `memtest_vulkan_verbose` | Same binary, verbose mode: prints the Vulkan instance version, available layers and extensions, and per-device API/driver details before the menu |

`memtest_vulkan_verbose` is a symlink, not a wrapper with a flag: the tool
switches on verbose output when it finds the string `verbose` in the name it was
invoked as. Use it when a GPU you expect is missing from the device list.

### Picking a specific GPU

Two ways, since there are no flags:

- Type the index at the menu prompt within 10 seconds.
- Point the loader at one ICD, which makes it the only device offered:

  ```bash
  VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json memtest_vulkan
  ```

  The path is resolved **inside the container**, not on the host. List what is
  available with `distrobox enter memtest_vulkan-box -- ls /usr/share/vulkan/icd.d/`.

Linux installs almost always include Mesa's `llvmpipe`, a pure-CPU Vulkan
driver. It shows up in the menu as a device with a very large "memory" size and
is never what you want to test — testing it measures system RAM through a
software rasteriser at a fraction of the speed.

## Storage

No persistent state, with one exception: **every run writes `memtest_vulkan.log`
into the current working directory.** Launched from a terminal that is wherever
you are; launched from the app menu it is `$HOME`. This is upstream behaviour and
is deliberately left alone here so log paths match every other memtest_vulkan
install. Run it from a scratch directory if you would rather keep `$HOME` clean:

```bash
mkdir -p ~/gpu-logs && cd ~/gpu-logs && memtest_vulkan
```

The log holds the same text as the console, plus timestamps, and is written by
both the console and worker processes.

## Notes

- **The version is pinned to v0.5.0** rather than offered as a wizard picker.
  Upstream has published three releases in four years; the other two use older
  asset-naming schemes, and the `support` release contains only Windows DLLs.
  Bump `MEMTEST_VERSION` in the `Dockerfile` to move.
- **It tests the memory the driver reports, not the physical module.** On an APU
  or an iGPU with unified memory (e.g. Strix Halo, which reports ~83 GB), what
  gets tested is a GTT allocation out of system RAM. That is a genuine test of
  that memory path, but a `PASS` there says nothing about discrete VRAM, and the
  run competes with everything else on the machine for RAM.
- **The desktop shares the GPU you are testing.** A full-memory test on the card
  driving your display can make the session stutter. Harmless, but expect it.
- **NVIDIA GPUs need the CDI choice at setup.** Without it the box has no NVIDIA
  ICD and the card simply does not appear in the device list — no error, just a
  shorter menu. `memtest_vulkan_verbose` makes this obvious.
- **Two cosmetic warnings in verbose mode** are expected and harmless: a
  `Layer 0 does not exist` line (no validation layers installed — the tool
  retries without them) and a `Received return code -9 ... libvulkan_dzn.so`
  line (Mesa's Dozen/D3D12 ICD, which has no Linux hardware to bind to and is
  skipped).
- `vulkaninfo` is in the image for diagnostics but deliberately **not** exported,
  so it cannot shadow a host copy in `~/.local/bin`. Reach it with
  `distrobox enter memtest_vulkan-box -- vulkaninfo --summary`.
