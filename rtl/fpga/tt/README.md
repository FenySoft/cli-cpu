# CLI-CPU tt_board — A7-Lite FPGA build (F2.8.6)

> Magyar: [README-hu.md](README-hu.md) · Version: 1.0

Generates the `cilcpu_tt_board` (Tiny Tapeout `tt_um` equivalent) bitstream for
the A7-Lite XC7A200T, so that when the **qspi-pmod (W25Q128 flash + 2× APS6404L
PSRAM)** arrives, the boot-over-UART → run → UART-result path is testable immediately.

## What it builds

- Top: `cilcpu_tt_board` (→ `cilcpu_tt_top` → `cilcpu_soc`), XDC: `../cilcpu_tt_a7lite.xdc`.
- The bitstream goes to the **onboard config flash** (as usual); the CIL-T0
  **program goes to the qspi-pmod** (boot-over-UART or pre-flashed) — so there is
  **no `write_cfgmem` app embedding** (unlike `a7lite_board`), and `CODE_BASE_OFFSET=0`.
- **No STARTUPE2** (the QSPI clk is a plain I/O pin on JP1) → the **OpenXC7 flow
  fully works** (the `a7lite_board` STARTUPE2 limitation does not apply here).

## Build

**OpenXC7 (open source, WSL Ubuntu 22.04):**
```bash
cd rtl/fpga/tt/OpenXC7
make check-env
make chipdb          # one-time, ~5-10 min
make all             # cilcpu_tt.bit
openFPGALoader -b a7-lite cilcpu_tt.bit
```

**Vivado (batch):**
```bash
cd rtl/fpga/tt/Vivado
vivado -mode batch -source create_project.tcl
```

## Hardware — qspi-pmod adapter to JP1

The adapter routes GND/3.3V and passes the data lines unmodified. The qspi-pmod's
8 signal pins (PMOD1..8) map to JP1 `GPIO1_0..3 P/N`:

| uio | qspi-pmod | JP1 | FPGA |
|-----|-----------|-----|------|
| 0 | CS0 cs_flash | GPIO1_0P | F13 |
| 1 | SD0 DQ0 | GPIO1_1P | E13 |
| 2 | SD1 DQ1 | GPIO1_2P | D14 |
| 3 | SCK clk | GPIO1_3P | E16 |
| 4 | SD2 DQ2 | GPIO1_0N | F14 |
| 5 | SD3 DQ3 | GPIO1_1N | E14 |
| 6 | CS1 cs_psram (RAM A) | GPIO1_2N | D15 |
| 7 | CS2 (RAM B, unused) | GPIO1_3N | D16 |

**Power:** the qspi-pmod's **3.3V** from **JP1 pin 29 (VCC_3V3)**, GND from pin 12/30.
⚠️ JP1 pin 11 = **VCC_5V** — do NOT connect the Pmod to it!

UART: via CH340 USB-UART (RX=U2, TX=V2). Reset: KEY1 (AA1).

## ⚠️ Known bring-up risks (to address when the card arrives)

Sim is green (`test_tt_board` 2/2), but verify these on REAL HW (stated openly):

1. **W25Q128 QE bit (flash Quad-read 0x6B):** `QE_INIT_ENABLE=1` enables the
   controller's WREN+WRSR QE-init. If the flash returns garbage (as in F2.7 Sub5
   for the config flash), suspect QE.
2. **APS6404L PSRAM Quad mode (0x35 "Enter Quad Mode"):** the
   `cilcpu_qspi_controller` assumes the PSRAM is in Quad mode (0xEB/0x38), but the
   APS6404L powers up in SPI mode and needs a 0x35 command. **The controller does
   NOT currently issue 0x35** → PSRAM loading (dev=1) likely needs a PSRAM quad-init
   on HW (separate RTL task if confirmed). Flash boot (dev=0, if QE OK) is independent.
3. **QSPI clk on a plain GPIO (uio[3]=E16):** the controller drives a /2 gated clk
   on a non-clock-capable I/O. Likely fine at 25 MHz, but if timing/jitter is an
   issue → forward the clk via ODDR (RTL refinement).

These do not block the build; they surface during actual HW validation.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-06-01 | First version — tt_board OpenXC7 + Vivado build, qspi-pmod JP1 adapter, bring-up risks (QE, PSRAM 0x35, clk-on-GPIO). |
