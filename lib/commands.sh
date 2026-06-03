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
    if [[ -f "$APPS_DIR/$app/host-only" ]]; then
        echo "==> Note: '$app' is a HOST-ONLY install."
        echo "    Binaries → ~/.local/bin   Config → ~/.config/zsh/   Shell → ~/.zshrc"
        echo ""
    fi
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
        if [[ -f "$APPS_DIR/$app/host-only" ]]; then
            img_status="host-only"
            box_status="host-only"
        else
            image_exists "$app" && img_status="built" || img_status="--"
            box_exists   "$app" && box_status="running" || box_status="--"
        fi
        printf "%-20s %-30s %-12s %s\n" "$app" "$desc" "$img_status" "$box_status"
    done < <(list_apps)
}
