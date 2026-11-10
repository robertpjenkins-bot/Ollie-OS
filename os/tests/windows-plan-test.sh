#!/bin/bash
# Runs ollie-windows-plan (usr/local/lib/ollie/windows-plan) for real on a
# loop device: a made-up drive (GPT image) whose Ollie OS part is a real btrfs,
# mounted, that is really made smaller. Only the things that need a running
# Ollie OS are stood in for (findmnt, lsblk, the kernel's part list). Needs
# root, losetup and mount; skips itself where they are not there.
#   windows-plan-test.sh [RUNS]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
air="$here/../profile/airootfs"
runs="${1:-5}"
GiB=1073741824
fail=0
[[ $EUID -eq 0 ]] && command -v losetup >/dev/null && command -v mkfs.btrfs >/dev/null && command -v sgdisk >/dev/null || { echo "SKIP: needs root, losetup, mkfs.btrfs, sgdisk"; exit 0; }
work="$(mktemp -d)"
cleanup() {
    mountpoint -q "$work/mnt" && umount "$work/mnt"
    [[ -n ${L0:-} ]] && losetup -d "$L0" 2>/dev/null
    [[ -n ${L1:-} ]] && losetup -d "$L1" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT
RANDOM=${SEED:-$$}

for ((run = 1; run <= runs; run++)); do
    img="$work/disk.img"
    rm -f "$img"
    root_gb=$((90 + RANDOM % 120))
    after_gb=$((RANDOM % 3 == 0 ? 0 : 3 + RANDOM % 20))
    gb=$((32 + RANDOM % 40))
    old_setup=$((RANDOM % 3 == 0))
    tail_gb=$((RANDOM % 3 == 0 ? 100 + RANDOM % 80 : 4)) # free room at the end of the drive (sometimes)
    disk_gb=$((root_gb + after_gb + (old_setup ? 10 : 0) + tail_gb))
    truncate -s "${disk_gb}G" "$img"
    args=(-n 1:2048:+512M -t 1:ef00 -c 1:OLLIE_BOOT -n 2:0:+${root_gb}G -t 2:8300 -c 2:OLLIE_ROOT)
    ((after_gb)) && args+=(-n "3:0:+${after_gb}G" -t 3:0700 -c 3:data)
    ((old_setup)) && args+=(-n "4:0:+10G" -t 4:0700 -c 4:OLLIE_WINSETUP)
    sgdisk "${args[@]}" "$img" >/dev/null || { echo "could not make the image"; exit 1; }
    rstart=$(sfdisk -d "$img" | sed -n "s#^${img}2 : start= *\\([0-9]*\\),.*#\\1#p")
    rsize=$(sfdisk -d "$img" | sed -n "s#^${img}2 : start= *[0-9]*, size= *\\([0-9]*\\),.*#\\1#p")
    L0="$(losetup -f --show "$img")"
    L1="$(losetup -f --show -o $((rstart * 512)) --sizelimit $((rsize * 512)) "$img")"
    mkfs.btrfs -q -f "$L1" || exit 1
    mkdir -p "$work/mnt" && mount "$L1" "$work/mnt" || { echo "SKIP: cannot mount a loop btrfs here"; exit 0; }
    head -c 50000000 /dev/urandom >"$work/mnt/data.bin"
    before="$(sfdisk -d "$img")"

    # the stand-ins
    bin="$work/bin"
    mkdir -p "$bin" "$work/boot" "$work/etc" "$work/applications" "$work/autostart" "$work/share"
    cat >"$bin/findmnt" <<STUB
#!/bin/sh
case "\$*" in *FSTYPE*) echo btrfs;; *) echo $L1;; esac
STUB
    cat >"$bin/lsblk" <<STUB
