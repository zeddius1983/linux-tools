# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Packages Linux GUI and CLI applications into [Distrobox](https://distrobox.it/) containers and exports them to the host so they behave like natively installed apps. Each app lives under `apps/<name>/` and is managed via `tools.sh`.

## Runtime environment

Claude Code may be running **on the host** or **inside `claude-code-box`** (the
Distrobox container built from `linux-tools/claude-code:latest`), depending on how
it was launched. The two need different command prefixes, so check first — don't
assume:

```bash
[ -f /run/.containerenv ] && echo container || echo host
```

`$CONTAINER_ID` works as a secondary signal — inside a box it holds the box name
(`chrome-box`), on the host it is unset. `/etc/os-release` is a useful cross-check
too: it names the container's base image inside a box (`Ubuntu 24.04.4 LTS`) and
the real distro on the host (`Linux Mint 22.3`). **`hostname` is not a signal** —
Distrobox gives the container the host's hostname, so it reads the same (`halo`)
from both sides.

**On the host** (no `/run/.containerenv`): run everything directly. `tools`,
`podman` and `distrobox` are all on `PATH`, and `distrobox-host-exec` refuses to
run at all — it prints `You must run distrobox-host-exec inside a container!` and
exits 126, so prefixing with it there breaks the command rather than being a
harmless no-op.

```bash
tools setup <app>
podman images
distrobox list
```

**Inside `claude-code-box`** (`/run/.containerenv` exists): commands that touch the
host — `tools`, `podman`, `distrobox`, or anything that needs the host filesystem
or process tree — must be prefixed:

```bash
distrobox-host-exec tools setup <app>
distrobox-host-exec tools list
distrobox-host-exec podman images
distrobox-host-exec distrobox list
```

Plain shell commands (file edits, `git`, `grep`, etc.) need no prefix in either
case — `$HOME` is shared, so the working tree is the same files either way.

## Common commands

```bash
./tools.sh install        # symlink as 'tools' in ~/.local/bin + set up completion
tools build-tui           # build the Go dashboard (host Go, else a container)
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

Create `apps/<name>/` with the files below — `Dockerfile`, `exports`, `description`, and `README.md` are required; the rest are optional:

| File | Purpose |
|---|---|
| `Dockerfile` | Container image definition. Can instead be a `Dockerfile.ubuntu` + `Dockerfile.arch` pair — see [Multi-base-image pattern](#multi-base-image-pattern). |
| `exports` | What to expose to the host (see export types below) |
| `description` | One-line label shown in the interactive TUI (keep it under ~26 chars — that's the TUI description column width) |
| `category` | One line naming the dashboard tab the app appears under (e.g. `AI / LLM`, `Development`, `System`, `Browsers`, `Communication`, `Shell`). Missing or empty ⇒ the app lands in an `Other` tab. Preferred tab order lives in `Categories()` in `tui/apps.go`; unknown names are appended alphabetically. |
| `README.md` | **Required.** App-specific usage docs (see below). Rendered in the dashboard's info panel beside the app table; `tools setup` prints only its path when it finishes. |
| `create_flags` | Optional. Extra flags passed to the container engine via `distrobox create --additional-flags`. Use for privileged mode, device passthrough, or volume mounts needed at container creation time (e.g. `--privileged -v /usr/src:/usr/src:ro`). |
| `post-install` | Optional. Short text snippet `cat`-ed by `tools setup` when it finishes — use it for terse "next step" hints (e.g. `corefreq-setup`). This is now the *only* thing printed after an install, so keep it to a few lines; long-form docs belong in `README.md`. |
| `host-only` | Optional. Marker file (contents ignored). Tells `tools setup` the app installs straight to the host instead of running in a container (see `apps/shell-toolbox`). |
| `renamed-from` | Optional. Previous app name. During setup, removes that app's obsolete Distrobox and image before building the renamed app; shared-home data is preserved. |

Optionally add `icon.png` or `icon.svg` — if present, it overrides whatever icon the container has. All export types share the same bundled icon.

**Every new or touched app must include `apps/<name>/README.md`** covering: what the app does, install command, exported commands with usage examples, any persistent storage paths, and relevant notes (GPU setup, env vars, etc.). The main `README.md` app table row should link to it: `[`name`](apps/name/README.md)`. If you change an existing app that lacks a README, add one as part of the same change — the dashboard renders it in the info panel beside the app table, so a missing README means an empty panel and no reference for that app.

#### Compatibility badges

Every `apps/<name>/README.md` opens with a compatibility badge row directly under the `# <name>` heading — three shields.io badges saying which distros the app has actually been run on. Ubuntu and Linux Mint are green everywhere (that is where everything is developed); CachyOS is green only for apps exercised on an Arch-family host, and grey (`untested`) otherwise. The legend lives in the main `README.md` under `## Apps`.

