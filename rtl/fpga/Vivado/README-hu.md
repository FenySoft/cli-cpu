# cilcpu_a7lite_board — Vivado build (F2.7 Sub5)

> English version: [README.md](README.md)

> Verzió: 1.0

A teljes `cilcpu_a7lite_board` (Sub4 board.v) Vivado-build-je az
A7-Lite XC7A200T-re. A `smoke_test/Vivado/` mintáját követi, de a
teljes Nano core forrásfát szintetizálja, és a CIL-T0 alkalmazás-
binárist a config flash-be ágyazza.

> **Hatókör:** A szintézis/PnR/bitstream/cfgmem és a timing-zárás a
> felhasználó WSL-gépén fut — itt nem futtatható (nincs Vivado).

## Fájlok

| Fájl | Szerep |
|------|--------|
| `create_project.tcl` | Projekt auto-generálás: synth → impl → write_bitstream + timing report |
| `write_cfgmem.tcl` | `.bit` + CIL-T0 `.t0` → egyetlen `.mcs` (SPIx4, 16 MB IS25L128F) |

A `.xdc` egy szinttel feljebb (`../cilcpu_a7lite.xdc`) — shared az
OpenXC7-build forrás-paritásához (az OpenXC7 saját formátumú XDC-t
használ a `../OpenXC7/cilcpu_a7lite.xdc`-ben).

## Követelmények

- **Vivado ML Standard 2024.2** (vagy újabb), ingyenes WebPACK license
  támogatja az XC7A200T-t (Artix-7 telepítés elég)
- A CIL-T0 `.t0` előállításához: .NET 10 SDK (lásd `scripts/build_app_bin.sh`)

## Használat

```bash
# 1. App-bináris (a sim-mel azonos linker-parancs)
../scripts/build_app_bin.sh                 # FibonacciIterative, N=20

# 2. Szintézis → impl → bitstream
cd rtl/fpga/Vivado
vivado -mode batch -source create_project.tcl

# 3. cfgmem (.bit + .t0 → .mcs)
vivado -mode batch -source write_cfgmem.tcl -tclargs build/app.t0
```

Eredmény:
```
build/cilcpu_a7lite.runs/impl_1/cilcpu_a7lite_board.bit
build/cilcpu_a7lite.mcs
build/timing_summary.rpt   (ellenőrizd: sys_clk WNS >= 0)
```

## FPGA paraméter-override-ok

A `create_project.tcl` a top-level generikre állítja (a sim Verilator
`-G<...>` override-ok FPGA-megfelelői):

| Generic | Érték | Jelentés |
|---------|-------|----------|
| `BOOT_PC` | `0x00000008` | belépés a 8-byte method header után |
| `BOOT_ARG_COUNT` | 1 | egy argumentum (N) |
| `BOOT_LOCAL_COUNT` | 4 | FibonacciIterative lokálisai |
| `BOOT_ARG_VALUE` | 20 | Fibonacci(20) → 6765 |
| `DEBOUNCE_BITS` | 22 | ~84 ms @ 50 MHz gomb-pergésmentes |
| `CLOCKS_PER_BAUD` | 434 | 50 MHz / 115200 baud (CH340) |

## Flash-offszet (sim ↔ cfgmem) — Sub5.A-ban MEGOLDVA

`CODE_BASE_OFFSET` paraméterezhető generic: SIM default `0` (bit-azonos
a cocotb `TQSPIFlashModel`-lel), FPGA `0xC00000` (12 MB, a ~9,9 MB
XC7A200T bitstream FÖLÉ). A `write_cfgmem.tcl` ugyanerre az offszetre
ágyazza a `.t0`-t (`CODE_BASE_OFFSET_HEX` = a generic, egyetlen forrás).
Részletek: `../README-hu.md` Sub5 szakasz.

## Bring-up

Lásd a teljes bring-up runbookot: `../README-hu.md` „Sub5" szakasz
(JTAG → config flash → CH340 UART 115200 8N1 → KEY2 → "6765\r\n").

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-05-17 | Kezdeti kiadás — teljes board.v Vivado build + write_cfgmem |
| 1.0.1 | 2026-05-17 | Sub5.A — `CODE_BASE_OFFSET=32'hC00000` generic + `write_cfgmem.tcl` `CODE_BASE_OFFSET_HEX=0x00C00000` (egyetlen forrás); flash-ütközés megoldva (app a bitstream fölé) |
