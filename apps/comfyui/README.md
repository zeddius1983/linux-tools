# comfyui

Node-based UI for generative AI image and video workflows (Stable Diffusion,
SDXL, Flux, WAN video, …), running as a local web server in a Distrobox
container.

Setup asks two questions:

1. **GPU backend** — **AMD (ROCm)** or **NVIDIA (CUDA)**. This picks the PyTorch
   base image *and* the container's GPU passthrough.
2. **Release** — one of the last 10 [ComfyUI releases](https://github.com/Comfy-Org/ComfyUI/releases),
   or `master` for the branch tip. The newest release is the default.

## Install

```bash
tools setup comfyui
```

Run non-interactively (scripted, no wizard), you get the defaults: AMD/ROCm at
`master`. To pin either without the wizard:

```bash
podman build --build-arg COMFY_GPU=nvidia --build-arg COMFY_REF=v0.30.0 \
  -t linux-tools/comfyui:latest apps/comfyui
```

Re-running `tools setup comfyui` rebuilds from scratch, so it is also how you
switch GPU backend or change release. Models and outputs live in `$HOME` and are
untouched by the rebuild.

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
| ComfyUI (desktop launcher) | Starts the server if it isn't running, then opens it as a browser app window |

```bash
comfyui                      # foreground, Ctrl-C to stop
comfyui --port 9000          # extra flags pass straight through
```

The desktop entry uses `chrome-box` for an app-mode window if that box exists,
and falls back to `xdg-open`. Its server log goes to `~/.comfyui/server.log`.

### Tuning flags

The launcher applies a default flag set per backend:

- **AMD**: `--reserve-vram 3 --bf16-vae --disable-mmap --cache-none`, tuned for
  Strix Halo (gfx1151) unified memory. `--disable-mmap` in particular works
  around a ROCm bug that makes mapping above 64 GB extremely slow.
- **NVIDIA**: no extra flags; just `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

Those AMD defaults are wrong for a small discrete card. Replace them wholesale
with `COMFYUI_ARGS` (`--listen 0.0.0.0` is always kept):

```bash
COMFYUI_ARGS="--lowvram --preview-method auto" comfyui
```

## Storage

Everything persistent is in the host `$HOME`, so it survives rebuilds and is
shared between the AMD and NVIDIA variants:

| Path | Contents |
|---|---|
| `~/.comfyui/models/` | `checkpoints/`, `vae/`, `loras/`, `controlnet/`, `upscale_models/`, `clip/`, `unet/`, `diffusion_models/` |
| `~/.comfyui/server.log` | Log from a desktop-launched server |
| `~/.cache/miopen` | MIOpen kernel cache (AMD only) |

Drop `.safetensors` files straight into the matching `~/.comfyui/models/`
sub-directory; ComfyUI picks them up on refresh.

Custom nodes are the exception — they live at
`/opt/ComfyUI/custom_nodes` **inside the image** and are lost on rebuild.
ComfyUI-Manager is pre-installed, so reinstalling from the UI is the intended
path.

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
