# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Packages Linux GUI and CLI applications into [Distrobox](https://distrobox.it/) containers and exports them to the host so they behave like natively installed apps. Each app lives under `apps/<name>/` and is managed via `tools.sh`.

## Runtime environment

Claude Code runs inside `claude-code-box`, a Distrobox container (`linux-tools/claude-code:latest`). All shell commands execute inside that container by default.

Commands that interact with the host — running `tools`, `podman`, `distrobox`, or anything that needs to see the host filesystem or process tree — must be prefixed with `distrobox-host-exec`:

```bash
distrobox-host-exec tools setup <app>
distrobox-host-exec tools list
distrobox-host-exec podman images
distrobox-host-exec distrobox list
```

Plain shell commands (file edits, `git`, `grep`, etc.) run fine inside the container without the prefix because `$HOME` is shared.

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

### App memory file

New app directories should include a `.memory.md` file, and existing ones should gain one when they are updated. Keep it up to date as the app evolves.

**Required sections:**

```markdown
## <app-name>

Short description of what this app does and why it's packaged this way.

## Implementation

How it was actually implemented: base image choice, export type, wrapper scripts, wizard pages, any non-obvious decisions.

## Pitfalls and notes

Things that went wrong or were surprising during implementation. Anything a future reader would need to know before touching this app.
```

