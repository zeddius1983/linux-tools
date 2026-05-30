#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
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

app_status_detail() {
    local app="$1"
    local desc img_id img_ref box_str
    desc="$(app_description "$app")"
    desc="${desc:0:14}"
    local img_name
    img_name="$(image_name "$app")"
    if image_exists "$app"; then
        img_id="$($RUNTIME image inspect --format '{{.Id}}' "$img_name" 2>/dev/null \
            | sed 's/^sha256://' | cut -c1-7)"
        [[ -z "$img_id" ]] && img_id="?"
        img_ref="$img_name"
    else
        img_id="—"
        img_ref="—"
    fi
    box_exists "$app" && box_str="$(box_name "$app")" || box_str="—"
    printf '%-14s  |  %-7s  |  %-32s  |  %s' "$desc" "$img_id" "$img_ref" "$box_str"
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
        distrobox enter "$box" -- cat "$icon_src" > "$extracted" 2>/dev/null \
            && printf '%s' "$extracted"
    fi
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
    local flags_file="$APPS_DIR/$app/create_flags"
    if [[ -f "$flags_file" ]]; then
        local extra_flags
        extra_flags="$(cat "$flags_file")"
        distrobox create --name "$box" --image "$image" --yes --no-entry \
            --additional-flags "$extra_flags"
    else
        distrobox create --name "$box" --image "$image" --yes --no-entry
    fi
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
                    local icon
                    icon=$(resolve_icon "$app" "$box" "$name")
                    [[ -n "$icon" ]] && sed -i "s|^Icon=.*|Icon=${icon}|" "$app_desktop"
                    # Remove duplicate exports with a different desktop ID but same Name
                    local canonical_name f
                    canonical_name=$(grep -m1 '^Name=' "$app_desktop" | cut -d= -f2-)
                    for f in "$desktop_dir/"*"${box}"*.desktop; do
                        [[ -e "$f" ]] || continue
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
                local bin_path local_icon esc_display_name
                local_icon=""
                bin_path=$(distrobox enter "$box" -- bash -c "command -pv '$name'" 2>/dev/null | grep '^/') || true
                if [[ -z "$bin_path" ]]; then
                    echo "Error: cannot find '$name' inside container" >&2
                    continue
                fi
                local_icon=$(resolve_icon "$app" "$box" "$name")
                esc_display_name=$(desktop_escape "$display_name")

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
Name=${esc_display_name}
Comment=Launching $(desktop_escape "$name") in ${box}
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
            gui)
                local display_name="${extra:-$name}"
                echo "==> Creating GUI desktop entry for '$display_name'..."
                local bin_path local_icon esc_display_name
                local_icon=""
                bin_path=$(distrobox enter "$box" -- bash -c "command -pv '$name'" 2>/dev/null | grep '^/') || true
                if [[ -z "$bin_path" ]]; then
                    echo "Error: cannot find '$name' inside container" >&2
                    continue
                fi
                local_icon=$(resolve_icon "$app" "$box" "$name")
                esc_display_name=$(desktop_escape "$display_name")

                cat > "$desktop_dir/${box}-${name}.desktop" << DESKTOPEOF
[Desktop Entry]
Name=${esc_display_name}
Comment=Launching ${esc_display_name} in ${box}
Exec=distrobox enter ${box} -- ${bin_path}
Icon=${local_icon:-utilities-terminal}
Terminal=false
Type=Application
Categories=System;
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
    local term_exec term_flag esc_app_desc
    esc_app_desc=$(desktop_escape "$app_desc")
    if [[ -n "$t_prefix" ]]; then
        term_exec="${t_prefix} distrobox enter ${box}"
        term_flag="false"
    else
        term_exec="distrobox enter ${box}"
        term_flag="true"
    fi
    cat > "$desktop_dir/${box}-terminal.desktop" << DESKTOPEOF
[Desktop Entry]
Name=${esc_app_desc} (Terminal)
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
    local box
    box="$(box_name "$app")"

    # distrobox rm handles exported binaries; we handle the desktop files it leaves behind
    echo "==> Removing distrobox '$box'..."
    distrobox rm --force "$box"

    echo "==> Removing desktop shortcuts for '$box'..."
    rm -f "$HOME/.local/share/applications/${box}"-*.desktop
    rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/${box}"-*.png
}

cmd_enter() {
    distrobox enter "$(box_name "$1")"
}

cmd_setup() {
    local app="$1"
    box_exists   "$app" && distrobox rm --force "$(box_name "$app")"
    image_exists "$app" && $RUNTIME rmi "$(image_name "$app")"
    cmd_build  "$app"
    cmd_create "$app"
    cmd_export "$app"
    echo ""
    echo "Done. '$app' is ready. Log out and back in if it doesn't appear in your app menu."
    local hint="$APPS_DIR/$app/post-install"
    [[ -f "$hint" ]] && echo "" && cat "$hint"
}

