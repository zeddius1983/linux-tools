# dev-toolbox

Selectable Node.js, Python, Rust, JVM, and Firecrawl tooling, exported to the
host through Distrobox. Commands run in an Ubuntu environment while retaining
access to projects and caches in the shared home directory.

## Install

```bash
tools setup dev-toolbox
```

The interactive wizard lets you install Node.js, uv, Rust, SDKMAN, language
servers, and Firecrawl CLI. Re-running setup updates selected tools and removes
deselected tools. Selecting Firecrawl also selects its managed Node.js runtime
dependency. Selecting Rust Analyzer also selects the managed Rust toolchain.

For a non-interactive install, set up the box and then run the installer:

```bash
tools setup dev-toolbox
dev-toolbox-install --tools "node uv firecrawl rust sdkman rust-lsp java-lsp kotlin-lsp"
```

Node.js defaults to major version 22. Override it for a manual install with
`--node-major` or `DEV_TOOLBOX_NODE_MAJOR`:

```bash
dev-toolbox-install --tools "node uv" --node-major 24
```

## Exported commands

| Command | Description |
|---|---|
| `dev-toolbox-install` | Install, update, or remove selected runtimes |
| `node` | Node.js runtime |
| `npm` | Node.js package manager |
| `npx` | Run commands from npm packages |
| `uv` | Python project and package manager |
| `uvx` | Run commands from Python packages |
| `firecrawl` | Search, scrape, crawl, and run Firecrawl agent jobs |
| `rustup` | Rust toolchain manager |
| `rustc` | Rust compiler |
| `cargo` | Rust package manager and build tool |
| `bacon` | Background Rust checker |
| `rust-analyzer` | Rust language server |
| `sdk` | SDKMAN command wrapper for JVM toolchains |
| `jdtls` | Eclipse JDTLS Java language server |
| `kotlin-lsp` | Official Kotlin language server |

Examples:

```bash
node --version
npx cowsay "hello"
uv init example-project
uv run python --version
uvx ruff check .
firecrawl search "Linux containers" --limit 5
rustup toolchain install nightly
cargo test
bacon
sdk install java 21-tem
rust-analyzer --version
jdtls
kotlin-lsp
```

Enter the complete development environment when a workflow invokes several
tools internally:

```bash
distrobox enter dev-toolbox-box
```

## Persistent storage

| Path | Contents |
|---|---|
| `~/.local/share/dev-toolbox/node/` | Selected Node.js runtime, npm, and npx |
| `~/.local/share/dev-toolbox/uv/` | Selected uv and uvx binaries |
| `~/.local/share/dev-toolbox/firecrawl/` | Selected Firecrawl CLI npm package |
| `~/.cargo/` | Cargo, cargo-installed tools, and Rust command shims |
| `~/.rustup/` | Rustup-managed Rust toolchains |
| `~/.sdkman/` | SDKMAN install and SDKMAN-managed candidates |
| `~/.local/share/dev-toolbox/jdtls/` | Selected Eclipse JDTLS payload |
| `~/.local/share/dev-toolbox/kotlin-lsp/` | Selected official Kotlin LSP payload |
| `~/.npm/` | npm download cache |
| `~/.cache/uv/` | uv package and build cache |
| `~/.local/share/uv/` | uv-managed Python versions and tools |

These paths and project directories are shared with the host by Distrobox.

## Notes

- Exported commands remain on the host when a runtime is deselected. Invoking
  one prints a clear installation message instead of falling through to a host
  runtime with the same name.
- Native npm modules and Python virtual environments are built against the
  container. Run them through the exported commands or from inside
  `dev-toolbox-box`, rather than directly with host runtimes.
- Rust native crates build inside the container with the dev-toolbox compiler
  and build dependencies. Configure JetBrains IDEs to use the exported
  `cargo`, `rustc`, and `rustup` commands from this app.
- Deselecting Rust during setup does not remove `~/.cargo` or `~/.rustup`, so
  existing Rust toolchains and cargo-installed tools are preserved.
- SDKMAN is exported as `sdk` by sourcing SDKMAN's shell function inside the
  wrapper. After installing a JDK, configure JetBrains IDEs to use
  `~/.sdkman/candidates/java/current`.
- Deselecting SDKMAN during setup does not remove `~/.sdkman`, so existing
  Java, Gradle, Kotlin, and other SDKMAN candidates are preserved.
- `jdtls` and `kotlin-lsp` prefer `~/.sdkman/candidates/java/current` when
  `JAVA_HOME` is not set. JDTLS needs Java 21 or newer; the official Kotlin LSP
  currently needs JDK 25.
- Deselecting `java-lsp` or `kotlin-lsp` removes only their payload directories
  under `~/.local/share/dev-toolbox`. Deselecting `rust-lsp` does not remove
  `~/.cargo` or `~/.rustup`.
- Good future wizard additions are `pnpm`, `bun`, and `deno` for JavaScript,
  plus `just` and `task` as language-independent project runners. Python CLI
  applications generally do not need dedicated entries because `uvx` runs them.
