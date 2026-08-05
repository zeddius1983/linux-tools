# ComfyUI, built for one of two GPU backends.
#
# Both build args come from the setup wizard:
#   wizard/00-gpu.runtime      -> COMFY_GPU  (also selects create_flags.<value>)
#   wizard/01-release.buildarg -> COMFY_REF
# Both have defaults, so a non-interactive `tools setup comfyui` still builds the
# AMD variant at master exactly as before the wizard existed.
#
# The base image is chosen by `FROM base-${COMFY_GPU}`. Buildah/podman prunes
# stages the final stage doesn't reference, so selecting nvidia does NOT pull the
# ~20 GB ROCm image (verified: the unreferenced stage is never even fetched).
ARG COMFY_GPU=amd
ARG ROCM_BASE=docker.io/rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0
ARG CUDA_BASE=docker.io/nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

# --- AMD: PyTorch + ROCm come with the base image, already in /opt/venv -------
FROM ${ROCM_BASE} AS base-amd
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*
RUN echo amd > /etc/comfyui-gpu

# --- NVIDIA: same /opt/venv layout, built on a plain CUDA runtime image -------
# The runtime (not devel) image is enough for ComfyUI itself; custom nodes that
# compile CUDA kernels from source will not find nvcc here — see README.
FROM ${CUDA_BASE} AS base-nvidia
ARG TORCH_CUDA_INDEX=https://download.pytorch.org/whl/cu128
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ffmpeg curl python3 python3-venv python3-dev \
    && rm -rf /var/lib/apt/lists/*
# /opt/venv on purpose: it makes the venv path identical across both variants,
# so the wrapper scripts and every "use /opt/venv/bin/python" note still hold.
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir \
        torch torchvision torchaudio --index-url ${TORCH_CUDA_INDEX}
RUN echo nvidia > /etc/comfyui-gpu

# --- Common ------------------------------------------------------------------
FROM base-${COMFY_GPU} AS comfyui

ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:${PATH}

# Release tag chosen by the wizard; "master" tracks the branch tip.
ARG COMFY_REF=master
RUN git clone --depth=1 --branch "${COMFY_REF}" \
        https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI

WORKDIR /opt/ComfyUI
# torch/torchvision/torchaudio are already satisfied by the stage above, so this
# only pulls ComfyUI's own dependencies.
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir --prefer-binary \
        pillow opencv-python-headless imageio imageio-ffmpeg scipy \
        "huggingface_hub[hf_transfer]"

# ComfyUI-Manager for in-UI plugin installation
RUN git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/ComfyUI/custom_nodes/ComfyUI-Manager && \
    pip install --no-cache-dir -r /opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt

COPY extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml

# Tray icon dependencies. Installed in the common stage rather than in each base
# because both bases are Ubuntu 24.04 and the package set is identical.
# These land in the *system* python (/usr/lib/python3/dist-packages), not
# /opt/venv -- comfyui-tray runs on /usr/bin/python3 for exactly that reason.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-gi gir1.2-gtk-3.0 \
        gir1.2-ayatanaappindicator3-0.1 libayatana-appindicator3-1 \
    && rm -rf /var/lib/apt/lists/*
# icon.png is the single icon source for this app. tools.sh resolves it straight
# from the app directory for the desktop entry (preferring .png over .svg), and
# the tray icon below is generated from the same file, so the menu and the panel
# cannot drift apart.
#
# The 250px source is downscaled at build time rather than handed to GTK as-is:
# a panel renders this at roughly 22-32px, and one LANCZOS step from 250px is
# visibly softer than going via 64px. Pillow is already present (it is a ComfyUI
# dependency), so this costs nothing extra.
COPY icon.png /usr/share/comfyui/icon-src.png
RUN /opt/venv/bin/python -c "from PIL import Image; Image.open('/usr/share/comfyui/icon-src.png').convert('RGBA').resize((64, 64), Image.LANCZOS).save('/usr/share/comfyui/comfyui-tray.png')" \
    && rm /usr/share/comfyui/icon-src.png

# ComfyUI writes user/, output/ and temp/ under its install dir at runtime, as
# the (non-root) Distrobox user — without this it dies with PermissionError.
RUN chmod -R a+rwX /opt/ComfyUI

# Wrappers must live in /usr/bin/ — command -pv does not search /usr/local/bin.
COPY comfyui-run /usr/bin/comfyui
COPY comfyui-app /usr/bin/comfyui-app
COPY comfyui-open /usr/bin/comfyui-open
COPY comfyui-stop /usr/bin/comfyui-stop
COPY comfyui-tray /usr/bin/comfyui-tray
RUN chmod +x /usr/bin/comfyui /usr/bin/comfyui-app /usr/bin/comfyui-open \
        /usr/bin/comfyui-stop /usr/bin/comfyui-tray

# Both repos are cloned by root at build time but used by the non-root Distrobox
# user, so git refuses to touch them ("detected dubious ownership"). That breaks
# ComfyUI-Manager, which drives ComfyUI updates and custom-node installs through
# git — the very path this app's README points at after every rebuild. Marking
# just these two safe is consistent with /opt/ComfyUI already being deliberately
# world-writable. Nodes the Manager installs later are created by the user and
# need no entry; safe.directory has no partial globbing, so they could not get
# one anyway.
RUN git config --system --add safe.directory /opt/ComfyUI && \
    git config --system --add safe.directory /opt/ComfyUI/custom_nodes/ComfyUI-Manager

CMD ["/bin/bash"]
