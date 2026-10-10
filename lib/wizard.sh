# shellcheck shell=bash
# Wizard pages live in apps/<app>/wizard/NN-name.<type>. Each page is one
# question an action takes an answer to. Nothing in this file asks a question:
# the answers come from one of two front-ends.
#
#   - The dashboard (tui/) asks the pages natively and hands the answers over in
#     a state file (LT_SKIP_WIZARD + LT_WIZARD_STATE, see wizard_load_state).
#   - The command line takes them as KEY=value arguments, one per page:
#         tools setup comfyui COMFY_GPU=amd COMFY_REF=v0.3.39
#     wizard_from_args turns those into the same answers a state file carries,
#     and `tools help <app>` (wizard_help) lists an app's parameters.
#
# A page given no answer takes its build default, so a plain `tools setup <app>`
# behaves exactly as a scripted install always has.
#
# File format: line1=title  line2=prompt  line3=applicable actions (csv or *)
#              remaining lines: name|payload|description[|on|off]  (default: off)
#
# Every page has a parameter name, its KEY on the command line: the page's arg|
# name when it has one, otherwise an explicit
#   param|<NAME>
# line, which scripts/lint-apps.sh requires on any page without arg|. "arg" and
# "param" are reserved line keys and cannot be item names.
#
# Supported types:
#   .mcp      → checklist; applies 'claude mcp add --scope user' after action
#   .packages → checklist; calls '<app-name-without-box>-install --tools ...'
#               On the command line both take KEY=item1,item2 (item names, the
#               first field of each line); KEY=none clears every item, and
#               leaving KEY out changes nothing. Optional 4th field: default
#               on/off. Optional 5th field (.packages): detect paths, which the
#               dashboard uses to pre-tick what is already installed.
#   .buildarg → single choice; passes the chosen value to the image build as
#               --build-arg <NAME>=<value> (consumed by cmd_build, no
#               post-action apply step). Body lines are config, not items:
#                 arg|<BUILD_ARG_NAME>
#                 items-cmd|<shell command printing one value per line,
#                            preferred value first — it becomes the default>
#               Instead of items-cmd, a page may name a GitHub repo:
#                 releases|<owner>/<repo>[|<count>]   (default count: 10)
#               which lists that repo's release tags, newest first. The
#               dashboard shows each one's notes beside the list. Optional:
#                 extra|<value>       literal choice appended after the tags
#                                     (e.g. a branch name like "master")
#                 notes-repo|<owner>/<repo>[|<tag-template>[|<count>]]
#                                     notes for an items-cmd list, matched by
#                                     tag; "%s" in the template is the item
#                                     value (e.g. "rust-v%s"). Dashboard-only.
#                 alias|<item>|<tag-template>
#                                     an item that names no tag but the newest
#                                     tag of that shape, for its notes:
#                                     "alias|nightly|b%s". "latest" is one
#                                     implicitly, within notes-repo's template.
#                                     Dashboard-only.
#               Two .buildarg pages with the same arg| are alternative views of
#               one step, not two questions: the dashboard shows them as one tab
#               and [/] switches between them, the view showing being the
#               answer (llama-cpp's Release and Build lists). On the command
#               line they are one parameter that takes a value from either list.
#               The value is not checked against the list (it is fetched over
#               the network); a wrong one fails the build.
#   .runtime  → single choice; picks a create-time variant (consumed by
#               cmd_create via wizard_create_variant, no post-action apply
#               step). Body lines are items: Label|value|description (first
#               line = default). The dashboard shows the Label; the command line
#               takes the value, which selects create_flags.<value> (podman
#               --additional-flags) and create_args.<value> (extra
#               distrobox-level flags, e.g. --nvidia).
#               An optional config line
#                 arg|<BUILD_ARG_NAME>
#               additionally passes the chosen *value* to the image build as
#               --build-arg <NAME>=<value>, so a single question can drive both
#               the base image and the GPU passthrough (see apps/comfyui).
#
# To add a new type: add a handler function _wizard_apply_<type>() and register
# it in the case statement inside wizard_apply().

declare -A _WIZARD_SELECTIONS=()
_WIZARD_STATE_LOADED=0
BUILD_ARGS=""
VARIANT=""

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

# --- Page helpers ------------------------------------------------------------

# The value of a page's first "<key>|value" body line, up to the next '|'.
_wizard_page_key() {  # _wizard_page_key <page> <key>
    local page="$1" want="$2" key val
    while IFS='|' read -r key val; do
        key="${key%$'\r'}"; val="${val%$'\r'}"
        if [[ "$key" == "$want" ]]; then
            printf '%s' "${val%%|*}"
            return 0
        fi
    done < <(tail -n +4 "$page")
}

# The page's command-line KEY: param| when present, else arg|.
_wizard_page_param() {
    local p
    p="$(_wizard_page_key "$1" param)"
    [[ -n "$p" ]] || p="$(_wizard_page_key "$1" arg)"
    printf '%s' "$p"
}

