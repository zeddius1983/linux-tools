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

The image ships `libva2`, `libva-drm2`, `mesa-va-drivers` and `vainfo`, so the
VA-API driver is available inside the box. Verified on this host:

```console
$ distrobox enter chrome-box -- vainfo
libva info: Trying to open /usr/lib/x86_64-linux-gnu/dri/radeonsi_drv_video.so
vainfo: Driver version: Mesa Gallium driver 25.2.8 for Radeon 8060S Graphics (radeonsi, gfx1151)
      VAProfileH264High               : VAEntrypointVLD
      VAProfileHEVCMain10             : VAEntrypointVLD
      VAProfileVP9Profile0            : VAEntrypointVLD
      VAProfileAV1Profile0            : VAEntrypointVLD
```

Chrome does **not** use it by default on Linux — you have to turn it on, either
per profile:

- `chrome://flags/#enable-accelerated-video-decode` → *Enabled*, then relaunch,

or per launch, which is what you want for the scripted app-mode windows:

```bash
distrobox enter chrome-box -- google-chrome --enable-features=VaapiVideoDecodeLinuxGL
```

Check the result on `chrome://gpu` under *Video Decode* (it should say *Hardware
accelerated*), and watch a decode actually happen on `chrome://media-internals`
while a video plays — `vainfo` proving the driver loads is not the same as Chrome
choosing to use it, and Chrome's Linux VA-API feature names change between
releases.

No flags are baked into the image: Google's `.deb` wrapper no longer sources
`/etc/default/google-chrome`, so there is no injection point short of replacing
`/usr/bin/google-chrome-stable` with a wrapper script — which `apt upgrade` inside
the box would undo. Leaving it to a flag keeps the decision per profile, which
also matters because forcing VA-API can produce black frames on some drivers.

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
  manager. `distrobox enter chrome-box -- sudo apt-get update && sudo apt-get
  upgrade` bumps it in place; `tools setup chrome` rebuilds the image from the
  current stable `.deb` and keeps your profile.
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
