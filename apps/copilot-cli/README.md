# copilot-cli

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

> **Unmaintained.** This app still installs, but it isn't being kept current, and
> the dashboard greys it out. Expect rough edges.

GitHub's [Copilot CLI](https://github.com/github/copilot-cli) (`copilot`), installed
with GitHub's own installer in an `ubuntu:24.04` Distrobox container. The image
also includes the GitHub CLI (`gh`) and `git`.

## Install

```bash
tools setup copilot-cli
```

## What you get

| Entry | What it does |
|---|---|
| `copilot` (host `PATH`) | The Copilot CLI agent |
| **GitHub Copilot CLI** (menu) | Opens `copilot` in a terminal window |

```bash
copilot                 # interactive session in the current directory
```

## Storage

`$HOME` is shared with the host, so Copilot's config and login stay under
`~/.copilot/` across rebuilds.

## Notes

- The installer runs at image-build time, so `tools setup copilot-cli` is how you
  update it.
- Commands Copilot runs execute inside `copilot-cli-box`, not on the host.
