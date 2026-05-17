# cilcpu_a7lite_board — OpenXC7 build (F2.7 Sub5)

> English version: [README.md](README.md)

> Verzió: 1.1

A teljes `cilcpu_a7lite_board` OpenXC7-build-je (Yosys + nextpnr-xilinx
+ Project X-Ray) az A7-Lite XC7A200T-re. A `smoke_test/OpenXC7/`
mintáját követi, a teljes Nano core forrásfával.

> **Hatókör:** A build a felhasználó WSL-gépén fut — itt nem futtatható
> (nincs yosys/nextpnr-xilinx).

## ⚠️ STARTUPE2 — upstream támogatott, itt még nem igazolt

A Sub4 board.v **STARTUPE2** + 4× **IOBUF** primitívet példányosít.

- **IOBUF** — az nextpnr-xilinx/prjxray flow-ban **támogatott** (a
  QSPI DQ[3:0] busz rendben).
- **STARTUPE2** — a config-bank startup blokk, a user CCLK a
  `USRCCLKO`-n keresztül. Az `openXC7/nextpnr-xilinx` **#13** issue
  („Prioritize BSCANE2 + STARTUPE2 primitives") **lezárva, completed
  2024-02** → a STARTUPE2 a felső toolchainben **támogatott lett**. A
  projekt-specifikus **artix7 `USRCCLKO`** út (config-flash CCLK user
  módban) **ebben a projektben empirikusan még nincs igazolva** — az
  első WSL-build dönti el.

Ezért: az **OpenXC7 path Sub5-ben egyenrangú cél a pályázati „fully
open" deliverable miatt; az empirikusan igazolt path egyelőre a
Vivado.** Ha a `make all` a `nextpnr-xilinx` lépésnél a STARTUPE2-n
mégis elbukik, az **dokumentált, igazolandó kockázat**, nem RTL/XDC-hiba
— a single-layer-trust elv szerint a tényleges státuszt kimondjuk
(upstream támogatott, itt igazolatlan), se nem kerüljük meg hamis
stub-bal, se nem állítjuk túl. (A smoke-teszt LED-blink STARTUPE2
nélkül ment át OpenXC7-en 2026-04-24-én; a STARTUPE2 a board.v új
igénye.)

## Fájlok

| Fájl | Szerep |
|------|--------|
| `Makefile` | Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit, teljes forrásfa |
| `build.sh` | WSL launcher (PATH, S: drvfs mount, `make`) |
| `cilcpu_a7lite.xdc` | OpenXC7-formátumú constraint (nincs `-dict`, `create_clock` SDC-szerű) |

## Követelmények

- **Ubuntu 22.04** WSL2-ben
- **OpenXC7 snap package** (`/snap/bin/`: yosys, nextpnr-xilinx, bbasm,
  fasm2frames, xc7frames2bit), `make`, `python3`
- App-bináris flash-be töltéshez: `openFPGALoader`

## Használat

```bash
bash build.sh check-env       # toolchain ellenőrzés
bash build.sh chipdb          # egyszeri, ~5-10 perc (xc7a200t)
bash build.sh all             # teljes build → cilcpu_a7lite.bit
```

## App-bináris (CIL-T0) flash-be ágyazás OpenXC7-en

A Vivado `write_cfgmem` itt nem elérhető. Az `xc7frames2bit` után a
bitstream-et és a `.t0`-t külön töltjük a config flash-be
`openFPGALoader`-rel:

```bash
# Bitstream a flash 0x0-ra (FPGA config)
openFPGALoader -b <board> --write-flash cilcpu_a7lite.bit
# App-bináris a CODE_BASE_OFFSET-re (0xC00000) — Sub5.A
openFPGALoader -b <board> --external-flash -o 0xC00000 \
    ../Vivado/build/app.t0
```

**Flash-offszet — Sub5.A-ban MEGOLDVA (nem nyitott kérdés):** a
bitstream a config-flash 0x0-tól él (~9,9 MB), az app a
`CODE_BASE_OFFSET = 0xC00000`-ra kerül (12 MB, a bitstream fölé) →
**nincs ütközés**. **Egyetlen forrás:** ez az offszet = a `Makefile`
`CODE_BASE_OFFSET` chparam = a Vivado `write_cfgmem.tcl`
`CODE_BASE_OFFSET_HEX` = a `cilcpu_qspi_controller` generic. SIM
default `0` (bit-azonos cocotb flash-paritás). Részletek:
`../README-hu.md` Sub5.A szakasz + Vault `project_flash_base_offset`.

## Bring-up

Lásd a teljes runbookot: `../README-hu.md` „Sub5" szakasz.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-05-17 | Kezdeti kiadás — teljes board.v OpenXC7 build; STARTUPE2-korlát dokumentálva |
| 1.1 | 2026-05-17 | Doksi-szinkron: flash-offszet „nyitott kérdés" → Sub5.A MEGOLDVA (app @0xC00000, egyetlen forrás); STARTUPE2 státusz pontosítva (`#13` lezárva 2024-02 → upstream támogatott, artix7 USRCCLKO itt igazolandó), best-effort → pályázati egyenrangú cél |
