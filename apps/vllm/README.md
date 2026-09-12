# vllm

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[vLLM](https://github.com/vllm-project/vllm) — a high-throughput, OpenAI-compatible LLM inference server — with AMD GPU acceleration via ROCm, packaged as a Distrobox container.

Built on the official [`vllm/vllm-openai-rocm`](https://hub.docker.com/r/vllm/vllm-openai-rocm) image, so ROCm and PyTorch come pre-installed and matched. The server speaks the OpenAI API on port 8000, which means any OpenAI client SDK — Python, JS, `curl`, or an editor plugin — points at it unchanged. Models are pulled from HuggingFace on first use and cached in `~/.cache/huggingface`.

## Install

```bash
tools setup vllm
```

When run interactively, a wizard screen picks which image to install: `latest`, one of the 10 most recent `vX.Y.Z` release images, or `nightly`. The version list comes from the published Docker Hub tags — so every choice is an image that actually exists — and each release's notes from GitHub are shown beside it (`PgDn`/`PgUp` scrolls them). Non-interactive installs take `latest`.

Re-running `tools setup vllm` rebuilds from scratch, which is how you move between versions. The HuggingFace model cache lives in `$HOME` and survives the rebuild.

Expect a long first install: these images are 15–25 GB.

## Commands

Two commands are exported to the host:

| Command | Purpose |
|---|---|
| `vllm` | The full vLLM CLI — `serve`, `chat`, `complete`, `bench`, `run-batch`, `collect-env` |
| `vllm-serve` | Convenience wrapper: starts the OpenAI server on `0.0.0.0:8000` with the Strix Halo ROCm env vars already set |

`vllm-serve` passes every argument through to the server, so any flag from `vllm serve` works on it too.

## Usage

### Start a server

```bash
# Small model, good for checking the box works end to end
vllm-serve --model Qwen/Qwen3-0.6B

# A real one, with an explicit context length
vllm-serve --model meta-llama/Llama-3.1-8B-Instruct --max-model-len 8192

# Same thing through the plain CLI (model is positional here, and none of the
# ROCm env vars below are set for you)
vllm serve Qwen/Qwen3-0.6B
```

The server is reachable on the host at `http://localhost:8000` with no port mapping — Distrobox containers run with `--network host`.

### Query it

```bash
curl http://localhost:8000/v1/models

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 256
  }'
```

From an OpenAI SDK, point the base URL at it and use any non-empty key:

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1", api_key="EMPTY")
print(client.chat.completions.create(
    model="Qwen/Qwen3-0.6B",
    messages=[{"role": "user", "content": "Hello!"}],
).choices[0].message.content)
```

### Benchmark

```bash
vllm bench latency --model Qwen/Qwen3-0.6B
vllm bench throughput --model Qwen/Qwen3-0.6B --num-prompts 100
```

## Model storage

| Path | Contents |
|---|---|
| `~/.cache/huggingface` | Downloaded model weights and tokenizers |
| `~/.cache/miopen` | Compiled MIOpen GPU kernels |

Both are on the host via Distrobox's shared `$HOME`, so they persist across rebuilds and are shared with any other app that uses the same caches (`comfyui`, `unsloth`).

The first load of a given model compiles GPU kernels, which is slow; the second load of the same model reuses `~/.cache/miopen` and is not.

### Gated models

Models behind a HuggingFace licence (Llama, some Mistral builds) need a token. It is not baked into the image — the container inherits it from your host shell:

```bash
export HF_TOKEN=hf_...   # in ~/.bashrc or ~/.zshrc
```

Better, keep it in the keyring and read it in your rc file:

```bash
secret-tool store --label="HF token" service huggingface key token
export HF_TOKEN="$(secret-tool lookup service huggingface key token)"
```

## Shell access

```bash
tools enter vllm             # via tools
distrobox enter vllm-box     # directly
```

Inside the box, `python` is the system Python with vLLM installed (no venv), and the real CLI is at `/usr/local/bin/vllm`. `vllm collect-env` prints the ROCm/PyTorch/GPU details worth attaching to an upstream bug report.

## GPU notes

- The box gets `/dev/kfd` and `/dev/dri`, the `video` (44) and `render` (992) groups, `--ipc=host` for ROCm shared memory, and `SYS_PTRACE` for PyTorch's internals. These are set in `create_flags`; check your own GIDs with `getent group render video` if the container fails to see the GPU.
- `vllm-serve` sets the Strix Halo (gfx1151) workarounds for you:

  ```
  HSA_ENABLE_SDMA=0
  PYTORCH_HIP_ALLOC_CONF=expandable_segments:True
  TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
  TORCH_BLAS_PREFER_HIPBLASLT=1
  ```

  Set them yourself if you invoke `vllm serve` directly instead.
- vLLM allocates 90% of VRAM for the KV cache by default. On an APU where the GPU shares system memory, `--gpu-memory-utilization 0.7` (or lower) leaves the rest of the desktop something to work with.
- A model that won't fit is an out-of-memory error at load time, not a slow run — drop `--max-model-len`, use a quantized checkpoint, or pick a smaller model.
