#!/bin/bash
# Tests the Mac installer (os/usb/mac/ollie-mac-install.sh) on Linux, with stand-ins
# for the Mac's own tools (curl, osascript, diskutil, sudo, dd, shasum, pkill, uname).
# The osascript stand-in really runs the JavaScript the script sends it (with node),
# so the part that reads GitHub's answer is the real one.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../usb/mac/ollie-mac-install.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
fails=0
check() { # check "what" command...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then echo "  ok: $what"; else echo "  FAIL: $what"; fails=$((fails + 1)); fi
}
say() { printf '\n== %s\n' "$*"; }

stub="$work/stub"
mkdir -p "$stub" "$work/assets"
# --- The stand-ins -------------------------------------------------------------------
cat >"$stub/uname" <<'EOF'
#!/bin/bash
[ "${1:-}" = -m ] && { echo arm64; exit 0; }
exec /usr/bin/uname "$@"
EOF
cat >"$stub/shasum" <<'EOF'
#!/bin/bash
exec sha256sum
EOF
cat >"$stub/osascript" <<'EOF'
#!/bin/bash
# osascript -l JavaScript -e CODE ARG...  : runs CODE's run(argv) with node
echo called >>"$WORK/osascript.log"
[ -n "${FAIL_OSASCRIPT:-}" ] && exit 1
[ "$1" = -l ] && [ "$2" = JavaScript ] && [ "$3" = -e ] || exit 2
code=$4
shift 4
exec node -e 'const code = process.argv[1]; const args = process.argv.slice(2);
eval(code + "\n;"); const out = run(args); console.log(out);' "$code" "$@"
EOF
cat >"$stub/curl" <<'EOF'
#!/bin/bash
# Serves GitHub's answer and the assets from $WORK/assets (https://dl.test/NAME).
out="" resume="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
    -o) out=$2; shift ;;
    -C) resume=$2; shift ;;
    --retry | --retry-delay) shift ;;
    -*) ;;
    *) url=$1 ;;
    esac
    shift
done
echo "curl $url" >>"$WORK/curl.log"
if [ "$url" = "$WORK/api.json" ] || [[ $url == *api.github.com* ]]; then cat "$WORK/api.json"; exit 0; fi
name="${url##*/}"
f="$WORK/assets/$name"
[ -f "$f" ] || exit 22
if [ -n "$out" ]; then
    if [ "$resume" = - ] && [ -f "$out" ]; then
        have=$(wc -c <"$out")
        echo "resume from $have" >>"$WORK/curl.log"
        tail -c +$((have + 1)) "$f" >>"$out"
    else
        cp "$f" "$out"
    fi
else
    cat "$f"
fi
EOF
cat >"$stub/diskutil" <<'EOF'
#!/bin/bash
echo "diskutil $*" >>"$WORK/diskutil.log"
case "$1 $2 $3" in
"list external physical")
    [ -n "${NO_DISKS:-}" ] && exit 0
    cat <<'OUT'
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *64.0 GB    disk4
   1:                 DOS_FAT_32 STICK                   64.0 GB    disk4s1

/dev/disk5 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *4.5 TB     disk5
OUT
    ;;
esac
case "$1 $2" in
"info /dev/disk4")
    echo "   Media Name:                SanDisk Ultra"
    if [ -n "${SMALL:-}" ]; then
        echo "   Disk Size:                 1.0 MB (1000000 Bytes) (exactly 1953 512-Byte-Units)"
    else
        echo "   Disk Size:                 64.0 GB (64023257088 Bytes) (exactly 125045424 512-Byte-Units)"
    fi
    ;;
"info /dev/disk5")
    echo "   Media Name:                Seagate Expansion Desk"
    echo "   Total Size:                4.5 TB (4500000000000 Bytes) (exactly 8789062500 512-Byte-Units)"
    ;;
esac
exit 0
EOF
cat >"$stub/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$WORK/sudo.log"
[ "${1:-}" = -n ] && shift
[ "${1:-}" = -v ] && exit "${SUDO_RC:-0}"
exec "$@"
EOF
cat >"$stub/pkill" <<'EOF'
#!/bin/bash
echo "pkill $*" >>"$WORK/pkill.log"
[ -f "$WORK/dd.pid" ] && kill -USR1 "$(cat "$WORK/dd.pid")" 2>/dev/null
exit 0
EOF
cat >"$stub/dd" <<'EOF'
#!/bin/bash
# The drive is a file; asked how far it is (SIGUSR1), it answers the way the Mac's dd does.
args=()
for a in "$@"; do
    case "$a" in
    of=/dev/rdisk*) of="$WORK/${a#of=/dev/}.img"; args+=("of=$of" conv=notrunc) ;;
    if=/dev/rdisk*) in="$WORK/${a#if=/dev/}.img"; [ -f "$in" ] || head -c 1048576 /dev/zero >"$in"; args+=("if=$in") ;;
    bs=4m) args+=(bs=4M) ;;
    *) args+=("$a") ;;
    esac
