#!/bin/bash
# Build Ollie OS Builder for Windows (os/out/Ollie-OS-Builder-Windows.exe):
# the Ollie OS recipe from the committed tree, inside the program. Needs Go.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="${OUTDIR:-$root/os/out}"
mkdir -p "$out"
(cd "$root" && git archive --format=tar.gz -o "$here/ollie-os-source.tar.gz" HEAD \
    go.mod cmd internal packaging LICENSE THIRD-PARTY-NOTICES.md os/build.sh os/build-from-arch-iso.sh os/build-drive.sh os/build-drive-files.sh os/drive-common.sh os/secureboot-iso.sh os/ollie-write os/art os/profile)
(cd "$here" && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$out/Ollie-OS-Builder-Windows.exe" .)
rm -f "$here/ollie-os-source.tar.gz"
