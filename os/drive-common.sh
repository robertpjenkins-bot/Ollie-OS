# What installing Ollie OS straight onto a drive needs, either way: with admin
# rights (build-drive.sh) or without (build-drive-files.sh). Sourced by them.
#   fill_target TARGET   Ollie OS's own files, then Arch Linux's packages
#   check NAME TEST FIX  one line of the report; the checks and fixes below
# The checks use: t (the installed system's folder), profile, report,
# in_target (runs a command in t), reinstall (puts packages back in t).

step() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"; }

# --- Ollie OS's system --------------------------------------------------------------------
# Called as "fill_target ... || die", which set -e does not reach: every step
# checks. OLLIE_PROFILE: the profile.
fill_target() { # fill_target TARGET
    local target=$1 path log=/tmp/ollie-packages.log
    local -A file_permissions=()
    local -a perm pkgs
    # Ollie OS's own files first, the way mkarchiso puts them in the ISO, so
    # the packages' set-up (the start-up image, above all) already sees them.
    cp -af --no-preserve=ownership,mode -- "$OLLIE_PROFILE/airootfs/." "$target/" || return 1
    eval "$(sed -n '/^file_permissions=(/,/^)/p' "$OLLIE_PROFILE/profiledef.sh")"
    for path in "${!file_permissions[@]}"; do
        [[ -e "$target$path" ]] || continue
        IFS=: read -r -a perm <<<"${file_permissions[$path]}"
        if [[ $path == */ ]]; then
            chown -fhR -- "${perm[0]}:${perm[1]}" "$target$path" && chmod -fR -- "${perm[2]}" "$target$path"
        else
            chown -fh -- "${perm[0]}:${perm[1]}" "$target$path" && chmod -f -- "${perm[2]}" "$target$path"
        fi || return 1
    done
    # Arch Linux's packages. Without pacstrap's -c they are downloaded into
    # the drive's own package cache, not onto this computer. Shown as
    # downloading 5-45 and installing 45-75 of the whole install; all of
    # pacman's words go to the log.
    mapfile -t pkgs < <(list "$OLLIE_PROFILE/packages.x86_64")
    pacstrap -C "$OLLIE_PROFILE/pacman.conf" -G -M "$target" "${pkgs[@]}" 2>&1 | tee "$log" | awk '
        /^Packages \([0-9]+\)/ { total = substr($2, 2) + 0 }
        / downloading\.\.\.$/ { if (total) p = 5 + int(++got * 40 / total); text = "Downloading Arch Linux packages onto the drive" }
        /^\( *[0-9]+\/ *[0-9]+\) installing / { split($0, a, /[()\/]/); p = 45 + int(a[2] * 30 / a[3]); text = "Installing Ollie OS programs" }
        p && p != last { if (p > 75) p = 75; print "PROGRESS " p " " text; fflush(); last = p }'
    if ((PIPESTATUS[0] != 0)); then
        tail -n 25 "$log"
        return 1
    fi
}

# --- The report -----------------------------------------------------------------------------
problems=0
report_start() { # report_start DISK
    {
        echo "Ollie OS Drive Writer: the check of $1 ($(lsblk -dno SIZE,MODEL "$1" 2>/dev/null | xargs)), $(date '+%Y-%m-%d %H:%M')"
        echo
    } >"$report"
}
# check NAME TEST FIX: TEST (a function, run apart: what it sets is not kept)
# passes, or FIX runs and TEST must pass after it. What was wrong is noted.
check() {
    local name=$1 test=$2 fix=$3 why was
    if why="$($test 2>&1)"; then
        printf '  OK       %s\n' "$name" | tee -a "$report"
    elif $fix >/dev/null 2>&1 && was=$why && why="$($test 2>&1)"; then
        printf '  FIXED    %s (%s)\n' "$name" "$(head -c 200 <<<"$was" | tr -s '\n ' '  ' | sed 's/ $//')" | tee -a "$report"
    else
        printf '  PROBLEM  %s%s\n' "$name" "${why:+: $(head -c 300 <<<"$why" | tr '\n' ' ')}" | tee -a "$report"
        problems=$((problems + 1))
    fi
}
report_end() {
    echo >>"$report"
    if ((problems == 0)); then
        echo "Result: Ollie OS on this drive is ready to start." | tee -a "$report"
        return 0
    fi
    echo "Result: $problems problem(s) left, above. Running the Drive Writer again usually fixes them." | tee -a "$report"
    return 3
}

# --- The checks both ways share ----------------------------------------------------------------
# Every program's files are there (not damaged or missing). (The cursor
# colour sets Ollie OS leaves out on purpose do not count.)
broken_pkgs() { in_target pacman -Qkq 2>/dev/null | grep -v ' /usr/share/icons/Bibata-' | awk '{print $1}' | sort -u; }
test_files() {
    local broken
    broken="$(broken_pkgs)"
    [[ -z $broken ]] || { echo "missing files in" $broken; return 1; }
}
fix_files() {
    local -a broken
    mapfile -t broken < <(broken_pkgs)
    reinstall "${broken[@]}"
}

