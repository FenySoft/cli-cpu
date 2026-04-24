# LED blink — Vivado build

> English version: [README.md](README.md)

A CLI-CPU F2.7 smoke-teszt **Vivado toolchain**-en: ugyanaz a `led_blink.v` mint az OpenXC7 build-ben, de a hagyományos AMD/Xilinx zárt forráskódú tool-lánccal. A „kényelmes" út — gyorsabb build (45 sec vs 15 perc), jobb timing report, GUI.

**Státusz (2026-04-24):** ✅ Sikeres build és programozás az A7-Lite 200T-re. WNS = 17.972 ns 50 MHz-en.

## Fájlok

| Fájl | Szerep |
|------|--------|
| `led_blink.xdc` | Pin constraint (J19 clock, M18/N18 LED-ek, bitstream config) |
| `create_project.tcl` | Vivado projekt auto-generáló script — szintézis + implementation + bitstream |

A `led_blink.v` **egy szinttel feljebb** (`../led_blink.v`) — shared az OpenXC7 build-del.

## Követelmények

- **Vivado ML Standard 2024.2** (vagy újabb) Windows vagy Linux-on
  - Ingyenes WebPACK license támogatja az XC7A200T-t
  - Artix-7-only telepítés elég (~32 GB final disk)

## Használat

**Batch mód (gyors, parancssorból):**

```bash
cd rtl/fpga/smoke_test/Vivado/
vivado -mode batch -source create_project.tcl
```

**GUI mód:**

1. Nyisd meg a Vivado-t
2. Tools → Run Tcl Script → `create_project.tcl`
3. Várd meg, míg kiírja „Build SIKERES" üzenetet

A build ~5–10 perc. Az eredmény:
```
rtl/fpga/smoke_test/Vivado/build/led_blink.runs/impl_1/led_blink.bit
```

## Bitstream feltöltés JTAG-en

1. Csatlakoztasd a board-ot USB-JTAG kábellel
2. Vivado GUI → Open Hardware Manager → Open target → **Auto Connect**
3. Jobb klikk az `xc7a200t_0`-ra → **Program Device...**
4. Válaszd ki a `.bit` fájlt → **Program**
5. ~2-3 sec után a LED-eknek villogniuk kell:
   - **LED1 (M18):** ~0.75 Hz (lassabb)
   - **LED2 (N18):** ~1.5 Hz (kétszer gyorsabb)

## Várt eredmény

A board két zöld LED-je **eltérő ütemben villog** — az egyik kétszer gyorsabban, mint a másik. Ez bizonyítja, hogy:

- A Vivado 2024.2 helyesen szintetizál Artix-7-re
- Az XDC constraint fájl helyes (pin nevek és IO standard)
- A JTAG programozó lánc működik
- A saját bitstream fut az FPGA-n

Ha a LED-ek **fordítva világítanak** (ég, amikor nem kellene), invertáld a `led_blink.v` assign sorait — ez a MicroPhase LED active-low kötésének a következménye.

## Troubleshoot

- **Vivado nem találja az FPGA-t programozáskor:** Open Hardware Manager → Auto Connect újraindítása. USB-JTAG kábel / port csere.
- **Timing violation szintézisben:** nem valószínű, 50 MHz egy számlálónak bőven teljesíthető — ha mégis, a `create_clock` definíciója hibás lehet az XDC-ben.
- **LED-ek nem világítanak:** (a) nem a jó pin (ellenőrizd `docs/A7-Lite/A7-Lite-hu.md`), (b) active-low probléma (invertáld), (c) bitstream nem töltődött fel (nézd a Hardware Manager állapotot).

## Vivado warning-ok (4 darab, mind ártalmatlan)

A build során ezek a warning-ok megjelennek, mind a „design túl egyszerű" kategória:

1. `[Vivado 12-7122]` Auto Incremental Compile — első build-nél mindig
2. `[Synth 8-7080]` Parallel synthesis criteria is not met — design kicsi
3. `[Place 30-2953]` Timing driven mode turned off — slack hatalmas
4. `[Place 46-29]` Physical synthesis skipped — ugyanaz

Semmit nem kell javítani.

## Miért nincs testbench?

Ez egy smoke-teszt, nem az igazi Nano core. A szimuláció 25-bit számlálóra ~33 millió ciklus lenne — értelmetlen. A „teszt" maga a fizikai LED villogás.

A valódi RTL modulok (ALU, decoder, microcode) mind cocotb testbench-el vannak fedve a `rtl/tb/` alatt.
