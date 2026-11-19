#!/bin/bash
# Put Ollie OS on a drive with no admin rights and no password (OLLIE_BUILD_FILES;
# the Ollie OS Drive Writer on SteamOS, os/usb/ollie-install-drive). This
# computer's own disk service (udisks) has already erased the drive and made
# its two parts, the way Dolphin formats a USB drive: OLLIE_BOOT (the start-up
# part) and OLLIE (Ollie OS's part, btrfs, yours), both mounted. This runs as
# "root" of a user namespace of its own (really you), as the Builder does, so
# what it writes on the drive belongs to you, not to root and the system's
# own users. So:
#   1. Ollie OS's system is made in a folder on the drive: Ollie OS's own
#      files, then Arch Linux's packages, downloaded onto the drive.
#   2. It is set up as an installed system, the way Ollie OS's installer does
#      it (ollie-install), and its start-up files go on the start-up part.
#   3. It is checked, and what is wrong is fixed.
#   4. It is packed, with every file's owner and permissions, into
#      ollie-system.tar.zst on the drive. At the drive's first start Ollie OS
#      unpacks it as root (the ollie-unpack start-up hook) and starts; then
#      it adds the start-up code for older BIOS computers (ollie-drive-finish).
# Runs in the Arch Linux os/build.sh runs in:
#
#   build-drive-files.sh PROFILE DRIVE BOOT REPORT
#
# DRIVE and BOOT: the two parts, mounted; their IDs in OLLIE_ROOT_UUID and
# OLLIE_BOOT_UUID; the drive itself (for the report) in OLLIE_DRIVE_NAME.
# Exit status: 0 done and checked; 3 done, but the check found problems it
# could not fix (in the report); anything else, not done.
set -uo pipefail

profile=${1:?} drive=${2:?} esp=${3:?} report=${4:?}
uuid=${OLLIE_ROOT_UUID:?} boot_uuid=${OLLIE_BOOT_UUID:?}
# shellcheck source=drive-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/drive-common.sh"
die() {
    printf '\e[1;31mError:\e[0m %s\n' "$*" >&2
    exit 1
}
t=$drive/ollie-system
in_target() { arch-chroot "$t" "$@"; }
# Packages again (to put back what is damaged or missing): with the build's
# keys and settings, from the drive's own package cache where it has them.
reinstall() { pacstrap -C "$profile/pacman.conf" -G -M "$t" "$@" >/tmp/ollie-reinstall.log 2>&1; }
export OLLIE_PROFILE=$profile

# --- 1. Ollie OS's system, in a folder on the drive ------------------------------------------
step "Installing Ollie OS's programs"
echo "PROGRESS 5 Installing Ollie OS's programs"
rm -rf --one-file-system "${t:?}" "${drive:?}"/ollie-system.tar.zst* "${drive:?}"/ollie-home.tar.zst*
mkdir -p "$t" || die "could not write to the drive."
fill_target "$t" || die "installing Ollie OS's programs failed (see above)."

# --- 2. As an installed system (what ollie-install does after copying) -----------------------
step "Setting up the installed system"
echo "PROGRESS 80 Setting up Ollie OS on the drive"
rm -f "$t/etc/mkinitcpio.conf.d/archiso.conf" \
    "$t/etc/systemd/system/multi-user.target.wants/ollie-live-setup.service" \
    "$t/usr/share/applications/ollie-install.desktop"
# One start-up image with every driver (no autodetect), so the drive starts
# on any computer; with the hook that unpacks the system at the first start.
cat >"$t/etc/mkinitcpio.d/linux.preset" <<'EOF'
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux.img"
default_options="-S autodetect"
EOF
for unit in emergency rescue; do
    install -D -m 0644 /dev/stdin "$t/etc/systemd/system/$unit.service.d/ollie-shell.conf" <<'EOF'
