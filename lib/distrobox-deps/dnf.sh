#!/bin/sh
# Preinstall distrobox-init's first-start dnf packages (dnf.txt) into an image.
# See apt.sh for why; distrobox still refreshes dnf metadata on first start,
# but its install becomes a no-op.
#
#   COPY --from=distrobox-deps . /tmp/distrobox-deps/
#   RUN sh /tmp/distrobox-deps/dnf.sh && rm -rf /tmp/distrobox-deps
set -eu

here="$(dirname "$0")"

# --allowerasing as distrobox-init uses it (curl-minimal -> curl and the
# like); --skip-unavailable stands in for its `dnf list` filter.
# shellcheck disable=SC2046
dnf -y install --allowerasing --skip-unavailable --setopt=install_weak_deps=False \
    $(grep -v -e '^#' -e '^[[:space:]]*$' "$here/dnf.txt")
dnf clean all
rm -rf /var/cache/dnf/*
