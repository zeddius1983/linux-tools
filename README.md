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

Select an app with the arrow keys and press **ENTER**. Each app shows its description, image ID, image ref, and box name. After selecting, choose an action (Setup / Build / Create / Export / Enter / Remove). Apps with optional configuration (e.g. MCP servers for Claude Code) show a wizard before the final confirmation.

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
tools enter <app>    # open a shell inside the box
tools rm <app>       # remove distrobox (image is kept)
tools list           # show status of all apps
```

`make setup-<app>`, `make build-<app>`, etc. are available as shortcuts.

After setup, apps appear in your system application menu. Log out and back in if they don't show immediately.

### Shell access

```bash
tools enter <app>          # via tools (also available in the TUI)
distrobox enter <app>-box  # directly via distrobox
```

## Available apps

| App | Description | Box |
|---|---|---|
| `amdgpu_top` | AMD GPU monitor — TUI + GUI | `amdgpu_top-box` |
| `chrome` | Google Chrome browser | `chrome-box` |
| `claude-code` | Claude Code CLI | `claude-code-box` |
| `copilot-cli` | GitHub Copilot CLI | `copilot-cli-box` |
| `corefreq` | CPU frequency and performance monitor | `corefreq-box` |
| `lmstudio` | LM Studio (local AI, AMD GPU) | `lmstudio-box` |

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
