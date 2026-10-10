# antigravity

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

> **Unmaintained.** This app still installs, but it isn't being kept current, and
> the dashboard greys it out. Expect rough edges.

Google's Antigravity CLI (`agy`), installed with Google's official installer in an
`ubuntu:24.04` Distrobox container. The image also includes the GitHub CLI
(`gh`), `git` and `jq`.

## Install

```bash
tools setup antigravity
```

## What you get

| Entry | What it does |
|---|---|
| `agy` (host `PATH`) | The Antigravity CLI |
| **Antigravity CLI** (menu) | Opens `agy` in a terminal window |

```bash
agy                     # interactive session in the current directory
```

## Notes

- The installer runs at image-build time, so `tools setup antigravity` is how you
  update it.
- `$HOME` is shared with the host, so the CLI's config and login survive rebuilds.
- Commands `agy` runs execute inside `antigravity-box`, not on the host.
