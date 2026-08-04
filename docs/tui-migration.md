# Design: migrating the host TUI from whiptail to Go + huh

**Status:** proposed — not started
**Scope:** `lib/tui.sh`, `lib/wizard.sh`, `tools.sh` dispatch, `cmd_install`
**Non-goals:** changing `lib/commands.sh` behaviour, changing what any app installs

Roadmap entry: see *Tooling / Infrastructure* in [`ROADMAP.md`](../ROADMAP.md).

---

## 1. Why

The `whiptail` front-end works, but its limits have started dictating things
outside itself.

**Rendering limits leaking into project policy.** `_fw` (`lib/tui.sh:31`) pads
and truncates every menu row to fixed 26/34-column fields because whiptail has
no table support. That 26-character budget is now written into `CLAUDE.md:202`
as a rule every new app must follow when writing its `description`.
`fastflowlm` is already at 25 characters.

**A fragile selection round-trip.** The rendered detail line doubles as the
whiptail menu *tag*, and the selected line is mapped back to an app name
through `detail_to_app` (`lib/tui.sh:71-86`). Two apps with an identical
description *and* identical image/box status render byte-identical rows and
collide silently.

**Manual byte-vs-char arithmetic.** `_fw` computes `wc -c` against `${#s}` purely
to keep the `…` truncation character from breaking column alignment.

**No search, no multi-select.** 23 apps in a 10-row window, arrow keys only.
Every roadmap item makes this worse, and there is no way to set up several apps
in one pass.

**Wrong dependency hint.** `lib/tui.sh:58` hardcodes
`sudo apt install whiptail` even though the repo explicitly supports
Arch-family hosts via `host_distro_family` (`lib/helpers.sh`).

**Theme fights.** The 16-colour `NEWT_COLORS` block (`lib/tui.sh:1-27`)
approximates the intended palette with `brown`/`lightgray` and still loses
checkbox and button contrast.

**Esc does not quit.** newt swallows single-`Esc`, so leaving a page takes more
keystrokes than it should.

---

## 2. The core problem: wizard state crosses a process boundary

This is the part the roadmap one-liner does not address, and it drives the rest
of the design.

Wizard answers are not consumed by the rendering layer. They live in
`_WIZARD_SELECTIONS`, a bash associative array (`lib/wizard.sh:24`), and are
read at four separate points — two of them inside the backend that this
migration is supposed to leave alone:

| Consumer | Defined at | Called from | Needs |
|---|---|---|---|
| `tui_confirm_wizards` | `lib/wizard.sh:230` | `tools.sh:76` | selections + detect state → install/remove diff |
| `wizard_build_args` | `lib/wizard.sh:210` | `cmd_build`, `lib/commands.sh:9` | `--build-arg NAME=value` |
| `wizard_create_variant` | `lib/wizard.sh:187` | `cmd_create`, `lib/commands.sh:41` | `create_flags.<variant>` selection |
| `tui_apply_wizards` | `lib/wizard.sh:310` | `tools.sh:80` | post-action `distrobox enter … --tools` |

A Go front-end that collects answers and then shells out to `tools setup <app>`
starts a **new bash process with an empty array**. The build arg and the
runtime variant would silently disappear — no error, just a default build.

So "Go replaces only the rendering and shells out" is achievable only with an
explicit serialization contract between the two halves. Defining that contract
is the real work; the widget porting is the easy part.

---

## 3. Design: Go as pre-processor, not wrapper

The existing flow already collects **every** wizard answer before any container
work begins (`tools.sh:71-83`: `tui_run_wizards` → `tui_confirm_wizards` →
`cmd_setup`). That ordering is what makes a clean split possible.

```
tools            →  tools-tui (Go + huh)        →  exec tools <action> <app>
(no args)           · pick app                     LT_WIZARD_STATE=<file>
                    · pick action                  LT_SKIP_WIZARD=1
                    · run all wizard pages
                    · confirm
                    · write state file
```

The Go binary **execs and never returns**. It does not wrap the build, so
Bubble Tea never has to hand the terminal back and forth while podman streams
output — bash prints build progress exactly as it does today.

### Why not have Go orchestrate the whole run?

The alternative is Go calling `tools build` / `tools create` / `tools export`
as discrete steps with explicit flags (`--build-arg`, `--variant`). That is
attractive long-term because it would make the bash CLI fully non-interactive
and scriptable — a win independent of the TUI. It is rejected *for now* as a
larger, more invasive change that also has to define a stable flag surface.
Worth revisiting once the state-file protocol has proven itself.

---

## 4. State file protocol

Go writes a flat `KEY=value` file; bash sources it. Location comes from
`LT_WIZARD_STATE`, defaulting to
`${XDG_RUNTIME_DIR:-/tmp}/linux-tools/wizard-<app>.state`.

```sh
# resolved by Go, consumed verbatim by bash
BUILD_ARGS="--build-arg FLM_REF=v0.9.12"
VARIANT="nvidia"
PAGE_00_statusline="statusline"
PAGE_00_tools="node uv rust"
```

**Go is the sole parser of the page format.** This is a deliberate refinement
of the roadmap note. If both halves parse
`apps/<app>/wizard/NN-name.<type>`, there are two implementations of a fiddly
positional grammar — three different body grammars share one file convention
(`.packages` has 3-to-5 pipe-separated fields with optional trailing ones,
`.buildarg` uses `key|value` config lines, `.runtime` uses
`Label|value|desc` items) — and they will drift.

Instead Go resolves everything down to already-computed values, and the bash
parsers are **deleted rather than ported**:

