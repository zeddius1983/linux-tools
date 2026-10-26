# shellcheck shell=bash
# Shared container-side host handoff. No executable is staged in shared home.
GPU_UNLOCK_SHARE=/usr/share/gpu-unlock

run_host_helper() (
    set -euo pipefail
    local action="$1"; shift
    if [[ "$action" == status || "$action" == preflight ]]; then
        # Read-only checks need no sudo. Pass an immutable code argument rather
        # than executing a path that another process can replace.
        distrobox-host-exec /bin/bash -c "$(cat "$GPU_UNLOCK_SHARE/gpu-unlock-host")" gpu_unlock "$action" "$@"
        return
    fi
    local bundle digest bootstrap stage transfers
    transfers="${XDG_DATA_HOME:-$HOME/.local/share}/gpu-unlock/transfers"
    mkdir -p "$transfers"
    stage="$(mktemp -d "$transfers/transfer.XXXXXXXX")"
    trap 'rm -rf -- "$stage"' EXIT
    bundle="$stage/bundle.tar"
    tar -cf "$bundle" -C "$GPU_UNLOCK_SHARE" gpu-unlock-host
    if [[ "$action" == install ]]; then
        local kernel="$1" work="$2" backend="$3"
        # Bundle code and artifacts together. The digest is fixed before sudo
        # waits for authentication; replacement during that wait is rejected.
        tar -rf "$bundle" -C "$work" module/gpu_unlock.ko payload boot
        set -- "$kernel" "$backend"
    fi
    digest="$(sha256sum "$bundle")"; digest="${digest%% *}"
    bootstrap="$(cat "$GPU_UNLOCK_SHARE/host-bootstrap")"
    distrobox-host-exec sudo /bin/bash -c "$bootstrap" gpu_unlock "$bundle" "$digest" "$action" "$@"
)

stage_objtool_libraries() {
    local objtool="$1" host_root="$2" destination="$3" missing lib directory found
    [[ -x "$objtool" ]] || return 0
    missing="$(ldd "$objtool" 2>/dev/null | awk '/not found/ {print $1}' || true)"
    [[ -n "$missing" ]] || return 0
    mkdir -p "$destination"
    for lib in $missing; do
        found=0
        for directory in usr/lib/x86_64-linux-gnu lib/x86_64-linux-gnu usr/lib usr/lib64 lib lib64; do
            if [[ -f "$host_root/$directory/$lib" ]]; then
                cp -L -- "$host_root/$directory/$lib" "$destination/$lib"
                found=1
                break
            fi
        done
        if (( ! found )); then
            echo "ERROR: host objtool requires $lib, but it was not found in the host library directories under $host_root." >&2
            return 1
        fi
    done
    export LD_LIBRARY_PATH="$destination${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}
