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
| **Orca** (menu / `.desktop`) | Launches the app and its tray icon. It's the package's own `.desktop` entry, which keeps the `orca://` link handler |
| `orca-ide` (host `PATH`) | Orca's bundled command-line client, the one upstream installs as `/usr/bin/orca-ide` |
| `orca-tray` (host `PATH`) | The tray icon, started with Orca from the menu (see below). Run it yourself to get the icon back after closing it |
| `orca-host-shell` (host `PATH`) | Runs your host login shell. Orca's terminals use it by default (see below); `orca-host-zsh` and `orca-host-bash` pick a fixed shell |
| **Orca (Terminal)** (menu) | Opens a shell inside `orca-box` |

```bash
orca-ide --help     # the CLI's commands
```

The host command is `orca-ide`, not `orca`, as upstream names it. `orca` on Linux
is GNOME's screen reader, and a `~/.local/bin/orca` would shadow it.

### Tray icon

Closing Orca's window, or a plain **Quit**, leaves its terminals running in a
background daemon, agents included, so they're still there next time. Orca
itself shows nothing for this on Linux, so the box adds a tray icon:

- **Orca: window open / window closed** and the number of terminal sessions
  still running.
- **Open Orca** brings the window back.
- **Quit Orca Completely…** asks first, then stops the app, the daemon and
  every terminal session. It's the same as Orca's own **Quit Completely…** menu
  item, but it works without the window.

The icon closes by itself once nothing of Orca is running. It needs a desktop
with a StatusNotifier tray (Cinnamon, KDE, or GNOME with the AppIndicator
extension). Without one, Orca still starts normally.

### Host terminals

Orca's terminals, and the agents launched in them, open on the **host**, in your
login shell (zsh, bash, fish or whatever `getent passwd` lists for you), not
inside `orca-box`. Tools, `PATH` and dotfiles are the host's, as with a native
install.

This works because the launcher sets `SHELL` to `orca-host-shell`, and Orca uses
`$SHELL` when its own **Custom shell** setting is empty. The setting wins when
it is set, so you can still choose:

| Custom shell | Terminals open |
|---|---|
| *(empty)* | on the host, in your login shell (the default) |
| `/usr/bin/orca-host-zsh` or `/usr/bin/orca-host-bash` | on the host, in that shell |
| `/bin/bash` | inside `orca-box` |

Leave **Custom args** empty, or `-l` for a login shell. Don't set Custom shell
to `distrobox-host-exec` itself: agents launched from Orca's menu ignore Custom
args and pass `-l` straight to it, which fails with `ERROR: Invalid flag '-l'`.

Going to the host needs `flatpak` installed on the host (see the
`distrobox-host-exec` notes in the main `AGENTS.md`); without it the terminal
closes as soon as it opens. Orca only gets the default when started from the
menu entry or the tray. A bare `distrobox enter orca-box -- /opt/Orca/orca-ide`
keeps in-box terminals.

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

- **Agents run in Orca's terminals, so on the host by default** (see Host
  terminals). Agents you have exported from other boxes (`claude`, `codex`,
  `opencode`, `copilot` in `~/.local/bin`) work there as on any host shell. With
  in-box terminals they still work: their wrappers notice they are in a
  different box and go through `distrobox-host-exec` to the right one.
- **`jq` is in the image** for scripts that agents run in in-box terminals, such
  as a Claude Code status line (`~/.claude/statusline.sh`) that parses its JSON
  input with `jq`. Without it the status line drops the model, token counts and
  5h/7d usage.
- **Terminals outlive the window.** Orca keeps its terminals, and the agents
  in them, in a background daemon that keeps running after you close the window
  or choose Quit. The tray icon above shows that and can stop it, as can
  **Quit Completely…** in Orca's menu. `tools setup orca` and `tools rm orca` stop Orca and the
  daemon before removing the box, so they end every Orca terminal session. Run
  them from the host or from another box's terminal, not from inside Orca.
- **GitHub CLI.** `gh` is in the image for Orca's Tasks view and per-worktree
  PR/CI status. It reads the shared `~/.config/gh`, so a `gh auth login` on the
  host (or in any box) also covers Orca.
- **With in-box terminals, toolchains installed only on the host are not on the
  box's `PATH`.** Install what agents need with `distrobox enter orca-box -- sudo apt install …` (that
  lasts until the next `tools setup`), or use `dev-toolbox`.
- **File associations.** The package registers Orca for Markdown, CSV and TSV
  files. Those are removed from the exported entry so Orca doesn't take over
  opening Markdown on the host; the `orca://` link handler is kept.
- **Saved logins** go into the host keyring over D-Bus (`libsecret` is in the
  image), the same way as a native install.
