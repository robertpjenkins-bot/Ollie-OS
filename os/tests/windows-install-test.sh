#!/bin/bash
# Tests "Install Windows" (usr/local/bin/ollie-windows-install) at login: with a
# Windows file the Add Windows Updater saved it must not ask anything and must
# restart into Windows Setup by itself; without one it asks first. The system
# pieces are stood in for.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../profile/airootfs/usr/local/bin/ollie-windows-install"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
bad() { echo "  FAIL: $*"; fail=1; }
mkdir -p "$work/bin" "$work/etc/ollie" "$work/var/lib/ollie" "$work/boot/loader/entries"
echo "VERSION=10" >"$work/etc/ollie/windows"
cat >"$work/bin/kdialog" <<STUB
#!/bin/bash
echo "kdialog \$*" >>"$work/calls.log"
case "\$*" in *--progressbar*) echo "org.kde.fake /ProgressDialog" ;; *--yesno*) exit \${YESNO_RC:-0} ;; esac
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' >"$work/bin/qdbus6"
printf '#!/bin/sh\necho "systemctl $*" >>"%s/calls.log"\n' "$work" >"$work/bin/systemctl"
printf '#!/bin/sh\necho "OLLIE_WINSETUP"\n' >"$work/bin/lsblk"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/sleep"
printf '#!/bin/sh\nshift\nexec "$@"\n' >"$work/bin/sudo"
cat >"$work/bin/setup-stub" <<STUB
#!/bin/bash
echo "setup \$*" >>"$work/calls.log"
echo "PROGRESS 50 Halfway"
echo "PROGRESS 100 Windows Setup is ready"
echo "NEXT-START Windows Setup"
STUB
chmod +x "$work/bin"/*
sed -e "s#/etc/ollie/windows#$work/etc/ollie/windows#g" -e "s#/var/lib/ollie/#$work/var/lib/ollie/#g" \
    -e "s#/boot/loader/entries/windows.conf#$work/boot/loader/entries/windows.conf#g" \
    -e "s#/usr/local/bin/ollie-windows-setup#$work/bin/setup-stub#g" "$app" >"$work/app.sh"
chmod +x "$work/app.sh"
run() { : >"$work/calls.log"; PATH="$work/bin:$PATH" "$work/app.sh" "$@" >"$work/out.txt" 2>&1; }

echo "== at login, a saved Windows file: no question, goes on, restarts by itself"
truncate -s 3G "$work/var/lib/ollie/windows-10.iso"
run --at-login || bad "it failed: $(tail -n 3 "$work/out.txt")"
grep -q -- "--yesno" "$work/calls.log" && bad "it asked a question: $(grep -- --yesno "$work/calls.log" | head -n 1)"
grep -q "^setup --version 10 --iso $work/var/lib/ollie/windows-10.iso" "$work/calls.log" || bad "Windows Setup was not got ready from the saved file"
grep -q "^systemctl reboot" "$work/calls.log" || bad "it did not restart by itself"
[[ -e $work/var/lib/ollie/windows-10.iso ]] && bad "the saved file was not removed after it was on the drive"

echo "== at login, no saved file: it asks first (and 'Later' does nothing)"
YESNO_RC=1 run --at-login
grep -q -- "--yesno" "$work/calls.log" || bad "it did not ask"
grep -q "^setup" "$work/calls.log" && bad "it went on after Later"
grep -q "^systemctl reboot" "$work/calls.log" && bad "it restarted after Later"

echo "== from the apps menu with a saved file: it asks 'Restart now / Later' at the end (a person is there)"
truncate -s 3G "$work/var/lib/ollie/windows-10.iso"
run || bad "it failed: $(tail -n 3 "$work/out.txt")"
grep -q -- "--yesno.*Windows 10 Setup is ready" "$work/calls.log" || bad "no 'ready' question at the end"

((fail == 0)) && echo "ALL OK" || echo "FAILED"
exit $fail
