#!/usr/bin/env bash
# Shared helper for the openclaw wrappers. Sourced, never executed.
#
# Distrobox already shares the host's user runtime dir into every box, so
# DBUS_SESSION_BUS_ADDRESS points at /run/user/$UID/bus and `systemctl --user`
# reaches the *host's* user manager out of the box -- no distrobox-host-exec,
# and therefore no dependency on the host having flatpak installed. Verify with
# `systemctl --user list-units` inside any box: it lists host units.
#
# What is missing is /run/systemd/system. /run/systemd exists in the container
# as a real directory but has no `system` child, so sd_booted() returns false
# and anything that gates on "is systemd available here?" -- `openclaw doctor`,
# `openclaw gateway status --deep`, `systemctl is-system-running` -- concludes
# there is no systemd. Symlinking the host's copy in fixes that.
#
# Deliberately NOT done here: the /run/dbus/system_bus_socket half of the
# usual recipe. That one grants *system* scope, which would let anything in
# this box drive host system services via `sudo systemctl`. User scope is all
# OpenClaw needs.
#
# /run is a tmpfs recreated on every container start, so this cannot be baked
# into the image -- each wrapper calls it on the way in.
ensure_systemd_bridge() {
    { [ -e /run/systemd/system ] || [ -L /run/systemd/system ]; } && return 0
    [ -d /run/host/run/systemd/system ] || return 0
    sudo ln -sfn /run/host/run/systemd/system /run/systemd/system 2>/dev/null || true
}

# Absolute path to the real CLI, renamed aside by the Dockerfile so /usr/bin/openclaw
# can be a wrapper.
OPENCLAW_BIN=/usr/bin/openclaw-bin
