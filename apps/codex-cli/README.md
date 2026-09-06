# codex-cli

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

A non-interactive setup skips the wizard and installs `latest`. Every setup
refreshes the installer layer, so rerunning the command picks up a newly
published stable release instead of reusing an older cached binary.

The wizard's second page offers two optional status lines — Codex's
[built-in bar](#status-line-optional) and the
[gruvbox powerline bar](#gruvbox-powerline-status-line-optional) rendered by tmux.
Leave both unticked to keep `~/.codex/` untouched.

## Commands

| Export | Type | Description |
|---|---|---|
| `codex` | `bin` | Codex CLI on the host `PATH` |
| `codex-tmux` | `bin` | Codex wrapped in tmux with the gruvbox status bar |
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

The setup wizard can configure Codex's built-in status line to show roughly the
same information as this repo's [Claude Code status line](../claude-code/README.md#status-line-optional):

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

**This is a config change, not a script.** Unlike Claude Code, Codex has no hook
for running a custom command and rendering its output — `tui.status_line` accepts
only an ordered list of built-in item identifiers. So it carries the same
*information* as the Claude Code bar, but not its powerline segments, rounded caps
or gruvbox palette; see [No custom text, glyphs or separators](#no-custom-text-glyphs-or-separators).

You can also configure it interactively inside Codex with `/statusline`.

### Available items

Pick any subset, in any order, by editing `tui.status_line` yourself. This is
the complete set as of Codex 0.153.4 — the identifiers are a closed enum in the
binary, so anything not listed here is rejected:

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

### No custom text, glyphs or separators

`tui.status_line` accepts only the identifiers above — there is no `custom`,
`text`, `command` or format-string variant, and the only other status-line key
in `[tui]` is the boolean `status_line_use_colors`. So **Nerd Font glyphs,
powerline separators and a custom palette are not achievable here**, however the
Claude Code bar is configured. Codex assembles the string itself, joins items
with a fixed ` · ` separator, and colors them from its own theme.

### Safety

Your config is never silently overwritten:

- `config.toml` is edited with `tomlkit`, so **comments, key order and formatting
  are preserved**.
- If it already has a *different* `tui.status_line`, the whole file is copied to
  `config.toml.bak-<timestamp>` first, and the previous items are printed.
- If the file exists but isn't valid TOML, the installer refuses and exits
  without writing anything.

Untick it (or run `codex-cli-install --tools ""`) to remove it again. The
`tui.status_line` key is dropped **only if it still matches what we wrote** — if
you've customised the list since, it's left alone. Other `[tui]` keys always
survive, and the `[tui]` table itself is removed only if emptying it left it bare.

## Gruvbox powerline status line (optional)

Codex cannot draw the powerline bar from
[`~/.claude/statusline.sh`](../claude-code/README.md#status-line-optional) —
see [No custom text, glyphs or separators](#no-custom-text-glyphs-or-separators).
So this renders the same bar *around* Codex, using tmux as the frame:

```
┌─ codex (fullscreen TUI) ─────────────────────────────┐
│  > explain this repository                           │
└──────────────────────────────────────────────────────┘
  ~/D/linux-tools   main ●2 ?4   #45 │ gpt-6-astra high   215.9k/258.4k 84%   5h 52% 4h10m   13:54
  └── tmux status bar: same palette, glyphs and geometry as the Claude Code one
```

Enable it by ticking **tmux-statusline** in the wizard, or directly:

```bash
distrobox enter codex-cli-box -- codex-cli-install --tools tmux-statusline
```

Then run Codex through the wrapper instead of `codex`:

```bash
codex-tmux                       # takes the same arguments as codex
codex-tmux resume
```

Detach with `C-\ d` (the prefix is `C-\`, not `C-b`, so it does not shadow
Codex's own key bindings). The session uses a private tmux socket (`-L codex`),
so it never touches your own tmux server, config or bindings.

### What it shows

Identical segments to the Claude Code bar, minus one and plus one:

| Segment | Source |
|---|---|
| OS icon, dir, git branch + status | host `/run/host/etc/os-release`, `git status --porcelain=v2` |
| PR number, coloured by review state | `gh pr view`, cached for 90s |
| model **+ reasoning effort** | rollout `turn_context` (Claude's bar has no effort field) |
| context window used | rollout `last_token_usage` / `model_context_window` |
| cache read/write | rollout `cached_input_tokens` / `cache_write_input_tokens` |
| 5h and 7d limits + reset countdown | rollout `rate_limits.primary` / `.secondary` |
| user@host (ssh/root only), clock | same as the Claude Code bar |

The `agent` segment is dropped — Codex has no equivalent.

Live token and rate-limit numbers come from the session's rollout file under
`~/.codex/sessions/`, which is the only machine-readable source Codex exposes.
Two consequences worth knowing:

- Numbers update when Codex writes a `token_count` record, i.e. per turn — not
  continuously. A brand-new session shows dir/branch/PR only until its first
  turn completes.
- The active rollout file is identified as the newest one written since the
  wrapper started. Running two `codex-tmux` sessions at once will point both
  bars at whichever wrote most recently.

### Narrow terminals

The full bar is about 147 columns. Below that it drops whole segments rather
than letting tmux clip mid-segment, in this order: cache → user@host → 7d
limit → clock → 5h limit. Model and context window are never dropped, so the
floor is roughly 84 columns.

### Using it with the built-in bar

The two are independent and you can enable both, but Codex draws its bar inside
its own frame and tmux draws this one below it, so you get two. To use only this
one, leave **statusline** unticked (or set `tui.status_line = []`). The installer
prints a note if it sees both.

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
| `~/.codex/` | Auth, sessions, history |
| `~/.codex/.linux-tools-statusline` | Marker recording the items we set (see notes) |
| `~/.codex/codex-statusline.sh` | Gruvbox bar renderer, installed by the wizard |
| `~/.codex/codex-tmux.conf` | tmux config used by `codex-tmux` |
| `~/.codex/sessions/` | Per-session rollout files (the bar's data source) |

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

- **The status line needs a reasonably current Codex.** `tui.status_line` as an
  item list is a recent addition — older builds only had a simpler on/off form.
  If the key seems to do nothing, check `codex --version` and rebuild.
- The marker file at `~/.codex/.linux-tools-statusline` exists because the setup
  wizard detects installed integrations by file existence and cannot inspect a
  TOML key. Deleting it makes the wizard show the status line as not installed;
  it does not change your Codex config.
