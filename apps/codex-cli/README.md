# codex-cli

[OpenAI Codex CLI](https://developers.openai.com/codex/cli) packaged in an
Ubuntu Distrobox and exported as both a host command and a terminal launcher.
The image also includes Git, GitHub CLI (`gh`), and Bubblewrap.

## Install

```bash
tools setup codex-cli
```

Interactive setup opens a release picker. Choose `latest` (the default) to
follow OpenAI's stable standalone-installer channel, or pin one of the ten most
recent stable releases. The release list is read from the official
`openai/codex` tags at setup time.

A non-interactive setup skips the wizard and installs `latest`. Every setup
refreshes the installer layer, so rerunning the command picks up a newly
published stable release instead of reusing an older cached binary.

## Commands

| Export | Type | Description |
|---|---|---|
| `codex` | `bin` | Codex CLI on the host `PATH` |
| `Codex CLI` | `desktop` | Codex in a terminal from the app menu |

Examples:

```bash
# Start an interactive session in the current repository
codex

# Run one non-interactive task
codex exec "Explain this repository"

# Resume a saved session
codex resume

# Check the packaged version
codex --version
```

## Configuration and storage

Distrobox shares the host home directory with the container. Codex therefore
keeps authentication, configuration, sessions, plugins, and other state under
the usual host path:

```text
~/.codex/
```

The container can also see repositories and files under the host home
directory. Its system packages and `/usr/bin/codex` remain isolated in
`codex-cli-box`.

## Updating or changing versions

Run setup again and select a release:

```bash
tools setup codex-cli
```

This replaces the existing box and image while preserving `~/.codex/` in the
shared home directory. Prefer this flow over `codex update` inside the box:
the exported host wrapper launches the image's `/usr/bin/codex`, which is not
writable by the container user, so an in-container self-update would not
replace the packaged executable.

If the release picker cannot reach GitHub, it still offers `latest`; the
Dockerfile then resolves that through OpenAI's installer.

## Shell access

```bash
tools enter codex-cli
distrobox enter codex-cli-box
```
