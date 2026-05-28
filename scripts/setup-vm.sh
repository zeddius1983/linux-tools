#!/usr/bin/env bash
# Sets up prerequisites for linux-tools inside an Ubuntu VM (e.g. OrbStack).
# Installs: podman, distrobox, whiptail
set -euo pipefail

# ── Guards ───────────────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Error: run this script inside a Linux VM, not on macOS directly." >&2
    exit 1
fi

if ! command -v apt-get &>/dev/null; then
    echo "Error: apt-get not found — Ubuntu/Debian required." >&2
    exit 1
fi

# ── Packages ─────────────────────────────────────────────────────────────────

echo "==> Updating package lists..."
sudo apt-get update -qq

echo "==> Installing podman, whiptail, curl, uidmap..."
sudo apt-get install -y --no-install-recommends \
    podman \
    whiptail \
    curl \
    uidmap        # required for rootless podman user namespaces

# ── Distrobox ────────────────────────────────────────────────────────────────

echo "==> Installing distrobox (latest via official installer)..."
curl -fsSL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh

# ── Podman: rootless configuration ───────────────────────────────────────────

# Allow podman to resolve images from docker.io without full registry prefix
REGISTRIES_CONF="/etc/containers/registries.conf"
if ! grep -q "unqualified-search-registries" "$REGISTRIES_CONF" 2>/dev/null; then
    echo "==> Configuring podman unqualified search registries..."
    echo 'unqualified-search-registries = ["docker.io"]' \
        | sudo tee -a "$REGISTRIES_CONF" > /dev/null
fi

# Ensure subuid/subgid entries exist for the current user (needed for rootless)
USER="${USER:-$(whoami)}"
if ! grep -q "^$USER:" /etc/subuid 2>/dev/null; then
    echo "==> Configuring subuid/subgid for rootless podman..."
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
fi

# ── Verify ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Installed versions:"
echo -n "  podman:    "; podman --version
echo -n "  distrobox: "; distrobox --version 2>&1 | head -1
echo -n "  whiptail:  "; whiptail --version 2>&1 | head -1

echo ""
echo "All done. You can now run ./tools.sh from the project root."
echo "Tip: if podman complains about user namespaces, log out and back in first."
