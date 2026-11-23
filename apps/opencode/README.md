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
tools setup opencode OPENCODE_RELEASE=latest   # or a tag from tools help opencode
```

Setup asks one question: **which release** to install. The list is OpenCode's
published GitHub releases, newest first (the default), with each release's notes
beside it in the dashboard. A non-interactive `tools setup opencode` installs the
newest release.

### OpenCode 1 and 2

The list has both lines: `v2.x` releases and the older `v1.x` ones. The default,
`latest`, is the newest **2.x**. Pick a `v1.x` tag to stay on OpenCode 1; each
line has its own upstream installer, and setup uses the right one for the tag.

Moving from 1 to 2 keeps the same `opencode` command and the same config and
data locations (table below), and V2 reads V1 configuration as is. What breaks:
V1 plugins don't run under V2's new plugin API, the server API changed, and the
terminal settings in `tui.json(c)` move to a single `cli.json` (migrated
automatically). See OpenCode's
[Migrate from V1](https://opencode.ai/v2/docs/migrate-v1/) guide.

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

## Local model servers

On OpenCode 2, a plugin lists whatever local LLM servers are running, so there is
nothing to configure when you load a different model. Each server becomes a
provider named after its port, and its models appear as `local-<port>/<model>`:

```text
local-8000/Qwen3.6-35B-A3B-Q8_0
local-8001/qwen3.6-moe:35b-a3b
```

The list is rechecked every 30 seconds, so a model started or stopped in `llmctl`
shows up or disappears within that time. Pick one with `/models` in the TUI, or
`opencode run --model local-8000/<model> "..."`.

| Server | How it is found | Models shown | Context size from |
|---|---|---|---|
| llama.cpp | `/v1/models` | The loaded model | The server (`/props`) |
| FastFlowLM | `/v1/models`, then `/api/ps` | Only the loaded model, not its whole catalog | `--ctx-len` in the `llmctl` session; 32768 if started by hand |
| Strata, others | `/v1/models` | What the server lists | The server's `/v1/models`, or 32768 |

Ports checked: **8000-8099** (llama.cpp, and Strata's 8080), **52625-52634**
(FastFlowLM's default 52625 and the ports after it), and any port an `llmctl`
session uses. To replace the two ranges, create
`~/.config/opencode/local-discover.json`. It is read on each check:

```json
{ "ports": "8000-8099,52625-52634,9000" }
```

vLLM is skipped because OpenCode already detects it. The plugin isn't installed
for a `v1.x` release, which can't run V2 plugins.

## Updating

Rerun `tools setup opencode` and pick a newer release. The install step always
re-downloads, so the build cache never keeps an old version.

## Storage

`$HOME` is shared with the host, so everything survives a rebuild:

| Path | Contents |
|---|---|
| `~/.config/opencode/` | Config (`opencode.json`/`opencode.jsonc`) and installed plugins |
| `~/.config/opencode/plugins/opencode-local-discover.ts` | The local-server plugin. Overwritten from the image on each launch, and removed by `tools rm opencode` |
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
