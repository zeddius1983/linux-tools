# nvidia-cdi-regenerate

Boot-time systemd service that regenerates the **NVIDIA CDI spec**
(`/etc/cdi/nvidia.yaml`) on every boot so it always matches the currently-installed
GPUs.

This is a **host-only** app: it installs a systemd unit straight to the host and
builds **no container**.

## Why you want this

Distrobox/Podman apps in this repo request GPUs via CDI
(`--device nvidia.com/gpu=all` in their `create_flags`). That works only if
`/etc/cdi/nvidia.yaml` exists and lists the GPUs actually present. Two things
routinely invalidate it:

1. **The spec pins GPUs by UUID + device minors.** Add, remove, or move a card
   (or a PCIe switch re-enumerates) and resolving `nvidia.com/gpu=all` fails with
   `no such device`, so every CDI box refuses to start.
2. **Toolkit ≥ 1.19 emits a `disable-device-node-modification` hook** that fails
   under distrobox (`nvidia-cdi-hook (exit code: 1)`).

This service fixes both at every boot by running:

```
nvidia-ctk cdi generate \
    --disable-hook disable-device-node-modification \
    --output /etc/cdi/nvidia.yaml
```

Podman re-reads the spec on every container `start`, so a fresh spec is enough —
no box recreation is ever needed.

## Requirements

- **NVIDIA Container Toolkit** on the host (provides `nvidia-ctk`):
  - Debian/Ubuntu: `apt install nvidia-container-toolkit`
  - Fedora: `dnf install nvidia-container-toolkit`
  - Arch: `pacman -S nvidia-container-toolkit`
- systemd (any of the above).

The unit has `ConditionPathExists=/usr/bin/nvidia-ctk`, so it self-skips on a host
that doesn't have the toolkit yet.

## Install

```bash
tools setup nvidia-cdi-regenerate
```

Runs `install.sh` on the host: copies the unit to `/etc/systemd/system`,
`daemon-reload`, `enable --now`. You'll be prompted for sudo.

## Remove

```bash
tools rm nvidia-cdi-regenerate
```

Disables and deletes the unit (leaves the current `/etc/cdi/nvidia.yaml` in place).

## Files

| Path | What |
|---|---|
| `/etc/systemd/system/nvidia-cdi-regenerate.service` | the boot unit |
| `/etc/cdi/nvidia.yaml` | the spec it regenerates (read by Podman/distrobox) |

## Verify

```bash
systemctl status nvidia-cdi-regenerate
journalctl -u nvidia-cdi-regenerate -b
grep name: /etc/cdi/nvidia.yaml
```

## Related

- `nvidia-p2p-acs` — boot-time PCIe ACS fix for multi-GPU P2P over a switch.
- `nvidia-p2p-driver` — build/install the GeForce P2P-patched kernel module.
