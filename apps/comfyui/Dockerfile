FROM docker.io/rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# PyTorch already present in base image; just install ComfyUI and its deps
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
WORKDIR /opt/ComfyUI
RUN pip install -r requirements.txt && \
    pip install --prefer-binary \
    pillow opencv-python-headless imageio imageio-ffmpeg scipy \
    "huggingface_hub[hf_transfer]"

# ComfyUI-Manager for in-UI plugin installation
RUN git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/ComfyUI/custom_nodes/ComfyUI-Manager && \
    pip install -r /opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt

RUN chmod -R a+rwX /opt/ComfyUI

# Wrapper must live in /usr/bin/ — command -pv does not search /usr/local/bin.
# --base-directory routes all data (models, output, user, input) to ~/.comfyui,
# persisting across container rebuilds via Distrobox shared $HOME.
# Remaining flags tuned for Strix Halo (gfx1151):
#   --disable-mmap  critical: mmap above 64 GB is very slow on gfx1151 (ROCm bug)
#   --bf16-vae      prevents OOM during VAE decode on unified memory
#   --cache-none    disables model caching for better GTT/RAM management
RUN printf '#!/usr/bin/env bash\n\
export VIRTUAL_ENV=/opt/venv\n\
export PATH=/opt/venv/bin:${PATH}\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1\n\
export TORCH_BLAS_PREFER_HIPBLASLT=1\n\
export MIOPEN_USER_DB_PATH="${HOME}/.cache/miopen"\n\
echo "ComfyUI starting — open http://localhost:8188 in your browser"\n\
cd /opt/ComfyUI\n\
exec /opt/venv/bin/python main.py --listen 0.0.0.0 --base-directory "${HOME}/.comfyui" --reserve-vram 3 --bf16-vae --disable-mmap --cache-none "$@"\n\
' > /usr/bin/comfyui && chmod +x /usr/bin/comfyui

CMD ["/bin/bash"]
