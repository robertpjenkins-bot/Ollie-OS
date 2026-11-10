#!/bin/bash
# Runs ollie-windows-setup for real on a made-up Windows ISO (an unpacked
# folder) and a loop device standing in for the Windows Setup part (a folder
# stands in for its FAT32, as some kernels have no vfat): Windows Setup must land on the drive whole, the answer file must be
# there for Windows 11 only, a damaged ISO must be turned away, and a
# Windows image over 4 GB must be split (FAT32). Needs root, losetup, xorriso
# and wimlib; skips itself where they are not there.
#   windows-setup-test.sh [big]      ("big": also the over-4-GB image; slow)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
setup="$here/../profile/airootfs/usr/local/bin/ollie-windows-setup"
[[ $EUID -eq 0 ]] && command -v losetup >/dev/null && command -v wimlib-imagex >/dev/null || { echo "SKIP: needs root, losetup, wimlib-imagex"; exit 0; }
work="$(mktemp -d)"
L=""
cleanup() { mountpoint -q "$work/m" && umount "$work/m"; [[ -n $L ]] && losetup -d "$L" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT
fail=0
say() { printf '%s\n' "$*"; }
check() { # check DESCRIPTION CONDITION-COMMAND...
    local d="$1"; shift
    if "$@"; then say "  ok: $d"; else say "  FAIL: $d"; fail=1; fi
}

make_iso() { # make_iso [BIG]: the unpacked ISO in $work/tree
    local t="$work/tree"
    rm -rf "$t" "$work/img"; mkdir -p "$t/efi/boot" "$t/sources" "$t/boot" "$work/img"
    head -c 700000 /dev/urandom >"$t/efi/boot/bootx64.efi"
    head -c 300000 /dev/urandom >"$t/boot/bcd"
    head -c 200000 /dev/urandom >"$t/setup.exe"
    for i in 1 2 3; do head -c 100000 /dev/urandom >"$t/sources/file$i.dll"; done
    head -c 5000000 /dev/urandom >"$work/img/boot.bin"
    wimlib-imagex capture "$work/img" "$t/sources/boot.wim" "Windows PE" --compress=LZX >/dev/null 2>&1 || return 1
    rm -f "$work/img/boot.bin"
    if [[ ${1:-} == big ]]; then
        for i in 1 2 3 4 5 6; do yes "file $i" | head -c 800M >"$work/img/big$i.bin"; done # different files (not merged), 4.8 GB
        wimlib-imagex capture "$work/img" "$t/sources/install.wim" "Windows 10 Pro" --compress=none >/dev/null 2>&1 || return 1
    else
        head -c 20000000 /dev/urandom >"$work/img/os.bin"
        wimlib-imagex capture "$work/img" "$t/sources/install.wim" "Windows 10 Pro" --compress=LZX >/dev/null 2>&1 || return 1
    fi
}

# Stand-ins: "format" empties the folder, "mount" of the loop device shows it.
mkdir -p "$work/stub" "$work/fat"
cat >"$work/stub/mkfs.fat" <<STUB
#!/bin/sh
rm -rf "$work/fat" && mkdir -p "$work/fat"
STUB
cat >"$work/stub/mount" <<STUB
#!/bin/bash
args=("\$@")
mp="\${args[\$((\${#args[@]} - 1))]}"
exec /usr/bin/mount --bind "$work/fat" "\$mp"
STUB
chmod +x "$work/stub"/*

run_setup() { # run_setup VERSION TREE
    rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
    [[ -n $L ]] && losetup -d "$L" 2>/dev/null
    L="$(losetup -f --show "$work/part.img")"
    mkdir -p "$work/root/etc/ollie"
    PATH="$work/stub:$PATH" "$setup" --version "$1" --iso "$2" --part "$L" --no-label-check --no-efi-vars --root "$work/root" --work "$work" >"$work/out.txt" 2>&1
}

mounted() { mkdir -p "$work/m"; mount --bind "$work/fat" "$work/m"; }

for ver in 10 11; do
    say "== Windows $ver, a small image"
    make_iso || { say "could not make the ISO"; exit 1; }
    if run_setup "$ver" "$work/tree"; then say "  ok: ran"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
    mounted || { say "  FAIL: could not mount the part"; fail=1; continue; }
    check "Windows Setup files are there" test -f "$work/m/setup.exe" -a -f "$work/m/sources/boot.wim" -a -f "$work/m/efi/boot/bootx64.efi"
    check "the image is there" test -f "$work/m/sources/install.wim"
    check "the files are the same as in the ISO" cmp -s "$work/tree/sources/install.wim" "$work/m/sources/install.wim"
    check "SetupComplete.cmd is there" test -f "$work/m/sources/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd"
    if [[ $ver == 11 ]]; then
        check "Windows 11 has the answer file" test -f "$work/m/autounattend.xml"
        check "the answer file is well-formed" python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$work/m/autounattend.xml"
    else
        check "Windows 10 has no answer file" test ! -e "$work/m/autounattend.xml"
    fi
    check "it is noted for Ollie OS (windows $ver)" grep -q "^VERSION=$ver" "$work/root/etc/ollie/windows"
    umount "$work/m"
done

say "== a damaged image is turned away"
make_iso || exit 1
python3 - "$work/tree/sources/install.wim" <<'PY'
import sys
p = sys.argv[1]
with open(p, "r+b") as f:
    f.seek(5_000_000)
    b = f.read(64)
    f.seek(5_000_000)
    f.write(bytes(x ^ 0xFF for x in b))
PY
if run_setup 10 "$work/tree"; then say "  FAIL: a damaged image was accepted"; fail=1; else
    if grep -q "damaged" "$work/out.txt"; then say "  ok: turned away ($(grep Error "$work/out.txt" | head -n 1 | cut -c1-90))"; else say "  FAIL: stopped, but not for being damaged: $(tail -n 2 "$work/out.txt" | tr '\n' ' ')"; fail=1; fi
fi

say "== not a Windows ISO is turned away"
mkdir -p "$work/other" && echo hi >"$work/other/readme.txt"
if run_setup 10 "$work/other"; then say "  FAIL: accepted"; fail=1; else say "  ok: turned away"; fi

if [[ ${1:-} == big ]]; then
    say "== an image over 4 GB is split"
    make_iso big || exit 1
    if run_setup 10 "$work/tree"; then say "  ok: ran"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
    mounted && {
        check "split into install.swm parts" test -f "$work/m/sources/install.swm" -a -f "$work/m/sources/install2.swm"
        check "no part is 4 GB or more" bash -c "! find '$work/m/sources' -name 'install*.swm' -size +4000M | grep -q ."
        check "the parts verify together" bash -c "wimlib-imagex verify \"$work/m/sources/install.swm\" --ref=\"$work/m/sources/install*.swm\" >/dev/null 2>&1"
        umount "$work/m"
    }
fi
((fail == 0)) && say "ALL OK" || say "FAILED"
exit $fail
