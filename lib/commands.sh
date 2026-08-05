cmd_build() {
    local app="$1"
    [[ -d "$APPS_DIR/$app" ]] || { echo "Error: no app directory at $APPS_DIR/$app" >&2; exit 1; }
    echo "==> Building image for '$app' using $RUNTIME..."
    # CACHE_BUST lets Dockerfiles opt out of layer caching from a given step
    # (e.g. re-resolving an upstream release tag); unused build args are ignored.
    # .buildarg wizard selections arrive as extra --build-arg pairs.
    local -a extra_args=()
    mapfile -t extra_args < <(wizard_build_args "$app")
    # Apps that need a container toolchain close to the host's (e.g. kernel
    # module builds) can ship Dockerfile.ubuntu + Dockerfile.arch instead of a
    # single Dockerfile; pick the one matching this host's distro family.
    local -a dockerfile_args=()
    if [[ -f "$APPS_DIR/$app/Dockerfile.ubuntu" && -f "$APPS_DIR/$app/Dockerfile.arch" ]]; then
        local variant
        variant="$(host_distro_family)"
        echo "==> Detected ${variant}-family host; using Dockerfile.${variant}"
        dockerfile_args=(-f "$APPS_DIR/$app/Dockerfile.${variant}")
    fi
    $RUNTIME build --build-arg CACHE_BUST="$(date +%s)" \
        "${extra_args[@]+"${extra_args[@]}"}" \
        "${dockerfile_args[@]+"${dockerfile_args[@]}"}" \
        -t "$(image_name "$app")" "$APPS_DIR/$app"
}

cmd_create() {
    local app="$1" box image
    box="$(box_name "$app")"; image="$(image_name "$app")"
    if box_exists "$app"; then
        echo "==> Distrobox '$box' already exists, skipping"
        return
    fi
    echo "==> Creating distrobox '$box'..."
    # A .runtime wizard page may select a variant (e.g. amd/nvidia). When set:
    #   create_flags.<variant>  overrides create_flags (podman --additional-flags)
    #   create_args.<variant>   supplies distrobox-level args (e.g. --nvidia) that
    #                           cannot be passed through --additional-flags
    # With no wizard selection (non-interactive create), the plain create_flags
    # file is used, preserving previous behavior.
    local variant
    variant="$(wizard_create_variant "$app")"
    local flags_file="$APPS_DIR/$app/create_flags"
    [[ -n "$variant" && -f "$APPS_DIR/$app/create_flags.$variant" ]] \
        && flags_file="$APPS_DIR/$app/create_flags.$variant"

    local -a create_cmd=(distrobox create --name "$box" --image "$image" --yes --no-entry)
    if [[ -n "$variant" && -f "$APPS_DIR/$app/create_args.$variant" ]]; then
        local extra_create_args
        extra_create_args="$(cat "$APPS_DIR/$app/create_args.$variant")"
        # Word-split intentionally: file holds distrobox flags like "--nvidia".
        # shellcheck disable=SC2206
        create_cmd+=($extra_create_args)
    fi
    [[ -f "$flags_file" ]] && create_cmd+=(--additional-flags "$(cat "$flags_file")")
    "${create_cmd[@]}"
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

    # Container-less host-only apps have no box — delegate to install.sh uninstall.
    if is_hostonly_installer "$app"; then
        echo "==> '$app' is a host-only install — running install.sh uninstall on the host..."
        bash "$APPS_DIR/$app/install.sh" uninstall
        return
    fi

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
    [[ -d "$APPS_DIR/$app" ]] || { echo "Error: no app directory at $APPS_DIR/$app" >&2; exit 1; }

    # Container-less host-only apps install straight to the host (systemd units,
    # host scripts, package deps) with no image or box, so skip build/create/export
    # entirely and just run install.sh on the host — where sudo has a real TTY.
    if is_hostonly_installer "$app"; then
        echo "==> '$app' is a host-only install (no container) — running install.sh on the host..."
        echo ""
        bash "$APPS_DIR/$app/install.sh" || { echo "Error: install.sh failed for '$app'" >&2; exit 1; }
        return  # dispatcher (tools.sh) calls cmd_setup_finish next
    fi

    if [[ -f "$APPS_DIR/$app/host-only" ]]; then
        echo "==> Note: '$app' is a HOST-ONLY install."
        echo "    Binaries → ~/.local/bin   Config → ~/.config/zsh/   Shell → ~/.zshrc"
        echo ""
    fi
    local renamed_from_file="$APPS_DIR/$app/renamed-from"
    if [[ -f "$renamed_from_file" ]]; then
        local previous_app
        read -r previous_app < "$renamed_from_file"
        if [[ -n "$previous_app" && "$previous_app" != "$app" ]]; then
            if box_exists "$previous_app"; then
                echo "==> Removing renamed Distrobox '$(box_name "$previous_app")'..."
                distrobox rm --force "$(box_name "$previous_app")"
            fi
            if image_exists "$previous_app"; then
                echo "==> Removing renamed image '$(image_name "$previous_app")'..."
                $RUNTIME rmi "$(image_name "$previous_app")"
            fi
        fi
    fi
    box_exists   "$app" && distrobox rm --force "$(box_name "$app")"
    image_exists "$app" && $RUNTIME rmi "$(image_name "$app")"
    cmd_build  "$app"
    cmd_create "$app"
    cmd_export "$app"
}

