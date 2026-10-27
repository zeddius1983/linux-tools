FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

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
    && for command in node npm npx uv uvx firecrawl go gofmt rustup rustc cargo bacon rust-analyzer sdk jdtls kotlin-lsp; do \
        ln -s /usr/libexec/dev-toolbox-run "/usr/bin/${command}"; \
    done

CMD ["/bin/bash"]
