FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    curl \
    gzip \
    git \
    jq \
    libssl-dev \
    pkg-config \
    python3 \
    tar \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/*

COPY dev-toolbox-install /usr/bin/dev-toolbox-install
COPY dev-toolbox-run /usr/libexec/dev-toolbox-run

RUN chmod +x /usr/bin/dev-toolbox-install /usr/libexec/dev-toolbox-run \
    && for command in node npm npx uv uvx firecrawl rustup rustc cargo bacon rust-analyzer sdk jdtls kotlin-lsp; do \
        ln -s /usr/libexec/dev-toolbox-run "/usr/bin/${command}"; \
    done

CMD ["/bin/bash"]