**Write the row as a raw HTML `<p>` block, never as markdown `![alt](url)` images.** GitHub renders both identically, but the dashboard renders each README through glamour, which expands a markdown image into three lines of `Image: <alt> → <full URL>` — nine lines of shields.io URLs shoved above the app's actual description. Glamour skips raw HTML blocks entirely, so `tui/badges.go` lifts the row out before rendering and paints it back in as coloured terminal pills (`extractBadges` → `injectBadges`, wired into `infoPanel.readme`). The README is the single source of truth for both audiences — there is no per-app metadata file for this.

The parser keys on the **first** HTML `<p>` block containing `img.shields.io`, reads the label and value from each `<img>`'s `alt="<label>: <value>"`, and takes the verdict from the **URL colour** (`-brightgreen` ⇒ green pill, anything else ⇒ grey). Keep the alt text and the colour in agreement; the colour is what wins. An app whose README has no badge row renders exactly as before, so this is safe for any README that predates the convention.

```markdown
# <name>

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/Ubuntu-tested-brightgreen?logo=ubuntu&logoColor=white">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/Linux_Mint-tested-brightgreen?logo=linuxmint&logoColor=white">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/CachyOS-untested-lightgrey?logo=archlinux&logoColor=white">
</p>
```

A new app starts with the grey CachyOS badge; flip it to `CachyOS-tested-brightgreen` (and the alt text to `CachyOS: tested`) only once the app has genuinely been run there.

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

### Multi-base-image pattern

Some build-environment apps need a container toolchain close to whatever built the *host* kernel (or other host binaries the container has to interoperate with) — no single base image tracks both Debian/Ubuntu-family and Arch-family hosts closely enough. Ship `Dockerfile.ubuntu` and `Dockerfile.arch` instead of a single `Dockerfile`; `tools setup`/`tools build` (`cmd_build` in `lib/commands.sh`) detects the pair and automatically builds with `-f Dockerfile.$(host_distro_family)`, where `host_distro_family` (`lib/helpers.sh`) greps the host's `/etc/os-release` `ID`/`ID_LIKE` for `arch`, defaulting to `ubuntu` otherwise. Apps with a single `Dockerfile` are completely unaffected — this only activates when both variant files are present.

Example: `apps/corefreq/` needs this because CachyOS (Arch-family) kernels are built with Clang and carry Clang-only codegen flags, while Ubuntu-family kernels are GCC-built — no amount of extra packages in a single `ubuntu:24.04` image closes that gap cleanly (see `apps/corefreq/.memory.md` for the three escalating workarounds that were tried before splitting the Dockerfile).

### `distrobox-host-exec` pattern

`distrobox-host-exec <cmd>` runs a command on the host from inside a container. Use it whenever a wrapper script needs host-level operations that container capabilities can't provide:

```bash
# load a kernel module on the host
distrobox-host-exec sudo insmod "$HOME/.local/corefreq/corefreqk.ko"

# check host process list (use -f, not -x -- see note below on exact-name matching)
distrobox-host-exec pgrep -f corefreqd

# start a background daemon on the host
distrobox-host-exec sudo bash -c "nohup ${DAEMON} &>/dev/null &"
```

Pipe output from host commands normally — only the command runs on the host, stdout flows back to the container:
```bash
distrobox-host-exec lsmod | grep -q "^corefreqk "
```

**When to use it:** rootless Podman containers with `--privileged` do not get `CAP_SYS_MODULE`, so `insmod`/`rmmod` fail even inside a privileged container. `distrobox-host-exec` bypasses this by delegating to the host's sudo.

