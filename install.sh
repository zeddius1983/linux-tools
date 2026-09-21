#!/usr/bin/env bash
#
# linux-tools installer.
#
#   curl -fsSL https://raw.githubusercontent.com/zeddius1983/linux-tools/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --version v2026.09.1
#
# Installs a release tarball into a versioned directory and points `current` at
# it, so an update is a download plus a symlink flip and a rollback is a symlink
# flip on its own:
#
#   ~/.local/share/linux-tools/versions/2026.09.1/
#   ~/.local/share/linux-tools/current -> versions/2026.09.1
#   ~/.local/bin/tools -> ~/.local/share/linux-tools/current/tools.sh
#
# Nothing user-owned lives in those directories — wizard state is written to
# ~/.cache/linux-tools — so old versions are safe to prune and safe to go back to.
#
# This same script is shipped inside every release tarball, and `tools update`
# runs it: there is exactly one implementation of download-verify-swap.

set -euo pipefail

REPO="zeddius1983/linux-tools"
# LT_RELEASES_URL is a test seam: scripts/test-install-e2e.sh points it at a
# local server that mimics GitHub's redirects, so the download, checksum and
# tag-resolution paths can be exercised without publishing anything.
RELEASES_URL="${LT_RELEASES_URL:-https://github.com/$REPO/releases}"

DATA_DIR="${LT_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/linux-tools}"
BIN_DIR="$HOME/.local/bin"

WORKDIR=""          # scratch space for the download, removed on exit
REQ_VERSION=""      # --version: a tag, pinned
LOCAL_TARBALL=""    # --tarball: install a local file, skipping download
KEEP=3              # --keep: how many versions to retain
MODIFY_RC=1         # --no-modify-rc
SKIP_CHECKS=0       # --skip-checks
FORCE=0             # --force: re-unpack a version already on disk

# ── Output ───────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
    C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_B=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi

say()  { printf '%s==>%s %s\n' "$C_B" "$C_OFF" "$*"; }
info() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
warn() { printf '%swarning:%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
linux-tools installer

Usage: install.sh [options]

  --version <tag>     install a specific release (e.g. v2026.09.1) instead of
                      the latest one; also how you roll back
  --prefix <dir>      install root (default: $DATA_DIR)
  --tarball <path>    install from a local tarball, skipping the download
  --keep <n>          keep the n most recent versions (default: $KEEP)
  --no-modify-rc      do not touch ~/.bashrc or the zsh completion fragment
  --skip-checks       proceed even if podman/docker or distrobox are missing
  --force             re-unpack a version that is already installed
  -h, --help          this message

Releases: $RELEASES_URL
EOF
}

# ── Arguments ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) REQ_VERSION="${2:-}"; [[ -n "$REQ_VERSION" ]] || die "--version needs a tag"; shift 2 ;;
        --prefix)  DATA_DIR="${2:-}";    [[ -n "$DATA_DIR" ]]    || die "--prefix needs a directory"; shift 2 ;;
        --tarball) LOCAL_TARBALL="${2:-}"; [[ -n "$LOCAL_TARBALL" ]] || die "--tarball needs a path"; shift 2 ;;
        --keep)    KEEP="${2:-}"; [[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep needs a number"; shift 2 ;;
        --no-modify-rc) MODIFY_RC=0; shift ;;
        --skip-checks)  SKIP_CHECKS=1; shift ;;
        --force)        FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

# Absolute from here on. `current` is created with a target that the symlink
# stores verbatim, and a relative target is resolved against the directory
# holding the link — so a relative --prefix would point current at
# <prefix>/<prefix>/versions/... and every path built from it, the `tools`
# command included, would dangle while the install still reported success.
mkdir -p "$DATA_DIR" 2>/dev/null || die "cannot create $DATA_DIR"
DATA_DIR="$(cd "$DATA_DIR" && pwd)"

VERSIONS_DIR="$DATA_DIR/versions"
CURRENT_LINK="$DATA_DIR/current"