done
if [ -n "${DD_DENY:-}" ]; then
    echo "dd: /dev/rdisk4: Operation not permitted" >&2
    echo "dd-denied" >>"$WORK/dd.log"
    exit 1
fi
echo "dd $*" >>"$WORK/dd.log"
echo $$ >"$WORK/dd.pid"
trap 'echo "$(wc -c <"$of" 2>/dev/null) bytes transferred in 1.0 secs (1 bytes/sec)" >&2' USR1
/bin/dd "${args[@]}" 2>/dev/null
rc=$?
# (a drive that takes a while: short sleeps, so the answer to SIGUSR1 comes at once)
if [ -n "${SLOW:-}" ]; then
    end=$((SECONDS + SLOW))
    while [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
fi
exit "$rc"
EOF
chmod +x "$stub"/*

# --- Fake release ------------------------------------------------------------------
make_json() { # make_json NAME:SIZE ...  (GitHub's answer: one key per line)
    python3 - "$@" <<'PY'
import json, sys
assets = []
for a in sys.argv[1:]:
    n, s = a.rsplit(":", 1)
    assets.append({"url": "https://api.github.com/x", "id": 1, "name": n, "label": "",
                   "uploader": {"login": "github-actions[bot]", "id": 2},
                   "content_type": "application/octet-stream", "state": "uploaded", "size": int(s),
                   "download_count": 0, "browser_download_url": "https://dl.test/" + n})
print(json.dumps({"tag_name": "ollie-os-newest", "name": "Ollie OS (2026-11-21)", "assets": assets}, indent=2))
PY
}
head -c 3000000 /dev/urandom >"$work/iso"
export WORK="$work"
reset_assets() {
    rm -rf "${work:?}/assets" "${work:?}/tmp" "${work:?}/dd.pid"
    rm -f "${work:?}"/rdisk*.img "${work:?}"/*.log
    mkdir -p "$work/assets"
}
iso_name=ollie-os-2026.11.21-x86_64.iso
single() {
    reset_assets
    cp "$work/iso" "$work/assets/$iso_name"
    (cd "$work/assets" && sha256sum "$iso_name" >"$iso_name.sha256")
    make_json "$iso_name:3000000" "$iso_name.sha256:97" "Ollie-OS-Installer-Mac.dmg:100" >"$work/api.json"
}
parts() {
    reset_assets
    split -b 1700000 -d -a 1 "$work/iso" "$work/assets/$iso_name.part"
    (cd "$work" && sha256sum iso | sed "s/ iso\$/ $iso_name/" >"assets/$iso_name.sha256")
    make_json "$iso_name.part1:1300000" "$iso_name.part0:1700000" "$iso_name.sha256:97" >"$work/api.json"
}
run() { # run ANSWERS... : the script, answering its questions in turn
    printf '%s\n' "$@" "" "" | PATH="$stub:$PATH" OLLIE_MAC_TEST=1 OLLIE_MAC_API="$work/api.json" OLLIE_MAC_TMP="$work/tmp" bash "$script" >"$work/out.txt" 2>&1
}

say "one ISO file: found, downloaded, checked and written to the drive"
single
run 1 ERASE
check "it finishes with Done" grep -q 'Done: Ollie OS is on the USB drive' "$work/out.txt"
check "the drive got exactly the ISO" cmp -s "$work/iso" "$work/rdisk4.img"
check "it says the Apple chip is fine" grep -q 'Apple chip' "$work/out.txt"
check "the drive was closed first and ejected after" bash -c "grep -q 'unmountDisk force /dev/disk4' '$work/diskutil.log' && grep -q 'eject /dev/disk4' '$work/diskutil.log'"
check "it wrote to the raw device with 4 MB blocks" grep -q 'of=/dev/rdisk4 bs=4m' "$work/dd.log"
check "the download folder is gone" test ! -d "$work/tmp"
check "the Installer .dmg in the release is not taken for the ISO" bash -c "! grep -q 'Installer-Mac' '$work/curl.log'"

say "the answer from GitHub read without osascript (a plain text way)"
single
FAIL_OSASCRIPT=1 run 1 ERASE
check "osascript was tried (and failed), so the plain way was used" test -s "$work/osascript.log"
check "it still finishes" grep -q 'Done: Ollie OS is on the USB drive' "$work/out.txt"
check "and the drive has the ISO" cmp -s "$work/iso" "$work/rdisk4.img"

say "an ISO in two parts: put together on the drive, in order"
parts
run 1 ERASE
check "it finishes" grep -q 'Done: Ollie OS is on the USB drive' "$work/out.txt"
check "the drive has the whole ISO" cmp -s "$work/iso" "$work/rdisk4.img"

say "a download that stopped half way carries on"
single
mkdir -p "$work/tmp"
head -c 1000000 "$work/iso" >"$work/tmp/$iso_name"
run 1 ERASE
check "it resumed from where it was" grep -q 'resume from 1000000' "$work/curl.log"
check "and the drive has the ISO" cmp -s "$work/iso" "$work/rdisk4.img"

say "a file that is already whole is not downloaded again"
single
mkdir -p "$work/tmp"
cp "$work/iso" "$work/tmp/$iso_name"
run 1 ERASE
check "the ISO itself was not fetched" bash -c "! grep -q 'dl.test/$iso_name\$' '$work/curl.log'"
check "the drive has the ISO" cmp -s "$work/iso" "$work/rdisk4.img"

say "a damaged download: nothing is written, the file goes"
single
echo "0000000000000000000000000000000000000000000000000000000000000000  $iso_name" >"$work/assets/$iso_name.sha256"
run 1 ERASE
check "it says the checksum is wrong" grep -q 'damaged on the way' "$work/out.txt"
check "nothing was written to the drive (no write of the ISO)" bash -c "! grep -q 'bs=4m' '$work/dd.log'"
check "the damaged file was removed" test ! -e "$work/tmp/$iso_name"

say "not typing ERASE changes nothing"
single
run 1 nope
check "cancelled" grep -q 'cancelled; nothing was changed' "$work/out.txt"
check "nothing written" test ! -e "$work/rdisk4.img"
check "nothing downloaded" test ! -e "$work/tmp/$iso_name"

say "a big storage drive (4.5 TB) must be named as well; the wrong name changes nothing"
single
run 2 nope
check "it warns it is a big drive" grep -q 'looks like a big storage drive' "$work/out.txt"
check "cancelled" grep -q 'cancelled; nothing was changed' "$work/out.txt"
check "nothing written" test ! -e "$work/rdisk5.img"
check "it did not go on to download" test ! -d "$work/tmp"

say "the big drive, named right, is allowed (the person said so twice)"
single
run 2 disk5 ERASE
check "it writes" grep -q 'Done: Ollie OS is on the USB drive' "$work/out.txt"
check "the 4.5 TB size was read from 'Total Size:'" grep -q '4.5 TB' "$work/out.txt"

say "no USB drive plugged in"
single
NO_DISKS=1 run 1
check "it says to plug one in" grep -q 'no USB drive was found' "$work/out.txt"

say "a drive too small"
single
SMALL=1 run 1 ERASE
check "it says the drive is too small" grep -q 'too small for Ollie OS' "$work/out.txt"
check "nothing written" test ! -e "$work/rdisk4.img"

say "no ISO in the release yet"
reset_assets
make_json "Ollie-OS-Installer-Mac.dmg:100" >"$work/api.json"
run 1 ERASE
check "it says to try later" grep -q 'has no ISO in it yet' "$work/out.txt"

say "the password does not work"
single
SUDO_RC=1 run 1 ERASE
check "it says so and writes nothing" bash -c "grep -q 'that password did not work' '$work/out.txt' && test ! -e '$work/rdisk4.img'"

say "progress while writing (the drive takes a while)"
single
SLOW=7 run 1 ERASE
check "it showed a percentage" grep -q '%' "$work/out.txt"
check "it never asks for the password in the middle (only sudo -n)" bash -c "! grep -E '^sudo pkill' '$work/sudo.log'"
check "it still wrote the whole ISO" cmp -s "$work/iso" "$work/rdisk4.img"

say "macOS does not let Terminal write to drives yet (Full Disk Access): said before anything is downloaded"
single
DD_DENY=1 run 1 ERASE
check "it says what to switch on" grep -q 'Full Disk Access' "$work/out.txt"
check "it says nothing was changed" grep -q 'Nothing was changed' "$work/out.txt"
check "nothing was downloaded" test ! -e "$work/tmp/$iso_name"
check "nothing was written (no write of the ISO)" bash -c "! grep -q 'bs=4m' '$work/dd.log'"

say "the check of the drive changes nothing on it (it writes back the block it read)"
single
head -c 2000000 /dev/urandom >"$work/before.img"
cp "$work/before.img" "$work/rdisk4.img"
rm -f "${work:?}/assets/$iso_name"   # (so the download stops after the check)
run 1 ERASE
check "the download stopped, as made to" grep -q 'the download stopped' "$work/out.txt"
check "the check ran first" grep -q 'Checking that this Mac lets Terminal write' "$work/out.txt"
check "the drive is exactly as it was" cmp -s "$work/before.img" "$work/rdisk4.img"

say "the script has no bash 4 things (macOS has bash 3.2)"
check "no mapfile / readarray" bash -c "! grep -v '^[[:space:]]*#' '$script' | grep -nE '(^|[^a-z_])(mapfile|readarray)([^a-z_]|\$)'"
check "no lowercase/uppercase expansions" bash -c "! grep -v '^[[:space:]]*#' '$script' | grep -nE '\\\$\\{[a-zA-Z_]+(,,|\\^\\^)'"
check "no associative arrays" bash -c "! grep -nE 'declare -A|local -A' '$script'"
check "no set -u (an empty list is an error in bash 3.2)" bash -c "! grep -nE '^set .*-[a-z]*u' '$script'"
check "no &>> or |& (bash 4)" bash -c "! grep -nE '&>>|\\|&' '$script'"

echo
if ((fails)); then echo "FAILED: $fails"; exit 1; fi
echo "ALL OK"
