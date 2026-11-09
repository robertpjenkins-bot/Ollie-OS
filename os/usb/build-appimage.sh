#!/bin/bash
# Build Ollie OS USB Maker as AppImages in os/out/:
#   Ollie-OS-USB-Maker-x86_64.AppImage      takes the ISO, its parts, or a zip
#   Ollie-OS-USB-Maker-Zip-x86_64.AppImage  the Zip edition: takes only a zip
#   Ollie-OS-Drive-Doctor-x86_64.AppImage   checks an Ollie OS drive and fixes it
#   Ollie-OS-Get-ISO-x86_64.AppImage        downloads the ISO next to USB Maker
#   Ollie-OS-Installer-x86_64.AppImage      the Builder (below), under the Installer's name
#   Ollie-OS-Drive-Writer-x86_64.AppImage   makes Ollie OS from Arch Linux right on a drive
#   Ollie-OS-Updater-x86_64.AppImage        brings an ISO up to the newest Ollie OS
#   Ollie-OS-Stuff-Saver-Updater-x86_64.AppImage  adds Stuff Saver to a running Ollie OS
#   Ollie-OS-Storage-Updater-x86_64.AppImage      adds Ollie OS Storage, the new Fixer and Stuff Saver
#   Ollie-OS-Drive-Installer-x86_64.AppImage      adds the Install Ollie OS that installs into a drive or folder
#   Ollie-OS-Discover-Updater-x86_64.AppImage     adds Discover, the app store, with Flathub
#   Ollie-OS-Windows-Boot-Updater-x86_64.AppImage puts Windows on Ollie OS's start-up menu
#   Ollie-OS-Wallpaper-Maker-Updater-x86_64.AppImage adds Wallpaper Maker (your name, or a drawing)
#   Ollie-OS-Download-Tracker-Updater-x86_64.AppImage adds Download Tracker (biobro's GitHub downloads)
#   Ollie-OS-Game-Pack-Updater-x86_64.AppImage   adds the Game Pack: Game Mode, Speed Boost, FPS, Minecraft, Settings...
#   Ollie-OS-Update-Publisher-x86_64.AppImage    for biobro: publishes an update the Update Checker tells everyone about
#   Ollie-OS-Fun-Pack-Updater-x86_64.AppImage    adds Games (drop in ROMs and ISOs), Ollie Finder, Typing Game, Ollie Pet
#   Ollie-OS-Builder-x86_64.AppImage        builds a brand-new ISO on the computer
#   Ollie-OS-Builder-Mac.zip                the same for a Mac (with Mac Setup); and as .dmg
# (Ollie-OS-Builder-Windows.exe, for Windows: os/windows/builder/build.sh.)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
os="$(dirname "$here")"
out="${OUTDIR:-$os/out}"
mkdir -p "$out"

tool="${APPIMAGETOOL:-$out/appimagetool-x86_64.AppImage}"
if [[ ! -x "$tool" ]]; then
    curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$tool"
fi

build() { # build NAME-SUFFIX DISPLAY-NAME ENV-LINE
    local appdir="$out/OllieUSB$1.AppDir"
    rm -rf "$appdir"
    install -d "$appdir"
    cat >"$appdir/AppRun" <<APPRUN
#!/bin/sh
# AppImage entry point: start the USB maker, passing along a dropped file.
HERE="\$(dirname "\$(readlink -f "\$0")")"
$3
exec "\$HERE/usr/bin/ollie-usb" "\$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -D -m 0755 "$here/ollie-usb" "$appdir/usr/bin/ollie-usb"
    sed "s/^Name=.*/Name=$2/" "$here/ollie-usb.desktop" >"$appdir/ollie-usb.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    # --appimage-extract-and-run: works without FUSE, as in containers and CI.
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-USB-Maker$1-x86_64.AppImage"
    rm -rf "$appdir"
}

build "" "Ollie OS USB Maker" ""
build "-Zip" "Ollie OS USB Maker (Zip)" "export OLLIE_USB_ZIP_ONLY=1"

