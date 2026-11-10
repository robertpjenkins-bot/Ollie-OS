#!/bin/bash
# Runs the Add Windows Updater (os/usb/ollie-add-windows) and then Ollie OS's
# start-up part of it (windows-plan) for real, on a loop device: a made-up
# drive (GPT image) whose Ollie OS part is a real mounted btrfs. Only what needs
# a running Ollie OS is stood in for (findmnt, lsblk, sudo's paths, the kernel's
# part list, the download). Needs root, losetup, mkfs.btrfs and sgdisk; skips
# itself where they are not there.
#   windows-updater-test.sh [SCENARIO...]     (default: all)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
air="$here/../profile/airootfs"
upd="$here/../usb/ollie-add-windows"
[[ $EUID -eq 0 ]] && command -v losetup >/dev/null && command -v mkfs.btrfs >/dev/null && command -v sgdisk >/dev/null || { echo "SKIP: needs root, losetup, mkfs.btrfs, sgdisk"; exit 0; }
work="$(mktemp -d)"
L0="" L1=""
cleanup() {
    mountpoint -q "$work/mnt" && umount "$work/mnt"
    [[ -n $L0 ]] && losetup -d "$L0" 2>/dev/null
    [[ -n $L1 ]] && losetup -d "$L1" 2>/dev/null
    rm -f /dev/ollietest0
    rm -rf "$work"
}
trap cleanup EXIT
fail=0
problems=()
bad() { problems+=("$*"); }

tab() { sfdisk -d "$work/disk.img"; }
partline() { tab | grep "^$work/disk.img$1 :" ; }
partsize() { partline "$1" | sed -n 's/.*size= *\([0-9]*\),.*/\1/p'; }
setups() { tab | grep -c 'name="OLLIE_WINSETUP"'; }

# world ROOT_GB TAIL_GB EXTRA...   EXTRA: "n:size:type:name" parts after Ollie OS's (size like 6G or 16M)
world() {
    local root_gb="$1" tail_gb="$2"
    shift 2
    [[ -n $L0 ]] && { mountpoint -q "$work/mnt" && umount "$work/mnt"; losetup -d "$L0" 2>/dev/null; losetup -d "$L1" 2>/dev/null; L0="" L1=""; }
    rm -rf "${work:?}/fake" "${work:?}/home"
    local total=$((root_gb + tail_gb + 2)) a=(-n 1:2048:+512M -t 1:ef00 -c 1:OLLIE_BOOT -n "2:0:+${root_gb}G" -t 2:8300 -c 2:OLLIE_ROOT) x
    for x in "$@"; do
        IFS=: read -r n sz ty nm <<<"$x"
        if [[ $sz == *M ]]; then total=$((total + 1)); else total=$((total + ${sz%G})); fi
        a+=(-n "$n:0:+$sz" -t "$n:$ty")
        [[ -n $nm ]] && a+=(-c "$n:$nm")
    done
    rm -f "$work/disk.img"
    truncate -s "${total}G" "$work/disk.img"
    sgdisk "${a[@]}" "$work/disk.img" >/dev/null || { echo "could not make the image"; exit 1; }
    local rs rz
    rs=$(partline 2 | sed -n 's/.*start= *\([0-9]*\),.*/\1/p')
    rz=$(partsize 2)
    L0="$(losetup -f --show "$work/disk.img")"
    L1="$(losetup -f --show -o $((rs * 512)) --sizelimit $((rz * 512)) "$work/disk.img")"
    ln -sf "$L0" /dev/ollietest0 # a name without "loop" in it (the updater skips loop devices when it lists drives)
    mkfs.btrfs -q -f "$L1" && mkdir -p "$work/mnt" && mount "$L1" "$work/mnt" || { echo "SKIP: cannot mount a loop btrfs here"; exit 0; }
    head -c 20000000 /dev/urandom >"$work/mnt/data.bin"
    mkdir -p "$work/fake/boot/loader/entries" "$work/fake/usr/local/bin" "$work/fake/sys/firmware/efi" "$work/fake/var/lib/ollie" "$work/fake/etc/ollie" \
        "$work/home/Downloads" "$work/share/airootfs" "$work/bin" "$work/fake/etc/xdg/autostart" "$work/fake/usr/share/applications"
    touch "$work/fake/usr/local/bin/ollie-first-setup"
    chmod +x "$work/fake/usr/local/bin/ollie-first-setup"
    # what the AppImage carries
    local f
    for f in usr/local/lib/ollie/windows-plan usr/local/lib/ollie/windows-layout usr/local/lib/ollie/get-windows.py etc/systemd/system/ollie-windows-plan.service \
        usr/local/bin/ollie-windows-setup usr/local/bin/ollie-windows-install usr/local/bin/ollie-windows-boot usr/local/bin/ollie-restart-windows \
        usr/local/share/ollie/ollie-windows-install.desktop usr/share/applications/ollie-restart-windows.desktop; do
        mkdir -p "$work/share/airootfs/$(dirname "$f")"
        cp -a "$air/$f" "$work/share/airootfs/$f"
    done
    make_stubs
}

