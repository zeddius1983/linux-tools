# shellcheck shell=bash
# ── Naming ───────────────────────────────────────────────────────────────────

image_name() { echo "linux-tools/$1:latest"; }
box_name()   { echo "$1-box"; }

# ── Runtime ──────────────────────────────────────────────────────────────────

# Commands that touch images or boxes need podman or docker; install, version
# and update do not. Checking here rather than at startup means linux-tools can
# be installed on a host that has not set up a container runtime yet, and says
# so when it first matters instead of refusing to install at all.
require_runtime() {
    [[ -n "${RUNTIME:-}" ]] && return 0
    echo "Error: neither podman nor docker found." >&2
    echo "       podman: https://podman.io/docs/installation" >&2
    exit 1
}

# ── GitHub ───────────────────────────────────────────────────────────────────

# GitHub API GET. Anonymous calls are limited to 60/hour per address; with
# GITHUB_TOKEN or GH_TOKEN set (e.g. `export GH_TOKEN=$(gh auth token)`) the
# limit is the account's 5000/hour. The header is read from a file descriptor
# so the token never appears in the process list. No permissions are needed.
github_curl() {
    local tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [[ -n "$tok" ]]; then
        curl -fsSL -H @<(printf 'Authorization: Bearer %s\n' "$tok") "$@"
    else
        curl -fsSL "$@"
    fi
}

# ── Status helpers ───────────────────────────────────────────────────────────

image_exists() {
    $RUNTIME image exists "$(image_name "$1")" 2>/dev/null
}

box_exists() {
    distrobox ls --no-color 2>/dev/null \
        | awk -F'|' 'NR>1 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }' \
        | grep -qx "$(box_name "$1")"
}

