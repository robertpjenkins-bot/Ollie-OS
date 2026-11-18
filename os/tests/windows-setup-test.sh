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
    wimlib-imagex capture "$work/img" "$t/sources/boot.wim" "Microsoft Windows PE (x64)" --compress=LZX >/dev/null 2>&1 || return 1
    wimlib-imagex append "$work/img" "$t/sources/boot.wim" "Microsoft Windows Setup (x64)" --compress=LZX >/dev/null 2>&1 || return 1
    rm -f "$work/img/boot.bin"
    if [[ ${1:-} == big ]]; then
        for i in 1 2 3 4 5 6; do yes "file $i" | head -c 800M >"$work/img/big$i.bin"; done # different files (not merged), 4.8 GB
        wimlib-imagex capture "$work/img" "$t/sources/install.wim" "Windows 10 Pro" --compress=none >/dev/null 2>&1 || return 1
    else
        head -c 20000000 /dev/urandom >"$work/img/os.bin"
        wimlib-imagex capture "$work/img" "$t/sources/install.wim" "Windows 10 Home" --compress=LZX >/dev/null 2>&1 || return 1
        wimlib-imagex append "$work/img" "$t/sources/install.wim" "Windows 10 Pro" --compress=LZX >/dev/null 2>&1 || return 1
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

say "== a drive connected by USB: Windows is put on without Windows Setup (its check does not apply)"
make_iso || exit 1
truncate -s 3G "$work/ntfs.img"
L3="$(losetup -f --show "$work/ntfs.img")"
rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
[[ -n $L ]] && losetup -d "$L" 2>/dev/null
L="$(losetup -f --show "$work/part.img")"
mkdir -p "$work/root/etc/ollie"
if OLLIE_WINDOWS_USB_CMD="$here/../profile/airootfs/usr/local/share/ollie/windows-usb-install.cmd" PATH="$work/stub:$PATH" "$setup" --version 10 --iso "$work/tree" --part "$L" --no-label-check --no-efi-vars --usb yes --windows-part "$L3" --root "$work/root" --work "$work" >"$work/out.txt" 2>&1; then say "  ok: ran"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
check "the part for Windows has the marker file the script looks for" bash -c "ntfsls '$L3' | grep -qx OLLIE-WINDOWS-TARGET"
check "the part for Windows is NTFS (it can be listed)" bash -c "ntfsls '$L3' >/dev/null 2>&1"
mounted || { say "  FAIL: could not open the Setup part"; fail=1; }
check "the Windows Setup part has its marker" test -f "$work/m/ollie-setup-marker"
check "the edition is Windows 10 Pro (number 2)" grep -q '^2' "$work/m/ollie-image-index.txt"
check "the Windows image is NOT on the Setup part (FAT32 cannot hold it whole)" test ! -e "$work/m/sources/install.wim"
check "the Windows image is on the NTFS part, identical to the one in the ISO" bash -c "ntfscat -f '$L3' ollie-image.wim 2>/dev/null | cmp -s - '$work/tree/sources/install.wim'"
d="$work/extract"; rm -rf "$d"; mkdir -p "$d"
wimlib-imagex extract "$work/m/sources/boot.wim" 2 /Windows/System32/winpeshl.ini /Windows/System32/ollie-usb-install.cmd --dest-dir="$d" >/dev/null 2>&1
check "Setup's start-up image runs the script instead of Setup" grep -q 'ollie-usb-install.cmd' "$d/winpeshl.ini"
check "winpeshl.ini has Windows line endings" bash -c "grep -q \$'\\r' '$d/winpeshl.ini'"
check "the script is there, with Windows line endings" bash -c "grep -q 'dism /apply-image' '$d/ollie-usb-install.cmd' && grep -q \$'\\r' '$d/ollie-usb-install.cmd'"
check "the Setup image (2), not the PE image (1), got it" bash -c "! wimlib-imagex extract '$work/m/sources/boot.wim' 1 /Windows/System32/winpeshl.ini --dest-dir='$work/x1' >/dev/null 2>&1"
check "the start-up image is whole" bash -c "wimlib-imagex verify '$work/m/sources/boot.wim' >/dev/null 2>&1"
umount "$work/m"
check "it is noted that the drive is USB" grep -q '^USB=1' "$work/root/etc/ollie/windows"

