FROM rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0

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

# Route all models to ~/comfy-models so they persist via Distrobox shared $HOME
RUN printf 'comfyui:\n\
  base_path: ~/comfy-models/\n\
  checkpoints: checkpoints/\n\
  vae: vae/\n\
  loras: loras/\n\
  controlnet: controlnet/\n\
  upscale_models: upscale_models/\n\
  clip: clip/\n\
  unet: unet/\n\
  diffusion_models: diffusion_models/\n' \
    > /opt/ComfyUI/extra_model_paths.yaml

# Wrapper must live in /usr/bin/ — command -pv does not search /usr/local/bin.
# Flags tuned for Strix Halo (gfx1151):
#   --disable-mmap  critical: mmap above 64 GB is very slow on gfx1151 (ROCm bug)
#   --bf16-vae      prevents OOM during VAE decode on unified memory
#   --cache-none    disables model caching for better GTT/RAM management
RUN printf '#!/usr/bin/env bash\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export HSA_ENABLE_SDMA=0\n\
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1\n\
export TORCH_BLAS_PREFER_HIPBLASLT=1\n\
export MIOPEN_USER_DB_PATH="${HOME}/.cache/miopen"\n\
mkdir -p "${HOME}/comfy-models"/{checkpoints,vae,loras,controlnet,upscale_models,clip,unet,diffusion_models}\n\
echo "ComfyUI starting — open http://localhost:8188 in your browser"\n\
cd /opt/ComfyUI\n\
exec python main.py --listen 0.0.0.0 --reserve-vram 3 --bf16-vae --disable-mmap --cache-none "$@"\n\
' > /usr/bin/comfyui && chmod +x /usr/bin/comfyui

CMD ["/bin/bash"]
