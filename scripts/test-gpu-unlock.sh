#!/usr/bin/env bash
# Root tests in a disposable filesystem; run in a container or with sudo in CI.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run this test as root in a disposable container (or sudo in CI).' >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/apps/gpu-unlock"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GPU_UNLOCK_TEST_LOG="$work/commands"
export GPU_UNLOCK_TEST_KVER=6.8.0-test
export GPU_UNLOCK_TEST_ONCE="$work/rebuild-failed"
mkdir -p "$work/bin"
cat > "$work/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
name="${0##*/}"
printf '%s %s\n' "$name" "$*" >> "$GPU_UNLOCK_TEST_LOG"
case "$name" in
    modinfo) [[ "${GPU_UNLOCK_TEST_NO_MODULE:-}" != yes ]] || exit 1; echo "$GPU_UNLOCK_TEST_KVER SMP" ;;
    depmod) [[ -z "${GPU_UNLOCK_TEST_UMASK:-}" ]] || umask > "$GPU_UNLOCK_TEST_UMASK" ;;
    mkinitcpio|update-initramfs|dracut)
        if [[ "${GPU_UNLOCK_TEST_FAIL_REBUILD:-}" == once && ! -f "$GPU_UNLOCK_TEST_ONCE" ]]; then
            touch "$GPU_UNLOCK_TEST_ONCE"; exit 23
        fi
        ;;
esac
MOCK
chmod +x "$work/bin/mock"
for tool in modinfo depmod mkinitcpio update-initramfs dracut journalctl limine-mkinitcpio limine-dracut; do ln -s mock "$work/bin/$tool"; done
export PATH="$work/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_line() { grep -Fqx -- "$1" "$GPU_UNLOCK_TEST_LOG" || fail "missing command $1"; }
make_host() {
    mkdir -p "$1/proc" "$1/lib/modules/$GPU_UNLOCK_TEST_KVER" "$1/usr/share/licenses" "$1/usr/lib/firmware" "$1/usr/share/initramfs-tools"
    printf 'quiet splash\n' > "$1/proc/cmdline"
    chmod 751 "$1/usr/share/licenses"
    touch "$1/usr/share/licenses/unrelated-license"
}
make_host "$work/host"
run_host() {
    bash -c 'source "$1"; ROOT="$2"; shift 2; "$@"' \
        _ "$app/gpu-unlock-host" "${GPU_UNLOCK_TEST_ROOT_PATH:-$work/host}" "$@"
}
config="$work/host/etc/modprobe.d/zz-linux-tools-gpu-unlock.conf"
staging="$work/staging"
mkdir -p "$staging/module" "$staging/payload/usr/lib/firmware/gpu-unlock/610.43.03" \
    "$staging/payload/usr/share/licenses/gpu-unlock" "$staging/payload/usr/share/licenses/gpu-unlock-firmware"
touch "$staging/module/gpu_unlock.ko" "$staging/payload/usr/lib/firmware/gpu-unlock/610.43.03/test.bin" \
    "$staging/payload/usr/share/licenses/gpu-unlock/LICENSE" "$staging/payload/usr/share/licenses/gpu-unlock-firmware/NOTICE"
