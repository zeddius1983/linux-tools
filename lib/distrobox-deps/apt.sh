#!/bin/sh
# Preinstall distrobox-init's first-start apt packages (apt.txt) into an image.
#
# distrobox-init installs that list on every box's first start, and `tools
# setup` recreates the box each time, so without this every rebuild
# re-downloads ~180 packages behind a silent "Installing basic packages...".
# distrobox still runs its install on first start (it only checks for
# /.containersetupdone), but with everything present it is a no-op.
#
# Reached from a Dockerfile through the build context `tools build` passes:
#   COPY --from=distrobox-deps . /tmp/distrobox-deps/
#   RUN sh /tmp/distrobox-deps/apt.sh && rm -rf /tmp/distrobox-deps
set -eu

here="$(dirname "$0")"
export DEBIAN_FRONTEND=noninteractive

# distrobox-init removes Ubuntu's dpkg excludes so man pages and docs land;
# do it first so the packages installed here get them too.
rm -f /etc/dpkg/dpkg.cfg.d/excludes

apt-get update

# Like distrobox-init, drop names this release does not carry (the libgl1-mesa
# transitional names are gone from noble) rather than failing the install.
# Test for a Package: record, not apt-cache's exit status: a name other
# packages still refer to (libgl1-mesa-glx) exits 0 with nothing installable.
pkgs=""
for p in $(grep -v -e '^#' -e '^[[:space:]]*$' "$here/apt.txt"); do
    if apt-cache show "$p" 2>/dev/null | grep -q '^Package:'; then
        pkgs="$pkgs $p"
    else
        echo "distrobox-deps: $p not in this release, skipped"
    fi
done

# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $pkgs
rm -rf /var/lib/apt/lists/*
