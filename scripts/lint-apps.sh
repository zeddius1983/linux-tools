#!/usr/bin/env bash
#
# Check every apps/<name>/ against the contract in CLAUDE.md.
#
# This is a ratchet, not a gate: rules that the tree does not fully satisfy yet
# carry an explicit list of the apps that predate them (LEGACY_* below). A new
# violation fails; an existing one is visible, counted, and can only shrink.
# Deleting a name from a legacy list is the whole of "fixing" it once the app
# complies — and an app that complies while still listed is reported too, so the
# lists cannot quietly rot.
#
# Usage: scripts/lint-apps.sh [--strict] [app...]
#   --strict   treat the grandfathered violations as failures too

set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
APPS_DIR="$ROOT/apps"

# Apps that predate the "every app has a README" rule (CLAUDE.md, "Adding a new
# app"). The dashboard renders README.md in its info panel, so each of these is
# an empty panel for that app.
LEGACY_NO_README=(
    amdgpu_top
    antigravity
    chrome
    copilot-cli
    opencode
    telegram
)

# Apps whose Dockerfile still has an unqualified FROM. Podman has no
# unqualified-search registries configured, so these depend on the host having
# one set up (CLAUDE.md, "Known pitfalls").
LEGACY_UNQUALIFIED_FROM=(
    antigravity
    chrome
    claude-code
    copilot-cli
    telegram
)

# The TUI description column is 26 characters wide in the whiptail fallback.
MAX_DESCRIPTION=26

STRICT=0
declare -a ONLY=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) ONLY+=("$1"); shift ;;
    esac
done

errors=0
legacy=0
stale=0

fail()   { printf 'error: %s: %s\n'  "$1" "$2" >&2; ((errors++)); }
excuse() { printf 'legacy: %s: %s\n' "$1" "$2";     ((legacy++)); }
note()   { printf 'stale:  %s: %s\n' "$1" "$2";     ((stale++)); }

in_list() {  # in_list <needle> <list...>
    local needle="$1"; shift
    local item
    for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
    return 1
}

# A rule with a grandfather list: fail unless the app is listed (or --strict).
graduated() {  # graduated <app> <message> <list...>
    local app="$1" msg="$2"; shift 2
    if in_list "$app" "$@" && ((! STRICT)); then
        excuse "$app" "$msg"
    else
        fail "$app" "$msg"
    fi
}

# Host-only installers (host-only marker + install.sh + no Dockerfile) run
# straight on the host, so image and export rules do not apply to them.
is_hostonly_installer() {
    local d="$APPS_DIR/$1"
    [[ -f "$d/host-only" && -f "$d/install.sh" \
       && ! -f "$d/Dockerfile" && ! -f "$d/Dockerfile.arch" && ! -f "$d/Dockerfile.ubuntu" ]]
}

