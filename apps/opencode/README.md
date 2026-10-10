# opencode

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[OpenCode](https://opencode.ai), an open-source AI coding agent with a terminal
UI, in an `ubuntu:24.04` Distrobox container. It's installed with OpenCode's
official installer, and the image also includes `git` and the GitHub CLI (`gh`).

## Install

```bash
tools setup opencode
```

The setup question can also be answered on the command line, which asks
nothing and runs straight through. `tools help opencode` lists the releases;
leave the parameter out to get the newest:

```bash
tools setup opencode OPENCODE_RELEASE=v1.18.35
```

Setup asks one question: **which release** to install. The list is OpenCode's
published GitHub releases, newest first (the default), with each release's notes
beside it in the dashboard. A non-interactive `tools setup opencode` installs the
newest release.

## What you get

| Entry | What it does |
|---|---|
| `opencode` (host `PATH`) | The OpenCode agent |
| **OpenCode** (menu) | Opens `opencode` in a terminal window |

```bash
opencode                      # TUI in the current directory
opencode run "explain this repo"   # one-shot, non-interactive
opencode auth login           # add a provider API key
opencode --version
```

## Updating

Rerun `tools setup opencode` and pick a newer release. The install step always
re-downloads, so the build cache never keeps an old version.

## Storage

`$HOME` is shared with the host, so everything survives a rebuild:

| Path | Contents |
|---|---|
| `~/.config/opencode/` | Config (`opencode.json`/`opencode.jsonc`) and installed plugins |
| `~/.local/share/opencode/` | Provider logins (`auth.json`), sessions (`opencode.db`), logs |
| `~/.cache/opencode/` | Cached model list (`models.json`) and helper binaries it downloads |

## Notes

- **Commands run inside the box.** Shell commands and tools that OpenCode runs
  in a project execute in `opencode-box` (Ubuntu 24.04), not on the host.
  Toolchains installed only on the host aren't on its `PATH`.
- **API keys are never baked into the image.** Add them at runtime with
  `opencode auth login` or through provider environment variables.
- OpenCode's own self-update writes to its install location inside the image and
  is lost on the next rebuild. Use `tools setup opencode` instead.