cmd_setup_finish() {
    local app="$1"
    echo ""
    echo "Done. '$app' is ready. Log out and back in if it doesn't appear in your app menu."
    local hint="$APPS_DIR/$app/post-install"
    [[ -f "$hint" ]] && echo "" && cat "$hint"
    local readme="$APPS_DIR/$app/README.md"
    if [[ -f "$readme" ]]; then
        echo ""
        echo "==> README for '$app':"
        echo ""
        if command -v glow &>/dev/null; then glow "$readme"; else cat "$readme"; fi
    fi
}

# ── Dashboard binary ─────────────────────────────────────────────────────────
# tools-tui (see tui/) is Go, and most hosts have no Go toolchain. It is built
# through a ladder so it never becomes a hard dependency: an existing binary is
# reused, a host toolchain is used if there is one, otherwise a throwaway
# container does the build, and a host with none of those simply keeps the
# whiptail menu.
#
# The Go module and build caches live in a named volume, so only the first
# container build pays for the 58 MB of module downloads.

TUI_DIR="$SCRIPT_DIR/tui"
TUI_BIN="$TUI_DIR/tools-tui"
TUI_GO_IMAGE="docker.io/library/golang:1.25-alpine"
TUI_GO_VOLUME="linux-tools-go-cache"

# Is the built binary newer than every source it was built from?
tui_bin_is_current() {
    [[ -x "$TUI_BIN" ]] || return 1
    local f
    for f in "$TUI_DIR"/*.go "$TUI_DIR/go.mod" "$TUI_DIR/go.sum"; do
        [[ -f "$f" ]] || continue
        [[ "$f" -nt "$TUI_BIN" ]] && return 1
    done
    return 0
}

# CGO_ENABLED=0 is not optional: it produces a static binary, which is what
# lets a container-built (musl) binary run on a glibc host, and lets the
# dashboard run on the host at all.
tui_build_with_host_go() {
    echo "==> Building the dashboard with the host Go toolchain..."
    ( cd "$TUI_DIR" && CGO_ENABLED=0 go build -o "$TUI_BIN" . )
}

tui_build_with_container() {
    echo "==> Building the dashboard in a $TUI_GO_IMAGE container..."
    # /go holds both caches (GOPATH/pkg/mod and the build cache), so one volume
    # covers both. :z is a no-op where SELinux is not enabled.
    $RUNTIME run --rm \
        -v "$TUI_DIR":/src:z \
        -v "$TUI_GO_VOLUME":/go \
        -w /src \
        -e CGO_ENABLED=0 \
        -e GOCACHE=/go/build-cache \
        "$TUI_GO_IMAGE" \
        go build -o /src/tools-tui .
}

# Build the dashboard binary. Never fatal: every failure mode here leaves the
# whiptail menu working, which is the whole point of the ladder.
cmd_build_tui() {
    [[ -d "$TUI_DIR" ]] || return 0

    if tui_bin_is_current; then
        echo "==> Dashboard binary is up to date: $TUI_BIN"
        return 0
    fi

    if command -v go &>/dev/null; then
        tui_build_with_host_go || {
            echo "Warning: host Go build failed; the whiptail menu still works." >&2
            return 0
        }
    elif command -v "$RUNTIME" &>/dev/null; then
        tui_build_with_container || {
            echo "Warning: container build failed (no network on first run?);" >&2
            echo "         the whiptail menu still works." >&2
            return 0
        }
    else
        echo "==> No Go toolchain and no container runtime; skipping the dashboard."
        echo "    The whiptail menu is used instead."
        return 0
    fi

    echo "==> Built: $TUI_BIN"
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

    # For zsh, write a conf.d fragment so it survives shell-toolbox regenerating ~/.zshrc
    local zsh_conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/conf.d"
    local zsh_fragment="$zsh_conf_dir/00-tools-completion.zsh"
    if [[ -d "$zsh_conf_dir" ]] || [[ -f "$HOME/.zshrc" ]]; then
        mkdir -p "$zsh_conf_dir"
        if [[ -f "$zsh_fragment" ]] && grep -qF "$SCRIPT_DIR/completion/tools.bash" "$zsh_fragment" 2>/dev/null; then
            echo "==> Completion already in $zsh_fragment"
        else
            printf '# linux-tools completion\nautoload -Uz bashcompinit && bashcompinit\n%s\n' "$completion_line" > "$zsh_fragment"
            echo "==> Wrote completion to $zsh_fragment"
        fi
    fi

    cmd_build_tui

    echo ""
    echo "Done. Open a new shell or run: source ~/.bashrc / source ~/.zshrc"
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
