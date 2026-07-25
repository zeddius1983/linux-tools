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
| **IOMMU enabled** | The driver binds the process address space via IOMMU SVA. `amd_iommu=off` on the kernel command line makes every open of the NPU fail with `SVA bind device failed, ret -19` — the device probes and `/dev/accel/accel0` exists, but nothing can use it. |
| memlock rlimit | `*  soft  memlock  unlimited` + `*  hard  memlock  unlimited` in `/etc/security/limits.conf`, then reboot |
| Group membership | Your host user must be in the group owning `/dev/accel/accel0` (usually `render`) |

Run `flm-doctor` to check all of these at once — it reads the host kernel, driver,
IOMMU and firmware state from inside the box and reports what is missing.

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