cleanup() { [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# ── Preflight ────────────────────────────────────────────────────────────────

have() { command -v "$1" &>/dev/null; }

DOWNLOADER=""
preflight() {
    have tar || die "tar is required"

    if have curl; then
        DOWNLOADER="curl"
    elif have wget; then
        DOWNLOADER="wget"
    elif [[ -z "$LOCAL_TARBALL" ]]; then
        die "curl or wget is required to download a release"
    fi

    have sha256sum || warn "sha256sum not found — the download cannot be verified"

    # Runtime prerequisites. linux-tools installs fine without them, but it
    # cannot do anything, so say so loudly rather than at first use.
    #
    # This gates a *first* install only. Updating an installation that already
    # exists is not the moment to relitigate the host's setup: `tools update`
    # comes back through here, and refusing to move someone to a new release
    # because distrobox is currently missing helps nobody.
    local updating=0
    [[ -L "$CURRENT_LINK" ]] && updating=1

    local missing=()
    have podman || have docker || missing+=("podman (or docker)")
    have distrobox || missing+=("distrobox")
    if ((${#missing[@]})); then
        if ((SKIP_CHECKS || updating)); then
            warn "missing: ${missing[*]} — continuing anyway"
        else
            printf '%serror:%s linux-tools needs %s on the host.\n' \
                "$C_ERR" "$C_OFF" "$(join_by ', ' "${missing[@]}")" >&2
            printf '       podman:    https://podman.io/docs/installation\n' >&2
            printf '       distrobox: https://distrobox.it/#installation\n' >&2
            printf '       Re-run with --skip-checks to install anyway.\n' >&2
            exit 1
        fi
    fi

    # Not required to install, but required for anything using
    # distrobox-host-exec — and its absence is completely silent at runtime:
    # host commands just return with no output and no error. Worth one line now
    # rather than a debugging session later.
    have flatpak || warn "flatpak is not installed on the host.
         distrobox-host-exec needs it (it talks to the host over the
         org.freedesktop.Flatpak D-Bus interface) and fails *silently* without
         it — no error, no hang. Apps that reach the host (corefreq,
         shell-toolbox, comfyui) will not work until it is installed."
}

join_by() { local d="$1"; shift; printf '%s' "$1"; shift; printf '%s' "${@/#/$d}"; }

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) die "unsupported architecture: $(uname -m) (releases cover amd64 and arm64)" ;;
    esac
}

# ── Download ─────────────────────────────────────────────────────────────────

fetch() {  # fetch <url> <dest>
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --retry 3 --retry-delay 1 -o "$2" "$1"
    else
        wget -q -t 3 -O "$2" "$1"
    fi
}

# The tag of the newest release, without an API call: the /releases/latest page
# redirects to /releases/tag/<tag>, so the effective URL carries the answer.
# GitHub's API would do this too, but it rate-limits unauthenticated callers by
# IP, which is exactly the wrong failure mode for an installer.
resolve_latest_tag() {
    local url=""
    if [[ "$DOWNLOADER" == "curl" ]]; then
        url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$RELEASES_URL/latest" 2>/dev/null)" || return 1
    else
        url="$(wget -q -S --max-redirect=5 --spider "$RELEASES_URL/latest" 2>&1 \
               | awk '/^[[:space:]]*Location:/ { print $2 }' | tail -1)" || return 1
    fi
    [[ "$url" == */releases/tag/* ]] || return 1
    printf '%s\n' "${url##*/releases/tag/}"
}

# Best-effort, purely for the error message when a pinned tag does not exist.
recent_tags() {
    local json
    json="$(fetch "https://api.github.com/repos/$REPO/releases?per_page=5" /dev/stdout 2>/dev/null)" || return 1
    printf '%s' "$json" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4
}

# ── Install steps ────────────────────────────────────────────────────────────

# Point `current` at a version directory without a window where it is missing:
# create the new link under a temporary name, then rename it over the old one.
swap_current() {  # swap_current <version-dir>
    ln -sfn "$1" "$CURRENT_LINK.tmp"
    mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"
}

# Hand off to the tree's own installer for the host-side wiring (the `tools`
# symlink, shell completion, dashboard). One implementation, used by both
# install kinds — and it links through `current`, not the versioned path, so
# the next update does not leave a dead symlink behind.
wire_host() {  # wire_host <version-dir>
    local -a args=()
    ((MODIFY_RC)) || args+=(--no-modify-rc)
    "$1/tools.sh" install "${args[@]+"${args[@]}"}"
}

# Keep the newest $KEEP versions, never removing the one in use. Each tree is
# around 9 MB and holds nothing the user owns, so old ones are pure cache —
# except as rollback targets, which is why a few are kept rather than one.
prune_versions() {  # prune_versions <keep-version>
    local keep_ver="$1" dir name
    local -a all=()
    while IFS= read -r dir; do all+=("$dir"); done < <(
        find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -rV
    )
    ((${#all[@]} > KEEP)) || return 0
    local i=0
    for name in "${all[@]}"; do
        # ++i, not i++: the post-increment form evaluates to the old value, so
        # the very first iteration would be an arithmetic expression worth 0 —
        # a non-zero exit status, and under `set -e` the end of the script.
        ((++i))
        ((i > KEEP)) || continue
        [[ "$name" == "$keep_ver" ]] && continue
        info "pruning old version $name"
        rm -rf -- "${VERSIONS_DIR:?}/$name"
    done
}

summary() {  # summary <version> <version-dir>
    echo
    printf '%s linux-tools %s installed%s\n' "$C_OK" "$1" "$C_OFF"
    info "tree:    $2"
    info "current: $CURRENT_LINK"
    info "command: $BIN_DIR/tools"
    echo
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR is not on your PATH — add it to your shell profile."
    fi
    echo "Open a new shell (or: source ~/.bashrc), then run: tools"
}

main() {
    preflight
    mkdir -p "$VERSIONS_DIR" "$BIN_DIR"

    local arch asset
    arch="$(detect_arch)"
    asset="linux-tools-linux-${arch}.tar.gz"

    # 1. Work out which version is wanted, and short-circuit if it is already
    #    unpacked — that turns `tools update --version <old>` into a symlink
    #    flip with no network at all.
    local tag="" want_ver=""
    if [[ -n "$LOCAL_TARBALL" ]]; then
        [[ -f "$LOCAL_TARBALL" ]] || die "no such tarball: $LOCAL_TARBALL"
    elif [[ -n "$REQ_VERSION" ]]; then
        tag="$REQ_VERSION"
        [[ "$tag" == v* ]] || tag="v$tag"
        want_ver="${tag#v}"
    else
        say "Resolving the latest release..."
        if tag="$(resolve_latest_tag)"; then
            want_ver="${tag#v}"
            info "latest is $tag"
        else
            tag=""
            warn "could not resolve the latest tag; downloading anyway"
        fi
    fi

    if [[ -n "$want_ver" && -d "$VERSIONS_DIR/$want_ver" && $FORCE -eq 0 ]]; then
        say "Version $want_ver is already installed — switching to it"
        swap_current "$VERSIONS_DIR/$want_ver"
        wire_host "$VERSIONS_DIR/$want_ver"
        summary "$want_ver" "$VERSIONS_DIR/$want_ver"
        return
    fi

    # 2. Fetch and verify.
    #    WORKDIR is global: the EXIT trap runs outside this function, where a
    #    local would be unset — and under `set -u` that turns a clean install
    #    into a non-zero exit after the success message.
    WORKDIR="$(mktemp -d)"
    local tmp="$WORKDIR"

    local tarball
    if [[ -n "$LOCAL_TARBALL" ]]; then
        tarball="$LOCAL_TARBALL"
        say "Installing from $tarball"
    else
        local base
        if [[ -n "$tag" ]]; then base="$RELEASES_URL/download/$tag"
        else                     base="$RELEASES_URL/latest/download"; fi

        tarball="$tmp/$asset"
        say "Downloading ${tag:-latest} ($arch)..."
        if ! fetch "$base/$asset" "$tarball"; then
            printf '%serror:%s no release asset at %s\n' "$C_ERR" "$C_OFF" "$base/$asset" >&2
            local tags
            if tags="$(recent_tags)" && [[ -n "$tags" ]]; then
                printf '       recent releases: %s\n' "$(echo "$tags" | tr '\n' ' ')" >&2
            fi
            printf '       see %s\n' "$RELEASES_URL" >&2
            exit 1
        fi

        if have sha256sum && fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS" 2>/dev/null; then
            say "Verifying checksum..."
            ( cd "$tmp" && sha256sum --ignore-missing -c SHA256SUMS >/dev/null 2>&1 ) \
                || die "checksum mismatch for $asset — refusing to install"
            info "ok"
        else
            warn "no SHA256SUMS published for this release; skipping verification"
        fi
    fi

    # 3. Unpack, and take the version from the tree itself rather than the tag,
    #    so the directory name always matches what `tools version` will report.
    say "Unpacking..."
    mkdir -p "$tmp/tree"
    tar -xzf "$tarball" -C "$tmp/tree" --strip-components=1

    [[ -f "$tmp/tree/tools.sh" ]] || die "that tarball does not look like linux-tools"
    [[ -f "$tmp/tree/VERSION" ]]  || die "tarball has no VERSION file"
    local version
    version="$(tr -d '[:space:]' < "$tmp/tree/VERSION")"
    [[ -n "$version" ]] || die "tarball has an empty VERSION file"

    local dest="$VERSIONS_DIR/$version"
    if [[ -d "$dest" ]]; then
        say "Replacing the existing $version tree"
        rm -rf -- "$dest"
    fi
    mv -T "$tmp/tree" "$dest"
    chmod +x "$dest/tools.sh" "$dest/install.sh" 2>/dev/null || true

    # 4. Publish it, wire up the host, tidy up.
    swap_current "$dest"
    say "Wiring up the host..."
    wire_host "$dest"
    prune_versions "$version"
    summary "$version" "$dest"
}

main