**When working on an existing app, read its `.memory.md` first** — this is required before making any changes. See [Working practices](#working-practices) for the full set of update rules.

---

### Adding a new app

Create `apps/<name>/` with three files:

| File | Purpose |
|---|---|
| `Dockerfile` | Container image definition |
| `exports` | What to expose to the host (see export types below) |
| `description` | One-line label shown in the interactive TUI (keep it short — the TUI is 72 cols wide; description + app name + status must fit) |
| `README.md` | **Required.** App-specific usage docs (see below). |
| `create_flags` | Optional. Extra flags passed to the container engine via `distrobox create --additional-flags`. Use for privileged mode, device passthrough, or volume mounts needed at container creation time (e.g. `--privileged -v /usr/src:/usr/src:ro`). |

Optionally add `icon.png` or `icon.svg` — if present, it overrides whatever icon the container has. All export types share the same bundled icon.

**Every new app must include `apps/<name>/README.md`** covering: what the app does, install command, exported commands with usage examples, any persistent storage paths, and relevant notes (GPU setup, env vars, etc.). The main `README.md` app table row should link to it: `[`name`](apps/name/README.md)`.

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

### Build-environment container pattern

Some tools must run on bare metal (kernel modules, hardware monitors) and can't be containerized at runtime. Use the container as a **build environment only**: compile inside, run the artifacts on the host.

Key points:
- Clone source at image-build time (`git clone` in `Dockerfile`) so the image is self-contained
- Build at runtime (not image-build time) because the host kernel version isn't known until then
- Copy build artifacts to `~/.local/<app>/` — Distrobox's shared `$HOME` makes them immediately visible on the host
- Use `distrobox-host-exec` in wrapper scripts for any operation that needs real host privileges (see below)

Example: `apps/corefreq/` — container provides `build-essential` + CoreFreq source; `corefreq-setup` builds the kernel module inside the container and copies it to `~/.local/corefreq/` on the host.

### `distrobox-host-exec` pattern

`distrobox-host-exec <cmd>` runs a command on the host from inside a container. Use it whenever a wrapper script needs host-level operations that container capabilities can't provide:

```bash
# load a kernel module on the host
distrobox-host-exec sudo insmod "$HOME/.local/corefreq/corefreqk.ko"

# check host process list
distrobox-host-exec pgrep -x corefreqd

# start a background daemon on the host
distrobox-host-exec sudo bash -c "nohup ${DAEMON} &>/dev/null &"
```

Pipe output from host commands normally — only the command runs on the host, stdout flows back to the container:
```bash
distrobox-host-exec lsmod | grep -q "^corefreqk "
```

**When to use it:** rootless Podman containers with `--privileged` do not get `CAP_SYS_MODULE`, so `insmod`/`rmmod` fail even inside a privileged container. `distrobox-host-exec` bypasses this by delegating to the host's sudo.

### Base image selection

| Situation | Base image |
|---|---|
| AMD GPU access, Vulkan, GUI rendering (egui/WGPU) | `registry.fedoraproject.org/fedora:43` |
| App with official Ubuntu/Debian APT repo | `ubuntu:24.04` |
| Kernel module compilation (must match host ABI) | `ubuntu:24.04` |
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

## Working practices

- **Read `.memory.md` first**: before touching any existing app, read `apps/<name>/.memory.md`. It contains implementation context, pitfalls, and decisions that are not obvious from the code.
- **Keep `.memory.md` current**: after any change to an app, update its `.memory.md` to reflect what changed and why. Add new pitfalls as they are discovered.
- **Keep `ROADMAP.md` current**: if a task completes, unblocks, or adds a planned item, update `ROADMAP.md` to reflect the new state.
- **Keep `README.md` current**: if a new app is added or an existing one changes significantly (new features, renamed exports, different usage), update `README.md`.
- **Every new app needs `apps/<name>/README.md`**: cover install, exported commands with examples, storage paths, and any GPU/env notes. Link to it from the main `README.md` table: `[`name`](apps/name/README.md)`.

## Branching policy

- Primary branch is `main` — all branches are cut from `main` and PRed back to `main`
- Always create a dedicated branch for every task (feature, fix, or otherwise); never commit directly to `main`
- Branch naming:
  - `feature/<name>` — new apps or features (e.g. `feature/codex-cli`)
  - `bugfix/<name>` — bug fixes (e.g. `bugfix/export-lookup`)
- Pull `main` before branching to ensure the branch starts from the latest state

## Known pitfalls

- **`app:` + manual `.desktop`**: `distrobox-export --app` cannot find `.desktop` files that weren't installed by the package manager. Use `gui:` + a wrapper script in `/usr/bin/` instead.
- **`/usr/local/bin` not in system PATH**: `command -pv` (used to locate binaries for `bin:`, `desktop:`, `gui:` exports) searches the system default PATH. Place wrapper scripts in `/usr/bin/`, not `/usr/local/bin/`.
- **WGPU / egui GUI apps**: Require `vulkan-loader` + `mesa-vulkan-drivers` in the container. Missing these produces `Failed to create surface for any enabled backend`.
- **`libxkbcommon-x11`**: A separate package from `libxkbcommon` on Fedora — both are needed for any Rust GUI using xkbcommon.
- **Kernel module builds**: Distrobox does NOT auto-share `/lib/modules` or `/usr/src`. Add both to `create_flags`: `--privileged -v /usr/src:/usr/src:ro -v /lib/modules:/lib/modules:ro`. Without `/usr/src`, the `/lib/modules/$(uname -r)/build` symlink is broken inside the container.
- **`insmod` in rootless Podman**: `--privileged` does not grant `CAP_SYS_MODULE` in rootless mode. Use `distrobox-host-exec sudo insmod` to load modules via the host's sudo instead.
- **Daemon IPC across container boundary**: `corefreqd` (host) and `corefreq-cli` (container) communicate via POSIX shared memory. This works because Distrobox shares `/dev/shm` with the host. However, `pgrep` inside the container won't find host processes — check with `distrobox-host-exec pgrep` instead.
- **Unqualified image names in Dockerfiles**: Podman has no unqualified-search registries configured (`/etc/containers/registries.conf`). Always use fully-qualified names in `FROM` lines — e.g. `docker.io/ubuntu:24.04`, `docker.io/rocm/pytorch:...`. The `registry.fedoraproject.org/fedora:43` form is already fully qualified.
- **`/opt` permissions in Ubuntu-based images**: directories created under `/opt` during the image build are owned by root. Apps that write runtime state there (logs, user dirs, temp files) will fail with `PermissionError` when run as the Distrobox user. Fix: `RUN chmod -R a+rwX /opt/<app>` at the end of the Dockerfile.
- **`rocm/pytorch` venv path**: the `rocm/pytorch` base image installs all Python packages into `/opt/venv`, not the system Python. Wrapper scripts must call `/opt/venv/bin/python` explicitly — bare `python` resolves to `/usr/bin/python` which has no site-packages.
- **`--group-add <name>` on Ubuntu-based images**: Podman resolves group names against the container's `/etc/group`. Ubuntu images don't ship `render` or `video` groups, so `--group-add render` causes "Unable to find group render" and the container fails to start. Use numeric GIDs instead (e.g. `--group-add 992 --group-add 44`); Podman accepts GIDs directly without an `/etc/group` lookup. Check host GIDs with `getent group render video`.
