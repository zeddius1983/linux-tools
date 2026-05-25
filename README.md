# linux-tools

Manages Linux GUI and CLI applications inside [Distrobox](https://distrobox.it/) containers, keeping the host system clean. Each app lives in its own container and is exported to the host so it behaves like a natively installed application.

## Testing on macOS (OrbStack)

If you don't have a Linux machine handy, use [OrbStack](https://orbstack.dev) to spin up a lightweight Ubuntu VM:

```bash
# Install OrbStack, then:
orb create ubuntu:24.04 linux-tools-test
orb shell linux-tools-test

# Inside the VM — clone the repo and run the setup script:
git clone git@github.com:zeddius1983/linux-tools.git
cd linux-tools
bash scripts/setup-vm.sh
```

After setup, `./manage.sh` runs fully inside the VM. You can test building images, creating distroboxes, and exporting apps. Rendering GUI windows (e.g. Chrome opening visually) requires X11 forwarding and is easier to verify on a real Linux Mint machine.

## Prerequisites

- [Distrobox](https://distrobox.it/#installation) installed on the host
- [Podman](https://podman.io/docs/installation) (preferred) or Docker

## Project structure

```
linux-tools/
├── apps/
│   └── <app>/
│       ├── Dockerfile   # container image definition
│       └── exports      # what to export to the host
├── manage.sh            # main CLI
└── Makefile             # convenience wrapper around manage.sh
```

## Naming conventions

| Artifact | Pattern | Example |
|---|---|---|
| Container image | `linux-tools/<app>:latest` | `linux-tools/chrome:latest` |
| Distrobox name | `<app>-box` | `chrome-box` |

## Usage

### Interactive TUI (recommended)

Run with no arguments to open the interactive manager:

```bash
./manage.sh
```

A checklist shows all available apps with their current status (`image:OK / image:--` and `box:OK / box:--`). Use **SPACE** to toggle apps, **ENTER** to confirm, then pick an action from the menu.

### CLI — full setup

Builds the image, creates the distrobox, and exports the app to the host in one step:

```bash
./manage.sh setup chrome
# or
make setup-chrome
```

After setup, the app appears in your system application menu. Log out and back in if it doesn't show immediately.

### CLI — individual commands

```bash
# Show status of all apps
./manage.sh list

# Build the container image only
./manage.sh build chrome

# Create the distrobox from the built image
./manage.sh create chrome

# Export apps/binaries to the host
./manage.sh export chrome

# Remove the distrobox (image is kept)
./manage.sh rm chrome
```

### Open a shell inside a box

```bash
distrobox enter chrome-box
```

### Re-export after changes

If you update the exports file, re-run:

```bash
./manage.sh export chrome
```

## Available apps

| App | Image | Box |
|---|---|---|
| Google Chrome | `linux-tools/chrome:latest` | `chrome-box` |

## Adding a new app

1. Create a directory under `apps/` with a `description` file (shown in the TUI):

```bash
mkdir apps/myapp
echo "My App description" > apps/myapp/description
```

2. Write a `Dockerfile`:

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    myapp \
    && rm -rf /var/lib/apt/lists/*
```

3. Write an `exports` file declaring what to expose to the host:

```
# app: exports a .desktop entry to the system app menu
app:myapp

# bin: exports a binary to ~/.local/bin
bin:myapp-cli
```

4. Run setup:

```bash
./manage.sh setup myapp
```
