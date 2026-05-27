# zsh-toolbox — Implementation Plan

A host-install app that sets up zsh with a curated set of modern CLI tools,
a smart prompt, and a fully reversible install/uninstall cycle.

---

## 1. tools.sh extension

`tools.sh` currently assumes every app has a `Dockerfile`. A minimal branch on
app type is added:

- **Detection**: if `apps/<name>/install.sh` exists (and no `Dockerfile`) → host-install mode
- **`tools setup <app>`**: runs `bash apps/<app>/install.sh` instead of build+create+export
- **`tools rm <app>`**: runs `bash apps/<app>/uninstall.sh` (if present); skips container teardown
- **`tools list`**: shows `[host:OK]` / `[host:--]` instead of image/box status

Both modes coexist; no existing app is affected.

---

## 2. Directory layout

```
apps/zsh-toolbox/
  install.sh       ← main installer (runs on host)
  uninstall.sh     ← full cleanup/revert
  description      ← "zsh + modern CLI tools"
  plan.md          ← this file
```

Runtime state lives entirely in `~/.zsh-toolbox/`:

```
~/.zsh-toolbox/
  init.zsh              ← single file sourced by .zshrc
  aliases.zsh           ← eza aliases, misc
  plugins/
    zsh-syntax-highlighting/
    zsh-autosuggestions/
    zsh-you-should-use/
  starship.toml         ← our config; pointed to via $STARSHIP_CONFIG
  manifest              ← JSON log of every change made (for uninstall)
```

---

## 3. .zshrc / .zprofile management

**Rule: touch `.zshrc` exactly once.**

The installer appends one line:

```bash
[[ -f ~/.zsh-toolbox/init.zsh ]] && source ~/.zsh-toolbox/init.zsh
```

`.zprofile` is not touched. `init.zsh` handles any `PATH` extensions internally.

Before appending, the installer backs up `.zshrc`:

```
~/.zshrc.zsh-toolbox-backup-<YYYYMMDD-HHMMSS>
```

The backup path is written to `manifest`. Uninstall restores from it exactly and
removes the backup.

---

## 4. Manifest and uninstall guarantee

Every action during install is appended to `~/.zsh-toolbox/manifest` as one
JSON object per line, e.g.:

```jsonl
{"action":"backed_up","file":"~/.zshrc","backup":"~/.zshrc.zsh-toolbox-backup-20260527-143022"}
{"action":"appended_zshrc"}
{"action":"chsh","from":"/bin/bash","to":"/bin/zsh"}
{"action":"installed_bin","path":"~/.local/bin/starship"}
{"action":"installed_bin","path":"~/.local/bin/eza"}
{"action":"installed_bin","path":"~/.local/bin/zoxide"}
{"action":"installed_bin","path":"~/.local/bin/atuin"}
{"action":"installed_bin","path":"~/.local/bin/glow"}
{"action":"apt_installed","packages":["zsh","bat","ripgrep","fd-find","fzf","direnv","tmux"]}
{"action":"cloned_plugin","path":"~/.zsh-toolbox/plugins/zsh-syntax-highlighting"}
{"action":"cloned_plugin","path":"~/.zsh-toolbox/plugins/zsh-autosuggestions"}
{"action":"cloned_plugin","path":"~/.zsh-toolbox/plugins/zsh-you-should-use"}
```

Uninstall reads the manifest in reverse and undoes each entry:

1. Restore `.zshrc` from backup
2. Revert default shell back to original (only if we changed it)
3. Remove binaries from `~/.local/bin`
4. Optionally remove apt packages (prompts user — they may be used elsewhere)
5. Remove `~/.zsh-toolbox/` entirely

---

## 5. Tool list and install methods

### Via apt (Ubuntu 24.04)

| Package | Provides |
|---|---|
| `zsh` | shell |
| `bat` | `batcat` binary (symlinked to `bat` in `~/.local/bin`) |
| `ripgrep` | `rg` |
| `fd-find` | `fdfind` (symlinked to `fd`) |
| `fzf` | fuzzy finder |
| `direnv` | per-directory env vars |

### Via official install scripts

| Tool | Install method |
|---|---|
| starship | `curl -sS https://starship.rs/install.sh \| sh -s -- --bin-dir ~/.local/bin -y` |
| eza | GitHub release binary download (no official install script; curl latest release) |
| zoxide | `curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \| sh` |
| atuin | `curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh \| sh` |
| glow | GitHub release binary download |

### Via git clone (zsh plugins)

```
zsh-users/zsh-syntax-highlighting  → ~/.zsh-toolbox/plugins/
zsh-users/zsh-autosuggestions      → ~/.zsh-toolbox/plugins/
MichaelAquilina/zsh-you-should-use → ~/.zsh-toolbox/plugins/
```

---

## 6. init.zsh structure

