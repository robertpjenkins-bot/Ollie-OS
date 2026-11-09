#!/bin/bash
# Build the Ollie OS ISO.
#
# Runs as root inside an Arch Linux container (see .github/workflows/os-iso.yml):
#
#   docker run --rm --privileged -v "$PWD:/src" -w /src archlinux:latest bash os/build.sh
#
# The ISO and its checksum land in os/out/.
#
# With OLLIE_BUILD_DISK=/dev/... (the Ollie OS Drive Writer) there is no ISO:
# Ollie OS is installed straight onto that drive, which is erased, by
# os/build-drive.sh, and the check of it lands in os/out/Ollie-OS-check.txt.
# With OLLIE_BUILD_FILES=FOLDER and OLLIE_BUILD_ESP=FOLDER (the Drive Writer
# with no admin rights: a drive's two parts, mounted) by os/build-drive-files.sh.
#
# The profile starts from archiso's own "releng" profile for the boot loader
# configuration, which tracks the installed archiso version, and layers
# os/profile on top for everything that makes the system Ollie OS.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
os="$repo/os"
out="$os/out"
work=/tmp/ollie-work
profile=/tmp/ollie-profile
localrepo=/tmp/ollie-repo

step() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }
# Package lists: one name per line, # starts a comment.
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"; }

step "Preparing the build container"
# The container image strips man pages and translations from everything it
# installs; the ISO must not inherit that.
sed -i '/^NoExtract/d' /etc/pacman.conf
# Steam, Wine and the 32-bit drivers live in multilib. Uncomment it, or add it
# if this pacman.conf has no multilib section at all.
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
fi
# OLLIE_ROOTLESS=1 (see below): pacman's download sandbox, its switch to
# another user for downloading, and its free space check cannot work as
# "root" of a user namespace. They are off for the build only: the ISO's
# pacman.conf gets them back.
if [[ -n "${OLLIE_ROOTLESS:-}" ]]; then
    sed -i -E 's/^(DownloadUser|CheckSpace)/#ollie-build-only: \1/' /etc/pacman.conf
    grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
fi
pacman-key --init >/dev/null
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm
# noto-fonts: rsvg-convert draws the "Ollie OS" text on the wallpaper with it;
# without any font installed the letters come out as boxes.
pacman -S --noconfirm --needed archiso base-devel git go librsvg noto-fonts sudo sbsigntools
# Onto a drive: Ollie OS's installer partitions, formats and makes it start
# (and checks the time zone it is given), and build-drive.sh checks it.
if [[ -n "${OLLIE_BUILD_DISK:-}" ]]; then
    pacman -S --noconfirm --needed btrfs-progs diffutils dosfstools gptfdisk parted syslinux tzdata
fi
# Onto a drive with no admin rights (OLLIE_BUILD_FILES, see build-drive-files.sh):
# only files are written, as you; the checks compare files.
if [[ -n "${OLLIE_BUILD_FILES:-}" ]]; then
    pacman -S --noconfirm --needed diffutils zstd
fi

# OLLIE_ROOTLESS=1: in an Arch Linux started by a normal user, with no
# password (the Ollie OS Builder app: a user namespace of its own, the way
# Annie OS Maker builds, or rootless Podman). Its "root" may mount proc,
# tmpfs and binds but not a fresh devtmpfs, sysfs or devpts, so the chroots
# pacstrap and arch-chroot set up borrow the build's own /dev and /sys (with
# everything mounted below them) instead. Those borrowed mounts cannot
# always be unmounted one by one afterwards, so each run of the two gets a
# mount namespace of its own: whatever it mounted is gone when it exits, and
# the build's later clean-up never reaches into /dev or /sys.
if [[ -n "${OLLIE_ROOTLESS:-}" ]]; then
    for tool in pacstrap arch-chroot; do
        sed -i -E \
            -e 's#chroot_add_mount udev "\$1/dev" -t devtmpfs[^&]*#chroot_add_mount /dev "$1/dev" --rbind #' \
            -e 's#chroot_add_mount sys "\$1/sys" -t sysfs[^&]*#chroot_add_mount /sys "$1/sys" --rbind #' \
            -e '/chroot_add_mount devpts "\$1\/dev\/pts"/d' \
            -e 's#umount "\$\{CHROOT_ACTIVE_MOUNTS\[@\]\}"#umount --recursive --lazy "${CHROOT_ACTIVE_MOUNTS[@]}" 2>/dev/null#' \
            "/usr/bin/$tool"
        grep -q 'chroot_add_mount /dev "\$1/dev" --rbind' "/usr/bin/$tool" ||
            echo "note: could not adapt $tool for a rootless build; it may fail" >&2
        mv "/usr/bin/$tool" "/usr/bin/$tool.rootless"
        printf '#!/bin/sh\nexec unshare --mount --propagation private /usr/bin/%s.rootless "$@"\n' "$tool" >"/usr/bin/$tool"
        chmod 0755 "/usr/bin/$tool"
    done
