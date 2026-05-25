#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"

# ── Runtime detection ────────────────────────────────────────────────────────

if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "Error: neither podman nor docker found" >&2; exit 1
fi

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

app_status_label() {
    local img box
    image_exists "$1" && img="image:OK" || img="image:--"
    box_exists   "$1" && box="box:OK"   || box="box:--"
    echo "$img  $box"
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_build() {
    local app="$1"
    [[ -d "$APPS_DIR/$app" ]] || { echo "Error: no app directory at $APPS_DIR/$app" >&2; exit 1; }
    echo "==> Building image for '$app' using $RUNTIME..."
    $RUNTIME build -t "$(image_name "$app")" "$APPS_DIR/$app"
}

cmd_create() {
    local app="$1" box image
    box="$(box_name "$app")"; image="$(image_name "$app")"
    if box_exists "$app"; then
        echo "==> Distrobox '$box' already exists, skipping"
        return
    fi
    echo "==> Creating distrobox '$box'..."
    distrobox create --name "$box" --image "$image" --yes
}

cmd_export() {
    local app="$1" box
    box="$(box_name "$app")"
    local exports_file="$APPS_DIR/$app/exports"
    [[ -f "$exports_file" ]] || { echo "No exports file found, skipping"; return; }
    while IFS=: read -r type name; do
        [[ -z "$type" || "$type" == \#* ]] && continue
        name="$(echo "$name" | xargs)"
        case "$type" in
            app)
                echo "==> Exporting desktop app '$name'..."
                distrobox enter "$box" -- distrobox-export --app "$name"
                ;;
            bin)
                echo "==> Exporting binary '$name' to ~/.local/bin..."
                distrobox enter "$box" -- distrobox-export --bin "$name" --export-path ~/.local/bin
                ;;
            *)
                echo "Warning: unknown export type '$type'" >&2
                ;;
        esac
    done < "$exports_file"
}

cmd_rm() {
    local app="$1"
    echo "==> Removing distrobox '$(box_name "$app")'..."
    distrobox rm --name "$(box_name "$app")" --force
}

cmd_setup() {
    cmd_build  "$1"
    cmd_create "$1"
    cmd_export "$1"
    echo ""
    echo "Done. '$1' is ready. Log out and back in if it doesn't appear in your app menu."
}

cmd_list() {
    printf "%-20s %-30s %-12s %s\n" "APP" "DESCRIPTION" "IMAGE" "BOX"
    printf "%-20s %-30s %-12s %s\n" "───────────────────" "─────────────────────────────" "───────────" "──────────"
    for app in $(ls "$APPS_DIR" 2>/dev/null); do
        local desc img_status box_status
        desc="$(app_description "$app")"
        image_exists "$app" && img_status="built" || img_status="--"
        box_exists   "$app" && box_status="running" || box_status="--"
        printf "%-20s %-30s %-12s %s\n" "$app" "$desc" "$img_status" "$box_status"
    done
}

# ── Interactive TUI ──────────────────────────────────────────────────────────

setup_tui_theme() {
    export NEWT_COLORS='
root=white,black
border=brown,black
window=lightgray,black
shadow=gray,black
title=yellow,black
button=yellow,brown
actbutton=white,brown
compactbutton=brown,black
checkbox=lightgray,black
actcheckbox=yellow,brown
entry=yellow,brown
disentry=gray,brown
label=white,black
listbox=gray,black
actlistbox=black,brown
sellistbox=lightgray,green
actsellistbox=white,brown
textbox=white,black
acttextbox=black,cyan
emptyscale=,gray
fullscale=,brown
helpline=white,black
roottext=lightgrey,black
'
}

interactive() {
    setup_tui_theme
    command -v whiptail &>/dev/null || {
        echo "Error: whiptail not found. Install with: sudo apt install whiptail" >&2; exit 1
    }

    local apps=()
    mapfile -t apps < <(ls "$APPS_DIR" 2>/dev/null)

    if [[ ${#apps[@]} -eq 0 ]]; then
        whiptail --title "linux-tools" --msgbox "No apps found in $APPS_DIR" 8 50
        exit 0
    fi

    # Build checklist entries: name  "description  [status]"  OFF
    local checklist=()
    for app in "${apps[@]}"; do
        local desc status
        desc="$(app_description "$app")"
        status="$(app_status_label "$app")"
        checklist+=("$app" "$desc  [$status]" "OFF")
    done

    local selected
    selected=$(whiptail --title "linux-tools" \
        --checklist "Select apps  (SPACE = toggle, ENTER = confirm):" \
        20 72 10 "${checklist[@]}" 3>&1 1>&2 2>&3) || exit 0

    # whiptail wraps selections in quotes — strip them
    read -ra selected_arr <<< "$(echo "$selected" | tr -d '"')"

    if [[ ${#selected_arr[@]} -eq 0 ]]; then
        whiptail --title "linux-tools" --msgbox "No apps selected." 8 40
        exit 0
    fi

    local action
    action=$(whiptail --title "linux-tools" \
        --menu "Action for: ${selected_arr[*]}" 16 68 5 \
        "setup"  "Build image + create box + export to host" \
        "build"  "Build container image only" \
        "create" "Create distrobox from built image" \
        "export" "Re-export apps/bins to host" \
        "rm"     "Remove distrobox  (image is kept)" \
        3>&1 1>&2 2>&3) || exit 0

    whiptail --title "Confirm" \
        --yesno "Run '$action' on: ${selected_arr[*]}?" 8 58 || exit 0

    for app in "${selected_arr[@]}"; do
        "cmd_$action" "$app"
    done
}

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    local apps
    apps="$(ls "$APPS_DIR" 2>/dev/null | tr '\n' ' ')"
    cat <<EOF
Usage: $0 [command] [app]

  (no args)        Launch interactive TUI manager

Commands:
  setup  <app>     Build + create + export (full install)
  build  <app>     Build container image only
  create <app>     Create distrobox from built image
  export <app>     Export apps/bins to host menu
  rm     <app>     Remove distrobox (image is kept)
  list             Show status of all apps

Available apps: ${apps:-none}
EOF
}

# ── Entrypoint ───────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    interactive
    exit 0
fi

command_="$1"

if [[ "$command_" == "list" ]]; then
    cmd_list
    exit 0
fi

[[ $# -ge 2 ]] || { usage; exit 1; }
app="$2"

case "$command_" in
    setup)  cmd_setup  "$app" ;;
    build)  cmd_build  "$app" ;;
    create) cmd_create "$app" ;;
    export) cmd_export "$app" ;;
    rm)     cmd_rm     "$app" ;;
    *)      usage; exit 1 ;;
esac
