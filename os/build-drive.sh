#!/bin/bash
# Install Ollie OS straight onto a drive from the profile os/build.sh has put
# together, instead of building the ISO (OLLIE_BUILD_DISK; the Ollie OS Drive
# Writer, os/usb/ollie-install-drive):
#   1. Ollie OS's own installer (ollie-install) erases the drive and makes its
#      parts, as "Install Ollie OS" does from the USB.
#   2. On it goes what mkarchiso would put in the ISO's system: Ollie OS's own
#      files, then Arch Linux's packages, downloaded onto the drive itself.
#   3. The installer makes that an installed system that starts by itself on
#      new computers and old ones.
#   4. The drive is checked, what is wrong is fixed, and a report is written.
# Runs as root in the Arch Linux that os/build.sh runs in:
#
#   build-drive.sh PROFILE DISK REPORT
#
# Exit status: 0 installed and checked; 3 installed, but the check found
# problems it could not fix (in the report); anything else, not installed.
set -uo pipefail

profile=${1:?} disk=${2:?} report=${3:?}
# shellcheck source=drive-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/drive-common.sh"

# --- 1-3. Installing -------------------------------------------------------------------
# ollie-install runs fill_target (OLLIE_INSTALL_FILL) with the drive's new
# parts mounted at TARGET, where it would copy the live USB's system.
export -f fill_target list
export OLLIE_PROFILE=$profile

OLLIE_INSTALL_DISK=$disk OLLIE_INSTALL_YES=1 OLLIE_INSTALL_PROGRESS=1 OLLIE_INSTALL_NO_EFI_VARS=1 \
    OLLIE_INSTALL_FILL=fill_target OLLIE_INSTALL_TIMEZONE="${OLLIE_INSTALL_TIMEZONE:-UTC}" \
    bash "$profile/airootfs/usr/local/bin/ollie-install" </dev/null || exit 1

# --- 4. Checking it ----------------------------------------------------------------------
step "Checking Ollie OS on the drive (and fixing what is wrong)"
echo "PROGRESS 99 Checking Ollie OS on the drive"
if [[ "$disk" =~ [0-9]$ ]]; then sep=p; else sep=; fi
boot_part=${disk}${sep}1 root_part=${disk}${sep}2
t=/mnt/ollie-check
mkdir -p "$t"
mount -o subvol=@ "$root_part" "$t" && mount -o subvol=@home "$root_part" "$t/home" && mount "$boot_part" "$t/boot" ||
    { echo "The drive could not be opened to check it."; exit 1; }
trap 'umount -R "$t" 2>/dev/null' EXIT
in_target() { arch-chroot "$t" "$@"; }
# Packages again (to put back what is damaged or missing): with the build's
# keys and settings, from the drive's own package cache where it has them.
reinstall() { pacstrap -C "$profile/pacman.conf" -G -M "$t" "$@" >/tmp/ollie-reinstall.log 2>&1; }
uuid="$(blkid -s UUID -o value "$root_part")"
report_start "$disk"
check_common

entry() { # entry TITLE OPTIONS: a systemd-boot menu entry
    printf 'title   %s\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions root=UUID=%s rootflags=subvol=@ rw%s\n' "$1" "$uuid" "$2"
}
test_uefi() {
    local f
    for f in EFI/BOOT/BOOTX64.EFI EFI/systemd/systemd-bootx64.efi loader/loader.conf loader/entries/ollie.conf; do
        [[ -s "$t/boot/$f" ]] || { echo "$f is missing"; return 1; }
    done
    grep -q "root=UUID=$uuid " "$t/boot/loader/entries/ollie.conf" || { echo "the menu does not point at Ollie OS"; return 1; }
}
fix_uefi() {
    in_target bootctl install --esp-path=/boot --no-variables 2>/dev/null ||
        in_target bootctl update --esp-path=/boot --no-variables 2>/dev/null
    printf 'default ollie.conf\ntimeout 2\neditor no\n' >"$t/boot/loader/loader.conf"
    entry "Ollie OS" " quiet splash" >"$t/boot/loader/entries/ollie.conf"
    entry "Ollie OS (show start-up messages)" "" >"$t/boot/loader/entries/ollie-fallback.conf"
}
check "Starting on new computers: Steam Machine, Dells, Intel Macs (UEFI)" test_uefi fix_uefi
if [[ -n "${OLLIE_SB_KEYDIR:-}" ]]; then
    sb="$profile/airootfs/usr/local/lib/ollie/secureboot"
    test_secureboot() { bash "$sb" check "$t/boot" "$OLLIE_SB_KEYDIR"; }
    fix_secureboot() { bash "$sb" system "$t" "$OLLIE_SB_KEYDIR"; }
    check "Starting with Secure Boot on (the first time: MokManager, Enroll key from disk, OLLIE-OS-KEY.cer)" test_secureboot fix_secureboot
fi

test_bios() {
    [[ -s "$t/boot/syslinux/ldlinux.sys" ]] || { echo "SYSLINUX is not installed"; return 1; }
    grep -q "root=UUID=$uuid " "$t/boot/syslinux/syslinux.cfg" || { echo "the menu does not point at Ollie OS"; return 1; }
    cmp -s -n 440 "$disk" /usr/lib/syslinux/bios/gptmbr.bin || { echo "the drive's start-up code is missing"; return 1; }
    sgdisk -A 1:get:2 "$disk" 2>/dev/null | grep -q ':2:1' || { echo "the start-up part is not marked for BIOS"; return 1; }
}
fix_bios() {
    extlinux --install "$t/boot/syslinux" &&
        dd if=/usr/lib/syslinux/bios/gptmbr.bin of="$disk" bs=440 count=1 conv=notrunc status=none &&
        sgdisk --attributes=1:set:2 "$disk"
}
check "Starting on older computers set to BIOS / Legacy" test_bios fix_bios

test_fstab() {
    grep -q "^UUID=${uuid}[[:space:]]*/[[:space:]]" "$t/etc/fstab" && grep -q "[[:space:]]/boot[[:space:]]" "$t/etc/fstab" ||
        { echo "the list of the drive's parts is wrong"; return 1; }
}
fix_fstab() { genfstab -U "$t" | sed -E 's/,subvolid=[0-9]+//; s/subvolid=[0-9]+,//' >"$t/etc/fstab"; }
check "The drive's parts are found at start-up (fstab)" test_fstab fix_fstab

check "The desktop, and the first start that asks for your name and password" test_first_start fix_first_start

# The downloaded packages are not needed any more: their room goes to Steam
# and everything you save. (The Fixer downloads what it needs to put back.)
rm -rf -- "${t:?}"/var/cache/pacman/pkg/*
free_gb=$(($(df -B1 --output=avail "$t" | tail -n 1) / 1000000000))
used_gb=$(($(df -B1 --output=used "$t" | tail -n 1) / 1000000000))
printf '  ROOM     %s GB free for Steam, games and everything you save (Ollie OS uses %s GB)\n' "$free_gb" "$used_gb" | tee -a "$report"

# Last, the drive's file systems themselves, closed.
umount -R "$t"
trap - EXIT
sync
test_fs() {
    fsck.fat -n "$boot_part" >/dev/null 2>&1 || { echo "the start-up part has errors"; return 1; }
    btrfs check --readonly "$root_part" >/dev/null 2>&1 || { echo "Ollie OS's part has errors"; return 1; }
}
fix_fs() { fsck.fat -a "$boot_part"; }
check "The drive's file systems have no errors" test_fs fix_fs
sync

report_end
exit $?
