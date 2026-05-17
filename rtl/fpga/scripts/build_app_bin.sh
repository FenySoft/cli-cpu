#!/bin/bash
# hu: CLI-CPU F2.7 Sub5 — CIL-T0 alkalmazas-binaris (.t0) build script.
#     A teljes toolchain: dotnet build -> Roslyn .dll -> TCliCpuLinker
#     link -> .t0. A kimenet a write_cfgmem flow altal vart helyre kerul
#     (alapertelmezesben rtl/fpga/Vivado/build/app.t0). A linker-hivas a
#     rtl/tb/test_a7lite_board_fib.py-ben hasznalt parancs HW-megfeleloje
#     (--class Math --method FibonacciIterative), igy a HW a sim-mel BIT-
#     azonos binarist futtat.
# en: CLI-CPU F2.7 Sub5 — CIL-T0 application binary (.t0) build script.
#     Full toolchain: dotnet build -> Roslyn .dll -> TCliCpuLinker link
#     -> .t0. Output goes where the write_cfgmem flow expects it. The
#     linker invocation is the HW counterpart of the command used in
#     rtl/tb/test_a7lite_board_fib.py, so HW runs the BIT-identical
#     binary as the sim.
#
# Hasznalat / Usage:
#   build_app_bin.sh [METHOD] [N] [OUT]
#     METHOD : a linkelendo metodus (default: FibonacciIterative)
#     N      : a boot argumentum erteke — CSAK informatikvkent ide irjuk,
#              a tenyleges N a BOOT_ARG_VALUE generic (Vivado create_project
#              .tcl-ben / OpenXC7 -G); alapertelmezett 20 (default: 20)
#     OUT    : kimeneti .t0 utvonal
#              (default: <repo>/rtl/fpga/Vivado/build/app.t0)
#
# Pelda / Example:
#   ./build_app_bin.sh                       # FibonacciIterative, N=20
#   ./build_app_bin.sh Factorial 5 /tmp/f.t0 # Factorial, N=5

set -e

METHOD="${1:-FibonacciIterative}"
ARG_N="${2:-20}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT="${3:-$REPO_ROOT/rtl/fpga/Vivado/build/app.t0}"

RUNNER_DLL="$REPO_ROOT/src/CilCpu.Sim.Runner/bin/Debug/net10.0/CilCpu.Sim.Runner.dll"
PUREMATH_DLL="$REPO_ROOT/samples/PureMath/bin/Debug/net10.0/PureMath.dll"

echo "INFO: repo       = $REPO_ROOT"
echo "INFO: method     = $METHOD"
echo "INFO: boot N      = $ARG_N (a BOOT_ARG_VALUE generic-be allitsd be)"
echo "INFO: out .t0    = $OUT"

# hu: 1. .NET build (Runner + PureMath) ha hianyzik a DLL
# en: 1. .NET build (Runner + PureMath) if the DLL is missing
if [ ! -f "$RUNNER_DLL" ] || [ ! -f "$PUREMATH_DLL" ]; then
    echo "INFO: dotnet build CLI-CPU.sln -c Debug ..."
    dotnet build "$REPO_ROOT/CLI-CPU.sln" -c Debug
fi

# hu: 2. Linker hivas — .dll -> CIL-T0 .t0 (a sim-mel azonos parancs)
# en: 2. Linker invocation — .dll -> CIL-T0 .t0 (same command as sim)
mkdir -p "$(dirname "$OUT")"
dotnet "$RUNNER_DLL" link \
    "$PUREMATH_DLL" \
    --class Math \
    --method "$METHOD" \
    -o "$OUT"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo ""
echo "========================================================"
echo "INFO: CIL-T0 binaris KESZ: $OUT ($SIZE byte)"
echo "INFO: 8-byte method header @ offset 0, kod @ offset 8 (BOOT_PC=0x08)"
echo "INFO: Kovetkezo: Vivado write_cfgmem.tcl -tclargs $OUT"
echo "========================================================"
