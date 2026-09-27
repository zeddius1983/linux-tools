# chrome

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

Google Chrome (stable channel) from Google's own APT repo, in an `ubuntu:24.04`
Distrobox container, exported to the host application menu. It behaves like a
natively installed Chrome: hardware-accelerated rendering, host audio, host
downloads, and the host keyring for saved passwords — the only difference is that
the browser and its auto-updates live in a container instead of in your host
package manager.

It also doubles as **the repo's app-mode browser**: `openclaw-dashboard` and
`comfyui-open` both open their web UI in a `chrome-box` window when this app is
installed, and fall back to `xdg-open` when it is not.

## Install

```bash
tools setup chrome
```

No wizard, no GPU picker, no `create_flags` — see [GPU
acceleration](#gpu-acceleration) for why none are needed.

## What you get

| Entry | What it does |
|---|---|
| **Google Chrome** (menu / `.desktop`) | Launches Chrome; the `.desktop` carries Chrome's own `MimeType=` list and its *New window* / *New incognito window* actions, so it can be set as the host's default browser |
| **Google Chrome (Terminal)** (menu) | Opens a shell inside `chrome-box` |

There is no `bin:` export, so `google-chrome` is **not** on the host `PATH`. To
drive it from a script, go through the box:

```bash
distrobox enter chrome-box -- google-chrome --version
distrobox enter chrome-box -- google-chrome --app=http://127.0.0.1:8188   # app-mode window
```

From *inside* another container, prefix that with `distrobox-host-exec` — that is
exactly what `apps/openclaw/openclaw-dashboard` and `apps/comfyui/comfyui-open`
do.

## GPU acceleration

Hardware GL works out of the box, with no device flags in `create_flags`:

```
ANGLE (AMD, Radeon 8060S Graphics (radeonsi gfx1151 LLVM 20.1.2 DRM 3.64), OpenGL 4.6)
```

Two things make that work:

- **Distrobox installs the Mesa stack itself.** On first start,
  `distrobox-init` apt-installs `libgl1`, `libegl1`, `libegl-mesa0`,
  `libglx-mesa0`, `libvulkan1` and `mesa-vulkan-drivers` into any Debian/Ubuntu
  box (`libgl1-mesa-dri` follows as a dependency of `libglx-mesa0`). That is why
  this Dockerfile lists no GL packages at all, unlike the Fedora-based GUI apps
  in this repo, where they have to be spelled out.
- **`/dev/dri` is reachable without `--group-add`.** Distrobox shares `/dev` and
  keeps the host user's supplementary groups (`render`, `video`), so the DRI nodes
  show up as `nobody nogroup` with an ACL (`crw-rw----+`) and are still
  readable/writable by the container user.

Check it yourself from the host:

```bash
distrobox enter chrome-box -- bash -c 'ls -l /dev/dri; test -w /dev/dri/renderD128 && echo writable'
```

or open `chrome://gpu` in the browser and look at *Graphics Feature Status*.

## Hardware video decode (VA-API)

**Works, out of the box, since this app installs one flag for you.** A 1080p H.264
clip costs ~7 % of one core instead of ~35 %.

It takes exactly one flag — `--disable-gpu-driver-bug-workarounds`. Without it
Chrome refuses VA-API on this Mesa/radeonsi combination:

```
media/gpu/vaapi/vaapi_wrapper.cc] GetHandle(): VAAPI has been disabled due to
a detected driver bug.
```

No feature flags, no `LIBVA_DRIVER_NAME`, no Vulkan backend, no Wayland — all
tested, none needed. **The trade-off is real though:** that flag disables *all* of
Chrome's GPU driver bug workarounds, not just the VA-API one. If you ever see
rendering glitches in this browser, that is the first thing to blame.

### Changing the flags: `~/.config/chrome-flags.conf`

`/usr/bin/google-chrome-stable` in the image is a wrapper (the real binary is
diverted to `.real` with `dpkg-divert`, so an `apt upgrade` inside the box cannot
clobber it). It reads flags, one per line with `#` comments, from the first file
that exists:

| File | Role |
|---|---|
| `~/.config/chrome-flags.conf` | yours — if it exists, it wins outright |
| `/etc/chrome-flags.conf` | the image default: just the flag above |

Same file name CachyOS uses, so flag lists from its wiki paste straight in. The
wrapper sits on the `.desktop`'s `Exec` path, so flags apply to every entry point:
the menu icon, `google-chrome` inside the box, and the app-mode windows
`openclaw-dashboard` and `comfyui-open` open.

To turn the override off without touching the image, write your own file omitting
that line — verified: Chrome then goes back to ~45 % CPU and software decode.

Video *encode* stays on the CPU: Chrome blocklists accelerated encode on Linux
separately, whatever `VAEntrypointEncSlice` support `vainfo` advertises.

### Flags that do nothing here

Measured against a playing 1080p clip, each left decode in software — including
both flag sets from the CachyOS wiki:

```
--enable-features=VaapiVideoDecoder,AcceleratedVideoDecodeLinuxGL,
                  AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,
                  VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo
--enable-features=Vulkan,VulkanFromANGLE,DefaultANGLEVulkan   --use-angle=vulkan
--ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy
--disable-gpu-sandbox   LIBVA_DRIVER_NAME=radeonsi
```

`--ozone-platform=wayland` does not apply on an X11 session (this one is
`XDG_SESSION_TYPE=x11`); the wiki's note is about the reverse case. And
`--enable-gpu-rasterization` has nothing to do — `chrome://gpu` already reports
*Rasterization: Hardware accelerated*.

### The `libpci3` prerequisite

Before `libpci3` was added to the image, the box failed one step *earlier* than
this, with a different message — `GetHandle(): … failed to find a suitable render
node` — because Chrome dlopens libpci to read the GPU's PCI IDs and without it
`chrome://gpu` reports `GPU0: VENDOR = 0x0000, DEVICE = 0x0000`. Chrome then has
nothing to match a DRM render node against. **`VENDOR=0x0000` in `chrome://gpu`
means libpci is missing in that container** — a useful check for any GUI box here.

### How to check it yourself

`apps/chrome/chrome-decode-check`, on the host, while a video is actually playing:

```console
$ ./apps/chrome/chrome-decode-check
--disable-gpu-driver-bug-workarounds : yes   [browser pid 457083]
Total Chrome CPU over 8s              : 7% of one core
GPU engine time over 8s:
  drm-engine-gfx          175 ms  ( 2%)
  drm-engine-enc         1786 ms  (22%)
  drm-engine-compute        2 ms  ( 0%)
  drm-engine-vpe         2178 ms  (27%)

VERDICT: hardware decode — the video engines are doing the work.
```

It reads per-engine GPU time from the Chrome processes' DRM `fdinfo`, which is
ground truth and independent of codec and resolution, and cross-checks total
Chrome CPU (~35 % of one core at 1080p = software, ~7 % = hardware).

The verdict turns on *any* video-engine time rather than a utilisation
percentage — in software those engines are absent from `fdinfo` entirely, while a
480p or low-frame-rate stream can decode in hardware using well under 1 % of the
engine. Below 1 ms of engine time it says "inconclusive" instead of guessing, and
under 3 % CPU it reports that nothing was playing rather than calling an idle
browser a pass. The flag is read from the browser process of whichever instance
is busiest (shown in brackets), so a second Chrome window cannot lend its flag to
the one you are measuring.

In the browser: `chrome://media-internals` → play something → click the player.
Hardware decode says, in as many words:

```
Selected VaapiVideoDecoder for video decoding, config: codec: av1, …
```

### Why `amdgpu_top` shows 0 % media

Because it is looking at a counter the decoder does not touch on this chip. **On
VCN 4.x the decoder rides the *unified* VCN queue, which the kernel accounts to
`drm-engine-enc`** — so hardware *decode* shows up under "enc", alongside
`drm-engine-vpe` for the scaling/colour-conversion block. Measured on a 1080p
clip, hardware vs software:

| Engine | Hardware decode | Software decode |
|---|---|---|
| `drm-engine-enc` | 23 % | absent |
| `drm-engine-vpe` | 28 % | absent |
| `drm-engine-gfx` | 2 % | 2 % |

Meanwhile `/sys/class/drm/card*/device/vcn_busy_percent` — which is what
`amdgpu_top`'s Media row reflects — reads `0` throughout both. So on gfx1151, a
`0 %` media reading says nothing about whether decode is on the GPU. Use `fdinfo`
(or `chrome-decode-check`, which does it for you); `nvtop` and `amdgpu_top`'s
per-process view read the same fdinfo counters and will show the `enc`/`vpe`
activity too.

**Three signals that lie on this machine**, all of which cost time here:

- **`chrome://gpu`'s *Video Decode: Hardware accelerated*** is a blocklist status,
  not a fact about playback. It says that even while decode is measurably software.
- **`vcn_busy_percent` / `amdgpu_top`'s Media row** — see above.
- **Grepping `/proc/<pid>/maps` for `*_drv_video.so`** never matches on Ubuntu's
  Mesa 25: the VA driver is a symlink to `libgallium-<ver>.so` and maps shows the
  resolved name.

And two ways to measure nothing and believe it: a stopped video reads exactly like
flawless hardware decode, and `--headless=new` logs the VA-API warning
unconditionally, so it is not a test bed.

### The rest of `chrome://gpu`

So a future reader does not chase a Linux default as a container bug: `Vulkan`,
`Skia Graphite`, `Direct Rendering Display Compositor`, `Raw Draw` and `WebNN` are
*Disabled* on a healthy box — Chrome renders through ANGLE/GL on Linux — while
`Canvas`, `Compositing`, `Rasterization`, `WebGL` and `WebGPU` report *Hardware
accelerated*. The *Problems Detected* list is generic Mesa workarounds (partial
swaps, `KHR_blend_equation_advanced`, `GL_MESA_framebuffer_flip_y`,
`exit_on_context_lost`); a host-installed Chrome on the same GPU prints the same
list.

## Audio

`libpulse0` + `libasound2t64` are in the image, and Distrobox passes the host's
PulseAudio/PipeWire socket through, so sound works with no extra configuration.

## Saved passwords and the keyring

Chrome 148 encrypts its password store through the **XDG Secret portal**
(`org.freedesktop.impl.portal.Secret`), reached over the host session bus that
Distrobox shares into the container (`DBUS_SESSION_BUS_ADDRESS` →
`/run/user/1000/bus`). The container therefore needs no `libsecret` or
`gnome-keyring` of its own, and passwords land in the host's real keyring.

Confirm it took by looking for `"prev_init_success": true` under `os_crypt` in
`~/.config/google-chrome/Local State`. If it reports `false`, the host is missing
a Secret portal backend (`gnome-keyring` or `kwallet` plus
`xdg-desktop-portal`); Chrome then silently downgrades to its obfuscated "basic"
store, which is *not* real encryption.

## Persistent storage

All of these are host paths in the shared `$HOME`, so they survive
`tools rm chrome` and a `tools setup chrome` rebuild:

- `~/.config/google-chrome/` — profiles, history, bookmarks, extensions, passwords
- `~/.cache/google-chrome/` — HTTP and GPU shader cache
- `~/Downloads/` — downloads land on the host, as normal
- `~/.openclaw/chrome-profile/`, `~/.comfyui/chrome-profile/` — the separate
  profiles the openclaw and comfyui app-mode windows use

Because the profile lives in the host home, **never run this Chrome and a
host-installed Chrome against the same profile directory** — two Chrome builds
sharing one profile is how profiles get corrupted.

## Notes

- **Chrome updates itself via APT inside the box**, not through the host package
  manager. Both halves have to run inside the box — a bare `&& sudo apt-get
  upgrade` would upgrade the *host* and leave Chrome untouched:

  ```bash
  distrobox enter chrome-box -- bash -c 'sudo apt-get update && sudo apt-get upgrade'
  ```

  `tools setup chrome` rebuilds the image from the current stable `.deb` instead,
  and keeps your profile.
- **"Install as app" (PWA) shortcuts need a re-export to work from the host
  menu.** Chrome writes them into the shared `~/.local/share/applications/` as
  `chrome-<app-id>-Default.desktop` with `Exec=/opt/google/chrome/google-chrome
  …` — a path that only exists inside the container, so launching it from the
  host menu does nothing. Fix it by exporting that entry through Distrobox:

  ```bash
  distrobox enter chrome-box -- distrobox-export --app chrome-<app-id>-Default
  ```

  which rewrites `Exec=` to go through `distrobox-enter`. `tools export chrome`
  does not do this for you — it only handles `google-chrome` itself, and its
  duplicate cleanup keys on the entry's `Name=`, so PWA entries are left alone.
- **`vainfo` is in the image on purpose** — it is the only way to tell "the
  container cannot see the GPU" apart from "Chrome chose not to use VA-API".
- **The Noto fonts are ~140 MB of the image** (`fonts-noto-cjk` alone is 89 MB).
  That is the price of a browser that can render arbitrary pages; drop
  `fonts-noto-cjk` from the Dockerfile if you never open CJK content and want the
  image ~90 MB smaller.
- **amd64 only.** Google ships Chrome for `amd64`, so the Dockerfile pins
  `--platform=linux/amd64`. On an arm64 host the build needs `qemu-user-static`
  binfmt registered on the host.
- **The box stays running while a Chrome window is open.** `tools setup chrome`
  removes the box first, which kills any open Chrome window (including the
  openclaw/comfyui app-mode ones) — close them before rebuilding.
