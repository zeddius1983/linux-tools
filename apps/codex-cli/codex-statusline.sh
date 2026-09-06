#!/usr/bin/env bash
# Codex CLI status line for tmux, styled to match ~/.claude/statusline.sh (and
# through it the shell prompt in ~/.config/starship.toml, palette gruvbox_dark).
#
#   left:  os_icon, dir, vcs (branch + status + ahead/behind), pull request
#   right: model + reasoning effort, context window, cache read/write,
#          5h/7d rate limits, context (user@host, ssh/root only), time
#
# Two things differ from the Claude Code script, both forced by Codex:
#
#   1. Codex has no status-line hook, so this cannot be a Codex plugin. It is
#      rendered by tmux *around* Codex instead (see codex-tmux), which is why
#      colors are emitted as tmux `#[fg=...,bg=...]` tags rather than raw ANSI
#      SGR — tmux sanitizes escape sequences out of its own status line, so the
#      original's `\e[48;2;...m` approach produces literal garbage there.
#   2. There is no stdin JSON. Codex's per-session rollout file is the only
#      machine-readable source of live token/rate-limit state, so this reads the
#      newest one under ~/.codex/sessions/. See "rollout" below for the caveats.
#
# The `agent` segment has no Codex equivalent and is dropped; the model segment
# gains the reasoning effort instead.
#
# Perf note: tmux re-runs this every status-interval, so the rollout file is
# read via a bounded `tail` (not a whole-file scan, which grows without limit
# over a long session) and all fields come out of a single jq call.

set -uo pipefail

# tmux expands #{client_width} in the status-format command and passes it as
# $1 (see codex-tmux.conf). 0 means "unknown" — render everything and let tmux
# clip. Segment dropping below depends on this being the *client* width.
term_width="${1:-0}"
[[ "$term_width" =~ ^[0-9]+$ ]] || term_width=0