fi

git config --global --add safe.directory "$repo"
version="$(git -C "$repo" describe --tags --always --dirty 2>/dev/null || echo dev)"

step "Assembling the profile"
rm -rf "$profile" "$work"
cp -a /usr/share/archiso/configs/releng "$profile"
rm -rf /tmp/releng-airootfs
mv "$profile/airootfs" /tmp/releng-airootfs
mkdir -p "$profile/airootfs"
# Ollie OS ships its own live initramfs hooks (os/profile/airootfs/etc/
# mkinitcpio.conf.d); of releng's root filesystem it only keeps a kernel
# preset, in archiso versions that still provide one.
if [[ -f /tmp/releng-airootfs/etc/mkinitcpio.d/linux.preset ]]; then
    install -D -m 0644 /tmp/releng-airootfs/etc/mkinitcpio.d/linux.preset \
        "$profile/airootfs/etc/mkinitcpio.d/linux.preset"
fi
rm -rf /tmp/releng-airootfs
cp -a "$os/profile/airootfs/." "$profile/airootfs/"

# Name the ISO and boot menus Ollie OS.
sed -i \
    -e 's/^iso_name=.*/iso_name="ollie-os"/' \
    -e 's/^iso_label="ARCH_/iso_label="OLLIE_/' \
    -e 's|^iso_publisher=.*|iso_publisher="Ollie OS"|' \
    -e 's|^iso_application=.*|iso_application="Ollie OS live and installer"|' \
    "$profile/profiledef.sh"
