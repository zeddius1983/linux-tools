# unsloth

Fast LLM fine-tuning with [Unsloth](https://unsloth.ai/) on AMD GPU via ROCm. The container provides a Python 3.11 venv with PyTorch (ROCm 7.2), `unsloth[amd]`, and ROCm-compatible bitsandbytes pre-installed.

## Install

```bash
tools setup unsloth
```

## Exported commands

### `unsloth` — Python runner

Runs a Python script inside the Unsloth venv with AMD GPU env vars set:

```bash
unsloth train.py
unsloth -c "from unsloth import FastLanguageModel; print('ok')"
```

The `HF_TOKEN` environment variable is inherited from the host shell — set it before running if your model requires authentication:

```bash
export HF_TOKEN=hf_...
unsloth train.py
```

### `unsloth-studio` — Unsloth Studio web UI

Starts Unsloth Studio on port 8888:

```bash
unsloth-studio
# Open http://localhost:8888 in your browser
```

> **AMD limitation**: Training inside Unsloth Studio does not yet support AMD GPUs. Chat and Data Recipes features work. Training with AMD GPU support is tracked as "coming soon" by the Unsloth team. For AMD-accelerated fine-tuning, use `unsloth train.py` directly.

## Persistent storage

HuggingFace model cache: `~/.cache/huggingface/` (shared with host via Distrobox `$HOME`)

## Fine-tuning example

```python
from unsloth import FastLanguageModel
import torch

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/Llama-3.2-1B-Instruct",
    max_seq_length=2048,
    load_in_4bit=True,
)
```

Save as `train.py` and run with `unsloth train.py`.

## Notes

- Port 8888 used by `unsloth-studio`. Distrobox uses `--network host` so no port mapping needed.
- The container uses ROCm 7.2.4 with PyTorch wheels from `download.pytorch.org/whl/rocm7.2`.
- bitsandbytes is installed from the Unsloth-recommended GitHub release URL — the PyPI version does not support ROCm.
