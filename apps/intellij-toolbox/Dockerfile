FROM --platform=linux/amd64 docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    SDKMAN_DIR=/opt/sdkman

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget \
    libxi6 libxrender1 libxtst6 mesa-utils libfontconfig1 \
    libgtk-3-bin dbus-user-session libxcb-keysyms1 \
    zsh git git-lfs \
    build-essential cmake \
    python3 python3-pip python3-venv \
    jq unzip zip \
    ripgrep shellcheck \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (client only — connects to host socket)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install SDKMAN to /opt/sdkman and pre-install default Java LTS
RUN curl -s "https://get.sdkman.io" | bash \
    && chmod -R a+rwX /opt/sdkman

SHELL ["/bin/bash", "-c"]
RUN source /opt/sdkman/bin/sdkman-init.sh && sdk install java

# Make SDKMAN available in login shells (bash + zsh)
RUN printf '\nexport SDKMAN_DIR=/opt/sdkman\n[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"\n' \
    >> /etc/bash.bashrc \
    && mkdir -p /etc/zsh \
    && printf '\nexport SDKMAN_DIR=/opt/sdkman\n[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"\n' \
    >> /etc/zsh/zshrc

# Download and install latest JetBrains Toolbox
RUN TOOLBOX_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['TBA'][0]['downloads']['linux']['link'])") \
    && curl -fL "$TOOLBOX_URL" -o /tmp/jetbrains-toolbox.tar.gz \
    && mkdir -p /opt/jetbrains-toolbox \
    && tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /opt/jetbrains-toolbox --strip-components=1 \
    && rm /tmp/jetbrains-toolbox.tar.gz \
    && chmod -R a+rwX /opt/jetbrains-toolbox \
    && ln -sf /opt/jetbrains-toolbox/bin/jetbrains-toolbox /usr/bin/jetbrains-toolbox
