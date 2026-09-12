# vllm

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[vLLM](https://github.com/vllm-project/vllm) — a high-throughput, OpenAI-compatible LLM inference server — on an AMD or NVIDIA GPU, packaged as a Distrobox container.

Built on the official upstream images, so the GPU stack and PyTorch come pre-installed and matched: [`vllm/vllm-openai-rocm`](https://hub.docker.com/r/vllm/vllm-openai-rocm) for AMD, [`vllm/vllm-openai`](https://hub.docker.com/r/vllm/vllm-openai) for NVIDIA. The server speaks the OpenAI API on port 8000, which means any OpenAI client SDK — Python, JS, `curl`, or an editor plugin — points at it unchanged. Models are pulled from HuggingFace on first use and cached in `~/.cache/huggingface`.

## Install

```bash
tools setup vllm
```

Run interactively, setup asks two questions:

1. **GPU backend** — AMD (ROCm) or NVIDIA (CUDA). This picks both the upstream image and the container's GPU passthrough.
2. **Release** — one of the 10 newest vLLM releases, or `latest`, or `nightly`. Each release's notes are shown beside the list (`PgDn`/`PgUp` scrolls them); the newest release is the default.

Non-interactive installs build the AMD variant on `:latest`.

Re-running `tools setup vllm` rebuilds from scratch, which is how you move between versions or switch backends — it is a rebuild, not a repair, so it re-pulls the image. The HuggingFace model cache lives in `$HOME` and survives it.

Expect a long first install: these images are 15–25 GB.

### GPU backends

| Wizard choice | Image | Passthrough |
|---|---|---|
| AMD (ROCm) | `vllm/vllm-openai-rocm` | `/dev/kfd` + `/dev/dri`, `video`/`render` groups |
| NVIDIA (CUDA) | `vllm/vllm-openai` | CDI `nvidia.com/gpu=all` |

There is no single image that serves both: vLLM's kernels and the PyTorch underneath them are compiled per accelerator, so each install is one backend. `cat /etc/vllm-gpu` inside the box says which one you have.

#### NVIDIA prerequisite — the CDI spec

`--device nvidia.com/gpu=all` needs a CDI spec on the **host**:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Regenerate it after every driver update — the spec pins driver library paths — or install [`nvidia-cdi-service`](../nvidia-cdi-service/README.md), which does that on every boot. Verify with `nvidia-ctk cdi list`; without the spec, `tools setup` fails at container-create time with podman's `no such device nvidia.com/gpu=all`.

Do **not** swap this for `distrobox create --nvidia`. On a rootless-podman host it bind-mounts the entire host driver on every start and can wedge in a remount loop — the post-mortem is in [`apps/lmstudio/README.md`](../lmstudio/README.md).

## Commands

Two commands are exported to the host:

| Command | Purpose |
|---|---|
| `vllm` | The full vLLM CLI — `serve`, `chat`, `complete`, `bench`, `run-batch`, `collect-env` |
| `vllm-serve` | Convenience wrapper around `vllm serve`: binds `0.0.0.0:8000` and applies this build's backend environment |

`vllm-serve` passes every argument through to the server, so any flag from `vllm serve` works on it too.

## Usage

### Start a server

```bash
# Small model, good for checking the box works end to end
vllm-serve Qwen/Qwen3-0.6B

# A real one, with an explicit context length (--model works too)
vllm-serve --model meta-llama/Llama-3.1-8B-Instruct --max-model-len 8192

# The plain CLI is the same command without the wrapper's defaults: no
# 0.0.0.0:8000 binding, and none of the backend environment below
vllm serve Qwen/Qwen3-0.6B
```

The server is reachable on the host at `http://localhost:8000` with no port mapping — Distrobox containers run with `--network host`.

**The first start of a given model is slow, and looks like a hang.** vLLM compiles the model with `torch.compile`, captures GPU graphs, then profiles the KV cache — and only then opens the port, so `curl` is refused the entire time. On this hardware Qwen3-0.6B took ~9 minutes, nearly all of it single-core compilation. Wait for these lines:

```
torch.compile takes X s in total
Capturing CUDA graph shapes: 34%|███ | 17/51
Starting vLLM API server on http://0.0.0.0:8000
Application startup complete.
```

The result is cached in `~/.cache/vllm`, so starting the same model again with the same flags is quick — the cache is keyed on the config, so changing `--max-model-len`, dtype or the model recompiles. To skip compilation entirely (much slower per token, up in under a minute), add `--enforce-eager`; it is the fastest way to check the GPU works at all. `VLLM_LOGGING_LEVEL=DEBUG` logs each sub-graph as it compiles.

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

Reasoning models (Qwen3 among them) spend the response on a `<think>` block first, so a small `max_tokens` can return nothing but reasoning. Raise it, or turn thinking off per request with `"chat_template_kwargs": {"enable_thinking": false}`.

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
| `~/.cache/miopen` | Compiled MIOpen kernels (AMD build only) |
| `~/.cache/vllm` | vLLM's own compiled-graph cache |

All of these are on the host via Distrobox's shared `$HOME`, so they persist across rebuilds and are shared with any other app that uses the same caches (`comfyui`, `unsloth`).

The first load of a given model compiles GPU kernels, which is slow; loading the same model again reuses those caches and is not.

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

Inside the box, the real CLI is at `/usr/local/bin/vllm`, and on the ROCm image `python` is the system Python with vLLM importable (no venv). `cat /etc/vllm-gpu` says which backend the box was built for, and `vllm collect-env` prints the GPU/PyTorch details worth attaching to an upstream bug report.

## GPU notes

- The AMD box gets `/dev/kfd` and `/dev/dri`, the `video` (44) and `render` (992) groups, `--ipc=host` for shared memory, and `SYS_PTRACE` for PyTorch's internals; the NVIDIA box swaps the first for the CDI device. These live in `create_flags` and `create_flags.nvidia`; check your own GIDs with `getent group render video` if the container fails to see the GPU.
- On the AMD build, `vllm-serve` sets the Strix Halo (gfx1151) workarounds for you (they live in `/etc/vllm-env`, which the wrapper sources; the CUDA build's copy is empty, because none of them mean anything there):

  ```
  HSA_ENABLE_SDMA=0
  PYTORCH_HIP_ALLOC_CONF=expandable_segments:True
  TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
  TORCH_BLAS_PREFER_HIPBLASLT=1
  ```

  Set them yourself if you invoke `vllm serve` directly instead.
- vLLM allocates 90% of VRAM for the KV cache by default. On an APU where the GPU shares system memory, `--gpu-memory-utilization 0.7` (or lower) leaves the rest of the desktop something to work with.
- A model that won't fit is an out-of-memory error at load time, not a slow run — drop `--max-model-len`, use a quantized checkpoint, or pick a smaller model.
