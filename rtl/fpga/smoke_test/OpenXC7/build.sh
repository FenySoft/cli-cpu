#!/bin/bash
# hu: OpenXC7 build indító script WSL-ben.
#     Beállítja a PATH-t, biztosítja az S: meghajtó mount-olását,
#     majd meghívja a make-et.
# en: OpenXC7 build launcher script for WSL.
#     Sets PATH, ensures S: drive is mounted, then invokes make.

set -e
export PATH=/snap/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# hu: S: meghajtó mount-olása (ha még nincs). A WSL nem auto-mount-olja
#     a nem-alapértelmezett meghajtókat, ezért itt biztosítjuk.
# en: Mount S: drive (if not yet mounted). WSL doesn't auto-mount non-default
#     drives, so we ensure it here.
if [ ! -d /mnt/s/github.com ]; then
    sudo mkdir -p /mnt/s
    sudo mount -t drvfs S: /mnt/s
fi

cd "$(dirname "$0")"

# Argumentumok továbbadása a make-nek (pl. "check-env", "all", "clean")
make "$@"
