#!/bin/bash
# Check a built Ollie OS ISO without booting it: unpack it and confirm that
# everything Ollie OS promises is actually inside.
#
#   os/tests/check-iso.sh ollie-os-*.iso
#
# Needs xorriso and unsquashfs. Prints one line per check and exits non-zero
# if any check fails.
set -uo pipefail

iso="${1:?usage: check-iso.sh ISO}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0 fail=0
ok() { printf '  \e[32mok\e[0m    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \e[31mFAIL\e[0m  %s\n' "$1"; fail=$((fail + 1)); }
check() { # check "description" command...
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

echo "== ISO layout"
xorriso -osirrox on -indev "$iso" -extract / "$work/iso" >/dev/null 2>&1
chmod -R u+w "$work/iso"
check "boot loader for UEFI (Steam Deck / Steam Machine)" test -f "$work/iso/EFI/BOOT/BOOTx64.EFI"
check "boot menu entries" compgen -G "$work/iso/loader/entries/*.conf"
check "kernel" test -f "$work/iso/arch/boot/x86_64/vmlinuz-linux"
check "initramfs" test -f "$work/iso/arch/boot/x86_64/initramfs-linux.img"
check "boot menu says Ollie OS" grep -rq "Ollie OS" "$work/iso/loader/entries"
check "boot menu finds the ISO by UUID (USB Maker rewrites this)" grep -rqE 'archisosearchuuid=|archisolabel=' "$work/iso/loader/entries"
check "Secure Boot: the USB starts shim, with the key for MokManager and for the installer" bash -c "cmp -s '$work/iso/EFI/BOOT/BOOTx64.EFI' '$work/iso/EFI/ollie/shimx64.efi' && test -s '$work/iso/EFI/BOOT/grubx64.efi' && test -s '$work/iso/OLLIE-OS-KEY.cer' && test -s '$work/iso/ollie/secureboot/ollie.key'"
sfs="$work/iso/arch/x86_64/airootfs.sfs"
check "system image present" test -f "$sfs"
size=$(stat -c %s "$sfs" 2>/dev/null || echo 0)
if ((size > 0 && size < 4 * 1024 * 1024 * 1024)); then
    ok "system image fits on FAT32 ($((size / 1024 / 1024)) MB < 4096 MB)"
else
    bad "system image fits on FAT32 ($((size / 1024 / 1024)) MB)"
fi
iso_mb=$(($(stat -c %s "$iso") / 1024 / 1024))
if ((iso_mb < 2047)); then ok "ISO is one file under GitHub's 2 GB limit ($iso_mb MB)"; else bad "ISO is one file under GitHub's 2 GB limit ($iso_mb MB)"; fi
echo "   What takes the room on the ISO (MB):"
(cd "$work/iso" && du -m -a . 2>/dev/null | sort -rn | awk '$1 >= 5' | head -n 12 | sed 's/^/     /')
if ((iso_mb < 5 * 1024)); then ok "ISO fits the USB Maker's 5 GB boot partition ($iso_mb MB)"; else bad "ISO too big for 5 GB boot partition ($iso_mb MB)"; fi

echo "== System image"
unsquashfs -no-progress -quiet -d "$work/root" "$sfs" >/dev/null 2>&1 || bad "unpack system image"
r="$work/root"
pkg() { compgen -G "$r/var/lib/pacman/local/$1-[0-9]*" >/dev/null || compgen -G "$r/var/lib/pacman/local/$1-r[0-9]*" >/dev/null; }
for p in bibata-cursor-theme-bin pciutils usbutils vulkan-tools linux plasma-desktop sddm dolphin konsole steam wine wine-mono gamescope firefox \
    networkmanager pipewire mesa vulkan-radeon lib32-vulkan-radeon zram-generator btrfs-progs arch-install-scripts; do
    check "package $p" pkg "$p"
done
check "The Fixer in the menu" test -f "$r/usr/share/applications/ollie-fixer.desktop"
check "Get Proton-GE in the menu" test -f "$r/usr/share/applications/ollie-get-proton-ge.desktop"
check "graphics firmware for AMD (Steam Machine, Steam Deck)" compgen -G "$r/usr/lib/firmware/amdgpu/*"
check "kernel modules present" compgen -G "$r/usr/lib/modules/*/vmlinuz"

echo "== Ollie OS pieces"
for f in /usr/local/bin/oliver /usr/local/bin/ollie-install /usr/local/bin/ollie-write \
    /usr/local/bin/ollie-add-to-bar /usr/local/bin/ollie-live-setup \
    /usr/local/bin/ollie-dc /usr/local/bin/ollie-drivers \
    /usr/local/bin/ollie-first-setup /usr/local/bin/ollie-set-account /usr/local/bin/ollie-get-proton-ge \
    /usr/local/bin/ollie-fixer /usr/local/bin/ollie-fixer-helper; do
    check "$f is executable" test -x "$r$f"
done
check "oliver runs" "$r/usr/local/bin/oliver" help
check "Oliver handles .exe files" grep -q 'application/x-ms-dos-executable=oliver.desktop' "$r/etc/xdg/mimeapps.list"
check "oliver.desktop installed" test -f "$r/usr/share/applications/oliver.desktop"
check "Firefox is the default browser" grep -q 'https=firefox.desktop' "$r/etc/xdg/mimeapps.list"
check "firefox.desktop exists" test -f "$r/usr/share/applications/firefox.desktop"
check "steam.desktop exists" test -f "$r/usr/share/applications/steam.desktop"
check "DC - Debug Computer in the menu" test -f "$r/usr/share/applications/ollie-dc.desktop"
check "Driver Installer in the menu" test -f "$r/usr/share/applications/ollie-drivers.desktop"
check "DC icon" test -f "$r/usr/share/icons/hicolor/scalable/apps/ollie-dc.svg"
check "Driver Installer icon" test -f "$r/usr/share/icons/hicolor/scalable/apps/ollie-drivers.svg"
check "Bibata cursor installed" test -d "$r/usr/share/icons/Bibata-Modern-Ice/cursors"
check "Bibata cursor is the default" grep -q 'cursorTheme=Bibata-Modern-Ice' "$r/etc/xdg/kcminputrc"
check "lspci for the Driver Installer" test -x "$r/usr/bin/lspci"
check "vulkaninfo for DC" test -x "$r/usr/bin/vulkaninfo"
check "cube logo icon" test -f "$r/usr/share/icons/hicolor/scalable/apps/ollie-os.svg"
for s in 1280x720 1920x1080 2560x1440 3840x2160; do
    check "wallpaper $s" test -s "$r/usr/share/wallpapers/OllieOS/contents/images/$s.png"
done
check "Google search box widget" test -f "$r/usr/share/plasma/plasmoids/org.ollieos.googlesearch/contents/ui/main.qml"
check "bar layout" test -f "$r/usr/share/plasma/look-and-feel/org.ollieos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
check "look-and-feel is the default" grep -q 'LookAndFeelPackage=org.ollieos.desktop' "$r/etc/xdg/kdeglobals"
check "'Set as wallpaper' right-click menu" test -f "$r/usr/share/kio/servicemenus/ollie-set-wallpaper.desktop"
check "'Add to bar' right-click menu" test -f "$r/usr/share/kio/servicemenus/ollie-add-to-bar.desktop"
check "plasma-apply-wallpaperimage exists" test -x "$r/usr/bin/plasma-apply-wallpaperimage"
check "busctl exists (Add to bar)" test -x "$r/usr/bin/busctl"
check "Steam Game Mode in the menu" test -f "$r/usr/share/applications/steam-game-mode.desktop"
check "Plasma Wayland session" test -f "$r/usr/share/wayland-sessions/plasma.desktop"
check "login screen background" test -f "$r/usr/share/sddm/themes/breeze/theme.conf.user"
check "breeze login theme" test -d "$r/usr/share/sddm/themes/breeze"
check "kwin_wayland for the login screen" test -x "$r/usr/bin/kwin_wayland"

echo "== Services"
check "no first-boot questions (systemd-firstboot masked)" test "$(readlink "$r/etc/systemd/system/systemd-firstboot.service")" = /dev/null
check "time zone set" test -L "$r/etc/localtime"
check "keyboard layout set" test -f "$r/etc/vconsole.conf"
check "boots to the desktop" test "$(readlink "$r/etc/systemd/system/default.target")" = /usr/lib/systemd/system/graphical.target
check "login screen enabled" test -e "$r/usr/lib/systemd/system/sddm.service"
check "networking enabled" test -e "$r/usr/lib/systemd/system/NetworkManager.service"
check "bluetooth unit exists" test -e "$r/usr/lib/systemd/system/bluetooth.service"
check "power profiles unit exists" test -e "$r/usr/lib/systemd/system/power-profiles-daemon.service"
check "paccache timer exists" test -e "$r/usr/lib/systemd/system/paccache.timer"
check "pacman has multilib" grep -q '^\[multilib\]' "$r/etc/pacman.conf"
check "pacman has no build-only local repo" bash -c "! grep -q 'ollie-local' '$r/etc/pacman.conf'"
check "pacman has working mirrors" grep -q '^Server' "$r/etc/pacman.d/mirrorlist"
check "live initramfs hooks" grep -q archiso "$r/etc/mkinitcpio.conf.d/archiso.conf"
check "admin tasks need no password (sudo)" grep -q 'NOPASSWD' "$r/etc/sudoers.d/10-wheel"
check "admin tasks need no password (polkit)" test -f "$r/etc/polkit-1/rules.d/49-ollie-no-password.rules"
check "straight to the desktop (autologin)" grep -q '^User=ollie' "$r/etc/sddm.conf.d/20-autologin.conf"
check "live setup runs even when the system was copied into memory" grep -q '^ConditionKernelCommandLine=archisobasedir' "$r/etc/systemd/system/ollie-live-setup.service"
check "login screen waits for the graphics card" test -f "$r/etc/systemd/system/sddm.service.d/10-ollie-wait-for-graphics.conf"
check "screen never locks" grep -q '^Autolock=false' "$r/etc/xdg/kscreenlockerrc"
check "USB Maker's account choice is honoured" grep -q 'ollie-account.conf' "$r/usr/local/bin/ollie-live-setup"
check "first start asks for a username and password" test -f "$r/etc/xdg/autostart/ollie-first-setup.desktop"
check "kdialog for the first-start questions" test -x "$r/usr/bin/kdialog"
check "chpasswd for the first-start account" test -x "$r/usr/bin/chpasswd"
check "installer asks for no password" bash -c "! grep -q 'read -rsp' '$r/usr/local/bin/ollie-install'"
check "Installing Windows too: Setup helper, its download and the Install Windows app" bash -c "test -x '$r/usr/local/bin/ollie-windows-setup' && test -x '$r/usr/local/lib/ollie/get-windows.py' && test -x '$r/usr/local/bin/ollie-windows-install' && test -f '$r/usr/local/share/ollie/ollie-windows-install.desktop' && grep -q OLLIE_INSTALL_WINDOWS_VERSION '$r/usr/local/bin/ollie-install-gui'"
check "Windows asked for in the Drive Writer: room made at the first start (ollie-windows-plan)" bash -c "test -x '$r/usr/local/lib/ollie/windows-plan' && test -L '$r/etc/systemd/system/multi-user.target.wants/ollie-windows-plan.service'"
check "efibootmgr and wimlib for Windows Setup" bash -c "test -x '$r/usr/bin/efibootmgr' && test -x '$r/usr/bin/wimlib-imagex'"
check "translations kept (NoExtract removed)" compgen -G "$r/usr/share/locale/de/LC_MESSAGES/*"

echo "== The Game Pack"
for p in gamemode lib32-gamemode mangohud lib32-mangohud plymouth libinput; do
    check "package $p" pkg "$p"
done
for f in steam speed-boost minecraft startup-sound os-update colours settings welcome parent screen-time \
    timesup typing-scanner scanner-notes firefox update-checker; do
    check "/usr/local/bin/ollie-$f is executable" test -x "$r/usr/local/bin/ollie-$f"
done
check "Steam opens the Ollie OS way" grep -q 'ollie-steam' "$r/usr/local/share/applications/steam.desktop"
check "Firefox asks for its password" grep -q 'ollie-firefox' "$r/usr/local/share/applications/firefox.desktop"
check "start-up animation theme" test -s "$r/usr/share/plymouth/themes/ollie/cube-0.png"
check "start-up animation chosen" grep -q '^Theme=ollie' "$r/etc/plymouth/plymouthd.conf"
check "live USB's start-up image without the animation" bash -c "! grep -q plymouth '$r/etc/mkinitcpio.conf.d/archiso.conf'"
check "start-up sound" test -s "$r/usr/share/sounds/ollie/startup.ogg"
check "Speed Boost runs at every start" test -L "$r/etc/systemd/user/default.target.wants/ollie-speed-boost.service"
check "Screen Time runs at every start" test -L "$r/etc/systemd/system/multi-user.target.wants/ollie-screen-time.service"
check "FPS counter on in games" grep -q '^MANGOHUD=1' "$r/etc/environment.d/20-ollie-games.conf"
check "controller rules" test -s "$r/etc/udev/rules.d/71-ollie-controllers.rules"
check "purple and red backgrounds" test -s "$r/usr/share/wallpapers/OllieOS-Purple/contents/images/1920x1080.png"
check "grown-up settings start empty" grep -q '^PIN_MD5=$' "$r/etc/ollie/parent.conf"
check "Welcome opens at the first start" test -f "$r/etc/xdg/autostart/ollie-welcome.desktop"
check "qml6 for Welcome and Settings" test -x "$r/usr/bin/qml6"
check "a keyboard reader for the Typing Scanner (libinput, or od and stdbuf)" bash -c "test -x '$r/usr/bin/libinput' || { test -x '$r/usr/bin/od' && test -x '$r/usr/bin/stdbuf'; }"
check "Update Checker in the menu" test -f "$r/usr/share/applications/ollie-update-checker.desktop"
check "the list of the latest updates" test -s "$r/usr/local/share/ollie/updates.qml"
check "Update Checker is asked about at the first start (off until then)" bash -c "! test -e '$r/etc/systemd/user/timers.target.wants/ollie-update-checker.timer' && grep -q update-checker '$r/usr/local/bin/ollie-welcome'"
check "python for the Update Checker" test -x "$r/usr/bin/python3"
for f in games finder typing pet coop sticker comic paint mouse school animator soundboard codequest space spelling world mathquest appcenter trophies gamehub quickmenu playtime music photobooth tour screensaver; do
    check "/usr/local/bin/ollie-$f is executable" test -x "$r/usr/local/bin/ollie-$f"
    check "$f window" test -s "$r/usr/local/share/ollie/$f.qml"
done
for f in sticker spelling animator soundboard world space; do
    check "$f is in the App Center (Ollie apps), not the apps menu" bash -c "test -f '$r/usr/local/share/ollie/store/ollie-$f.desktop' && ! test -e '$r/usr/share/applications/ollie-$f.desktop'"
done
check "Games' helper runs" test -x "$r/usr/local/lib/ollie/games.py"
check "Mouse Maker's helper runs" test -x "$r/usr/local/lib/ollie/mouse.py"
check "Ollie OS saves itself before updates (snapshot, Undo an update)" bash -c "test -x '$r/usr/local/lib/ollie/snapshot' && test -x '$r/usr/local/bin/ollie-undo-update' && test -f '$r/usr/local/share/ollie/pacman-hooks/00-ollie-save.hook'"
check "the save-before-update hook is not in the USB's pacman (it would run while building)" bash -c "! test -e '$r/etc/pacman.d/hooks/00-ollie-save.hook'"
check "saved starts are tidied at each start" test -L "$r/etc/systemd/system/multi-user.target.wants/ollie-saved-cleanup.service"
check "Secure Boot: the signing tool, shim and MokManager" bash -c "test -x '$r/usr/local/lib/ollie/secureboot' && test -s '$r/usr/local/share/ollie/secureboot/shimx64.efi' && test -s '$r/usr/local/share/ollie/secureboot/mmx64.efi' && test -f '$r/usr/local/share/ollie/pacman-hooks/zz-ollie-secureboot.hook'"
check "Secure Boot: sbsign for the installer" test -x "$r/usr/bin/sbsign"
check "Secure Boot: shim is the one from Ubuntu's shim-signed 15.8" bash -c "echo '3ed8aa3591f793de2e0886d077aae950810843caac5eaf96e1436a439bf5e150  $r/usr/local/share/ollie/secureboot/shimx64.efi' | sha256sum -c --quiet"
check "Couch Co-op's controller watcher runs" test -x "$r/usr/local/lib/ollie/pads.py"
check "the pet's body" test -s "$r/usr/local/share/ollie/PetBody.qml"
check "the pet on the desktop" test -s "$r/usr/local/share/ollie/pet-desktop.qml"
check "the secrets' confetti" test -s "$r/usr/local/share/ollie/Confetti.qml"
check "World Explorer's map" python3 -c "import json,sys; assert len(json.load(open(sys.argv[1]))) > 150" "$r/usr/local/share/ollie/world.json"
check "No robot voice (ollie-say and Read aloud are gone)" bash -c "! test -e '$r/usr/local/bin/ollie-say' && ! test -e '$r/usr/local/bin/ollie-readaloud'"
check "the in-game overlay switch" test -x "$r/usr/local/bin/ollie-overlay"
check "ffmpeg for the Animator and the Sound Board" test -x "$r/usr/bin/ffmpeg"
check "Ollie OS version 1.6" grep -qx "1.6" "$r/etc/ollie-version"
check "the colourful app icons" test -s "$r/usr/share/icons/hicolor/256x256/apps/ollie-games.png"
check "the controller helper and Play Time start with the desktop" bash -c "test -L '$r/etc/systemd/user/default.target.wants/ollie-padd.service' && test -L '$r/etc/systemd/user/default.target.wants/ollie-playtime.service' && test -x '$r/usr/local/lib/ollie/padd.py'"
check "the controller as a mouse may make its mouse (uinput)" bash -c "grep -q uinput '$r/etc/udev/rules.d/71-ollie-controllers.rules' && test -s '$r/etc/modules-load.d/ollie-uinput.conf'"
check "seasonal themes start with the desktop" bash -c "test -x '$r/usr/local/bin/ollie-seasons' && test -f '$r/etc/xdg/autostart/ollie-seasons.desktop' && test -s '$r/usr/local/share/ollie/birthday.qml'"
check "the seasonal backgrounds" bash -c "for s in Halloween Winter Birthday; do test -s '$r/usr/share/wallpapers/OllieOS-'\$s'/contents/images/1920x1080.png' || exit 1; done"
check "Ollie's Tour opens at the first start" grep -q ollie-tour "$r/usr/local/bin/ollie-welcome"
check "the Ollie login screen" bash -c "grep -q login-background '$r/usr/share/sddm/themes/breeze/theme.conf.user' && test -s '$r/usr/local/share/ollie/login-background.png' && test -s '$r/usr/local/share/ollie/avatar.png'"
check "the screensaver starts with the desktop" test -f "$r/etc/xdg/autostart/ollie-screensaver.desktop"
check "Bedtime" bash -c "grep -q bedtime-left '$r/usr/local/bin/ollie-parent' && grep -q 'ollie-parent bedtime-left' '$r/usr/local/bin/ollie-screen-time'"
check "Easy reading and languages" bash -c "test -x '$r/usr/local/bin/ollie-easyread' && test -x '$r/usr/local/bin/ollie-language'"
check "Trophies can be earned" test -x "$r/usr/local/bin/ollie-trophy"
check "Fun Fact of the Day on the desktop" bash -c "test -s '$r/usr/share/plasma/plasmoids/org.ollieos.funfact/contents/ui/facts.js' && grep -q org.ollieos.funfact '$r/usr/share/plasma/look-and-feel/org.ollieos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js'"
check "Recovery Mode in the menu" test -f "$r/usr/share/applications/ollie-recovery.desktop"
check "Recovery Mode's window and helper" bash -c "test -s '$r/usr/local/share/ollie/recovery.qml' && test -x '$r/usr/local/lib/ollie/recovery-helper' && test -x '$r/usr/local/lib/ollie/recovery-cleanup' && test -x '$r/usr/local/bin/ollie-recovery'"
check "Recovery Mode's tools (btrfs, rsync, arch-chroot)" bash -c "test -x '$r/usr/bin/btrfs' && test -x '$r/usr/bin/rsync' && test -x '$r/usr/bin/arch-chroot'"
check "the old-version cleanup is off until Recovery Mode switches it on" bash -c "test -f '$r/etc/systemd/system/ollie-recovery-cleanup.timer' && ! test -e '$r/etc/systemd/system/timers.target.wants/ollie-recovery-cleanup.timer'"
check "the secret Ollie Gold background" test -s "$r/usr/share/wallpapers/OllieOS-Gold/contents/images/1920x1080.png"
check "live USB starts without the start-up animation" grep -rq 'plymouth.enable=0' "$work/iso/loader/entries"

echo
echo "== The 25 largest packages (installed MB)"
for d in "$r"/var/lib/pacman/local/*/; do
    awk -v n="$(basename "$d")" '/^%SIZE%/ {getline; printf "%8d  %s\n", $1 / 1048576, n}' "$d/desc"
done | sort -rn | head -n 25

echo
echo "$pass passed, $fail failed"
((fail == 0))