cp -a "$app/boot" "$staging/boot"
# Reproduce user-owned, permissive container build output.
chown -R 2001:2002 "$staging"
chmod -R 777 "$staging"
: > "$GPU_UNLOCK_TEST_LOG"
run_host install_host "$GPU_UNLOCK_TEST_KVER" "$staging" mkinitcpio > "$work/output"
[[ -f "$work/host/lib/modules/$GPU_UNLOCK_TEST_KVER/updates/linux-tools-gpu-unlock/gpu_unlock.ko" ]] || fail 'module was not staged'
grep -qx 'options gpu_unlock targets=' "$config" || fail 'installation must start disabled'
expect_line "depmod $GPU_UNLOCK_TEST_KVER"
expect_line 'mkinitcpio -P'
[[ "$(stat -c '%u:%g %a' "$work/host/usr/share/licenses")" == '0:0 751' ]] || fail 'shared license parent metadata changed'
[[ -f "$work/host/usr/share/licenses/unrelated-license" ]] || fail 'unrelated license was changed'
for tree in usr/lib/firmware/gpu-unlock usr/share/licenses/gpu-unlock usr/share/licenses/gpu-unlock-firmware; do
    [[ -z "$(find "$work/host/$tree" \( ! -uid 0 -o ! -gid 0 \) -print -quit)" ]] || fail 'installed tree inherited user ownership'
    [[ -z "$(find "$work/host/$tree" -type d ! -perm 755 -print -quit)" ]] || fail 'wrong directory permissions'
    [[ -z "$(find "$work/host/$tree" -type f ! -perm 644 -print -quit)" ]] || fail 'wrong file permissions'
done

mkdir "$work/insecure-parent"
chown 2001:2002 "$work/insecure-parent"
if run_host install_owned_tree "$staging/payload/usr/lib/firmware/gpu-unlock" "$work/insecure-parent/gpu-unlock" > "$work/output" 2> "$work/error"; then fail 'insecure shared system parent accepted'; fi
[[ ! -e "$work/insecure-parent/gpu-unlock" ]] || fail 'insecure parent was modified'

# All three tools are installed in the fixture. Auto must refuse ambiguity,
# respect explicit kernel-install config, then use the recorded backend.
make_host "$work/ambiguous"
if GPU_UNLOCK_TEST_ROOT_PATH="$work/ambiguous" run_host select_initramfs_tool auto > "$work/output" 2> "$work/error"; then fail 'ambiguous tools accepted'; fi
grep -q 'Cannot determine' "$work/error" || fail 'missing ambiguity diagnostic'
mkdir -p "$work/ambiguous/etc/kernel"
printf 'initrd_generator="dracut"\n' > "$work/ambiguous/etc/kernel/install.conf"
[[ "$(GPU_UNLOCK_TEST_ROOT_PATH="$work/ambiguous" run_host select_initramfs_tool auto)" == dracut ]] || fail 'configured dracut ignored'
[[ "$(run_host select_initramfs_tool auto)" == mkinitcpio ]] || fail 'recorded backend ignored'

# CachyOS can ship update-initramfs as a compatibility dispatcher while Limine
# uses mkinitcpio without presets. Honor the active local hook over its vendor
# counterpart and invoke the Limine entrypoint, not plain mkinitcpio -P.
make_host "$work/limine"
rmdir "$work/limine/usr/share/initramfs-tools"
mkdir -p "$work/limine/etc/default" "$work/limine/etc/pacman.d/hooks" "$work/limine/usr/share/libalpm/hooks"
touch "$work/limine/etc/default/limine"
printf '[Action]\nExec = /usr/share/libalpm/scripts/limine-mkinitcpio-install\n' > "$work/limine/etc/pacman.d/hooks/90-install.hook"
printf '[Action]\nExec = /usr/share/libalpm/scripts/limine-dracut-install\n' > "$work/limine/usr/share/libalpm/hooks/90-install.hook"
[[ "$(GPU_UNLOCK_TEST_ROOT_PATH="$work/limine" run_host select_initramfs_tool auto)" == mkinitcpio ]] || fail 'Limine generator was not detected'
if GPU_UNLOCK_TEST_ROOT_PATH="$work/limine" run_host validate_tool update-initramfs > "$work/output" 2> "$work/error"; then fail 'compatibility wrapper accepted as initramfs-tools'; fi
if GPU_UNLOCK_TEST_ROOT_PATH="$work/limine" run_host validate_tool dracut > "$work/output" 2> "$work/error"; then fail 'backend conflicting with active Limine hook accepted'; fi
: > "$GPU_UNLOCK_TEST_LOG"
GPU_UNLOCK_TEST_ROOT_PATH="$work/limine" run_host install_host "$GPU_UNLOCK_TEST_KVER" "$staging" auto > "$work/output"
expect_line 'limine-mkinitcpio '
if grep -qx 'mkinitcpio -P' "$GPU_UNLOCK_TEST_LOG"; then fail 'Limine boot entries were bypassed'; fi
rm "$work/limine/etc/pacman.d/hooks/90-install.hook"
ln -s /dev/null "$work/limine/etc/pacman.d/hooks/90-install.hook"
[[ -z "$(GPU_UNLOCK_TEST_ROOT_PATH="$work/limine" run_host configured_limine_backend)" ]] || fail 'masked vendor hook was treated as active'

