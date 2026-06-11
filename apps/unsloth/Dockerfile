FROM docker.io/rocm/dev-ubuntu-24.04:7.2.4-complete

RUN apt-get update \
    && apt-get install -y \
       python3.11 python3.11-venv python3.11-dev python3-pip git curl \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

RUN python3.11 -m venv /opt/unsloth

RUN /opt/unsloth/bin/pip install --upgrade pip uv

# PyTorch with ROCm 7.2 wheels (rocm7.2 starts at torch 2.11.0; no upper cap needed)
RUN /opt/unsloth/bin/uv pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/rocm7.2

RUN /opt/unsloth/bin/uv pip install "unsloth[amd]"

# ROCm-compatible bitsandbytes — PyPI release does not support ROCm
RUN /opt/unsloth/bin/pip install --force-reinstall --no-cache-dir --no-deps \
    "https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_x86_64.whl"

# Python runner: sets AMD env vars, delegates to venv Python
RUN printf '#!/usr/bin/env bash\n\
export HF_HUB_DISABLE_XET=1\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
exec /opt/unsloth/bin/python "$@"\n\
' > /usr/bin/unsloth && chmod +x /usr/bin/unsloth

# Studio launcher: AMD training not yet supported; chat + data recipes work
RUN printf '#!/usr/bin/env bash\n\
export HF_HUB_DISABLE_XET=1\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
echo "Unsloth Studio starting on http://localhost:8888"\n\
exec /opt/unsloth/bin/unsloth studio -H 0.0.0.0 -p 8888 "$@"\n\
' > /usr/bin/unsloth-studio && chmod +x /usr/bin/unsloth-studio

CMD ["/bin/bash"]
