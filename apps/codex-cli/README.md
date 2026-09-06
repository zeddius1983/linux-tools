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

The wizard's second page offers the optional [status line](#status-line-optional);
leave it unticked to keep `~/.codex/config.toml` untouched.

## Commands

| Export | Type | Description |
|---|---|---|
| `codex` | `bin` | Codex CLI on the host `PATH` |
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