[Service]
Environment=SYSTEMD_SULOGIN_FORCE=1
EOF
done
cat >"$t/etc/mkinitcpio.conf.d/ollie.conf" <<'EOF'
FILES=(/etc/systemd/system/emergency.service.d/ollie-shell.conf /etc/systemd/system/rescue.service.d/ollie-shell.conf)
EOF
echo 'HOOKS+=(ollie-unpack)' >"$t/etc/mkinitcpio.conf.d/ollie-unpack.conf"
cat >"$t/etc/fstab" <<EOF
# Ollie OS on a drive made by the Drive Writer
UUID=$uuid	/	btrfs	rw,noatime,compress=zstd:3,subvol=/@	0 0
UUID=$uuid	/home	btrfs	rw,noatime,compress=zstd:3,subvol=/@home	0 0
UUID=$boot_uuid	/boot	vfat	rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro	0 2
EOF
timezone="${OLLIE_INSTALL_TIMEZONE:-UTC}"
[[ -f "$t/usr/share/zoneinfo/$timezone" ]] || timezone=UTC
echo ollie >"$t/etc/hostname"
ln -sf "/usr/share/zoneinfo/$timezone" "$t/etc/localtime"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$t/etc/locale.gen"
echo LANG=en_US.UTF-8 >"$t/etc/locale.conf"
in_target /bin/bash -euo pipefail -s <<'CHROOT' || die "setting up Ollie OS on the drive failed (see above)."
locale-gen >/dev/null
useradd -m -G wheel,video,audio,input,storage -s /bin/bash -c "Ollie" ollie
passwd -d ollie >/dev/null
passwd -l root >/dev/null
mkinitcpio -P
CHROOT
# Finished at the first start, as root: the start-up code for older computers.
mkdir -p "$t/etc/systemd/system/multi-user.target.wants"
ln -sfn /etc/systemd/system/ollie-drive-finish.service "$t/etc/systemd/system/multi-user.target.wants/ollie-drive-finish.service"

# The start-up part: what is in the system's /boot (the kernel, its start-up
# image, CPU microcode), systemd-boot as every computer's fallback loader,
# its menu, and SYSLINUX's files for older computers (switched on at the
# first start). The first start unpacks the system (ollie.unpack).
entry() { # entry TITLE OPTIONS
    printf 'title   %s\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions root=UUID=%s rootflags=subvol=@ rw%s ollie.unpack\n' "$1" "$uuid" "$2"
}
put_boot_files() {
    cp -rf "$t/boot/." "$esp/" &&
        mkdir -p "$esp/EFI/BOOT" "$esp/EFI/systemd" "$esp/loader/entries" "$esp/syslinux" &&
        cp -f "$t/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "$esp/EFI/BOOT/BOOTX64.EFI" &&
        cp -f "$t/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "$esp/EFI/systemd/systemd-bootx64.efi" &&
        printf 'default ollie.conf\ntimeout 2\neditor no\n' >"$esp/loader/loader.conf" &&
        entry "Ollie OS" " quiet splash" >"$esp/loader/entries/ollie.conf" &&
        entry "Ollie OS (show start-up messages)" "" >"$esp/loader/entries/ollie-fallback.conf" &&
        cp -f "$t"/usr/lib/syslinux/bios/{ldlinux.c32,libcom32.c32,libutil.c32,menu.c32} "$esp/syslinux/" &&
        cat >"$esp/syslinux/syslinux.cfg" <<EOF
DEFAULT ollie
PROMPT 0
TIMEOUT 20
UI menu.c32
MENU TITLE Ollie OS
LABEL ollie
    MENU LABEL Ollie OS
    LINUX /vmlinuz-linux
    INITRD /initramfs-linux.img
    APPEND root=UUID=$uuid rootflags=subvol=@ rw quiet splash
LABEL messages
    MENU LABEL Ollie OS (show start-up messages)
    LINUX /vmlinuz-linux
    INITRD /initramfs-linux.img
    APPEND root=UUID=$uuid rootflags=subvol=@ rw
EOF
}
put_boot_files || die "could not write Ollie OS's start-up files to the drive's start-up part."

# --- 3. Checking it -------------------------------------------------------------------------
step "Checking Ollie OS on the drive (and fixing what is wrong)"
echo "PROGRESS 90 Checking Ollie OS on the drive"
report_start "${OLLIE_DRIVE_NAME:-the drive}"
OLLIE_NEED_HOOKS="ollie-unpack" check_common
test_uefi() {
    local f
    for f in vmlinuz-linux initramfs-linux.img EFI/BOOT/BOOTX64.EFI loader/loader.conf loader/entries/ollie.conf; do
        [[ -s "$esp/$f" ]] || { echo "$f is missing"; return 1; }
    done
    cmp -s "$esp/vmlinuz-linux" "$t/boot/vmlinuz-linux" && cmp -s "$esp/initramfs-linux.img" "$t/boot/initramfs-linux.img" ||
        { echo "the start-up part has older start-up files"; return 1; }
    grep -q "root=UUID=$uuid .*ollie.unpack" "$esp/loader/entries/ollie.conf" || { echo "the menu does not point at Ollie OS"; return 1; }
}
# Secure Boot: Linux signed in the system too (the check above compares the two).
if [[ -n "${OLLIE_SB_KEYDIR:-}" ]]; then
    sb="$profile/airootfs/usr/local/lib/ollie/secureboot"
    bash "$sb" keep "$t" "$OLLIE_SB_KEYDIR" && bash "$sb" sign "$t/boot/vmlinuz-linux" "$OLLIE_SB_KEYDIR" || true
