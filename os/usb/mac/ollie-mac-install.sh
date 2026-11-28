#!/bin/bash
# Ollie OS Installer for a Mac (Apple Silicon: M1, M2, M3, M4 ... and Intel):
# puts Ollie OS on a USB drive. It looks in the Downloads folder for the Ollie OS
# ISO first (no second download); if it is not there, it downloads the newest
# one from GitHub into Downloads and keeps it there. Start the Steam Deck, Steam
# Machine, a Dell or another PC (or an Intel Mac, holding Option) from that
# drive to get Ollie OS. The drive is erased.
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
# The release called ollie-os-newest first; if it is not there (or has no ISO),
# the newest of all the releases that has an Ollie OS ISO in it.
API="${OLLIE_MAC_API:-https://api.github.com/repos/$REPO/releases/tags/$TAG}"
LIST_API="${OLLIE_MAC_LIST_API:-https://api.github.com/repos/$REPO/releases?per_page=30}"
bold=$'\e[1m' red=$'\e[31m' green=$'\e[32m' reset=$'\e[0m'
tmp="${OLLIE_MAC_TMP:-${TMPDIR:-/tmp}/ollie-os-installer}"
dl="${OLLIE_MAC_DOWNLOADS:-$HOME/Downloads}"
min_iso="${OLLIE_MAC_MIN_ISO:-1000000000}"

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

fsize() { wc -c <"$1" 2>/dev/null | tr -d ' '; }
# A real Ollie OS ISO: big enough, and "CD001" where every ISO has it (so a
# half download or some other file is not taken for one).
iso_ok() { # iso_ok FILE
    [ -f "$1" ] || return 1
    [ "$(fsize "$1")" -ge "$min_iso" ] 2>/dev/null || return 1
    [ "$(tail -c +32770 "$1" 2>/dev/null | head -c 5)" = CD001 ]
}

# --- 1. Ollie OS: in Downloads already? else the newest on GitHub ----------------------
# The newest Ollie OS in Downloads: a whole ISO file (ollie-os-...iso), or all the
# parts of one (ollie-os-...iso.part0, .part1 ...).
local_files=() local_name="" local_size=0 local_sumfile=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if iso_ok "$f"; then
        local_files=("$f") local_name="${f##*/}" local_size="$(fsize "$f")" local_sumfile="$f.sha256"
        break
    fi
done < <(ls -t "$dl"/ollie-os-*.iso 2>/dev/null)
if [ "${#local_files[@]}" -eq 0 ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        base="${f%.part0}" i=0 total=0 plist=() first_size="$(fsize "$f")" last_size=0
        while [ -f "$base.part$i" ]; do
            plist+=("$base.part$i")
            last_size="$(fsize "$base.part$i")"
            total=$((total + last_size))
            i=$((i + 1))
        done
        # All the parts: every part but the last is the same size, and the last is smaller.
        [ "$last_size" -lt "$first_size" ] 2>/dev/null || continue
        [ "$total" -ge "$min_iso" ] || continue
        [ "$(tail -c +32770 "$f" 2>/dev/null | head -c 5)" = CD001 ] || continue
        local_files=("${plist[@]}") local_name="${base##*/}" local_size="$total" local_sumfile="$base.sha256"
        break
    done < <(ls -t "$dl"/ollie-os-*.iso.part0 2>/dev/null)
fi

# GitHub's answer, one line per file: SIZE<TAB>NAME<TAB>URL (the ISO or its
# parts, and its checksum).
pick_files() { # pick_files: GitHub's JSON on stdin, no osascript: the first release that has an ISO
    # (GitHub's answer has one key per line.)
    awk -F'"' '
        $2 == "name" {n = $4}
        $2 == "size" {s = $3; gsub(/[^0-9]/, "", s)}
        $2 == "browser_download_url" && (n ~ /\.iso$/ || n ~ /\.iso\.part[0-9]+$/ || n ~ /\.iso\.sha256$/) {
            t = $4; sub(/.*\/download\//, "", t); sub(/\/.*/, "", t)
            if (n !~ /\.sha256$/ && first == "") first = t
            k++; rt[k] = t; rs[k] = s; rn[k] = n; ru[k] = $4
        }
        END {for (i = 1; i <= k; i++) if (rt[i] == first) print rs[i] "\t" rn[i] "\t" ru[i]}'
}
isos="" sumline="" size=0 reached=""
fetch_release() { # fetch_release: sets isos, sumline, size; fails if no release has an ISO
    local url json list s n u
    for url in "$API" "$LIST_API"; do
        json="$(curl -fsSL --max-time 30 "$url" 2>/dev/null)" || continue
        reached=1
        list=""
        if [ "$url" = "$API" ]; then
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
        fi
        [ -n "$list" ] || list="$(printf '%s\n' "$json" | pick_files)"
        isos="" sumline="" size=0
        while IFS=$'\t' read -r s n u; do
            [ -n "$n" ] || continue
            case "$n" in
            *.sha256) sumline="$n"$'\t'"$u" ;;
            *) isos="$isos$n"$'\t'"$u"$'\t'"$s"$'\n'; size=$((size + s)) ;;
            esac
        done <<<"$list"
        [ -n "$isos" ] && return 0
    done
    return 1
}

