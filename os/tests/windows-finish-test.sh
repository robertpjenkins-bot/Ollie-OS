#!/bin/bash
# Tests ollie-windows-finish: after Windows is put on the USB way it restarts
# straight into Windows each time Ollie OS starts, until Windows has written
# its ready marker; at most 5 times; and it stops by itself if there is nothing to wait for.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../profile/airootfs/usr/local/bin/ollie-windows-finish"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
bad() { echo "  FAIL: $*"; fail=1; }
mkdir -p "$work/bin"
cat >"$work/bin/lsblk" <<STUB
#!/bin/sh
[ -n "\${NOPART:-}" ] || echo "/dev/ollietest9 OLLIE_WINDOWS"
STUB
cat >"$work/bin/ntfsls" <<STUB
#!/bin/sh
[ -n "\${READY:-}" ] && echo ollie-windows-ready.txt
echo Windows
STUB
printf '#!/bin/sh\necho restart >>"%s/calls.log"\n' "$work" >"$work/restart"
chmod +x "$work/bin"/* "$work/restart"
run() { : >"$work/calls.log"; OLLIE_FINISH_STATE="$work/state" OLLIE_RESTART_WINDOWS="$work/restart" PATH="$work/bin:$PATH" "$app" >"$work/out.txt" 2>&1; }

echo "== Windows not finished: restarts into it, counting"
echo 0 >"$work/state"
run
grep -q restart "$work/calls.log" || bad "it did not restart into Windows"
[[ "$(cat "$work/state")" == 1 ]] || bad "the count is not 1: $(cat "$work/state")"
run; run
[[ "$(cat "$work/state")" == 3 ]] || bad "the count is not 3 after three tries: $(cat "$work/state")"

echo "== Windows has finished: stops, no restart"
READY=1 run
grep -q restart "$work/calls.log" && bad "it restarted although Windows had finished"
[[ -e $work/state ]] && bad "the state file was not removed"
grep -q "finished setting itself up" "$work/out.txt" || bad "it did not say Windows had finished"

echo "== five tries and no ready marker: gives up"
echo 5 >"$work/state"
run
grep -q restart "$work/calls.log" && bad "it restarted a sixth time"
[[ -e $work/state ]] && bad "the state file stayed after giving up"

echo "== no part for Windows: nothing to wait for"
echo 0 >"$work/state"
NOPART=1 run
grep -q restart "$work/calls.log" && bad "it restarted with no Windows"
[[ -e $work/state ]] && bad "the state file stayed"

echo "== no state file: does nothing"
rm -f "$work/state"
run
grep -q restart "$work/calls.log" && bad "it restarted without a state file"

echo "== the service is wired the way the script expects"
svc="$here/../profile/airootfs/etc/systemd/system/ollie-windows-finish.service"
grep -q 'ConditionPathExists=/var/lib/ollie/windows-firstboot' "$svc" || bad "the service does not wait for the state file"
grep -q 'After=ollie-windows-boot.service' "$svc" || bad "the service does not run after ollie-windows-boot"
[[ -L $here/../profile/airootfs/etc/systemd/system/multi-user.target.wants/ollie-windows-finish.service ]] || bad "the service is not enabled in the image"

((fail == 0)) && echo "ALL OK" || echo "FAILED"
exit $fail
