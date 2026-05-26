# linux-tools

Manages Linux GUI and CLI applications inside [Distrobox](https://distrobox.it/) containers, keeping the host system clean. Each app lives in its own container and is exported to the host so it behaves like a natively installed application.

## Prerequisites

- [Distrobox](https://distrobox.it/#installation) installed on the host
- [Podman](https://podman.io/docs/installation) (preferred) or Docker

## Usage

### Interactive TUI (recommended)

```bash
./tools.sh
```

A checklist shows all available apps with their current status (`image:OK / image:--` and `box:OK / box:--`). Use **SPACE** to toggle, **ENTER** to confirm, then pick an action.

### Install (one-time)

Symlinks `tools` into `~/.local/bin` and wires up bash completion in `~/.bashrc`:

```bash
./tools.sh install
source ~/.bashrc
```

After that, use `tools` from anywhere instead of `./tools.sh`.

### CLI

```bash
tools setup <app>    # full install — removes any existing box+image first
tools export <app>   # re-export after editing an exports file
tools build <app>    # build container image only
tools create <app>   # create distrobox from built image
tools rm <app>       # remove distrobox (image is kept)
tools list           # show status of all apps
```

`make setup-<app>`, `make build-<app>`, etc. are available as shortcuts.

After setup, apps appear in your system application menu. Log out and back in if they don't show immediately.

### Shell access

```bash
distrobox enter <app>-box
```

## Available apps

| App | Description | Box |
|---|---|---|
| `chrome` | Google Chrome browser | `chrome-box` |
| `claude-code` | Claude Code CLI | `claude-code-box` |
| `lmstudio` | LM Studio (AMD GPU) | `lmstudio-box` |
| `amdgpu_top` | AMD GPU monitor — TUI + GUI | `amdgpu_top-box` |

## Adding a new app

Create `apps/<name>/` with these files:

**`Dockerfile`** — container image:

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    myapp \
    && rm -rf /var/lib/apt/lists/*
```

**`exports`** — what to expose to the host:

```
# bin     — export binary to ~/.local/bin
# desktop — create a terminal-launched shortcut
# gui     — create a non-terminal shortcut (GUI apps)
# app     — export a .desktop installed by the package manager
bin:myapp-cli
desktop:myapp:My App
```

**`description`** — one-line label for the TUI (keep it short):

```
My app description
```

Optionally add **`icon.png`** or **`icon.svg`** to use a custom icon for all exported shortcuts.

Then run:

```bash
./tools.sh setup myapp
```

## Testing on macOS (OrbStack)

Use [OrbStack](https://orbstack.dev) to spin up a lightweight Ubuntu VM:

```bash
orb create ubuntu:24.04 linux-tools-test
orb shell linux-tools-test

git clone git@github.com:zeddius1983/linux-tools.git
cd linux-tools
bash scripts/setup-vm.sh
./tools.sh
```

Rendering GUI windows requires X11 forwarding and is easier to verify on a real Linux machine.
