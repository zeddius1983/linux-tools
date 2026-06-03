FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates unzip tar jq \
    && rm -rf /var/lib/apt/lists/*

COPY zsh-install /usr/bin/zsh-install
RUN chmod +x /usr/bin/zsh-install

CMD ["/bin/bash"]
