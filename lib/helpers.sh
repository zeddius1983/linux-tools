# ── Naming ───────────────────────────────────────────────────────────────────

image_name() { echo "linux-tools/$1:latest"; }
box_name()   { echo "$1-box"; }

# ── Status helpers ───────────────────────────────────────────────────────────

image_exists() {
    $RUNTIME image exists "$(image_name "$1")" 2>/dev/null
}

box_exists() {
    distrobox ls --no-color 2>/dev/null \
        | awk -F'|' 'NR>1 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }' \
        | grep -qx "$(box_name "$1")"
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

resolve_icon() {
    local app="$1" box="$2" name="$3"
    local ext
    for ext in png svg; do
        if [[ -f "$APPS_DIR/$app/icon.$ext" ]]; then
            printf '%s' "$APPS_DIR/$app/icon.$ext"
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