# releng's permission list names files that Ollie OS leaves out.
sed -i '/^file_permissions=(/,/^)/d' "$profile/profiledef.sh"
cat >>"$profile/profiledef.sh" <<'EOF'
file_permissions=(
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-wheel"]="0:0:440"
  ["/usr/local/bin/oliver"]="0:0:755"
  ["/usr/local/bin/ollie-install"]="0:0:755"
  ["/usr/local/bin/ollie-write"]="0:0:755"
  ["/usr/local/bin/ollie-add-to-bar"]="0:0:755"
  ["/usr/local/bin/ollie-live-setup"]="0:0:755"
  ["/usr/local/bin/ollie-dc"]="0:0:755"
  ["/usr/local/bin/ollie-drivers"]="0:0:755"
  ["/usr/local/bin/ollie-first-setup"]="0:0:755"
  ["/usr/local/bin/ollie-set-account"]="0:0:755"
  ["/usr/local/bin/ollie-get-proton-ge"]="0:0:755"
  ["/usr/local/bin/ollie-fixer"]="0:0:755"
  ["/usr/local/bin/ollie-fixer-helper"]="0:0:755"
  ["/usr/local/bin/ollie-selftest-fixer"]="0:0:755"
  ["/usr/local/bin/ollie-selftest-install"]="0:0:755"
  ["/usr/local/bin/ollie-selftest-folder"]="0:0:755"
  ["/usr/local/bin/ollie-install-gui"]="0:0:755"
  ["/usr/local/bin/ollie-stuff-saver"]="0:0:755"
  ["/usr/local/bin/ollie-stuff-saver-helper"]="0:0:755"
  ["/usr/local/bin/ollie-storage"]="0:0:755"
  ["/usr/local/bin/ollie-storage-helper"]="0:0:755"
  ["/usr/local/bin/ollie-install-folder"]="0:0:755"
  ["/usr/local/lib/ollie/loop-root"]="0:0:755"
  ["/usr/local/lib/ollie/copy-boot-files"]="0:0:755"
  ["/usr/local/bin/ollie-windows-boot"]="0:0:755"
  ["/usr/local/bin/ollie-windows-setup"]="0:0:755"
  ["/usr/local/bin/ollie-windows-install"]="0:0:755"
  ["/usr/local/lib/ollie/get-windows.py"]="0:0:755"
  ["/usr/local/lib/ollie/windows-plan"]="0:0:755"
  ["/usr/local/bin/ollie-wallpaper-maker"]="0:0:755"
  ["/usr/local/bin/ollie-rename"]="0:0:755"
  ["/usr/local/bin/ollie-download-tracker"]="0:0:755"
  ["/usr/local/bin/ollie-restart-windows"]="0:0:755"
  ["/usr/local/lib/ollie/unpack-root"]="0:0:755"
  ["/usr/local/lib/ollie/drive-finish"]="0:0:755"
  ["/usr/local/bin/ollie-steam"]="0:0:755"
  ["/usr/local/bin/ollie-speed-boost"]="0:0:755"
  ["/usr/local/lib/ollie/speed-boost-hook"]="0:0:755"
  ["/usr/local/lib/ollie/boot-splash"]="0:0:755"
  ["/usr/local/bin/ollie-minecraft"]="0:0:755"
  ["/usr/local/bin/ollie-startup-sound"]="0:0:755"
  ["/usr/local/bin/ollie-os-update"]="0:0:755"
  ["/usr/local/bin/ollie-colours"]="0:0:755"
  ["/usr/local/bin/ollie-settings"]="0:0:755"
  ["/usr/local/bin/ollie-welcome"]="0:0:755"
  ["/usr/local/bin/ollie-parent"]="0:0:755"
  ["/usr/local/bin/ollie-screen-time"]="0:0:755"
  ["/usr/local/bin/ollie-timesup"]="0:0:755"
  ["/usr/local/bin/ollie-typing-scanner"]="0:0:755"
  ["/usr/local/bin/ollie-scanner-notes"]="0:0:755"
  ["/usr/local/bin/ollie-firefox"]="0:0:755"
  ["/usr/local/bin/ollie-update-checker"]="0:0:755"
  ["/usr/local/bin/ollie-games"]="0:0:755"
  ["/usr/local/lib/ollie/games.py"]="0:0:755"
  ["/usr/local/bin/ollie-finder"]="0:0:755"
  ["/usr/local/bin/ollie-typing"]="0:0:755"
  ["/usr/local/bin/ollie-pet"]="0:0:755"
  ["/usr/local/bin/ollie-overlay"]="0:0:755"
  ["/usr/local/bin/ollie-coop"]="0:0:755"
  ["/usr/local/bin/ollie-sticker"]="0:0:755"
  ["/usr/local/bin/ollie-comic"]="0:0:755"
  ["/usr/local/bin/ollie-paint"]="0:0:755"
  ["/usr/local/bin/ollie-mouse"]="0:0:755"
  ["/usr/local/bin/ollie-school"]="0:0:755"
  ["/usr/local/bin/ollie-undo-update"]="0:0:755"
  ["/usr/local/lib/ollie/snapshot"]="0:0:755"
  ["/usr/local/lib/ollie/secureboot"]="0:0:755"
  ["/usr/local/lib/ollie/mouse.py"]="0:0:755"
  ["/usr/local/bin/ollie-animator"]="0:0:755"
  ["/usr/local/bin/ollie-soundboard"]="0:0:755"
  ["/usr/local/bin/ollie-codequest"]="0:0:755"
  ["/usr/local/bin/ollie-space"]="0:0:755"
  ["/usr/local/bin/ollie-spelling"]="0:0:755"
  ["/usr/local/bin/ollie-world"]="0:0:755"
  ["/usr/local/lib/ollie/pads.py"]="0:0:755"
  ["/usr/local/bin/ollie-recovery"]="0:0:755"
  ["/usr/local/lib/ollie/recovery-helper"]="0:0:755"
  ["/usr/local/lib/ollie/recovery-cleanup"]="0:0:755"
  ["/usr/local/bin/ollie-appcenter"]="0:0:755"
  ["/usr/local/bin/ollie-mathquest"]="0:0:755"
  ["/usr/local/bin/ollie-trophies"]="0:0:755"
  ["/usr/local/bin/ollie-trophy"]="0:0:755"
  ["/usr/local/bin/ollie-gamehub"]="0:0:755"
  ["/usr/local/bin/ollie-quickmenu"]="0:0:755"
  ["/usr/local/bin/ollie-playtime"]="0:0:755"
  ["/usr/local/lib/ollie/padd.py"]="0:0:755"
  ["/usr/local/bin/ollie-music"]="0:0:755"
  ["/usr/local/bin/ollie-photobooth"]="0:0:755"
  ["/usr/local/bin/ollie-seasons"]="0:0:755"
  ["/usr/local/bin/ollie-tour"]="0:0:755"
  ["/usr/local/bin/ollie-screensaver"]="0:0:755"
  ["/usr/local/bin/ollie-easyread"]="0:0:755"
  ["/usr/local/bin/ollie-language"]="0:0:755"
)
EOF
find "$profile/efiboot" "$profile/syslinux" "$profile/grub" -type f -name '*speech*' -delete 2>/dev/null || true
# The live USB starts without the start-up animation (Plymouth is there for
# installed Ollie OS, whose start-up image has it): plymouth.enable=0.
grep -rlZ 'archisobasedir=' "$profile/efiboot" "$profile/syslinux" "$profile/grub" 2>/dev/null |
    xargs -0r sed -i -E '/plymouth\.enable=/!s/(archisobasedir=[^ ]*)/\1 plymouth.enable=0/'
