#!/usr/bin/env bash
# Regenerate the dashboard screenshots in docs/images/.
#
# Every shot comes from the dashboard's own --render mode (one frame, no tty)
# piped through charmbracelet/freeze, so the images are reproducible: no window
# manager, no manual cropping, and nothing that quietly goes stale when the UI
# changes. --render-keys presses the keys needed to reach a screen that is not
# the first one.
#
# Requires: freeze (go install github.com/charmbracelet/freeze@latest) and
# ImageMagick's convert, for the downscale that keeps the images repo-sized.
#
# freeze reads stdin when it is not a terminal, so every call redirects it from
# /dev/null — without that the script hangs forever the moment it runs from
# anything but an interactive shell (a CI job, a background task).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

out_dir="docs/images"
real_home="$HOME"
tui_bin="tui/tools-tui"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v freeze >/dev/null || {
    echo "freeze not found: go install github.com/charmbracelet/freeze@latest" >&2
    exit 1
}
[[ -x "$tui_bin" ]] || tools build-tui

mkdir -p "$out_dir"

# --ascii is deliberate. freeze rasterises with its own embedded JetBrains Mono,
# which has no Nerd Font private-use glyphs, so the default icon set would come
# out as tofu boxes; --ascii is the same dashboard as seen without a patched
# font.
#
# HOME points at an empty directory so the .packages wizard shows the state a
# new user sees — nothing detected as installed — instead of this machine's.
# XDG_DATA_HOME/XDG_CONFIG_HOME stay on the real home, or rootless podman takes
# the empty HOME as a brand new container store and spends minutes building one
# before the dashboard can report a single image.
shot() {
    local name="$1"; shift
    HOME="$work/home" \
    XDG_DATA_HOME="${XDG_DATA_HOME:-$real_home/.local/share}" \
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$real_home/.config}" \
        "$tui_bin" --ascii --render "$@" > "$work/$name.ansi"
    freeze "$work/$name.ansi" \
        --language ansi \
        --output "$work/$name.png" \
        --window --border.radius 8 --padding 20 \
        --background "#282828" --font.size 14 >/dev/null </dev/null
    # freeze renders at ~4000px; half that is plenty for a README and a quarter
    # of the bytes.
    convert "$work/$name.png" -resize 1800x -strip "$out_dir/$name.png"
    echo "  $out_dir/$name.png  ($(du -h "$out_dir/$name.png" | cut -f1))"
}

mkdir -p "$work/home"

echo "Rendering:"
# The dashboard itself: category tabs, app table, README panel, key footer.
shot dashboard --render-app comfyui --render-width 100 --render-height 22

# A .packages wizard page — the checklist that decides what goes in the box.
shot wizard-tools --render-app dev-toolbox --render-wizard setup \
    --render-keys "space,j,space,j,j,space" --render-width 100 --render-height 20

# A .buildarg release picker, with the selected release's notes beside it.
shot wizard-release --render-app fastflowlm --render-wizard setup \
    --render-width 100 --render-height 21

# The review screen every wizard ends on, before anything is changed.
shot wizard-review --render-app dev-toolbox --render-wizard setup \
    --render-keys "space,j,space,j,j,space,enter" --render-width 100 --render-height 16
