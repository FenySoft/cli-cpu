# cilcpu_a7lite_board — Vivado build (F2.7 Sub5)

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 1.0

Vivado build of the full `cilcpu_a7lite_board` (Sub4 board.v) for the
A7-Lite XC7A200T. Mirrors `smoke_test/Vivado/` but synthesizes the
complete Nano core source tree and embeds the CIL-T0 application binary
into the config flash.

> **Scope:** Synthesis/PnR/bitstream/cfgmem and timing closure run on
> the user's WSL machine — not runnable here (no Vivado).

## Files

| File | Role |
|------|------|
| `create_project.tcl` | Project auto-generation: synth → impl → write_bitstream + timing report |
| `write_cfgmem.tcl` | `.bit` + CIL-T0 `.t0` → one `.mcs` (SPIx4, 16 MB IS25L128F) |

The `.xdc` is one level up (`../cilcpu_a7lite.xdc`) — shared for
source parity with the OpenXC7 build (OpenXC7 uses its own format XDC
in `../OpenXC7/cilcpu_a7lite.xdc`).

## Requirements

- **Vivado ML Standard 2024.2** (or newer), free WebPACK license
  supports XC7A200T (Artix-7-only install suffices)
- For the CIL-T0 `.t0`: .NET 10 SDK (see `scripts/build_app_bin.sh`)

## Usage

```bash
# 1. App binary (same linker command as the sim)
../scripts/build_app_bin.sh                 # FibonacciIterative, N=20

# 2. Synthesis → impl → bitstream
cd rtl/fpga/Vivado
vivado -mode batch -source create_project.tcl

# 3. cfgmem (.bit + .t0 → .mcs)
vivado -mode batch -source write_cfgmem.tcl -tclargs build/app.t0
```

Output:
```
build/cilcpu_a7lite.runs/impl_1/cilcpu_a7lite_board.bit
build/cilcpu_a7lite.mcs
build/timing_summary.rpt   (check: sys_clk WNS >= 0)
```

## FPGA parameter overrides

`create_project.tcl` sets the top-level generics (FPGA counterparts of
the sim Verilator `-G<...>` overrides):

| Generic | Value | Meaning |
|---------|-------|---------|
| `BOOT_PC` | `0x00000008` | entry after the 8-byte method header |
| `BOOT_ARG_COUNT` | 1 | one argument (N) |
| `BOOT_LOCAL_COUNT` | 4 | FibonacciIterative locals |
| `BOOT_ARG_VALUE` | 20 | Fibonacci(20) → 6765 |
| `DEBOUNCE_BITS` | 22 | ~84 ms @ 50 MHz button debounce |
| `CLOCKS_PER_BAUD` | 434 | 50 MHz / 115200 baud (CH340) |

## Flash offset (sim ↔ cfgmem) — RESOLVED in Sub5.A

`CODE_BASE_OFFSET` parameterizable generic: SIM default `0`
(bit-identical with the cocotb `TQSPIFlashModel`), FPGA `0xC00000`
(12 MB, ABOVE the ~9.9 MB XC7A200T bitstream). `write_cfgmem.tcl`
embeds the `.t0` at the same offset (`CODE_BASE_OFFSET_HEX` = the
generic, single source). Details: `../README.md` Sub5 section.

## Bring-up

See the full bring-up runbook: `../README.md` "Sub5" section
(JTAG → config flash → CH340 UART 115200 8N1 → KEY2 → "6765\r\n").

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-05-17 | Initial release — full board.v Vivado build + write_cfgmem |
| 1.0.1 | 2026-05-17 | Sub5.A — `CODE_BASE_OFFSET=32'hC00000` generic + `write_cfgmem.tcl` `CODE_BASE_OFFSET_HEX=0x00C00000` (single source); flash collision resolved (app above the bitstream) |
