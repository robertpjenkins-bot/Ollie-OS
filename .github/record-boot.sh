#!/bin/bash
# Films Ollie OS starting up, in a virtual machine that starts like a real PC
# (UEFI), with its screen (4 pictures a second) and its sound:
#   1. from the USB drive (the ISO): the boot menu, then the first start, up to
#      the Welcome window;
#   2. installed on a disk (the installer runs by itself first, as the build's
#      install test does): switching on, the start-up animation, the desktop.
#   .github/record-boot.sh ISO OUTDIR   ->  OUTDIR/ollie-os-start-up.mp4
set -uo pipefail
iso="$(realpath "${1:?usage: record-boot.sh ISO OUTDIR}")"
out="$(realpath -m "${2:?}")"
mkdir -p "$out"
for t in qemu-system-x86_64 socat ffmpeg convert xorriso; do
    command -v "$t" >/dev/null || { echo "needs $t"; exit 1; }
done
accel=tcg cpu=max
if [[ -w /dev/kvm ]]; then accel=kvm cpu=host; fi
code="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}" vars="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}"
fps="${FPS:-4}" secs="${SECONDS_EACH:-150}"
bold=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf plain=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
W=1280 H=800
log() { printf '\n== %s\n' "$*"; }

# The PC: UEFI (its settings in VARS), 2 cores, 4 GB, the screen the tests use.
pc() { # pc VARS ARGS...
    local v=$1
    shift
    qemu-system-x86_64 -machine q35,accel=$accel -cpu $cpu -smp 2 -m 4096 \
        -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$v" \
        -device virtio-vga -display none -nic user,model=virtio-net-pci "$@"
}

