#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"

# ── Runtime detection ────────────────────────────────────────────────────────

# Left empty when neither is present: `install`, `version` and `update` work
# fine without a container runtime, and require_runtime fails the ones that do
# not with a message naming what to install.
if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    RUNTIME=""
fi

# ── Libraries ────────────────────────────────────────────────────────────────

source "$SCRIPT_DIR/lib/release.sh"
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/commands.sh"
source "$SCRIPT_DIR/lib/wizard.sh"

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    local apps
    apps="$(list_apps | tr '\n' ' ')"
    cat <<EOF
Usage: $0 [command] [app] [KEY=value ...]

  (no args)        Launch the dashboard

Commands:
  install          Symlink as 'tools' in ~/.local/bin + set up completion
                     --dev            take the command over from a release install
                     --no-modify-rc   do not touch ~/.bashrc or the zsh fragment
  update           Update this installation in place
                     --version <tag>  install that release instead of the latest
                                      (this is also how you roll back)
                     --check          report installed vs latest, change nothing
  version          Print the installed version and where it came from
  build-tui        Build the Go dashboard binary (host Go, else a container)
  setup  <app>     Install app (removes existing box+image first)
  build  <app>     Build container image only
  create <app>     Create distrobox from built image
  export <app>     Export apps/bins to host menu
  enter  <app>     Open shell inside box
  rm     <app>     Remove distrobox (image is kept)
  list             Show status of all apps
  help   <app>     Show an app's parameters

setup, build and create take an app's parameters as KEY=value, e.g.
  tools setup comfyui COMFY_GPU=nvidia COMFY_REF=v0.3.39
A parameter left out takes its default; 'tools help <app>' lists them.

Available apps: ${apps:-none}
EOF
}

# ── Entrypoint ───────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    require_runtime
    cmd_menu
    exit 0
fi

command_="$1"
shift

case "$command_" in
    list)              require_runtime; cmd_list;      exit 0 ;;
    install)           cmd_install "$@";               exit 0 ;;
    update)            cmd_update  "$@";               exit 0 ;;
    version|--version) cmd_version;                    exit 0 ;;
    build-tui)         cmd_build_tui;                  exit 0 ;;
    -h|--help|help)
        if [[ $# -ge 1 ]]; then
            require_app "$1"
            wizard_help "$1"
        else
            usage
        fi
        exit 0 ;;
esac

[[ $# -ge 1 ]] || { usage; exit 1; }
app="$1"
shift
require_app "$app"
require_runtime

# Answers to the app's wizard pages come from exactly one place: the
# dashboard's state file (LT_SKIP_WIZARD, set by tui/ once it has asked
# everything) or KEY=value arguments. With neither, every page takes its
# default, which is the plain scripted `tools setup <app>`.
load_answers() {  # load_answers <action> [KEY=value...]
    if [[ -n "${LT_SKIP_WIZARD:-}" ]]; then
        if [[ $# -gt 1 ]]; then
            echo "Error: KEY=value parameters cannot be combined with LT_SKIP_WIZARD." >&2
            exit 1
        fi
        wizard_require_state "$app" || exit 1
    elif [[ $# -gt 1 ]]; then
        wizard_from_args "$app" "$@" || exit 1
    else
        # No-op unless LT_WIZARD_STATE names a file, as it has always been.
        wizard_load_state "$app"
    fi
}

no_params() {
    if [[ $# -gt 0 ]]; then
        echo "Error: '$command_' takes no parameters (got: $*)." >&2
        exit 1
    fi
}

case "$command_" in
    setup)
        load_answers setup "$@"
        cmd_setup "$app"
        wizard_apply "$app"
        cmd_setup_finish "$app"
        ;;
    build)  load_answers build  "$@"; cmd_build  "$app" ;;
    create) load_answers create "$@"; cmd_create "$app" ;;
    export) no_params "$@"; cmd_export "$app" ;;
    enter)  no_params "$@"; cmd_enter  "$app" ;;
    rm)     no_params "$@"; cmd_rm     "$app" ;;
    *)      usage; exit 1 ;;
esac
