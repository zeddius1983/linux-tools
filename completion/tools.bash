# Bash completion for tools.sh
# Installed automatically by: ./tools.sh install

# COMPREPLY=($(compgen ...)) is the standard bash-completion idiom; the words
# compgen emits are exactly what should be split here.
# shellcheck disable=SC2207
_tools_complete() {
    local cur prev script_path script_dir apps_dir commands apps
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Resolve symlink so apps/ is found regardless of how the command is invoked
    script_path="$(command -v "${COMP_WORDS[0]}" 2>/dev/null || echo "${COMP_WORDS[0]}")"
    script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
    script_dir="$(dirname "$script_path")"
    apps_dir="${script_dir}/apps"

    commands="install update version build-tui setup build create export enter rm list"

    case "$COMP_CWORD" in
        1)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        2)
            # Commands that take flags rather than an app name.
            case "$prev" in
                install)   COMPREPLY=($(compgen -W "--dev --no-modify-rc" -- "$cur")); return ;;
                update)    COMPREPLY=($(compgen -W "--version --check" -- "$cur")); return ;;
                list|version|build-tui) return ;;
            esac
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