use_local="" keep="" fetched=""
if [ "${#local_files[@]}" -gt 0 ]; then
    echo "==> Ollie OS is already in Downloads: $local_name ($((local_size / 1000000)) MB)"
    echo "  Checking it (about a minute)..."
    have="$(cat "${local_files[@]}" | shasum -a 256 | awk '{print $1}')"
    own=""
    [ -f "$local_sumfile" ] && own="$(awk '{print tolower($1)}' "$local_sumfile" 2>/dev/null | head -n 1)"
    if [ -n "$own" ] && [ "$have" != "$own" ]; then
        echo "  It does not match its checksum file (${local_sumfile##*/}): it is damaged or not whole."
        echo "  It is not used (and not deleted)."
        local_files=()
    elif [ -n "${OLLIE_MAC_LOCAL_ONLY:-}" ]; then
        echo "  Right."
        use_local=1
    elif fetch_release; then
        fetched=1
        want=""
        [ -n "$sumline" ] && want="$(curl -fsSL --max-time 30 "${sumline#*$'\t'}" 2>/dev/null | awk '{print tolower($1)}')"
        if [ -z "$want" ]; then
            echo "  (It could not be compared with the newest one, so it is used as it is.)"
            use_local=1
        elif [ "$have" = "$want" ]; then
            echo "  Right: it is the newest Ollie OS. No download needed."
            use_local=1
        else
            echo "  The newest Ollie OS on GitHub is a different one: this one may be older."
            read -rp "  Use the one in Downloads? [Y/n] (n: download the newest) " answer
            case "$answer" in n* | N*) ;; *) use_local=1 ;; esac
        fi
    else
        echo "  (GitHub could not be asked, so it is used as it is.)"
        use_local=1
    fi
fi
if [ -n "$use_local" ]; then
    files=("${local_files[@]}")
    size="$local_size"
else
    [ -z "${OLLIE_MAC_LOCAL_ONLY:-}" ] || die "there is no good Ollie OS ISO in $dl."
    echo "==> Finding the newest Ollie OS"
    if [ -z "$fetched" ] && ! fetch_release; then
        if [ -z "$reached" ]; then
            die "could not reach GitHub. Is the internet connected? (Or put the Ollie OS .iso file in your Downloads folder first: this looks there.)"
        fi
        die "no Ollie OS file was found on GitHub yet (a new one is made about an hour after each change). Try again later."
    fi
    echo "  Ollie OS: $((size / 1000000)) MB"
fi

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

# --- 3. Does macOS let this Terminal write to the drive? (asked before the big download) ---
# New macOS versions block "dd" to a drive until Terminal has Full Disk Access.
# The first block of the drive is read and written back, the same: it changes nothing.
rdisk="${disk/disk/rdisk}"
mkdir -p "$tmp" || die "could not make a folder for the download."
ddlog="$tmp/dd.log"
echo
echo "==> Writing to a drive needs this Mac's password (the one you log in with)"
sudo -v || die "that password did not work."
diskutil unmountDisk force "$disk" >/dev/null || die "the drive could not be closed: quit what has files open on it."
echo "==> Checking that this Mac lets Terminal write to the drive"
# (The files are opened by this user, not by sudo: that is on purpose, so no file is root's.)
# shellcheck disable=SC2024
if ! { sudo dd if="$rdisk" bs=512 count=1 >"$tmp/block0" 2>"$ddlog" && sudo dd of="$rdisk" bs=512 count=1 <"$tmp/block0" 2>>"$ddlog"; }; then
    if grep -qi 'not permitted' "$ddlog" 2>/dev/null; then
        die "macOS is not letting Terminal write to a drive yet. Fix it once:
  1. Open System Settings > Privacy & Security > Full Disk Access.
  2. Turn on Terminal (press + and add it from Applications > Utilities if it is not there).
  3. Quit Terminal (Command + Q), open it again, and run this again.
