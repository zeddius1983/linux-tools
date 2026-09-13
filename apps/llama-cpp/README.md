# llama-cpp

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

llama.cpp LLM inference engine, compiled from source for the GPU stack you pick at install time — **ROCm 7.2**, **ROCm 10.0** or **NVIDIA CUDA** — with the Vulkan backend built alongside in every variant, packaged as a Distrobox container.

Backends are dynamically loaded plugins (`GGML_BACKEND_DL`), so one GPU shows up once per backend and you pick per run with `--device`. Each install builds an upstream [release tag](https://github.com/ggml-org/llama.cpp/releases) (`llama-server --version` reports it). Supports GGUF models for chat, HTTP API serving, quantization, and HuggingFace model conversion — all via a single `llama` dispatcher command.

## Install

```bash
tools setup llama-cpp
```

Run interactively, the wizard asks two questions:

1. **GPU runtime** — picks the build toolchain, the runtime base image *and* the container's GPU passthrough:

   | Choice | Base image | Backends | Passthrough |
   |---|---|---|---|
   | **ROCm 7.2** (default) | `rocm/dev-ubuntu-24.04:7.2.4-complete` | `ROCm0` + `Vulkan0` (Mesa RADV) | `/dev/kfd` + `/dev/dri` |
   | **ROCm 10.0** | `rocm/dev-ubuntu-24.04:10.0.0-full` | `ROCm0` + `Vulkan0` (Mesa RADV) | `/dev/kfd` + `/dev/dri` |
   | **NVIDIA (CUDA)** | `nvidia/cuda:12.8.1-devel` → `-runtime` | `CUDA0` + `Vulkan0` (NVIDIA driver) | CDI `nvidia.com/gpu=all` |

2. **Release** — one of the 10 latest upstream tags (default: the newest), with each tag's release notes shown beside the list (`PgDn`/`PgUp` scrolls them). llama.cpp marks nearly every build as a pre-release, so that label next to the date is normal.

Both answers are baked in at build time: re-run `tools setup llama-cpp` to switch runtime or release. Models live wherever you keep them in `$HOME`, so they survive the rebuild. `cat /etc/llama-cpp-gpu` inside the box shows which runtime it was built as.

Build time: ~10–20 minutes (ROCm/HIP or CUDA kernels compiled for every supported GPU architecture).

This app used to be called `llama-cpp-rocm`. The first `tools setup llama-cpp` removes the old `llama-cpp-rocm-box` and its image; the exported command names are unchanged.

### Non-interactive install

With no wizard (a scripted `tools setup llama-cpp`, or a non-tty shell) you get **ROCm 7.2 at the newest release**. To pin either answer, hand `tools` a wizard state file:

```bash
cat > /tmp/llama-cpp.state <<'EOF'
APP="llama-cpp"
ACTION="setup"
BUILD_ARGS="--build-arg LLAMA_GPU=cuda --build-arg LLAMA_REF=b10948"
VARIANT="cuda"
EOF

LT_SKIP_WIZARD=1 LT_WIZARD_STATE=/tmp/llama-cpp.state tools setup llama-cpp
```

`BUILD_ARGS` and `VARIANT` must agree: `LLAMA_GPU` picks the image, `VARIANT` picks `create_flags.<variant>`. A CUDA image created with the default (AMD) flags has no GPU at all. `rocm10` has no flags file of its own and uses the default `create_flags`, same as `rocm`.

To cut build time while testing, limit the architectures: `--build-arg ROCM_DOCKER_ARCH=gfx1151` (ROCm) or `--build-arg CUDA_DOCKER_ARCH=89` (CUDA).

### NVIDIA prerequisite — the CDI spec

The CUDA variant exposes the GPU with `--device nvidia.com/gpu=all`, which needs a CDI spec on the **host** — the [`nvidia-cdi-service`](../nvidia-cdi-service/README.md) app keeps one current, or by hand:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Without it, `tools setup` fails at container-create time with podman's `no such device nvidia.com/gpu=all`. The CUDA 12.8 build needs host driver **≥ 570**. Do **not** use `distrobox create --nvidia` — see [`apps/lmstudio/README.md`](../lmstudio/README.md) for why.

The Vulkan backend on NVIDIA uses the host driver's own Vulkan ICD, which the CDI spec mounts into the box; the image deliberately ships no Mesa drivers.

## Commands

Four commands are exported to the host:

| Command | Purpose |
|---|---|
| `llama` | Unified dispatcher — routes to the right binary based on the first flag |
| `llama-cli` | Direct access to the llama-cli inference binary |
| `llama-server` | Direct access to the llama-server HTTP API binary |
| `llama-bench` | Direct access to the llama-bench benchmarking binary |

### `llama` dispatcher

```
llama --run      / -r   Run chat inference (llama-cli)
llama --server   / -s   Start HTTP API server (llama-server)
llama --quantize / -q   Quantize a GGUF model
llama --convert  / -c   Convert a HuggingFace model to GGUF
llama --bench    / -b   Benchmark inference performance
llama --perplexity / -p Measure model perplexity
```

## Usage

### Choosing a GPU backend (ROCm/CUDA vs Vulkan)

The GPU backend and Vulkan are both compiled in as dynamically loaded plugins, so the same physical GPU shows up twice — once per backend:

```bash
llama-server --list-devices
# ROCm variants:
# ROCm0:   AMD Radeon Graphics ...
# Vulkan0: AMD Radeon Graphics (RADV ...) ...
# CUDA variant:
# CUDA0:   NVIDIA GeForce ...
# Vulkan0: NVIDIA GeForce ...
```

Select one explicitly with `--device` (works on `llama-cli` and `llama-server`):

```bash
llama-server -m ~/models/model.gguf --device ROCm0 -ngl 99    # ROCm variants
llama-server -m ~/models/model.gguf --device CUDA0 -ngl 99    # CUDA variant
llama-server -m ~/models/model.gguf --device Vulkan0 -ngl 99  # any variant
```

Without `--device`, llama.cpp picks by backend priority (ROCm/CUDA before Vulkan). On Strix Halo (gfx1151) Vulkan often matches or beats ROCm depending on model and quantization — benchmark both with `llama -b -m model.gguf --device <dev>`.

**Compare backends only with the model fully on the GPU, or with the same `-ngl` on both.** When a model doesn't fit, llama.cpp chooses how many layers to offload per backend, based on the memory each one reports and its own buffer sizes. CUDA and Vulkan can land on different splits, so a comparison through `llama-server` measures the splits, not the backends. A model that doesn't fit shows up as `offloaded N/M layers to GPU` with N < M in the startup log. For a fair comparison, fix the layer count:

```bash
llama-bench -m ~/models/model.gguf -dev CUDA0,Vulkan0 -ngl 99 -fa 1   # lower -ngl if it runs out of memory
```

### Chat

```bash
llama -r -m ~/models/model.gguf
llama -r -m ~/models/model.gguf -n 512 -p "Explain quantum entanglement:"
```

### HTTP API server

Start with the dispatcher:

```bash
llama -s -m ~/models/model.gguf --port 8080 --ctx-size 4096
```

Or use the direct binary (full flag control):

```bash
llama-server -m ~/models/model.gguf --host 0.0.0.0 --port 8080 --ctx-size 4096
# On Strix Halo (gfx1151), set HSA_ENABLE_SDMA=0 if you see hangs:
HSA_ENABLE_SDMA=0 llama-server -m ~/models/model.gguf --host 0.0.0.0 --port 8080
```

Query the API (OpenAI-compatible):

```bash
# Health check
curl http://localhost:8080/health

# List loaded model
curl http://localhost:8080/v1/models

# Chat completion
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 256
  }'
```

### Quantize a model

```bash
# Q4_0 quantization (good balance of size and quality)
llama -q input.gguf output-q4_0.gguf q4_0

# Q8_0 (higher quality, larger file)
llama -q input.gguf output-q8_0.gguf q8_0
```

Available quant types: `q4_0`, `q4_1`, `q5_0`, `q5_1`, `q8_0`, `q2_k`, `q3_k_m`, `q4_k_m`, `q5_k_m`, `q6_k`.

### Convert HuggingFace model to GGUF

Basic conversion (requires the model downloaded locally):

```bash
llama -c --outtype f16 ~/models/my-hf-model/
```

For full HuggingFace conversion support (safetensors, tokenizer variants), install extra Python deps inside the container first:

```bash
distrobox enter llama-cpp-box
pip install --break-system-packages torch transformers sentencepiece protobuf
exit
```

Then convert:

```bash
llama -c --outtype f16 ~/models/my-hf-model/ --outfile ~/models/model-f16.gguf
llama -q ~/models/model-f16.gguf ~/models/model-q4_k_m.gguf q4_k_m
```

### Benchmark

```bash
llama -b -m ~/models/model.gguf
llama-bench -m ~/models/model.gguf -p 512 -n 128 -r 5

# Compare GPU backends (CUDA0 instead of ROCm0 on the CUDA variant)
llama-bench -m ~/models/model.gguf --device ROCm0 -ngl 99
llama-bench -m ~/models/model.gguf --device Vulkan0 -ngl 99
```

## Model storage

llama.cpp takes model paths directly — no fixed storage directory is enforced. Any path on the host works because Distrobox shares `$HOME`:

```bash
# Example layout
~/models/
  llama-3-8b-q4_k_m.gguf
  mistral-7b-q4_0.gguf
  qwen2.5-14b-q5_k_m.gguf
```

Download GGUF models from [HuggingFace](https://huggingface.co/models?library=gguf) with `huggingface-cli` or `wget`.

## Shell access

```bash
tools enter llama-cpp         # via tools
distrobox enter llama-cpp-box # directly
```

Inside the box, all binaries are at `/opt/llama-cpp/`: `llama-cli`, `llama-server`, `llama-quantize`, `llama-bench`, `llama-gguf-split`, and others.

## GPU notes

- ROCm variants use `/dev/kfd` and `/dev/dri` for compute; Vulkan needs only `/dev/dri` (Mesa RADV inside the container). The CUDA variant gets the GPU, driver libraries and Vulkan ICD through CDI.
- **ROCm 10.0** is the newer stack (built on TheRock, gfx1151 officially supported); **ROCm 7.2** stays the default because it is the one proven on Strix Halo here. Benchmark both with `llama-bench` before switching.
- Set `HSA_ENABLE_SDMA=0` if you see hangs on Strix Halo / gfx1151 (ROCm backend only; may not be needed on ROCm 10).
- No MIOpen kernel caching — llama.cpp uses HIP directly without MIOpen.
- `-ngl <n>` flag controls how many layers to offload to GPU (`-ngl 99` for all layers).
- `vulkaninfo --summary` (inside the box) shows the Vulkan device if the Vulkan backend isn't listed by `--list-devices`.
