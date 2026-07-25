#!/usr/bin/env bash
# Add a second GRUB boot entry that disables the IOMMU, for hosts that want both
# NPU inference and full iGPU throughput on AMD Strix Halo.
#
# Why: the NPU needs the IOMMU (amdxdna binds via IOMMU SVA), but the IOMMU costs
# 5-12% iGPU prefill throughput. The setting is per-boot and has no middle ground
# (iommu=pt performs identically to the default translated mode), so the only way
# to have both is to choose at the boot menu.
#
# Leaves the default entry untouched: IOMMU on, NPU working. The new entry is
# additive — if it were ever malformed, boot the normal entry instead.
#
# Installs a *generator* under /etc/grub.d/ rather than a static 40_custom entry,
# so the kernel version is recomputed on every update-grub and never goes stale.
#
# Run with sudo on the host. Revert with --uninstall.
set -euo pipefail

GEN=/etc/grub.d/45_iommu_off
DEFAULTS=/etc/default/grub
STAMP="$(date +%Y%m%d-%H%M%S)"

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$GEN"
    echo "==> removed $GEN (GRUB_TIMEOUT* in $DEFAULTS left as-is)"
    update-grub
    exit 0
fi

echo "==> writing generator $GEN"
cat > "$GEN" <<'GENERATOR'
#!/bin/sh
# Emits a boot entry matching the default one, plus amd_iommu=off.
# Generated entry disables the AMD Ryzen AI NPU and speeds up the iGPU.
# Installed by linux-tools apps/fastflowlm/iommu-off-entry.sh
set -e

prefix=/usr
exec_prefix=/usr
datarootdir=/usr/share
. "$datarootdir/grub/grub-mkconfig_lib"

# If the default cmdline already disables the IOMMU there is nothing to offer.
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
[ -r /etc/default/grub ] && . /etc/default/grub
case " ${GRUB_CMDLINE_LINUX_DEFAULT} ${GRUB_CMDLINE_LINUX} " in
    *" amd_iommu=off "*|*" iommu=off "*) exit 0 ;;
esac

# Current kernel via the distro-maintained symlinks, so this survives updates.
kernel=$(readlink -f /boot/vmlinuz 2>/dev/null) || exit 0
[ -n "$kernel" ] && [ -e "$kernel" ] || exit 0
version=${kernel##*/vmlinuz-}
initrd=/boot/initrd.img-${version}
[ -e "$initrd" ] || exit 0

# Reuse the running kernel's root= / rootflags= — correct for btrfs subvolumes,
# LVM, LUKS and plain partitions alike, with no filesystem-specific logic here.
# Drop BOOT_IMAGE/initrd (GRUB supplies those) and any pre-existing iommu flags.
cmdline=$(
    tr ' ' '\n' < /proc/cmdline \
    | grep -vE '^(BOOT_IMAGE|initrd)=' \
    | grep -vE '^(amd_)?iommu=' \
    | tr '\n' ' '
)
[ -n "$cmdline" ] || exit 0

rel_kernel=$(make_system_path_relative_to_its_root "$kernel")
rel_initrd=$(make_system_path_relative_to_its_root "$initrd")

cat <<EOF
menuentry 'GPU-max — IOMMU off (NPU disabled), kernel ${version}' --class gnu-linux --class os \$menuentry_id_option 'iommu-off-${version}' {
	recordfail
	load_video
	gfxmode \$linux_gfx_mode
	insmod gzio
$(prepare_grub_to_access_device "$(${grub_probe} --target=device /boot)" | sed 's/^/\t/')
	echo 'Loading Linux ${version} with IOMMU disabled ...'
	linux ${rel_kernel} ${cmdline} amd_iommu=off
	echo 'Loading initial ramdisk ...'
	initrd ${rel_initrd}
}
EOF
GENERATOR
chmod 0755 "$GEN"

# The entry is unreachable if the menu never shows. Mint/Ubuntu default to a
# hidden menu with a zero timeout.
if grep -qE '^GRUB_TIMEOUT_STYLE=hidden|^GRUB_TIMEOUT=0' "$DEFAULTS"; then
    cp -a "$DEFAULTS" "${DEFAULTS}.bak.${STAMP}"
    echo "==> backup: ${DEFAULTS}.bak.${STAMP}"
    sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$DEFAULTS"
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$DEFAULTS"
    echo "==> menu made visible (GRUB_TIMEOUT_STYLE=menu, GRUB_TIMEOUT=5)"
    grep -E '^GRUB_(DEFAULT|TIMEOUT)' "$DEFAULTS"
fi

echo
update-grub

echo
echo "==> boot entries now available:"
grep -oP "^menuentry '\K[^']+" /boot/grub/grub.cfg | sed 's/^/    /'
echo
echo "GRUB_DEFAULT=$(grep -oP '^GRUB_DEFAULT=\K.*' "$DEFAULTS") — the default entry keeps the IOMMU on (NPU works)."
echo "Pick the 'GPU-max' entry at boot for full iGPU throughput without the NPU."
