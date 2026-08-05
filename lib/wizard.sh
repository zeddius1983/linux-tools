# Wizard pages live in apps/<app>/wizard/NN-name.<type>
# File format: line1=title  line2=prompt  line3=applicable actions (csv or *)
#              remaining lines: name|payload|description[|on|off]  (default: off)
#
# Supported types:
#   .mcp      → checklist; applies 'claude mcp add --scope user' after action
#   .packages → checklist; calls '<app-name-without-box>-install --tools ...'
#   .buildarg → radiolist; passes the chosen value to the image build as
#               --build-arg <NAME>=<value> (consumed by cmd_build, no
#               post-action apply step). Body lines are config, not items:
#                 arg|<BUILD_ARG_NAME>
#                 items-cmd|<shell command printing one value per line,
#                            preferred value first — it becomes the default>
#   .runtime  → radiolist; picks a create-time variant (consumed by cmd_create
#               via wizard_create_variant, no post-action apply step). Body lines
#               are items: Label|value|description (first line = default). The
#               Label shows verbatim; the value selects create_flags.<value>
#               (podman --additional-flags) and create_args.<value> (extra
#               distrobox-level flags, e.g. --nvidia).
#
# To add a new type: add a handler function _wizard_apply_<type>() and register
# it in the case statement inside tui_apply_wizards().

declare -A _WIZARD_SELECTIONS=()
_WIZARD_STATE_LOADED=0

# --- Go front-end bridge -----------------------------------------------------
# tools-tui (see tui/) collects every answer up front and writes a flat
# KEY=value state file, then execs this script with LT_WIZARD_STATE pointing at
# it. Rather than teaching each consumer a second code path, the file is
# re-hydrated into _WIZARD_SELECTIONS so everything downstream — the apply
# handlers, wizard_build_args, wizard_create_variant — works unchanged.
#
# Page variables are named PAGE_<sanitised pagename> because a page name like
# "00-statusline" is not a valid shell identifier. The sanitisation is not
# reversible, so the page files are walked and each name re-sanitised the same
# way Go does, rather than trying to decode the variable name.
#
# A missing or unset state file is not an error: it is the normal
# non-interactive path (`tools setup <app>` from a script), which must keep
# taking build defaults exactly as before.
_wizard_var_suffix() {
    local s="$1"
    printf '%s' "${s//[^a-zA-Z0-9]/_}"
}

# Load the state file, refusing to continue when one was promised but cannot be
# read. LT_SKIP_WIZARD says a front-end has already asked every question, so a
# missing or unreadable file is not "no answers" — it is answers that were lost.
# Carrying on would remove and rebuild the app while discarding the build args,
# runtime variant and package selections the user just chose.
wizard_require_state() {
    local app="$1"
    wizard_load_state "$app"
    if [[ -n "${LT_SKIP_WIZARD:-}" && $_WIZARD_STATE_LOADED -ne 1 ]]; then
        echo "Error: LT_SKIP_WIZARD is set but no wizard state could be loaded from" >&2
        echo "       '${LT_WIZARD_STATE:-<unset>}'. Refusing to continue: the run would" >&2
        echo "       silently ignore every selection made in the front-end." >&2
        return 1
    fi
    return 0
}

wizard_load_state() {
    local app="$1"
    [[ -n "${LT_WIZARD_STATE:-}" && -f "${LT_WIZARD_STATE}" ]] || return 0

    # shellcheck disable=SC1090
    source "$LT_WIZARD_STATE"
    _WIZARD_STATE_LOADED=1

    local page fname pagename varname
    for page in "$APPS_DIR/$app/wizard"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] || continue
        fname="${page##*/}"
        pagename="${fname%.*}"
        varname="PAGE_$(_wizard_var_suffix "$pagename")"
        # Tested for being *defined*, not non-empty: an empty PAGE_ value is the
        # "nothing selected" answer, and the apply handlers act on it by removing
        # what is currently installed. Skipping it would silently turn
        # "deselect everything" into "change nothing".
        [[ -n "${!varname+set}" ]] && _WIZARD_SELECTIONS["$pagename"]="${!varname}"
    done
    return 0
}

