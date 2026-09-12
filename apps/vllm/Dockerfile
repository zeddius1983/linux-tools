# vLLM, built for one of two GPU backends.
#
# Both build args come from the setup wizard:
#   wizard/00-gpu.runtime      -> VLLM_GPU  (also selects create_flags.<value>)
#   wizard/01-release.buildarg -> VLLM_TAG
# Both have defaults, so a non-interactive `tools setup vllm` still builds the
# AMD variant on :latest exactly as it did before the wizard existed.
#
# There is no single image that serves both backends: vLLM's kernels, and the
# PyTorch underneath them, are compiled per accelerator, so upstream publishes
# the same release as two separate images. `FROM base-${VLLM_GPU}` picks one,
# and buildah prunes the stage the final stage doesn't reference — selecting
# one backend never pulls the other's ~20 GB image.
ARG VLLM_GPU=amd
ARG VLLM_TAG=latest
ARG ROCM_BASE=docker.io/vllm/vllm-openai-rocm
ARG CUDA_BASE=docker.io/vllm/vllm-openai

# --- AMD: ROCm + PyTorch come with the base image ----------------------------
# /etc/vllm-env is sourced by vllm-serve. The Strix Halo (gfx1151) workarounds
# live here rather than in the wrapper because they are ROCm-only — exporting
# them on a CUDA box would be noise at best.
FROM ${ROCM_BASE}:${VLLM_TAG} AS base-amd
RUN printf '%s\n' \
        '# ROCm / Strix Halo (gfx1151) workarounds, sourced by vllm-serve.' \
        'export HSA_ENABLE_SDMA=0' \
        'export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True' \
        'export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1' \
        'export TORCH_BLAS_PREFER_HIPBLASLT=1' \
        'export MIOPEN_USER_DB_PATH="${HOME}/.cache/miopen"' \
        > /etc/vllm-env && echo amd > /etc/vllm-gpu

# --- NVIDIA: same image family, built against CUDA ---------------------------
FROM ${CUDA_BASE}:${VLLM_TAG} AS base-nvidia
RUN printf '%s\n' \
        '# CUDA build: nothing to work around. The ROCm variant sets HSA/HIP' \
        '# env vars here; none of them mean anything on this stack.' \
        > /etc/vllm-env && echo nvidia > /etc/vllm-gpu

# --- Common ------------------------------------------------------------------
FROM base-${VLLM_GPU}

# The CLI lives in /usr/local/bin, which `command -pv` (used by tools.sh for
# bin: exports) does not search, so it is bridged into /usr/bin. Both paths are
# resolved at build time rather than hard-coded: the ROCm and CUDA images are
# separate upstream builds and need not agree on where they put things. The
# guard keeps the shim from calling itself if a future image ships the CLI in
# /usr/bin already.
RUN set -eux; \
    vllm_bin="$(command -v vllm)"; \
    py_bin="$(command -v python || command -v python3)"; \
    if [ "$vllm_bin" != /usr/bin/vllm ]; then \
        printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$vllm_bin" > /usr/bin/vllm; \
        chmod +x /usr/bin/vllm; \
    fi; \
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '# Convenience server wrapper: the OpenAI API server on 0.0.0.0:8000,' \
        '# with the environment for this build backend already applied. Every' \
        '# argument is passed through to the server.' \
        '. /etc/vllm-env' \
        '[ -n "${MIOPEN_USER_DB_PATH:-}" ] && mkdir -p "$MIOPEN_USER_DB_PATH"' \
        'echo "vLLM OpenAI server starting on http://localhost:8000"' \
        'exec @PYTHON@ -m vllm.entrypoints.openai.api_server --host 0.0.0.0 --port 8000 "$@"' \
        | sed "s|@PYTHON@|$py_bin|" > /usr/bin/vllm-serve; \
    chmod +x /usr/bin/vllm-serve

CMD ["/bin/bash"]
