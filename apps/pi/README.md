# pi

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[Pi](https://pi.dev), a minimal, extensible terminal coding agent, in an
`ubuntu:24.04` Distrobox container. It's installed from npm
(`@earendil-works/pi-coding-agent`) on Node 24, and the image also includes
`git`, `ripgrep` and the GitHub CLI (`gh`).

Pi keeps its core small: no sub-agents, plan mode, permission prompts or to-do
list built in. You add what you want with TypeScript extensions, skills, prompt
templates and Pi packages (`pi install npm:...` / `git:...`).

## Install

```bash
tools setup pi
```

Setup asks one question: **which release** to install. The list is Pi's
published GitHub releases, newest first (the default). It can also be answered
on the command line; `tools help pi` lists the releases:

```bash
tools setup pi PI_RELEASE=latest   # or a tag such as v1.4.0
```

## What you get

| Entry | What it does |
|---|---|
| `pi` (host `PATH`) | The Pi agent |
| **Pi** (menu) | Opens `pi` in a terminal window |

```bash
pi                               # interactive TUI in the current directory
pi -p "explain this repo"        # print mode: one-shot, non-interactive
pi install npm:@example/pi-tools # add a Pi package (extensions, skills, themes)
pi list                          # configured packages
pi --version
```

Inside the TUI, `/login` connects a provider subscription or API key, `/model`
(or `Ctrl+L`) switches model, `/tree` branches from an earlier point in the
session, and `Enter` while the agent is working sends a steering message.

## Updating

Rerun `tools setup pi` and pick a newer release. The install step always
re-downloads, so the build cache never keeps an old version. Don't use
`pi update` for Pi itself: it installs into the image, which is read-only to
you and replaced on the next rebuild. `pi update --extensions` (packages only)
is fine; they live in your home directory.

## Storage

`$HOME` is shared with the host, so everything survives a rebuild:

| Path | Contents |
|---|---|
| `~/.pi/agent/` | Settings (`settings.json`), credentials, sessions, installed Pi packages |
| `<project>/.pi/` | Project settings and packages (loaded after project trust) |
| `<project>/AGENTS.md` | Per-project instructions Pi reads |

## Notes

- **No permission prompts.** Pi runs shell commands without asking. The box
  isolates packages, not files: it shares your `$HOME`, so Pi can read and write
  everything you can.
- **Commands run inside the box.** Shell commands Pi runs execute in `pi-box`
  (Ubuntu 24.04), not on the host. Toolchains installed only on the host aren't
  on its `PATH`.
- **API keys are never baked into the image.** Add them at runtime with
  `/login` or through provider environment variables.
- **Install telemetry** (anonymous install/update reporting) is on by default
  upstream; set `"enableInstallTelemetry": false` in `~/.pi/agent/settings.json`
  to turn it off.
