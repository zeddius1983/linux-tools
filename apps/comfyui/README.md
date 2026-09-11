# comfyui

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/Ubuntu-tested-brightgreen?logo=ubuntu&logoColor=white">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/Linux_Mint-tested-brightgreen?logo=linuxmint&logoColor=white">
  <img alt="CachyOS: tested" src="https://img.shields.io/badge/CachyOS-tested-brightgreen?logo=archlinux&logoColor=white">
</p>

Node-based UI for generative AI image and video workflows (Stable Diffusion,
SDXL, Flux, WAN video, …), running as a local web server in a Distrobox
container.

Setup asks two questions:

1. **GPU backend** — **AMD (ROCm)** or **NVIDIA (CUDA)**. This picks the PyTorch
   base image *and* the container's GPU passthrough.
2. **Release** — one of the last 10 [ComfyUI releases](https://github.com/Comfy-Org/ComfyUI/releases),
   or `master` for the branch tip. The newest release is the default. Each
   release's notes are shown beside the list (`PgDn`/`PgUp` scrolls them);
   `master` is a branch, so it has none.

## Install

```bash
tools setup comfyui
```

Re-running `tools setup comfyui` rebuilds from scratch, so it is also how you
switch GPU backend or change release. Models, generated images, inputs and saved
workflows all live under `~/.comfyui/` (see [Storage](#storage)) and survive the
rebuild; custom nodes do not.

### Non-interactive install

Run with no wizard — a scripted `tools setup comfyui`, or a non-tty shell — and
you get the defaults: **AMD/ROCm at `master`**. Pinning either means handing the
answers to `tools` in a wizard state file:

```bash
cat > /tmp/comfyui.state <<'EOF'
APP="comfyui"
ACTION="setup"
BUILD_ARGS="--build-arg COMFY_GPU=nvidia --build-arg COMFY_REF=v0.30.0"
VARIANT="nvidia"
EOF

LT_SKIP_WIZARD=1 LT_WIZARD_STATE=/tmp/comfyui.state tools setup comfyui
```

`BUILD_ARGS` and `VARIANT` must agree. `VARIANT` is what makes `tools create`
use `create_flags.nvidia`; a bare `podman build --build-arg COMFY_GPU=nvidia`
followed by `tools create comfyui` builds an NVIDIA **image** and then creates
the box with the **AMD** flags — `/dev/kfd` and no CDI device — which on an
NVIDIA-only host fails to create or comes up with no usable GPU.

The equivalent by hand, if you would rather not go through `tools`:

```bash
tools rm comfyui && podman rmi linux-tools/comfyui:latest
podman build --build-arg COMFY_GPU=nvidia --build-arg COMFY_REF=v0.30.0 \
  -t linux-tools/comfyui:latest apps/comfyui
distrobox create --name comfyui-box --image linux-tools/comfyui:latest --yes --no-entry \
  --additional-flags "$(cat apps/comfyui/create_flags.nvidia)"
tools export comfyui
```

### NVIDIA prerequisite — the CDI spec

The NVIDIA variant exposes the GPU with `--device nvidia.com/gpu=all`, which
needs a CDI spec on the **host**:

```bash
sudo pacman -S nvidia-container-toolkit           # CachyOS / Arch
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Regenerate after every driver update (the spec pins driver library paths).
Verify with `nvidia-ctk cdi list` — it should show `nvidia.com/gpu=all`. Without
it, `tools setup` fails at container-create time with podman's
`no such device nvidia.com/gpu=all`.

> Do **not** use `distrobox create --nvidia` here. On a rootless-podman host it
> bind-mounts the entire host driver on every start and can wedge in a remount
> loop — see [`apps/lmstudio/README.md`](../lmstudio/README.md) for the full
> post-mortem.

The CUDA wheels are built for **CUDA 12.8**, which needs host driver **≥ 570**.

## Usage

| Command | What it does |
|---|---|
| `comfyui` | Runs the server in the foreground on `http://localhost:8188` |
| `comfyui --help` | ComfyUI's own flags (extra flags are appended to the defaults) |
| `comfyui-stop` | Stops a running server, however it was started |
| `comfyui-tray` | Tray icon with a Start/Stop menu (the launcher starts this for you) |
| ComfyUI (desktop launcher) | Starts the server, brings up the tray, opens a browser app window |

```bash
comfyui                      # foreground, Ctrl-C to stop
comfyui --port 9000          # extra flags pass straight through
```

The desktop entry uses `chrome-box` for an app-mode window if that box exists,
and falls back to `xdg-open`. Its server log goes to `~/.comfyui/server.log`.

### Tray icon

Launching ComfyUI from the desktop entry also puts an icon in the notification
area, so a detached server is not something you have to hunt for afterwards:

| Menu item | |
|---|---|
| `Server: running (2 queued)` | Live status, refreshed every 3s |
| Open in browser | Same window the launcher opens |
| Start / Stop server | Toggles with the current state |
| Show log | Opens `~/.comfyui/server.log` in a terminal pager, following live |
| Close | Stops the server, then hides the tray |

Stop asks before discarding queued prompts, offering **Stop anyway**.

**Close** stops the server first, then hides the tray — closing without it would
leave the server with no icon, no window and no terminal, which is the exact
state the tray exists to prevent. If prompts are queued you still get the
**Stop anyway** prompt, and declining it cancels the close too, leaving both the
queue and the tray intact.

**Show log** opens the server log in a host terminal, following it live.

It uses `less -r -f +F`: `-r` so the tqdm progress bars' carriage returns reach
the terminal and overwrite in place (rather than every redraw landing side by
side), `-f` to stop less calling the colour-coded log a binary file, and `+F` to
follow. `Ctrl-C` stops following and leaves you in normal `less` navigation; `F`
resumes.

[`ov`](https://github.com/noborus/ov) was tried here and is worse for this log —
it swallows carriage returns, so a finished progress bar reads as every
intermediate percentage strung along one line. It remains available in
`shell-toolbox` as a general-purpose pager.

It picks the first of ghostty, kitty, alacritty,
gnome-terminal, xfce4-terminal, mate-terminal, konsole or xterm found **on the
host** — this container ships none, and the log is in the shared `$HOME` where
the host can read it directly. With none of those installed it falls back to
`xdg-open`.

To hide the icon but keep generating, close it from your panel's own applet
settings, or just leave it — it costs nothing.

There is deliberately **no separate menu entry** for the tray — the ComfyUI
launcher starts it, so a second icon would only be clutter. If you close it and
want it back without restarting the server, run `comfyui-tray`; it holds a lock
and exits quietly if one is already running.

To have it come up with your session, point autostart at that command:

```bash
cat > ~/.config/autostart/comfyui-tray.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=ComfyUI Tray
Exec=comfyui-tray
Terminal=false
EOF
```

It needs a StatusNotifier host on the session bus — standard on KDE, Cinnamon and
XFCE. GNOME needs the AppIndicator extension. If there is none, the tray simply
does not appear and everything else still works; the launcher treats it as
best-effort and never fails ComfyUI's start over it.

### Stopping it

A foreground `comfyui` stops with Ctrl-C. The desktop launcher starts the server
**detached**, so there is no terminal to Ctrl-C — use the tray's **Stop server**,
or:

```bash
comfyui-stop            # interrupt current prompt, then stop
comfyui-stop --force    # stop even with prompts still queued
```

It prefers **SIGINT**, which is what Ctrl-C sends, so Python unwinds normally and
ComfyUI's cleanup runs. Before signalling it reads `/proc/<pid>/status` and falls
back to SIGTERM if that process ignores SIGINT — servers started by a launcher
from before this fix do, and would otherwise sit there while the signal is
silently discarded. SIGKILL after 30s is the last resort.

> If `pkill -INT` appears to do nothing on an old box, this is why: the launcher
> backgrounded the server without job control, so the shell set SIGINT to
> `SIG_IGN`, and CPython then skips installing its `KeyboardInterrupt` handler.
> Use `pkill -TERM` there, or rebuild to get `comfyui-stop`.

Queued prompts live in memory and die with the process, so `comfyui-stop`
refuses while any are pending and tells you to wait or pass `--force`.

To watch a detached server the way you would a foreground one:

```bash
tail -f ~/.comfyui/server.log
```

`podman stop comfyui-box` is not a substitute — it tears the container down
around ComfyUI rather than letting it shut itself down. Stop the app first.

### Tuning flags

The launcher applies a default flag set per backend:

- **AMD**: `--reserve-vram 3 --bf16-vae --disable-mmap --cache-none`, tuned for
  Strix Halo (gfx1151) unified memory. `--disable-mmap` in particular works
  around a ROCm bug that makes mapping above 64 GB extremely slow.
- **NVIDIA**: no extra flags; just `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

Those AMD defaults are wrong for a small discrete card. Replace the tuning set
with `COMFYUI_ARGS`:

```bash
COMFYUI_ARGS="--lowvram --preview-method auto" comfyui
```

`--listen` and the three directory flags below are *not* replaceable this way —
losing them would put your generated images back inside the image, where a
rebuild deletes them.

## Storage

Everything you create is under the host `$HOME`, so it survives rebuilds and is
shared between the AMD and NVIDIA variants:

| Path | Contents |
|---|---|
| `~/.comfyui/models/` | `checkpoints/`, `vae/`, `loras/`, `controlnet/`, `upscale_models/`, `clip/`, `unet/`, `diffusion_models/` |
| `~/.comfyui/output/` | Generated images and video |
| `~/.comfyui/input/` | Images you upload to a workflow |
| `~/.comfyui/user/` | **Saved workflows**, UI settings, and the asset database (`comfyui.db`) |
| `~/.comfyui/server.log` | Log from a desktop-launched server |
| `~/.cache/miopen` | MIOpen kernel cache (AMD only) |

Drop `.safetensors` files straight into the matching `~/.comfyui/models/`
sub-directory; ComfyUI picks them up on refresh.

Models come from `extra_model_paths.yaml`; the others are `--output-directory`,
`--input-directory`, `--user-directory` and `--database-url` passed by the
launcher. ComfyUI's own defaults for all of them are inside `/opt/ComfyUI`,
which `tools setup` destroys.

`--database-url` needs setting separately because it does **not** follow
`--user-directory` — its default is computed from the install directory at
import time. Left alone once the user dir is redirected, it points at
`/opt/ComfyUI/user/comfyui.db` in a directory nothing creates any more, and
startup logs `Failed to initialize database … unable to open database file`.

Custom nodes are the exception — they live at
`/opt/ComfyUI/custom_nodes` **inside the image** and are lost on rebuild.
ComfyUI-Manager is pre-installed, so reinstalling from the UI is the intended
path.

### Upgrading from a build before this redirect

Earlier images wrote outputs and workflows to `/opt/ComfyUI/output` and
`/opt/ComfyUI/user`, inside the container. **Rescue them before the next
`tools setup comfyui`**, which deletes the image:

```bash
distrobox enter comfyui-box -- \
  bash -c 'mkdir -p ~/.comfyui && cp -rn /opt/ComfyUI/output /opt/ComfyUI/user ~/.comfyui/ 2>/dev/null; true'
```

Then check `~/.comfyui/output` and `~/.comfyui/user` look right before rebuilding.

## Notes

- **First AMD generation is slow.** MIOpen compiles GPU kernels on first use
  (~2× the normal time). The cache in `~/.cache/miopen` persists afterwards.
- **The images are large** — the ROCm base is 15–20 GB, and the CUDA variant
  downloads ~3 GB of PyTorch wheels. Expect a long first build.
- **No `nvcc` in the NVIDIA image.** It is built on `nvidia/cuda:*-runtime`.
  Custom nodes that compile CUDA kernels from source will fail; switch
  `CUDA_BASE` to the matching `-devel` tag if you need one.
- **Both variants use `/opt/venv/bin/python`.** A bare `python` inside the box is
  the system one and has no site-packages.