# Stop processes that belong to a box but have left its cgroup. Removing a box
# kills only what is in its libpod-<id>.scope, and Electron/Chromium apps move
# themselves into their own app-<name>-<pid>.scope over the shared session bus,
# so they outlive `distrobox rm` and keep running on the deleted image. Orca is
# the costly case: its terminal daemon survives the window too, and a relaunched
# Orca reconnects to it and keeps opening terminals in the old box.
#
# Processes are matched by the container ID in their own /run/.containerenv,
# read through /proc/<pid>/root, which works whatever cgroup they are in and
# even when the box is stopped. Podman only: docker writes no ID there.
#
# Run it before anything is removed: if it kills the terminal `tools` was
# started from (an Orca terminal, say), the command dies with the old box and
# image still in place instead of halfway through a rebuild.
stop_box_processes() {
    local box id pid d i
    local -a left=()
    box="$(box_name "$1")"
    [[ "$RUNTIME" == podman ]] || return 0
    id="$($RUNTIME inspect -f '{{.Id}}' "$box" 2>/dev/null)" || return 0
    [[ -n "$id" ]] || return 0
    local -a pids=()
    for d in /proc/[0-9]*; do
        grep -qs "^id=\"$id\"" "$d/root/run/.containerenv" || continue
        grep -qs "libpod-$id" "$d/cgroup" && continue  # distrobox rm handles these
        pids+=("${d#/proc/}")
    done
    ((${#pids[@]})) || return 0

    echo "==> Stopping ${#pids[@]} process(es) still running from '$box' outside the container..."
    kill -TERM "${pids[@]}" 2>/dev/null || true
    for ((i = 0; i < 50; ++i)); do
        left=()
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && left+=("$pid")
        done
        ((${#left[@]})) || return 0
        sleep 0.2
    done
    kill -KILL "${left[@]}" 2>/dev/null || true
}

app_description() {
    local f="$APPS_DIR/$1/description"
    [[ -f "$f" ]] && cat "$f" || echo "$1"
}

# A container-less host-only app: 'host-only' marker + an install.sh and NO
# Dockerfile of any kind. `tools setup` runs install.sh on the host and skips the
# whole build/create/export/box lifecycle; `tools rm` runs install.sh uninstall.
is_hostonly_installer() {
    local app="$1"
    [[ -f "$APPS_DIR/$app/host-only" && -f "$APPS_DIR/$app/install.sh" \
       && ! -f "$APPS_DIR/$app/Dockerfile" \
       && ! -f "$APPS_DIR/$app/Dockerfile.arch" \
       && ! -f "$APPS_DIR/$app/Dockerfile.ubuntu" ]]
}

list_apps() {
    local app_dir app
    for app_dir in "$APPS_DIR"/*/; do
        [[ -d "$app_dir" ]] || continue
        app="${app_dir%/}"
        printf '%s\n' "${app##*/}"
    done
}

require_app() {
    if [[ -z "$1" || ! -d "$APPS_DIR/$1" ]]; then
        echo "Error: no app named '$1'. Available: $(list_apps | tr '\n' ' ')" >&2
        exit 1
    fi
}

# ── Host detection ───────────────────────────────────────────────────────────

# Used to pick between Dockerfile.ubuntu / Dockerfile.arch for apps that ship
# both (e.g. corefreq, where the container's toolchain has to be close enough
# to whatever built the host kernel). Apps with a single Dockerfile are
# unaffected.
host_distro_family() {
    local ids
    ids=$(bash -c 'source /etc/os-release 2>/dev/null && echo "${ID:-} ${ID_LIKE:-}"')
    if [[ "$ids" == *arch* ]]; then
        echo "arch"
    else
        echo "ubuntu"
    fi
}

# ── Terminal detection ───────────────────────────────────────────────────────

pick_terminal() {
    for t in ghostty kitty alacritty gnome-terminal xfce4-terminal mate-terminal konsole xterm; do
        command -v "$t" &>/dev/null && echo "$t" && return
    done
}

terminal_exec_prefix() {
    case "${1:-}" in
        ghostty|kitty|alacritty) echo "$1 -e" ;;
        gnome-terminal|mate-terminal|xfce4-terminal|konsole) echo "$1 --" ;;
        xterm) echo "xterm -e" ;;
        *) echo "" ;;
    esac
}

# ── Desktop helpers ──────────────────────────────────────────────────────────

desktop_escape() {
    local s="${1//\\/\\\\}"
    printf '%s' "${s//$'\n'/\\n}"
}

# Where an exported entry's icon is kept: outside the linux-tools tree, because
# in a release install that tree is versions/<ver>/, which a later `tools update`
# prunes. `tools rm` deletes these by the same <box>-<name> prefix.
stable_icon_path() {  # stable_icon_path <box> <name> <png|svg>
    local dir="$HOME/.local/share/icons/hicolor/256x256/apps"
    [[ "$3" == svg ]] && dir="$HOME/.local/share/icons/hicolor/scalable/apps"
    printf '%s' "$dir/$1-$2.$3"
}

# Copy an app's bundled icon to its stable path (only when it changed) and
# print that path.
install_bundled_icon() {  # install_bundled_icon <src> <box> <name> <ext>
    local dest
    dest="$(stable_icon_path "$2" "$3" "$4")"
    mkdir -p "${dest%/*}"
    cmp -s "$1" "$dest" || cp "$1" "$dest" || return 1
    printf '%s' "$dest"
}

resolve_icon() {
    local app="$1" box="$2" name="$3"
    local ext
    for ext in png svg; do
        if [[ -f "$APPS_DIR/$app/icon.$ext" ]]; then
            install_bundled_icon "$APPS_DIR/$app/icon.$ext" "$box" "$name" "$ext"
            return
        fi
    done
    local icon_dir icon_src
    icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
    icon_src=$(distrobox enter "$box" -- bash -c '
        for f in \
            "/usr/share/icons/hicolor/256x256/apps/$1-code.png" \
            "/usr/share/icons/hicolor/256x256/apps/$1.png" \
            "/usr/share/icons/hicolor/512x512/apps/$1-code.png" \
            "/usr/share/icons/hicolor/512x512/apps/$1.png" \
            "/usr/share/icons/hicolor/128x128/apps/$1-code.png" \
            "/usr/share/icons/hicolor/128x128/apps/$1.png" \
            "/usr/share/pixmaps/$1-code.png" \
            "/usr/share/pixmaps/$1.png"; do
            [ -f "$f" ] && echo "$f" && exit 0
        done' _ "$name" 2>/dev/null | grep '^/') || true
    if [[ -n "$icon_src" ]]; then
        mkdir -p "$icon_dir"
        local extracted="$icon_dir/${box}-${name}.png"
        distrobox enter "$box" -- cp "$icon_src" "$extracted" 2>/dev/null \
            && printf '%s' "$extracted"
    fi
}