for targets in all 0000:21:00.0 0000:21:00.0,0000:22:00.0; do
    run_host set_targets "$targets" > "$work/output"
    grep -qx "options gpu_unlock targets=$targets" "$config" || fail 'wrong next-boot targets'
done
run_host set_targets '' > "$work/output"
for targets in 'all,0000:21:00.0' '21:00.0' 'all; reboot' '0000:21:00.8'; do
    if run_host set_targets "$targets" > "$work/error" 2>&1; then fail "invalid targets accepted: $targets"; fi
done
if GPU_UNLOCK_TEST_FAIL_REBUILD=once run_host set_targets all > "$work/error" 2>&1; then fail 'rebuild failure swallowed'; fi
grep -qx 'options gpu_unlock targets=' "$config" || fail 'failed toggle did not roll back'

for tool in update-initramfs dracut; do
    make_host "$work/host-$tool"
    : > "$GPU_UNLOCK_TEST_LOG"
    GPU_UNLOCK_TEST_ROOT_PATH="$work/host-$tool" run_host install_host "$GPU_UNLOCK_TEST_KVER" "$staging" "$tool" > "$work/output"
    case "$tool" in
        update-initramfs) expect_line "update-initramfs -u -k $GPU_UNLOCK_TEST_KVER" ;;
        dracut)
            expect_line "dracut --force --kver $GPU_UNLOCK_TEST_KVER"
            [[ -x "$work/host-$tool/usr/lib/dracut/modules.d/01linux-tools-gpu-unlock/module-setup.sh" ]] || fail 'missing dracut module'
            [[ ! -f "$work/host-$tool/etc/dracut.conf.d/linux-tools-gpu-unlock.conf" ]] || fail 'must not force dracut'
            ;;
    esac
done
# Failure of an earlier kernel cannot be hidden by a later kernel succeeding.
printf 'update-initramfs\n' > "$work/host/var/lib/linux-tools/gpu-unlock/initramfs-tool"
mkdir -p "$work/host/lib/modules/second-test"
touch "$work/host/var/lib/linux-tools/gpu-unlock/kernels/second-test"
rm -f "$GPU_UNLOCK_TEST_ONCE"
if GPU_UNLOCK_TEST_FAIL_REBUILD=once run_host set_targets all > "$work/error" 2>&1; then fail 'multi-kernel rebuild failure swallowed'; fi
grep -qx 'options gpu_unlock targets=' "$config" || fail 'multi-kernel failure did not roll back'

# Installation/on still reject legacy conflicts, but uninstall must work and
# preserve firmware used by another DKMS installation and unrelated config.
printf 'quiet gpu_unlock.targets=all\n' > "$work/host/proc/cmdline"
mkdir -p "$work/host/var/lib/dkms/gpu-unlock" "$work/host/etc/dracut.conf.d"
printf 'unrelated\n' > "$work/host/etc/dracut.conf.d/linux-tools-gpu-unlock.conf"
if run_host set_targets all > "$work/error" 2>&1; then fail 'conflicting boot option accepted'; fi
run_host uninstall_host > "$work/output"
[[ ! -f "$config" && ! -d "$work/host/lib/modules/$GPU_UNLOCK_TEST_KVER/updates/linux-tools-gpu-unlock" ]] || fail 'uninstall left owned files'
[[ -f "$work/host/etc/dracut.conf.d/linux-tools-gpu-unlock.conf" ]] || fail 'uninstall removed unowned dracut config'
[[ -d "$work/host/var/lib/dkms/gpu-unlock" && -d "$work/host/usr/lib/firmware/gpu-unlock" ]] || fail 'uninstall damaged separate DKMS installation'
GPU_UNLOCK_TEST_ROOT_PATH="$work/host-dracut" run_host uninstall_host > "$work/output"
[[ ! -d "$work/host-dracut/usr/lib/firmware/gpu-unlock" ]] || fail 'normal uninstall kept owned firmware'