# Steam: the program, its 32-bit graphics drivers (Steam itself is 32-bit),
# the multilib packages it updates from, and the language setting it needs
# to start.
steam_pkgs=(steam lib32-mesa lib32-vulkan-radeon lib32-vulkan-intel lib32-vulkan-icd-loader lib32-pipewire ttf-liberation)
missing_steam() { local p; for p in "${steam_pkgs[@]}"; do in_target pacman -Q "$p" >/dev/null 2>&1 || echo "$p"; done; }
test_steam() {
    local missing
    missing="$(missing_steam)"
    [[ -z $missing ]] || { echo "not installed:" $missing; return 1; }
    [[ -f "$t/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz" && -e "$t/usr/lib32/libGL.so.1" ]] || { echo "Steam's files are incomplete"; return 1; }
}
fix_steam() {
    local -a missing
    mapfile -t missing < <(missing_steam)
    reinstall "${missing[@]:-steam}"
}
test_multilib() { grep -q '^\[multilib\]' "$t/etc/pacman.conf"; }
fix_multilib() { printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$t/etc/pacman.conf"; }
test_locale() { in_target locale -a 2>/dev/null | grep -qix 'en_US.utf8'; }
fix_locale() {
    sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$t/etc/locale.gen"
    echo LANG=en_US.UTF-8 >"$t/etc/locale.conf"
    in_target locale-gen
}

# Starting: the kernel, and a start-up image for it with every computer's
# drivers (USB drives, NVMe, btrfs) and none of the live USB's; with
# OLLIE_NEED_HOOKS, those start-up hooks too.
test_image() {
    local kver files m h
    kver="$(ls "$t/usr/lib/modules" 2>/dev/null | head -n 1)"
    [[ -n $kver && -s "$t/boot/vmlinuz-linux" && -s "$t/boot/initramfs-linux.img" ]] || { echo "the start-up files are missing"; return 1; }
    cmp -s "$t/boot/vmlinuz-linux" "$t/usr/lib/modules/$kver/vmlinuz" || { echo "the kernel does not match its drivers"; return 1; }
    files="$(in_target lsinitcpio /boot/initramfs-linux.img 2>/dev/null)"
    grep -q 'hooks/archiso' <<<"$files" && { echo "the start-up image is the live USB's"; return 1; }
    for m in uas usb-storage xhci-pci nvme btrfs; do
        grep -q "/$m\.ko" <<<"$files" || grep -q "/$m\.ko\$" "$t/usr/lib/modules/$kver/modules.builtin" ||
            { echo "the start-up image lacks $m"; return 1; }
    done
    for h in ${OLLIE_NEED_HOOKS:-}; do
        grep -q "$h" <<<"$files" || { echo "the start-up image lacks $h"; return 1; }
    done
}
fix_image() {
    local kver
    kver="$(ls "$t/usr/lib/modules" | head -n 1)"
    rm -f "$t/etc/mkinitcpio.conf.d/archiso.conf"
    cp -f "$t/usr/lib/modules/$kver/vmlinuz" "$t/boot/vmlinuz-linux"
    in_target mkinitcpio -P
}
kernel_version() { ls "$t/usr/lib/modules" 2>/dev/null | head -n 1; }

# (Service links point at /usr/lib/... inside Ollie OS: -L, as this Arch
# Linux's own /usr is not Ollie OS's.)
test_first_start() {
    grep -q '^ollie:' "$t/etc/passwd" || { echo "the account is missing"; return 1; }
    [[ -s "$t/etc/xdg/autostart/ollie-first-setup.desktop" ]] || { echo "the first-start setup is missing"; return 1; }
    [[ ! -L "$t/etc/systemd/system/multi-user.target.wants/ollie-live-setup.service" ]] || { echo "the live USB's set-up is still on"; return 1; }
    [[ -L "$t/etc/systemd/system/display-manager.service" && -e "$t$(readlink "$t/etc/systemd/system/display-manager.service")" ]] ||
        { echo "the desktop does not start"; return 1; }
}
fix_first_start() {
    rm -f "$t/etc/systemd/system/multi-user.target.wants/ollie-live-setup.service"
    grep -q '^ollie:' "$t/etc/passwd" || in_target useradd -m -G wheel,video,audio,input,storage -s /bin/bash -c "Ollie" ollie
    in_target passwd -d ollie
    [[ -s "$t/etc/xdg/autostart/ollie-first-setup.desktop" ]] ||
        install -D -m 0644 "$profile/airootfs/etc/xdg/autostart/ollie-first-setup.desktop" "$t/etc/xdg/autostart/ollie-first-setup.desktop"
    [[ -e "$t/usr/lib/systemd/system/sddm.service" ]] || reinstall sddm
    ln -sfn /usr/lib/systemd/system/sddm.service "$t/etc/systemd/system/display-manager.service"
}

# The checks both ways run first, in this order.
check_common() {
    check "All of Ollie OS's programs are there, nothing damaged ($(in_target pacman -Qq | wc -l) programs)" test_files fix_files
    check "Steam and its 32-bit graphics drivers" test_steam fix_steam
    check "Steam's updates (the multilib packages are switched on)" test_multilib fix_multilib
    check "The language setting Steam needs to start (en_US.UTF-8)" test_locale fix_locale
    check "Start-up image with the drivers for every computer (kernel $(kernel_version))" test_image fix_image
}
