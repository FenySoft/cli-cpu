# cilcpu_a7lite_board — OpenXC7 build (F2.7 Sub5)

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 1.0

OpenXC7 build (Yosys + nextpnr-xilinx + Project X-Ray) of the full
`cilcpu_a7lite_board` for the A7-Lite XC7A200T. Mirrors
`smoke_test/OpenXC7/` with the complete Nano core source tree.

> **Scope:** The build runs on the user's WSL machine — not runnable
> here (no yosys/nextpnr-xilinx).

## ⚠️ STARTUPE2 limitation (stated openly)

The Sub4 board.v instantiates a **STARTUPE2** + 4× **IOBUF**.

- **IOBUF** — **supported** in the nextpnr-xilinx/prjxray flow (the
  QSPI DQ[3:0] bus is fine).
- **STARTUPE2** — the config-bank startup block, user CCLK via
  `USRCCLKO`. STARTUP site fuzzing is **incomplete** in the
  nextpnr-xilinx + prjxray-db **artix7** flow, so the STARTUPE2 binding
  is **NOT reliably supported**.

Therefore: the **OpenXC7 path is best-effort in Sub5; the primary Sub5
path is Vivado.** If `make all` fails at the `nextpnr-xilinx` step on
STARTUPE2, that is the **documented OpenXC7 limitation**, not an
RTL/XDC bug — per the single-layer-trust principle the limitation is
stated, not papered over with a fake stub. (The smoke-test LED-blink
passed on OpenXC7 on 2026-04-24 without STARTUPE2; STARTUPE2 is a new
requirement introduced by board.v.)

## Files

| File | Role |
|------|------|
| `Makefile` | Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit, full source tree |
| `build.sh` | WSL launcher (PATH, S: drvfs mount, `make`) |
| `cilcpu_a7lite.xdc` | OpenXC7-format constraint (no `-dict`, SDC-like `create_clock`) |

## Requirements

- **Ubuntu 22.04** under WSL2
- **OpenXC7 snap package** (`/snap/bin/`: yosys, nextpnr-xilinx, bbasm,
  fasm2frames, xc7frames2bit), `make`, `python3`
- For app-binary flashing: `openFPGALoader`

## Usage

```bash
bash build.sh check-env       # toolchain check
bash build.sh chipdb          # one-time, ~5-10 min (xc7a200t)
bash build.sh all             # full build → cilcpu_a7lite.bit
```

## App binary (CIL-T0) flash embedding on OpenXC7

Vivado `write_cfgmem` is not available here. After `xc7frames2bit`,
load the bitstream and the `.t0` separately into the config flash with
`openFPGALoader`:

```bash
# Bitstream to flash 0x0 (FPGA config)
openFPGALoader -b <board> --write-flash cilcpu_a7lite.bit
# App binary at a separate offset (see the flash-offset open question)
openFPGALoader -b <board> --external-flash -o <APP_OFFSET> \
    ../Vivado/build/app.t0
```

**Flash offset (sim parity):** the cocotb model and the QSPI controller
read CODE from flash QSPI 0x000000. **Open HW question:** the bitstream
is also at 0x0 — details and resolution options in `../README.md` Sub5
section.

## Bring-up

See the full runbook: `../README.md` "Sub5" section.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-05-17 | Initial release — full board.v OpenXC7 build; STARTUPE2 limitation documented |
