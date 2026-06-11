# llama-cpp

llama.cpp LLM inference engine with AMD ROCm GPU acceleration, packaged as a Distrobox container.

Compiled from source against ROCm 7.2.4. Supports GGUF models for chat, HTTP API serving, quantization, and HuggingFace model conversion — all via a single `llama` dispatcher command.

## Install

```bash
tools setup llama-cpp
```

Build time: ~10–20 minutes (ROCm/HIP compilation for all GPU architectures).

## Commands

Two commands are exported to the host:

| Command | Purpose |
|---|---|
| `llama` | Unified dispatcher — routes to the right binary based on the first flag |
| `llama-serve` | Convenience server — starts HTTP API on port 8080 with ROCm env vars pre-set |

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

Or use the convenience wrapper (port 8080, `HSA_ENABLE_SDMA=0` pre-set):

```bash
llama-serve -m ~/models/model.gguf --ctx-size 4096
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
llama -b -m ~/models/model.gguf -p 512 -n 128 -r 5
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
tools enter llama-cpp       # via tools
distrobox enter llama-cpp-box  # directly
```

Inside the box, all binaries are at `/opt/llama-cpp/`: `llama-cli`, `llama-server`, `llama-quantize`, `llama-bench`, `llama-gguf-split`, and others.

## GPU / ROCm notes

- Uses `/dev/kfd` and `/dev/dri` for ROCm compute access.
- `llama-serve` sets `HSA_ENABLE_SDMA=0` (required on Strix Halo / gfx1151).
- No MIOpen kernel caching — llama.cpp uses HIP directly without MIOpen.
- `-ngl <n>` flag controls how many layers to offload to GPU (`-ngl 99` for all layers).
