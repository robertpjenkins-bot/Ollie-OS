#!/bin/bash
# Ollie OS Installer for a Mac (Apple Silicon: M1, M2, M3, M4 ... and Intel):
# downloads the newest Ollie OS from its GitHub release and writes it onto a
# USB drive. Start the Steam Deck, Steam Machine, a Dell or another PC (or an
# Intel Mac, holding Option) from that drive to get Ollie OS. The drive is erased.
#
# A Mac with an Apple chip cannot start Ollie OS itself; it only makes the
# drive for another computer. Nothing here needs Docker, Rosetta or Xcode: it
# uses only what comes with macOS (bash, curl, osascript, diskutil, dd, shasum).
# Writing to a drive asks for this Mac's password (macOS's own rule).
#
# Two ways to start it:
#   - double-click this file (macOS may ask first: see "Read me.txt"), or
#   - paste this in Terminal (nothing for macOS to block):
#       bash <(curl -fsSL https://raw.githubusercontent.com/robertpjenkins-bot/Ollie-OS/claude/fervent-gates-cs7smv/os/usb/mac/ollie-mac-install.sh)
#
# Written for the bash that comes with macOS (3.2): no "set -u" (an empty list
# is an error there), no mapfile, no ${x,,}.
set -o pipefail
REPO="${OLLIE_MAC_REPO:-robertpjenkins-bot/Ollie-OS}" TAG="${OLLIE_MAC_TAG:-ollie-os-newest}"
API="${OLLIE_MAC_API:-https://api.github.com/repos/$REPO/releases/tags/$TAG}"
bold=$'\e[1m' red=$'\e[31m' green=$'\e[32m' reset=$'\e[0m'
tmp="${OLLIE_MAC_TMP:-${TMPDIR:-/tmp}/ollie-os-installer}"

die() {
    printf '\n%sError:%s %s\n\nPress Enter to close.' "$red$bold" "$reset" "$*"
    read -r _
    exit 1
}
# Started with "curl ... | bash": the questions come from the keyboard, not the pipe.
if [ ! -t 0 ] && [ -z "${OLLIE_MAC_TEST:-}" ]; then
    { exec </dev/tty; } 2>/dev/null || die "this needs a Terminal window to ask its questions."
fi

printf '\n%s  Ollie OS Installer%s  (puts Ollie OS on a USB drive)\n' "$bold" "$reset"
chip="$(uname -m)"
if [ "$chip" = arm64 ]; then
    echo "  This Mac has an Apple chip. That is fine: this makes the USB drive for another"
    echo "  computer (Steam Deck, Steam Machine, a PC or an Intel Mac). Ollie OS does not"
    echo "  start on this Mac itself."
fi
echo

# --- 1. The newest Ollie OS --------------------------------------------------------
echo "==> Finding the newest Ollie OS"
json="$(curl -fsSL "$API")" || die "could not reach GitHub. Is the internet connected?"
# One line per file: SIZE<TAB>NAME<TAB>URL (the ISO, or its parts, and its checksum).
list="$(osascript -l JavaScript -e '
function run(argv) {
  const a = JSON.parse(argv[0]).assets;
  const iso = a.filter(x => /\.iso$/.test(x.name));
  const parts = a.filter(x => /\.iso\.part\d+$/.test(x.name))
    .sort((x, y) => +x.name.match(/\d+$/)[0] - +y.name.match(/\d+$/)[0]);
  const sum = a.filter(x => /\.iso\.sha256$/.test(x.name));
  return (iso.length ? iso : parts).concat(sum)
    .map(x => x.size + "\t" + x.name + "\t" + x.browser_download_url).join("\n");
}' "$json" 2>/dev/null)"
if [ -z "$list" ]; then
    # (Without osascript's help: GitHub's answer has one key per line.)
    list="$(printf '%s\n' "$json" | awk -F'"' '
        $2 == "name" {n = $4}
        $2 == "size" {s = $3; gsub(/[^0-9]/, "", s)}
        $2 == "browser_download_url" && (n ~ /\.iso$/ || n ~ /\.iso\.part[0-9]+$/ || n ~ /\.iso\.sha256$/) {print s "\t" n "\t" $4}')"
