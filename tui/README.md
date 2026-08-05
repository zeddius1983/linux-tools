# tools-tui — dashboard front-end (prototype)

A `gh-dash`-style dashboard for linux-tools: category tabs, an app table, and a
right-hand info panel showing the selected app's README as rendered markdown.
Built on the same stack gh-dash uses — Bubble Tea v2, Lip Gloss v2, Glamour v2.

Apps are listed by their `description` (e.g. "Dev Toolbox"), not their directory
name; the directory name remains the identity used for commands and paths, and
is what the footer and every action refer to.

See [`docs/tui-migration.md`](../docs/tui-migration.md) for the design.

**This is what `tools` opens.** With the binary built and `LT_NO_GO_TUI` unset,
`tools` (no arguments) launches the dashboard; otherwise it falls back to the
whiptail menu, which is still there and still works.

| Variable | Effect |
|---|---|
| `LT_NO_GO_TUI=1` | force the whiptail menu |
| `LT_TUI_ASCII=1` | plain Unicode markers instead of Nerd Font glyphs |
| `LT_TUI_NO_MOUSE=1` | no mouse reporting, so the terminal keeps text selection |

## Build

`tools install` builds the binary, and `tools build-tui` rebuilds it on demand.
Neither needs a Go toolchain on the host — the build walks a ladder so that Go
never becomes a dependency of using linux-tools:

| Rung | Condition | Cost |
|---|---|---|
| reuse | binary newer than every `*.go`, `go.mod`, `go.sum` | 0 |
| host Go | `go` on PATH (e.g. exported from `dev-toolbox`) | ~0.5s |
| container | a container runtime | 13s first ever, ~1s after |
| skip | neither | whiptail menu, unchanged |

The container rung runs `golang:1.25-alpine` (228 MB, pulled once) with
`/go` on a named volume — `linux-tools-go-cache` — so the 58 MB of module
downloads and the build cache survive between runs. Failures are never fatal:
every one of them leaves the whiptail menu working.

To force a rebuild, delete the binary: `rm tui/tools-tui && tools build-tui`.

Building by hand is still just:

```bash
cd tui
CGO_ENABLED=0 go build -o tools-tui .
go test ./...
```

`CGO_ENABLED=0` is not optional — it produces a static binary, which is what
lets an alpine/musl container build run on a glibc host.

## Run

```bash
tools                     # the normal way in

# or directly, which is what the gate does
./tui/tools-tui --apps-dir apps

# print one frame and exit; no tty needed, useful for layout checks
./tui/tools-tui --apps-dir apps --render --render-width 104

# render with a specific app selected
./tui/tools-tui --apps-dir apps --render --render-app dev-toolbox

# render the wizard for an app instead of the dashboard
./tui/tools-tui --apps-dir apps --render --render-app lmstudio --render-wizard setup
```

## Footer

Two lines. The first is context for the selected app — its image reference
(or "installs to the host") and the commands it exports — and is taken over by
the filter prompt while filtering, or by the result of the last action. A status
message is cleared by the next keypress; it occupies a line that is otherwise
useful, so it must not become permanent. The second line is the key legend.

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
| wheel | scroll the pane under the pointer — README on the right, app list on the left |
| `/` | filter within the category |
| `⏎` / `s` | setup — the primary action: wizard, then the review screen |
| `b` `c` | build · create (wizard first when the app has pages for them) |
| `e` `r` | export · rm — run immediately |
| `o` | open a shell in the box |
| `R` | reload app and container state |
| `?` | toggle help |
| `q` / `esc` | quit |

## How actions run

Actions use `tea.ExecProcess`: the dashboard suspends, the bash backend gets the
real terminal so podman output streams normally, and the dashboard resumes and
refreshes container state when the command exits. It does not exec away.

## Wizard

`⏎`/`s`, `b` and `c` open the app's wizard pages natively (`wizardui.go`) when
it has any that declare that action. Every one of them ends at a review screen,
and setup shows that screen even for an app with no pages at all — it removes
the existing image and box before rebuilding, which is worth one keypress
rather than none. `b` and `c` are additive, so without pages they run straight
away. Answers are written to a state file and handed to bash as
`LT_SKIP_WIZARD=1 LT_WIZARD_STATE=<path>`, which `wizard_load_state`
(`lib/wizard.sh`) re-hydrates into `_WIZARD_SELECTIONS` so every existing
consumer — the apply handlers, `wizard_build_args`, `wizard_create_variant` —
works unchanged. Without those variables bash asks its own whiptail pages, so
the old path is still there for a scripted `tools setup`.

| Page type | Widget | Result |
|---|---|---|
| `.packages` | checklist, pre-ticked from each item's detect path | `PAGE_<name>` → the app's `-install --tools` run |
| `.mcp` | checklist | `PAGE_<name>` → `claude mcp add/remove` |
| `.buildarg` | single choice, items from the page's `items-cmd` | `BUILD_ARGS` → `--build-arg NAME=value` |
| `.runtime` | single choice | `VARIANT` → `create_flags.<value>` |