_wizard_page_actions() {
    sed -n 3p "$1" | tr -d '\r '
}

_wizard_page_applies() {  # _wizard_page_applies <page> <action>
    local applicable a
    local -a acts=()
    applicable="$(_wizard_page_actions "$1")"
    [[ "$applicable" == "*" ]] && return 0
    IFS=',' read -ra acts <<< "$applicable"
    for a in "${acts[@]}"; do
        [[ "$a" == "$2" ]] && return 0
    done
    return 1
}

# Item lines of a checklist or .runtime page: blanks, comments and the reserved
# config keys left out.
_wizard_items() {
    local line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        case "${line%%|*}" in arg|param) continue ;; esac
        printf '%s\n' "$line"
    done < <(tail -n +4 "$1")
}

_wizard_runtime_values() {
    local _label value _desc
    while IFS='|' read -r _label value _desc; do
        printf '%s\n' "$value"
    done < <(_wizard_items "$1")
}

_wizard_has_pages() {
    local page
    for page in "$APPS_DIR/$1/wizard"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] && return 0
    done
    return 1
}

# --- Command-line parameters ----------------------------------------------------

# A checklist value, "a,b,c" or "none", as the space-separated item names the
# apply handlers take. Unknown names are an error rather than ignored: a typo
# would otherwise uninstall the item it was meant to keep.
_wizard_checklist_value() {  # _wizard_checklist_value <page> <param> <value>
    local page="$1" param="$2" value="$3" v out=""
    local -a names=() wanted=()
    mapfile -t names < <(_wizard_items "$page" | cut -d'|' -f1)
    [[ "$value" == none ]] && value=""
    IFS=',' read -ra wanted <<< "$value"
    for v in "${wanted[@]+"${wanted[@]}"}"; do
        v="${v//[[:space:]]/}"
        [[ -z "$v" ]] && continue
        if ! printf '%s\n' "${names[@]}" | grep -qxF -- "$v"; then
            echo "Error: $param: unknown item '$v'. Choose from: ${names[*]} (or none)." >&2
            return 1
        fi
        out+=" $v"
    done
    printf '%s' "${out# }"
}

