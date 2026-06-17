# jetbrains-toolbox

JetBrains Toolbox App in a Distrobox container. Manages JetBrains IDEs (IDEA, PyCharm, GoLand, RustRover, etc.) installed into the shared `$HOME` — IDE binaries and their `.desktop` files appear on the host immediately.

## Install

```bash
tools setup jetbrains-toolbox
```

On first launch the wrapper installs SDKMAN (Java/Kotlin SDKs), rustup (stable toolchain), and cargo-binstall + bacon + just into `~/.sdkman` and `~/.cargo` respectively. These directories live in the shared `$HOME` and are immediately visible on the host and in every other Distrobox.

## Exported commands

| Command | Description |
|---|---|
| `jetbrains-toolbox` | Launch the system-tray Toolbox manager |

IDEs installed by Toolbox are launched directly from their own `.desktop` entries — they run outside the container using JetBrains' bundled JDK.

## Rust development tools

Installed at first launch into `~/.cargo/bin` (shared `$HOME`, visible on host):

| Tool | Description |
|---|---|
| `rustup` | Rust toolchain manager |
| `cargo` | Rust package manager / build tool |
| `bacon` | Background Rust code checker (runs `cargo check` on save) |
| `just` | Command runner (like Make, but simpler) |

`~/.cargo/bin` is on PATH inside the container (via `/etc/bash.bashrc` and `/etc/zsh/zshrc`) and should also be on your host PATH if you source the same files.

To add a toolchain or component:
```bash
distrobox enter jetbrains-toolbox-box
rustup toolchain install nightly
rustup component add rust-analyzer
```

## Java / JVM tools (SDKMAN)

SDKMAN is installed at first launch to `~/.sdkman`. Use it from inside the container:

```bash
distrobox enter jetbrains-toolbox-box
sdk install java 21-tem
sdk install kotlin
```

## Persistent storage

| Path | Contents |
|---|---|
| `~/.local/share/JetBrains/Toolbox/` | Toolbox state, installed IDEs |
| `~/.sdkman/` | SDKMAN — Java, Kotlin, Gradle SDKs |
| `~/.cargo/`, `~/.rustup/` | Rust toolchain, cargo-installed tools |

## Notes

- Toolbox replaces the distrobox-exported `.desktop` on first run — this is expected.
- Tray icon is refreshed by the wrapper on every launch to prevent the grey-exclamation-mark regression.
- The Docker CLI inside the container is bridged to host Podman via `distrobox-host-exec podman`.
