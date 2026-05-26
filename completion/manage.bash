# Bash completion for manage.sh
# Add to ~/.bashrc:
#   source /path/to/linux-tools/completion/manage.bash

_manage_sh_complete() {
    local cur prev script_dir apps_dir commands apps
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    script_dir="$(cd "$(dirname "${COMP_WORDS[0]}")" 2>/dev/null && pwd)"
    apps_dir="${script_dir}/apps"
    commands="setup build create export rm list"

    case "$COMP_CWORD" in
        1)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        2)
            [[ "$prev" == "list" ]] && return
            apps="$(ls "$apps_dir" 2>/dev/null | tr '\n' ' ')"
            COMPREPLY=($(compgen -W "$apps" -- "$cur"))
            ;;
    esac
}

complete -F _manage_sh_complete manage.sh
complete -F _manage_sh_complete ./manage.sh