check_app() {
    local app="$1" d="$APPS_DIR/$app"
    local hostonly=0
    is_hostonly_installer "$app" && hostonly=1

    # ── Image definition ────────────────────────────────────────────────────
    if ((! hostonly)); then
        if [[ -f "$d/Dockerfile" ]]; then
            :
        elif [[ -f "$d/Dockerfile.ubuntu" && -f "$d/Dockerfile.arch" ]]; then
            :
        elif [[ -f "$d/Dockerfile.ubuntu" || -f "$d/Dockerfile.arch" ]]; then
            fail "$app" "has only one of Dockerfile.ubuntu / Dockerfile.arch — the multi-base pattern needs both"
        else
            fail "$app" "no Dockerfile (and not a host-only installer)"
        fi

        # Unqualified FROM. Stage references (FROM base-x) and ARG-substituted
        # images (FROM \${ROCM_BASE}) resolve elsewhere and are not the target.
        local df line image
        for df in "$d"/Dockerfile "$d"/Dockerfile.ubuntu "$d"/Dockerfile.arch; do
            [[ -f "$df" ]] || continue
            while IFS= read -r line; do
                image="$(awk '{ for (i=2;i<=NF;i++) if ($i !~ /^--/) { print $i; exit } }' <<<"$line")"
                [[ -n "$image" ]] || continue
                [[ "$image" == *'$'* ]] && continue
                [[ "$image" == *.*/* || "$image" == localhost/* ]] && continue
                grep -qiE "^FROM[[:space:]]+.*[[:space:]]AS[[:space:]]+$image\$" "$df" && continue
                graduated "$app" "unqualified image '$image' in $(basename "$df") (Podman has no unqualified-search registries)" \
                    "${LEGACY_UNQUALIFIED_FROM[@]}"
                break 2
            done < <(grep -iE '^[[:space:]]*FROM[[:space:]]' "$df")
        done

        # ── exports ─────────────────────────────────────────────────────────
        if [[ ! -f "$d/exports" ]]; then
            fail "$app" "no exports file"
        else
            local type name
            while IFS=: read -r type name _; do
                [[ -z "${type// /}" || "$type" == \#* ]] && continue
                case "$type" in
                    bin|app|desktop|gui) ;;
                    *) fail "$app" "exports: unknown type '$type' (want bin, app, desktop or gui)" ;;
                esac
                [[ -n "${name// /}" ]] || fail "$app" "exports: '$type' entry has no name"
            done < "$d/exports"
        fi

        # Wrapper scripts reached through command -pv have to be in /usr/bin:
        # that searches the system default PATH, which does not include
        # /usr/local/bin. Only bin:, desktop: and gui: exports are resolved that
        # way — an app: export re-exports a .desktop that the container resolves
        # itself, where /usr/local/bin is on PATH as usual — so this is checked
        # per export name rather than against the Dockerfile as a whole.
        if [[ -f "$d/exports" ]]; then
            while IFS=: read -r type name _; do
                type="${type// /}"; name="${name// /}"
                [[ -z "$type" || "$type" == \#* ]] && continue
                case "$type" in bin|desktop|gui) ;; *) continue ;; esac
                if grep -rqE "/usr/local/bin/$name([[:space:]]|\"|'|$)" "$d"/Dockerfile* 2>/dev/null; then
                    fail "$app" "exports '$type:$name' but writes it to /usr/local/bin (command -pv will not find it; use /usr/bin)"
                fi
            done < "$d/exports"
        fi
    fi

    # ── description ─────────────────────────────────────────────────────────
    if [[ ! -f "$d/description" ]]; then
        fail "$app" "no description file"
    else
        local desc
        desc="$(head -1 "$d/description")"
        if [[ -z "${desc// /}" ]]; then
            fail "$app" "description is empty"
        elif (( ${#desc} > MAX_DESCRIPTION )); then
            fail "$app" "description is ${#desc} chars, over the $MAX_DESCRIPTION-char TUI column"
        fi
    fi

    # ── category ────────────────────────────────────────────────────────────
    if [[ ! -f "$d/category" ]] || [[ -z "$(head -1 "$d/category" | tr -d '[:space:]')" ]]; then
        fail "$app" "no category (the app would land in the 'Other' tab)"
    fi

    # ── README and its badge row ────────────────────────────────────────────
    if [[ ! -f "$d/README.md" ]]; then
        graduated "$app" "no README.md (the dashboard info panel renders it)" "${LEGACY_NO_README[@]}"
    else
        if in_list "$app" "${LEGACY_NO_README[@]}"; then
            note "$app" "has a README now — remove it from LEGACY_NO_README in $(basename "$0")"
        fi
        # tui/badges.go keys on the first HTML <p> containing img.shields.io and
        # reads the distro name out of the alt text, so the alt text is
        # load-bearing in a way the visible badge is not.
        if ! grep -q 'img.shields.io' "$d/README.md"; then
            fail "$app" "README.md has no compatibility badge row"
        else
            if grep -qE '!\[[^]]*\]\(https://img\.shields\.io' "$d/README.md"; then
                fail "$app" "README.md badges are markdown images; glamour expands those into URL noise — use a raw <p> block"
            fi
            local distro
            for distro in "Ubuntu" "Linux Mint" "CachyOS"; do
                grep -q "alt=\"$distro: " "$d/README.md" \
                    || fail "$app" "README.md badge row has no alt=\"$distro: ...\" badge"
            done
        fi
    fi

    # ── .memory.md ──────────────────────────────────────────────────────────
    # Warned about, never failed: it is a working note for whoever touches the
    # app next, and a missing one blocks nothing at runtime.
    [[ -f "$d/.memory.md" ]] || printf 'note:   %s: no .memory.md\n' "$app"
}

# ── Run ─────────────────────────────────────────────────────────────────────

declare -a apps=()
if ((${#ONLY[@]})); then
    apps=("${ONLY[@]}")
else
    while IFS= read -r a; do apps+=("$a"); done < <(
        find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    )
fi

for app in "${apps[@]}"; do
    [[ -d "$APPS_DIR/$app" ]] || { fail "$app" "no such app directory"; continue; }
    check_app "$app"
done

# Stale legacy entries: listed apps that no longer exist at all.
for app in "${LEGACY_NO_README[@]}" "${LEGACY_UNQUALIFIED_FROM[@]}"; do
    [[ -d "$APPS_DIR/$app" ]] || note "$app" "listed as legacy but there is no such app — remove it"
done

echo
printf 'checked %d app(s): %d error(s), %d grandfathered, %d stale\n' \
    "${#apps[@]}" "$errors" "$legacy" "$stale"
((errors == 0)) || exit 1
exit 0
