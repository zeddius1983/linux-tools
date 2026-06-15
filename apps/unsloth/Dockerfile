FROM docker.io/rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0

RUN apt-get update \
    && apt-get install -y git curl \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

# Use the pre-built venv from the base image (Python 3.12 + PyTorch 2.10.0 ROCm)
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip uv

RUN uv pip install "unsloth[amd]"

# Studio backend dependencies (not pulled in by unsloth itself)
RUN uv pip install \
    -r /opt/venv/lib/python3.12/site-packages/studio/backend/requirements/studio.txt

# ROCm-compatible bitsandbytes — PyPI release does not support ROCm
RUN pip install --force-reinstall --no-cache-dir --no-deps \
    "https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_x86_64.whl"

# unsloth_cli expects STUDIO_HOME/unsloth_studio/bin/python + a sentinel file.
# $HOME is the shared host home at runtime — create the layout on first run.
# Python runner: sets AMD env vars, delegates to venv Python
RUN printf '#!/usr/bin/env bash\n\
export HF_HUB_DISABLE_XET=1\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
exec /opt/venv/bin/python "$@"\n\
' > /usr/bin/unsloth && chmod +x /usr/bin/unsloth

# Studio launcher: sets up ~/.unsloth/studio layout on first run, then starts studio
# AMD training not yet supported; chat + data recipes work
RUN printf '#!/usr/bin/env bash\n\
export HF_HUB_DISABLE_XET=1\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
_studio_home="$HOME/.unsloth/studio"\n\
if [[ ! -L "$_studio_home/unsloth_studio" ]]; then\n\
    mkdir -p "$_studio_home/share"\n\
    ln -sf /opt/venv "$_studio_home/unsloth_studio"\n\
    touch "$_studio_home/share/studio.conf"\n\
fi\n\
echo "Unsloth Studio starting on http://localhost:8888"\n\
exec /opt/venv/bin/unsloth studio -H 0.0.0.0 -p 8888 "$@"\n\
' > /usr/bin/unsloth-studio && chmod +x /usr/bin/unsloth-studio

CMD ["/bin/bash"]
