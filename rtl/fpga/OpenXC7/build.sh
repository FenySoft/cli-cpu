#!/bin/bash
# hu: CLI-CPU F2.7 Sub5 — OpenXC7 build indito script WSL-ben.
#     A smoke_test/OpenXC7/build.sh mintajat koveti: PATH beallitas,
#     S: meghajto drvfs mount (ha nincs), majd `make` hivas a teljes
#     cilcpu_a7lite_board build-hez. Argumentumok tovabbadva a make-nek.
# en: CLI-CPU F2.7 Sub5 — OpenXC7 build launcher for WSL.
#     Mirrors smoke_test/OpenXC7/build.sh: sets PATH, mounts S: drvfs
#     (if needed), then invokes `make` for the full cilcpu_a7lite_board
#     build. Arguments are forwarded to make.

set -e
export PATH=/snap/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# hu: S: meghajto mount-olasa (ha meg nincs). A WSL nem auto-mount-olja
#     a nem-alapertelmezett meghajtokat.
# en: Mount S: drive (if not yet mounted). WSL doesn't auto-mount
#     non-default drives.
if [ ! -d /mnt/s/github.com ]; then
    sudo mkdir -p /mnt/s
    sudo mount -t drvfs S: /mnt/s
fi

cd "$(dirname "$0")"

# Argumentumok tovabbadasa a make-nek (pl. "check-env", "all", "clean")
make "$@"