- `wizard_build_args` (`lib/wizard.sh:210-228`) collapses to reading `BUILD_ARGS`
- `wizard_create_variant` (`lib/wizard.sh:187-206`) collapses to reading `VARIANT`
- `_wizard_apply_mcp` / `_wizard_apply_packages` still need per-item payloads, so
  they keep reading their page files — but only for the *apply* step, which is
  backend work that stays in bash regardless

Bash gains one small `wizard_load_selections` helper, guarded so that a missing
file (non-interactive `tools setup <app>` from a script) behaves exactly as an
empty array does today.

---

## 5. Widget mapping

| Today (whiptail) | huh | Note |
|---|---|---|
| app menu, `lib/tui.sh:81` | `huh.NewSelect` + filtering | kills `_fw` and the 26-char budget |
| action menu, `lib/tui.sh:90` | `huh.NewSelect` | |
| `.packages` checklist, `lib/wizard.sh:113` | `huh.NewMultiSelect` | prefill from existing detect logic |
| `.buildarg` radiolist, `lib/wizard.sh:151` | `huh.NewSelect` + spinner | see below |
| `.runtime` radiolist, `lib/wizard.sh:178` | `huh.NewSelect` with `Option` key/value | see below |
| `--yesno` confirm, `lib/wizard.sh:305` | `huh.NewConfirm` | |
| one page = one blocking dialog | one page = one `huh.Group` in a single form | gains back-navigation |

Three wins here are concrete rather than cosmetic:

**The `.runtime` label→value round-trip disappears.** whiptail returns the
*display label*, so `wizard_create_variant` (`lib/wizard.sh:186-206`) has to
re-open the page file and translate `"AMD (ROCm/Vulkan)"` back to `amd`. huh's
`Option` carries display key and typed value together, so this code is deleted,
not ported.

**Pages stop being dead ends.** Today each dialog is standalone and cancelling
any page returns 1, which aborts the whole wizard (`lib/tui.sh:100` → `exit 0`).
A single form with one group per page gives back/forward navigation for free.

**The `.buildarg` network freeze becomes visible.** `fastflowlm`'s
`00-release.buildarg` runs `items-cmd` against the GitHub releases API; today
that is a silent multi-second hang before the menu appears. A spinner covers
it, and the empty-result case can be surfaced inline instead of as the stderr
warning at `lib/wizard.sh:137-140` that scrolls past unnoticed.

> API specifics (exact `huh` option constructors, whether filtering is enabled
> per-field or per-form) are to be confirmed against the library during the
> spike rather than assumed here.

---

## 6. Build and distribution

`dev-toolbox` currently ships node, uv, rust and JVM toolchains — **there is no
Go toolchain anywhere in the repo today**, so this needs deciding before work
starts.

| Option | Assessment |
|---|---|
| **Build in a throwaway `golang:*-alpine` container at `tools install` time** | **Preferred.** Matches the repo's philosophy — no host toolchain, the container does the build. `CGO_ENABLED=0` gives a static binary; drop it at `~/.local/bin/tools-tui`. Hooks into `cmd_install` (`lib/commands.sh:286`), which already writes to `~/.local/bin` and manages completion. |
| Add Go to `dev-toolbox` | Couples a host-side tool's build to an unrelated app's image; `dev-toolbox` is for user projects, not for building this repo. |
| Vendor a prebuilt binary in git | Puts a multi-MB binary under version control and needs per-arch builds. |

Base image must be fully qualified per `CLAUDE.md` (`docker.io/golang:...`);
exact version pin is an open question below.

---

## 7. Fallback and incremental migration

The whiptail path stays intact and working. `tools.sh` gains a gate alongside
the existing `command -v whiptail` check (`tools.sh:71`):

1. `tools-tui` present and `LT_NO_GO_TUI` unset → Go front-end
2. otherwise → current whiptail path, unchanged

This keeps the migration non-breaking, lets pages port one type at a time, and
gives an escape hatch if the Go binary misbehaves on some host. The gate is
removed and `lib/tui.sh` retired only once all four page types are ported.

---

## 8. Spike

The roadmap note proposes porting the app-selection menu plus `claude-code`'s
`.packages` page. **The state-file protocol should be added to that scope** —
it is the piece that can invalidate the design, and everything else is
mechanical once it holds.

**Phase 1 — spike**
- app-selection menu (proves the list, filtering, and the death of `_fw`)
- `claude-code` `00-statusline.packages` (exercises the detect-path logic at
  `lib/wizard.sh:89-103`)
- state file written by Go, read by a `wizard_load_selections` in bash
- `cmd_install` builds the binary in a container
- whiptail fallback gate

**Phase 2 — the pages that need the protocol**
- `.buildarg` (`fastflowlm`, `llama-cpp-rocm`) — proves `BUILD_ARGS` through
  `cmd_build`, plus the spinner
- `.runtime` (`lmstudio`) — proves `VARIANT` through `cmd_create` and deletes
  the label→value round-trip

**Phase 3 — completion**
- `.mcp`, confirm screen, multi-select across apps
- retire `lib/tui.sh`, drop the whiptail gate
- drop the 26-char `description` rule from `CLAUDE.md:202`

---

## 9. Open questions

- **Go version pin** for the build container, and whether to commit
  `go.mod`/`go.sum` plus a vendored module tree so builds work without network
  access.
- **Where the Go source lives** — `tui/` at repo root is the obvious spot, but
  it is the first non-app, non-lib source tree in the repo.
- **Multi-app select** is listed as a win, but `cmd_setup` is strictly
  single-app today. Batching means either looping in bash or teaching the
  backend a list — deferred to Phase 3 deliberately.
- **Non-interactive parity.** `tools setup <app>` from a script currently skips
  wizards entirely and takes build defaults. That behaviour must be preserved
  exactly; the state-file loader has to treat "no file" as "no selections".
