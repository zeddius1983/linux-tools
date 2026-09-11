# codex-cli

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/Ubuntu-tested-brightgreen?logo=ubuntu&logoColor=white">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/Linux_Mint-tested-brightgreen?logo=linuxmint&logoColor=white">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/CachyOS-untested-lightgrey?logo=archlinux&logoColor=white">
</p>

[OpenAI Codex CLI](https://developers.openai.com/codex/cli) packaged in an
Ubuntu Distrobox and exported as both a host command and a terminal launcher.
The image also includes Git, GitHub CLI (`gh`), and Bubblewrap.

## Install

```bash
tools setup codex-cli
```

Interactive setup opens a release picker. Choose `latest` (the default) to
follow OpenAI's stable standalone-installer channel, or pin one of the ten most
recent stable releases. The release list is read from the official
`openai/codex` tags at setup time.

Each version's release notes are shown beside the picker (`PgDn`/`PgUp` scrolls
them); `latest` shows the newest stable release's, labelled with the tag it
resolves to.

A non-interactive setup skips the wizard and installs `latest`. Every setup
refreshes the installer layer, so rerunning the command picks up a newly
published stable release instead of reusing an older cached binary.

The wizard's second page offers two optional status lines — Codex's
[built-in bar](#status-line-optional) and a
[styled powerline bar](#powerline-status-bar-optional). Leave both unticked to
keep `~/.codex/` untouched.

## Commands

| Export | Type | Description |
|---|---|---|
| `codex` | `bin` | Codex CLI on the host `PATH` |
| `codex-tmux` | `bin` | *Optional.* Codex with the [powerline status bar](#powerline-status-bar-optional). Added only if you tick **tmux-statusline** in the wizard, and removed if you untick it |
| `Codex CLI` | `desktop` | Codex in a terminal from the app menu |

Examples:

```bash
# Start an interactive session in the current repository
codex

# Run one non-interactive task
codex exec "Explain this repository"

# Resume a saved session
codex resume

# Check the packaged version
codex --version
```

## Status line (optional)

The setup wizard can turn on Codex's own status line, showing:

```
project · branch · #PR · model · context used · 5h limit · weekly limit
```

Enable it by ticking **statusline** in the wizard during `tools setup codex-cli`,
or apply it directly:

```bash
distrobox enter codex-cli-box -- codex-cli-install --tools statusline
```

It sets `tui.status_line` in `~/.codex/config.toml` (the shared `$HOME`, so it
applies on the host too) to:

```toml
[tui]
status_line = [
    "project-name",
    "git-branch",
    "pull-request-number",
    "model",
    "context-used",
    "five-hour-limit",
    "weekly-limit",
]
```

Codex draws this bar itself, so its colours and spacing come from the Codex
theme and are not configurable. You can change *which* items appear, and in
what order — either by editing the list below, or interactively inside Codex
with `/statusline`. If you want a styled bar instead, see
[Powerline status bar](#powerline-status-bar-optional).

### Available items

Pick any subset, in any order, by editing `tui.status_line` yourself. This is
everything Codex accepts as of 0.153.4; anything else is rejected:

| Item | Shows |
|---|---|
| `model`, `model-with-reasoning`, `reasoning` | Model name, optionally with reasoning level |
| `current-dir`, `project-name` | Working directory, project root |
| `git-branch`, `pull-request-number`, `branch-changes` | Branch, open PR number, diff vs default branch |
| `run-state` (alias `status`) | Ready / Working / Thinking |
| `permissions`, `approval-mode` | Sandbox profile, approval mode |
| `context-used`, `context-remaining`, `context-window-size` | Context window |
| `five-hour-limit`, `weekly-limit` | Usage limits |
| `thread-credits`, `estimated-thread-cost` | Credits left, estimated cost of this thread |
| `used-tokens`, `total-input-tokens`, `total-output-tokens` | Token counts |
| `codex-version`, `thread-id`, `thread-title` | Session metadata |
| `fast-mode`, `raw-output` | Mode flags |
| `task-progress`, `workspace-headline` | Plan progress, notifications |

Items with no value are omitted rather than rendered empty. Setting
`tui.status_line = []` or removing the key disables the bar.

`[tui].terminal_title` takes identifiers from this same set, if you want your
terminal's title bar driven by it too.

You cannot add your own text, icons or separators to this bar — it is built
from the items above and nothing else.

### Safety

Your config is never silently overwritten:

- **Comments, key order and formatting are preserved** — the file is edited in
  place, not rewritten.
- If it already has a *different* `tui.status_line`, the whole file is copied to
  `config.toml.bak-<timestamp>` first, and the previous items are printed.
- If the file exists but isn't valid TOML, the installer refuses and exits
  without writing anything.

Untick it in the wizard to turn it off again. The `tui.status_line` key is
removed **only if it still matches what the wizard set** — if you have edited
the list since, it is left alone. Your other `[tui]` settings are never touched.

## Powerline status bar (optional)

A styled status bar with a gruvbox palette and Nerd Font icons, drawn beneath
Codex:

```
  > explain this repository
  ...codex, fullscreen...
────────────────────────────────────────────────────────────────────────────────
  ~/D/linux-tools   main ●2 ?4   #45   gpt-6-astra high   215.9k/258.4k 84%   5h 52% 4h10m   13:54
```

Codex cannot style its own bar, so this one is drawn around it by tmux: a rule
and the bar, taking two terminal rows. It needs a Nerd Font in your terminal
for the icons and separators.

Enable it by ticking **tmux-statusline** in the wizard, or directly:

```bash
distrobox enter codex-cli-box -- codex-cli-install --tools tmux-statusline
```

Then start Codex with `codex-tmux` instead of `codex`:

```bash
codex-tmux                       # takes the same arguments as codex
codex-tmux resume
```

Detach with `C-\ d`. The prefix is `C-\` rather than tmux's usual `C-b` so it
does not shadow Codex's own keys, and the session is kept separate from any
tmux server of your own.

The mouse wheel scrolls, as it does when you run Codex directly. Codex has no
scroll keys for the main view — `↑`/`↓` move through your input history,
shell-style. Use `Ctrl`+`T` to open the transcript, which is scrollable.

Every other key belongs to Codex; the wrapper only adds `C-\` as the tmux
prefix.

### What it shows

| Segment | Shows |
|---|---|
| OS icon and directory | Your distro, and the working directory |
| Branch | Current branch, changed and untracked file counts, ahead/behind |
| PR | Open pull request for the branch, coloured by review state |
| Model | Model name and reasoning effort |
| Context | Context window used, of the total |
| Cache | Cache hit rate, tokens read and written |
| 5h / 7d | Usage remaining, and time until each limit resets |
| Clock | Current time |

Token and usage numbers refresh once per turn rather than continuously, so a
new session shows the directory, branch and PR until its first turn finishes.

Running two `codex-tmux` sessions at once is not supported: both bars will
follow whichever session was most recently active.

### Narrow terminals

The full bar needs about 147 columns. Below that it drops segments in order —
cache, then user@host, the weekly limit and the clock — rather than truncating.
The model and context window always stay.

### Using both bars

The two status lines are independent. If you enable both, Codex draws its own
inside its frame and tmux draws this one below it, so you see two. To use only
this one, leave **statusline** unticked, or set `tui.status_line = []`.

## Configuration and storage

Distrobox shares the host home directory with the container. Codex therefore
keeps authentication, configuration, sessions, plugins, and other state under
the usual host path:

```text
~/.codex/
```

| Path | Contents |
|---|---|
| `~/.codex/config.toml` | Codex configuration, including `tui.status_line` |
| `~/.codex/sessions/` | Session history |
| `~/.codex/.linux-tools-statusline` | Records which status line items were set (see notes) |
| `~/.codex/codex-statusline.sh` | Powerline bar renderer, added by the wizard |
| `~/.codex/codex-tmux.conf` | tmux settings for `codex-tmux`, added by the wizard |
| `~/.local/bin/codex-tmux` | The `codex-tmux` command, added by the wizard |

The container can also see repositories and files under the host home
directory. Its system packages and `/usr/bin/codex` remain isolated in
`codex-cli-box`.

## Updating or changing versions

Run setup again and select a release:

```bash
tools setup codex-cli
```

This replaces the existing box and image while preserving `~/.codex/` in the
shared home directory. Prefer this flow over `codex update` inside the box:
the exported host wrapper launches the image's `/usr/bin/codex`, which is not
writable by the container user, so an in-container self-update would not
replace the packaged executable.

If the release picker cannot reach GitHub, it still offers `latest`; the
Dockerfile then resolves that through OpenAI's installer.

## Shell access

```bash
tools enter codex-cli
distrobox enter codex-cli-box
```

## Notes

- **The built-in status line needs a reasonably current Codex.** Choosing which
  items it shows is a recent addition; older builds only had a simple on/off
  form. If `tui.status_line` seems to do nothing, check `codex --version` and
  re-run setup.
- **The powerline bar needs a Nerd Font** in your terminal. Without one the
  icons and separators show as missing-glyph boxes.
- Deleting `~/.codex/.linux-tools-statusline` makes the wizard show the built-in
  status line as not enabled. It does not change your Codex config.