make_stubs() {
    local b="$work/bin"
    cat >"$b/sudo" <<STUB
#!/bin/bash
[[ \$1 == -n ]] && shift
map() { case "\$1" in "$work/fake"/*) echo "\$1" ;; *) echo "$work/fake\$1" ;; esac; }
case "\$1" in
install) shift; d=""; args=(); while [[ \$1 == -* ]]; do if [[ \$1 == -m ]]; then args+=(-m "\$2"); shift 2; elif [[ \$1 == -d ]]; then d=1; args+=(-d); shift; else args+=("\$1"); shift; fi; done
    if [[ -n \$d ]]; then mkdir -p "\$(map "\$1")"; else exec install "\${args[@]}" "\$1" "\$(map "\$2")"; fi ;;
tee) exec tee "\$(map "\$2")" ;;
btrfs) exec btrfs filesystem usage -b "$work/mnt" ;;
rm) shift; args=(); for a in "\$@"; do case "\$a" in /*) args+=("\$(map "\$a")") ;; *) args+=("\$a") ;; esac; done; exec rm "\${args[@]}" ;;
cp) shift 3; mkdir -p "\$(dirname "\$(map "\$2")")"; exec cp "\$1" "\$(map "\$2")" ;;
mv) shift; exec mv "\$(map "\$1")" "\$(map "\$2")" ;;
curl) shift; while [[ \$1 != -o ]]; do shift; done; echo "curl \$*" >>"$work/curl.log"; mkdir -p "\$(dirname "\$(map "\$2")")"; truncate -s 3G "\$(map "\$2")" ;;
pacman | systemctl | sync | umount) exit 0 ;;
efibootmgr) cat "$work/efibootmgr.out" 2>/dev/null ;;
/usr/local/bin/ollie-windows-boot) echo "ollie-windows-boot ran" >>"$work/boot.log" ;;
*) exec "\$@" ;;
esac
STUB
    cat >"$b/findmnt" <<STUB
#!/bin/sh
case "\$*" in *FSTYPE*) echo btrfs;; *-S*) exit 1;; *) echo $L1;; esac
STUB
    cat >"$b/lsblk" <<STUB
#!/bin/bash
case "\$*" in
*PKNAME*) echo ollietest0 ;;
*PTTYPE*) echo gpt ;;
*NAME,SIZE,TYPE,MODEL*) echo "/dev/ollietest0 500G disk Test drive" ;;
*PARTTYPE*) # the parts, from the image
    sfdisk -d "$work/disk.img" | awk -v d="/dev/ollietest0" -v img="$work/disk.img" 'index(\$1, img) == 1 {
        n = substr(\$1, length(img) + 1); line = \$0; t = ""; z = 0; nm = ""
        if (match(line, /type=[0-9A-Fa-f-]+/)) t = tolower(substr(line, RSTART + 5, RLENGTH - 5))
        if (match(line, /size= *[0-9]+/)) { z = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", z) }
        if (match(line, /name="[^"]*"/)) nm = substr(line, RSTART + 6, RLENGTH - 7)
        fs = (nm == "Basic data partition" ? "ntfs" : "")
        printf "NAME=\"%sp%s\" PARTTYPE=\"%s\" FSTYPE=\"%s\" PARTLABEL=\"%s\" SIZE=\"%d\"\n", d, n, t, fs, nm, z * 512 }' ;;
esac
STUB
    printf '#!/bin/sh\nexit 0\n' >"$b/partx"
    printf '#!/bin/sh\nexit 0\n' >"$b/resizepart"
    printf '#!/bin/sh\nexit 0\n' >"$b/udevadm"
    printf '#!/bin/sh\nexit 1\n' >"$b/xdg-user-dir"
    printf '#!/bin/sh\nexit 0\n' >"$b/xdg-open"
    printf '#!/bin/sh\nexit 0\n' >"$b/kbuildsycoca6"
    printf '#!/bin/sh\necho 1\n' >"$b/uname_stub"
    cat >"$b/python3" <<'STUB'
#!/bin/bash
echo "https://example.invalid/windows.iso"
STUB
    chmod +x "$b"/*
    rm -f "$work/curl.log" "$work/boot.log" "$work/efibootmgr.out"
}

# run_updater "INPUT LINES"
run_updater() {
    sed -e "s#/usr/local/bin/ollie-first-setup#$work/fake/usr/local/bin/ollie-first-setup#" \
        -e "s#/sys/firmware/efi#$work/fake/sys/firmware/efi#" \
        -e "s#/boot/loader/entries#$work/fake/boot/loader/entries#" \
        -e "s#/boot/EFI/Microsoft#$work/fake/boot/EFI/Microsoft#" \
        -e "s#/boot/ollie-windows-plan#$work/fake/boot/ollie-windows-plan#g" \
        -e "s#/var/lib/ollie#$work/fake/var/lib/ollie#g" \
        -e "s#/usr/local/bin/ollie-windows-boot#ollie-windows-boot-stub#" \
        -e 's|^num="\${src##\*\[!0-9\]}".*|num=2|' \
        "$upd" >"$work/upd.sh"
    chmod +x "$work/upd.sh"
    printf '#!/bin/sh\necho "ollie-windows-boot ran" >>"%s/boot.log"\n' "$work" >"$work/bin/ollie-windows-boot-stub"
    chmod +x "$work/bin/ollie-windows-boot-stub"
    printf '%b' "$1" | HOME="$work/home" PATH="$work/bin:$PATH" OLLIE_WINDOWS_IN_TERMINAL=1 OLLIE_APPS_SHARE="$work/share" timeout 120 "$work/upd.sh" >"$work/upd.out" 2>&1
    return $?
}

# run_plan: what the next start does (windows-plan), on the same drive
run_plan() {
    sed -e "s#plan=/boot/ollie-windows-plan#plan=$work/fake/boot/ollie-windows-plan#" \
        -e "s#/sys/class/block/\$name/partition#$work/partnum#" \
        -e "s#btrfs filesystem usage -b /#btrfs filesystem usage -b $work/mnt#" \
        -e "s#resize \"-\${1}g\" /#resize \"-\${1}g\" $work/mnt#" \
        -e "s#/etc/ollie/windows#$work/fake/etc/ollie/windows#; s#/usr/share/applications/#$work/fake/usr/share/applications/#; s#/etc/xdg/autostart/#$work/fake/etc/xdg/autostart/#; s#/usr/local/share/ollie/#$work/share/airootfs/usr/local/share/ollie/#g" \
        "$air/usr/local/lib/ollie/windows-plan" >"$work/plan.sh"
    chmod +x "$work/plan.sh"
    echo 2 >"$work/partnum"
    PATH="$work/bin:$PATH" OLLIE_WINDOWS_LAYOUT="$air/usr/local/lib/ollie/windows-layout" "$work/plan.sh" >"$work/plan.out" 2>&1
}

check_common() { # after the plan: the table is good, Ollie OS's btrfs fits and is readable
    sgdisk -v "$work/disk.img" | grep -q "No problems found" || bad "sgdisk -v is not happy"
    (($(setups) == 1)) || bad "$(setups) Windows Setup parts"
    local rsz fs
    rsz=$(partsize 2)
    fs="$(btrfs filesystem usage -b "$work/mnt" | awk '/Device size:/ {print $3; exit}')"
    ((fs <= rsz * 512)) || bad "the btrfs ($fs) is bigger than its part ($((rsz * 512)))"
    [[ "$(stat -c %s "$work/mnt/data.bin")" == 20000000 ]] || bad "Ollie OS's files were damaged"
}

report() { # report NAME
    if ((${#problems[@]})); then
        fail=1
        echo "FAIL $1:"
        printf '   - %s\n' "${problems[@]}"
        echo "   --- updater:"; tail -n 12 "$work/upd.out" | sed 's/\x1b\[[0-9;]*m//g; s/^/   | /'
        [[ -f $work/plan.out ]] && { echo "   --- plan:"; tail -n 6 "$work/plan.out" | sed 's/^/   | /'; }
    else
        echo "ok   $1"
    fi
    problems=()
    rm -f "$work/plan.out"
}

want() { [[ $# -eq 0 ]] || [[ " ${ONLY:-} " == *" $1 "* ]] || [[ -z ${ONLY:-} ]]; }
ONLY="$*"

WIN=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7 # basic data
MSR=e3c9e316-0b5c-4db8-817d-f92df00215ae
REC=de94bba4-06d1-4d40-a16a-bfd50179d6ac

# ----- 1. the drive is full of Ollie OS, a data part after it: made smaller -----
if want shrink; then
    world 120 0 "3:6G:$WIN:file mail" "4:3G:$WIN:OLLIE_WINSETUP"
    truncate -s 3500M "$work/home/Downloads/Win10_22H2_English_x64v1.iso"
    before3="$(partline 3)"
    # 1 Windows 10, 1 regular, Enter = use the Downloads file, 1 drive, 40 GB, yes, close
    run_updater '1\n1\n\n1\n40\nyes\n\n' || bad "updater failed ($?)"
    [[ -f $work/fake/boot/ollie-windows-plan ]] || bad "no plan was left"
    grep -q "^GB=40" "$work/fake/boot/ollie-windows-plan" 2>/dev/null || bad "the plan does not say 40 GB"
    [[ -s $work/fake/var/lib/ollie/windows-10.iso ]] || bad "the Windows file was not kept"
    [[ -f $work/curl.log ]] && bad "it downloaded although a file was in Downloads"
    run_plan || bad "plan failed: $(tail -n 2 "$work/plan.out" | tr '\n' ' ')"
    check_common
    [[ "$(partline 3)" == "$before3" ]] || bad "the data part changed"
    grep -q 'Making room' "$work/plan.out" || bad "it did not make Ollie OS's part smaller"
    report "full drive: Ollie OS made smaller, data part after it kept"
fi

# ----- 2. free room at the end of the drive: Ollie OS is not touched -----
if want free; then
    world 100 150
    truncate -s 3500M "$work/home/Downloads/Win11_24H2_English_x64.iso"
    rsz_before=$(partsize 2)
    run_updater '2\n1\n\n1\n64\nyes\n\n' || bad "updater failed ($?)"
    grep -q "^VERSION=11" "$work/fake/boot/ollie-windows-plan" 2>/dev/null || bad "the plan does not say Windows 11"
    run_plan || bad "plan failed: $(tail -n 2 "$work/plan.out" | tr '\n' ' ')"
    check_common
    [[ $(partsize 2) == "$rsz_before" ]] || bad "Ollie OS's part changed although there was free room"
    grep -q 'not made smaller' "$work/plan.out" || bad "plan did not say it used free room"
    report "free room: Ollie OS's part not touched"
fi

# ----- 3. Windows is on the drive: delete it, install fresh -----
if want delete; then
    world 80 0 "3:16M:$MSR:Microsoft reserved partition" "4:60G:$WIN:Basic data partition" "5:1G:$REC:" "6:20G:$WIN:file mail"
    printf 'Windows 10 Pro' >/dev/null
    touch "$work/fake/boot/loader/entries/windows.conf"
    mkdir -p "$work/fake/boot/EFI/Microsoft/Boot"
    truncate -s 3500M "$work/home/Downloads/Win10_22H2_English_x64v1.iso"
    keep6="$(partline 6)"
    # 1 Windows 10, 1 regular, Enter (Downloads), 1 drive, 1 = delete Windows, parts 3,4,5, DELETE, 40 GB, yes
    run_updater '1\n1\n\n1\n1\n3,4,5\nDELETE\n40\nyes\n\n' || bad "updater failed ($?)"
    for p in 3 4 5; do [[ -n "$(partline $p)" ]] && bad "part $p is still there"; done
    [[ "$(partline 6)" == "$keep6" ]] || bad "your own data part (6) was touched"
    [[ -e $work/fake/boot/loader/entries/windows.conf || -e $work/fake/boot/EFI/Microsoft ]] && bad "Windows' start-up files were left"
    grep -q 'Deleted' "$work/upd.out" || bad "it did not say it deleted"
    run_plan || bad "plan failed: $(tail -n 2 "$work/plan.out" | tr '\n' ' ')"
    check_common
    report "Windows on the drive: deleted (3,4,5), your data part (6) kept"
fi

# ----- 4. wrong word: nothing is deleted -----
if want nodelete; then
    world 80 0 "3:16M:$MSR:Microsoft reserved partition" "4:60G:$WIN:Basic data partition"
    before="$(tab)"
    run_updater '1\n1\n\n1\n1\nall\ndelete\n' || true
    [[ "$(tab)" == "$before" ]] || bad "something was deleted without the word DELETE"
    grep -q 'nothing was changed' "$work/upd.out" || bad "it did not say nothing was changed"
    report "wrong word instead of DELETE: nothing deleted"
fi

# ----- 5. keep Windows: only the start-up menu -----
if want keep; then
    world 80 0 "3:60G:$WIN:Basic data partition"
    touch "$work/fake/boot/loader/entries/windows.conf"
    before="$(tab)"
    run_updater '1\n1\n1\n2\n\n' || bad "updater failed ($?)"
    [[ "$(tab)" == "$before" ]] || bad "the part table changed"
    [[ -f $work/boot.log ]] || bad "it did not put Windows on the start-up menu"
    [[ -f $work/fake/boot/ollie-windows-plan ]] && bad "a plan was left"
    report "keep Windows: only the start-up menu"
fi

# ----- 6. stop -----
if want stop; then
    world 80 0 "3:60G:$WIN:Basic data partition"
    before="$(tab)"
    run_updater '1\n1\n1\n3\n' || true
    [[ "$(tab)" == "$before" ]] || bad "the part table changed"
    report "stop: nothing changed"
fi

# ----- 7. ARM, and no room -----
if want arm; then
    world 80 0
    before="$(tab)"
    run_updater '1\n2\n' && bad "ARM was accepted"
    grep -q "ARM" "$work/upd.out" || bad "no word about ARM"
    [[ "$(tab)" == "$before" ]] || bad "the part table changed"
    report "ARM: turned away"
fi
if want noroom; then
    world 30 0
    before="$(tab)"
    run_updater '1\n1\n1\n1\n' && bad "it went on with no room"
    grep -q "needs 32 GB" "$work/upd.out" || bad "it did not say there is no room: $(tail -n 3 "$work/upd.out")"
    [[ "$(tab)" == "$before" ]] || bad "the part table changed"
    report "no room: said so, nothing changed"
fi

# ----- 8. the Windows file comes from Microsoft when there is none in Downloads -----
if want download; then
    world 100 150
    run_updater '1\n1\n1\n40\nyes\n\n' || bad "updater failed ($?)"
    [[ -f $work/curl.log ]] || bad "it did not download"
    [[ -s $work/fake/var/lib/ollie/windows-10.iso ]] || bad "the download was not kept"
    grep -q "downloaded from Microsoft now" "$work/upd.out" || bad "the text before the last question does not say it downloads"
    report "no file in Downloads: downloaded from Microsoft"
fi

((fail == 0)) && echo "ALL OK" || echo "FAILED"
exit $fail
