# cilcpu_a7lite_board — OpenXC7 build (F2.7 Sub5)

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 1.1

OpenXC7 build (Yosys + nextpnr-xilinx + Project X-Ray) of the full
`cilcpu_a7lite_board` for the A7-Lite XC7A200T. Mirrors
`smoke_test/OpenXC7/` with the complete Nano core source tree.

> **Scope:** The build runs on the user's WSL machine — not runnable
> here (no yosys/nextpnr-xilinx).

## ⚠️ STARTUPE2 — supported upstream, not yet verified here

The Sub4 board.v instantiates a **STARTUPE2** + 4× **IOBUF**.

- **IOBUF** — **supported** in the nextpnr-xilinx/prjxray flow (the
  QSPI DQ[3:0] bus is fine).
- **STARTUPE2** — the config-bank startup block, user CCLK via
  `USRCCLKO`. The `openXC7/nextpnr-xilinx` issue **#13** ("Prioritize
  BSCANE2 + STARTUPE2 primitives") was **closed, completed 2024-02** →
  STARTUPE2 **became supported** in the upstream toolchain. The
  project-specific **artix7 `USRCCLKO`** path (config-flash CCLK in
  user mode) is **not yet empirically verified in this project** — the
  first WSL build will decide.

Therefore: the **OpenXC7 path is a first-class Sub5 target for the
grant "fully open" deliverable; the empirically verified path is so
far Vivado.** If `make all` still fails at the `nextpnr-xilinx` step
on STARTUPE2, that is a **documented, to-be-verified risk**, not an
RTL/XDC bug — per the single-layer-trust principle we state the actual
status (supported upstream, unverified here), neither papering it over
with a fake stub nor over-claiming. (The smoke-test LED-blink passed
on OpenXC7 on 2026-04-24 without STARTUPE2; STARTUPE2 is a new
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
# App binary at CODE_BASE_OFFSET (0xC00000) — Sub5.A
openFPGALoader -b <board> --external-flash -o 0xC00000 \
    ../Vivado/build/app.t0
```

**Flash offset — RESOLVED in Sub5.A (not an open question):** the
bitstream lives from config-flash 0x0 (~9.9 MB), the app is placed at
`CODE_BASE_OFFSET = 0xC00000` (12 MB, above the bitstream) → **no
collision**. **Single source:** this offset = the `Makefile`
`CODE_BASE_OFFSET` chparam = the Vivado `write_cfgmem.tcl`
`CODE_BASE_OFFSET_HEX` = the `cilcpu_qspi_controller` generic. SIM
default `0` (bit-identical cocotb flash parity). Details:
`../README.md` Sub5.A section + Vault `project_flash_base_offset`.

## Bring-up

See the full runbook: `../README.md` "Sub5" section.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-05-17 | Initial release — full board.v OpenXC7 build; STARTUPE2 limitation documented |
| 1.1 | 2026-05-17 | Doc-sync: flash-offset "open question" → Sub5.A RESOLVED (app @0xC00000, single source); STARTUPE2 status corrected (`#13` closed 2024-02 → supported upstream, artix7 USRCCLKO to verify here), best-effort → first-class grant target |