**Host prerequisite — the `flatpak` package must be installed on the host.** `distrobox-host-exec` shells out to `host-spawn`, which (for these non-`--init` containers) talks to the host over the `org.freedesktop.Flatpak` D-Bus interface — the same mechanism `flatpak-spawn --host` uses. That interface is provided by the `flatpak` package itself, *not* by `xdg-desktop-portal` or its KDE/GTK backends — a host can have all of those running and still have no `flatpak`-related name on the session bus at all. If `flatpak` isn't installed, **every** `distrobox-host-exec` call on that host fails completely silently: no error, no hang, it just returns with no output, as if the command were a no-op. This affects every app in this repo that relies on `distrobox-host-exec` (corefreq's module load/daemon start, shell-toolbox's host package installs, comfyui's browser launch, etc.) — it's a one-time host dependency, not something any single app's Dockerfile can work around.
- Diagnose with `busctl --user list | grep -i flatpak` (should show something once `flatpak` is installed) and `distrobox-host-exec -v echo hello` (verbose trace stops right after `+ host-spawn echo hello` with nothing further when this is the cause).

**Never redirect stderr away from a `distrobox-host-exec sudo ...` call**, even one you're intentionally letting fail with `|| true`. `sudo`'s credential cache does not appear to carry over between separate `distrobox-host-exec` invocations (each one goes through `host-spawn`'s D-Bus `HostCommand` call, seemingly as an unrelated host-side session each time) — a single script calling `distrobox-host-exec sudo` three times in a row can prompt `[sudo] password for ...` three separate times, not once. A `2>/dev/null` on one of those calls doesn't just hide noise, it hides that prompt, so the command silently never runs. Letting a command fail (`|| true`) and hiding *why* it failed are independent choices — keep the first, never do the second, on any `sudo` call reached through `distrobox-host-exec`.

**Match process names with `pgrep -f`/`pkill -f`, not `-x`, unless you're certain the daemon doesn't rename itself.** `-x` requires an exact match against `/proc/[pid]/comm`; several real daemons (CoreFreq's `corefreqd` included, which forks into `corefreqd-pmgr`/`corefreqd-cmgr` worker processes via `prctl`/`PR_SET_NAME`) rename their own processes away from the binary's name, so `-x <binary-name>` silently matches nothing even while the daemon is running. This is easy to misdiagnose as a `distrobox-host-exec`/host-spawn visibility problem — confirm with `ps aux | grep -i <name>` run directly on the host before assuming that.
- Fix: install `flatpak` on the host (e.g. `sudo pacman -S flatpak` on Arch-family hosts) — no container rebuild needed, this is purely a host-side gap.

### Base image selection

| Situation | Base image |
|---|---|
| AMD GPU access, Vulkan, GUI rendering (egui/WGPU) | `registry.fedoraproject.org/fedora:43` |
| App with official Ubuntu/Debian APT repo | `ubuntu:24.04` |
| Kernel module compilation (must match host ABI) | `ubuntu:24.04`, or a `Dockerfile.ubuntu`/`Dockerfile.arch` pair if the app must also support Arch-family hosts — see [Multi-base-image pattern](#multi-base-image-pattern) |
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

`./tools.sh` with no arguments opens the **Go dashboard** in `tui/` (Bubble Tea v2, modelled on `gh-dash`): category tabs, an app table, a rendered-README panel, native wizard pages and a keybinding footer. `tools install` builds the binary — host Go if present, otherwise a throwaway `golang:1.25-alpine` container — and never fails the install if it cannot. See [`tui/README.md`](tui/README.md) and [`docs/tui-migration.md`](docs/tui-migration.md).

The old `whiptail` menu (`lib/tui.sh`) is the fallback, used when the binary is missing or `LT_NO_GO_TUI=1` is set. It renders each row as `description | image ref | box name` with fixed column widths (26 / 34), so **keep `description` under ~26 chars** while that fallback exists — the dashboard itself sizes columns to the terminal and does not need the limit.

## Working practices

- **Read `.memory.md` first**: before touching any existing app, read `apps/<name>/.memory.md`. It contains implementation context, pitfalls, and decisions that are not obvious from the code.
- **Keep `.memory.md` current**: after any change to an app, update its `.memory.md` to reflect what changed and why. Add new pitfalls as they are discovered.
- **Keep `ROADMAP.md` current**: if a task completes, unblocks, or adds a planned item, update `ROADMAP.md` to reflect the new state.
- **Keep the screenshots current**: `README.md` embeds `docs/images/*.png`, generated by `scripts/screenshots.sh` from the dashboard's own `--render` mode. Rerun it after any change to the dashboard's layout, wizard pages, or the apps it shows; it needs `freeze` (`go install github.com/charmbracelet/freeze@latest`) and ImageMagick.
- **Keep `README.md` current**: if a new app is added or an existing one changes significantly (new features, renamed exports, different usage), update `README.md`.
- **Every new or touched app needs `apps/<name>/README.md`**: cover install, exported commands with examples, storage paths, and any GPU/env notes. Link to it from the main `README.md` table: `[`name`](apps/name/README.md)`. If you're modifying an existing app that doesn't have one, add it in the same change — the dashboard renders it in the info panel beside the app table, which is the user's primary reference for the app. `tools setup` deliberately does not print it (it prints the path only); use `post-install` for anything that must be seen right after an install.

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
- **Prebuilt kernel-headers tools (e.g. `tools/objtool/objtool`) are tied to the *host's* binutils, not the container's**: kernel-headers packages ship prebuilt binaries linked against whatever binutils built that kernel. On a rolling-release host (CachyOS, Arch) these can need a newer shared library (e.g. `libsframe.so.3`) than an older container distro packages, failing with `error while loading shared libraries: ... not found` — and since `/lib/modules`/`/usr/src` are mounted read-only, the container can't just rebuild the tool from source. Fix: `ldd` the prebuilt binary, and for each `not found` library, copy it from `/run/host/usr/lib` (Distrobox mounts the full host root read-only there in every container, no extra `create_flags` needed) into a small scratch dir, then point `LD_LIBRARY_PATH` at just that dir — never add the host's entire lib tree to `LD_LIBRARY_PATH` directly, or host copies of glibc/libstdc++/etc. can shadow the container's own and break the build in more confusing ways. See `apps/corefreq/Dockerfile.ubuntu`/`Dockerfile.arch` for the implementation.
- **`pahole` is needed by any kernel with `CONFIG_DEBUG_INFO_BTF=y`**, not just Arch/CachyOS — this includes stock Ubuntu kernels. Missing it fails the module build late, at the BTF-encoding step (`gen-btf.sh: pahole: not found`), well after compilation succeeds — easy to mistake for a different problem. The **package name differs by distro**: Debian/Ubuntu calls it `dwarves`, Arch calls it `pahole` directly (there is no `dwarves` package on Arch — `pacman -S dwarves` fails with `target not found`, and critically, an unresolvable target aborts the *entire* `pacman -S` transaction, silently skipping every other package in the same command too). Install the right name for each base image regardless of distro.
- **`distrobox-host-exec` needs `curl` or `wget` in the container** to bootstrap its own `host-spawn` helper binary on a fresh box (it's installed per-container, not shared via `$HOME`, so every new box needs this at least once). Without either, the very first `distrobox-host-exec` call in a box silently fails: the wrapper script exits early under its own `set -o errexit`, and if the caller also uses `set -e` (common in this repo's wrapper scripts), the failure can look like nothing happened at all — no error text, just an early return. Symptom to watch for: a script that calls `distrobox-host-exec sudo insmod ...` (or similar) prints its "doing X..." message and then returns with no further output, and `dmesg` shows no corresponding kernel-side attempt (confirming the failure happened before reaching the host command at all). Any minimal/from-scratch base image (Arch, slim Ubuntu, etc.) is exposed to this — install `curl` alongside whatever else the app needs.
- **Don't let a trailing `|| true` swallow failures from an earlier `&&` in the same `RUN`**: `cmd1 && cmd2 || true` masks a `cmd1` failure just as much as a `cmd2` failure, because `&&`/`||` chain left-to-right at the same precedence (`(cmd1 && cmd2) || true`, not `cmd1 && (cmd2 || true)`). If only `cmd2` (e.g. a best-effort cache-clean step) should be allowed to fail, wrap it explicitly: `cmd1 && (cmd2 || true)`. Otherwise a broken `cmd1` — like a pacman install with a typo'd package name — reports success and commits an image layer that's silently missing everything it was supposed to install.