# ${#var} counts bytes under a non-UTF-8 locale, which would overcount every
# glyph threefold and drop segments that actually fit. The tmux server's
# environment is not guaranteed to carry a UTF-8 locale, so pin one.
if [[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" != *[Uu][Tt][Ff]* ]]; then
    export LC_ALL=C.UTF-8
fi

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
SESSIONS_DIR="$CODEX_DIR/sessions"

# --- rollout: find the file backing the current session ------------------------
#
# Codex does not expose its active rollout path, so this picks the most recently
# modified one. CODEX_STATUSLINE_SINCE (exported by codex-tmux as the wrapper's
# start epoch) restricts the search to files touched during this session, so a
# session that has not written its first token_count yet shows an empty bar
# rather than the *previous* session's numbers.
newest_rollout() {
    local since="${CODEX_STATUSLINE_SINCE:-0}"
    [[ -d "$SESSIONS_DIR" ]] || return 0
    find "$SESSIONS_DIR" -name 'rollout-*.jsonl' -newermt "@$since" \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

rollout="$(newest_rollout)"

# \x1f (unit separator) instead of a tab: bash's `read` collapses consecutive
# whitespace delimiters even when IFS is one of them, silently swallowing empty
# fields and shifting every field after. \x1f isn't whitespace.
#
# Only the tail is parsed. Both records we need are rewritten on every turn, so
# the last of each is always near the end; a full scan would make the bar get
# slower the longer the session runs.
IFS=$'\x1f' read -r \
    cwd model_name effort \
    ctx_in ctx_out ctx_size \
    cache_read cache_write \
    five_h_used seven_d_used five_h_resets_at seven_d_resets_at \
    <<< "$(
    if [[ -n "$rollout" && -r "$rollout" ]]; then
        tail -n 400 "$rollout" 2>/dev/null | jq -rs '
          # Last turn_context wins for model/cwd; last token_count for usage.
          (map(select(.type == "turn_context")) | last | .payload?) as $t
          | (map(select(.type == "event_msg" and .payload.type == "token_count"))
             | last | .payload?) as $u
          | ($u.info.last_token_usage // {}) as $lu
          | [
              ($t.cwd // ""),
              ($t.model // ""),
              ($t.effort // ""),
              ($lu.input_tokens // 0 | tostring),
              ($lu.output_tokens // 0 | tostring),
              ($u.info.model_context_window // 0 | tostring),
              ($lu.cached_input_tokens // 0 | tostring),
              ($lu.cache_write_input_tokens // 0 | tostring),
              ($u.rate_limits.primary.used_percent
                 | if . == null then "" else ((. + 0.5) | floor | tostring) end),
              ($u.rate_limits.secondary.used_percent
                 | if . == null then "" else ((. + 0.5) | floor | tostring) end),
              ($u.rate_limits.primary.resets_at // "" | tostring),
              ($u.rate_limits.secondary.resets_at // "" | tostring)
            ] | join("")
        ' 2>/dev/null
    fi
)"

# Fall back to the pane's directory when no rollout has been written yet, so the
# bar still shows dir/vcs/PR during the first few seconds of a session.
[[ -z "${cwd:-}" ]] && cwd="${CODEX_STATUSLINE_CWD:-$PWD}"
[[ -d "$cwd" ]] || cwd="$PWD"
ctx_in=${ctx_in:-0} ctx_out=${ctx_out:-0} ctx_size=${ctx_size:-0}
cache_read=${cache_read:-0} cache_write=${cache_write:-0}
ctx_used=$((ctx_in + ctx_out))
cache_total=$((cache_read + cache_write))
ctx_pct=0
(( ctx_size > 0 )) && ctx_pct=$(((ctx_used * 100 + ctx_size / 2) / ctx_size))

# --- gruvbox_dark palette, copied from [palettes.gruvbox_dark] in
#     ~/.config/starship.toml. Hex here rather than the Claude script's "R;G;B"
#     because tmux styles take #rrggbb, not SGR parameters. ---
c_fg0='#fbf1c7'    # default ink
c_ink='#282828'    # dark ink, for light backgrounds (yellow)
c_bg1='#3c3836'
c_bg3='#665c54'
c_blue='#458588'
c_aqua='#689d6a'
c_green='#98971a'
c_orange='#d65d0e'
c_purple='#b16286'
c_red='#cc241d'
c_yellow='#d79921'

fg_for() { # readable ink for a given background
    case "$1" in
        "$c_yellow") printf '%s' "$c_ink" ;;
        *)           printf '%s' "$c_fg0" ;;
    esac
}

# tmux eats a literal '#' in status text (it introduces a format), so any text
# that can contain one — the PR number — must double it.
esc() { printf '%s' "${1//#/##}"; }

# detect_os_icon: pick the nerd-font OS glyph for the *host* distro. This runs
# inside the codex-cli container, but Distrobox bind-mounts the host root at
# /run/host, so /run/host/etc/os-release names the real host (e.g. arch/cachyos)
# even though /etc/os-release here says ubuntu. Falls back to the local
# /etc/os-release when run directly on a host, and to a generic Tux when nothing
# matches. Codepoints match starship's [os.symbols].
detect_os_icon() {
  local osr="" os_id="" os_like="" tok
  if [[ -r /run/host/etc/os-release ]]; then
    osr=/run/host/etc/os-release
  elif [[ -r /etc/os-release ]]; then
    osr=/etc/os-release
  fi
  if [[ -n "$osr" ]]; then
    IFS=$'\x1f' read -r os_id os_like <<< "$(awk -F= '
      $1=="ID"      {gsub(/"/,"",$2); id=$2}
      $1=="ID_LIKE" {gsub(/"/,"",$2); like=$2}
      END {print id"\x1f"like}' "$osr")"
  fi
  case "$os_id" in # direct match on the distro ID
    arch)                printf ''; return ;; # arch
    manjaro|manjaro-arm) printf ''; return ;; # manjaro
    ubuntu)              printf ''; return ;; # ubuntu
    linuxmint)           printf ''; return ;; # mint
    debian|raspbian)     printf ''; return ;; # debian
    fedora)              printf ''; return ;; # fedora
    rhel|centos)         printf ''; return ;; # centos
    rocky|almalinux|ol)  printf ''; return ;; # redhat
    opensuse*|sled|sles) printf ''; return ;; # opensuse
    gentoo)              printf ''; return ;; # gentoo
    nixos)               printf ''; return ;; # nixos
    alpine)              printf ''; return ;; # alpine
  esac
  for tok in $os_like; do # fall back to distro family (ID_LIKE, specific first)
    case "$tok" in
      arch)          printf ''; return ;;
      ubuntu)        printf ''; return ;;
      debian)        printf ''; return ;;
      fedora)        printf ''; return ;;
      rhel|centos)   printf ''; return ;;
      suse|opensuse) printf ''; return ;;
    esac
  done
  printf '' # generic Tux
}