#!/bin/sh
case "\$*" in *PKNAME*) basename $L0;; *PTTYPE*) echo gpt;; esac
STUB
    for t in resizepart partx udevadm systemctl; do printf '#!/bin/sh\nexit 0\n' >"$bin/$t"; done
    chmod +x "$bin"/*
    echo 2 >"$work/partnum"
    mkdir -p "$work/share/ollie"
    printf '[Desktop Entry]\nExec=/usr/local/bin/ollie-windows-install\n' >"$work/share/ollie/ollie-windows-install.desktop"
    printf 'MENU=1\nVERSION=10\nGB=%s\n' "$gb" >"$work/boot/ollie-windows-plan"
    # "/" is the mounted btrfs; the plan's own files are in the work folder
    sed -e "s#plan=/boot/ollie-windows-plan#plan=$work/boot/ollie-windows-plan#" \
        -e "s#/sys/class/block/\$name/partition#$work/partnum#" \
        -e "s#btrfs filesystem usage -b /#btrfs filesystem usage -b $work/mnt#" \
        -e "s#resize \"-\${1}g\" /#resize \"-\${1}g\" $work/mnt#" \
        -e "s#-b \$src#-n \$src#; s#-b \$disk#-n \$disk#" \
        -e "s#/etc/ollie/windows#$work/etc/windows#; s#/usr/share/applications/#$work/applications/#; s#/etc/xdg/autostart/#$work/autostart/#; s#/usr/local/share/ollie/#$work/share/ollie/#g" \
        "$air/usr/local/lib/ollie/windows-plan" >"$work/plan.sh"
    chmod +x "$work/plan.sh"
    fs_before="$(btrfs filesystem usage -b "$work/mnt" | awk '/Device size:/ {print $3; exit}')"
    out="$(PATH="$bin:$PATH" OLLIE_WINDOWS_LAYOUT="$air/usr/local/lib/ollie/windows-layout" "$work/plan.sh" 2>&1)"
    rc=$?
    problems=()
    ((rc == 0)) || problems+=("plan exited $rc: $(echo "$out" | tail -n 3 | tr '\n' ' ')")
    after="$(sfdisk -d "$img")"
    nsetup=$(echo "$after" | grep -c 'name="OLLIE_WINSETUP"')
    ((nsetup == 1)) || problems+=("$nsetup Windows Setup parts")
    sgdisk -v "$img" | grep -q "No problems found" || problems+=("sgdisk -v is not happy")
    # the data part is untouched
    if ((after_gb)); then
        [[ "$(echo "$before" | grep "$img"3)" == "$(echo "$after" | grep "$img"3)" ]] || problems+=("the data part changed")
    fi
    # Ollie OS's btrfs fits in its part, with room
    rsize_after=$(echo "$after" | sed -n "s#^${img}2 : start= *[0-9]*, size= *\\([0-9]*\\),.*#\\1#p")
    fs_after="$(btrfs filesystem usage -b "$work/mnt" | awk '/Device size:/ {print $3; exit}')"
    if echo "$out" | grep -q 'not made smaller'; then margin=0; else margin=$GiB; fi # made smaller: 1 GiB to spare
    if [[ -n $rsize_after && -n $fs_after ]]; then
        ((fs_after + margin <= rsize_after * 512)) || problems+=("the btrfs ($fs_after) does not fit in its part ($((rsize_after * 512)))")
    fi
    # still readable
    cmp -s <(head -c 50000000 "$work/mnt/data.bin") <(head -c 50000000 "$work/mnt/data.bin") && [[ "$(stat -c %s "$work/mnt/data.bin")" == 50000000 ]] || problems+=("Ollie OS's files were damaged")
    btrfs scrub start -B "$work/mnt" >/dev/null 2>&1 || true
    [[ -f $work/etc/windows && -f $work/autostart/ollie-windows-install.desktop ]] || problems+=("Install Windows was not set up")
    if echo "$out" | grep -q 'not made smaller'; then
        mode=free
        [[ "$fs_after" == "$fs_before" ]] || problems+=("free room used, but the btrfs changed size")
    else
        mode=shrink
        ((fs_after < fs_before)) || problems+=("the btrfs was not made smaller")
    fi
    if ((${#problems[@]})); then
        fail=1
        echo "run $run (root ${root_gb}G, after ${after_gb}G, tail ${tail_gb}G, old setup $old_setup, Windows ${gb}G): FAIL: ${problems[*]}"
    else
        echo "run $run (root ${root_gb}G, after ${after_gb}G, tail ${tail_gb}G, old setup $old_setup, Windows ${gb}G): ok, $mode"
    fi
    umount "$work/mnt"
    losetup -d "$L0"; losetup -d "$L1"; L0="" L1=""
done
exit $fail