fi
check "Starting on new computers: Steam Machine, Dells, Intel Macs (UEFI)" test_uefi put_boot_files
if [[ -n "${OLLIE_SB_KEYDIR:-}" ]]; then
    test_secureboot() { bash "$sb" check "$esp" "$OLLIE_SB_KEYDIR"; }
    fix_secureboot() { bash "$sb" esp "$esp" "$OLLIE_SB_KEYDIR" "$t/usr/lib/systemd/boot/efi/systemd-bootx64.efi"; }
    check "Starting with Secure Boot on (the first time: MokManager, Enroll key from disk, OLLIE-OS-KEY.cer)" test_secureboot fix_secureboot
fi
test_fstab() {
    grep -q "^UUID=${uuid}[[:space:]]*/[[:space:]]" "$t/etc/fstab" && grep -q "^UUID=${boot_uuid}[[:space:]]*/boot[[:space:]]" "$t/etc/fstab" ||
        { echo "the list of the drive's parts is wrong"; return 1; }
}
fix_fstab() { false; }
check "The drive's parts are found at start-up (fstab)" test_fstab fix_fstab
check "The desktop, and the first start that asks for your name and password" test_first_start fix_first_start
test_finish() {
    [[ -L "$t/etc/systemd/system/multi-user.target.wants/ollie-drive-finish.service" && -x "$t/usr/local/lib/ollie/drive-finish" ]] ||
        { echo "the first start's last step is not switched on"; return 1; }
}
fix_finish() { ln -sfn /etc/systemd/system/ollie-drive-finish.service "$t/etc/systemd/system/multi-user.target.wants/ollie-drive-finish.service"; }
check "Starting on older computers set to BIOS / Legacy (switched on at the first start)" test_finish fix_finish

# --- 4. Packed for the first start ---------------------------------------------------------------
# The downloaded packages are not needed any more, and the system's /boot is
# the start-up part (copied there above).
step "Packing Ollie OS for its first start"
echo "PROGRESS 95 Packing Ollie OS for its first start"
rm -rf -- "${t:?}"/var/cache/pacman/pkg/* "${t:?}"/boot/*
pack() { # pack FROM ARCHIVE [tar options]
    tar --numeric-owner --xattrs --xattrs-include='*' --acls -I 'zstd -T0 -3' -C "$1" -cf "$2.part" "${@:3}" . &&
        mv -f "$2.part" "$2"
}
pack "$t" "$drive/ollie-system.tar.zst" --exclude='./home/*' && pack "$t/home" "$drive/ollie-home.tar.zst" ||
    die "could not pack Ollie OS on the drive (is it full?)."
test_packed() {
    [[ -s "$drive/ollie-system.tar.zst" ]] && zstd -tq "$drive/ollie-system.tar.zst" && zstd -tq "$drive/ollie-home.tar.zst" ||
        { echo "the packed system is damaged"; return 1; }
}
fix_packed() { false; }
check "Ollie OS packed for its first start, which unpacks it ($(($(stat -c %s "$drive/ollie-system.tar.zst") / 1000000)) MB)" test_packed fix_packed
rm -rf --one-file-system "${t:?}"
sync
# (Unpacked, the system takes about the room the packed file does now.)
free_gb=$(($(df -B1 --output=avail "$drive" | tail -n 1) / 1000000000))
printf '  ROOM     about %s GB free for Steam, games and everything you save\n' "$free_gb" | tee -a "$report"
echo "  FIRST START  on a newer computer (Steam Machine, Dell, Mac): it unpacks Ollie OS, 5 to 15 minutes, once." | tee -a "$report"
report_end
exit $?
