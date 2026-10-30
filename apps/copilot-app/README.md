# copilot-app

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

The [GitHub Copilot app](https://github.com/features/copilot), GitHub's desktop app
for agent work: start Copilot sessions against your repositories, follow and steer
them, and review the resulting pull requests and issues in one window. It is
installed from GitHub's official `.deb` ([`github/app`](https://github.com/github/app)
releases) in an `ubuntu:24.04` Distrobox container and exported to the host
application menu.

Any [GitHub Copilot plan](https://github.com/features/copilot/plans) works,
including Copilot Free and Copilot Student. Without a plan you can still use it by
bringing your own key (BYOK) for your own model provider.

## Install

```bash
tools setup copilot-app
```

No wizard and no `create_flags`. The image picks the `x64` or `arm64` package to
match the host.

## What you get

| Entry | What it does |
|---|---|
| **GitHub Copilot** (menu) | Launches the app (the package's own `.desktop`, pointed at the `copilot-app` launcher) |
| `copilot-app` (host `PATH`) | The same launcher, for starting it from a terminal or another box |
| **GitHub Copilot (Terminal)** (menu) | Opens a shell inside `copilot-app-box` |

```bash
copilot-app                  # start the app
```

## Links

The app opens `ghapp://`, `github-app://` and `gh://` links. On every start,
`copilot-app` registers a hidden handler for them,
`~/.local/share/applications/copilot-app-box-url-handler.desktop`, and makes it the
default in `~/.config/mimeapps.list`. Its command is `~/.local/bin/copilot-app`,
which works from the host and from inside other boxes, so a link clicked in
[`chrome`](../chrome/README.md) (`chrome-box`) opens the app too. A link opened
while the app is running is handed to the open window.

The handler is written when the app starts, so links open the app only after it
has been started once since the last `tools setup`.

## Signing in

The app signs in with your GitHub account on first start. It shares `~/.copilot/`
with [`copilot-cli`](../copilot-cli/README.md) through the shared `$HOME`, so if
you have already signed in to Copilot on this machine, it may start signed in.

## Updating

```bash
tools setup copilot-app
```

Every setup downloads the current release, so this is the update path. The
`.deb` doesn't add an APT repository, so `apt upgrade` inside the box won't
update it.

## Storage

Distrobox shares your host `$HOME`, so the app's state lives where it would on a
native install and survives `tools setup` rebuilds:

| Path | Contents |
|---|---|
| `~/.copilot/` | Sessions, chats, settings and logs; shared with `copilot-cli` |
| `~/.config/github-copilot/` | Copilot auth database |
| `~/.cache/github-copilot-sdk/` | The Copilot runtime the app downloads and runs locally |
| `~/.cache/github-copilot-git-*`, `~/.cache/copilot-desktop-gh-*` | The app's own bundled `git` and `gh` |

## Notes

- **Local sessions run inside the box.** When the app works on "This computer",
  its commands run in `copilot-app-box` (Ubuntu 24.04), not on the host. Your
  files are the same because `$HOME` is shared, but toolchains installed only on
  the host are not available. Install what you need with
  `distrobox enter copilot-app-box -- sudo apt install …`; that lasts until the
  next `tools setup`.
- **Sound and voice input** go through the host's PulseAudio/PipeWire. The image
  routes ALSA there, since the app has no audio device in the box otherwise.
- The `.deb` is ~370 MB, so the image is large and every rebuild re-downloads it.