# Root bootstrap executes only a root-owned, digest-checked private snapshot.
mkdir -p "$work/bundle/module"
cat > "$work/bundle/gpu-unlock-host" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$(stat -c '%u:%g' "${BASH_SOURCE[0]}")" == 0:0 ]]
[[ "$(stat -c '%u:%g' "$3/module/gpu_unlock.ko")" == 0:0 ]]
grep -qx 'original module' "$3/module/gpu_unlock.ko"
printf '%s\n' "${BASH_SOURCE[0]%/*}" > "$GPU_UNLOCK_TEST_SNAPSHOT"
HELPER
printf 'original module\n' > "$work/bundle/module/gpu_unlock.ko"
chown -R 2001:2002 "$work/bundle"
tar -cf "$work/bundle.tar" -C "$work/bundle" gpu-unlock-host module
expected="$(sha256sum "$work/bundle.tar")"; expected="${expected%% *}"
printf 'replacement after authorization\n' > "$work/bundle/module/gpu_unlock.ko"
export GPU_UNLOCK_TEST_SNAPSHOT="$work/snapshot-path"
bash -c "$(cat "$app/host-bootstrap")" gpu_unlock "$work/bundle.tar" "$expected" install test auto
[[ -f "$GPU_UNLOCK_TEST_SNAPSHOT" ]] || fail 'root snapshot helper was not run'
[[ ! -d "$(cat "$GPU_UNLOCK_TEST_SNAPSHOT")" ]] || fail 'root snapshot leaked after success'
rm -f "$GPU_UNLOCK_TEST_SNAPSHOT"
printf 'tampered while password prompt waits' >> "$work/bundle.tar"
if bash -c "$(cat "$app/host-bootstrap")" gpu_unlock "$work/bundle.tar" "$expected" install test auto > "$work/output" 2> "$work/error"; then fail 'tampered bundle accepted'; fi
[[ ! -f "$GPU_UNLOCK_TEST_SNAPSHOT" ]] || fail 'tampered helper executed'
grep -q 'bundle changed' "$work/error" || fail 'missing integrity diagnostic'

# host-bootstrap runs the helper under umask 077; privileged actions must reset it
# so depmod indexes and created system directories stay world-readable.
make_host "$work/umask-host"
(
    umask 077
    GPU_UNLOCK_TEST_UMASK="$work/depmod-umask" GPU_UNLOCK_TEST_ROOT_PATH="$work/umask-host" \
        run_host main install "$GPU_UNLOCK_TEST_KVER" "$staging" mkinitcpio > "$work/output"
)
[[ "$(cat "$work/depmod-umask")" == 0022 ]] || fail 'privileged helper kept the bootstrap umask'

bash -c 'set -eu; KERNELVERSION=test; MODULES=(ext4 gpu_unlock nvidia nvidia_modeset); FILES=(); source "$1"; [[ "${MODULES[*]}" == "ext4 gpu_unlock nvidia nvidia_modeset" ]]; [[ "${FILES[*]}" == /etc/modprobe.d/zz-linux-tools-gpu-unlock.conf ]]' _ "$app/boot/mkinitcpio.conf"
GPU_UNLOCK_TEST_NO_MODULE=yes bash -c 'set -eu; kernel=test; source "$1"; if check; then exit 1; fi' _ "$app/boot/dracut/module-setup.sh"
bash "$app/gpu_unlock" help > "$work/output"
echo 'gpu-unlock ownership/bootstrap/backend/controller tests passed'
