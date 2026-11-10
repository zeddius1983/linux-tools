FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# distrobox-init's first-start packages, preinstalled from the shared list so a
# fresh box doesn't download them (lib/distrobox-deps; context passed by tools).
COPY --from=distrobox-deps . /tmp/distrobox-deps/
RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps

# curl fetches the release and lets distrobox-host-exec bootstrap host-spawn on
# a fresh box, which the launcher depends on; git is for the shared-$HOME dotfiles.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# The release selected by wizard/00-release.buildarg, as a tag ("v0.3.5"), or
# "latest", the non-interactive default. "latest" is resolved from the
# releases/latest redirect, which has no API rate limit. The asset name uses
# the bare version. CACHE_BUST is fresh on every `tools build/setup`, so "latest"
# is never satisfied by a stale layer.
ARG CACHE_BUST=0
ARG GPUTASKMAN_RELEASE=latest
RUN echo "==> Installing gputaskman ${GPUTASKMAN_RELEASE} (cache-bust: ${CACHE_BUST})" \
    && base=https://github.com/shanselman/gputaskman/releases \
    && tag="${GPUTASKMAN_RELEASE}" \
    && if [ "$tag" = latest ]; then \
         tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$base/latest")"; \
         tag="${tag##*/}"; \
       fi \
    && test -n "$tag" \
    && case "$(dpkg --print-architecture)" in \
         amd64) arch=x64 ;; \
         arm64) arch=arm64 ;; \
         *) echo "unsupported architecture" >&2; exit 1 ;; \
       esac \
    && asset="gputaskman-${tag#v}-linux-${arch}.tar.gz" \
    && mkdir -p /tmp/gputaskman /opt/gputaskman \
    && cd /tmp/gputaskman \
    && curl -fsSLO "$base/download/$tag/$asset" \
    && curl -fsSLO "$base/download/$tag/$asset.sha256" \
    && sha256sum -c "$asset.sha256" \
    && tar -xzf "$asset" --strip-components=1 -C /opt/gputaskman \
    && cd / \
    && rm -rf /tmp/gputaskman \
    && chmod -R a+rX /opt/gputaskman \
    && /opt/gputaskman/gputaskman --help > /dev/null

# The release actually installed, as the picker writes it ("v0.3.5"), for the
# dashboard's update check; read back by record_install (lib/commands.sh). The
# launcher also names the host copy after it. gputaskman has no --version, so
# it comes from the bundled package metadata.
RUN mkdir -p /usr/share/linux-tools \
    && d="$(ls -d /opt/gputaskman/_internal/gputaskman-*.dist-info)" \
    && v="${d##*/gputaskman-}" \
    && v="${v%.dist-info}" \
    && test -n "$v" && echo "v$v" > /usr/share/linux-tools/release

# The launcher runs the bundle on the host; see the comment in the script.
# /usr/bin, because exports resolve through `command -pv`.
COPY gputaskman /usr/bin/gputaskman
RUN chmod +x /usr/bin/gputaskman

CMD ["/bin/bash"]
