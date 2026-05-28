FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bubblewrap \
    && rm -rf /var/lib/apt/lists/*

# Install script downloads the pre-built Rust binary to $HOME/.local/bin.
# In the build context HOME=/root; copy to /usr/bin so command -pv can find it.
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh && \
    cp /root/.local/bin/codex /usr/bin/codex
