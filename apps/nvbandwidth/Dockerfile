FROM docker.io/nvidia/cuda:12.6.3-devel-ubuntu24.04

# build-essential + cmake (>=3.20; Ubuntu 24.04 ships 3.28) for the build;
# git because CMakeLists runs `git describe` for the version string;
# ca-certificates so CMake FetchContent can pull the pinned argparse tarball.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# nvbandwidth links against -lcuda (libcuda.so.1) and -lnvidia-ml. Neither the
# real driver nor its dev libs exist at image-build time — the host NVIDIA
# driver is injected only at runtime via CDI (--device nvidia.com/gpu=all).
# The CUDA toolkit ships link stubs for both in lib64/stubs; put that on the
# linker search path so the build resolves them. The stub soname is
# libcuda.so.1, so the runtime loader picks up the real driver lib from CDI.
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs

# Pin the CUDA arch list: there is no GPU present at build time, so CMake's
# default arch auto-detection has nothing to probe. This list spans Turing
# through Hopper (86 = the RTX 3080 this box runs). Binary → /usr/bin so that
# `command -pv` (which ignores /usr/local/bin) finds it for the bin: export.
RUN git clone --depth 1 https://github.com/NVIDIA/nvbandwidth.git /opt/nvbandwidth && \
    cmake -S /opt/nvbandwidth -B /opt/nvbandwidth/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="75;80;86;89;90" && \
    cmake --build /opt/nvbandwidth/build -j"$(nproc)" && \
    install -m 0755 /opt/nvbandwidth/build/nvbandwidth /usr/bin/nvbandwidth

# p2pBandwidthLatencyTest from NVIDIA/cuda-samples — the community-standard P2P
# matrix (P2P enabled-vs-disabled bandwidth + latency). Complements nvbandwidth:
# this tool reports the enabled/disabled contrast that proves the P2P capability
# flipped, but it only TIMES cuMemcpyPeer — it does NOT verify data integrity, so
# nvbandwidth stays the correctness oracle. It's a single-file sample: build it
# directly with nvcc against the repo's Common/ headers (same arch span as above),
# emit to /usr/bin for the bin: export, then drop the (large) source tree.
RUN git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git /opt/cuda-samples && \
    src="$(find /opt/cuda-samples -name p2pBandwidthLatencyTest.cu)" && \
    nvcc -O3 -I /opt/cuda-samples/Common \
      -gencode arch=compute_75,code=sm_75 \
      -gencode arch=compute_80,code=sm_80 \
      -gencode arch=compute_86,code=sm_86 \
      -gencode arch=compute_89,code=sm_89 \
      -gencode arch=compute_90,code=sm_90 \
      "$src" -o /usr/bin/p2pBandwidthLatencyTest && \
    rm -rf /opt/cuda-samples

CMD ["/bin/bash"]