say "== a whole Windows already on the part for Windows is never formatted over; an interrupted try is"
mkdir -p "$work/stub2"
cat >"$work/stub2/ntfsls" <<STUB
#!/bin/bash
# a stand-in for what is on the part: WIN_WHOLE=1 a whole Windows, else only its folders
case "\$*" in
*"-p /Windows/System32"*) [[ -n \${WIN_WHOLE:-} ]] && printf '%s\\n' ntoskrnl.exe winload.efi smss.exe ;;
*) exec /usr/bin/ntfsls "\$@" ;;
esac
STUB
chmod +x "$work/stub2/ntfsls"
usb_run() { # usb_run [ENV=VALUE...]
    make_iso || exit 1
    rm -f "$work/ntfs.img"; truncate -s 3G "$work/ntfs.img"; L3="$(losetup -f --show "$work/ntfs.img")"
    rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
    [[ -n $L ]] && losetup -d "$L" 2>/dev/null
    L="$(losetup -f --show "$work/part.img")"
    env "$@" OLLIE_WINDOWS_USB_CMD="$here/../profile/airootfs/usr/local/share/ollie/windows-usb-install.cmd" PATH="$work/stub2:$work/stub:$PATH" "$setup" --version 10 --iso "$work/tree" --part "$L" --no-label-check --no-efi-vars --usb yes --windows-part "$L3" --root "$work/root" --work "$work" >"$work/out.txt" 2>&1
}
if usb_run WIN_WHOLE=1; then say "  FAIL: it formatted over a whole Windows"; fail=1; else
    grep -q "already a Windows" "$work/out.txt" && say "  ok: turned away" || { say "  FAIL: stopped, but not for that: $(tail -n 2 "$work/out.txt" | tr '\n' ' ')"; fail=1; }
fi
losetup -d "$L3" 2>/dev/null
if usb_run A=1; then say "  ok: an interrupted try (folders, no files) is formatted over"; else say "  FAIL: an interrupted try blocked it: $(tail -n 2 "$work/out.txt" | tr '\n' ' ')"; fail=1; fi
check "the part for Windows has the marker again" bash -c "ntfsls '$L3' | grep -qx OLLIE-WINDOWS-TARGET"
losetup -d "$L3" 2>/dev/null

say "== not USB: no script goes in, Setup runs as always"
make_iso || exit 1
if run_setup 10 "$work/tree"; then :; else say "  FAIL: ran"; fail=1; fi
mounted && { check "Setup's own start-up image is untouched" bash -c "! wimlib-imagex extract '$work/m/sources/boot.wim' 2 /Windows/System32/ollie-usb-install.cmd --dest-dir='$work/x2' >/dev/null 2>&1"; umount "$work/m"; }

