# tools-tui — dashboard front-end (prototype)

A `gh-dash`-style dashboard for linux-tools: category tabs, an app table, and a
right-hand info panel showing the selected app's README as rendered markdown.
Built on the same stack gh-dash uses — Bubble Tea v2, Lip Gloss v2, Glamour v2.

Apps are listed by their `description` (e.g. "Dev Toolbox"), not their directory
name; the directory name is shown in the info panel as `dir`, since that is what
commands and paths use.

See [`docs/tui-migration.md`](../docs/tui-migration.md) for the design.

**Not wired in.** `tools` still opens the whiptail menu; this binary must be run
directly.

## Build

Needs the Go toolchain from `dev-toolbox` (`tools setup dev-toolbox`, select
`go`):

```bash
cd tui
CGO_ENABLED=0 go build -o tools-tui .
go test ./...
```

`CGO_ENABLED=0` matters — it produces a static binary that runs on the host
without linking the container's glibc.

## Run

```bash
./tui/tools-tui --apps-dir apps

# print one frame and exit; no tty needed, useful for layout checks
./tui/tools-tui --apps-dir apps --render --render-width 104

# render with a specific app selected
./tui/tools-tui --apps-dir apps --render --render-app dev-toolbox
```

## Keys

| Key | Action |
|---|---|
| `↑`/`k` `↓`/`j` | move selection |
| `←`/`h` `→`/`l`, `tab`/`shift+tab` | previous / next category |
| `g` / `end` | first / last row |
| `J`/`K`, `pgdn`/`pgup` | scroll the README panel |
| `/` | filter within the category |
| `s` `b` `c` `e` `r` | setup · build · create · export · rm |
| `⏎` | open a shell in the box |
| `R` | reload app and container state |
| `?` | toggle help |
| `q` / `esc` | quit |

## How actions run

Actions use `tea.ExecProcess`: the dashboard suspends, the bash backend gets the
real terminal so podman output streams normally, and the dashboard resumes and
refreshes container state when the command exits. It does not exec away.

Because bash sees a real tty, `tools setup` still runs its **existing whiptail
wizard**. Native wizard pages are the next step; the Go-side state-file bridge
(`state.go`, `wizard.go`, and `wizard_load_state` in `lib/wizard.sh`) is
already in place and tested for when they land.

## Info panel

Renders `apps/<name>/README.md` with Glamour. Results are cached per app and
width. Apps without a README show a placeholder — currently 9 of 23 apps have
none, even though `CLAUDE.md` requires one.

## Categories

Read from `apps/<name>/category`, one line per app. Missing ⇒ `Other`.
Preferred tab order is in `Categories()` in `apps.go`; unknown names are
appended alphabetically.

## Status

| Piece | State |
|---|---|
| category tabs with counts | done |
| app table, terminal-width columns | done — no fixed 26-char budget |
| info panel: metadata + rendered README | done |
| filter, help overlay, footer | done |
| actions via `ExecProcess` + state refresh | done |
| native wizard pages (multi-select, select) | not started — bash whiptail still handles these |
| state-file bridge to bash | built and tested, not yet used by the dashboard |
| `cmd_install` building the binary | not started |
| wiring `tools` to launch it | not started |

## Files

| File | Contents |
|---|---|
| `main.go` | model, update loop, rendering, theme |
| `apps.go` | app discovery, categories, podman/distrobox state |
| `wizard.go` | parser for the wizard page format |
| `state.go` | state file rendering and shell quoting |