# Turn KEY=value arguments into the answers a dashboard state file carries —
# BUILD_ARGS, VARIANT and _WIZARD_SELECTIONS — and mark them loaded, so every
# consumer downstream reads them exactly as it reads the dashboard's.
wizard_from_args() {  # wizard_from_args <app> <action> [KEY=value...]
    local app="$1" action="$2"; shift 2
    local -A given=() used=()
    local kv key
    for kv in "$@"; do
        key="${kv%%=*}"
        if [[ "$kv" != *=* || ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "Error: '$kv' is not a KEY=value parameter. See: tools help $app" >&2
            return 1
        fi
        if [[ -n "${given[$key]+set}" ]]; then
            echo "Error: $key is given twice." >&2
            return 1
        fi
        given[$key]="${kv#*=}"
    done
    (( ${#given[@]} )) || return 0

    BUILD_ARGS="" VARIANT=""
    local page fname pagename param value arg sel
    for page in "$APPS_DIR/$app/wizard"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] || continue
        param="$(_wizard_page_param "$page")"
        [[ -n "$param" && -n "${given[$param]+set}" ]] || continue
        # Pages sharing a parameter are views of one step (llama-cpp's Release
        # and Build lists); the first one carries the answer.
        [[ -n "${used[$param]:-}" ]] && continue
        used[$param]=1
        if ! _wizard_page_applies "$page" "$action"; then
            echo "Error: $param does not apply to '$action' (only to: $(_wizard_page_actions "$page"))." >&2
            return 1
        fi
        value="${given[$param]}"
        fname="${page##*/}"; pagename="${fname%.*}"
        case "${fname##*.}" in
            buildarg)
                # BUILD_ARGS is split on whitespace downstream, as the
                # dashboard's is, so a value cannot carry any.
                if [[ -z "$value" || "$value" =~ [[:space:]] ]]; then
                    echo "Error: $param needs a single value with no spaces (or leave it out for the default)." >&2
                    return 1
                fi
                BUILD_ARGS+=" --build-arg $(_wizard_page_key "$page" arg)=$value"
                ;;
            runtime)
                if ! _wizard_runtime_values "$page" | grep -qxF -- "$value"; then
                    echo "Error: $param=$value is not one of: $(_wizard_runtime_values "$page" | paste -sd' ')." >&2
                    return 1
                fi
                VARIANT="$value"
                arg="$(_wizard_page_key "$page" arg)"
                [[ -n "$arg" ]] && BUILD_ARGS+=" --build-arg $arg=$value"
                ;;
            packages|mcp)
                sel="$(_wizard_checklist_value "$page" "$param" "$value")" || return 1
                _WIZARD_SELECTIONS["$pagename"]="$sel"
                ;;
        esac
    done

    for key in "${!given[@]}"; do
        if [[ -z "${used[$key]:-}" ]]; then
            echo "Error: '$app' has no parameter '$key'. See: tools help $app" >&2
            return 1
        fi
    done
    BUILD_ARGS="${BUILD_ARGS# }"
    _WIZARD_STATE_LOADED=1
}

# The values a .buildarg page offers, as the dashboard would list them. Network
# backed (items-cmd, or the releases| repo), so it is only used by `tools help`,
# never to validate an argument; failures just leave the list empty.
_wizard_buildarg_values() {
    local page="$1" items_cmd rel_val rel_repo rel_count
    items_cmd="$(sed -n 's/^items-cmd|//p' "$page" | tr -d '\r' | head -1)"
    rel_val="$(sed -n 's/^releases|//p' "$page" | tr -d '\r' | head -1)"
    if [[ -n "$items_cmd" ]]; then
        timeout 20 bash -c "$items_cmd" 2>/dev/null
    elif [[ -n "$rel_val" ]]; then
        rel_repo="${rel_val%%|*}"
        [[ "$rel_val" == *"|"* ]] && rel_count="${rel_val#*|}"
        github_curl --max-time 20 \
            "https://api.github.com/repos/${rel_repo}/releases?per_page=${rel_count:-10}" 2>/dev/null \
            | grep -o '"tag_name": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/'
    fi
    sed -n 's/^extra|//p' "$page" | tr -d '\r' | cut -d'|' -f1
}

# The build default for an arg: its ARG line in the app's Dockerfile(s).
_wizard_arg_default() {  # _wizard_arg_default <app> <ARG>
    grep -hoE "^ARG $2=[^[:space:]]+" "$APPS_DIR/$1"/Dockerfile* 2>/dev/null \
        | head -1 | cut -d= -f2-
}

# `tools help <app>`: the app's parameters, their choices and defaults.
wizard_help() {
    local app="$1"
    if ! _wizard_has_pages "$app"; then
        echo "Usage: tools setup $app"
        echo
        echo "'$app' takes no parameters."
        return 0
    fi
    echo "Usage: tools setup $app [KEY=value ...]"
    echo
    echo "Every parameter is optional; a parameter left out takes its default."
    local -A shown=()
    local page fname param title name value label desc default first
    local -a vals=()
    for page in "$APPS_DIR/$app/wizard"/[0-9][0-9]-*.*; do
        [[ -f "$page" ]] || continue
        fname="${page##*/}"
        param="$(_wizard_page_param "$page")"
        [[ -n "$param" ]] || continue
        title="$(sed -n 1p "$page" | tr -d '\r')"
        if [[ -z "${shown[$param]:-}" ]]; then
            shown[$param]=1
            echo
            echo "  $param    $title  (for: $(_wizard_page_actions "$page"))"
        else
            echo "      ...or $title:"
        fi
        case "${fname##*.}" in
            runtime)
                first=1
                while IFS='|' read -r label value desc; do
                    default=""; (( first )) && default="  (default)"
                    printf '      %-10s %s%s\n' "$value" "$label" "$default"
                    first=0
                done < <(_wizard_items "$page")
                ;;
            buildarg)
                mapfile -t vals < <(_wizard_buildarg_values "$page")
                if ((${#vals[@]})); then
                    printf '      %s\n' "$(printf '%s ' "${vals[@]}")"
                else
                    echo "      (could not fetch the list of values)"
                fi
                default="$(_wizard_arg_default "$app" "$(_wizard_page_key "$page" arg)")"
                [[ -n "$default" && -z "${shown[$param.default]:-}" ]] && \
                    echo "      default: $default"
                shown[$param.default]=1
                ;;
            packages|mcp)
                while IFS='|' read -r name _ desc _ _; do
                    printf '      %-24s %s\n' "$name" "$desc"
                done < <(_wizard_items "$page")
                echo "      comma-separated, or none; left out, nothing changes"
                ;;
        esac
    done
}

# --- Answers for the backend ------------------------------------------------
# Both front-ends end in the same globals, so these read only those.

# The .runtime value chosen for this run, or nothing for the plain create_flags.
wizard_create_variant() {
    [[ $_WIZARD_STATE_LOADED -eq 1 ]] && printf '%s' "${VARIANT:-}"
    return 0
}

# --build-arg tokens, one per line, for cmd_build's mapfile. BUILD_ARGS arrives
# as "--build-arg NAME=value ..."; values never contain whitespace.
wizard_build_args() {
    [[ $_WIZARD_STATE_LOADED -eq 1 ]] || return 0
    local tok
    for tok in ${BUILD_ARGS:-}; do printf '%s\n' "$tok"; done
}

wizard_apply() {
    local app="$1"
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
    done < <(_wizard_items "$page")
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