tui_run_wizards() {
    local app="$1" action="$2"
    # Clear previous selections in-place. Avoid unset+declare-gA inside a function
    # — bash does not reliably re-create the global after unset in all versions.
    local _k
    for _k in "${!_WIZARD_SELECTIONS[@]}"; do unset '_WIZARD_SELECTIONS[$_k]'; done
    local wizard_dir="$APPS_DIR/$app/wizard"
    [[ -d "$wizard_dir" ]] || return 0
    local page
    for page in "$wizard_dir"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] || continue
        _wizard_run_page "$app" "$action" "$page" || return 1
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

    if [[ "$ext" == "buildarg" ]]; then
        _wizard_run_buildarg_page "$page" "$pagename" "$title" "$prompt"
        return $?
    fi

    if [[ "$ext" == "runtime" ]]; then
        _wizard_run_runtime_page "$page" "$pagename" "$title" "$prompt"
        return $?
    fi

    # Build whiptail item list.
    # Optional 4th field sets default state (on/off); omitting defaults to off.
    # For .packages pages, optional 5th field is a detect path: a bare name is
    # checked as ~/.local/bin/<name>; a ~/ prefix expands to $HOME/; multiple
    # paths may be comma-separated (any match → ON). When a detect field is
    # present it is the sole authority — default_state is ignored so that
    # uninstalled tools always appear unchecked.
    local -a items=()
    local name payload desc default_state detect
    while IFS='|' read -r name payload desc default_state detect; do
        name="${name%$'\r'}"; payload="${payload%$'\r'}"
        desc="${desc%$'\r'}"; default_state="${default_state%$'\r'}"
        detect="${detect%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        local state="OFF"
        if [[ "$ext" == "packages" && -n "$detect" ]]; then
            local -a _dpaths=()
            IFS=',' read -ra _dpaths <<< "$detect"
            local _dp
            for _dp in "${_dpaths[@]}"; do
                if [[ "$_dp" == "~/"* ]]; then
                    _dp="${HOME}/${_dp:2}"
                else
                    _dp="${HOME}/.local/bin/${_dp}"
                fi
                if [[ -e "$_dp" ]]; then
                    state="ON"
                    break
                fi
            done
        else
            [[ "${default_state,,}" == "on" ]] && state="ON"
        fi
        items+=("$name" "$desc" "$state")
    done < <(tail -n +4 "$page")

    [[ ${#items[@]} -eq 0 ]] && return 0

    local selected
    selected=$(whiptail --title "linux-tools — $title" \
        --checklist "$prompt  (SPACE = toggle, ENTER = confirm):" \
        20 84 10 "${items[@]}" 3>&1 1>&2 2>&3) || return 1

    _WIZARD_SELECTIONS["$pagename"]="$(tr -d '"' <<< "$selected")"
}

# Single-choice radiolist for .buildarg pages. Items are produced by the
# page's items-cmd at wizard time (first line = default); the selection is
# stored for wizard_build_args to turn into a --build-arg during cmd_build.
_wizard_run_buildarg_page() {
    local page="$1" pagename="$2" title="$3" prompt="$4"
    local arg_name="" items_cmd="" key val
    while IFS='|' read -r key val; do
        key="${key%$'\r'}"; val="${val%$'\r'}"
        case "$key" in
            arg)       arg_name="$val" ;;
            items-cmd) items_cmd="$val" ;;
        esac
    done < <(tail -n +4 "$page")
    [[ -z "$arg_name" || -z "$items_cmd" ]] && return 0

    local -a values=()
    mapfile -t values < <(bash -c "$items_cmd" 2>/dev/null)
    if [[ ${#values[@]} -eq 0 ]]; then
        echo "Warning: wizard page '$pagename': items-cmd produced no items, using build default" >&2
        return 0
    fi

    local -a items=()
    local v state="ON" desc="(default)"
    for v in "${values[@]}"; do
        [[ -z "$v" ]] && continue
        items+=("$v" "$desc" "$state")
        state="OFF"; desc=""
    done

    local selected
    selected=$(whiptail --title "linux-tools — $title" \
        --radiolist "$prompt  (SPACE = select, ENTER = confirm):" \
        20 72 10 "${items[@]}" 3>&1 1>&2 2>&3) || return 1
    [[ -z "$selected" ]] && return 0
    _WIZARD_SELECTIONS["$pagename"]="$selected"
}

# Single-choice radiolist for .runtime pages. Body lines are
# "Label|value|description"; the first line is the default. The visible choice
# is the Label exactly as written (e.g. "AMD (ROCm/Vulkan)"); the hidden value
# is a filename-safe key (e.g. amd/nvidia). whiptail returns the Label, so the
# selection is stored as the Label and translated to its value on demand by
# wizard_create_variant. cmd_create uses that value to pick a
# create_flags.<value> / create_args.<value> variant.
_wizard_run_runtime_page() {
    local page="$1" pagename="$2" title="$3" prompt="$4"
    local -a items=()
    local name value desc state="ON"
    while IFS='|' read -r name value desc; do
        name="${name%$'\r'}"; value="${value%$'\r'}"; desc="${desc%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        items+=("$name" "$desc" "$state")
        state="OFF"
    done < <(tail -n +4 "$page")
    [[ ${#items[@]} -eq 0 ]] && return 0

    local selected
    selected=$(whiptail --title "linux-tools — $title" \
        --radiolist "$prompt  (SPACE = select, ENTER = confirm):" \
        20 84 10 "${items[@]}" 3>&1 1>&2 2>&3) || return 1
    [[ -z "$selected" ]] && return 0
    _WIZARD_SELECTIONS["$pagename"]="$selected"
}

# Print the variant value for this app's .runtime selection (empty if none).
# Translates the stored Label back to its "Label|value|desc" value field.
wizard_create_variant() {
    local app="$1"
    # Go already resolved the label to its value, so no round-trip is needed.
    if [[ $_WIZARD_STATE_LOADED -eq 1 ]]; then
        printf '%s' "${VARIANT:-}"
        return 0
    fi
    declare -p _WIZARD_SELECTIONS &>/dev/null || return 0
    local page fname pagename selected name value _desc
    for page in "$APPS_DIR/$app/wizard"/[0-9][0-9]-*.runtime; do
        [[ -f "$page" ]] || continue
        fname="${page##*/}"; pagename="${fname%.*}"
        selected="${_WIZARD_SELECTIONS[$pagename]:-}"
        [[ -n "$selected" ]] || return 0
        while IFS='|' read -r name value _desc; do
            name="${name%$'\r'}"; value="${value%$'\r'}"
            [[ -z "$name" || "$name" == \#* ]] && continue
            if [[ "$name" == "$selected" ]]; then
                printf '%s' "$value"
                return 0
            fi
        done < <(tail -n +4 "$page")
        return 0
    done
}

# Emit --build-arg tokens (one per line) for this app's .buildarg selections.
# Called by cmd_build; prints nothing when no wizard ran (non-interactive).
wizard_build_args() {
    local app="$1"
    # BUILD_ARGS arrives pre-rendered as "--build-arg NAME=value ..."; split it
    # back into the one-token-per-line form cmd_build reads with mapfile.
    if [[ $_WIZARD_STATE_LOADED -eq 1 ]]; then
        local tok
        for tok in ${BUILD_ARGS:-}; do printf '%s\n' "$tok"; done
        return 0
    fi
    declare -p _WIZARD_SELECTIONS &>/dev/null || return 0
    local wizard_dir="$APPS_DIR/$app/wizard"
    local page
    for page in "$wizard_dir"/[0-9][0-9]-*.buildarg; do
        [[ -f "$page" ]] || continue
        local fname="${page##*/}"
        local pagename="${fname%.*}"
        local selection="${_WIZARD_SELECTIONS[$pagename]:-}"
        [[ -n "$selection" ]] || continue
        local arg_name="" key val
        while IFS='|' read -r key val; do
            [[ "${key%$'\r'}" == "arg" ]] && arg_name="${val%$'\r'}"
        done < <(tail -n +4 "$page")
        [[ -n "$arg_name" ]] || continue
        printf -- '--build-arg\n%s=%s\n' "$arg_name" "$selection"
    done
}

tui_confirm_wizards() {
    local app="$1"
    local wizard_dir="$APPS_DIR/$app/wizard"
    [[ -d "$wizard_dir" ]] || return 0

    local page
    local -a to_install=() to_remove=()
    local any_packages=0

    for page in "$wizard_dir"/[0-9][0-9]-*.packages; do
        [[ -f "$page" ]] || continue
        any_packages=1
        local fname="${page##*/}"
        local pagename="${fname%.*}"
        local selected_str="${_WIZARD_SELECTIONS[$pagename]:-}"
        local -a selected_arr=()
        [[ -n "$selected_str" ]] && read -ra selected_arr <<< "$selected_str"

        local name _payload desc _default detect
        while IFS='|' read -r name _payload desc _default detect; do
            name="${name%$'\r'}"; desc="${desc%$'\r'}"; detect="${detect%$'\r'}"
            [[ -z "$name" || "$name" == \#* ]] && continue

            local installed=0
            if [[ -n "$detect" ]]; then
                local -a dpaths=()
                IFS=',' read -ra dpaths <<< "$detect"
                local dp
                for dp in "${dpaths[@]}"; do
                    if [[ "$dp" == "~/"* ]]; then
                        dp="${HOME}/${dp:2}"
                    else
                        dp="${HOME}/.local/bin/${dp}"
                    fi
                    [[ -e "$dp" ]] && { installed=1; break; }
                done
            fi

            local is_selected=0
            local s
            for s in "${selected_arr[@]+"${selected_arr[@]}"}"; do
                [[ "$s" == "$name" ]] && is_selected=1 && break
            done

            if [[ $is_selected -eq 1 && $installed -eq 0 ]]; then
                to_install+=("$name — $desc")
            elif [[ $is_selected -eq 0 && $installed -eq 1 ]]; then
                to_remove+=("$name — $desc")
            fi
        done < <(tail -n +4 "$page")
    done

    [[ $any_packages -eq 0 ]] && return 0
    [[ ${#to_install[@]} -eq 0 && ${#to_remove[@]} -eq 0 ]] && return 0

    local msg=""
    if [[ ${#to_install[@]} -gt 0 ]]; then
        msg+="Installing:\n"
        local item
        for item in "${to_install[@]}"; do msg+="  + $item\n"; done
    fi
    if [[ ${#to_remove[@]} -gt 0 ]]; then
        [[ -n "$msg" ]] && msg+="\n"
        msg+="Removing:\n"
        local item
        for item in "${to_remove[@]}"; do msg+="  - $item\n"; done
    fi

    local total=$(( ${#to_install[@]} + ${#to_remove[@]} ))
    local height=$(( total + 10 ))
    [[ ${#to_install[@]} -gt 0 ]] && height=$(( height + 1 ))
    [[ ${#to_remove[@]} -gt 0 ]] && height=$(( height + 1 ))
    [[ $height -lt 12 ]] && height=12
    [[ $height -gt 24 ]] && height=24

    whiptail --title "linux-tools — $app: confirm changes" \
        --yesno "$(printf '%b' "$msg")\nProceed?" \
        "$height" 72 || return 1
}

tui_apply_wizards() {
    local app="$1" action="$2"
    # Guard against _WIZARD_SELECTIONS being unset (e.g. tui_run_wizards not called).
    declare -p _WIZARD_SELECTIONS &>/dev/null || return 0
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
            mcp)      _wizard_apply_mcp      "$app" "$match" "${_WIZARD_SELECTIONS[$pagename]}" ;;
            packages) _wizard_apply_packages "$app" "$match" "${_WIZARD_SELECTIONS[$pagename]}" ;;
            buildarg) : ;;  # consumed by cmd_build via wizard_build_args
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
            if ! distrobox enter "$box" -- \
                    claude mcp add --transport stdio --scope user "$name" -- npx -y "$payload"; then
                echo "Warning: failed to configure MCP server '$name'" >&2
            fi
        else
            echo "==> Skipping MCP server: $name"
            distrobox enter "$box" -- \
                claude mcp remove --scope user "$name" 2>/dev/null || true
        fi
    done < <(tail -n +4 "$page")
}

_wizard_apply_packages() {
    local app="$1" page="$2" selected_str="${3:-}"
    local -a selected_arr=()
    [[ -n "$selected_str" ]] && read -ra selected_arr <<< "$selected_str"
    local box tools_str="" installer
    box="$(box_name "$app")"
    installer="${app%-box}-install"
    for s in "${selected_arr[@]+"${selected_arr[@]}"}"; do tools_str+=" $s"; done
    tools_str="${tools_str# }"
    echo "==> Applying selected packages for '$app'..."
    distrobox enter "$box" -- "$installer" --tools "$tools_str"
}
