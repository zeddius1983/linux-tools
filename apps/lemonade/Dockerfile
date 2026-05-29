FROM ghcr.io/lemonade-sdk/lemonade-server:latest

# Wrapper: start server — symlinks llama cache into $HOME so it persists across rebuilds
RUN printf '#!/usr/bin/env bash\n\
mkdir -p "$HOME/.local/share/lemonade/llama"\n\
if [ ! -L /opt/lemonade/llama ]; then\n\
  rm -rf /opt/lemonade/llama\n\
  ln -s "$HOME/.local/share/lemonade/llama" /opt/lemonade/llama\n\
fi\n\
export LEMONADE_LLAMACPP=rocm\n\
exec /opt/lemonade/lemond --host 0.0.0.0 "$@"\n\
' > /usr/bin/lemonade-server && chmod +x /usr/bin/lemonade-server

# Wrapper: CLI client
RUN printf '#!/usr/bin/env bash\nexec /opt/lemonade/lemonade "$@"\n' \
  > /usr/bin/lemonade && chmod +x /usr/bin/lemonade

RUN printf "\nNOTE: ROCm requires the host user to be in the render and video groups.\nIf /dev/kfd access fails, run on the host:\n  sudo usermod -aG render,video \$USER  (then log out and back in)\n" >> /etc/motd

CMD ["/bin/bash"]