cmd_install() {
    local bin_dir="$HOME/.local/bin"
    local target="$bin_dir/tools"
    local completion_line="source \"$SCRIPT_DIR/completion/tools.bash\""

    mkdir -p "$bin_dir"
    ln -sf "$SCRIPT_DIR/tools.sh" "$target"
    echo "==> Linked: $target -> $SCRIPT_DIR/tools.sh"

    if grep -qF "$completion_line" "$HOME/.bashrc" 2>/dev/null; then
        echo "==> Completion already in ~/.bashrc"
    else
        printf '\n# linux-tools completion\n%s\n' "$completion_line" >> "$HOME/.bashrc"
        echo "==> Added completion to ~/.bashrc"
    fi

    echo ""
    echo "Done. Open a new shell or run: source ~/.bashrc"
}

cmd_list() {
    printf "%-20s %-30s %-12s %s\n" "APP" "DESCRIPTION" "IMAGE" "BOX"
    printf "%-20s %-30s %-12s %s\n" "───────────────────" "─────────────────────────────" "───────────" "──────────"
    local app
    while IFS= read -r app; do
        local desc img_status box_status
        desc="$(app_description "$app")"
        image_exists "$app" && img_status="built" || img_status="--"
        box_exists   "$app" && box_status="running" || box_status="--"
        printf "%-20s %-30s %-12s %s\n" "$app" "$desc" "$img_status" "$box_status"
    done < <(list_apps)
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

# ── Wizard system ─────────────────────────────────────────────────────────────
# Wizard pages live in apps/<app>/wizard/NN-name.<type>
# File format: line1=title, line2=prompt, line3=applicable actions (csv or *),
#              remaining lines: name|payload|description
# Types: .mcp  → whiptail checklist; applies 'claude mcp add --scope global'
#        (more types added as needed)

declare -gA _WIZARD_SELECTIONS=()

tui_run_wizards() {
    local app="$1" action="$2"
    # Explicitly reset the global associative array (plain `var=()` in a function
    # coerces it to indexed, corrupting string-keyed writes from subfunctions).
    unset _WIZARD_SELECTIONS
    declare -gA _WIZARD_SELECTIONS
    local wizard_dir="$APPS_DIR/$app/wizard"
    [[ -d "$wizard_dir" ]] || return 0
    local page
    for page in "$wizard_dir"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] || continue
        _wizard_run_page "$app" "$action" "$page" || true
    done
}