# Drive Doctor carries SYSLINUX (and the mtools it uses) to add the start-up
# code for older BIOS computers. They come from Ubuntu's packages, which only
# need the C library.
build_doctor() {
    local appdir="$out/OllieDoctor.AppDir" debs="$out/doctor-debs" sl
    rm -rf "$appdir" "$debs"
    mkdir -p "$debs/x"
    (cd "$debs" && apt-get download syslinux syslinux-common mtools >/dev/null)
    for d in "$debs"/*.deb; do dpkg-deb -x "$d" "$debs/x"; done
    sl="$appdir/usr/lib/ollie-doctor/syslinux"
    install -d "$sl/modules"
    install -m 0755 "$debs/x/usr/bin/syslinux" "$debs/x/usr/bin/mtools" "$sl/"
    for l in mattrib mcopy mdel mdir mmove mformat minfo mlabel mmd mtype; do ln -s mtools "$sl/$l"; done
    install -m 0644 "$debs/x/usr/lib/syslinux/mbr/gptmbr.bin" "$debs/x/usr/lib/syslinux/mbr/mbr.bin" "$sl/"
    install -m 0644 "$debs/x/usr/lib/syslinux/modules/bios/"*.c32 "$sl/modules/"
    install -D -m 0755 "$here/ollie-doctor" "$appdir/usr/bin/ollie-doctor"
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: start Drive Doctor.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/ollie-doctor" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-doctor.desktop" "$appdir/ollie-doctor.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Drive-Doctor-x86_64.AppImage"
    rm -rf "$appdir" "$debs"
}
build_doctor


# The Updater and what it carries: the Ollie OS files changed since the ISO on
# the release was built (UPDATE_BASE), and xorriso and squashfs-tools with the
# libraries they need beyond the C library, taken from this (build) computer.
add_update_kit() { # add_update_kit APPDIR
    local appdir="$1" kit rel b lib base="${UPDATE_BASE:-dc16a2a}"
    kit="$appdir/usr/lib/ollie-update"
    carry_tools "$kit" xorriso unsquashfs mksquashfs
    (cd "$os/.." && git diff --name-only "$base" HEAD -- os/profile/airootfs) | while read -r rel; do
        rel="${rel#os/profile/airootfs/}"
        [[ -e "$os/profile/airootfs/$rel" || -L "$os/profile/airootfs/$rel" ]] || continue
        mkdir -p "$(dirname "$appdir/usr/share/ollie-update/airootfs/$rel")"
        cp -a "$os/profile/airootfs/$rel" "$appdir/usr/share/ollie-update/airootfs/$rel"
    done
    install -D -m 0755 "$here/ollie-update" "$appdir/usr/bin/ollie-update"
}

build_get_iso() {
    local appdir="$out/OllieGetISO.AppDir"
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-get-iso" "$appdir/usr/bin/ollie-get-iso"
    add_update_kit "$appdir"
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: download Ollie OS and make it the newest.
HERE="$(dirname "$(readlink -f "$0")")"
export OLLIE_UPDATER="$HERE/usr/bin/ollie-update"
exec "$HERE/usr/bin/ollie-get-iso" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-get-iso.desktop" "$appdir/ollie-get-iso.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Get-ISO-x86_64.AppImage"
    rm -rf "$appdir"
}
build_get_iso

# Get ISO and USB Maker in one: download, then straight on to choosing the drive.
# (The Installers are the Builders, under the name people look for: they
# download the Arch Linux ISO and turn it into Ollie OS, no GitHub. See
# build_builder.)


build_updater() {
    local appdir="$out/OllieUpdater.AppDir"
    rm -rf "$appdir"
    add_update_kit "$appdir"
    install -D -m 0755 "$here/ollie-usb" "$appdir/usr/bin/ollie-usb"
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: update the ISO, then hand over to USB Maker.
HERE="$(dirname "$(readlink -f "$0")")"
export OLLIE_USB_MAKER="$HERE/usr/bin/ollie-usb"
exec "$HERE/usr/bin/ollie-update" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-update.desktop" "$appdir/ollie-update.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Updater-x86_64.AppImage"
    rm -rf "$appdir"
}
build_updater

# Apps that add apps to a running Ollie OS (ollie-apps-updater):
#   build_apps_updater APPIMAGE TITLE NAME OPEN AFTER_INSTALL FILE...
# Each FILE is a path in os/profile/airootfs (a file, or a service's link).
build_apps_updater() {
    local appimage=$1 title=$2 name=$3 open=$4 after=$5 appdir="$out/OllieApps.AppDir" f
    shift 5
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-apps-updater" "$appdir/usr/bin/ollie-apps-updater"
    for f in "$@"; do
        mkdir -p "$(dirname "$appdir/usr/share/ollie-apps/airootfs/$f")"
        cp -a "$os/profile/airootfs/$f" "$appdir/usr/share/ollie-apps/airootfs/$f"
    done
    printf 'TITLE=%s\nNAME=%s\nOPEN=%s\n' "$title" "$name" "$open" >"$appdir/usr/share/ollie-apps/app.conf"
    [[ -n $after ]] && install -m 0755 "$here/$after" "$appdir/usr/share/ollie-apps/after-install"
    # More files made for this one updater (apps_updater_extra AIROOTFS-DIR), if it has some.
    if declare -F apps_updater_extra >/dev/null; then
        apps_updater_extra "$appdir/usr/share/ollie-apps/airootfs"
        unset -f apps_updater_extra
    fi
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: add the apps to this Ollie OS, then open one.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/ollie-apps-updater" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    printf '[Desktop Entry]\nType=Application\nName=%s\nComment=Add %s to this Ollie OS\nExec=ollie-apps-updater\nIcon=ollie-os\nTerminal=false\nCategories=System;\n' \
        "$title" "$name" >"$appdir/ollie-apps-updater.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/$appimage"
    rm -rf "$appdir"
}
stuff_saver_files=(usr/local/bin/ollie-stuff-saver usr/local/bin/ollie-stuff-saver-helper
    usr/share/applications/ollie-stuff-saver.desktop)
build_stuff_saver_updater() {
    build_apps_updater Ollie-OS-Stuff-Saver-Updater-x86_64.AppImage "Stuff Saver Updater" "Stuff Saver" \
        /usr/local/bin/ollie-stuff-saver "" "${stuff_saver_files[@]}"
}
build_stuff_saver_updater
# Ollie OS Storage (asked at the first start: where Ollie OS keeps what is
# saved in it), the Fixer that knows about room and Steam, and Stuff Saver.
build_storage_updater() {
    build_apps_updater Ollie-OS-Storage-Updater-x86_64.AppImage "Ollie OS Storage Updater" \
        "Ollie OS Storage, the new Fixer and Stuff Saver" /usr/local/bin/ollie-storage ollie-storage-updater.after-install \
        usr/local/bin/ollie-storage usr/local/bin/ollie-storage-helper usr/share/applications/ollie-storage.desktop \
        etc/xdg/autostart/ollie-storage.desktop etc/systemd/system/ollie-storage.service \
        etc/systemd/system/multi-user.target.wants/ollie-storage.service \
        usr/local/bin/ollie-fixer usr/local/bin/ollie-fixer-helper usr/share/applications/ollie-fixer.desktop \
        "${stuff_saver_files[@]}"
}
build_storage_updater
# The Install Ollie OS that also installs into a drive or a folder on one,
# keeping everything on it (the drive Ollie OS runs from too).
build_install_updater() {
    build_apps_updater Ollie-OS-Drive-Installer-x86_64.AppImage "Ollie OS Drive Installer" \
        "the new Install Ollie OS" /usr/local/bin/ollie-install-gui "" \
        usr/local/bin/ollie-install-gui usr/local/bin/ollie-install usr/local/bin/ollie-install-folder \
        usr/local/bin/ollie-storage-helper usr/local/lib/ollie/loop-root usr/local/lib/ollie/ollie-loop-root.service \
        usr/local/lib/ollie/copy-boot-files etc/initcpio/install/ollie-loop-root usr/share/applications/ollie-install.desktop
}
build_install_updater
# Discover, the app store, from the Arch servers (not files of Ollie OS's own).
build_discover_updater() {
    local appdir="$out/OllieDiscover.AppDir"
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-discover-updater" "$appdir/usr/bin/ollie-discover-updater"
    printf '#!/bin/sh\n# AppImage entry point: add Discover to Ollie OS.\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/ollie-discover-updater" "$@"\n' >"$appdir/AppRun"
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-discover-updater.desktop" "$appdir/ollie-discover-updater.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Discover-Updater-x86_64.AppImage"
    rm -rf "$appdir"
}
build_discover_updater
# Windows on Ollie OS's start-up menu, and Restart into Windows.
build_windows_updater() {
    local appdir="$out/OllieWindows.AppDir" f
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-windows-updater" "$appdir/usr/bin/ollie-windows-updater"
    for f in usr/local/bin/ollie-windows-boot usr/local/bin/ollie-restart-windows usr/share/applications/ollie-restart-windows.desktop; do
        mkdir -p "$(dirname "$appdir/usr/share/ollie-apps/airootfs/$f")"
        cp -a "$os/profile/airootfs/$f" "$appdir/usr/share/ollie-apps/airootfs/$f"
    done
    printf '#!/bin/sh\n# AppImage entry point: put Windows on Ollie OS'"'"'s start-up menu.\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/ollie-windows-updater" "$@"\n' >"$appdir/AppRun"
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-windows-updater.desktop" "$appdir/ollie-windows-updater.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Windows-Boot-Updater-x86_64.AppImage"
    rm -rf "$appdir"
}
build_windows_updater
# Wallpaper Maker: a background with your name (and the OS called by it), or drawn.
build_wallpaper_updater() {
    build_apps_updater Ollie-OS-Wallpaper-Maker-Updater-x86_64.AppImage "Wallpaper Maker Updater" "Wallpaper Maker" \
        /usr/local/bin/ollie-wallpaper-maker "" \
        usr/local/bin/ollie-wallpaper-maker usr/local/bin/ollie-rename usr/local/share/ollie/wallpaper-maker.qml \
        usr/share/applications/ollie-wallpaper-maker.desktop
}
build_wallpaper_updater
# Download Tracker: how many times each of biobro's release files was downloaded.
build_tracker_updater() {
    build_apps_updater Ollie-OS-Download-Tracker-Updater-x86_64.AppImage "Download Tracker Updater" "Download Tracker" \
        /usr/local/bin/ollie-download-tracker "" \
        usr/local/bin/ollie-download-tracker usr/local/share/ollie/download-tracker.qml \
        usr/share/applications/ollie-download-tracker.desktop
}
build_tracker_updater
# The Game Pack: Steam in Game Mode, Speed Boost, the FPS counter, controllers,
# Minecraft, the start-up animation and sound, Welcome, Ollie OS Settings
# (colours, Screen Time, the Typing Scanner) and Update Ollie OS, which opens
# next to get the packages they use.
game_pack_files() { # game_pack_files: its files, into files=()
    local f air="$os/profile/airootfs"
    for f in usr/local/bin/ollie-{steam,speed-boost,minecraft,startup-sound,os-update,colours,settings,welcome,parent,screen-time,timesup,typing-scanner,scanner-notes,firefox,update-checker,overlay,recovery} \
        usr/local/lib/ollie/{speed-boost-hook,boot-splash,recovery-helper,recovery-cleanup} usr/local/share/ollie/{welcome.qml,Confetti.qml,settings.qml,timesup.qml,updates.qml,recovery.qml,scanner-words.txt} \
        usr/local/share/applications/{steam,firefox}.desktop usr/share/applications/ollie-{minecraft,os-update,welcome,settings,scanner-notes,update-checker,recovery}.desktop \
        usr/share/icons/hicolor/scalable/apps/ollie-minecraft.svg etc/xdg/autostart/ollie-{welcome,startup-sound}.desktop \
        etc/systemd/user/ollie-speed-boost.service etc/systemd/user/ollie-update-checker.{service,timer} etc/systemd/system/ollie-recovery-cleanup.{service,timer} etc/systemd/system/ollie-{screen-time,typing-scanner}.service \
        etc/systemd/system/multi-user.target.wants/ollie-{screen-time,typing-scanner}.service \
        etc/gamemode.ini etc/environment.d/20-ollie-games.conf etc/udev/rules.d/71-ollie-controllers.rules etc/udev/rules.d/72-ollie-typing-scanner.rules \
        etc/plymouth/plymouthd.conf etc/mkinitcpio.conf.d/ollie-splash.conf usr/share/sounds/ollie/startup.ogg; do
        files+=("$f")
    done
    for f in "$air"/usr/share/plymouth/themes/ollie/*; do files+=("${f#"$air/"}"); done
}
build_game_pack_updater() {
    local files=()
    game_pack_files
    # Ollie OS's background in Settings' other colours, when this computer can draw them.
    # (And its checks that each part works: share/ollie-apps/check.)
    apps_updater_extra() {
        install -m 0755 "$here/ollie-game-pack.check" "$1/../check"
        command -v rsvg-convert >/dev/null && bash "$os/art/colour-wallpapers.sh" "$1/usr/share/wallpapers"
        return 0
    }
    build_apps_updater Ollie-OS-Game-Pack-Updater-x86_64.AppImage "Ollie OS Game Pack Updater" \
        "the Game Pack (Game Mode, Speed Boost, FPS counter, Minecraft, Welcome, Settings, Screen Time, Typing Scanner, Firefox password, Recovery Mode)" \
        /usr/local/bin/ollie-os-update ollie-game-pack.after-install "${files[@]}"
}
build_game_pack_updater
# For biobro: publish an Ollie OS update that the Update Checker tells everyone about.
build_publisher() {
    local appdir="$out/OlliePublisher.AppDir"
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-update-publisher" "$appdir/usr/bin/ollie-update-publisher"
    printf '#!/bin/sh\n# AppImage entry point: publish an Ollie OS update.\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/ollie-update-publisher" "$@"\n' >"$appdir/AppRun"
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-update-publisher.desktop" "$appdir/ollie-update-publisher.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Update-Publisher-x86_64.AppImage"
    rm -rf "$appdir"
}
build_publisher
# The Fun Pack: Games (every game in one place; drop in ROMs, ISOs and
# Windows games), Ollie Finder, the Typing Game, Ollie Pet, Couch Co-op,
# Comic Maker, Coding Quest, the App Center (with Sticker Maker, Ollie
# Animator, Sound Board, Space Explorer, Spelling Bee and World Explorer in
# it, to install), the Game Overlay and the secrets. Update Ollie OS opens
# next to get the packages they use (ffmpeg for GIFs and sounds).
fun_apps=(games finder typing pet coop sticker comic paint mouse school animator soundboard codequest space spelling world mathquest appcenter trophies gamehub quickmenu playtime music photobooth tour)
fun_pack_files() { # fun_pack_files: its files, into files=()
    local a f
    for a in "${fun_apps[@]}"; do
        files+=("usr/local/bin/ollie-$a" "usr/local/share/ollie/$a.qml")
        # In the apps menu, or in the App Center's Ollie apps (to install).
        if [[ -f "$os/profile/airootfs/usr/share/applications/ollie-$a.desktop" ]]; then
            files+=("usr/share/applications/ollie-$a.desktop")
        else
            files+=("usr/local/share/ollie/store/ollie-$a.desktop")
        fi
        # Its icon, where it has one of its own.
        for f in "$os"/profile/airootfs/usr/share/icons/hicolor/*/apps/"ollie-$a".{png,svg}; do
            [[ -f $f ]] && files+=("${f#"$os/profile/airootfs/"}")
        done
    done
    files+=(usr/local/bin/ollie-{overlay,welcome,os-update,colours,settings} usr/local/lib/ollie/{games,pads,mouse}.py
        usr/local/share/ollie/{PetBody,pet-desktop,Confetti,welcome,settings}.qml usr/local/share/ollie/world.json
        usr/local/bin/ollie-trophy usr/share/plasma/plasmoids/org.ollieos.funfact/metadata.json
        usr/local/lib/ollie/padd.py usr/local/share/ollie/padsetup.qml etc/modules-load.d/ollie-uinput.conf
        etc/systemd/user/ollie-{padd,playtime}.service etc/systemd/user/default.target.wants/ollie-{padd,playtime}.service
        etc/udev/rules.d/71-ollie-controllers.rules
        usr/local/bin/ollie-seasons usr/local/share/ollie/birthday.qml etc/xdg/autostart/ollie-seasons.desktop
        usr/local/bin/ollie-{easyread,language,parent,timesup,screen-time} usr/local/share/ollie/{timesup.qml,login-background.png,avatar.png}
        usr/share/sddm/themes/breeze/theme.conf.user etc/xdg/autostart/ollie-screensaver.desktop
        usr/local/bin/ollie-screensaver usr/local/share/ollie/screensaver.qml
        etc/xdg/autostart/ollie-school-morning.desktop
        usr/share/plasma/plasmoids/org.ollieos.funfact/contents/ui/{main.qml,facts.js})
}
# Not part of Ollie OS any more: the robot voice (ollie-say, Read aloud),
# and the six apps' old menu entries (they are in the App Center now).
gone_files() { # gone_files DIR: the list, as DIR/../remove
    printf '%s\n' /usr/local/bin/ollie-say /usr/local/bin/ollie-readaloud /usr/share/applications/ollie-readaloud.desktop \
        /usr/share/kglobalaccel/ollie-readaloud.desktop /usr/share/icons/hicolor/{256x256,128x128,64x64,48x48}/apps/ollie-readaloud.png \
        /usr/share/applications/ollie-{sticker,spelling,animator,soundboard,world,space}.desktop >"$1/../remove"
}
build_fun_pack_updater() {
    local files=()
    fun_pack_files
    # The secret Ollie Gold background (and the others), when this computer can draw them.
    apps_updater_extra() {
        gone_files "$1"
        command -v rsvg-convert >/dev/null && bash "$os/art/colour-wallpapers.sh" "$1/usr/share/wallpapers"
        return 0
    }
    build_apps_updater Ollie-OS-Fun-Pack-Updater-x86_64.AppImage "Ollie OS Fun Pack Updater" \
        "the Fun Pack (Games, Finder, Typing Game, Ollie Pet, Couch Co-op, Comic Maker, Coding Quest, the App Center with Sticker Maker, Animator, Sound Board, Space Explorer, Spelling Bee and World Explorer)" \
        /usr/local/bin/ollie-os-update "" "${files[@]}"
}
build_fun_pack_updater
# Ollie OS Latest Updater: everything new in one: the Game Pack and the Fun
# Pack, Recovery Mode, the app icons and the version. Update Ollie OS opens
# next to get the packages they use.
build_latest_updater() {
    local f files=() air="$os/profile/airootfs"
    game_pack_files
    fun_pack_files
    files+=(etc/ollie-version usr/share/applications/ollie-recovery.desktop
        usr/local/bin/ollie-windows-boot etc/systemd/system/ollie-windows-boot.service
        usr/local/lib/ollie/snapshot usr/local/bin/ollie-undo-update usr/share/applications/ollie-undo-update.desktop
        etc/xdg/autostart/ollie-undo-update.desktop usr/local/share/ollie/pacman-hooks/00-ollie-save.hook
        etc/systemd/system/ollie-saved-cleanup.service etc/systemd/system/multi-user.target.wants/ollie-saved-cleanup.service)
    for f in "$air"/usr/share/icons/hicolor/*/apps/ollie-*.png "$air"/usr/share/icons/hicolor/scalable/apps/ollie-*.svg; do files+=("${f#"$air/"}"); done
    mapfile -t files < <(printf '%s\n' "${files[@]}" | awk '!seen[$0]++')
    apps_updater_extra() {
        gone_files "$1"
        install -m 0755 "$here/ollie-latest.check" "$1/../check"
        install -m 0755 "$here/ollie-game-pack.check" "$1/../check-game-pack"
        command -v rsvg-convert >/dev/null && bash "$os/art/colour-wallpapers.sh" "$1/usr/share/wallpapers"
        return 0
    }
    build_apps_updater Ollie-OS-Latest-Updater-x86_64.AppImage "Ollie OS Latest Updater" \
        "everything new in Ollie OS (the Game Pack, all the apps, Recovery Mode, the icons)" \
        /usr/local/bin/ollie-os-update ollie-game-pack.after-install "${files[@]}"
}
build_latest_updater

# The Ollie OS recipe: what os/build.sh needs, from the committed tree.
source_tarball() { # source_tarball OUT.tar.gz
    (cd "$os/.." && git archive --format=tar.gz -o "$1" HEAD go.mod cmd internal packaging LICENSE THIRD-PARTY-NOTICES.md os/build.sh os/build-from-arch-iso.sh os/build-drive.sh os/build-drive-files.sh os/drive-common.sh os/secureboot-iso.sh os/ollie-write os/art os/profile)
}

# The Builder: builds the ISO in an Arch Linux container from the recipe it
# carries, then hands over to USB Maker (or, on a Mac, Mac Setup).
# carry_tools KIT TOOL...: this computer's TOOLs and their libraries into
# KIT (bin/ the ones to run, libexec/ and lib/), for computers without them.
carry_tools() {
    local kit=$1 b lib carried=()
    shift
    install -d "$kit/bin" "$kit/libexec" "$kit/lib"
    for b in "$@"; do
        install -m 0755 "$(command -v "$b")" "$kit/libexec/$b"
        carried+=("$(command -v "$b")")
        while read -r lib; do
            case "$(basename "$lib")" in libc.so* | libm.so* | ld-linux* | libpthread* | libdl.so* | librt.so*) continue ;; esac
            cp -nL "$lib" "$kit/lib/"
            carried+=("$lib")
        done < <(ldd "$(command -v "$b")" | awk '$3 ~ /^\// {print $3}')
        printf '#!/bin/sh\nd="$(dirname "$(readlink -f "$0")")"\nLD_LIBRARY_PATH="$d/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$d/../libexec/%s" "$@"\n' "$b" >"$kit/bin/$b"
        chmod 0755 "$kit/bin/$b"
    done
    carry_licences "$kit" "${carried[@]}"
}
# The licences of the programs and libraries carried (all free software, many
# under the GPL, which asks for its licence and the source code to go with
# them): each package's licence files in KIT/licenses, and in KIT/SOURCES.txt
# which package and version each file is from and where its source code is.
carry_licences() { # carry_licences KIT ORIGINAL-FILE...
    local kit=$1 f real pkg ver src
    shift
    install -d "$kit/licenses"
    for f in /usr/share/common-licenses/{GPL-2,GPL-3,LGPL-2.1,LGPL-3} /usr/share/licenses/common/{GPL2,GPL3,LGPL2.1,LGPL3}/license.txt; do
        [[ -f $f ]] && install -m 0644 "$f" "$kit/licenses/$(basename "$(dirname "$f")" | sed 's/^common-licenses$//')$(basename "$f")"
    done
    {
        echo "Free software carried by this Ollie OS program, from the computer it was built on."
        echo "Each one's licence is in licenses/. Its source code: where each line says; or ask at"
        echo "https://github.com/robertpjenkins-bot/Ollie-OS/issues and you will be sent it (this"
        echo "offer is good for 3 years from when this program was made: $(date +%Y-%m-%d))."
        echo "This program itself also contains the AppImage runtime (MIT License,"
        echo "https://github.com/AppImage/type2-runtime)."
        echo
        for f in "$@"; do
            real="$(readlink -f "$f")"
            if command -v dpkg >/dev/null && pkg="$(dpkg -S "$real" 2>/dev/null || dpkg -S "${real#/usr}" 2>/dev/null)" && pkg="$(head -n1 <<<"$pkg" | cut -d: -f1)" && [[ -n $pkg ]]; then
                ver="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)"
                src="$(dpkg-query -W -f='${source:Package}' "$pkg" 2>/dev/null)"
                [[ -f /usr/share/doc/$pkg/copyright ]] && install -D -m 0644 "/usr/share/doc/$pkg/copyright" "$kit/licenses/$pkg/copyright"
                echo "$(basename "$f"): $pkg $ver; source: https://sources.debian.org/src/${src:-$pkg}/ (or apt-get source ${src:-$pkg}=$ver)"
            elif command -v pacman >/dev/null && pkg="$(pacman -Qqo "$real" 2>/dev/null)" && [[ -n $pkg ]]; then
                ver="$(pacman -Q "$pkg" | cut -d' ' -f2)"
                [[ -d /usr/share/licenses/$pkg ]] && cp -r "/usr/share/licenses/$pkg" "$kit/licenses/"
                echo "$(basename "$f"): $pkg $ver; source: https://gitlab.archlinux.org/archlinux/packaging/packages/$pkg"
            else
                echo "$(basename "$f"): (its package is not known on the build computer; ask for the source as above)"
            fi
        done | sort -u
    } >"$kit/SOURCES.txt"
}
build_builder() {
    local appdir="$out/OllieBuilder.AppDir" mac="$out/Ollie-OS-Builder-Mac"
    rm -rf "$appdir" "$mac"
    install -D -m 0755 "$here/ollie-build" "$appdir/usr/bin/ollie-build"
    # To open the Arch Linux ISO and the system inside it.
    carry_tools "$appdir/usr/lib/ollie-build" xorriso unsquashfs
    install -D -m 0755 "$here/ollie-usb" "$appdir/usr/bin/ollie-usb"
    install -d "$appdir/usr/share/ollie-build"
    source_tarball "$appdir/usr/share/ollie-build/ollie-os-source.tar.gz"
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: build Ollie OS, then hand over to USB Maker.
HERE="$(dirname "$(readlink -f "$0")")"
export OLLIE_USB_MAKER="$HERE/usr/bin/ollie-usb"
exec "$HERE/usr/bin/ollie-build" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-build.desktop" "$appdir/ollie-build.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Builder-x86_64.AppImage"
    rm -rf "$appdir"
    # The Installer is the same: it makes Ollie OS from the Arch Linux ISO, then USB Maker.
    cp -f "$out/Ollie-OS-Builder-x86_64.AppImage" "$out/Ollie-OS-Installer-x86_64.AppImage"
    # For a Mac: a folder with the Builder, its recipe and Mac Setup, zipped.
    mkdir -p "$mac"
    install -m 0755 "$here/ollie-build" "$mac/Ollie-OS-Builder.command"
    install -m 0755 "$here/mac/Ollie-OS-Mac-Setup.command" "$mac/Ollie-OS-Mac-Setup.command"
    source_tarball "$mac/ollie-os-source.tar.gz"
    rm -f "$out/Ollie-OS-Builder-Mac.zip"
    (cd "$out" && zip -q -r -X Ollie-OS-Builder-Mac.zip "$(basename "$mac")")
    # The same as a .dmg (opens on a Mac like a drive), where xorriso is here.
    if command -v xorriso >/dev/null; then
        rm -f "$out/Ollie-OS-Builder-Mac.dmg"
        xorriso -as mkisofs -quiet -V "Ollie OS Builder" -R -J -hfsplus -o "$out/Ollie-OS-Builder-Mac.dmg" "$mac"
        cp -f "$out/Ollie-OS-Builder-Mac.dmg" "$out/Ollie-OS-Installer-Mac.dmg"
    fi
    rm -rf "$mac"
}
build_builder

# The Drive Writer, for SteamOS or any Linux: makes Ollie OS from Arch Linux
# right on a drive, with the recipe it carries (no GitHub, no ISO).
build_drive_writer() {
    local appdir="$out/OllieDriveWriter.AppDir"
    rm -rf "$appdir"
    install -D -m 0755 "$here/ollie-install-drive" "$appdir/usr/bin/ollie-install-drive"
    install -d "$appdir/usr/share/ollie-build"
    source_tarball "$appdir/usr/share/ollie-build/ollie-os-source.tar.gz"
    cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage entry point: make Ollie OS on a drive.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/ollie-install-drive" "$@"
APPRUN
    chmod 0755 "$appdir/AppRun"
    install -m 0644 "$here/ollie-drive-writer.desktop" "$appdir/ollie-drive-writer.desktop"
    install -D -m 0644 "$os/art/ollie-os.svg" "$appdir/ollie-os.svg"
    ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Ollie-OS-Drive-Writer-x86_64.AppImage"
    rm -rf "$appdir"
}
build_drive_writer
