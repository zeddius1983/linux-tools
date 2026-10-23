# strata

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[Strata](https://github.com/Niko1221/Strata) runs **Qwen3.8-Flash-Next**, a
125-billion-parameter mixture-of-experts model, on one consumer GPU plus system
RAM. The most-used experts are kept on the GPU, the rest in RAM, and a small draft
layer guesses ahead. It serves the OpenAI, Anthropic and Responses APIs, plus a
web chat page, on `http://127.0.0.1:8080`.

Strata is **not a general model runner**. Its engine is written for two model
families only: Qwen3.8-Flash-Next and its variants (Coder, Swift 1.5, Gyro,
Unsloth UD quants, NVFP4), and Qwen3.6-35B-A3B. For any other model, use
[`llama-cpp`](../llama-cpp/README.md), [`lmstudio`](../lmstudio/README.md) or
[`vllm`](../vllm/README.md).

This box packages the **Strata Terminal** (the `strata` command), not the
desktop AppImage. The Terminal has the same engine and models, and serves the
same web chat page.

## Install

```bash
tools setup strata
```

Two setup questions, both also available as command-line parameters
(`tools help strata` lists them):

| Parameter | Values | Default |
|---|---|---|
| `STRATA_GPU` | `amd` (`/dev/kfd` + `/dev/dri`), `nvidia` (CDI `nvidia.com/gpu=all`) | `amd` |
| `STRATA_REF` | `latest`, or a release tag from `v0.2.0-beta` on | `latest` |

```bash
tools setup strata STRATA_REF=v0.2.3.1
tools setup strata STRATA_GPU=nvidia
```

The image is the same for both GPUs. `STRATA_GPU` picks the device passthrough
and sets `STRATA_ENGINE_BACKEND` (`hip` or `cuda`) in the box, so the engine
downloaded on first use is for that make even on a PC with both AMD and NVIDIA
cards. Strata itself would otherwise prefer NVIDIA.

## Exported commands

| Command | What it does |
|---|---|
| `strata` | the Strata Terminal (on `PATH` via `~/.local/bin`) |
| **Strata** (app menu) | runs `strata launch`'s guided screens in a terminal window |

```bash
strata launch                                  # guided: model, context, pictures, access, then serve
strata launch --plan --model q2_0              # what would happen and how much it downloads; changes nothing
strata launch --model q2_0 --yes --no-tui      # no questions: download, serve, print the address, return
strata launch --status                         # what is serving now
strata launch --stop                           # stop it
strata monitor                                 # speed, GPU, memory and requests
strata models list                             # installed models
strata connect                                 # settings for OpenCode, Codex CLI, Claude Code, ...
strata update --check                          # is there a newer engine?
strata doctor                                  # check the installed engine files
```

A real `strata launch` downloads the GPU engine first, then the model, the
draft layer and the picture reader. Q2_0 at 128K context is about 72.5 GB in
total. `--plan` prints the exact amount. Downloads resume where they stopped.

### Which size

Strata counts RAM plus GPU memory. On a unified-memory machine (Strix Halo), it
counts the shared pool once.

| Memory | Size |
|---|---|
| 32 GB | `gyro-s`, or the Coder for code |
| 40 GB | Swift 1.5 IQ2_XS, or `gyro-m` |
| 48 GB | `iq3_xxs` |
| 64 GB | `iq3_s` |
| 96 GB+ | Unsloth UD-IQ4_XS to Q8_0 (`strata launch` offers them; on Strix Halo upstream recommends UD-IQ4_XS from about 80 GB) |

Full list: upstream's [MODELS.md](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md).

### Your own model files

A GGUF of a supported model (another quant, or a fine-tune with the same
architecture) can be used in place:

```bash
strata models import /path/to/folder --plan    # recognise the files, change nothing
strata launch --model-path /path/to/folder --no-tui
```

## Connecting other apps

| API | Base URL |
|---|---|
| OpenAI-compatible | `http://127.0.0.1:8080/v1` (any key, any model name) |
| Anthropic (Claude Code) | `ANTHROPIC_BASE_URL=http://127.0.0.1:8080` (no `/v1`) |
| OpenAI Responses (Codex CLI) | `http://127.0.0.1:8080/v1/responses` |

The box shares the host's network, so other boxes (`claude-code`, `codex-cli`,
`opencode`) reach it on `127.0.0.1` too. `strata connect <app> --write` writes
an app's config file, after asking, and keeps a backup.

**Port 8080** is also `llama-server`'s default. To run both, give one of them
another port: `strata launch --port 8081`.

## Storage

Everything lives in the shared `$HOME`, so `tools setup strata` (which rebuilds
the box) keeps all of it:

| Path | Contents | Size |
|---|---|---|
| `~/.local/share/strata/components/` | the GPU engine and Control, from `strata update` | ~0.2–1 GB per version |
| `~/.local/share/strata/install/` | run configs (`strata-<model>.json`) and their logs | small |
| the data folder (under `~/.local/share/strata/` unless `strata launch --data-dir` names one; remembered in `~/.config/strata/settings.json`) | models, prepared packs, draft layers | 40–190 GB |
| `~/.local/state/strata/` | presets, tuning results, API keys | small |

To keep the models on another disk: `strata launch --data-dir /mnt/big/strata`.
`--move-data` moves the models that are already downloaded.

## Updating

- **Terminal:** it is baked into the image, so `tools setup strata` updates it.
- **Engine:** `strata update` installs a newer engine for the current Terminal,
  after a test start. `strata components rollback` goes back. The engine also
  comes with a fresh `strata launch` after a rebuild.

## GPU notes

- **AMD:** the box gets `/dev/kfd` and `/dev/dri` with the `render` (992) and
  `video` (44) GIDs, as the other ROCm boxes do. The host needs only the
  kernel's `amdgpu` driver. ROCm comes inside the engine package.
- **Strix Halo (gfx1151):** gets the `hip-halo` engine. The GPU can only use as
  much of the shared RAM as the GTT pool allows, and the kernel default is
  about half of the RAM. Raise it on the host kernel command line, e.g.
  `amdgpu.gttsize=126976 ttm.pages_limit=32505856` for about 124 GiB on a
  128 GB machine. Upstream marks this chip experimental.
- **NVIDIA:** needs the host's CDI spec (`/etc/cdi/nvidia.yaml`, see
  [`nvidia-cdi-service`](../nvidia-cdi-service/README.md)) and driver 580+ for
  the `cuda13` engine (older drivers get `cuda12`).
- **Locked memory:** Strata locks part of the model in RAM for the GPU. A
  rootless box cannot go above the host user's hard `memlock` limit (`ulimit
  -Hl`), so it is not raised in `create_flags`. With a low limit Strata warns
  and runs. To raise the limit, add a host `/etc/security/limits.d/` drop-in
  (`* hard memlock unlimited`, `* soft memlock unlimited`), then log in again
  and run `tools setup strata`.

## Notes

- **The server outlives the command.** `strata launch --no-tui` starts the
  server and returns, and the server keeps running inside `strata-box`. Stop it
  with `strata launch --stop`. `distrobox stop strata-box` also ends it.
- **First start:** loading 40–70 GB into RAM can make the desktop slow for a
  minute or two. That is expected.
- **Privacy:** no telemetry. The internet is used only for downloads, and for
  web search if you turn it on in the chat. Upstream's
  [SAFETY.md](https://github.com/Niko1221/Strata/blob/main/docs/SAFETY.md) has
  the details.
