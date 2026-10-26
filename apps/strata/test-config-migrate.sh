#!/usr/bin/env bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly here
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

install="$work/.local/share/strata/install"
launch="$work/.local/state/strata/launch"
mkdir -p "$install" "$launch" "$work/unrelated"

printf '%s\n' \
    '{"cwd":"/opt/strata/terminal/0.1.48.1","custom":{"temperature":0.25}}' \
    > "$install/strata-q2_0.json"
printf '%s\n' \
    '#!/bin/sh' \
    'exec /opt/strata/terminal/0.1.48.1/python/bin/python3.12 "$@"' \
    > "$install/run-q2_0.sh"
printf '%s\n' \
    '{"args":["--expert-profile","/opt/strata/terminal/0.1.48.1/data/expert-profile.bin"]}' \
    > "$launch/q2_0-32k.json"
printf '%s\n' '{"cwd":"/opt/strata/terminal/current"}' > "$launch/current.json"
printf '%s\n' '/opt/strata/terminal/0.1.48.1' > "$work/unrelated/keep.txt"
chmod 600 "$install/strata-q2_0.json"

HOME="$work" XDG_DATA_HOME='' XDG_STATE_HOME='' "$here/strata-config-migrate"

! grep -R -q '/opt/strata/terminal/0.1.48.1' "$install" "$launch"
grep -q '"custom":{"temperature":0.25}' "$install/strata-q2_0.json"
grep -q '/opt/strata/terminal/current/python/bin/python3.12' "$install/run-q2_0.sh"
grep -q '/opt/strata/terminal/current/data/expert-profile.bin' "$launch/q2_0-32k.json"
grep -q '/opt/strata/terminal/0.1.48.1' "$work/unrelated/keep.txt"
[[ "$(stat -c '%a' "$install/strata-q2_0.json")" == 600 ]]

before="$(find "$install" "$launch" -type f -exec sha256sum {} + | sort)"
HOME="$work" XDG_DATA_HOME='' XDG_STATE_HOME='' "$here/strata-config-migrate"
after="$(find "$install" "$launch" -type f -exec sha256sum {} + | sort)"
[[ "$before" == "$after" ]]
! find "$install" "$launch" -name '*.linux-tools.tmp.*' -print -quit | grep -q .

echo 'strata config migration: ok'