say "== the account Windows is set up with (no questions, a password at the login screen)"
cat >"$work/account" <<ACC
USER=Bobby Bro
COMPUTER=BOBBYBRO-PC
PASSWORD_B64=$(printf '%s' 'pass123Password' | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
ACC
for ver in 10 11; do
    make_iso || exit 1
    rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
    [[ -n $L ]] && losetup -d "$L" 2>/dev/null
    L="$(losetup -f --show "$work/part.img")"
    mkdir -p "$work/root/etc/ollie"
    if OLLIE_WINDOWS_ACCOUNT="$work/account" PATH="$work/stub:$PATH" "$setup" --version "$ver" --iso "$work/tree" --part "$L" --no-label-check --no-efi-vars --usb no --root "$work/root" --work "$work" >"$work/out.txt" 2>&1; then say "  ok: Windows $ver ran with an account"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
    mounted || { say "  FAIL: could not open the Setup part"; fail=1; continue; }
    x="$work/m/autounattend.xml"
    check "Windows $ver: an answer file is there" test -f "$x"
    check "Windows $ver: it is well-formed" python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$x"
    check "Windows $ver: it makes the account Bobby Bro, an administrator" bash -c "grep -q '<Name>Bobby Bro</Name>' '$x' && grep -q '<Group>Administrators</Group>' '$x'"
    check "Windows $ver: it names the computer BOBBYBRO-PC" grep -q '<ComputerName>BOBBYBRO-PC</ComputerName>' "$x"
    check "Windows $ver: the password is not in plain text" bash -c "! grep -q 'pass123' '$x' && grep -q '<PlainText>false</PlainText>' '$x'"
    check "Windows $ver: the stored password decodes to the typed one (+Password)" bash -c "v=\$(sed -n 's#.*<Value>\\(.*\\)</Value>.*#\\1#p' '$x'); [[ \"\$(printf '%s' \"\$v\" | base64 -d | iconv -f UTF-16LE -t UTF-8)\" == pass123Password ]]"
    check "Windows $ver: no automatic login (the login screen asks)" bash -c "! grep -qi 'AutoLogon' '$x'"
    check "Windows $ver: nothing is asked (OOBE hidden)" bash -c "grep -q '<HideEULAPage>true' '$x' && grep -q '<HideOnlineAccountScreens>true' '$x' && grep -q '<SkipMachineOOBE>true' '$x'"
    if [[ $ver == 11 ]]; then
        check "Windows 11: the checks are bypassed too" grep -q BypassTPMCheck "$x"
    else
        check "Windows 10: no bypass section" bash -c "! grep -q LabConfig '$x'"
    fi
    umount "$work/m"
done

say "== the account, the USB way: the file for the script, no copy with the password at Setup's root"
make_iso || exit 1
rm -f "$work/ntfs.img"; truncate -s 3G "$work/ntfs.img"; L3="$(losetup -f --show "$work/ntfs.img")"
rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
[[ -n $L ]] && losetup -d "$L" 2>/dev/null
L="$(losetup -f --show "$work/part.img")"
if OLLIE_WINDOWS_ACCOUNT="$work/account" OLLIE_WINDOWS_USB_CMD="$here/../profile/airootfs/usr/local/share/ollie/windows-usb-install.cmd" PATH="$work/stub:$PATH" "$setup" --version 10 --iso "$work/tree" --part "$L" --no-label-check --no-efi-vars --usb yes --windows-part "$L3" --root "$work/root" --work "$work" >"$work/out.txt" 2>&1; then say "  ok: ran"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
mounted
check "the answer file for the script is there" test -f "$work/m/ollie-unattend.xml"
check "the first-start script tells Ollie OS when Windows is set up (ollie-windows-ready.txt)" grep -q 'ollie-windows-ready.txt' "$work/m/sources/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd"
check "the first-start script has no start-up-path change (the files are already on Ollie OS's part)" bash -c "! grep -q 'bcdedit' '$work/m/sources/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd' && grep -q RealTimeIsUniversal '$work/m/sources/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd'"
check "it is well-formed and makes the account" bash -c "python3 -c \"import sys,xml.dom.minidom as m; m.parse(sys.argv[1])\" '$work/m/ollie-unattend.xml' && grep -q '<Name>Bobby Bro</Name>' '$work/m/ollie-unattend.xml'"
check "no autounattend.xml at Setup's root (Setup is not run)" test ! -e "$work/m/autounattend.xml"
d="$work/extract2"; rm -rf "$d"; mkdir -p "$d"
wimlib-imagex extract "$work/m/sources/boot.wim" 2 /Windows/System32/ollie-usb-install.cmd --dest-dir="$d" >/dev/null 2>&1
check "the script copies it into Windows (Panther\\Unattend)" grep -q 'Panther.Unattend.unattend.xml' "$d/ollie-usb-install.cmd"
check "the script removes the copy with the password afterwards" grep -q 'del /f /q %S%.ollie-unattend.xml' "$d/ollie-usb-install.cmd"
umount "$work/m"; losetup -d "$L3" 2>/dev/null

say "== a damaged account file is turned away"
printf 'USER=Bobby<script>\nCOMPUTER=X\nPASSWORD_B64=!!!\n' >"$work/badaccount"
make_iso || exit 1
if OLLIE_WINDOWS_ACCOUNT="$work/badaccount" run_setup 10 "$work/tree"; then say "  FAIL: accepted"; fail=1; else grep -q "not in the right form" "$work/out.txt" && say "  ok: turned away" || { say "  FAIL: stopped for another reason: $(tail -n 2 "$work/out.txt" | tr '\n' ' ')"; fail=1; }; fi

say "== the next start: only said to work when the start-up list really shows it chosen"
mkdir -p "$work/efi" "$work/fakeefi"
cat >"$work/stub/efibootmgr" <<STUB
#!/bin/bash
# a made-up start-up list kept in $work/efi/list
f="$work/efi/list"; touch "\$f"
case "\$1" in
-q) shift ;;
esac
case "\$1" in
-C) [[ -n \${FAIL_CREATE:-} ]] && { echo "Could not prepare Boot variable: No such file or directory" >&2; exit 1; }
    echo "Boot0007* Install Windows \$VERSION_FOR_STUB HD(5,GPT,abcd)/File(\\efi\\boot\\bootx64.efi)" >>"\$f" ;;
