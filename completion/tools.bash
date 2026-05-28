# Bash completion for tools.sh
# Installed automatically by: ./tools.sh install

_tools_complete() {
    local cur prev script_path script_dir apps_dir commands apps
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Resolve symlink so apps/ is found regardless of how the command is invoked
    script_path="$(command -v "${COMP_WORDS[0]}" 2>/dev/null || echo "${COMP_WORDS[0]}")"
    script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
    script_dir="$(dirname "$script_path")"
    apps_dir="${script_dir}/apps"

    commands="install setup build create export rm list"

    case "$COMP_CWORD" in
        1)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        2)
            [[ "$prev" == "list" || "$prev" == "install" ]] && return
            local app_dir
            apps=""
            for app_dir in "$apps_dir"/*/; do
                [[ -d "$app_dir" ]] || continue
                app_dir="${app_dir%/}"
                apps+="${app_dir##*/} "
            done
            COMPREPLY=($(compgen -W "$apps" -- "$cur"))
            ;;
    esac
}

complete -F _tools_complete tools
complete -F _tools_complete tools.sh
complete -F _tools_complete ./tools.sh
