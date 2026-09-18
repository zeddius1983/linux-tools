# shellcheck shell=bash
# ── Release identity and the installed layout ────────────────────────────────
#
# linux-tools is distributed two ways, and almost every difference between them
# is answered by one question: is there a VERSION file next to tools.sh?
#
#   release install   VERSION exists. The tree was unpacked from a release
#                     tarball into ~/.local/share/linux-tools/versions/<ver>/,
#                     with `current` pointing at it. It ships a prebuilt
#                     dashboard binary, and `tools update` swaps versions by
#                     re-running the bundled install.sh.
#
#   git checkout      No VERSION. The tree is a clone; `tools update` is a
#                     `git pull`, and the dashboard is built from source.
#
# Nothing user-owned lives inside the tree either way — wizard state goes to
# ~/.cache/linux-tools/wizard — which is what makes a versioned directory safe
# to delete and a rollback a symlink flip.

# The install root. A release tree knows its own: it lives at
# <root>/versions/<version>, so <root> is two directories up — which is what
# makes --prefix work without anything having to be told about it. Anything
# else falls back to the default location.
lt_default_root() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/linux-tools"; }

lt_root_from_tree() {
    local parent="${SCRIPT_DIR%/*}"
    [[ "${parent##*/}" == "versions" ]] || return 1
    printf '%s\n' "${parent%/*}"
}

if [[ -n "${LT_PREFIX:-}" ]]; then
    LT_DATA_DIR="$LT_PREFIX"
elif LT_DATA_DIR="$(lt_root_from_tree)"; then
    :
else
    LT_DATA_DIR="$(lt_default_root)"
fi

LT_CURRENT_LINK="$LT_DATA_DIR/current"
LT_BIN_LINK="$HOME/.local/bin/tools"

# A release tree carries VERSION at its root; package.sh writes it.
is_release_install() {
    [[ -f "$SCRIPT_DIR/VERSION" ]]
}

# Is this tree the one `current` points at? A release tarball unpacked by hand
# somewhere else is still a release tree, but it is not the managed install, and
# `tools update` must not swap the symlink out from under it.
is_managed_install() {
    is_release_install || return 1
    [[ -L "$LT_CURRENT_LINK" ]] || return 1
    local resolved
    resolved="$(readlink -f "$LT_CURRENT_LINK" 2>/dev/null)" || return 1
    [[ "$resolved" == "$SCRIPT_DIR" ]]
}

# The version string for this tree: the release tag, or a git description.
#
# Printed by `tools version`, shown in the dashboard footer, and used as the
# directory name under versions/ — so it must never be empty.
lt_version() {
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        local v
        v="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
        [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
    fi
    if command -v git &>/dev/null && git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
        local desc
        desc="$(git -C "$SCRIPT_DIR" describe --tags --always --dirty 2>/dev/null)" || desc=""
        [[ -n "$desc" ]] && { printf 'dev (%s)\n' "$desc"; return; }
    fi
    printf 'unknown\n'
}

lt_install_kind() {
    if is_managed_install; then
        echo "release"
    elif is_release_install; then
        echo "release (unmanaged)"
    elif command -v git &>/dev/null && git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
        echo "git checkout"
    else
        echo "unknown"
    fi
}

# Who owns ~/.local/bin/tools right now: "release", "checkout", "other" or
# "none". `tools install` from a clone uses this to refuse to steal the symlink
# from a release install without --dev, because a machine that has both — the
# maintainer's — otherwise silently ends up running whichever was installed last.
lt_bin_owner() {
    [[ -e "$LT_BIN_LINK" || -L "$LT_BIN_LINK" ]] || { echo "none"; return; }
    local target
    target="$(readlink -f "$LT_BIN_LINK" 2>/dev/null)" || { echo "other"; return; }
    if [[ "$target" == "$SCRIPT_DIR"/* ]]; then
        echo "checkout"
    elif [[ -f "${target%/*}/VERSION" ]]; then
        # Identified by the tree it lands in, not by where that tree sits: an
        # install under --prefix is still a release install, and a clone must
        # not walk over it just because it is somewhere unexpected.
        echo "release"
    else
        echo "other"
    fi
}

# The newest published tag, without an API call: /releases/latest redirects to
# /releases/tag/<tag>, so the effective URL is the answer. The API would also
# answer it, but it rate-limits unauthenticated callers by IP — the wrong
# failure mode for something a dashboard launch might touch.
#
# install.sh carries its own copy of this: it has to run standalone, piped from
# curl, with none of lib/ on disk yet.
lt_latest_tag() {
    local repo="zeddius1983/linux-tools" url=""
    command -v curl &>/dev/null || return 1
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
           "https://github.com/$repo/releases/latest" 2>/dev/null)" || return 1
    [[ "$url" == */releases/tag/* ]] || return 1
    printf '%s\n' "${url##*/releases/tag/}"
}
