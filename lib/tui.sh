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

app_status_detail() {
    local app="$1"
    local desc img_id img_ref box_str
    desc="$(app_description "$app")"
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
    printf '%-22s  |  %-7s  |  %-32s  |  %s' "$desc" "$img_id" "$img_ref" "$box_str"
}

interactive() {
    setup_tui_theme
    command -v whiptail &>/dev/null || {
        echo "Error: whiptail not found. Install with: sudo apt install whiptail" >&2; exit 1
    }

    local -a apps=()
    mapfile -t apps < <(list_apps)

    if [[ ${#apps[@]} -eq 0 ]]; then
        whiptail --title "linux-tools" --msgbox "No apps found in $APPS_DIR" 8 50
        exit 0
    fi

    # Build menu: detail line as tag (what's displayed), app name as lookup value.
    # --menu with empty item shows only the tag, giving a clean single-column list.
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
