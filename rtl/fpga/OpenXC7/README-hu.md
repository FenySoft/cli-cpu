# cilcpu_a7lite_board — OpenXC7 build (F2.7 Sub5)

> English version: [README.md](README.md)

> Verzió: 1.0

A teljes `cilcpu_a7lite_board` OpenXC7-build-je (Yosys + nextpnr-xilinx
+ Project X-Ray) az A7-Lite XC7A200T-re. A `smoke_test/OpenXC7/`
mintáját követi, a teljes Nano core forrásfával.

> **Hatókör:** A build a felhasználó WSL-gépén fut — itt nem futtatható
> (nincs yosys/nextpnr-xilinx).

## ⚠️ STARTUPE2-korlát (nyíltan kimondva)

A Sub4 board.v **STARTUPE2** + 4× **IOBUF** primitívet példányosít.

- **IOBUF** — az nextpnr-xilinx/prjxray flow-ban **támogatott** (a
  QSPI DQ[3:0] busz rendben).
- **STARTUPE2** — a config-bank startup blokk, a user CCLK a
  `USRCCLKO`-n keresztül. Az nextpnr-xilinx + prjxray-db **artix7**
  flow-ban a STARTUP site fuzzing **hiányos**, ezért a STARTUPE2
  binding **NEM megbízhatóan támogatott**.

Ezért: az **OpenXC7 path Sub5-ben best-effort; az elsődleges Sub5 path
a Vivado.** Ha a `make all` a `nextpnr-xilinx` lépésnél a STARTUPE2-n
elbukik, az a **dokumentált OpenXC7-korlát**, nem RTL/XDC-hiba — a
single-layer-trust elv szerint a korlátot kimondjuk, nem kerüljük meg
egy hamis stub-bal. (A smoke-teszt LED-blink STARTUPE2 nélkül ment át
OpenXC7-en 2026-04-24-én; a STARTUPE2 a board.v új igénye.)

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
# App-bináris külön offszetre (lásd a flash-offszet nyitott kérdést)
openFPGALoader -b <board> --external-flash -o <APP_OFFSET> \
    ../scripts/../Vivado/build/app.t0
```

**Flash-offszet (sim-paritás):** a cocotb modell és a QSPI controller
a CODE-ot a flash QSPI 0x000000-ról olvassa. **Nyitott HW-kérdés:** a
bitstream is 0x0-tól van — részletek és a feloldási opciók a
`../README-hu.md` Sub5 szakaszában.

## Bring-up

Lásd a teljes runbookot: `../README-hu.md` „Sub5" szakasz.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-05-17 | Kezdeti kiadás — teljes board.v OpenXC7 build; STARTUPE2-korlát dokumentálva |
