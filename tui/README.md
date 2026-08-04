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

## Footer

Two lines. The first is context for the selected app — its image reference
(or "installs to the host") and the commands it exports — and is taken over by
the filter prompt while filtering, or by the result of the last action. The
second is the key legend.

## Selection

The selected row is marked by a background running the full table width, not a
leading arrow. Each segment keeps its own foreground so state colour stays
readable, and only gains the background — wrapping an already-styled string
would be cut short by its own resets.

## Keys

| Key | Action |
|---|---|
| `↑`/`k` `↓`/`j` | move selection |
| `←`/`h` `→`/`l`, `tab`/`shift+tab` | previous / next category |
| `g` / `end` | first / last row |
| `PgDn` / `PgUp` | scroll the README panel |
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

Shows only the rendered `apps/<name>/README.md` — image and box state live in
the table columns, so repeating them here would just cost README rows. Rendered
with Glamour, cached per app and width, scrollable. Apps without a README show a
placeholder — currently 9 of 23 apps have none, even though `CLAUDE.md`
requires one.

## Running from inside a container

The binary targets the host, where `podman`, `distrobox` and `tools` are on
PATH. Run from inside a Distrobox container none of them exist, and
`exec.Command` just fails — which showed every app as "not built" with no error.

It now detects containerisation (`/run/.containerenv`, `/.dockerenv`, or
`$CONTAINER_ID`) and routes those commands through `distrobox-host-exec`. The
footer says `via distrobox-host-exec` when that is active, so it is never a
silent mode.

## Platform glyph

Each app carries a one-cell glyph beside its name saying where it runs:

| App kind | Glyph |
|---|---|
| containerised (20 of 23) | Docker (`--ascii`: `◆`) |
| host-only (`shell-toolbox`, `nvidia-acs-service`, `nvidia-cdi-service`) | the host distro's logo, e.g. Mint (`--ascii`: `⌂`) |

Host-only apps also show a dim `─` in IMAGE and BOX — distinct from `✗ —`,
which means "could be built, is not".

It sits with the name rather than in its own column because it is a fixed
property of the app, not live state like IMAGE and BOX.

Every glyph — tab bar and rows alike — uses one colour (gruvbox blue,
`colGlyph` in `main.go`) so they read as a set. The shape already distinguishes
container from host, so colour only has to make them legible. The active tab
keeps its inverted styling, since a blue glyph on the accent background would
lose contrast.

All glyphs come from the `nf-linux` block (U+F300–F32F), including the Docker
logo, so they share a weight. Do **not** substitute `nf-md-docker` (U+F0868) to
get a heavier icon: it lives in a supplementary plane, and terminals render
those PUA codepoints double-width even though wcwidth — and so
`lipgloss.Width` — reports 1, which shifts every column right of it by a cell.

The host distro comes from os-release. Inside a Distrobox container
`/etc/os-release` describes the *container* (ubuntu), so
`/run/host/etc/os-release` is read first. Distros with no logo of their own
(CachyOS, EndeavourOS, …) fall back through `ID_LIKE` to a parent distro, and
anything still unresolved — including a completely failed detection — falls
back to the generic Tux glyph.

Nerd Font glyphs are written as explicit `\u` escapes rather than pasted
literals: they live in the Unicode private-use area and silently become empty
strings when they pass through tooling that does not preserve it. That is
exactly how the Docker glyph was lost once; there is now a test asserting no
glyph is empty.

## Icons

Nerd Font glyphs are used for category tabs and image state by default, as
gh-dash does. They render as tofu without a patched font, so `--ascii` swaps in
plain Unicode (`✓`, `✗`) instead. Run/stop dots (`●`/`○`) are plain Unicode in
both modes.

Tab counts are Unicode superscripts (`Development⁷`). For gh-dash's
parenthesised style instead, change `superscript()` in `main.go`.

## Categories

Read from `apps/<name>/category`, one line per app. Missing ⇒ `Other`.
Preferred tab order is in `Categories()` in `apps.go`; unknown names are
appended alphabetically.

## Status

| Piece | State |
|---|---|
| category tabs with counts | done |
| app table, terminal-width columns | done — no fixed 26-char budget |
| info panel: rendered README, scrollable | done |
| IMAGE / BOX table columns with glyphs | done |
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
