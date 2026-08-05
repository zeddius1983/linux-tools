#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"

# ── Runtime detection ────────────────────────────────────────────────────────

if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "Error: neither podman nor docker found" >&2; exit 1
fi

# ── Libraries ────────────────────────────────────────────────────────────────

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/commands.sh"
source "$SCRIPT_DIR/lib/wizard.sh"
source "$SCRIPT_DIR/lib/tui.sh"

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    local apps
    apps="$(list_apps | tr '\n' ' ')"
    cat <<EOF
Usage: $0 [command] [app]

  (no args)        Launch interactive TUI manager

Commands:
  install          Symlink as 'tools' in ~/.local/bin + set up completion
  build-tui        Build the Go dashboard binary (host Go, else a container)
  setup  <app>     Install app (removes existing box+image first)
  build  <app>     Build container image only
  create <app>     Create distrobox from built image
  export <app>     Export apps/bins to host menu
  enter  <app>     Open shell inside box
  rm     <app>     Remove distrobox (image is kept)
  list             Show status of all apps

Available apps: ${apps:-none}
EOF
}

# ── Entrypoint ───────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    interactive
    exit 0
fi

command_="$1"

case "$command_" in
    list)      cmd_list;      exit 0 ;;
    install)   cmd_install;   exit 0 ;;
    build-tui) cmd_build_tui; exit 0 ;;
esac

[[ $# -ge 2 ]] || { usage; exit 1; }
app="$2"

case "$command_" in
    setup)
        # Collect wizard selections up front (interactive only) so .buildarg
        # pages can influence the image build; other page types are applied
        # after setup as before.
        wizard_active=0
        # LT_SKIP_WIZARD is set by the Go front-end, which has already asked
        # everything and left its answers in LT_WIZARD_STATE.
        if [[ -n "${LT_SKIP_WIZARD:-}" ]]; then
            wizard_require_state "$app" || exit 1
            wizard_active=1
        elif [[ -t 0 ]] && command -v whiptail &>/dev/null \
                       && [[ -d "$APPS_DIR/$app/wizard" ]]; then
            wizard_active=1
            setup_tui_theme
            tui_run_wizards "$app" "setup" || exit 0
            tui_confirm_wizards "$app" || exit 0
        fi
        cmd_setup "$app"
        if [[ $wizard_active -eq 1 ]]; then
            tui_apply_wizards "$app" "setup"
        fi
        cmd_setup_finish "$app"
        ;;
    # These are no-ops unless LT_WIZARD_STATE points at a real file, so they
    # stay safe for plain scripted invocations — but a front-end that promised
    # state via LT_SKIP_WIZARD and lost it is an error, not a default build.
    build)  wizard_require_state "$app" || exit 1; cmd_build  "$app" ;;
    create) wizard_require_state "$app" || exit 1; cmd_create "$app" ;;
    export) cmd_export "$app" ;;
    enter)  cmd_enter  "$app" ;;
    rm)     cmd_rm     "$app" ;;
    *)      usage; exit 1 ;;
esac
