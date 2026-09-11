# llama-cpp-rocm

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

llama.cpp LLM inference engine with AMD GPU acceleration via both ROCm and Vulkan backends, packaged as a Distrobox container.

Compiled from source against ROCm 7.2.4 with the Vulkan backend built alongside (`GGML_BACKEND_DL` dynamic backend loading). Each install builds the latest upstream [release tag](https://github.com/ggml-org/llama.cpp/releases) (resolved at build time; `llama-server --version` reports it). Supports GGUF models for chat, HTTP API serving, quantization, and HuggingFace model conversion — all via a single `llama` dispatcher command. Pick the GPU backend per run with `--device`.

## Install

```bash
tools setup llama-cpp-rocm
```

When run interactively, a wizard screen lets you pick which upstream release to build from the 10 latest tags (default: latest), with each tag's release notes shown beside the list (`PgDn`/`PgUp` scrolls them). Non-interactive installs build the latest release automatically. llama.cpp marks nearly every build as a pre-release, so that label next to the date is normal.

Build time: ~10–20 minutes (ROCm/HIP compilation for all GPU architectures).

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

### Choosing a GPU backend (ROCm vs Vulkan)

Both backends are compiled in as dynamically loaded plugins, so the same physical GPU shows up twice — once per backend:

```bash
llama-server --list-devices
# ROCm0:   AMD Radeon Graphics ...
# Vulkan0: AMD Radeon Graphics (RADV ...) ...
```

Select one explicitly with `--device` (works on `llama-cli` and `llama-server`):

```bash
llama-server -m ~/models/model.gguf --device ROCm0 -ngl 99
llama-server -m ~/models/model.gguf --device Vulkan0 -ngl 99
```

Without `--device`, llama.cpp picks by backend priority (ROCm first). On Strix Halo (gfx1151) Vulkan often matches or beats ROCm depending on model and quantization — benchmark both with `llama -b -m model.gguf --device <dev>`.

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
distrobox enter llama-cpp-rocm-box
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

# Compare GPU backends
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
tools enter llama-cpp-rocm       # via tools
distrobox enter llama-cpp-rocm-box  # directly
```

Inside the box, all binaries are at `/opt/llama-cpp/`: `llama-cli`, `llama-server`, `llama-quantize`, `llama-bench`, `llama-gguf-split`, and others.

## GPU notes

- Uses `/dev/kfd` and `/dev/dri` for ROCm compute access; Vulkan needs only `/dev/dri` (Mesa RADV inside the container).
- Set `HSA_ENABLE_SDMA=0` if you see hangs on Strix Halo / gfx1151 (ROCm backend only).
- No MIOpen kernel caching — llama.cpp uses HIP directly without MIOpen.
- `-ngl <n>` flag controls how many layers to offload to GPU (`-ngl 99` for all layers).
- `vulkaninfo --summary` (inside the box) shows the Vulkan device if the Vulkan backend isn't listed by `--list-devices`.