Nothing was changed."
    fi
    tail -n 3 "$ddlog" 2>/dev/null
    die "the drive could not be written to (see above). Is it plugged in well? Nothing was changed."
fi
echo "  OK."

# --- 4. Download (not needed when Ollie OS was in Downloads) ---------------------------
if [ -z "$use_local" ]; then
    # It goes into Downloads and stays there (found there next time); in this
    # Mac's temporary folder if Terminal may not use Downloads.
    dldir="$dl"
    if mkdir -p "$dldir" 2>/dev/null && : >"$dldir/.ollie-os-test" 2>/dev/null; then
        rm -f "$dldir/.ollie-os-test"
        keep=1
    else
        dldir="$tmp"
    fi
    echo
    echo "==> Room on this Mac for the download"
    free_kb="$(df -Pk "$dldir" | awk 'NR == 2 {print $4}')"
    need_kb=$((size / 1024 + 300000))
    [ "${free_kb:-0}" -ge "$need_kb" ] || die "not enough free room on this Mac: the download needs $((need_kb / 1024)) MB, $((${free_kb:-0} / 1024)) MB is free."
    echo "  OK."
    echo
    echo "==> Downloading Ollie OS into $dldir (a few minutes to half an hour; if it stops, run this again: it carries on)"
    files=()
    while IFS=$'\t' read -r n u s; do
        [ -n "$n" ] || continue
        echo "  $n"
        part="$dldir/$n.part"
        have_size="$(fsize "$part")"
        [ "${have_size:-0}" -le "$s" ] || rm -f "$part"
        if [ "$(fsize "$part")" != "$s" ]; then
            curl -fL --retry 5 --retry-delay 3 -C - -o "$part" "$u" || die "the download stopped. Run this again: it carries on where it stopped."
        fi
        [ "$(fsize "$part")" = "$s" ] || die "$n is not the right size: the download was cut short. Run this again."
        files+=("$part")
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
    # Whole and checked: now they get their real names (so a half download is never taken for Ollie OS).
    whole=()
    for f in "${files[@]}"; do
        mv -f "$f" "${f%.part}" && whole+=("${f%.part}")
    done
    files=("${whole[@]}")
    if [ -n "$keep" ] && [ -n "$want" ]; then
        isoname="${sumline%%$'\t'*}"
        printf '%s  %s\n' "$want" "${isoname%.sha256}" >"$dldir/$isoname"
    fi
fi

# --- 5. Write ---------------------------------------------------------------------------
echo
echo "==> Writing Ollie OS to $disk (a few minutes; do not unplug it)"
sudo -v || die "that password did not work."
diskutil unmountDisk force "$disk" >/dev/null || die "the drive could not be closed: quit what has files open on it."
: >"$ddlog"
cat "${files[@]}" | sudo dd of="$rdisk" bs=4m 2>"$ddlog" &
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
    if grep -qi 'not permitted' "$ddlog" 2>/dev/null; then
        die "macOS is not letting Terminal write to a drive: System Settings > Privacy & Security > Full Disk Access > turn on Terminal, quit Terminal (Command + Q), open it again and run this again. The download is kept."
    fi
    die "writing to the drive stopped (see above). Is it plugged in well? The download is kept: run this again."
fi
sync
diskutil eject "$disk" >/dev/null 2>&1
rm -rf "${tmp:?}"
printf '\n%s  Done: Ollie OS is on the USB drive, and checked.%s\n' "$green$bold" "$reset"
if [ -n "$use_local" ] || [ -n "$keep" ]; then
    echo "  The Ollie OS file stays in your Downloads folder: next time this finds it there and"
    echo "  needs no download. (Delete it if you want the room back.)"
fi
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
