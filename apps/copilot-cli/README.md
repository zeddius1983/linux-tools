# copilot-cli

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

GitHub's [Copilot CLI](https://github.com/github/copilot-cli) (`copilot`), an
agentic coding assistant for the terminal: it reads and edits files in your
repository, runs shell commands, and works with GitHub issues and pull requests,
asking before it acts. It is installed with GitHub's own installer in an
`ubuntu:24.04` Distrobox container, together with the GitHub CLI (`gh`) and `git`.

You need a GitHub Copilot subscription (any plan, including Copilot Free) to use it.

## Install

```bash
tools setup copilot-cli
```

## Commands

| Export | Type | Description |
|---|---|---|
| `copilot` | `bin` | Copilot CLI on the host `PATH` |
| **GitHub Copilot CLI** | `desktop` | Opens `copilot` in a terminal window from the app menu |

## Signing in

Run `copilot` and type `/login`, or sign in from the shell first:

```bash
copilot login                          # browser / device-code flow
gh auth token | copilot login --with-token   # reuse an existing gh login
```

A token in the environment also works, which suits scripts and CI. The CLI checks
`COPILOT_GITHUB_TOKEN`, then `GH_TOKEN`, then `GITHUB_TOKEN`; a fine-grained
personal access token needs the **Copilot Requests** permission.

## Usage

```bash
copilot                                # interactive session in the current directory
copilot --model <name>                 # pick a model at startup (or /model inside)
copilot --continue                     # continue the most recent session
copilot --resume                       # resume a session (or --resume=<id>)
copilot -p "Explain this repository"   # one-shot prompt, then exit
copilot -C ~/src/project               # start in another directory
```

Inside a session, `/` lists the slash commands (`/model`, `/login`,
`/permissions`, ...). Copilot asks before it runs tools or touches files outside
the working directory; `--allow-all-tools` / `--yolo` skip those prompts, so use
them only in a repository you are happy for it to change freely.

## Storage

`$HOME` is shared with the host, so Copilot's login, settings and session history
stay under `~/.copilot/` across rebuilds:

| Path | Contents |
|---|---|
| `~/.copilot/config.json`, `settings.json` | Configuration |
| `~/.copilot/session-state/`, `session-store.db` | Saved sessions (for `--resume`) |
| `~/.copilot/logs/` | Logs |

## Updating

The installer runs at image-build time, so rebuilding is how you update:

```bash
tools setup copilot-cli
```

This replaces the box and image; `~/.copilot/` is kept.

## Shell access

```bash
distrobox enter copilot-cli-box
```

## Notes

- Commands Copilot runs execute inside `copilot-cli-box` (Ubuntu 24.04), not on
  the host. It sees your files through the shared `$HOME`, but host-only tools
  and packages are not available to it.
- `gh` is in the box, so Copilot can query issues and pull requests once you
  have run `gh auth login` (on the host or in the box; the login lives in the
  shared `~/.config/gh/`).
