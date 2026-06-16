# claude-code

[Claude Code](https://docs.claude.com/en/docs/claude-code/overview), Anthropic's terminal AI coding assistant, packaged as a Distrobox container.

Installed from the **official native-binary install script** (`https://claude.ai/install.sh`) at image-build time, so each rebuild pulls the latest `claude` release — typically several patch versions ahead of the APT channel.

## Install

```bash
tools setup claude-code
```

Build time: ~1–2 minutes (downloads the ~240 MB native binary).

## Commands

| Export | Type | Description |
|---|---|---|
| `claude` | `bin` | The Claude Code CLI on the host `PATH` |
| `Claude Code` | `desktop` | Terminal launcher in your app menu |

The container also bundles `git`, `gh` (GitHub CLI), `jq`, `curl`, and `node`/`npx` (Node.js 22 LTS) so Claude Code can run common operations — and launch npx-based MCP servers like [context7](https://github.com/upstash/context7) — without needing extra host tools.

## MCP servers

`npx` is available inside the container, so MCP servers distributed as npx packages work out of the box. For example, to add context7:

```bash
claude mcp add context7 -- npx -y @upstash/context7-mcp
```

The MCP config is written to `~/.claude.json` on the host (shared `$HOME`), and `npx` resolves the server from the container's Node.js install at runtime.

## Usage

```bash
# Start an interactive session in the current directory
claude

# Continue the last conversation in this dir
claude --continue

# Non-interactive one-shot
claude -p "Explain what this repo does"

# Pick a different model
claude --model claude-sonnet-4-7

# Show version (handy after a rebuild)
claude --version
```

Full options: `claude --help`.

## Config and state

Distrobox shares `$HOME` with the host, so all Claude Code state lives where you'd expect it on the host:

```
~/.claude/                 # config, MCP servers, projects, sessions
~/.claude.json             # main settings file
```

Anything written by `claude` from inside the container shows up on the host immediately, and vice versa. You can read/edit settings outside the container with your normal editor.

## Updating

Rebuild the image to pick up a newer `claude`:

```bash
tools setup claude-code
```

`setup` is idempotent — it removes the existing box and image first, then rebuilds from scratch. The install script always fetches the latest release.

`claude install latest` from inside the container is **not** the right path here: that writes a binary to `$HOME/.local/share/claude/versions/...` on the host, but the host's `bin:claude` wrapper always invokes the container's `/usr/bin/claude` — so the update would be invisible to the exported command. Use `tools setup claude-code` instead.

## Shell access

```bash
tools enter claude-code           # via tools
distrobox enter claude-code-box   # directly via distrobox
```

Inside the box, `claude` is at `/usr/bin/claude`, and your `$HOME` is the same as on the host.

## Notes

- The APT channel (`downloads.claude.ai/claude-code/apt/stable`) was previously used here but lags the install script by many patch versions; we switched to the install script for that reason.
- Claude Code itself ships as a self-contained native binary and does **not** require Node.js. Node.js 22 LTS is bundled separately solely to provide `npx` for npx-based MCP servers.
