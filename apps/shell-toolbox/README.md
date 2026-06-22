# shell-toolbox

A **host-only** installer for Zsh and a curated set of modern shell utilities.

Unlike every other app in this repo, nothing runs inside the container at runtime — the Distrobox box is used purely as a portable download/build environment. Zsh is installed on the host via its package manager; all utilities land in `~/.local/bin` as static musl binaries; configuration is written under `~/.config/zsh/`.

## Install

```bash
tools setup shell-toolbox
```

The interactive wizard (`wizard/00-tools.packages`) lets you pick which tools to install. Re-running is idempotent: deselected tools are removed, selected ones are (re)installed, and the managed config is regenerated.

When upgrading from `zsh-box`, setup automatically removes the obsolete
`zsh-box-box` container and image. Host-installed tools and shared-home data are
preserved, and the installer migrates the managed `.zshrc` source line.

You can also call the installer directly from inside the box:

```bash
shell-toolbox-install --tools "fzf bat eza zoxide starship"
```

After install, set Zsh as your default shell and open a new terminal:

```bash
chsh -s $(which zsh)
```

## Config layout

Configuration is split into a **tool-owned** part and a **user-owned** part so re-runs never clobber your edits:

| Path | Owner | Behavior |
|---|---|---|
| `~/.config/zsh/shell-toolbox.zsh` | **shell-toolbox** | Fully regenerated on every run. Carries a `DO NOT EDIT` header. Holds core options, history, completion, keybindings, plugin sourcing, the `conf.d` loader, and the prompt. |
| `~/.zshrc` | **you** | Written **once** as a thin loader that `source`s `shell-toolbox.zsh`, then never overwritten. Add your own customizations below the source line — they survive re-runs. |
| `~/.config/zsh/conf.d/NN-tool.zsh` | **shell-toolbox** | Per-tool init snippets (aliases, env, `eval "$(tool init zsh)"`), sourced in order by the glob loop in `shell-toolbox.zsh`. Removed automatically when a tool is deselected. |

If you already had a `~/.zshrc` that predates this layout, the installer backs it up to `~/.zshrc.bak.YYYYMMDD-HHMMSS` and appends the single `source` line rather than overwriting your file.

## Storage paths

| Path | Contents |
|---|---|
| `~/.local/bin/` | Tool binaries (`fzf`, `bat`, `eza`, `rg`, `fd`, `delta`, …) |
| `~/.local/share/zsh/plugins/` | `zsh-syntax-highlighting`, `zsh-autosuggestions` (cloned, no plugin manager) |
| `~/.local/share/zsh/completions/` | Generated tool completions (e.g. `_zellij`), autoloaded via `$fpath` |
| `~/.config/zsh/` | `shell-toolbox.zsh` + `conf.d/` fragments |
| `~/.config/starship.toml` | Starship prompt config (`gruvbox-rainbow` preset; written only if absent) |
| `~/.local/state/zsh/history` | Command history |
| `~/.cache/zsh/` | `compinit` dump |

## Included tools

Shell plugins: `zsh-syntax-highlighting`, `zsh-autosuggestions`.

Utilities: `fzf`, `bat`, `eza`, `ripgrep` (`rg`), `fd`, `delta`, `zoxide`, `atuin`, `starship`, `glow`, `tealdeer` (`tldr`), `yazi`, `lazygit`, `dust`, `zellij`, `direnv`.

All utilities are downloaded as static musl binaries from their GitHub release pages, so they run on any Linux host regardless of glibc version.

## Notes

- **Host package manager** is used only for Zsh itself (apt / dnf / pacman / zypper, auto-detected from `/etc/os-release`) so the shell registers in `/etc/shells` and `chsh` works.
- **No plugin manager** — plugins are plain `git clone`s sourced directly.
- Re-run `tools setup shell-toolbox` (or `shell-toolbox-install --tools "…"`) any time to add/remove tools or pull updated binaries.
- `zsh-install` remains available as a compatibility alias for the renamed installer.
