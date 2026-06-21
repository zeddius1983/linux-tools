# dev-toolbox

Selectable Node.js and Python project tooling, exported to the host through
Distrobox. Commands run in an Ubuntu environment while retaining access to
projects and caches in the shared home directory.

## Install

```bash
tools setup dev-toolbox
```

The interactive wizard lets you install Node.js, uv, or both. Re-running setup
updates selected tools and removes deselected tools.

For a non-interactive install, set up the box and then run the installer:

```bash
tools setup dev-toolbox
dev-toolbox-install --tools "node uv"
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

Examples:

```bash
node --version
npx cowsay "hello"
uv init example-project
uv run python --version
uvx ruff check .
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
- Good future wizard additions are `pnpm`, `bun`, and `deno` for JavaScript,
  plus `just` and `task` as language-independent project runners. Python CLI
  applications generally do not need dedicated entries because `uvx` runs them.
