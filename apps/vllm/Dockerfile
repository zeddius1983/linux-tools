FROM docker.io/vllm/vllm-openai-rocm:latest

# vllm binary is at /usr/local/bin/vllm in this image;
# command -pv doesn't search /usr/local/bin, so bridge it via /usr/bin.
RUN printf '#!/usr/bin/env bash\nexec /usr/local/bin/vllm "$@"\n' \
    > /usr/bin/vllm && chmod +x /usr/bin/vllm

# Convenience server wrapper with Strix Halo env vars and sensible defaults.
# Model cache lands in ~/.cache/huggingface via Distrobox shared $HOME.
# HF_TOKEN is inherited from the host shell — no need to bake it in.
RUN printf '#!/usr/bin/env bash\n\
export HSA_ENABLE_SDMA=0\n\
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True\n\
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1\n\
export TORCH_BLAS_PREFER_HIPBLASLT=1\n\
export MIOPEN_USER_DB_PATH="${HOME}/.cache/miopen"\n\
mkdir -p "${HOME}/.cache/miopen"\n\
echo "vLLM OpenAI server starting on http://localhost:8000"\n\
exec python -m vllm.entrypoints.openai.api_server \\\n\
    --host 0.0.0.0 --port 8000 "$@"\n\
' > /usr/bin/vllm-serve && chmod +x /usr/bin/vllm-serve

CMD ["/bin/bash"]