grep -rlZ 'Arch Linux' "$profile/efiboot" "$profile/syslinux" "$profile/grub" 2>/dev/null |
    xargs -0r sed -i -e 's/Arch Linux install medium/Ollie OS/g' -e 's/Arch Linux/Ollie OS/g'

step "Building Oliver $version"
(cd "$repo" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=$version" \
    -o "$profile/airootfs/usr/local/bin/oliver" ./cmd/oliver)
install -D -m 0644 "$repo/packaging/oliver.desktop" "$profile/airootfs/usr/share/applications/oliver.desktop"
# Other people's work in Ollie OS, and its licences (THIRD-PARTY-NOTICES.md).
for f in THIRD-PARTY-NOTICES.md LICENSE; do
    [[ -f $repo/$f ]] && install -D -m 0644 "$repo/$f" "$profile/airootfs/usr/share/doc/ollie-os/$f"
done
install -D -m 0644 "$repo/packaging/oliver.svg" "$profile/airootfs/usr/share/icons/hicolor/scalable/apps/oliver.svg"
install -D -m 0755 "$os/ollie-write" "$profile/airootfs/usr/local/bin/ollie-write"

step "Drawing the logo and wallpaper"
for icon in ollie-os ollie-dc ollie-drivers; do
    install -D -m 0644 "$os/art/$icon.svg" "$profile/airootfs/usr/share/icons/hicolor/scalable/apps/$icon.svg"
done
images="$profile/airootfs/usr/share/wallpapers/OllieOS/contents/images"
mkdir -p "$images"
for size in 1280x720 1920x1080 2560x1440 3840x2160; do
    rsvg-convert -w "${size%x*}" -h "${size#*x}" -o "$images/$size.png" "$os/art/wallpaper.svg"
done
# The same background in Ollie OS Settings' other colours.
bash "$os/art/colour-wallpapers.sh" "$profile/airootfs/usr/share/wallpapers"
# The BIOS boot menu background; syslinux wants exactly 640x480.
rsvg-convert -w 640 -h 480 -o "$profile/syslinux/splash.png" "$os/art/splash.svg"

step "Building AUR packages: $(list "$os/profile/aur-packages.txt" | tr '\n' ' ')"
id builder &>/dev/null || useradd -m builder
# No terminal of its own for sudo (its use_pty): with no admin rights
# (OLLIE_ROOTLESS) it may not make one ("unable to allocate pty").
printf 'builder ALL=(ALL) NOPASSWD: ALL\nDefaults !use_pty\n' >/etc/sudoers.d/builder
rm -rf "$localrepo"
install -d -o builder "$localrepo"
while read -r pkg; do
    rm -rf "/home/builder/$pkg"
    sudo -u builder git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "/home/builder/$pkg"
    (cd "/home/builder/$pkg" && sudo -u builder PKGEXT=.pkg.tar.zst PKGDEST="$localrepo" \
        makepkg --syncdeps --noconfirm --needed)
    rm -rf "/home/builder/$pkg"
done < <(list "$os/profile/aur-packages.txt")
repo-add "$localrepo/ollie-local.db.tar.gz" "$localrepo"/*.pkg.tar.zst

step "Writing package lists and pacman configuration"
# Firmware for consumer hardware only. Arch splits linux-firmware into parts;
# the NVIDIA part (large, and for cards the Steam Machine and Deck do not
# have), Qualcomm phone and laptop chips (qcom) and the server network cards
# are left out. Without the split, the
# whole package.
firmware=(linux-firmware)
if pacman -Si linux-firmware-amdgpu &>/dev/null; then
    firmware=()
    for part in amdgpu radeon intel realtek mediatek atheros broadcom cirrus other; do
        pacman -Si "linux-firmware-$part" &>/dev/null && firmware+=("linux-firmware-$part")
    done
fi
echo "firmware: ${firmware[*]}"
{
    printf '%s\n' "${firmware[@]}"
    list "$os/profile/packages.x86_64"
    while read -r pkg; do
        if pacman -Si "$pkg" &>/dev/null; then
            echo "$pkg"
        else
            echo "note: optional package $pkg is not in the repositories, leaving it out" >&2
        fi
    done < <(list "$os/profile/packages-optional.x86_64")
    list "$os/profile/aur-packages.txt"
} | sort -u >"$profile/packages.x86_64"

# The installed system gets the container's pacman setup (with multilib) and
# its working mirror list; the build additionally sees the local AUR repo.
install -D -m 0644 /etc/pacman.conf "$profile/airootfs/etc/pacman.conf"
sed -i -e '/^DisableSandbox$/d' -e 's/^#ollie-build-only: //' "$profile/airootfs/etc/pacman.conf"
install -D -m 0644 /etc/pacman.d/mirrorlist "$profile/airootfs/etc/pacman.d/mirrorlist"
cp /etc/pacman.conf "$profile/pacman.conf"
# Of the cursor package's 24 colour sets, only the one Ollie OS uses goes on
# the ISO (the rest is over 300 MB). Later patterns win in pacman.
sed -i '/^\[options\]/a NoExtract = usr/share/icons/Bibata-* !usr/share/icons/Bibata-Modern-Ice/*' \
    "$profile/pacman.conf" "$profile/airootfs/etc/pacman.conf"
cat >>"$profile/pacman.conf" <<EOF

[ollie-local]
SigLevel = Optional TrustAll
Server = file://$localrepo
EOF

# Secure Boot: this Builder's own key (made the first time, then kept in
# os/out/secureboot), so a computer that learned it once starts every Ollie OS
# made here with Secure Boot on. See secureboot-iso.sh.
mkdir -p "$out"
export OLLIE_SB_KEYDIR="${OLLIE_SB_KEYDIR:-$out/secureboot}"
bash "$os/profile/airootfs/usr/local/lib/ollie/secureboot" key "$OLLIE_SB_KEYDIR" ||
    { echo "(No Secure Boot key: Ollie OS starts with Secure Boot off.)"; unset OLLIE_SB_KEYDIR; }

if [[ -n "${OLLIE_BUILD_DISK:-}" ]]; then
    step "Installing Ollie OS onto $OLLIE_BUILD_DISK"
    mkdir -p "$out"
    exec bash "$os/build-drive.sh" "$profile" "$OLLIE_BUILD_DISK" "$out/Ollie-OS-check.txt"
fi
if [[ -n "${OLLIE_BUILD_FILES:-}" ]]; then
    step "Putting Ollie OS on the drive"
    mkdir -p "$out"
    exec bash "$os/build-drive-files.sh" "$profile" "$OLLIE_BUILD_FILES" "${OLLIE_BUILD_ESP:?}" "$out/Ollie-OS-check.txt"
fi

step "Building the ISO"
mkdir -p "$out"
rm -f "$out"/ollie-os-*.iso "$out"/ollie-os-*.iso.sha256
mkarchiso -v -w "$work" -o "$out" "$profile"
rm -rf "$work"

cd "$out"
for iso in ollie-os-*.iso; do
    if [[ -n "${OLLIE_SB_KEYDIR:-}" ]]; then
        step "Making it start with Secure Boot on"
        bash "$os/secureboot-iso.sh" "$iso" "$OLLIE_SB_KEYDIR" ||
            echo "(Secure Boot could not be added: this ISO starts with Secure Boot off.)"
    fi
    sha256sum "$iso" >"$iso.sha256"
done
step "Done"
ls -lh "$out"
