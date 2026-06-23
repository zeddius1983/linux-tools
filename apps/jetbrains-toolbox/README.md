# jetbrains-toolbox

JetBrains Toolbox App in a Distrobox container. Manages JetBrains IDEs (IDEA,
PyCharm, GoLand, RustRover, etc.) installed into the shared `$HOME` — IDE
binaries and their `.desktop` files appear on the host immediately.

## Install

```bash
tools setup jetbrains-toolbox
```

Toolbox only manages the JetBrains GUI app and IDE lifecycle. Install language
runtimes and project toolchains with `dev-toolbox` so they are available
independently of whether JetBrains IDEs are installed.

## Exported commands

| Command | Description |
|---|---|
| `jetbrains-toolbox` | Launch the system-tray Toolbox manager |

IDEs installed by Toolbox are launched directly from their own `.desktop` entries — they run outside the container using JetBrains' bundled JDK.

## Toolchains

Rust toolchains are installed by `dev-toolbox` and exported as `rustup`,
`rustc`, `cargo`, and `bacon`. Configure RustRover or IntelliJ Rust projects to
use those exported commands.

Java support should use JetBrains' bundled JDK for the IDE process itself.
Project JDKs and SDKMAN-managed runtimes belong in `dev-toolbox`; use `sdk`
there and point IDE projects at `~/.sdkman/candidates/java/current`.

## Persistent storage

| Path | Contents |
|---|---|
| `~/.local/share/JetBrains/Toolbox/` | Toolbox state, installed IDEs |

## Notes

- Toolbox replaces the distrobox-exported `.desktop` on first run — this is expected.
- Tray icon is refreshed by the wrapper on every launch to prevent the grey-exclamation-mark regression.
- The JetBrains-bundled JDK is left untouched; it runs the IDE itself.
