FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libasound2t64 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://lmstudio.ai/download/latest/linux/x64?format=deb" \
    -o /tmp/lmstudio.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/lmstudio.deb \
    && rm /tmp/lmstudio.deb \
    && rm -rf /var/lib/apt/lists/*
