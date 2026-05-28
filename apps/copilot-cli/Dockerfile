FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    tar \
    libsecret-1-0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://gh.io/copilot-install | PREFIX=/usr bash
