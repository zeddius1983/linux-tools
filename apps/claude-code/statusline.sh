#!/usr/bin/env bash
# Approximates the enabled segments from ~/.p10k.zsh:
#   left:  os_icon, dir, vcs
#   right: model, context window usage, cache read/write,
#          5h/7d rate-limit remaining, context (user@host, ssh/root only), time
#
# status/command_execution_time/background_jobs are skipped: there is no
# "last shell command" in Claude Code's status line context, so those
# segments would just be fake data.
#
# Perf note: this runs on every render, so all JSON fields are pulled in a
# single jq call (not one per field), git state in a single `status
# --porcelain=v2 --branch` call (branch + dirty in one shot), and both clock
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
      (.rate_limits.seven_day.resets_at // "" | tostring)
    ] | join("")
  ' <<< "$input")"

[[ -z "$cwd" ]] && cwd="$PWD"
ctx_used=$((ctx_in + ctx_out))
cache_total=$((cache_read + cache_write))

bg() { printf '\e[48;5;%sm' "$1"; }
fg() { printf '\e[38;5;%sm' "$1"; }
reset=$'\e[0m'

# detect_os_icon: pick the powerlevel10k OS glyph for the *host* distro. This
# script runs inside the ubuntu container, but Distrobox bind-mounts the host
# root at /run/host, so /run/host/etc/os-release names the real host (e.g.
# arch/cachyos) even though /etc/os-release here says ubuntu. Falls back to the
# local /etc/os-release when run directly on a host, and to a generic Tux when
# nothing matches. Codepoints match powerlevel10k's icons.zsh OS-icon table.
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
    arch)                printf '\uF303'; return ;; # arch
    manjaro|manjaro-arm) printf '\uF312'; return ;; # manjaro
    ubuntu)              printf '\uF31B'; return ;; # ubuntu
    linuxmint)           printf '\uF30E'; return ;; # mint
    debian|raspbian)     printf '\uF306'; return ;; # debian
    fedora)              printf '\uF30A'; return ;; # fedora
    rhel|centos)         printf '\uF304'; return ;; # centos
    rocky|almalinux|ol)  printf '\uF316'; return ;; # redhat
    opensuse*|sled|sles) printf '\uF314'; return ;; # opensuse
    gentoo)              printf '\uF30D'; return ;; # gentoo
    nixos)               printf '\uF313'; return ;; # nixos
    alpine)              printf '\uF300'; return ;; # alpine
  esac
  for tok in $os_like; do # fall back to distro family (ID_LIKE, specific first)
    case "$tok" in
      arch)          printf '\uF303'; return ;;
      ubuntu)        printf '\uF31B'; return ;;
      debian)        printf '\uF306'; return ;;
      fedora)        printf '\uF30A'; return ;;
      rhel|centos)   printf '\uF304'; return ;;
      suse|opensuse) printf '\uF314'; return ;;
    esac
  done
  printf '\uF17C' # generic Tux
}

sep=$'\uE0B0' # powerline arrow, matches p10k separator style
branch_icon=$'\uF126' # POWERLEVEL9K_VCS_BRANCH_ICON, verified against ~/.p10k.zsh
os_icon=$(detect_os_icon) # host distro glyph (see detect_os_icon above)
dir_icon=$'\uF115' # FOLDER_ICON, verified against powerlevel10k source (icons.zsh)
cache_icon=$'\uF0A0' # DISK_ICON, verified against powerlevel10k source (icons.zsh)
ctx_icon=$'\uF0E4' # RAM_ICON, reused for context window (same "memory usage" concept)
clock_icon=$'\uF017' # nf-fa-clock_o

usage_color() { # 5h: red >=80%, yellow >=50%, else green
  local pct=$1
  if (( pct >= 80 )); then echo 1
  elif (( pct >= 50 )); then echo 3
  else echo 2
  fi
}

usage_color_weekly() { # 7d: red >=80%, magenta >=50%, else blue (distinct hue from 5h)
  local pct=$1
  if (( pct >= 80 )); then echo 1
  elif (( pct >= 50 )); then echo 5
  else echo 4
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

# --- vcs: branch + dirty state in a single git call (colors match
#     POWERLEVEL9K_VCS_*_BACKGROUND) ---
vcs_branch=""
vcs_bg=2 # clean/untracked -> green
vcs_raw=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
if [[ -n "$vcs_raw" ]]; then
  vcs_branch=$(awk '/^# branch\.head/{print $3; exit}' <<< "$vcs_raw")
  if [[ "$vcs_branch" == "(detached)" || -z "$vcs_branch" ]]; then
    vcs_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
  if grep -qv '^#' <<< "$vcs_raw"; then
    vcs_bg=3 # modified -> yellow
  fi
fi

# --- context: user@host, only when it would actually differ from p10k's
#     default-hidden behavior (ssh session or root) ---
context=""
if [[ -n "$SSH_CONNECTION" || "$EUID" -eq 0 ]]; then
  context="$(whoami)@$(hostname -s)"
fi

# --- clock: one `date` call feeds both the epoch (for countdowns) and the
#     display time ---
read -r now time_str <<< "$(date +'%s %H:%M:%S')"

# ---- assemble left side ----
line="$(bg 7)$(fg 232) ${os_icon} "
line+="$(bg 4)$(fg 7)${sep}$(fg 254) ${dir_icon} ${dir_display} "
last_bg=4
if [[ -n "$vcs_branch" ]]; then
  line+="$(bg "$vcs_bg")$(fg 4)${sep}$(fg 0) ${branch_icon} ${vcs_branch} "
  last_bg=$vcs_bg
fi
line+="${reset}$(fg "$last_bg")${sep}${reset}"

# ---- assemble right side ----
right=""
prev_bg=""
add_seg() { # $1=bg $2=fg $3=text
  local segbg=$1 segfg=$2 text=$3
  if [[ -n "$prev_bg" ]]; then
    right+="$(bg "$segbg")$(fg "$prev_bg")${sep}"
  fi
  right+="$(bg "$segbg")$(fg "$segfg") ${text} "
  prev_bg=$segbg
}

[[ -n "$model_name" ]] && add_seg 5 15 "$model_name"

ctx_color=$(usage_color "$ctx_pct")
add_seg "$ctx_color" 0 "${ctx_icon} $(fmt_num "$ctx_used")/$(fmt_num "$ctx_size") ${ctx_pct}%"

if (( cache_total > 0 )); then
  cache_pct=$(((cache_read * 100 + cache_total / 2) / cache_total))
  add_seg 3 0 "${cache_icon} ${cache_pct}% ↓$(fmt_num "$cache_read") ↑$(fmt_num "$cache_write")"
fi

if [[ -n "$five_h_used" && -n "$five_h_resets_at" ]]; then
  add_seg "$(usage_color "$five_h_used")" 0 "5h $((100 - five_h_used))% ${clock_icon}$(fmt_countdown $((five_h_resets_at - now)))"
fi
if [[ -n "$seven_d_used" && -n "$seven_d_resets_at" ]]; then
  add_seg "$(usage_color_weekly "$seven_d_used")" 15 "7d $((100 - seven_d_used))% ${clock_icon}$(fmt_countdown $((seven_d_resets_at - now)))"
fi

[[ -n "$context" ]] && add_seg 0 3 "$context"

add_seg 7 0 "$time_str"

right+="${reset}"

printf '%s  %s' "$line" "$right"