# Segment geometry, identical to the Claude Code bar: rounded caps on the outer
# edges, powerline arrows between segments. Written as \u escapes rather than
# literal private-use glyphs so the codepoints stay legible in any editor.
sep=$'\ue0b0'         # powerline arrow, between segments
cap_l=$'\ue0b6'       # rounded left cap, opens a group
cap_r=$'\ue0b4'       # rounded right cap, closes a group
branch_icon=$'\uf126' # nf-dev-git_branch, matches [git_branch].symbol
os_icon=$(detect_os_icon)
dir_icon=$'\uf115'    # nf-fa-folder_open_o
cache_icon=$'\uf0a0'  # nf-fa-hdd_o
ctx_icon=$'\uf0e4'    # nf-fa-dashboard, reused for context window
clock_icon=$'\uf017'  # nf-fa-clock_o
pr_icon=$'\uf407'     # nf-oct-git_pull_request
agent_icon=$'\uf085'  # nf-fa-cogs
ahead_icon=$'\u21e1'  # matches starship's git_status ahead marker
behind_icon=$'\u21e3'
dirty_icon=$'\u25cf'  # tracked changes (staged / modified / conflicted)
untracked_icon='?'

usage_color() { # 5h: red >=80%, yellow >=50%, else green
    local pct=$1
    if   (( pct >= 80 )); then printf '%s' "$c_red"
    elif (( pct >= 50 )); then printf '%s' "$c_yellow"
    else                       printf '%s' "$c_green"
    fi
}

usage_color_weekly() { # 7d: red >=80%, purple >=50%, else blue (distinct from 5h)
    local pct=$1
    if   (( pct >= 80 )); then printf '%s' "$c_red"
    elif (( pct >= 50 )); then printf '%s' "$c_purple"
    else                       printf '%s' "$c_blue"
    fi
}

fmt_countdown() { # seconds remaining -> "2h14m" / "3d4h" / "45m"
    local secs=$1
    (( secs < 0 )) && secs=0
    local days=$((secs / 86400))
    local hours=$(((secs % 86400) / 3600))
    local mins=$(((secs % 3600) / 60))
    if (( days > 0 )); then
        printf '%dd%dh' "$days" "$hours"
    elif (( hours > 0 )); then
        printf '%dh%dm' "$hours" "$mins"
    else
        printf '%dm' "$mins"
    fi
}

fmt_num() {
    local n=$1
    if (( n >= 1000000 )); then
        printf '%d.%01dM' $((n / 1000000)) $(((n / 100000) % 10))
    elif (( n >= 1000 )); then
        printf '%d.%01dk' $((n / 1000)) $(((n / 100) % 10))
    else
        printf '%d' "$n"
    fi
}

# --- dir: p10k-style truncation (keep last component full, others to 1 char) ---
disp="$cwd"
if [[ "$cwd" == "$HOME" ]]; then
    disp="~"
