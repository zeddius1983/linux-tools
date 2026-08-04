#!/usr/bin/env bash
# Claude Code status line, styled to match the shell prompt in
# ~/.config/starship.toml (palette: gruvbox_dark).
#
#   left:  os_icon, dir, vcs (branch + status + ahead/behind), pull request
#   right: model, agent, context window, cache read/write, 5h/7d rate limits,
#          context (user@host, ssh/root only), time
#
# Colors are 24-bit truecolor taken verbatim from the [palettes.gruvbox_dark]
# table in starship.toml, and segments follow starship's own ordering
# (orange -> yellow -> aqua -> ... -> bg1) so both bars read as one design.
# The older 256-color version approximated ~/.p10k.zsh, which no longer exists.
#
# Perf note: this runs on every render, so all JSON fields are pulled in a
# single jq call (not one per field), git state in a single `status
# --porcelain=v2 --branch` call parsed by a single awk pass, and both clock
# reads share one `date` call.

input=$(cat)

# \x1f (unit separator) is used instead of a tab: bash's `read` collapses
# consecutive tab/space/newline delimiters even when IFS is set to just one
# of them, which silently swallows empty fields (e.g. a missing model) and
# shifts every field after it. \x1f isn't whitespace, so it doesn't collapse.
IFS=$'\x1f' read -r \
  cwd model_name \
  ctx_in ctx_out ctx_size ctx_pct \
  cache_read cache_write \
  five_h_used seven_d_used five_h_resets_at seven_d_resets_at \
  pr_number pr_url pr_state agent_name \
  <<< "$(jq -r '
    [
      (.workspace.current_dir // .cwd // ""),
      (.model.display_name // ""),
      (.context_window.total_input_tokens // 0 | tostring),
      (.context_window.total_output_tokens // 0 | tostring),
      (.context_window.context_window_size // 0 | tostring),
      (.context_window.used_percentage | if . == null then "0" else ((. + 0.5) | floor | tostring) end),
      (.context_window.current_usage.cache_read_input_tokens // 0 | tostring),
      (.context_window.current_usage.cache_creation_input_tokens // 0 | tostring),
      (.rate_limits.five_hour.used_percentage | if . == null then "" else ((. + 0.5) | floor | tostring) end),
      (.rate_limits.seven_day.used_percentage | if . == null then "" else ((. + 0.5) | floor | tostring) end),
      (.rate_limits.five_hour.resets_at // "" | tostring),
      (.rate_limits.seven_day.resets_at // "" | tostring),
      (.pr.number // "" | tostring),
      (.pr.url // ""),
      (.pr.review_state // ""),
      (.agent.name // "")
    ] | join("\u001f")
  ' <<< "$input")"

[[ -z "$cwd" ]] && cwd="$PWD"
ctx_used=$((ctx_in + ctx_out))
cache_total=$((cache_read + cache_write))

# --- gruvbox_dark palette, copied from [palettes.gruvbox_dark] in
#     ~/.config/starship.toml. Values are "R;G;B" for truecolor SGR. ---
c_fg0='251;241;199'    # #fbf1c7  default ink
c_ink='40;40;40'       # #282828  dark ink, for light backgrounds (yellow)
c_bg1='60;56;54'       # #3c3836
c_bg3='102;92;84'      # #665c54
c_blue='69;133;136'    # #458588
c_aqua='104;157;106'   # #689d6a
c_green='152;151;26'   # #98971a
c_orange='214;93;14'   # #d65d0e
c_purple='177;98;134'  # #b16286
c_red='204;36;29'      # #cc241d
c_yellow='215;153;33'  # #d79921

bg() { printf '\e[48;2;%sm' "$1"; }
fg() { printf '\e[38;2;%sm' "$1"; }
reset=$'\e[0m'

fg_for() { # readable ink for a given background
  case "$1" in
    "$c_yellow") printf '%s' "$c_ink" ;;
    *)           printf '%s' "$c_fg0" ;;
  esac
}

# osc8: wrap text in an OSC 8 hyperlink so terminals that support it (Kitty,
# WezTerm, iTerm2, foot, recent VTE) make it ctrl-clickable. Terminals that
# don't just render the text, since the escape carries no printable payload.
osc8() { # $1=url $2=text
  if [[ -n "$1" ]]; then
    printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

# detect_os_icon: pick the nerd-font OS glyph for the *host* distro. This
# script runs inside the ubuntu container, but Distrobox bind-mounts the host
# root at /run/host, so /run/host/etc/os-release names the real host (e.g.
# arch/cachyos) even though /etc/os-release here says ubuntu. Falls back to the
# local /etc/os-release when run directly on a host, and to a generic Tux when
# nothing matches. Codepoints match starship's [os.symbols] / p10k's icons.zsh.
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

# Segment geometry, mirroring starship.toml: rounded caps on the outer edges
# (its format opens with [\ue0b6](color_orange) and closes with [\ue0b4 ]),
# powerline arrows between segments. Written as \u escapes rather than literal
# private-use glyphs so the codepoints stay legible in any editor.
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

usage_color_weekly() { # 7d: red >=80%, purple >=50%, else blue (distinct hue from 5h)
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
  disp="~/${cwd#$HOME/}"
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

# --- vcs: branch, ahead/behind and per-class change counts from a single git
#     call, parsed in a single awk pass.
#
#     Untracked files do NOT make the segment "dirty". `git status
#     --porcelain=v2` reports them as `? path` lines, so testing for any
#     non-`#` line (the previous approach) coloured an otherwise clean tree as
#     modified. They get their own `?N` marker instead, matching starship's
#     $all_status, which distinguishes the two.
vcs_branch="" vcs_status="" vcs_bg=$c_aqua
vcs_raw=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
if [[ -n "$vcs_raw" ]]; then
  IFS=$'\x1f' read -r vcs_branch vcs_ahead vcs_behind vcs_tracked vcs_untracked <<< "$(
    awk '
      /^# branch\.head / { head = $3 }
      /^# branch\.ab /   { ahead = $3 + 0; behind = -($4 + 0) }
      # ordinary (1), renamed/copied (2) and unmerged (u) entries are tracked
      # changes; XY is field 2 and is "." in a position with no change.
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

# --- pr: colour by review state; the number links to the PR via OSC 8 ---
pr_bg=$c_bg3
case "$pr_state" in
  approved)          pr_bg=$c_green ;;
  changes_requested) pr_bg=$c_red ;;
  pending)           pr_bg=$c_yellow ;;
  draft|"")          pr_bg=$c_bg3 ;;
esac

# --- context: user@host, only when it would actually differ from starship's
#     default-hidden behavior (ssh session or root) ---
context=""
if [[ -n "$SSH_CONNECTION" || "$EUID" -eq 0 ]]; then
  context="$(whoami)@$(hostname -s)"
fi

# --- clock: one `date` call feeds both the epoch (for countdowns) and the
#     display time ---
read -r now time_str <<< "$(date +'%s %H:%M:%S')"

# ---- assemble left side ----
line="${reset}$(fg "$c_orange")${cap_l}$(bg "$c_orange")$(fg "$c_fg0") ${os_icon} "
line+="$(bg "$c_yellow")$(fg "$c_orange")${sep}$(fg "$c_ink") ${dir_icon} ${dir_display} "
last_bg=$c_yellow
if [[ -n "$vcs_branch" ]]; then
  line+="$(bg "$vcs_bg")$(fg "$last_bg")${sep}$(fg "$(fg_for "$vcs_bg")") ${branch_icon} ${vcs_branch}${vcs_status} "
  last_bg=$vcs_bg
fi
if [[ -n "$pr_number" ]]; then
  line+="$(bg "$pr_bg")$(fg "$last_bg")${sep}$(fg "$(fg_for "$pr_bg")") $(osc8 "$pr_url" "${pr_icon} #${pr_number}") "
  last_bg=$pr_bg
fi
line+="${reset}$(fg "$last_bg")${cap_r}${reset}"

# ---- assemble right side ----
right=""
prev_bg=""
add_seg() { # $1=bg $2=text
  local segbg=$1 text=$2
  if [[ -n "$prev_bg" ]]; then
    right+="$(bg "$segbg")$(fg "$prev_bg")${sep}"
  else
    right+="${reset}$(fg "$segbg")${cap_l}" # rounded cap, on default bg
  fi
  right+="$(bg "$segbg")$(fg "$(fg_for "$segbg")") ${text} "
  prev_bg=$segbg
}

[[ -n "$model_name" ]] && add_seg "$c_purple" "$model_name"
[[ -n "$agent_name" ]] && add_seg "$c_blue" "${agent_icon} ${agent_name}"

add_seg "$(usage_color "$ctx_pct")" "${ctx_icon} $(fmt_num "$ctx_used")/$(fmt_num "$ctx_size") ${ctx_pct}%"

if (( cache_total > 0 )); then
  cache_pct=$(((cache_read * 100 + cache_total / 2) / cache_total))
  add_seg "$c_yellow" "${cache_icon} ${cache_pct}% ↓$(fmt_num "$cache_read") ↑$(fmt_num "$cache_write")"
fi

if [[ -n "$five_h_used" && -n "$five_h_resets_at" ]]; then
  add_seg "$(usage_color "$five_h_used")" "5h $((100 - five_h_used))% ${clock_icon}$(fmt_countdown $((five_h_resets_at - now)))"
fi
if [[ -n "$seven_d_used" && -n "$seven_d_resets_at" ]]; then
  add_seg "$(usage_color_weekly "$seven_d_used")" "7d $((100 - seven_d_used))% ${clock_icon}$(fmt_countdown $((seven_d_resets_at - now)))"
fi

[[ -n "$context" ]] && add_seg "$c_bg3" "$context"

add_seg "$c_bg1" "$time_str"

right+="${reset}$(fg "$prev_bg")${cap_r}${reset}"

printf '%s  %s' "$line" "$right"