A `.buildarg` page's `items-cmd` reaches the network (a GitHub API call, a
`git ls-remote`), so it runs off the update loop with a 30s timeout, and Enter
is held while it is in flight. If it produces nothing the page is left
unanswered and the build keeps its Dockerfile default — the same outcome as the
bash path.

Ticked state is what will exist *after* the run, not what to add: unticking an
already-installed tool removes it. The review screen before the run spells that
out as a `+`/`-` diff, mirroring `tui_confirm_wizards`.

Deselecting everything on a page is an answer, not an absence — the page is
still written, with an empty value, so the apply handler removes what is
installed. `wizard_load_state` therefore tests each `PAGE_` variable for being
*defined* rather than non-empty.

A review screen with no pages behind it hands bash nothing — no state file — so
that run is an ordinary `tools setup <app>`.

### The state file

Written under `$XDG_CACHE_HOME`/`~/.cache/linux-tools/wizard/`, in a `0700`
directory, with a random name created `O_EXCL` and mode `0600`, and deleted once
the run finishes. Two reasons it lives there rather than in `/tmp` or
`$XDG_RUNTIME_DIR`:

- **bash sources it.** A predictable path in a world-writable directory is a way
  for another local user to run commands as whoever is using the dashboard.
- **`$HOME` is the one thing Distrobox shares.** `/tmp` inside a container is not
  the host's `/tmp`, so a state file written there is invisible to the backend —
  which would mean a setup that rebuilds the app while discarding every answer.

That last failure is also guarded on the bash side: `wizard_require_state`
aborts when `LT_SKIP_WIZARD` is set and no state can be loaded, rather than
falling through to a default build.

Keys: `space` toggle/select, `a`/`n` all/none, `↑`/`↓` move, `⏎` next page or
review, `esc` back a page (and out of the wizard from the first), `q` cancel.

## Mouse

The wheel scrolls whichever pane the pointer is over: the README on the right,
the app list on the left. In a wizard it moves the cursor; toggling still takes
a keypress, since a wheel click is too easy to fire by accident on a screen
where every row changes what gets installed.

Over the app list one notch is one row. Terminals report a physical notch as a
burst of events — usually three — which moved the selection several apps at a
time, so events closer together than `wheelNotch` (60ms, `main.go`) in the same
direction count as one. Reversing direction is never part of a burst. The
README panel is deliberately left un-coalesced: there a burst just scrolls the
page at a natural speed.

Mouse reporting is a `View` property in Bubble Tea v2 (`MouseMode`), set
alongside `AltScreen` in `altView()`. It is on by default, and the cost is that
the terminal no longer owns the wheel or drag — selecting text needs Shift in
most terminals. `--no-mouse` gives that back.

## Info panel

Takes half the terminal width. The only thing that overrides that is the
table's own 30-column minimum (`minTableWidth` in `main.go`), which bites below
about 66 columns — the panel gives width back rather than let the table header
wrap.

Below 73 columns (`minTableWidth + dividerWidth + minPanelWidth`) the panel is
dropped entirely and the table spans the full width. A README wrapped into 30-odd
columns is a stack of fragments, and the space is worth more as table; the
footer stops offering `PgDn`/`PgUp` when there is nothing to scroll.

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
`$CONTAINER_ID`) and routes those commands through `distrobox-host-exec` —
including a wizard page's `items-cmd`, which then runs where the build will.

## Platform glyph

Each app carries a one-cell glyph beside its name saying where it runs:

| App kind | Glyph |
|---|---|
| containerised (20 of 23) | Docker (`--ascii`: `◆`) |
| host-only (`shell-toolbox`, `nvidia-acs-service`, `nvidia-cdi-service`) | the host distro's logo, e.g. Mint (`--ascii`: `⌂`) |

## State columns

IMAGE and BOX are glyph-only — two states and three respectively, few enough
that a word adds nothing:

| Column | Glyph | Meaning |
|---|---|---|
| IMAGE | `✓` | image built |
| IMAGE | `✗` | not built |
| BOX | `●` | box exists and is running |
| BOX | `○` | box exists, stopped |
| BOX | `✗` | no box |
| either | *(blank)* | host-only app — it has neither |

`?` shows this legend in the app. Every value is one cell, so the glyphs align
down the column by construction; the footer names the image reference in full
for the selected row.

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
| native wizard pages (checklist, single choice, review) | done — whiptail is no longer reached from here |
| state-file bridge to bash | done, and now used by the wizard |
| `cmd_install` building the binary | done — ladder, never fatal |
| wiring `tools` to launch it | done — behind `LT_NO_GO_TUI` |
| retiring `lib/tui.sh` | not yet: it is the fallback |

## Files

| File | Contents |
|---|---|
| `main.go` | model, update loop, rendering, theme |
| `apps.go` | app discovery, categories, podman/distrobox state |
| `wizard.go` | parser for the wizard page format |
| `wizardui.go` | wizard session: pages, review screen, state hand-off |
| `state.go` | state file rendering and shell quoting |
| `info.go` | README panel (Glamour), cached per app and width |
| `icons.go` | glyph sets, including the `--ascii` fallback |
| `platform.go` | host distro detection and platform glyphs |
| `host.go` | routing commands through `distrobox-host-exec` |
