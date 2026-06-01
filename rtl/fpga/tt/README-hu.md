# CLI-CPU tt_board — A7-Lite FPGA build (F2.8.6)

> English: [README.md](README.md) · Version: 1.0

A `cilcpu_tt_board` (Tiny Tapeout `tt_um` ekvivalens) bitstream-generálása az
A7-Lite XC7A200T-re, hogy a **qspi-pmod (W25Q128 flash + 2× APS6404L PSRAM)**
megérkezésekor azonnal tesztelhető legyen a boot-over-UART → futás → UART-eredmény út.

## Mit épít

- Top: `cilcpu_tt_board` (→ `cilcpu_tt_top` → `cilcpu_soc`), XDC: `../cilcpu_tt_a7lite.xdc`.
- A bitstream az **onboard config-flash-re** kerül (a szokásos módon); a CIL-T0
  **program a qspi-pmod-ra** kerül (boot-over-UART vagy előre flashelve) — ezért
  **nincs `write_cfgmem` app-beágyazás** (eltérés az `a7lite_board`-tól), és
  `CODE_BASE_OFFSET=0`.
- **Nincs STARTUPE2** (a QSPI clk sima I/O pin a JP1-en) → az **OpenXC7 flow
  teljesen működik** (az `a7lite_board` STARTUPE2-korlátja itt nem érvényes).

## Build

**OpenXC7 (nyílt forrású, WSL Ubuntu 22.04):**
```bash
cd rtl/fpga/tt/OpenXC7
make check-env      # toolchain
make chipdb         # egyszeri, ~5-10 perc
make all            # cilcpu_tt.bit
openFPGALoader -b a7-lite cilcpu_tt.bit   # config-flash-re
```

**Vivado (batch):**
```bash
cd rtl/fpga/tt/Vivado
vivado -mode batch -source create_project.tcl
# build/.../impl_1/cilcpu_tt_board.bit + timing_summary.rpt + utilization.rpt
```

## Hardver — qspi-pmod adapter a JP1-re

Az adapter a GND/3.3V-ot vezeti, az adatvonalakat módosítás nélkül. A qspi-pmod
8 jel-pinje (PMOD1..8) a JP1 `GPIO1_0..3 P/N`-re:

| uio | qspi-pmod | JP1 jel | FPGA |
|-----|-----------|---------|------|
| 0 | CS0 cs_flash | GPIO1_0P | F13 |
| 1 | SD0 DQ0 | GPIO1_1P | E13 |
| 2 | SD1 DQ1 | GPIO1_2P | D14 |
| 3 | SCK clk | GPIO1_3P | E16 |
| 4 | SD2 DQ2 | GPIO1_0N | F14 |
| 5 | SD3 DQ3 | GPIO1_1N | E14 |
| 6 | CS1 cs_psram (RAM A) | GPIO1_2N | D15 |
| 7 | CS2 (RAM B, nem használt) | GPIO1_3N | D16 |

**Táp:** a qspi-pmod **3.3V**-ja a **JP1 pin 29 (VCC_3V3)**-ról, GND a pin 12/30-ról.
⚠️ A JP1 pin 11 = **VCC_5V** — NE arra kösd a Pmod-ot!

UART: a CH340 USB-UART-on (RX=U2, TX=V2). Reset: KEY1 (AA1).

## Teszt-procedúra (boot-over-UART)

1. Flasheld a bitstream-et a config-flash-re, reset (KEY1).
2. A host UART-on (115200 8N1) küldd a WRITE keretet (`0xC0`, dev=PSRAM, addr, len,
   payload = `.t0`), majd a BOOT keretet (`0xB0`, code_src=PSRAM, pc=0).
3. A core PSRAM-ból fut, az eredményt decimálisan az UART-on adja (`\r\n`).
4. halt → LED1 (M18), trap → LED2 (N18).

## ⚠️ Ismert bring-up kockázatok (a kártya megjöttekor kezelendő)

A sim zöld (`test_tt_board` 2/2), de a VALÓS HW-en ezek a pontok ellenőrzendők —
nyíltan kimondva (single-layer-trust elv: a korlátot kimondani kell):

1. **W25Q128 QE-bit (flash Quad-read 0x6B):** a `QE_INIT_ENABLE=1` generic
   bekapcsolja a controller WREN+WRSR QE-init szekvenciáját. Ha a flash garbage-t
   ad (mint az F2.7 Sub5-nél a config-flash-nél), ez a gyanús — ellenőrizd a QE
   beállítást.
2. **APS6404L PSRAM Quad-mód (0x35 „Enter Quad Mode"):** a `cilcpu_qspi_controller`
   a PSRAM-ot Quad-módúnak feltételezi (0xEB/0x38), de az APS6404L SPI-módban
   indul, és egy 0x35 paranccsal kell Quad-módba kapcsolni. **A controller
   jelenleg NEM ad 0x35-öt** → a PSRAM-betöltés (dev=1) a HW-en valószínűleg
   PSRAM-quad-init-et igényel (külön RTL-taszk, ha a HW-en kiderül). A flash-boot
   (dev=0, ha QE OK) ettől független. Roadmap/todo: külön bring-up taszk.
3. **QSPI clk sima GPIO-n (uio[3]=E16):** a controller egy /2 gated clk-ot hajt a
   SCK-ra egy sima I/O pinen (nem clock-capable). 25 MHz-en várhatóan jó, de ha a
   timing/jitter gond → ODDR-rel kell forward-olni a clk-ot (RTL-finomítás).

Ezek nem blokkolják a build-et; a tényleges HW-validációkor derülnek ki.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-06-01 | Első verzió — tt_board OpenXC7 + Vivado build, qspi-pmod JP1-adapter, bring-up kockázatok (QE, PSRAM 0x35, clk-on-GPIO). |
