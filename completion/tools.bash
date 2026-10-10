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

    commands="install update version build-tui setup build create export enter rm list help"

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
        *)
            # setup/build/create take the app's wizard parameters as KEY=value:
            # each page's param| name, or its arg| name when it has none.
            case "${COMP_WORDS[1]}" in
                setup|build|create) ;;
                *) return ;;
            esac
            local page key params=""
            for page in "$apps_dir/${COMP_WORDS[2]}"/wizard/[0-9][0-9]-*.*; do
                [[ -f "$page" ]] || continue
                key="$(sed -n 's/^param|\([A-Za-z0-9_]*\).*/\1/p' "$page" | head -1)"
                [[ -n "$key" ]] || key="$(sed -n 's/^arg|\([A-Za-z0-9_]*\).*/\1/p' "$page" | head -1)"
                [[ -n "$key" && " $params" != *" $key= "* ]] && params+="$key= "
            done
            COMPREPLY=($(compgen -W "$params" -- "$cur"))
            compopt -o nospace 2>/dev/null
            ;;
    esac
}

complete -F _tools_complete tools
complete -F _tools_complete tools.sh
complete -F _tools_complete ./tools.sh
