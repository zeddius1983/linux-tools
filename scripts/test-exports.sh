#!/usr/bin/env bash
# Export lookup must preserve Distrobox errors and stop setup on failure.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/commands.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
APPS_DIR="$work/apps"
mkdir -p "$APPS_DIR/test"
printf 'bin:test-command\n' > "$APPS_DIR/test/exports"
fail() { echo "FAIL: $*" >&2; exit 1; }

distrobox() {
    echo 'pacman: conflicting files in container initialization' >&2
    return 23
}
pick_terminal() { fail 'must not reach desktop/export operations after failed initialization'; }
if cmd_export test > "$work/output" 2> "$work/error"; then
    fail 'failed initialization reported success'
fi
grep -q 'conflicting files' "$work/error" || fail 'initialization error was hidden'
grep -q 'failed to initialize' "$work/error" || fail 'missing initialization diagnostic'
if grep -q 'Exporting binary' "$work/output"; then fail 'export continued after initialization failure'; fi

# Match tools.sh's setup/finish sequence: a real cmd_export failure must abort
# before the success banner, even though build/create themselves succeeded.
if bash -c '
    set -euo pipefail
    SCRIPT_DIR="$1"; APPS_DIR="$2"
    source "$SCRIPT_DIR/lib/helpers.sh"
    source "$SCRIPT_DIR/lib/commands.sh"
    box_exists() { return 1; }
    image_exists() { return 1; }
    cmd_build() { :; }
    cmd_create() { :; }
    distrobox() { echo "initialization failed" >&2; return 23; }
    cmd_setup test
    cmd_setup_finish test
' _ "$SCRIPT_DIR" "$APPS_DIR" > "$work/output" 2> "$work/error"; then
    fail 'setup swallowed initialization/export failure'
fi
if grep -q 'Done\.' "$work/output"; then fail 'setup printed a success banner after failure'; fi

if resolve_export_bin test-box test-command > "$work/output" 2> "$work/error"; then
    fail 'failed lookup reported success'
fi
grep -q 'conflicting files' "$work/error" || fail 'lookup error was hidden'
grep -q 'binary lookup failed' "$work/error" || fail 'missing lookup diagnostic'

distrobox() { return 0; }
if resolve_export_bin test-box absent-command > "$work/output" 2> "$work/error"; then
    fail 'empty lookup result reported success'
fi
grep -q "cannot find 'absent-command'" "$work/error" || fail 'missing absent-command diagnostic'

distrobox() {
    [[ "$*" == "enter test-box -- bash -c command -pv 'test-command'" ]] || return 1
    printf 'startup notice\n/usr/bin/test-command\n'
    echo 'visible stderr notice' >&2
}
resolve_export_bin test-box test-command > "$work/output" 2> "$work/error"
grep -qx '/usr/bin/test-command' "$work/output" || fail 'wrong resolved binary path'
grep -q 'visible stderr notice' "$work/error" || fail 'successful lookup suppressed stderr'

echo 'export initialization/lookup tests passed'
