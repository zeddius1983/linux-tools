# corefreq

[CoreFreq](https://github.com/cyring/CoreFreq) is a CPU monitoring and tuning tool that reads low-level CPU counters (frequency, power, cache, temperature) via a kernel module. Because the module has to load into the *host* kernel, this app uses the container purely as a build environment: it compiles CoreFreq at runtime against whatever kernel headers are mounted in from the host, then copies the resulting module/binaries out to `~/.local/corefreq/` for the host to use directly.

## Install

```bash
tools setup corefreq
corefreq-setup   # builds the kernel module against your running kernel, installs it, and sets up passwordless sudo
```

`corefreq-setup` prompts for your sudo password once (to install a sudoers rule scoped to the CoreFreq helper scripts). After that, `corefreq-cli` runs without any password prompts.

Re-run `corefreq-setup` any time you update the kernel — the module has to be rebuilt for each kernel version. It's safe to re-run while CoreFreq is already loaded/running; it stops the old daemon, swaps in the new binaries, and reloads the module.

> **Host prerequisite:** the `flatpak` package must be installed on the host — CoreFreq's wrappers reach the host via Distrobox's `distrobox-host-exec`, which needs the `org.freedesktop.Flatpak` D-Bus service that package provides. Without it, `corefreq-cli` silently does nothing. Install with e.g. `sudo pacman -S flatpak` (Arch/CachyOS) or `sudo apt install flatpak` (Debian/Ubuntu).

## Exported commands

- `corefreq-setup` — builds `corefreqk.ko`, `corefreqd`, and `corefreq-cli` against the currently running kernel's headers, installs the sudoers rule, and (re)loads the module.
- `corefreq-cli` — launches the CoreFreq TUI. Automatically loads the kernel module and starts `corefreqd` on the host first if they aren't already running.

## Storage

- `~/.local/corefreq/` — built artifacts (`corefreqk.ko`, `corefreqd`, `corefreq-cli`), the privileged host helper scripts (`module-reload`, `daemon-ensure`), and `sudoers`. Safe to delete and rebuild with `corefreq-setup`.
- `~/.local/corefreq-build/` — scratch build directory, recreated on every `corefreq-setup` run.
- `/etc/sudoers.d/corefreq` — passwordless sudo rule scoped to `~/.local/corefreq/module-reload` and `~/.local/corefreq/daemon-ensure`, installed by `corefreq-setup`.

## Notes

- Requires kernel headers for your running kernel to be installed on the host (e.g. `linux-headers-$(uname -r)` on Debian/Ubuntu, or the matching `linux-*-headers` package on Arch-based distros).
- **Two container images, picked automatically:** `tools setup corefreq` builds from `apps/corefreq/Dockerfile.ubuntu` on Debian/Ubuntu-family hosts and `Dockerfile.arch` (Arch Linux base) on Arch-family hosts (including CachyOS) — detected from the host's `/etc/os-release`. This matters because Arch-family kernels (CachyOS in particular) are built with Clang and carry Clang-only codegen flags that GCC can't parse; the Arch-based image ships a matching Clang/LLVM toolchain so the module builds correctly. No action needed; this is automatic.
- The module must be rebuilt (`corefreq-setup`) after every kernel upgrade.
