#!/usr/bin/env bash
#
# Install (or uninstall) LACT on the HOST.
#
# LACT is a root system daemon (lactd) that writes GPU control files under
# /sys/class/drm/*/device/ — power caps, clock/voltage curves, fan curves. That
# cannot be done from a rootless Podman container, which is why this app is
# host-only rather than a Distrobox image: upstream's own container image is
# daemon+CLI only, no GUI, and expects rootful Docker with --privileged.
#
# Invoked by `tools setup lact` (runs on the host, so sudo has a real TTY).
# `tools rm lact` calls `install.sh uninstall`.
#
# LACT_VERSION is set by the wizard's release picker and arrives as an
# environment variable (cmd_setup hands .buildarg answers to host-only
# installers that way, since there is no image build to take --build-arg).
# Unset means the newest stable release.
#
set -euo pipefail

REPO="ilya-zlobintsev/LACT"
API="https://api.github.com/repos/${REPO}/releases"
VERSION="${LACT_VERSION:-latest}"

# ── Host → release asset ─────────────────────────────────────────────────────
# Upstream builds a separate package per distro release. Each version ships both
# `lact-<ver>-...` (daemon + GUI) and `lact-headless-<ver>-...` (daemon + CLI
# only) for every target, so any matcher has to exclude the headless twin — a
# plain grep for "ubuntu-2404.deb" matches both, and picking wrong silently
# installs a build with no GUI.
#
# Emits the asset-name suffix to look for, most specific first.
asset_patterns() {
    local id="" id_like="" version_id="" ubuntu_codename=""
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    id="${ID:-}"; id_like="${ID_LIKE:-}"
    version_id="${VERSION_ID:-}"; ubuntu_codename="${UBUNTU_CODENAME:-}"

    case "$id" in
        arch|cachyos|endeavouros|manjaro)
            printf '%s\n' 'pkg.tar.arch.zst'; return ;;
        fedora)
            printf '%s\n' "fedora-${version_id}.rpm" 'fedora-44.rpm' 'fedora-43.rpm'; return ;;
        opensuse*|suse*)
            printf '%s\n' 'opensuse-tumbleweed.rpm'; return ;;
        debian)
            printf '%s\n' "debian-${version_id%%.*}.deb" 'debian-13.deb'; return ;;
        ubuntu)
            printf '%s\n' "ubuntu-${version_id//./}.deb" ;;
    esac

    # Mint, Pop!_OS, elementary and friends: derive the Ubuntu base from
    # UBUNTU_CODENAME, which every Ubuntu derivative sets even when ID does not
    # say "ubuntu" (Mint 22.3 reports ID=linuxmint, VERSION_ID=22.3,
    # UBUNTU_CODENAME=noble — its own version number is meaningless here).
    case "$ubuntu_codename" in
        noble)   printf '%s\n' 'ubuntu-2404.deb' ;;
        jammy)   printf '%s\n' 'ubuntu-2204.deb' ;;
        *)       [[ -n "$ubuntu_codename" ]] && printf '%s\n' 'ubuntu-2604.deb' 'ubuntu-2404.deb' ;;
    esac

    # Last resort for anything Debian-family we could not pin down.
    case "$id_like" in
        *ubuntu*|*debian*) printf '%s\n' 'ubuntu-2404.deb' 'debian-13.deb' ;;
    esac
}

# asset_patterns deliberately lets the cases overlap (a Mint host matches both
# the codename branch and the ID_LIKE fallback), so the same pattern can be
# emitted twice. Order carries the priority, so dedupe keeping first occurrence.
asset_patterns_uniq() { asset_patterns | awk 'NF && !seen[$0]++'; }

# Install command for a downloaded package file.
install_package() {
    local file="$1"
    case "$file" in
        *.deb)          sudo apt-get install -y "$file" ;;
        *.rpm)          sudo dnf install -y "$file" ;;
        *.pkg.tar.zst)  sudo pacman -U --noconfirm "$file" ;;
        *)              echo "Error: don't know how to install '$file'" >&2; exit 1 ;;
    esac
}

remove_package() {
    if command -v apt-get >/dev/null 2>&1 && dpkg -s lact >/dev/null 2>&1; then
        sudo apt-get remove -y lact
    elif command -v dnf >/dev/null 2>&1 && rpm -q lact >/dev/null 2>&1; then
        sudo dnf remove -y lact
    elif command -v pacman >/dev/null 2>&1 && pacman -Q lact >/dev/null 2>&1; then
        sudo pacman -R --noconfirm lact
    else
        echo "==> No 'lact' package found for this host's package manager; nothing to remove."
    fi
}

uninstall() {
    echo "==> Stopping and disabling lactd..."
    # Not fatal: the unit may already be gone, or never have been enabled.
    sudo systemctl disable --now lactd || true

    echo "==> Removing the LACT package..."
    remove_package

    echo ""
    echo "Done. /etc/lact/config.yaml is left in place — your fan curves, power"
    echo "caps and profiles survive a reinstall. Remove it by hand if you want a"
    echo "clean slate:  sudo rm -rf /etc/lact"
}

install() {
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }

    local url
    if [[ "$VERSION" == "latest" ]]; then url="${API}/latest"; else url="${API}/tags/${VERSION}"; fi

    echo "==> Resolving LACT release '${VERSION}'..."
    local json
    json="$(curl -fsSL "$url")" || { echo "Error: no release '${VERSION}' at ${REPO}" >&2; exit 1; }

    # All asset names/URLs in this release, one "name<TAB>url" pair per line.
    local assets
    assets="$(printf '%s' "$json" \
        | grep -o '"browser_download_url": *"[^"]*"' \
        | sed 's/.*"\(https[^"]*\)"$/\1/' \
        | awk -F/ '{print $NF "\t" $0}')"

    local pattern name dl=""
    while read -r pattern; do
        [[ -n "$pattern" ]] || continue
        # Exclude the headless twin: names start with "lact-headless-".
        name="$(printf '%s\n' "$assets" | grep -v '	.*/lact-headless-' \
                | grep -F "$pattern" | head -1 || true)"
        if [[ -n "$name" ]]; then dl="${name#*	}"; break; fi
    done < <(asset_patterns_uniq)

    if [[ -z "$dl" ]]; then
        echo "Error: no LACT package matches this host." >&2
        echo "       Host: $(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")" >&2
        echo "       Available assets in ${VERSION}:" >&2
        printf '%s\n' "$assets" | cut -f1 | sed 's/^/         /' >&2
        echo "       Install one manually, or use the Flatpak:" >&2
        echo "         flatpak install flathub io.github.ilya_zlobintsev.LACT" >&2
        exit 1
    fi

    local tmp file
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    file="${tmp}/${dl##*/}"
    echo "==> Downloading ${dl##*/}"
    curl -fsSL -o "$file" "$dl"

    echo "==> Installing $(basename "$file") (sudo)..."
    install_package "$file"

    echo "==> Enabling and starting lactd..."
    sudo systemctl enable --now lactd

    echo ""
    sudo systemctl --no-pager --lines=0 status lactd || true
}

case "${1:-install}" in
    install)   install ;;
    uninstall) uninstall ;;
    *)         echo "Usage: $0 [install|uninstall]" >&2; exit 1 ;;
esac