_wizard_run_page() {
    local app="$1" action="$2" page="$3"
    local fname="${page##*/}"
    local ext="${fname##*.}"
    local pagename="${fname%.*}"

    # Read header lines; strip CR so CRLF files work too
    local title prompt applicable
    { IFS= read -r title; IFS= read -r prompt; IFS= read -r applicable; } < "$page"
    title="${title%$'\r'}"
    prompt="${prompt%$'\r'}"
    applicable="${applicable%$'\r'}"

    # Check if this action should trigger the page
    if [[ "$applicable" != "*" ]]; then
        local matched=0 a
        IFS=',' read -ra acts <<< "$applicable"
        for a in "${acts[@]}"; do
            [[ "${a// /}" == "$action" ]] && matched=1 && break
        done
        [[ $matched -eq 0 ]] && return 0
    fi

    # Query current state for pre-checking (safe empty-array idiom for set -u)
    local -a current_names=()
    if box_exists "$app"; then
        case "$ext" in
            mcp)
                local line
                while IFS= read -r line; do
                    [[ -n "$line" ]] && current_names+=("$line")
                done < <(distrobox enter "$(box_name "$app")" -- \
                    claude mcp list 2>/dev/null \
                    | grep -oP '^\s+\K[^:\s]+(?=\s*:)' || true)
                ;;
        esac
    fi

    # Build whiptail item list
    local -a items=()
    local name payload desc state cur
    while IFS='|' read -r name payload desc; do
        name="${name%$'\r'}"; payload="${payload%$'\r'}"; desc="${desc%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        state="OFF"
        for cur in "${current_names[@]+"${current_names[@]}"}"; do
            [[ "$cur" == "$name" ]] && state="ON" && break
        done
        items+=("$name" "$desc" "$state")
    done < <(tail -n +4 "$page")

    [[ ${#items[@]} -eq 0 ]] && return 0

    local selected
    selected=$(whiptail --title "linux-tools — $title" \
        --checklist "$prompt  (SPACE = toggle, ENTER = confirm):" \
        20 72 10 "${items[@]}" 3>&1 1>&2 2>&3) || return 0

    _WIZARD_SELECTIONS["$pagename"]="$(tr -d '"' <<< "$selected")"
}

tui_apply_wizards() {
    local app="$1" action="$2"
    [[ ${#_WIZARD_SELECTIONS[@]} -eq 0 ]] && return 0
    local wizard_dir="$APPS_DIR/$app/wizard"
    local pagename
    for pagename in "${!_WIZARD_SELECTIONS[@]}"; do
        # Find the wizard file by pagename (extension is the type)
        local match=""
        local f
        for f in "$wizard_dir/$pagename".*; do
            [[ -f "$f" ]] && match="$f" && break
        done
        [[ -n "$match" ]] || continue
        local ext="${match##*.}"
        case "$ext" in
            mcp) _wizard_apply_mcp "$app" "$match" "${_WIZARD_SELECTIONS[$pagename]}" ;;
        esac
    done
}

_wizard_apply_mcp() {
    local app="$1" page="$2" selected_str="${3:-}"
    local -a selected_arr=()
    [[ -n "$selected_str" ]] && read -ra selected_arr <<< "$selected_str"
    local box
    box="$(box_name "$app")"
    local name payload desc should_install s
    while IFS='|' read -r name payload desc; do
        name="${name%$'\r'}"; payload="${payload%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        should_install=0
        for s in "${selected_arr[@]+"${selected_arr[@]}"}"; do
            [[ "$s" == "$name" ]] && should_install=1 && break
        done
        if [[ $should_install -eq 1 ]]; then
            echo "==> Configuring MCP server: $name"
            distrobox enter "$box" -- \
                claude mcp add --scope global "$name" -- npx -y "$payload" \
                || echo "Warning: failed to configure MCP server '$name'" >&2
        else
            distrobox enter "$box" -- \
                claude mcp remove --scope global "$name" 2>/dev/null || true
        fi
    done < <(tail -n +4 "$page")
}

# ── Main TUI loop ─────────────────────────────────────────────────────────────

interactive() {
    setup_tui_theme
    command -v whiptail &>/dev/null || {
        echo "Error: whiptail not found. Install with: sudo apt install whiptail" >&2; exit 1
    }

    local apps=()
    mapfile -t apps < <(list_apps)

    if [[ ${#apps[@]} -eq 0 ]]; then
        whiptail --title "linux-tools" --msgbox "No apps found in $APPS_DIR" 8 50
        exit 0
    fi

    # Build menu: detail line as tag (what's displayed), app name as lookup key.
    # --menu shows only the tag column when item is empty, giving a clean list
    # without radio buttons or duplicate short names.
    local -a menu_items=()
    declare -A detail_to_app=()
    local app detail
    for app in "${apps[@]}"; do
        detail="$(app_status_detail "$app")"
        menu_items+=("$detail" "")
        detail_to_app["$detail"]="$app"
    done

    local selected_detail
    selected_detail=$(whiptail --title "linux-tools" \
        --menu "Select app  (arrow keys, ENTER to confirm):" \
        20 104 10 "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 0
    [[ -z "$selected_detail" ]] && exit 0

    local selected="${detail_to_app["$selected_detail"]}"
    [[ -z "$selected" ]] && exit 0

    local action
    action=$(whiptail --title "linux-tools — $selected" \
        --menu "Choose action:" 16 68 6 \
        "setup"  "Install  (removes existing box+image first)" \
        "build"  "Build container image only" \
        "create" "Create distrobox from built image" \
        "export" "Re-export apps/bins to host" \
        "enter"  "Open shell inside box" \
        "rm"     "Remove distrobox  (image is kept)" \
        3>&1 1>&2 2>&3) || exit 0

    tui_run_wizards "$selected" "$action"

    whiptail --title "Confirm" \
        --yesno "Run '$action' on '$selected'?" 8 58 || exit 0

    "cmd_$action" "$selected"

    tui_apply_wizards "$selected" "$action"
}

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    local apps
    apps="$(list_apps | tr '\n' ' ')"
    cat <<EOF
Usage: $0 [command] [app]

  (no args)        Launch interactive TUI manager

Commands:
  install          Symlink as 'tools' in ~/.local/bin + set up completion
  setup  <app>     Install app (removes existing box+image first)
  build  <app>     Build container image only
  create <app>     Create distrobox from built image
  export <app>     Export apps/bins to host menu
  enter  <app>     Open shell inside box
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

if [[ "$command_" == "install" ]]; then
    cmd_install
    exit 0
fi

[[ $# -ge 2 ]] || { usage; exit 1; }
app="$2"

case "$command_" in
    setup)  cmd_setup  "$app" ;;
    build)  cmd_build  "$app" ;;
    create) cmd_create "$app" ;;
    export) cmd_export "$app" ;;
    enter)  cmd_enter  "$app" ;;
    rm)     cmd_rm     "$app" ;;
    *)      usage; exit 1 ;;
esac
