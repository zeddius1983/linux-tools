# llama.cpp, built for one of three GPU runtimes.
#
# Both build args come from the setup wizard:
#   wizard/00-gpu.runtime      -> LLAMA_GPU  (also selects create_flags.<value>)
#   wizard/01-release.buildarg -> LLAMA_REF
# Both have defaults, so a non-interactive `tools setup llama-cpp` still builds
# ROCm 7.2.4 at the latest release exactly as it did before the wizard existed.
#
#   rocm    ROCm 7.2.4 (HIP) + Vulkan (Mesa RADV)
#   rocm10  ROCm 10.0  (HIP) + Vulkan (Mesa RADV)
#   cuda    CUDA 12.8  + Vulkan (NVIDIA's own ICD, supplied by the host via CDI)
#
# Unlike comfyui/vllm, both the build stage and the runtime stage depend on the
# runtime, so each is picked from per-variant stages with `FROM <stage>-${LLAMA_GPU}`.
# Buildah prunes stages the final image never reaches, so choosing one runtime
# never pulls another's base image.
ARG LLAMA_GPU=rocm
ARG ROCM_IMAGE=docker.io/rocm/dev-ubuntu-24.04:7.2.4-complete
ARG ROCM10_IMAGE=docker.io/rocm/dev-ubuntu-24.04:10.0.0-full
ARG CUDA_DEVEL_IMAGE=docker.io/nvidia/cuda:12.8.1-devel-ubuntu24.04
ARG CUDA_RUNTIME_IMAGE=docker.io/nvidia/cuda:12.8.1-runtime-ubuntu24.04

### Toolchains — the compiler stack for each runtime
FROM ${ROCM_IMAGE} AS toolchain-rocm

FROM ${ROCM10_IMAGE} AS toolchain-rocm10

