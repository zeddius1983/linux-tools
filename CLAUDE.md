# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Packages Linux GUI and CLI applications into [Distrobox](https://distrobox.it/) containers and exports them to the host so they behave like natively installed apps. Each app lives under `apps/<name>/` and is managed via `tools.sh`.

## Common commands

```bash
./tools.sh install        # symlink as 'tools' in ~/.local/bin + set up completion
tools setup <app>         # full install: remove existing box+image, build, create, export
tools export <app>        # re-export after editing an exports file
tools list                # show all apps with image/box status
tools rm <app>            # remove distrobox only (image kept)
distrobox enter <app>-box # open a shell inside a running box
```

`setup` is idempotent — it always removes any existing box and image before rebuilding, so it doubles as a rebuild command.

`make setup-<app>` / `make build-<app>` etc. are thin wrappers around the above.

Bash completion is in `completion/tools.bash` — source it from `~/.bashrc`.

## Architecture

### Adding a new app

Create `apps/<name>/` with three files:

| File | Purpose |
|---|---|
| `Dockerfile` | Container image definition |
| `exports` | What to expose to the host (see export types below) |
| `description` | One-line label shown in the interactive TUI (keep it short — the TUI is 72 cols wide; description + app name + status must fit) |

Optionally add `icon.png` or `icon.svg` — if present, it overrides whatever icon the container has. All export types share the same bundled icon.

`tools.sh` auto-discovers apps by listing `apps/`; no registration needed.

### Export types

Declared in `apps/<name>/exports`, one per line: `type:name[:Display Name]`

| Type | When to use | How it works |
|---|---|---|
| `bin:name` | CLI tool you want on the host PATH | Finds binary with `command -pv`, runs `distrobox-export --bin` → `~/.local/bin` |
| `desktop:name[:Label]` | TUI / terminal app (opens in a terminal window) | Finds binary with `command -pv`, creates `.desktop` with terminal emulator prefix |
| `gui:name[:Label]` | GUI app launched without a terminal | Finds binary with `command -pv`, creates `Terminal=false` `.desktop` with `Exec=distrobox enter <box> -- <bin>` |
| `app:name[:Label]` | App that installs its own `.desktop` via the package manager | Runs `distrobox-export --app` inside the container to re-export the existing `.desktop` |

**Critical:** `app:` only works for `.desktop` files installed by the package manager. Manually `printf`-ed `.desktop` files are not found by `distrobox-export --app`. Use `gui:` with a wrapper script instead.

**Critical:** `command -pv` uses the system default PATH, which does **not** include `/usr/local/bin`. Wrapper scripts referenced by `bin:`, `desktop:`, or `gui:` must live in `/usr/bin/`.

### Wrapper script pattern

When you need a binary with fixed flags (e.g. always `--dark`, or `--gui`), rename the real binary and create wrappers in `/usr/bin/`:

```dockerfile
RUN mv /usr/bin/mytool /usr/bin/mytool-bin && \
  printf '#!/usr/bin/env bash\nexec /usr/bin/mytool-bin --some-flag "$@"\n' \
    > /usr/bin/mytool && chmod +x /usr/bin/mytool
```

### Base image selection

| Situation | Base image |
|---|---|
| AMD GPU access, Vulkan, GUI rendering (egui/WGPU) | `registry.fedoraproject.org/fedora:43` |
| App with official Ubuntu/Debian APT repo | `ubuntu:24.04` |
| x86-only app on a mixed-arch host | `FROM --platform=linux/amd64 ubuntu:24.04` |

For AMD GPU GUI apps, the minimum required packages are:
```
vulkan-loader mesa-vulkan-drivers mesa-libGL mesa-libEGL mesa-dri-drivers
libdrm libglvnd-glx libglvnd-egl
libX11 libXcursor libXi libXrandr libXext libXrender
libxkbcommon libxkbcommon-x11
```

### Naming conventions

| Artifact | Pattern |
|---|---|
| Container image | `linux-tools/<app>:latest` |
| Distrobox name | `<app>-box` |
| Desktop file (host) | `~/.local/share/applications/<app>-box-<name>.desktop` |

### Distrobox home sharing

Distrobox mounts the host's `$HOME` inside the container. This means:
- The container sees your dotfiles and project directories
- `distrobox-export --bin` writes to `~/.local/bin` on the host
- `.desktop` files written to `~/.local/share/applications/` inside the container appear on the host immediately

### Icon resolution order

`tools.sh` resolves icons in this order for all export types:
1. `apps/<name>/icon.png` or `apps/<name>/icon.svg` (bundled — preferred)
2. Standard icon paths searched inside the container (`hicolor/256x256`, `512x512`, `128x128`, `pixmaps`)
3. Falls back to `utilities-terminal`

### Interactive TUI

`./tools.sh` with no arguments opens a `whiptail` checklist. The TUI window is **72 columns wide** — keep `description` files short (under ~25 chars) so the app name + description + `[image:OK  box:OK]` status fits on one line.

## Known pitfalls

- **`app:` + manual `.desktop`**: `distrobox-export --app` cannot find `.desktop` files that weren't installed by the package manager. Use `gui:` + a wrapper script in `/usr/bin/` instead.
- **`/usr/local/bin` not in system PATH**: `command -pv` (used to locate binaries for `bin:`, `desktop:`, `gui:` exports) searches the system default PATH. Place wrapper scripts in `/usr/bin/`, not `/usr/local/bin/`.
- **WGPU / egui GUI apps**: Require `vulkan-loader` + `mesa-vulkan-drivers` in the container. Missing these produces `Failed to create surface for any enabled backend`.
- **`libxkbcommon-x11`**: A separate package from `libxkbcommon` on Fedora — both are needed for any Rust GUI using xkbcommon.
