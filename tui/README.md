# tools-tui — dashboard front-end (prototype)

A `gh-dash`-style dashboard for linux-tools: category tabs, an app table, and a
right-hand info panel showing the selected app's README as rendered markdown.
Built on the same stack gh-dash uses — Bubble Tea v2, Lip Gloss v2, Glamour v2.

Apps are listed by their `description` (e.g. "Dev Toolbox"), not their directory
name; the directory name remains the identity used for commands and paths, and
is what the footer and every action refer to.

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

# render the wizard for an app instead of the dashboard
./tui/tools-tui --apps-dir apps --render --render-app lmstudio --render-wizard setup
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

Keys: `space` toggle/select, `a`/`n` all/none, `↑`/`↓` move, `⏎` next page or
review, `esc` back a page (and out of the wizard from the first), `q` cancel.

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
| `cmd_install` building the binary | not started |
| wiring `tools` to launch it | not started |

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
