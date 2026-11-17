#!/bin/bash
# Tests "Restart into Windows" (usr/local/bin/ollie-restart-windows) and that
# the start-up menu entry ollie-windows-boot makes is the one it asks for. The
# system pieces (systemctl, efibootmgr, kdialog) are stood in for; no root needed
# for the app itself.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
air="$here/../profile/airootfs"
app="$air/usr/local/bin/ollie-restart-windows"
boot="$air/usr/local/bin/ollie-windows-boot"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
bad() { echo "  FAIL: $*"; fail=1; }

mkdir -p "$work/bin" "$work/efi"
# systemctl knows the ids in $KNOWN (space separated), as the start-up menu does
cat >"$work/bin/systemctl" <<STUB
#!/bin/bash
echo "systemctl \$*" >>"$work/calls.log"
if [[ \$1 == reboot ]]; then
    for a in "\$@"; do
        case "\$a" in --boot-loader-entry=*) id="\${a#--boot-loader-entry=}"; [[ " \${KNOWN:-} " == *" \$id "* ]] && exit 0; exit 1 ;; esac
    done
    exit 0 # a plain restart
fi
exit 0
STUB
cat >"$work/bin/efibootmgr" <<STUB
#!/bin/bash
echo "efibootmgr \$*" >>"$work/calls.log"
[[ \$# -eq 0 ]] && printf '%s' "\${EFI_OUT:-}"
exit 0
STUB
printf '#!/bin/sh\necho "kdialog $*" >>"%s/calls.log"\n' "$work" >"$work/bin/kdialog"
printf '#!/bin/sh\nshift; exec "$@"\n' >"$work/bin/sudo" # sudo -n CMD
chmod +x "$work/bin"/*
sed "s#/sys/firmware/efi#$work/efi#" "$app" >"$work/app.sh"
chmod +x "$work/app.sh"

run() { # run KNOWN EFI_OUT
    : >"$work/calls.log"
    KNOWN="$1" EFI_OUT="$2" PATH="$work/bin:$PATH" "$work/app.sh" >"$work/out.txt" 2>&1
    return $?
}
calls() { cat "$work/calls.log"; }

echo "== the menu knows windows.conf (what ollie-windows-boot makes)"
run "windows.conf" "" || bad "it did not restart"
[[ "$(calls | head -n 1)" == "systemctl reboot --boot-loader-entry=windows.conf" ]] || bad "the first try was not windows.conf: $(calls | head -n 1)"
calls | grep -q efibootmgr && bad "it used the firmware list although the menu had Windows"
echo "== only the automatic entry exists"
run "auto-windows" "" || bad "it did not restart"
calls | grep -q "boot-loader-entry=auto-windows" || bad "auto-windows was not tried"
echo "== the menu does not know Windows, the computer's list does: BootNext"
run "" "Boot0001* Ollie OS
Boot0003* Windows Boot Manager	HD(1,GPT)" || bad "it did not restart"
calls | grep -q "efibootmgr -n 0003" || bad "BootNext was not set to Windows Boot Manager (0003): $(calls | tr '\n' '|')"
[[ "$(calls | tail -n 1)" == "systemctl reboot" ]] || bad "it did not restart after BootNext"
echo "== nothing knows Windows: a clear message, no restart"
run "" "Boot0001* Ollie OS" && bad "it said it worked"
calls | grep -q "^kdialog" || bad "no message was shown"
calls | grep -q "^systemctl reboot$" && bad "it restarted"
echo "== --dry-run changes nothing"
: >"$work/calls.log"; PATH="$work/bin:$PATH" "$work/app.sh" --dry-run >"$work/out.txt" 2>&1
grep -q "windows.conf" "$work/out.txt" || bad "dry run does not mention windows.conf"
[[ "$(grep -v '^efibootmgr *$' "$work/calls.log")" == "" ]] || bad "dry run called something: $(calls | tr '\n' '|')" # (listing the start-up entries is allowed)

echo "== the entry ollie-windows-boot makes has the id the app asks for"
F="$work/root"
mkdir -p "$F/boot/EFI/Microsoft/Boot" "$F/boot/loader/entries" "$F/etc/ollie" "$F/bin"
echo x >"$F/boot/EFI/Microsoft/Boot/bootmgfw.efi"
echo "VERSION=10" >"$F/etc/ollie/windows"
printf 'timeout 3\n' >"$F/boot/loader/loader.conf"
cat >"$F/bin/findmnt" <<STUB
#!/bin/sh
case "\$*" in *FSTYPE*) echo vfat;; *) echo /dev/fakeboot;; esac
STUB
printf '#!/bin/sh\nexit 0\n' >"$F/bin/lsblk"
chmod +x "$F/bin"/*
sed -e "s#\([ \">=]\)/boot#\1$F/boot#g" -e "s#/etc/ollie/windows#$F/etc/ollie/windows#g" "$boot" >"$work/boot.sh"
chmod +x "$work/boot.sh"
PATH="$F/bin:$PATH" "$work/boot.sh" >"$work/boot.out" 2>&1 || bad "ollie-windows-boot failed: $(tail -n 3 "$work/boot.out")"
[[ -f $F/boot/loader/entries/windows.conf ]] || bad "no windows.conf entry was made"
grep -q '^efi */EFI/Microsoft/Boot/bootmgfw.efi' "$F/boot/loader/entries/windows.conf" || bad "the entry does not start Windows Boot Manager"
grep -q '^title *Windows 10' "$F/boot/loader/entries/windows.conf" || bad "the entry is not called Windows 10"
grep -q '^auto-entries no' "$F/boot/loader/loader.conf" || bad "loader.conf lacks auto-entries no (the premise for the id)"
first="$(grep -o 'for id in [^;]*' "$app" | awk '{print $4}')"
[[ "$first" == windows.conf ]] || bad "the app's first id ($first) is not the entry file's name (windows.conf)"

((fail == 0)) && echo "ALL OK" || echo "FAILED"
exit $fail