fi
isos="" sumline="" size=0
while IFS=$'\t' read -r s n u; do
    [ -n "$n" ] || continue
    case "$n" in
    *.sha256) sumline="$n"$'\t'"$u" ;;
    *) isos="$isos$n"$'\t'"$u"$'\t'"$s"$'\n'; size=$((size + s)) ;;
    esac
done <<<"$list"
[ -n "$isos" ] || die "the newest Ollie OS release has no ISO in it yet. Try again in a few minutes."
echo "  Ollie OS: $((size / 1000000)) MB"

# --- 2. Which drive ------------------------------------------------------------------
echo
echo "==> USB drives (everything on the one you pick is erased)"
disks=()
while read -r d; do
    [[ $d == /dev/disk* ]] || continue
    disks+=("$d")
    info="$(diskutil info "$d" 2>/dev/null)"
    name="$(sed -n 's/^ *Media Name: *//p' <<<"$info" | head -n 1)"
    dsize="$(sed -nE 's/^ *(Disk|Total) Size: *([^(]*)\(.*/\2/p' <<<"$info" | head -n 1)"
    printf '  %d) %-12s %s  %s\n' "${#disks[@]}" "$d" "${dsize:-?}" "${name:-}"
done < <(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1}')
[ "${#disks[@]}" -gt 0 ] || die "no USB drive was found. Plug in a USB drive (8 GB or more), then run this again."
echo
read -rp "Put Ollie OS on which drive? [1-${#disks[@]}] " pick
[[ $pick =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#disks[@]}" ] || die "no such drive; nothing was changed."
disk="${disks[$((pick - 1))]}"
bytes="$(diskutil info "$disk" 2>/dev/null | sed -nE 's/.*(Disk|Total) Size:.*\(([0-9]+) Bytes\).*/\2/p' | head -n 1)"
[ -z "$bytes" ] || [ "$bytes" -ge "$size" ] || die "$disk is too small for Ollie OS (it needs $((size / 1000000)) MB)."
printf '\n%sEVERYTHING on %s will be erased.%s\n' "$red$bold" "$disk" "$reset"
# A big drive is a storage drive, not a USB stick: ask again, by its name.
if [ -n "$bytes" ] && [ "$bytes" -gt 400000000000 ]; then
    printf '%s%s is %d GB: that looks like a big storage drive (maybe the one Ollie OS runs from), not a USB stick.%s\n' "$red$bold" "$disk" $((bytes / 1000000000)) "$reset"
    read -rp "To erase it anyway, type its name (${disk#/dev/}): " answer
    [ "$answer" = "${disk#/dev/}" ] || die "cancelled; nothing was changed."
fi
read -rp "Type ERASE to put Ollie OS on it: " answer
[ "$answer" = ERASE ] || die "cancelled; nothing was changed."

# --- 3. Download (to this Mac first, checked, then written) --------------------------
echo
echo "==> Room on this Mac for the download"
mkdir -p "$tmp" || die "could not make a folder for the download."
free_kb="$(df -Pk "$tmp" | awk 'NR == 2 {print $4}')"
need_kb=$((size / 1024 + 300000))
[ "${free_kb:-0}" -ge "$need_kb" ] || die "not enough free room on this Mac: the download needs $((need_kb / 1024)) MB, $((${free_kb:-0} / 1024)) MB is free."
echo "  OK."
echo
echo "==> Downloading Ollie OS (a few minutes to half an hour; if it stops, run this again: it carries on)"
files=()
while IFS=$'\t' read -r n u s; do
    [ -n "$n" ] || continue
    echo "  $n"
    have_size="$(wc -c <"$tmp/$n" 2>/dev/null | tr -d ' ')"
    [ "${have_size:-0}" -le "$s" ] || rm -f "$tmp/$n"
    if [ "$(wc -c <"$tmp/$n" 2>/dev/null | tr -d ' ')" != "$s" ]; then
        curl -fL --retry 5 --retry-delay 3 -C - -o "$tmp/$n" "$u" || die "the download stopped. Run this again: it carries on where it stopped."
    fi
    [ "$(wc -c <"$tmp/$n" | tr -d ' ')" = "$s" ] || die "$n is not the right size: the download was cut short. Run this again."
    files+=("$tmp/$n")
done <<<"$isos"
if [ -n "$sumline" ]; then
    echo "==> Checking the download"
    want="$(curl -fsSL "${sumline#*$'\t'}" | awk '{print tolower($1)}')"
    have="$(cat "${files[@]}" | shasum -a 256 | awk '{print $1}')"
    if [ -n "$want" ] && [ "$have" != "$want" ]; then
        rm -f "${files[@]}"
        die "the download was damaged on the way (checksum). It was removed: run this again."
    fi
    echo "  Right."
fi

# --- 4. Write ---------------------------------------------------------------------------
echo
echo "==> Writing to a drive needs this Mac's password (the one you log in with)"
sudo -v || die "that password did not work."
diskutil unmountDisk force "$disk" >/dev/null || die "the drive could not be closed: quit what has files open on it."
echo
echo "==> Writing Ollie OS to $disk (a few minutes; do not unplug it)"
ddlog="$tmp/dd.log"
: >"$ddlog"
cat "${files[@]}" | sudo dd of="${disk/disk/rdisk}" bs=4m 2>"$ddlog" &
wpid=$!
start=$(date +%s)
# dd tells how far it is when asked (SIGINFO); asking is harmless if it does not answer.
while kill -0 "$wpid" 2>/dev/null; do
    sleep 4
    sudo -n -v 2>/dev/null # (keeps the password's few minutes going; never asks again)
    sudo -n pkill -INFO -x dd 2>/dev/null
    sleep 1
    done_bytes="$(awk '/bytes transferred/ {n = $1} END {print n + 0}' "$ddlog" 2>/dev/null)"
    if [ "${done_bytes:-0}" -gt 0 ] 2>/dev/null; then
        printf '\r  %d%%  (%d MB of %d MB, %d seconds)   ' $((done_bytes * 100 / size)) $((done_bytes / 1000000)) $((size / 1000000)) $(($(date +%s) - start))
    else
        printf '\r  writing...  (%d seconds)   ' $(($(date +%s) - start))
    fi
done
wait "$wpid"
rc=$?
printf '\n'
if [ "$rc" -ne 0 ]; then
    tail -n 3 "$ddlog" 2>/dev/null
    die "writing to the drive stopped (see above). Is it plugged in well? The download is kept: run this again."
fi
sync
diskutil eject "$disk" >/dev/null 2>&1
rm -rf "${tmp:?}"
printf '\n%s  Done: Ollie OS is on the USB drive, and checked.%s\n' "$green$bold" "$reset"
cat <<'MSG'

  Take the USB drive out and start the computer from it:
    Steam Deck:   hold Volume Down, press Power, pick the USB drive.
    Steam Machine: hold Volume Down.     Dell and most PCs: tap F12.
    Intel Mac:    hold Option and pick "EFI Boot".
  Then press Install Ollie OS.
  (If this Mac says the drive is not readable, click Eject or Ignore: that is Ollie OS.)
  Secure Boot on (most PCs)? The first time, a blue screen says "Verification
  failed": press Enter, then any key quickly, then pick Enroll key from disk,
  OLLIE_OS, OLLIE-OS-KEY.cer, Continue, Yes, Reboot. Only once on each computer.
  A PC with Windows? Write down its BitLocker recovery key first
  (aka.ms/myrecoverykey): Windows may ask for it after starting from a USB.

Press Enter to close.
MSG
read -r _
