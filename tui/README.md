# tools-tui — Go + huh front-end (spike)

Phase 1 spike for the `whiptail` → Go + [`huh`](https://github.com/charmbracelet/huh)
migration. See [`docs/tui-migration.md`](../docs/tui-migration.md) for the full
design.

**This is a prototype.** The whiptail front-end is untouched and still the
default; nothing here runs unless you invoke the binary directly.

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
# from the repo root; --dry-run prints the state file instead of exec'ing bash
./tui/tools-tui --apps-dir apps --dry-run
```

| Flag | Meaning |
|---|---|
| `--apps-dir` | path to `apps/` (default `apps`) |
| `--dry-run` | write and print the state file, then exit without exec |
| `--state` | state file path (default `$XDG_RUNTIME_DIR/linux-tools/wizard-<app>.state`) |
| `--tools` | bash entrypoint to exec (default `tools`) |

Needs a real terminal: `huh` exits with `could not open a new TTY` when stdin
is not a tty.

## Keys

| Key | Action |
|---|---|
| `↑` / `↓` | move |
| `enter` | select / next |
| `shift+tab` | **back** — walks backwards across every stage, including from a wizard page to the action and app menus |
| `/` | filter the app list |
| `space` | toggle a checkbox on multi-select pages |
| `esc` | quit |

`esc` is bound explicitly. huh v0.7.0 binds quit to `ctrl+c` alone and gives it
no help string, so out of the box nothing in the UI says how to leave — see
`keyMap()` in `main.go`.

## What it does

Collects the app, the action and every wizard answer, writes a flat `KEY=value`
state file, then `exec`s `tools <action> <app>` with `LT_WIZARD_STATE` and
`LT_SKIP_WIZARD=1` set. It never wraps the build, so podman output streams to
the terminal exactly as before.

```
APP="fastflowlm"
ACTION="setup"
BUILD_ARGS="--build-arg FLM_REF=v0.9.12"
VARIANT="nvidia"
PAGE_00_statusline="statusline"
```

`wizard_load_state` in `lib/wizard.sh` sources that file and re-hydrates
`_WIZARD_SELECTIONS`, so the existing apply handlers, `wizard_build_args` and
`wizard_create_variant` all work unchanged.

## Status

| Piece | State |
|---|---|
| app menu with type-to-filter | done — no fixed-width columns, so the ~26-char `description` budget is gone |
| action menu | done |
| `.packages` / `.mcp` multi-select | done, with detect-path prefill |
| `.runtime` select | done — `huh.Option` carries label and value, so no label→value round-trip |
| `.buildarg` select | done, with a spinner over the `items-cmd` network call |
| state file + bash bridge | done, covered by tests |
| confirm screen | basic — does not yet show the install/remove diff `tui_confirm_wizards` produces |
| `cmd_install` building the binary | not started |
| whiptail fallback gate | not started — whiptail is still the only default path |
| multi-app select | not started (Phase 3) |

## Files

| File | Contents |
|---|---|
| `main.go` | orchestration, huh forms, exec handoff |
| `apps.go` | app discovery, podman/distrobox status |
| `wizard.go` | the sole parser of the wizard page format |
| `state.go` | state file rendering and shell quoting |
| `exec_unix.go` | `syscall.Exec` handoff |
