# telegram

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[Telegram Desktop](https://desktop.telegram.org), the official Telegram client,
in an `ubuntu:24.04` Distrobox container. The image unpacks the official Linux
tarball from `telegram.org` into `/opt/Telegram`, adds the Qt/XCB and Mesa
libraries it needs, and starts it through a small `telegram-desktop` launcher
(see [Notes](#notes)).

## Install

```bash
tools setup telegram
```

No parameters and no `create_flags`.

## What you get

| Entry | What it does |
|---|---|
| **Telegram** (menu) | Launches Telegram through the box's `telegram-desktop` launcher |
| **Telegram Desktop (Terminal)** (menu) | Opens a shell inside `telegram-box` |

There's no `bin:` export, so `telegram-desktop` isn't on the host `PATH`. To
start it from a terminal:

```bash
distrobox enter telegram-box -- telegram-desktop
```

## Updating

The image downloads whatever version is current on `telegram.org` when it's
built. Telegram's built-in updater can't replace files in `/opt/Telegram`,
which is owned by root inside the box, so update by rebuilding:

```bash
tools setup telegram
```

Your login and chats aren't affected (see below).

## Storage

`$HOME` is shared with the host, so everything survives a rebuild:

| Path | Contents |
|---|---|
| `~/.local/share/TelegramDesktop/tdata/` | Session (login), settings, cache |
| `~/.local/share/TelegramDesktop/log.txt` | Log, including the launched version |
| `~/Downloads/Telegram Desktop/` | Downloaded files (Telegram's default) |

## Notes

- **Only one "Telegram" menu entry.** On every start Telegram writes its own
  `org.telegram.desktop._<hash>.desktop` into `~/.local/share/applications`,
  which is shared with the host, pointing at `/opt/Telegram/Telegram`, a path
  that exists only inside the box. The `telegram-desktop` launcher sets
  `DESKTOPINTEGRATION=1`, which stops that. It also deletes a copy left over
  from an older image (one whose `Exec` points into `/opt/Telegram`).
- **`tg://`, `ton://` and `tonsite://` links open Telegram from anywhere on the
  host**, e.g. a `t.me` "Open in Telegram" button in a browser. The launcher
  sets this up each time it starts:
  - a hidden `telegram-box-url-handler.desktop` that runs the link through the
    box, made the default for those schemes in `~/.config/mimeapps.list` (only
    those three keys are touched);
  - `~/.config/x-telegrambox-mimeapps.list`, which only Telegram reads. It makes
    Telegram see itself as the registered handler, so it doesn't overwrite the
    host's defaults with a box-only path.

  The first launch after `tools setup telegram` is what sets it up. `tools rm
  telegram` removes the handler with the rest of the box's menu entries.
- **Amd64 only.** Telegram publishes the Linux tarball for x86-64 only, so the
  image is pinned to `linux/amd64`.
- GPU rendering uses the host's Mesa through `/dev/dri`, which Distrobox shares
  by default. The image includes `mesa-utils` and `vulkan-tools` (`glxinfo`,
  `vulkaninfo`) for checking it.