elif [[ "$cwd" == "$HOME"/* ]]; then
    disp="~/${cwd#"$HOME"/}"
fi
IFS='/' read -ra parts <<< "$disp"
count=${#parts[@]}
dir_display=""
for i in "${!parts[@]}"; do
    seg="${parts[$i]}"
    [[ -z "$seg" ]] && continue
    if [[ $i -eq $((count - 1)) ]]; then
        dir_display+="/${seg}"
    elif [[ "$seg" == "~" ]]; then
        dir_display+="${seg}"
    else
        dir_display+="/${seg:0:1}"
    fi
done
[[ "$disp" == /* ]] || dir_display="${dir_display#/}"
# "/" has no components, so the loop above yields an empty string for it.
[[ -z "$dir_display" ]] && dir_display="/"

# --- vcs: branch, ahead/behind and per-class change counts from a single git
#     call, parsed in a single awk pass. Untracked files do NOT make the segment
#     "dirty" — they get their own `?N` marker, matching starship's $all_status.
vcs_branch="" vcs_status="" vcs_bg=$c_aqua
vcs_ahead=0 vcs_behind=0 vcs_tracked=0 vcs_untracked=0
vcs_raw=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
if [[ -n "$vcs_raw" ]]; then
    IFS=$'\x1f' read -r vcs_branch vcs_ahead vcs_behind vcs_tracked vcs_untracked <<< "$(
        awk '
      /^# branch\.head / { head = $3 }
      /^# branch\.ab /   { ahead = $3 + 0; behind = -($4 + 0) }
      /^[12] /           { if (substr($2, 1, 1) != "." || substr($2, 2, 1) != ".") tracked++ }
      /^u /              { tracked++ }
      /^\? /             { untracked++ }
      END { printf "%s\x1f%d\x1f%d\x1f%d\x1f%d", head, ahead, behind, tracked, untracked }
    ' <<< "$vcs_raw"
    )"
    if [[ "$vcs_branch" == "(detached)" || -z "$vcs_branch" ]]; then
        vcs_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    fi
    (( vcs_tracked > 0 )) && vcs_bg=$c_orange # tracked changes -> attention
    (( vcs_tracked > 0 ))   && vcs_status+=" ${dirty_icon}${vcs_tracked}"
    (( vcs_untracked > 0 )) && vcs_status+=" ${untracked_icon}${vcs_untracked}"
    (( vcs_ahead > 0 ))     && vcs_status+=" ${ahead_icon}${vcs_ahead}"
    (( vcs_behind > 0 ))    && vcs_status+=" ${behind_icon}${vcs_behind}"
fi

# --- pr: colour by review state.
#
# The Claude Code script gets the PR from its stdin JSON; Codex provides
# nothing, so it is looked up with `gh` — but only from a short-lived cache.
# An uncached `gh pr view` is a network round-trip, and this renders every
# status-interval; without the cache the bar would issue an API call every two
# seconds and get rate-limited within the hour.
pr_number="" pr_url="" pr_state=""
pr_cache="${TMPDIR:-/tmp}/.codex-statusline-pr-$(id -u)"
if [[ -n "$vcs_branch" ]] && command -v gh >/dev/null 2>&1; then
    pr_key="$cwd@$vcs_branch"
    pr_line=""
    if [[ -r "$pr_cache" ]]; then
        pr_age=$(( $(date +%s) - $(stat -c %Y "$pr_cache" 2>/dev/null || echo 0) ))
        (( pr_age < 90 )) && pr_line=$(grep -m1 -F "$pr_key"$'\x1f' "$pr_cache" 2>/dev/null)
    fi
    if [[ -z "$pr_line" ]]; then
        pr_json=$(cd "$cwd" && timeout 5 gh pr view --json number,url,reviewDecision 2>/dev/null)
        if [[ -n "$pr_json" ]]; then
            pr_line="$pr_key"$'\x1f'$(jq -r '[(.number|tostring), .url,
                (.reviewDecision // "" | ascii_downcase)] | join("")' <<< "$pr_json")
        else
            pr_line="$pr_key"$'\x1f\x1f\x1f'
        fi
        printf '%s\n' "$pr_line" > "$pr_cache" 2>/dev/null || true
    fi
    IFS=$'\x1f' read -r _ pr_number pr_url pr_state <<< "$pr_line"
fi

pr_bg=$c_bg3
case "${pr_state:-}" in
    approved)          pr_bg=$c_green ;;
    changes_requested) pr_bg=$c_red ;;
    review_required|pending) pr_bg=$c_yellow ;;
    *)                 pr_bg=$c_bg3 ;;
esac

# --- context: user@host, only when it would actually differ from starship's
#     default-hidden behavior (ssh session or root) ---
context=""
if [[ -n "${SSH_CONNECTION:-}" || "$EUID" -eq 0 ]]; then
    context="$(whoami)@$(hostname -s)"
fi

read -r now time_str <<< "$(date +'%s %H:%M:%S')"

# ---- assemble left side ----
line="#[fg=${c_orange},bg=default]${cap_l}#[bg=${c_orange},fg=${c_fg0}] ${os_icon} "
line+="#[bg=${c_yellow},fg=${c_orange}]${sep}#[fg=${c_ink}] ${dir_icon} $(esc "$dir_display") "
last_bg=$c_yellow
if [[ -n "$vcs_branch" ]]; then
    line+="#[bg=${vcs_bg},fg=${last_bg}]${sep}#[fg=$(fg_for "$vcs_bg")] ${branch_icon} $(esc "${vcs_branch}${vcs_status}") "
    last_bg=$vcs_bg
fi
if [[ -n "$pr_number" ]]; then
    line+="#[bg=${pr_bg},fg=${last_bg}]${sep}#[fg=$(fg_for "$pr_bg")] ${pr_icon} $(esc "#${pr_number}") "
    last_bg=$pr_bg
fi
line+="#[bg=default,fg=${last_bg}]${cap_r}#[default]"

# ---- assemble right side ----
#
# Collected first, rendered second: the bar is 147 columns on a typical session,
# so on a narrower terminal something has to go. Letting tmux clip would cut
# mid-segment and leave a half-drawn coloured block, which reads as a bug.
# Dropping whole low-value segments instead degrades cleanly. Model and context
# window are never dropped.
seg_bg=() seg_text=() seg_prio=()
add_seg() { # $1=bg $2=text $3=drop priority (higher drops first; 0 = never)
    seg_bg+=("$1"); seg_text+=("$2"); seg_prio+=("${3:-0}")
}

if [[ -n "${model_name:-}" ]]; then
    model_text="$model_name"
    [[ -n "${effort:-}" ]] && model_text+=" ${effort}"
    add_seg "$c_purple" "$(esc "$model_text")" 0
fi

if (( ctx_size > 0 )); then
    add_seg "$(usage_color "$ctx_pct")" "${ctx_icon} $(fmt_num "$ctx_used")/$(fmt_num "$ctx_size") ${ctx_pct}%" 0
fi

if (( cache_total > 0 )); then
    cache_pct=$(((cache_read * 100 + cache_total / 2) / cache_total))
    add_seg "$c_yellow" "${cache_icon} ${cache_pct}% ↓$(fmt_num "$cache_read") ↑$(fmt_num "$cache_write")" 5
fi

if [[ -n "${five_h_used:-}" && -n "${five_h_resets_at:-}" ]]; then
    add_seg "$(usage_color "$five_h_used")" "5h $((100 - five_h_used))% ${clock_icon}$(fmt_countdown $((five_h_resets_at - now)))" 1
fi
if [[ -n "${seven_d_used:-}" && -n "${seven_d_resets_at:-}" ]]; then
    add_seg "$(usage_color_weekly "$seven_d_used")" "7d $((100 - seven_d_used))% ${clock_icon}$(fmt_countdown $((seven_d_resets_at - now)))" 3
fi

[[ -n "$context" ]] && add_seg "$c_bg3" "$(esc "$context")" 4

add_seg "$c_bg1" "$time_str" 2

# Width of a rendered string, with the #[...] style tags removed — they occupy
# no cells. Done by measurement rather than arithmetic so the caps, separators
# and padding spaces cannot drift out of sync with the renderer below.
plain_width() {
    local t="$1" out=""
    while [[ "$t" == *"#["* ]]; do
        out+="${t%%#[*}"
        t="${t#*]}"
    done
    out+="$t"
    printf '%s' "${#out}"
}

render_right() { # renders the segments whose index is in $keep
    local out="" prev="" i segbg
    for i in "${keep[@]}"; do
        segbg="${seg_bg[$i]}"
        if [[ -n "$prev" ]]; then
            out+="#[bg=${segbg},fg=${prev}]${sep}"
        else
            out+="#[bg=default,fg=${segbg}]${cap_l}#[bg=${segbg}]" # rounded cap on default bg
        fi
        out+="#[bg=${segbg},fg=$(fg_for "$segbg")] ${seg_text[$i]} "
        prev=$segbg
    done
    [[ -n "$prev" ]] && out+="#[bg=default,fg=${prev}]${cap_r}"
    printf '%s#[default]' "$out"
}

keep=("${!seg_bg[@]}")
right="$(render_right)"

# Drop highest-priority-first until it fits, leaving two columns of breathing
# room between the two halves.
if (( term_width > 0 )); then
    left_w=$(plain_width "$line")
    for prio in 5 4 3 2 1; do
        (( left_w + $(plain_width "$right") + 2 <= term_width )) && break
        next=()
        for i in "${keep[@]}"; do
            (( seg_prio[i] == prio )) || next+=("$i")
        done
        keep=("${next[@]}")
        right="$(render_right)"
    done
fi

# Two spaces between the halves, exactly as the Claude Code bar joins them —
# the right side flows on from the left rather than being pushed to the far
# edge. (tmux's #[align=right] would do the latter; it is deliberately unused.)
printf '%s  %s' "$line" "$right"
