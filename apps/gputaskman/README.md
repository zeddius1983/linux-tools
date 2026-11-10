# gputaskman

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=ubuntu&logoColor=E95420">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/-tested-brightgreen?logo=linuxmint&logoColor=87CF3E">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/-untested-lightgrey?logo=cachyos&logoColor=00C2A0">
</p>

[gputaskman](https://github.com/shanselman/gputaskman) is a terminal task manager
for the GPU: per-process VRAM, spill to system memory and engine load, device
totals, and for local LLMs a breakdown of weights and KV cache. It supports
NVIDIA (NVML), AMD (`amdgpu`) and Intel (`i915`) on Linux.

The box only carries the release. **The program itself runs on the host**, because
a rootless box cannot read the per-process data of anything outside it (see
[How it runs](#how-it-runs)).

## Install

```bash
tools setup gputaskman
```

Setup asks which release to install. It can also be given on the command line;
left out, it takes the newest release. `tools help gputaskman` lists the choices:

```bash
tools setup gputaskman GPUTASKMAN_RELEASE=v0.3.5
```

The host needs the `flatpak` package, as every `distrobox-host-exec` app does.
No GPU option is needed: running on the host, it uses the host's driver directly,
so NVIDIA works without a CDI spec.

## Usage

Run `gputaskman` from a terminal, or open the **gputaskman** entry in the
application menu. `q` quits and `?` shows help.

```bash
gputaskman                   # live UI, every GPU
gputaskman --gpu 1           # only the second GPU
gputaskman --list-gpus       # GPU indexes
gputaskman --once            # one snapshot as text
gputaskman --json            # one snapshot as JSON
gputaskman record -o log.jsonl --duration 60   # sample to a file
```

## How it runs

The process table comes from `/proc/<pid>/fd`, `fdinfo` and `maps`. A rootless box
has its own user namespace and the kernel refuses those reads on outside
processes, so inside a box the table stays empty. Device totals are the same
either way.

The `gputaskman` command in the box therefore copies the release to the shared
home the first time it runs, then starts it on the host with
`distrobox-host-exec`. From there it sees host applications and the programs in
every other box, such as `llama-cpp`.

If the host cannot be reached, it warns and runs inside the box instead, with
an empty process table.

## Storage

| Path | Contents |
|---|---|
| `~/.local/share/gputaskman/<release>/` | The copy that runs on the host, about 40 MB. A new release replaces it the next time it runs. |

`tools rm gputaskman` removes the box, its shortcuts and this directory. It keeps
the image; `podman rmi linux-tools/gputaskman:latest` removes that too.

## Notes

- Only your own processes are listed. To include other users' processes, run the
  host copy with sudo: `sudo ~/.local/share/gputaskman/v*/gputaskman`.
- Quit with `q`. Closing the terminal window instead leaves gputaskman running in
  the background, as it does for any terminal app exported from a Distrobox.
  Stop a leftover with `pkill -f '/.local/share/gputaskman/v'`.
- Upstream's Linux tarballs need glibc 2.35 or newer **on the host** (Ubuntu 22.04,
  Debian 12 or newer), since that is where they run.
- `v0.1.0` has no Linux build, so the release picker leaves it out.