-n) [[ -n \${FAIL_NEXT:-} ]] && { echo "Could not set BootNext" >&2; exit 1; }
    sed -i '/^BootNext/d' "\$f"; echo "BootNext: \$2" >>"\$f" ;;
-b) sed -i "/^Boot\$2/d" "\$f" ;;
-v|"") cat "\$f" ;;
esac
exit 0
STUB
chmod +x "$work/stub/efibootmgr"
sed -e "s#/sys/firmware/efi#$work/fakeefi#g" "$setup" >"$work/setup-efi.sh"; chmod +x "$work/setup-efi.sh"
efi_run() { # efi_run [ENV=VALUE...]
    : >"$work/efi/list"; rm -f "$work/efi.log"
    make_iso || exit 1
    rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
    [[ -n $L ]] && losetup -d "$L" 2>/dev/null
    L="$(losetup -f --show "$work/part.img")"
    env "$@" VERSION_FOR_STUB=10 OLLIE_WINDOWS_EFI_LOG="$work/efi.log" PATH="$work/stub:$PATH" "$work/setup-efi.sh" --version 10 --iso "$work/tree" --part "$L" --no-label-check --usb no --root "$work/root" --work "$work" >"$work/out.txt" 2>&1
}
efi_run A=1; check "the list takes it: it says the next start is set" grep -q '^NEXT-START' "$work/out.txt"
check "the entry and BootNext are in the list" bash -c "grep -q 'Install Windows 10' '$work/efi/list' && grep -q '^BootNext: 0007' '$work/efi/list'"
check "what efibootmgr said is kept in the log" grep -q 'entry: 0007' "$work/efi.log"
efi_run FAIL_CREATE=1; check "no entry could be made: it does NOT say the next start is set" bash -c "! grep -q '^NEXT-START' '$work/out.txt' && grep -q 'would not take the entry' '$work/out.txt'"
check "the reason is in the log" grep -q 'Could not prepare Boot variable' "$work/efi.log"
efi_run FAIL_NEXT=1; check "BootNext could not be set: it does NOT say the next start is set" bash -c "! grep -q '^NEXT-START' '$work/out.txt'"
check "the reason is in the log (BootNext)" grep -q 'Could not set BootNext' "$work/efi.log"
rm -f "$work/stub/efibootmgr"

if [[ ${1:-} == big ]]; then
    say "== an image over 4 GB, the USB way: goes whole onto the NTFS part (no splitting, no converting)"
    make_iso big || exit 1
    rm -f "$work/ntfs.img"; truncate -s 14G "$work/ntfs.img"; L3="$(losetup -f --show "$work/ntfs.img")"
    rm -f "$work/part.img"; truncate -s 12G "$work/part.img"
    [[ -n $L ]] && losetup -d "$L" 2>/dev/null
    L="$(losetup -f --show "$work/part.img")"
    if OLLIE_WINDOWS_USB_CMD="$here/../profile/airootfs/usr/local/share/ollie/windows-usb-install.cmd" PATH="$work/stub:$PATH" "$setup" --version 10 --iso "$work/tree" --part "$L" --no-label-check --no-efi-vars --usb yes --windows-part "$L3" --root "$work/root" --work "$work" >"$work/out.txt" 2>&1; then say "  ok: ran"; else say "  FAIL: ran ($(tail -n 2 "$work/out.txt" | tr '\n' ' '))"; fail=1; fi
    check "the whole image (over 4 GB) is on the NTFS part, byte for byte" bash -c "ntfscat -f '$L3' ollie-image.wim 2>/dev/null | cmp -s - '$work/tree/sources/install.wim'"
    mounted && { check "nothing was split onto the Setup part" bash -c "! ls '$work/m/sources/' | grep -q 'install.*swm'"; umount "$work/m"; }
    losetup -d "$L3" 2>/dev/null
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
