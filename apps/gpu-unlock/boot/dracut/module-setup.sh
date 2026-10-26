#!/bin/bash
# shellcheck disable=SC2154
# dracut calls these functions with $kernel and its installation helpers set.
check() { modinfo -k "$kernel" gpu_unlock >/dev/null 2>&1; }
depends() { return 0; }
installkernel() { instmods gpu_unlock; }
install() {
    inst_simple /etc/modprobe.d/zz-linux-tools-gpu-unlock.conf
    inst_hook pre-udev 00 "$moddir/load.sh"
}
