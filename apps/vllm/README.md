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
torch.compile took X s in total
Capturing CUDA graphs (PIECEWISE): 34%|███ | 17/51
Starting vLLM server on http://0.0.0.0:8000
Application startup complete.
```

The result is cached in `~/.cache/vllm`, so starting the same model again with the same flags is quick — but the cache is keyed on the configuration, so changing flags recompiles (changing `--max-num-seqs` alone was enough to cost a fresh two-minute compile on a 27B model). To skip compilation entirely (much slower per token, up in under a minute), add `--enforce-eager`; it is the fastest way to check the GPU works at all. `VLLM_LOGGING_LEVEL=DEBUG` logs each sub-graph as it compiles.

### Larger models on Strix Halo

Memory is unified here, and `--gpu-memory-utilization` is a fraction of the GPU's *total* memory — all ~124 GB on a 128 GB Ryzen AI Max machine — not of what is free. vLLM does not account for other processes, so size it yourself: weights plus the KV cache you want. 0.35 is ~43 GB.

**int4 is what makes 27–31B models practical.** Tested on gfx1151 with vLLM 0.29.0:

| Format | Works here? | Notes |
|---|---|---|
| AWQ (int4) | ✅ | Triton kernels; greedy output matches the unquantized model |
| compressed-tensors w4a16 | ✅ | uses the dedicated `RDNAHybridW4A16LinearKernel` |
| FP8 | ❌ | engine fails to initialise — RDNA3.5 has no FP8 support in this build |
| MXFP4 / MXFP8 | ❌ | the AMD fast path is gated to a newer architecture (gfx1250) |
| NVFP4 | ❌ | NVIDIA-targeted; its quantization kernel is not in the ROCm build |

Check a repo's format before downloading it: plenty of recent quantized uploads are NVFP4 or FP8 only (at the time of writing, every quantized Qwen3.8-27B build), and neither runs here. Some that do:

| Model | Format | Weights |
|---|---|---|
| `google/gemma-4-31B-it-qat-w4a16-ct` | compressed-tensors, QAT | 23.3 GB |
| `cyankiwi/Qwen3.6-27B-AWQ-INT4` | AWQ | 20.4 GB |
| `cyankiwi/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit` | AWQ, MoE (~3B active) | 18.1 GB |
| `google/gemma-4-12B-it-qat-w4a16-ct` | compressed-tensors, QAT | 10.3 GB |

A working command for a local, single-user server:

```bash
VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0 \
vllm-serve cyankiwi/Qwen3.6-27B-AWQ-INT4 \
  --max-model-len 16384 --gpu-memory-utilization 0.35 \
  --max-num-seqs 32 --language-model-only
```

- **`--max-num-seqs 32`** is required for hybrid models such as Qwen3.5/3.6 once GPU graphs are on. Without it startup fails after several minutes with `max_num_seqs (256) exceeds available Mamba cache blocks`. It also cuts graph capture from 51 shapes to 11, and the memory those graphs pin from 2.5 GB to 0.6 GB.
- **`VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0`** skips an extra graph capture that exists only to estimate memory. Environment variables set on the host reach the server.
- **`--language-model-only`** skips the vision encoder's profiling and warmup. Leave it off if you send images.
- **Keep the flags the same between restarts**, since they are part of the compile cache key.

Even with a warm cache, a 27B model takes roughly two minutes to open its port — reading and repacking weights, a profiling run, and graph capture all happen on every start. That is the cost of vLLM's server design; [`llama-cpp`](../llama-cpp/README.md) opens a model of the same size in seconds. If you restart often, or only ever chat alone, llama.cpp is the better fit — vLLM earns its startup back under concurrent load.

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

### Downloading models

Download ahead of time rather than letting `vllm-serve` fetch the model. The server prints `Loading model from scratch...` *before* the weights arrive, so a slow or stuck download inside it looks exactly like a stuck server.

```bash
distrobox enter vllm-box -- hf download cyankiwi/Qwen3.6-27B-AWQ-INT4
```

If a download crawls, turn off Hugging Face's Xet transfer layer. On this machine Xet ran ~9× slower than the classic downloader (1.1 vs 10 MB/s, measured at the same time on the same connection), and once stopped moving data altogether while still logging activity:

```bash
HF_HUB_DISABLE_XET=1 distrobox enter vllm-box -- hf download <repo>
```

Interrupted downloads do not resume: each attempt writes its partial files under a new name, and the next run deletes the old ones.

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
- vLLM claims 90% of GPU memory by default. On an APU that means 90% of *system* memory, so always pass `--gpu-memory-utilization` — see [Larger models on Strix Halo](#larger-models-on-strix-halo) for sizing it.
- `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` enables a Flash Attention Triton backend that vLLM hints at in its log. On Qwen3.6 it changes only the vision encoder's attention — text generation stays on the same backend — so it does not speed up chat.
- A model that won't fit is an out-of-memory error at load time, not a slow run — drop `--max-model-len`, use a quantized checkpoint, or pick a smaller model.
