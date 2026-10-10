# chatgpt

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

OpenAI's [ChatGPT desktop app for Linux](https://learn.chatgpt.com/docs/linux/linux-app)
(preview), installed from OpenAI's official `.deb` in an `ubuntu:24.04` Distrobox
container and exported to the host application menu. Sign in with your ChatGPT
account to use chats, projects, local files and Codex.

## Install

```bash
tools setup chatgpt
```

No wizard and no `create_flags`. The image picks the `amd64` or `arm64` package to
match the host.

## What you get

| Entry | What it does |
|---|---|
| **ChatGPT** (menu / `.desktop`) | Launches the app. It's the package's own `.desktop`, so it keeps the `codex://` URL handler and the file types ChatGPT can open |
| `chatgpt` (host `PATH`) | The same launcher, for starting it from a terminal with flags |
| **ChatGPT (Terminal)** (menu) | Opens a shell inside `chatgpt-box` |

```bash
chatgpt                              # start the app (XWayland on a Wayland session)
chatgpt --ozone-platform=wayland     # experimental native Wayland (quit the app fully first)
```

## Updating

The package's `postinst` adds OpenAI's signed APT repo inside the box, so you can
update without a rebuild:

```bash
distrobox enter chatgpt-box -- sudo apt update
distrobox enter chatgpt-box -- sudo apt install --only-upgrade chatgpt
```

`tools setup chatgpt` also works: it rebuilds the image from the current `latest`
package.

## Storage

Distrobox shares your host `$HOME`, so the app's state lives where it would on a
native install and survives `tools setup` rebuilds:

| Path | Contents |
|---|---|
| `~/.config/Codex/` | Electron profile: login session, settings, caches (the app is built on the Codex desktop app, hence the name) |
| `~/.codex/` | Codex config, auth and history, shared with `codex-cli` if you have it installed |

## Notes

- **Local projects and commands run inside the box.** When ChatGPT or Codex runs
  a command in a project, it runs in `chatgpt-box` (Ubuntu 24.04, with `git`),
  not on the host. Your files are the same because `$HOME` is shared, but
  toolchains installed only on the host are not on the box's `PATH`. Install what
  you need with `distrobox enter chatgpt-box -- sudo apt install …`. That change
  lasts until the next `tools setup`.
- **Computer Use** isn't available in OpenAI's Linux preview yet. That's an
  upstream limitation and the container doesn't change it.
- **Browser handler.** The `.desktop` lists `http`/`https` among its
  `MimeType`s, so ChatGPT may show up in the host's "Open with" / default-browser
  lists. It doesn't become the default unless you choose it.
- **Saved login** goes into the host keyring over D-Bus (`libsecret` is in the
  image), the same way as a native install.
