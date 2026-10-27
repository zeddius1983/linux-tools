#!/bin/sh
# Preinstall distrobox-init's first-start pacman packages (pacman.txt) into an
# image. See apt.sh for why. distrobox still runs `pacman -Syu` on first start
# (small for a freshly built image) and, because its locale test is missing a
# '/' (`/usr/share/i18n/locales${HOST_LOCALE}`), always reinstalls glibc +
# glibc-locales (~22 MiB); its dependency install becomes a no-op.
#
#   COPY --from=distrobox-deps . /tmp/distrobox-deps/
#   RUN sh /tmp/distrobox-deps/pacman.sh && rm -rf /tmp/distrobox-deps
set -eu

here="$(dirname "$0")"

# distrobox-init drops these from pacman.conf so man pages and docs land and
# progress is shown; do it first so the packages installed here get them too.
sed -i "s|NoExtract.*||g" /etc/pacman.conf
sed -i "s|NoProgressBar.*||g" /etc/pacman.conf

pacman -Syy --noconfirm
# Like distrobox-init, only names the repos carry (pacman -Ssq).
names="$(grep -v -e '^#' -e '^[[:space:]]*$' "$here/pacman.txt" | paste -sd'|')"
# shellcheck disable=SC2046
pacman -Su --noconfirm --needed $(pacman -Ssq | grep -E "^(${names})$")

# distrobox-init runs locale-gen when en_US.UTF-8 is not generated yet.
sed -i "s|^#\(en_US.UTF-8\)|\1|" /etc/locale.gen
locale-gen

yes | pacman -Scc --noconfirm >/dev/null 2>&1 || true
