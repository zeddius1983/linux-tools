FROM docker.io/ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates unzip tar jq \
    && rm -rf /var/lib/apt/lists/*

COPY shell-toolbox-install /usr/bin/shell-toolbox-install
RUN chmod +x /usr/bin/shell-toolbox-install \
    && ln -s /usr/bin/shell-toolbox-install /usr/bin/zsh-install

CMD ["/bin/bash"]