# GCC 14 as CUDA's host compiler, matching upstream's .devops/cuda.Dockerfile.
FROM ${CUDA_DEVEL_IMAGE} AS toolchain-cuda
RUN apt-get update \
    && apt-get install -y gcc-14 g++-14 \
    && rm -rf /var/lib/apt/lists/*
ENV CC=gcc-14 CXX=g++-14 CUDAHOSTCXX=g++-14

### Build stage — compile llama.cpp with the selected GPU backend plus Vulkan
FROM toolchain-${LLAMA_GPU} AS build
ARG LLAMA_GPU

# Fat build targeting all supported AMD GPU architectures (ROCm variants only).
ARG ROCM_DOCKER_ARCH='gfx908;gfx90a;gfx942;gfx1030;gfx1100;gfx1101;gfx1102;gfx1151;gfx1150;gfx1200;gfx1201'
# CUDA architectures (cuda variant only). "default" leaves ggml's own list.
ARG CUDA_DOCKER_ARCH=default

RUN apt-get update \
    && apt-get install -y \
       build-essential cmake git libssl-dev curl libgomp1 \
       libvulkan-dev glslc spirv-headers \
    && rm -rf /var/lib/apt/lists/*

# Release tag (b####) to build. "latest" resolves the newest tag at build
# time; the interactive setup wizard offers the last 10 releases (LLAMA_REF).
# CACHE_BUST is passed fresh by tools.sh on every build, forcing this layer to
# re-run instead of reusing a stale cached clone; the apt layers above stay
# cached.
ARG CACHE_BUST=0
ARG LLAMA_REF=latest
RUN set -e; \
    ref="$LLAMA_REF"; \
    if [ "$ref" = "latest" ]; then \
        ref="b$(git ls-remote --tags --refs https://github.com/ggml-org/llama.cpp 'b*' \
            | sed 's|.*refs/tags/b||' | grep -E '^[0-9]+$' | sort -n | tail -1)"; \
    fi; \
    echo "==> Building llama.cpp release ${ref} for ${LLAMA_GPU} (cache-bust: ${CACHE_BUST})"; \
    git clone --depth 1 --branch "${ref}" https://github.com/ggml-org/llama.cpp /src; \
    echo "${ref#b}" > /src/.build-number

WORKDIR /src

# Every variant shares the Vulkan backend and dynamic backend loading; only the
# GPU backend's flags differ. The CUDA link allows undefined shlib symbols
# because libcuda.so.1 is only a stub in the devel image — the real one comes
# from the host driver at runtime (upstream does the same).
RUN set -e; \
    case "$LLAMA_GPU" in \
        rocm|rocm10) \
            export HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)"; \
            set -- -DGGML_HIP=ON -DAMDGPU_TARGETS="${ROCM_DOCKER_ARCH}" ;; \
        cuda) \
            set -- -DGGML_CUDA=ON -DGGML_NATIVE=OFF \
                   -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined; \
            if [ "$CUDA_DOCKER_ARCH" != default ]; then \
                set -- "$@" -DCMAKE_CUDA_ARCHITECTURES="${CUDA_DOCKER_ARCH}"; \
            fi ;; \
        *) echo "Unknown LLAMA_GPU '${LLAMA_GPU}' (want rocm, rocm10 or cuda)" >&2; exit 1 ;; \
    esac; \
    cmake -S . -B build \
        -DLLAMA_BUILD_NUMBER="$(cat .build-number)" \
        "$@" \
        -DGGML_VULKAN=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_TESTS=OFF; \
    cmake --build build --config Release -j"$(nproc)"

# Stage binaries, backend plugin .so files, and Python conversion tooling
RUN mkdir -p /stage/bin /stage/lib /stage/gguf-py \
    && cp -r /src/build/bin/. /stage/bin/ \
    && find /src/build -name "*.so*" -exec cp -P {} /stage/lib/ \; \
    && cp /src/.devops/tools.sh /stage/bin/llama-tools \
    && cp /src/convert_hf_to_gguf.py /stage/bin/ \
    && cp -r /src/gguf-py/. /stage/gguf-py/

### Runtimes — the base each variant runs on, with its Vulkan driver
# ROCm runtimes reuse the dev image the build ran on (already pulled), and take
# Mesa RADV as the Vulkan driver.
FROM ${ROCM_IMAGE} AS runtime-rocm
RUN apt-get update \
    && apt-get install -y libvulkan1 mesa-vulkan-drivers vulkan-tools \
    && rm -rf /var/lib/apt/lists/*

# The 10.0 image (TheRock) finds its own libraries through RPATH and, unlike
# 7.2.4, registers nothing with ld.so — so libggml-hip.so would load with
# libhipblas/librocblas/libamdhip64 "not found" and ROCm0 silently vanish
# from --list-devices, leaving only Vulkan0.
FROM ${ROCM10_IMAGE} AS runtime-rocm10
RUN apt-get update \
    && apt-get install -y libvulkan1 mesa-vulkan-drivers vulkan-tools \
    && rm -rf /var/lib/apt/lists/* \
    && echo /opt/rocm/lib > /etc/ld.so.conf.d/rocm.conf && ldconfig

# No Mesa here: NVIDIA's Vulkan ICD and libraries are injected from the host
# driver by the CDI spec. Mesa would only add a llvmpipe/lavapipe CPU device.
# --no-install-recommends is what keeps it out: libvulkan1 recommends
# mesa-vulkan-drivers, and a plain install pulls it in.
FROM ${CUDA_RUNTIME_IMAGE} AS runtime-cuda
RUN apt-get update \
    && apt-get install -y --no-install-recommends libvulkan1 vulkan-tools \
    && rm -rf /var/lib/apt/lists/*

### Runtime image
FROM runtime-${LLAMA_GPU}
ARG LLAMA_GPU

RUN apt-get update \
    && apt-get install -y libgomp1 curl git python3 python3-pip \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

# Record the variant — the quickest way to tell what a box was built as.
RUN echo "${LLAMA_GPU}" > /etc/llama-cpp-gpu

# Binaries and GGML_BACKEND_DL plugin .so files must be co-located for dynamic loader
COPY --from=build /stage/bin/ /opt/llama-cpp/
COPY --from=build /stage/lib/ /opt/llama-cpp/
COPY --from=build /stage/gguf-py/ /opt/llama-cpp/gguf-py/

# Register /opt/llama-cpp so ld.so finds libllama-*-impl.so and other build-time shared libs
RUN echo /opt/llama-cpp > /etc/ld.so.conf.d/llama-cpp.conf && ldconfig

# Minimal Python dep for convert_hf_to_gguf.py (--convert / -c)
RUN pip install --break-system-packages -e /opt/llama-cpp/gguf-py

# Unified dispatcher: cd so upstream tools.sh relative paths resolve to /opt/llama-cpp/
RUN printf '#!/usr/bin/env bash\ncd /opt/llama-cpp && exec ./llama-tools "$@"\n' \
    > /usr/bin/llama && chmod +x /usr/bin/llama

# Direct binary exports — command -pv requires these to live in /usr/bin/
RUN printf '#!/usr/bin/env bash\nexec /opt/llama-cpp/llama-cli "$@"\n' \
    > /usr/bin/llama-cli && chmod +x /usr/bin/llama-cli

RUN printf '#!/usr/bin/env bash\nexec /opt/llama-cpp/llama-server "$@"\n' \
    > /usr/bin/llama-server && chmod +x /usr/bin/llama-server

RUN printf '#!/usr/bin/env bash\nexec /opt/llama-cpp/llama-bench "$@"\n' \
    > /usr/bin/llama-bench && chmod +x /usr/bin/llama-bench

CMD ["/bin/bash"]
