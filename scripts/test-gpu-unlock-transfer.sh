#!/usr/bin/env bash
# Container-side transfer and objtool checks; no sudo, host changes, or GPU.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/apps/gpu-unlock/common.sh"
source "$root/apps/gpu-unlock/host-bootstrap"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$work/share" "$work/transfers" "$work/check"
# Read by run_host_helper from the sourced common.sh.
# shellcheck disable=SC2034
GPU_UNLOCK_SHARE="$work/share"
printf 'printf "original status\\n"\n' > "$work/share/gpu-unlock-host"
cp "$root/apps/gpu-unlock/host-bootstrap" "$work/share/host-bootstrap"
export XDG_DATA_HOME="$work/data"
distrobox-host-exec() {
    if [[ "$1" == sudo ]]; then
        [[ "$2" == /bin/bash && "$3" == -c && "$5" == gpu_unlock ]] || return 1
        # Simulate changing the archive while sudo waits for a password.
        if [[ "${TAMPER:-0}" == 1 ]]; then printf tamper >> "$6"; fi
        snapshot_bundle "$6" "$7" "$work/check"
    else
        # Status receives code as an argument, not a replaceable script path.
        printf 'echo replaced\n' > "$work/share/gpu-unlock-host"
        "$@"
    fi
}
run_host_helper on all
[[ -f "$work/check/tree/gpu-unlock-host" ]] || fail 'helper missing from transfer'
[[ -z "$(find "$XDG_DATA_HOME/gpu-unlock/transfers" -mindepth 1 -print -quit)" ]] || fail 'transfer was not cleaned up'
rm -rf "$work/check"
mkdir "$work/check"
if TAMPER=1 run_host_helper on all > "$work/output" 2> "$work/error"; then fail 'changed archive accepted'; fi
[[ -z "$(find "$XDG_DATA_HOME/gpu-unlock/transfers" -mindepth 1 -print -quit)" ]] || fail 'failed transfer was not cleaned up'
run_host_helper status > "$work/output"
grep -qx 'original status' "$work/output" || fail 'status ran a replaced helper'

# Debian/Ubuntu multiarch libraries are searched; an unresolved library fails
# here, before a confusing kernel build error.
mkdir -p "$work/host/usr/lib/x86_64-linux-gnu"
printf lib > "$work/host/usr/lib/x86_64-linux-gnu/libtest.so.1"
printf '#!/bin/sh\n' > "$work/objtool"
chmod +x "$work/objtool"
ldd() { printf 'libtest.so.1 => not found\n'; }
stage_objtool_libraries "$work/objtool" "$work/host" "$work/libs"
[[ -f "$work/libs/libtest.so.1" ]] || fail 'multiarch library not staged'
rm "$work/host/usr/lib/x86_64-linux-gnu/libtest.so.1"
if stage_objtool_libraries "$work/objtool" "$work/host" "$work/libs2" > "$work/output" 2> "$work/error"; then fail 'missing library silently skipped'; fi
grep -q 'host objtool requires libtest.so.1' "$work/error" || fail 'missing actionable objtool error'
echo 'gpu-unlock transfer/objtool tests passed'
