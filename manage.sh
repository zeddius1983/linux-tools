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
    distrobox create --name "$box" --image "$image" --yes --no-entry
}

cmd_export() {
    local app="$1" box
    box="$(box_name "$app")"
    local exports_file="$APPS_DIR/$app/exports"
    [[ -f "$exports_file" ]] || { echo "No exports file found, skipping"; return; }

    local term t_prefix desktop_dir app_desc
    term=$(pick_terminal)
    t_prefix=$(terminal_exec_prefix "$term")
    desktop_dir="$HOME/.local/share/applications"
    app_desc="$(app_description "$app")"
    mkdir -p "$desktop_dir"

    # Remove terminal shortcut before running distrobox-export so it isn't
    # visible in the shared home dir and re-exported with a doubled prefix.
    rm -f "$desktop_dir/${box}-terminal.desktop"

    while IFS=: read -r type name extra <&3; do
        [[ -z "$type" || "$type" == \#* ]] && continue
        name="$(echo "$name" | xargs)"
        extra="$(echo "$extra" | xargs)"
        case "$type" in
            app)
                local display_name="${extra:-$name}"
                echo "==> Exporting desktop app '$name'..."
                distrobox enter "$box" -- distrobox-export --app "$name"
                local app_desktop="$HOME/.local/share/applications/${box}-${name}.desktop"
                if [[ -f "$app_desktop" ]]; then
                    sed -i "s|^Name=.*|Name=${display_name} (on ${box})|" "$app_desktop"
                    ! grep -q '^Comment=' "$app_desktop" && \
                        sed -i "/^\[Desktop Entry\]/a Comment=Launching ${display_name} in ${box}" "$app_desktop"
                    local ext bundled_icon=""
                    for ext in png svg; do
                        if [[ -f "$APPS_DIR/$app/icon.$ext" ]]; then
                            bundled_icon="$APPS_DIR/$app/icon.$ext"
                            break
                        fi
                    done
                    if [[ -z "$bundled_icon" ]]; then
                        local icon_dir icon_src
                        icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
                        icon_src=$(distrobox enter "$box" -- bash -c "
                            for f in \
                                /usr/share/icons/hicolor/256x256/apps/${name}-code.png \
                                /usr/share/icons/hicolor/256x256/apps/${name}.png \
                                /usr/share/icons/hicolor/512x512/apps/${name}-code.png \
                                /usr/share/icons/hicolor/512x512/apps/${name}.png \
                                /usr/share/icons/hicolor/128x128/apps/${name}-code.png \
                                /usr/share/icons/hicolor/128x128/apps/${name}.png \
                                /usr/share/pixmaps/${name}-code.png \
                                /usr/share/pixmaps/${name}.png; do
                                [ -f \"\$f\" ] && echo \"\$f\" && exit 0
                            done" 2>/dev/null | grep '^/') || true
                        if [[ -n "$icon_src" ]]; then
                            mkdir -p "$icon_dir"
                            local extracted_icon="$icon_dir/${box}-${name}.png"
                            distrobox enter "$box" -- cat "$icon_src" > "$extracted_icon" 2>/dev/null \
                                && bundled_icon="$extracted_icon"
                        fi
                    fi
                    [[ -n "$bundled_icon" ]] && \
                        sed -i "s|^Icon=.*|Icon=${bundled_icon}|" "$app_desktop"
                    # Remove duplicate exports with a different desktop ID but same Name
                    local canonical_name
                    canonical_name=$(grep -m1 '^Name=' "$app_desktop" | cut -d= -f2-)
                    for f in "$desktop_dir/"*"${box}"*.desktop; do
                        [[ "$f" == "$app_desktop" || "$f" == "$desktop_dir/${box}-terminal.desktop" ]] && continue
                        [[ "$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2-)" == "$canonical_name" ]] && rm -f "$f"
                    done
                fi
                ;;
            bin)
                echo "==> Exporting binary '$name' to ~/.local/bin..."
                local bin_path
                bin_path=$(distrobox enter "$box" -- bash -c "command -pv '$name'" 2>/dev/null | grep '^/') || true
                if [[ -z "$bin_path" ]]; then
                    echo "Error: cannot find '$name' inside container" >&2
                    continue
                fi
                distrobox enter "$box" -- distrobox-export --bin "$bin_path" --export-path ~/.local/bin
                ;;
            desktop)
                local display_name="${extra:-$name}"
                echo "==> Creating desktop entry for '$display_name'..."
                local bin_path local_icon=""
                bin_path=$(distrobox enter "$box" -- bash -c "command -pv '$name'" 2>/dev/null | grep '^/') || true
                if [[ -z "$bin_path" ]]; then
                    echo "Error: cannot find '$name' inside container" >&2
                    continue
                fi

                # Prefer project-bundled icon, fall back to searching the container
                local ext
                for ext in png svg; do
                    if [[ -f "$APPS_DIR/$app/icon.$ext" ]]; then
                        local_icon="$APPS_DIR/$app/icon.$ext"
                        break
                    fi
                done
                if [[ -z "$local_icon" ]]; then
                    local icon_dir icon_src
                    icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
                    icon_src=$(distrobox enter "$box" -- bash -c "
                        for f in \
                            /usr/share/icons/hicolor/256x256/apps/${name}-code.png \
                            /usr/share/icons/hicolor/256x256/apps/${name}.png \
                            /usr/share/icons/hicolor/512x512/apps/${name}-code.png \
                            /usr/share/icons/hicolor/512x512/apps/${name}.png \
                            /usr/share/icons/hicolor/128x128/apps/${name}-code.png \
                            /usr/share/icons/hicolor/128x128/apps/${name}.png \
                            /usr/share/pixmaps/${name}-code.png \
                            /usr/share/pixmaps/${name}.png; do
                            [ -f \"\$f\" ] && echo \"\$f\" && exit 0
                        done" 2>/dev/null | grep '^/') || true
                    if [[ -n "$icon_src" ]]; then
                        mkdir -p "$icon_dir"
                        local_icon="$icon_dir/${box}-${name}.png"
                        distrobox enter "$box" -- cat "$icon_src" > "$local_icon" 2>/dev/null \
                            || local_icon=""
                    fi
                fi

                local app_exec app_flag
                if [[ -n "$t_prefix" ]]; then
                    app_exec="${t_prefix} distrobox enter ${box} -- ${bin_path}"
                    app_flag="false"
                else
                    app_exec="distrobox enter ${box} -- ${bin_path}"
                    app_flag="true"
                fi
                cat > "$desktop_dir/${box}-${name}.desktop" << DESKTOPEOF
[Desktop Entry]
Name=${display_name}
Comment=Launching ${name} in ${box}
Exec=${app_exec}
Icon=${local_icon:-utilities-terminal}
Terminal=${app_flag}
Type=Application
Categories=Development;
DESKTOPEOF
                echo "   Created: $desktop_dir/${box}-${name}.desktop"
                [[ -n "$local_icon" ]] && echo "   Icon:    $local_icon" \
                    || echo "   Icon:    not found, place icon.png in apps/${app}/ to set one"
                ;;
            *)
                echo "Warning: unknown export type '$type'" >&2
                ;;
        esac
    done 3< "$exports_file"

    # Terminal shortcut is created after all app exports so distrobox-export
    # doesn't pick it up from the shared home dir and double-export it.
    local term_exec term_flag
    if [[ -n "$t_prefix" ]]; then
        term_exec="${t_prefix} distrobox enter ${box}"
        term_flag="false"
    else
        term_exec="distrobox enter ${box}"
        term_flag="true"
    fi
    cat > "$desktop_dir/${box}-terminal.desktop" << DESKTOPEOF
[Desktop Entry]
Name=${app_desc} (Terminal)
Comment=Terminal entering ${box}
Exec=${term_exec}
Icon=utilities-terminal
Terminal=${term_flag}
Type=Application
Categories=System;
DESKTOPEOF
    echo "==> Terminal shortcut: $desktop_dir/${box}-terminal.desktop"
}

cmd_rm() {
    local app="$1"
    echo "==> Removing distrobox '$(box_name "$app")'..."
    distrobox rm --force "$(box_name "$app")"
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
