# Design: replacing the whiptail TUI with a Go dashboard

**Status:** prototype built — see [`tui/`](../tui). Not wired in: `tools` still
opens whiptail.
**Scope:** `lib/tui.sh`, `lib/wizard.sh`, `tools.sh` dispatch, `cmd_install`
**Non-goals:** changing `lib/commands.sh` behaviour, changing what any app installs

Roadmap entry: see *Tooling / Infrastructure* in [`ROADMAP.md`](../ROADMAP.md).

> **This document was revised after the prototype.** The original plan was
> Go + [`huh`](https://github.com/charmbracelet/huh) replacing whiptail's
> dialogs one-for-one. The target became a `gh-dash`-style dashboard, which huh
> cannot express. §3 and §5 record the decision that replaced it. §2 is
> unchanged, because it proved correct.

---

## 1. Why

The `whiptail` front-end works, but its limits have started dictating things
outside itself.

**Rendering limits leaking into project policy.** `_fw` (`lib/tui.sh:31`) pads
and truncates every menu row to fixed 26/34-column fields because whiptail has
no table support. That 26-character budget is written into `CLAUDE.md` as a rule
every new app must follow.

**A fragile selection round-trip.** The rendered detail line doubles as the
whiptail menu *tag*, and the selected line is mapped back to an app name through
`detail_to_app` (`lib/tui.sh:71-86`). Two apps with an identical description
*and* identical status render byte-identical rows and collide silently.

**No search, no multi-select, no categories.** 23 apps in a flat 10-row window,
arrow keys only.

**Wrong dependency hint.** `lib/tui.sh:58` hardcodes `sudo apt install whiptail`
even though the repo supports Arch-family hosts via `host_distro_family`.

**Theme fights.** The 16-colour `NEWT_COLORS` block (`lib/tui.sh:1-27`)
approximates the palette with `brown`/`lightgray` and still loses contrast.

**Esc does not quit.** newt swallows single-`Esc`.

> Correction: the roadmap entry claimed huh gives single-`Esc`-to-quit for free.
> It does not — huh v0.7.0 binds Quit to `ctrl+c` only, declares it with no help
> string, and does not bind Esc at all. Any front-end needs an explicit keymap.

---

## 2. The core problem: wizard state crosses a process boundary

Wizard answers live in `_WIZARD_SELECTIONS`, a bash associative array
(`lib/wizard.sh:24`), and are read at four points — two inside the backend this
migration is supposed to leave alone:

| Consumer | Defined at | Called from | Needs |
|---|---|---|---|
| `tui_confirm_wizards` | `lib/wizard.sh:230` | `tools.sh:76` | selections + detect state → diff |
| `wizard_build_args` | `lib/wizard.sh:210` | `cmd_build`, `lib/commands.sh:9` | `--build-arg NAME=value` |
| `wizard_create_variant` | `lib/wizard.sh:187` | `cmd_create`, `lib/commands.sh:41` | `create_flags.<variant>` |
| `tui_apply_wizards` | `lib/wizard.sh:310` | `tools.sh:80` | post-action `distrobox enter … --tools` |

Any front-end that collects answers and then invokes `tools setup <app>` starts
a **new bash process with an empty array** — the build arg and the runtime
variant vanish silently, with no error. An explicit serialization contract is
therefore mandatory, and defining it is the real work.

**This held up, and the fix was cheaper than predicted.** `wizard_load_state`
sources a flat `KEY=value` file and re-hydrates `_WIZARD_SELECTIONS` from it, so
every existing consumer works **unchanged**. This document originally assumed
`wizard_build_args` and `wizard_create_variant` would collapse into readers of
the new file; they did not have to change at all.

```sh
APP="fastflowlm"
ACTION="setup"
BUILD_ARGS="--build-arg FLM_REF=v0.9.12"
VARIANT="nvidia"
PAGE_00_statusline="statusline"
```

Go is the **sole parser** of the wizard page format — three different body
grammars share one file convention, and two implementations would drift. The
state file carries already-resolved values.

Page variables are named `PAGE_<sanitised name>` because `00-statusline` is not
a valid shell identifier; the sanitisation is not reversible, so bash re-derives
it by walking the page files rather than decoding the variable name.

A missing state file is a no-op, preserving the non-interactive path where
`tools setup <app>` from a script takes build defaults — **unless
`LT_SKIP_WIZARD` is set**, which is a front-end saying it has already asked
everything. Then a missing or unreadable file is not "no answers", it is
answers that were lost, and `wizard_require_state` aborts rather than removing
and rebuilding the app with every selection discarded.

The file lives under `~/.cache/linux-tools/wizard/`, `0700`, with a random name
created `O_EXCL`. `$HOME` is the one path Distrobox shares with the host, so a
file written there is readable by the backend even when the dashboard runs
inside a container; `/tmp` is not, and a world-writable predictable path is a
way for another local user to have bash source their file instead.

---

## 3. Architecture: a dashboard, not a form sequence

**Superseded.** The original plan was a huh form flow that collected everything
up front, wrote the state file, then `exec`'d bash and never returned.

The target is a `gh-dash`-style dashboard: category tabs, an app table, an info
panel, a keybinding footer — a persistent full-screen program.

### Why huh was dropped entirely

huh is a *form* library: sequential prompts, one group at a time. It cannot
express tabs plus a table plus a sidebar. Two facts settled it:

- **gh-dash uses no huh at all.** Its `go.mod` is `bubbletea/v2`, `bubbles/v2`,
  `lipgloss/v2`, plus glamour and fuzzy search.
- **huh v1.0.0 still depends on `bubbletea` v1.3.6**, not
  `charm.land/bubbletea/v2`, so it could not be embedded in a v2 app even as a
  wizard component.

The wizard page parser and the state-file protocol are stack-independent and
carried over unchanged.

### Actions suspend rather than exec away

`tea.ExecProcess` suspends the dashboard, hands bash the real terminal so podman
output streams exactly as today, then resumes and re-reads container state. This
is better than exec-and-never-return: the dashboard survives a build and reports
its result.

Because bash sees a real tty it would otherwise ask its own whiptail pages, so
the wizard hand-off is what suppresses them: a run started from a wizard carries
`LT_SKIP_WIZARD=1` and `LT_WIZARD_STATE`, and one started without a wizard does
not — which keeps the whiptail path working for anything this front-end has not
taken over.

---

## 4. Categories

Read from `apps/<name>/category`, one line per app, following the existing
per-app file convention (`description`, `host-only`, `create_flags`). Missing or
empty ⇒ an `Other` tab. Preferred tab order lives in `Categories()` in
`tui/apps.go`; unknown names are appended alphabetically.

Rejected: a central manifest (a second place to edit whenever an app is added)
and parsing `ROADMAP.md` headings (couples the UI to a prose doc's formatting,
and covers only apps listed there).

---

## 5. Components

**Superseded.** This section previously mapped each whiptail dialog to a huh
field.

| Element | Built with |
|---|---|
| category tabs, superscript counts | hand-rolled + lipgloss |
| app table, terminal-width columns | hand-rolled; the 26-char budget is gone |
| README info panel | glamour, cached per app and width |
| full-width selection highlight | per-segment background, no arrow |
| platform / image / box indicators | Nerd Font glyphs, `--ascii` fallback |
| actions | `tea.ExecProcess`; `⏎` is setup, the primary one |
| wizard pages | hand-rolled checklist / single choice + a review screen (`tui/wizardui.go`) |

---

## 6. Build and distribution

Resolved for development: **Go is a selectable `dev-toolbox` tool** (PR #47),
installing the latest stable release as a self-contained GOROOT under
`~/.local/share/dev-toolbox/go`.

Resolved for shipping: **`cmd_install` builds the binary through a ladder**
(`cmd_build_tui`, `lib/commands.sh`) — reuse a current binary, else host Go,
else a throwaway `golang:1.25-alpine` container, else skip and keep whiptail.
Go never becomes a dependency of *using* linux-tools, and no rung is fatal.

Measured on an x86_64 host: 13s for the very first container build including
the 228 MB image pull, ~1s afterwards. `/go` lives on a named volume
(`linux-tools-go-cache`), so the 58 MB of module downloads happen once.

Rejected alternatives:

- **Committing the binary.** The repo's entire pack is 1.41 MiB; one build adds
  6.8 MiB compressed, permanently, per rebuild. Also amd64-only, in a repo that
  supports mixed-arch hosts.
- **A release artifact.** The right answer if this is ever distributed to people
  who do not clone the repo, but there is no CI in the project at all, so it
  means building a release pipeline to replace something that takes 1s.
- **Vendoring.** Would make builds offline-capable, at 23 MB and 787 files in a
  1.41 MiB repo. The named volume gets the same result after one build.

`CGO_ENABLED=0` is required either way — it produces a static binary, which is
what lets the alpine/musl container build run on a glibc host. Verified: a
container-built binary runs unmodified inside the Fedora-based
`claude-code-box`.

---

## 7. Fallback and incremental migration

The whiptail path stays intact and working. `tools.sh` gains a gate alongside
the existing `command -v whiptail` check (`tools.sh:71`):

1. `tools-tui` present and `LT_NO_GO_TUI` unset → dashboard
2. otherwise → current whiptail path, unchanged

`lib/tui.sh` is retired only once native wizard pages land.

---

## 8. Status

**Done**
- category tabs, app table, README info panel, filter, help overlay, footer
- actions via `ExecProcess`, with container state refreshed on completion
- state-file bridge and `wizard_load_state`, covered by tests
- native wizard pages: checklists with detect prefill, single choice for
  `.buildarg`/`.runtime`, and a review screen — whiptail is no longer reached
  from the dashboard
- `apps/<name>/category` for all 23 apps
- Go toolchain in dev-toolbox (merged)

- `cmd_install` building the binary, through the ladder in §6

**Next**
- wiring `tools` to launch it, behind the fallback gate

**Then**
- retire `lib/tui.sh`, drop the gate
- drop the 26-char `description` rule from `CLAUDE.md`
- multi-app select (`cmd_setup` is strictly single-app today)

---

## 9. Pitfalls found building it

- **Podman prefixes locally-built images with `localhost/`**, while
  `image_name()` in `lib/helpers.sh` produces the unprefixed form. Matching
  exactly reported *every* app as "not built".
- **Nerd Font glyphs are treacherous**: private-use codepoints silently become
  empty strings in transit, and supplementary-plane ones (U+F0868) render
  double-width while `lipgloss.Width` reports 1, shifting every column to their
  right. See [`tui/README.md`](../tui/README.md#icons) for the rules.
- **`JoinHorizontal` pads a single-line element** with blanks on subsequent
  lines rather than repeating it, so a `" │ "` divider drew only on row one.
  Build it as its own column, sized to the taller pane.
- **A background applied to an already-styled string ends early**, because the
  inner ANSI resets terminate it. Style each segment individually.
- **Running from inside a container degrades silently.** `podman`, `distrobox`
  and `tools` are not on PATH there, and the deliberate degrade-to-empty
  behaviour in the status lookups turns that into "everything not built".
  Detect containerisation and route through `distrobox-host-exec`.
- **Column padding must count display cells, not bytes.** `●` is one rune and
  three bytes; `%-*s` silently shortens those columns.
- **An empty wizard answer is an answer.** `wizard_load_state` originally
  re-hydrated a page only when its `PAGE_` variable was non-empty, which turned
  "untick everything" into "change nothing" — the whiptail path assigns the
  empty string and the apply handler then removes what is installed. It now
  tests for the variable being *defined*, and the Go side always writes a line
  for every page it asked.
- **An async result outlives the wizard that asked for it.** `items-cmd` takes
  seconds; cancelling one wizard and opening another within that window landed
  the first app's releases in the second app's page, because the reply was
  matched on page index alone and every session has a page 0. Results carry a
  session id.
- **A long page runs off the screen.** `shell-toolbox` ships 18 items, more than
  a 24-line terminal holds, and the overflow pushed the key legend — the part
  that says how to get out — past the bottom. Item lists need a viewport that
  follows the cursor, not just a loop.
- **`podman` is not the only runtime.** `tools.sh` falls back to Docker, so the
  dashboard has to as well; querying podman alone on a Docker host reports every
  built image as missing.
- **`.buildarg` items come from the network.** The page's `items-cmd` is a
  GitHub API call or a `git ls-remote`; running it inline would freeze the first
  frame of the wizard. It runs as a `tea.Cmd` with a timeout, and a failure is
  not fatal — the page is left unanswered so the Dockerfile default stands,
  matching what bash does.

---

## 10. Open questions

- **Bumping the pinned builder image.** `TUI_GO_IMAGE` in `lib/commands.sh` is
  `golang:1.25-alpine`, matching the `go` directive in `tui/go.mod`. Nothing
  checks that the two stay in step.
- **Non-interactive parity.** `tools setup <app>` from a script must keep taking
  build defaults; the state-file loader treats "no file" as "no selections",
  which holds today and must not regress.
- **9 of 23 apps have no `README.md`** despite `CLAUDE.md` requiring one. The
  info panel makes the gap visible; it does not cause it.
