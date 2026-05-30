# Wizard pages live in apps/<app>/wizard/NN-name.<type>
# File format: line1=title  line2=prompt  line3=applicable actions (csv or *)
#              remaining lines: name|payload|description
#
# Supported types:
#   .mcp   → checklist; applies 'claude mcp add --scope global' after action
#
# To add a new type: add a handler function _wizard_apply_<type>() and register
# it in the case statement inside tui_apply_wizards().

declare -gA _WIZARD_SELECTIONS=()

tui_run_wizards() {
    local app="$1" action="$2"
    # Reset via unset+declare to avoid coercing the associative array to indexed.
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

    # Read header lines; strip CR so CRLF files work too.
    local title prompt applicable
    { IFS= read -r title; IFS= read -r prompt; IFS= read -r applicable; } < "$page"
    title="${title%$'\r'}"
    prompt="${prompt%$'\r'}"
    applicable="${applicable%$'\r'}"

    # Skip if this action doesn't trigger the page.
    if [[ "$applicable" != "*" ]]; then
        local matched=0 a
        IFS=',' read -ra acts <<< "$applicable"
        for a in "${acts[@]}"; do
            [[ "${a// /}" == "$action" ]] && matched=1 && break
        done
        [[ $matched -eq 0 ]] && return 0
    fi

    # Build whiptail item list; all items start unchecked.
    # Pre-checking current state would require querying the running box (slow),
    # creating a visible delay between action selection and the wizard appearing.
    local -a items=()
    local name payload desc
    while IFS='|' read -r name payload desc; do
        name="${name%$'\r'}"; payload="${payload%$'\r'}"; desc="${desc%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        items+=("$name" "$desc" "OFF")
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
        local match="" f
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
    local name payload should_install s
    while IFS='|' read -r name payload _; do
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