# film NAME ARGS...: starts the PC and takes $fps pictures a second of its
# screen for $secs seconds (and records its sound in NAME.wav).
film() {
    local name=$1 dir="$out/$1" mon="$out/$1.sock" pid start now next n=0 pic
    shift
    mkdir -p "$dir"
    rm -f "$mon" "$dir"/*.ppm "$dir/times"
    pc "$out/$name.vars" -monitor unix:"$mon",server,nowait \
        -audiodev wav,id=snd0,path="$out/$name.wav" -device ich9-intel-hda -device hda-output,audiodev=snd0 "$@" &
    pid=$!
    start=$(date +%s%N)
    next=$start
    while kill -0 "$pid" 2>/dev/null; do
        now=$(date +%s%N)
        (((now - start) / 1000000000 >= secs)) && break
        pic="$dir/$(printf %05d "$n").ppm"
        if printf 'screendump %s\n' "$pic" | socat - UNIX-CONNECT:"$mon" >/dev/null 2>&1 && [[ -s $pic ]]; then
            echo "$n $(((now - start) / 1000000))" >>"$dir/times"
            n=$((n + 1))
        fi
        next=$((next + 1000000000 / fps))
        now=$(date +%s%N)
        ((next > now)) && sleep "$(awk -v d=$((next - now)) 'BEGIN {printf "%.3f", d / 1e9}')"
    done
    printf 'quit\n' | socat - UNIX-CONNECT:"$mon" >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill "$pid" 2>/dev/null
    wait "$pid"
    echo "$name: $n pictures in $secs seconds"
}

# The moment (ms) a picture first shows the first-start Welcome window, read
# with tesseract; the film ends a few seconds after it. Empty if not found.
welcome_at() { # welcome_at NAME
    local dir="$out/$1" f t
    command -v tesseract >/dev/null || return 0
    while read -r f t; do
        ((t < 15000 || f % 8)) && continue
        convert "$dir/$(printf %05d "$f").ppm" -colorspace Gray -resize 200% "$out/ocr.png" 2>/dev/null || continue
        if tesseract "$out/ocr.png" - 2>/dev/null | grep -qiE 'Welcome to Ollie|Create your username'; then
            echo "$t"
            return 0
        fi
    done <"$dir/times"
}

# encode NAME: the pictures at the moments they were taken, with the sound,
# as NAME.mp4 (the last picture stays 3 seconds).
encode() {
    local name=$1 dir="$out/$1" list="$out/$1.list" prev="" pt=0 f t img stop=""
    stop="$(welcome_at "$name")"
    [[ -n $stop ]] && echo "$name: the Welcome window shows at $((stop / 1000)) s" && stop=$((stop + 7000))
    : >"$list"
    while read -r f t; do
        [[ -n $stop ]] && ((t > stop)) && break
        img="$dir/$(printf %05d "$f").jpg"
        convert "$dir/$(printf %05d "$f").ppm" -quality 92 "$img" 2>/dev/null || continue
        [[ -n $prev ]] && printf "file '%s'\nduration %s\n" "$prev" "$(awk -v a="$pt" -v b="$t" 'BEGIN {printf "%.3f", (b - a) / 1000}')" >>"$list"
        prev="$img" pt=$t
    done <"$dir/times"
    [[ -n $prev ]] || { echo "$name: no pictures"; return 1; }
    printf "file '%s'\nduration 3\nfile '%s'\n" "$prev" "$prev" >>"$list"
    local audio=(-f lavfi -i "anullsrc=r=44100:cl=stereo")
    [[ -s "$out/$name.wav" ]] && audio=(-i "$out/$name.wav")
    ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" "${audio[@]}" \
        -vf "scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:black,fps=30,format=yuv420p" \
        -af "aresample=44100,apad" -ac 2 -map 0:v -map 1:a -shortest \
        -c:v libx264 -preset medium -crf 22 -c:a aac -b:a 160k "$out/$name.mp4"
}

# card FILE SECONDS TITLE LINE: a teal title card (no ":" or "'" in the words).
card() {
    ffmpeg -y -loglevel error -f lavfi -i "color=c=0x0E6F70:s=${W}x${H}:d=$2:r=30" -f lavfi -i "anullsrc=r=44100:cl=stereo" \
        -vf "drawtext=fontfile=$bold:text='$3':fontsize=78:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-55,drawtext=fontfile=$plain:text='$4':fontsize=40:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+45,format=yuv420p" \
        -t "$2" -ac 2 -c:v libx264 -preset medium -crf 22 -c:a aac -b:a 160k -shortest "$1"
}

version="${OLLIE_VERSION:-}" # (Ollie OS's own number, for the first card)

log "1. Starting from the USB drive"
cp "$vars" "$out/usb.vars"
film usb -cdrom "$iso"

log "2. Installing onto a disk (the installer by itself), then starting the installed Ollie OS"
xorriso -osirrox on -indev "$iso" \
    -extract /arch/boot/x86_64/vmlinuz-linux "$out/vmlinuz-linux" \
    -extract /arch/boot/x86_64/initramfs-linux.img "$out/initramfs-linux.img" \
    -extract /loader/entries "$out/entries" >/dev/null 2>&1
options="$(awk '$1 == "options" {$1 = ""; print substr($0, 2)}' "$(ls "$out"/entries/*.conf | head -n1)")"
truncate -s 30G "$out/disk.img"
cp "$vars" "$out/installed.vars"
timeout "${INSTALL_TIMEOUT:-2400}" qemu-system-x86_64 -machine q35,accel=$accel -cpu $cpu -smp 2 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$out/installed.vars" \
    -kernel "$out/vmlinuz-linux" -initrd "$out/initramfs-linux.img" \
    -append "$options console=tty0 console=ttyS0,115200 ollie.selftest=install" \
    -cdrom "$iso" -drive "file=$out/disk.img,format=raw,if=virtio" -device virtio-vga -display none \
    -serial file:"$out/install.log" -nic user,model=virtio-net-pci
installed=""
if grep -aq 'OLLIE-INSTALL-TEST: installer finished' "$out/install.log"; then
    installed=1
    film installed -drive "file=$out/disk.img,format=raw,if=virtio"
else
    echo "(the installer did not finish: the film has the USB part only)"
    grep -a 'OLLIE-INSTALL-TEST' "$out/install.log" | tail -n 20
fi

log "Making the film"
parts=()
card "$out/c0.mp4" 3.5 "Ollie OS${version:+ $version}" "Starting up, as it really looks" && parts+=("$out/c0.mp4")
card "$out/c1.mp4" 2.5 "From the USB drive" "The first start" && encode usb && parts+=("$out/c1.mp4" "$out/usb.mp4")
if [[ -n $installed ]]; then
    card "$out/c2.mp4" 2.5 "Installed on the computer" "Switching it on" && encode installed && parts+=("$out/c2.mp4" "$out/installed.mp4")
fi
card "$out/c9.mp4" 3 "Ollie OS" "Made by biobro" && parts+=("$out/c9.mp4")
: >"$out/all.list"
for p in "${parts[@]}"; do printf "file '%s'\n" "$p" >>"$out/all.list"; done
ffmpeg -y -loglevel error -f concat -safe 0 -i "$out/all.list" -c copy -movflags +faststart "$out/ollie-os-start-up.mp4"
ls -la "$out/ollie-os-start-up.mp4"
ffprobe -v error -show_entries format=duration -of default=nw=1 "$out/ollie-os-start-up.mp4"
