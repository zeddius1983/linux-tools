FROM docker.io/ubuntu:24.04

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates unzip tar jq \
    && rm -rf /var/lib/apt/lists/*

COPY shell-toolbox-install /usr/bin/shell-toolbox-install
RUN chmod +x /usr/bin/shell-toolbox-install \
    && ln -s /usr/bin/shell-toolbox-install /usr/bin/zsh-install

CMD ["/bin/bash"]
