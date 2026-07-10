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

list_apps() {
    local app_dir app
    for app_dir in "$APPS_DIR"/*/; do
        [[ -d "$app_dir" ]] || continue
        app="${app_dir%/}"
        printf '%s\n' "${app##*/}"
    done
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
