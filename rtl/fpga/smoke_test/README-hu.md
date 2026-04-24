# LED blink smoke-teszt

> English version: [README.md](README.md)

Az első CLI-CPU saját bitstream az A7-Lite 200T board-on: egy ~10 soros Verilog számláló villogtatja a két user LED-et eltérő ütemben. Célja a **FPGA → A7-Lite 200T** end-to-end bring-up flow validálása, mielőtt a valódi Nano core RTL-t szintetizálnánk (F2.7).

## Két párhuzamos toolchain, ugyanarra a Verilog-ra

| Toolchain | Alkönyvtár | Build idő | Licenc |
|-----------|-----------|-----------|--------|
| **Vivado ML Standard 2024.2** | [`Vivado/`](Vivado/README-hu.md) | ~5–10 perc | zárt, ingyenes (WebPACK) |
| **OpenXC7** (Yosys + nextpnr-xilinx) | [`OpenXC7/`](OpenXC7/README-hu.md) | ~15 perc (első) / ~1 perc (cache) | 100% open source |

Mindkettő **ugyanazt a `led_blink.v`-t** szintetizálja a kanonikus A7-Lite 200T pin-jeire. 2026-04-24-én mindkettő verifikálva volt valódi hardveren (LED-ek villognak).

## Fájlok

```
rtl/fpga/smoke_test/
  ├── led_blink.v           ← megosztott Verilog RTL (mindkét toolchain használja)
  ├── README.md (en)
  ├── README-hu.md (hu)
  ├── Vivado/               ← Vivado-specifikus build
  │   ├── led_blink.xdc
  │   ├── create_project.tcl
  │   ├── README.md (en)
  │   └── README-hu.md (hu)
  └── OpenXC7/              ← OpenXC7-specifikus build
      ├── led_blink.xdc
      ├── Makefile
      ├── build.sh
      ├── README.md (en)
      └── README-hu.md (hu)
```

A `led_blink.v` **egyetlen** shared fájl — 10 sor Verilog, 25-bit counter, két LED kimenet eltérő frekvenciával:
- **LED1 (M18):** `counter[24]` → ~0.75 Hz
- **LED2 (N18):** `counter[23]` → ~1.5 Hz (kétszer gyorsabb)

## Melyiket használd?

**Vivado** — amikor:
- Gyors iteráció kell fejlesztés közben
- Részletes timing riport kell (WNS/TNS/WHS/THS)
- Zárt flow bevett (pl. NLnet-féle „libre silicon" értékelés nem fontos most)

**OpenXC7** — amikor:
- Full libre silicon flow a cél (CI-ban, publikációban)
- Vivado licence / elérés korlátozott
- A Vivado-függetlenséget bizonyítani akarod

**Vagy mindkettőt** — a `docs/tool-openness-hu.md` szerint ez a javasolt stratégia F4 felé.

## Miért nincs testbench?

Ez egy smoke-teszt, nem az igazi Nano core. A szimuláció 25-bit számlálóra ~33 millió ciklus lenne — értelmetlen. A „teszt" maga a fizikai LED villogás.

A valódi RTL modulok (ALU, decoder, microcode) mind cocotb testbench-el vannak fedve a `rtl/tb/` alatt.
