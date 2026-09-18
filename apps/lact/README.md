# lact

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[LACT](https://github.com/ilya-zlobintsev/LACT) — Linux GPU Control Application.
A GTK4 app plus a system daemon for controlling **AMD, NVIDIA and Intel** GPUs:
power caps, fan curves, clock and voltage offsets, power states, settings
profiles that activate per-process, historical charts, and a CSV/OpenTelemetry
metrics export.

## This one installs on the host, not in a container

Unlike most apps here, `lact` is a **host-only install** — no image, no box. Its
daemon (`lactd`) runs as root and writes GPU control files under
`/sys/class/drm/*/device/`, which a rootless Podman container cannot do
regardless of `--privileged` (the same limitation that stops `insmod` working in
[`corefreq`](../corefreq/README.md)). Upstream's own container image is
daemon-plus-CLI only, with no GUI, and expects rootful Docker.

So `tools setup lact` downloads the release package matching your distro,
installs it with your package manager, and enables the service — the same steps
upstream's README describes, with the version chosen from a picker.

## Install

```bash
tools setup lact
```

Setup asks which release to install, showing each one's changelog beside the
list:

| Choice | What it is |
|---|---|
| **v0.10.1** and older (default: newest) | Tagged stable releases, newest first |
| **test-build** | Upstream's rolling build from the latest commit — newer fixes, less tested |

Run non-interactively (scripts, `LT_SKIP_WIZARD`) and you get the newest stable
release.

The package is picked from the release assets to match your host: `.deb` for
Ubuntu/Mint/Debian, `.rpm` for Fedora/openSUSE, `.pkg.tar.zst` for Arch-family.
If nothing matches, the installer lists what the release does contain and points
at the Flatpak rather than guessing.

Uninstall — stops the service and removes the package, keeping your config:

```bash
tools rm lact
```

## Usage

The package installs its own application-menu entry (**LACT**), plus:

| Command | What it does |
|---|---|
| `lact gui` | The GTK4 interface |
| `lact cli` | Scriptable interface — `lact cli info`, `lact cli snapshot` |
| `lact daemon` | The daemon itself; normally run by systemd as `lactd` |

Service control, if you need it:

```bash
systemctl status lactd
sudo systemctl restart lactd
```

## Enabling overclocking on AMD

Clock and voltage control on AMD needs a kernel parameter — without it LACT runs
fine but the overclocking controls stay greyed out:

```
amdgpu.ppfeaturemask=0xffffffff
```

LACT's GUI offers to set this for you (it edits your bootloader config); you can
also add it by hand to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` and
run `sudo update-grub`. Either way it needs a reboot. See upstream's
[Overclocking (AMD)](https://github.com/ilya-zlobintsev/LACT/wiki/Overclocking-(AMD))
wiki page.

## Integrated GPUs expose much less

LACT's headline features target discrete cards. On an APU most of them have
nothing to bind to, and the app will look sparse. Measured on a Strix Halo
`Radeon 8060S`:

| Feature | On this APU |
|---|---|
| GPU clock range (`OD_SCLK`) | available — 600–2900 MHz |
| Performance level forcing | available |
| DPM state masking (sclk/mclk/fclk) | available |
| Monitoring: power, temperature, frequency, voltages | available |
| **Power cap** (`power1_cap`) | **absent** |
| **Fan curve** (`fan*` / `pwm*`) | **absent** |
| Power profile modes | absent |
| VRAM clocks, voltage offset curve | absent |

The reasons are structural, not fixable: power is a shared SoC budget the SMU
manages across CPU and GPU, so there is no GPU-level cap to write; there is no
dedicated GPU fan (chassis fans belong to the EC, not `amdgpu`); and memory is
unified, so there is no separate VRAM controller to clock.

Worth knowing before reaching for `amdgpu.ppfeaturemask`: that parameter gates
the *overclocking* interface, so it does not bring back a power cap or fan
control. Check whether it would change anything before rebooting for it — if
`/sys/class/drm/card*/device/pp_od_clk_voltage` already prints an `OD_RANGE`,
the interface is live and the mask is not what is limiting you.

If a bad overclock leaves the machine unstable, upstream documents the
[recovery procedure](https://github.com/ilya-zlobintsev/LACT/wiki/Recovering-from-a-bad-overclock)
— in short, boot with `systemd.unit=multi-user.target` and reset
`/etc/lact/config.yaml`.

## Storage

| Path | What |
|---|---|
| `/etc/lact/config.yaml` | Daemon config: fan curves, power caps, profiles |

`tools rm lact` deliberately leaves this in place so settings survive a
reinstall or a version change. Remove it by hand for a clean slate:
`sudo rm -rf /etc/lact`.

## Notes

- **Socket permissions.** The GUI talks to the daemon over a unix socket owned
  by the `wheel` or `sudo` group, whichever exists. On most desktop installs
  your user is already in one of them, so nothing is needed. If the GUI cannot
  connect, add yourself, or set `admin_group` / `admin_user` in
  `/etc/lact/config.yaml`.
- **NVIDIA needs the proprietary driver with CUDA libraries** installed on the
  host — LACT reads and writes clocks through NVML.
- **`test-build` assets are not named after their tag.** That release is
  rebuilt continuously and its packages carry whatever version they were built
  from (the 0.10.1 packages, at the time of writing). The installer resolves
  the download URL from the release's asset list rather than constructing it
  from the tag, so this works — but it is why the version you pick and the
  version you end up running can differ for this one entry.
- **Verified on Linux Mint 22.3** (Ubuntu 24.04 base): LACT 0.10.1 installed
  from the `ubuntu-2404.deb` asset, `lactd` enabled and running. The CachyOS
  badge stays grey until someone runs it on an Arch-family host.
- **Power-profiles-daemon conflict.** Upstream notes that
  `power-profiles-daemon` can fight LACT over power settings on some systems;
  see the [note in their
  README](https://github.com/ilya-zlobintsev/LACT#power-profiles-daemon-note).
