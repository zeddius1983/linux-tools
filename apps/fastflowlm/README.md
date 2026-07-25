# fastflowlm

[FastFlowLM](https://github.com/FastFlowLM/FastFlowLM) (FLM) — an Ollama-style LLM
runtime that executes **entirely on the AMD Ryzen™ AI NPU (XDNA2)**. No GPU, no CPU
inference load. Supports text, vision, audio, embedding and MoE models with context
windows up to 256k tokens.

Requires an **XDNA2** NPU: Ryzen AI 300-series (Strix / Strix Halo / Kraken Point),
400-series (Gorgon Point), or Z2 Extreme. Ryzen AI 7000 / 8000 / 200-series have
XDNA1 and are **not** supported.

## Install

```bash
tools setup fastflowlm
```

The interactive setup shows a release picker (last 10 GitHub releases); the
non-interactive CLI installs the latest release.

## Host prerequisites

The container ships only the **XRT userspace**. Everything below the driver line is
host-side and cannot be provided by a container:

| Requirement | How to satisfy it |
|---|---|
| `amdxdna` kernel driver | In-tree on kernel **7.0+**; below that install `amdxdna-dkms` |
| NPU firmware 1.1.0.0+ | Ships in `linux-firmware` / `linux-firmware-other` |
| **IOMMU enabled** | See [IOMMU](#iommu) below. The driver binds the process address space via IOMMU SVA, so `amd_iommu=off` makes every open of the NPU fail with `SVA bind device failed, ret -19`. |
| memlock rlimit | See [memlock](#memlock) below — an optimization, not a blocker |
| Group membership | Your host user must be in the group owning `/dev/accel/accel0` (usually `render`) |

Run `flm-doctor` to check all of these at once — it reads the host kernel, driver,
IOMMU and firmware state from inside the box and reports what is missing.

### IOMMU

`amdxdna_drm_open()` calls `iommu_sva_bind_device()` on every open of the NPU, so
the NPU addresses memory through the IOMMU or not at all. With `amd_iommu=off` the
driver still probes, the module still loads, and `/dev/accel/accel0` still exists —
every cheap check passes — while every open fails with `-ENODEV (-19)`. There is no
module parameter to bypass it.

**On Strix Halo this is a real tradeoff, because the IOMMU costs iGPU throughput:**

| iGPU workload | Cost of enabling the IOMMU |
|---|---|
| Token generation (decode) | ~2–3% — bandwidth-bound, largely insensitive |
| Prompt processing (prefill) | 5–12%, scales with batch size |

The prefill cost comes from ROCm runtime / HSA queue traffic going through the
IOMMU. So chat-style use with modest prompts barely notices; long-context, RAG and
batched workloads do.

**There is no middle setting.** Passthrough mode is not an escape hatch —
`iommu=pt` benchmarks *identically* to the default Translated mode, and
`amd_iommu=off` is 5–12% faster than either. Two traps worth knowing:

- **`amd_iommu=pt` is not a valid kernel parameter.** The kernel logs
  `AMD-Vi: Unknown option - 'pt'` and silently falls back to Translated mode, so
  anyone who sets it believes they have passthrough and does not. The valid
  spelling is `iommu=pt`, without the `amd_` prefix.
- `iommu=pt` buys nothing anyway. If you want the GPU performance back, the only
  option is genuinely disabling the IOMMU — which disables the NPU.

Measurements: [kyuz0/amd-strix-halo-toolboxes#66](https://github.com/kyuz0/amd-strix-halo-toolboxes/issues/66).

#### Having both: a per-boot GRUB entry

Since the choice is binary and set at boot, the practical answer is two boot
entries — default with the IOMMU on for NPU work, and a second with
`amd_iommu=off` for GPU-max sessions. Add a generator so it survives kernel
updates (a static `40_custom` entry goes stale the moment the kernel changes):

```sh
# /etc/grub.d/45_iommu_off  (chmod +x; re-runs on every update-grub)
```

See `iommu-off-entry.sh` in this directory for a ready-to-run installer. The menu
also has to be visible — Mint/Ubuntu ship `GRUB_TIMEOUT_STYLE=hidden` with
`GRUB_TIMEOUT=0`, which hides it entirely.

### memlock

Models pin weights, KV cache and activations so the NPU can DMA from them, and
pinned pages can't be paged out. FLM raises its own *soft* limit at startup, but
it can never exceed the *hard* limit — so on a distro default where soft equals
hard, it has nowhere to go and prints:

```
[Linux]  Warning: could not raise memlock limit to 33890 MB
```

Requirements scale with the model. Small models fit under a typical 15–16 GB
default; `qwen3.6-moe:35b-a3b` asks for **33.1 GB**.

**The warning is not fatal, and in most cases nothing breaks.** FLM logs it and
carries on without pinning: a `qwen3.6-moe:35b-a3b` session measured 24.5 GB RSS
with `VmLck: 16 kB` — essentially nothing locked. It works because the NPU reaches
memory through **IOMMU SVA**: the device walks the process's own page tables via a
PASID, so it addresses ordinary pageable memory and needs no pre-pinned DMA
buffers. Pinning is an optimization on this path, not a requirement.

It matters when pages can actually be evicted. On a host with **no swap**,
anonymous pages cannot be paged out at all, so `mlock` buys close to nothing and
raising the limit is cosmetic. With swap enabled and real memory pressure, an
evicted page the NPU is about to touch costs an IOMMU page-fault stall — that is
the case the limit protects against.

To raise the ceiling, add a drop-in — this is a *ceiling*, not a reservation,
so nothing is preallocated and an idle system consumes nothing:

```
# /etc/security/limits.d/30-npu-memlock.conf
*    soft    memlock    67108864     # 64 GiB
*    hard    memlock    67108864
```

64 GiB matches the NPU's own `<50%`-of-DRAM addressing ceiling on a 128 GB host,
so it costs no capability while still capping the blast radius of a runaway
process — preferable to `unlimited`, which lets one process pin all of RAM.
Scale the number to your machine.

Two things that make this not take effect:

- **`pam_limits` must be in your login path.** It is often present only in
  `/etc/pam.d/login` (console), while the display manager ignores it. Check your
  DM's file — e.g. `grep pam_limits /etc/pam.d/lightdm` — then log out and back
  in (or reboot) and confirm with `ulimit -Hl`.
- **Recreate the box afterwards.** Podman captures rlimits when the container is
  *created*, so an existing box keeps the old ceiling:
  `tools rm fastflowlm && tools create fastflowlm && tools export fastflowlm`
  (seconds — the image is not rebuilt).

`create_flags` deliberately carries no `--ulimit memlock`: rootless Podman cannot
request more than the host's hard limit, so hardcoding one would make the
container fail to start on any host that hasn't raised it. Inheritance is the
portable path.

## Exported commands

| Command | Purpose |
|---|---|
| `flm` | The FastFlowLM CLI |
| `flm-doctor` | Host + container NPU prerequisite check (see above) |
| `xrt-smi` | AMD XRT device query — `xrt-smi examine` lists the NPU |

### Usage

```bash
flm-doctor                      # check the whole stack first

flm list                        # list available models
flm pull llama3.2:1b            # download a model
flm run llama3.2:1b             # interactive chat in the terminal
flm serve llama3.2:1b           # OpenAI-compatible server on port 52625
flm validate                    # NPU/firmware/memlock check (FLM's own)
```

Inside a chat session: `/verbose` toggles performance reporting, `/bye` exits.

`flm serve` listens on **port 52625**. Distrobox uses host networking, so the server
is reachable at `http://localhost:52625/v1` from the host and any other app on it.

## Storage

| Path | Contents |
|---|---|
| `~/.config/flm/` | Downloaded models (default) |
| `/opt/fastflowlm/share/flm/xclbins/` | NPU kernel binaries (in-image, per model family) |

Models live under the shared `$HOME`, so they survive `tools setup` rebuilds and are
visible from the host. Override the location with `FLM_MODEL_PATH`.

Model downloads come from HuggingFace. If a download is corrupted, re-fetch with
`flm pull <model> --force`.

## Notes

- `FLM_DISABLE_UPDATE_CHECK=1` disables the startup version check.
- `flm validate` uses the DRM device directly while `flm run` goes through XRT — a
  passing validate does not guarantee XRT can open device index 0. If `flm run` fails
  with `No such device with index '0'`, check `xrt-smi examine` first.
- The box is created with `--device /dev/accel/accel0`, so the device must exist on
  the host **before** `tools create` / `tools setup` runs.
