FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY dev-toolbox-install /usr/bin/dev-toolbox-install
COPY dev-toolbox-run /usr/libexec/dev-toolbox-run

RUN chmod +x /usr/bin/dev-toolbox-install /usr/libexec/dev-toolbox-run \
    && for command in node npm npx uv uvx; do \
        ln -s /usr/libexec/dev-toolbox-run "/usr/bin/${command}"; \
    done

CMD ["/bin/bash"]
