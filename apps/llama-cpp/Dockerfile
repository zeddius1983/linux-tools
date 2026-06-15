### Build stage — compile llama.cpp with ROCm/HIP
FROM docker.io/rocm/dev-ubuntu-24.04:7.2.4-complete AS build

# Fat build targeting all supported AMD GPU architectures
ARG ROCM_DOCKER_ARCH='gfx908;gfx90a;gfx942;gfx1030;gfx1100;gfx1101;gfx1102;gfx1151;gfx1150;gfx1200;gfx1201'
ENV AMDGPU_TARGETS=${ROCM_DOCKER_ARCH}

RUN apt-get update \
    && apt-get install -y \
       build-essential cmake git libssl-dev curl libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp /src

WORKDIR /src

RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
        -DGGML_HIP=ON \
        -DGGML_HIP_ROCWMMA_FATTN=ON \
        -DAMDGPU_TARGETS="${ROCM_DOCKER_ARCH}" \
        -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_TESTS=OFF \
    && cmake --build build --config Release -j$(nproc)

# Stage binaries, backend plugin .so files, and Python conversion tooling
RUN mkdir -p /stage/bin /stage/lib /stage/gguf-py \
    && cp -r /src/build/bin/. /stage/bin/ \
    && find /src/build -name "*.so*" -exec cp -P {} /stage/lib/ \; \
    && cp /src/.devops/tools.sh /stage/bin/llama-tools \
    && cp /src/convert_hf_to_gguf.py /stage/bin/ \
    && cp -r /src/gguf-py/. /stage/gguf-py/

### Runtime image
FROM docker.io/rocm/dev-ubuntu-24.04:7.2.4-complete

RUN apt-get update \
    && apt-get install -y libgomp1 curl git python3 python3-pip \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

# Binaries and GGML_BACKEND_DL plugin .so files must be co-located for dynamic loader
COPY --from=build /stage/bin/ /opt/llama-cpp/
COPY --from=build /stage/lib/ /opt/llama-cpp/
COPY --from=build /stage/gguf-py/ /opt/llama-cpp/gguf-py/

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

CMD ["/bin/bash"]