```zsh
# PATH additions
export PATH="$HOME/.local/bin:$PATH"

# Starship (uses our config, not ~/.config/starship.toml)
export STARSHIP_CONFIG="$HOME/.zsh-toolbox/starship.toml"
eval "$(starship init zsh)"

# Zoxide (replaces cd)
eval "$(zoxide init zsh)"

# Atuin (replaces Ctrl-R history)
eval "$(atuin init zsh)"

# Direnv
eval "$(direnv hook zsh)"

# Plugins
source ~/.zsh-toolbox/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh-toolbox/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh-toolbox/plugins/zsh-you-should-use/you-should-use.plugin.zsh

# Aliases
source ~/.zsh-toolbox/aliases.zsh

# bat: Ubuntu ships as 'batcat', normalise
[[ -f ~/.local/bin/bat ]] || ln -sf "$(command -v batcat)" ~/.local/bin/bat

# fd: Ubuntu ships as 'fdfind', normalise
[[ -f ~/.local/bin/fd  ]] || ln -sf "$(command -v fdfind)"  ~/.local/bin/fd
```

---

## 7. aliases.zsh

```zsh
# eza (ls replacement)
alias ls='eza --icons'
alias ll='eza --icons --long --git'
alias la='eza --icons --long --git --all'
alias lt='eza --icons --tree'
alias lta='eza --icons --tree --all'

# bat as cat
alias cat='bat --paging=never'
```

---

## 8. Starship config (starship.toml)

Requirements:
- **Clearly distinguish host shell vs. container/Distrobox shell** — the most important visual cue
- Show git branch + status, podman context, python venv, java version
- Fast (no slow external calls)

### Container detection strategy

Starship has a built-in `container` module that reads `/run/host/container-manager`
and `/run/.containerenv` — both of which Distrobox sets. This will show a
container icon + name automatically when inside a Distrobox.

In addition, the prompt character (`character` module) will use a distinct color
or symbol inside a container so it's unmistakable at a glance.

```toml
"$schema" = 'https://starship.rs/config-schema.json'

format = """
$username$hostname$container$directory$git_branch$git_status\
$python$java$docker_context\
$fill\
$status$cmd_duration
$character"""

# ── Container indicator ──────────────────────────────────────────────────────
[container]
format  = '[$symbol \[$name\]]($style) '
symbol  = '⬡'
style   = 'bold yellow'

# ── Prompt character: green on host, yellow inside container ─────────────────
[character]
success_symbol = '[❯](bold green)'
error_symbol   = '[❯](bold red)'
# Inside a container the container module already provides strong visual signal;
# the character colour stays consistent (no separate override needed here).

# ── Directory ────────────────────────────────────────────────────────────────
[directory]
style            = 'bold cyan'
truncation_length = 4
truncate_to_repo  = true

# ── Git ──────────────────────────────────────────────────────────────────────
[git_branch]
symbol = ' '
style  = 'bold purple'

[git_status]
style    = 'bold red'
ahead    = '⇡${count}'
behind   = '⇣${count}'
diverged = '⇕⇡${ahead_count}⇣${behind_count}'
modified = '!${count}'
untracked = '?${count}'
staged   = '+${count}'

# ── Runtimes ─────────────────────────────────────────────────────────────────
[python]
symbol           = ' '
detect_files     = ['requirements.txt', 'pyproject.toml', '.python-version', 'Pipfile']
detect_extensions = ['py']

[java]
symbol        = ' '
detect_files  = ['pom.xml', 'build.gradle', '.java-version']
detect_extensions = ['java', 'class', 'jar']

[docker_context]
symbol       = ' '
detect_files = ['docker-compose.yml', 'docker-compose.yaml', 'Dockerfile']
only_with_files = true

# ── Right side / timing ───────────────────────────────────────────────────────
[fill]
symbol = ' '

[cmd_duration]
min_time = 2000
format   = '[$duration](bold yellow) '

[status]
disabled = false
format   = '[$status](bold red) '
```

---

## 9. zsh inside Distrobox containers

Since Distrobox mounts `$HOME`, `~/.zsh-toolbox/` is already visible inside
every container. The remaining requirement is the `zsh` binary.

**Recommended approach (Option A — explicit per Dockerfile):**

Add to any container `Dockerfile` where you want zsh:

```dockerfile
RUN apt-get install -y zsh && chsh -s /bin/zsh root
```

The `init.zsh` sourcing works automatically via the shared `$HOME` — no
additional wiring needed.

---

## 10. Deferred / future tools (not in v1)

Consider adding after zsh-toolbox is stable:

| Tool | Purpose |
|---|---|
| **tmux** | Session persistence across SSH disconnects |
| **mosh** | UDP-based SSH for flaky/mobile connections |
| **assh** | Templated `~/.ssh/config` with aliases and gateways |
| **delta** | Better `git diff` output (pairs with bat) |
| **lazygit** | TUI git interface |
| **yazi** | Terminal file manager with preview |
| **tldr** | Practical man page summaries |

SSH tools (`tmux`, `mosh`, `assh`) can live in a separate `apps/ssh-tools/`
host-install app, sharing the same install.sh convention.

---

## 11. Implementation order

1. Extend `tools.sh`: add host-install detection + branching in `cmd_setup`, `cmd_rm`, `cmd_list`
2. Write `apps/zsh-toolbox/install.sh`
3. Write `apps/zsh-toolbox/uninstall.sh`
4. Write `~/.zsh-toolbox/` template files (init.zsh, aliases.zsh, starship.toml)
5. Write `apps/zsh-toolbox/description`
6. Manual test: fresh install → verify prompt, all tools work
7. Manual test: uninstall → verify .zshrc restored, shell reverted, binaries gone
