# LM Studio

Desktop app for discovering, downloading, and running local LLMs. Packaged as
the official LM Studio AppImage inside a Distrobox container and exported to the
host application menu.

At setup time an interactive **GPU runtime picker** chooses which GPU the
container exposes to LM Studio:

- **AMD (ROCm/Vulkan)** — passes `/dev/kfd` + `/dev/dri` through and ships the
  Mesa Vulkan driver in the image. This is the default.
- **NVIDIA (CUDA)** — exposes the GPU via **CDI** (`--device nvidia.com/gpu=all`),
  which injects the host NVIDIA driver (libcuda + NVIDIA Vulkan ICD) and device
  nodes into the container.

## Prerequisite for the NVIDIA path (one-time host setup)

The NVIDIA option uses CDI (Container Device Interface). Install the toolkit and
generate the CDI spec **on the host** once:

```bash
sudo pacman -S nvidia-container-toolkit           # in CachyOS/Arch repos
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Re-run the `cdi generate` step after an NVIDIA **driver update** so the spec
tracks the new driver version. Verify with `nvidia-ctk cdi list` (should show
`nvidia.com/gpu=all`).

> Why CDI and not `distrobox --nvidia`? distrobox's `--nvidia` bind-mounts the
> entire host driver (~100 libraries) into the container on every startup; under
> rootless podman that is slow and can wedge in a retry loop. CDI does a single
> declarative device injection — fast and reliable. The AMD path needs none of
> this.

## Install

```bash
tools setup lmstudio
```

Pick your GPU vendor when the wizard prompts. `setup` removes any existing box
and image first, so re-running it (and choosing the other vendor) switches
runtimes.

## Exported commands

| Launcher | What it does |
|---|---|
| **LM Studio** (menu / `.desktop`) | Launches the LM Studio GUI |

## GPU runtimes

LM Studio manages its own llama.cpp inference engines. The AppImage ships a
baseline set **bundled** (CPU AVX2, Vulkan, and a CUDA 11.8 build), and on first
launch LM Studio detects the GPU and sets up the matching engine — **downloading
a newer runtime if one is available** (observed: it pulls a **CUDA 12** engine on
NVIDIA). Either way this is automatic; you don't pick a runtime by hand:

- On the **NVIDIA (CUDA)** box, once the GPU is visible (that's what CDI
  provides) LM Studio selects/downloads the CUDA engine automatically.
- On the **AMD** box, the Vulkan (or ROCm) engine is used.

The download is a one-time cost stored in `~/.lmstudio/` (shared host home), so
it persists across rebuilds.

You can confirm or change the active engine in-app under **Settings → Runtimes**,
or from the bundled CLI once the app has been launched at least once:

```bash
distrobox enter lmstudio-box -- lms runtime ls        # list installed engines
distrobox enter lmstudio-box -- lms runtime select     # pick the active engine
```

> Note: `lms runtime` commands require LM Studio to have been run at least once
> (they talk to the app's local daemon), so they can't be scripted before first
> launch. In practice you don't need them — the CUDA engine is bundled and
> auto-selected on the NVIDIA box.

## Persistent storage

Everything LM Studio stores lives in `~/.lmstudio/` on the host (shared into the
container via Distrobox home sharing):

- `~/.lmstudio/models/` — downloaded models
- `~/.lmstudio/.internal/extensions/backends/` — extracted inference engines
- `~/.lmstudio/settings.json` — app settings incl. selected runtime

Because it's the host home, models and settings survive `tools rm lmstudio` and
`tools setup lmstudio` rebuilds, and are shared if you switch GPU vendors.

## Notes

- **Switching vendors:** re-run `tools setup lmstudio` and pick the other option.
  Only the container's GPU passthrough changes; your models/settings in
  `~/.lmstudio/` are untouched.
- **NVIDIA requires the CDI spec.** If `/etc/cdi/nvidia.yaml` is missing, box
  creation fails with a podman "no such device nvidia.com/gpu=all" error — run
  the prerequisite steps above. Once set up, `nvidia-smi` works inside the box.
  If the host has no NVIDIA driver, choose the AMD option.
- The image bundles the Mesa Vulkan driver, which only matters for AMD/Intel;
  it's harmless (unused) on the NVIDIA box, where the NVIDIA Vulkan ICD comes
  from the host driver.
