# orca

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[Orca](https://github.com/stablyai/orca) by Stably AI: a desktop IDE for running
a fleet of coding agents in parallel (Claude Code, Codex, OpenCode, Copilot and
others), each in its own git worktree, with your own subscriptions. It's installed
from the official `.deb` of the release you pick, in an `ubuntu:24.04` Distrobox
container, and exported to the host application menu.

## Install

```bash
tools setup orca                          # newest desktop release
tools setup orca ORCA_RELEASE=v1.4.244    # a specific release
tools help orca                           # list the releases on offer
```

The dashboard asks for the release on a picker page, with each release's notes
next to the list. Only desktop releases (`vX.Y.Z`) are listed: the same repo
publishes Android pre-releases (`mobile-android-v*`), and those are filtered out.
The image picks the `amd64` or `arm64` package to match the host.

## What you get

| Entry | What it does |
|---|---|
| **Orca** (menu / `.desktop`) | Launches the app. It's the package's own `.desktop` entry, which keeps the `orca://` link handler |
| `orca-ide` (host `PATH`) | Orca's bundled command-line client, the one upstream installs as `/usr/bin/orca-ide` |
| **Orca (Terminal)** (menu) | Opens a shell inside `orca-box` |

```bash
orca-ide --help     # the CLI's commands
```

The host command is `orca-ide`, not `orca`, as upstream names it. `orca` on Linux
is GNOME's screen reader, and a `~/.local/bin/orca` would shadow it.

## Updating

Rerun `tools setup orca`, optionally with `ORCA_RELEASE=`, to move to another
release. Your settings and worktrees are kept (see below).

Orca checks for new releases itself and shows **Update Available**. On a `.deb`
install, its **Update** button downloads the package and installs it with
`sudo apt install` *inside the box*. That works, but the next `tools setup` puts
back the release you picked, so use `tools setup orca` instead.

## Storage

Distrobox shares your host `$HOME`, so Orca's state lives where it would on a
native install and survives `tools setup` rebuilds:

| Path | Contents |
|---|---|
| `~/.config/orca/` | Electron profile: settings, projects, agent sessions (`orchestration.db`), logs, caches |
| your repositories | worktrees Orca creates for each agent, next to the repo they belong to |

## Notes

- **Agents run inside `orca-box`.** Orca starts agent CLIs in the box, which
  sees the same files because `$HOME` is shared. Agents you have exported from
  other boxes (`claude`, `codex`, `opencode`, `copilot` in `~/.local/bin`) still
  work: their wrappers notice they are in a different box and go through
  `distrobox-host-exec` to the right one. That needs `flatpak` on the host; see
  the `distrobox-host-exec` notes in the main `CLAUDE.md`.
- **`jq` is in the image** for scripts that agents run in Orca's terminals, such
  as a Claude Code status line (`~/.claude/statusline.sh`) that parses its JSON
  input with `jq`. Without it the status line drops the model, token counts and
  5h/7d usage.
- **GitHub CLI.** `gh` is in the image for Orca's Tasks view and per-worktree
  PR/CI status. It reads the shared `~/.config/gh`, so a `gh auth login` on the
  host (or in any box) also covers Orca.
- **Toolchains installed only on the host are not on the box's `PATH`.** Install
  what agents need with `distrobox enter orca-box -- sudo apt install …` (that
  lasts until the next `tools setup`), or use `dev-toolbox`.
- **File associations.** The package registers Orca for Markdown, CSV and TSV
  files. Those are removed from the exported entry so Orca doesn't take over
  opening Markdown on the host; the `orca://` link handler is kept.
- **Saved logins** go into the host keyring over D-Bus (`libsecret` is in the
  image), the same way as a native install.
