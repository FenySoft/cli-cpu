# CLI-CPU — Roadmap

A CLI-CPU projekt **hét fázisban** épül fel, a spec dokumentumtól az első működő, kezedben tartható szilíciumig és tovább, a teljes ECMA-335 CIL implementációig.

## Vezérelvek

1. **Spec előbb, kód utána.** Minden fázis egy dokumentummal vagy egy pontos követelménylistával kezdődik. Nincs „majd menet közben kitaláljuk".
2. **TDD minden szoftveres rétegre.** A szimulátor és az RTL is tesztelt — a tesztek a spec követelményeiből születnek, nem utólag az implementáció alapján.
3. **Egy aranypélda.** Az F1 C# szimulátor **az aranypélda** — minden későbbi RTL (F2, F4, F5) ezt a viselkedést reprodukálja, cocotb/golden-vector összehasonlítással.
4. **Terjeszkedés alulról felfelé.** F0–F3 a „tiszta, szűk" CIL-T0 subset. F4–F6 csak akkor jön, ha az alap már szilárd.
5. **Valódi szilícium korán.** Az F3 (Tiny Tapeout) a projekt első „kézzel fogható" mérföldköve — akár hiányos is lehet a funkciókészlet, de **létezik fizikailag**.

## Fázisok

### F0 — Specifikáció

**Cél:** Olyan dokumentumok, amelyekből a teljes projekt megépíthető anélkül, hogy menet közben tervezési döntéseket kellene hozni.

**Kimenet:**
- `docs/roadmap.md` — ez a dokumentum
- `docs/architecture.md` — CLI-CPU architektúra: stack-gép, pipeline, memória modell, prior art
- `docs/ISA-CIL-T0.md` — CIL-T0 subset teljes specifikáció (~40 opkód)

**Kész kritérium:** A három dokumentum elolvasása után egy kívülálló mérnök meg tudja mondani, hogy *pontosan* melyik CIL opkód mit csinál a CLI-CPU-n, és hogyan illeszkedik a mikroarchitektúrába.

---

### F1 — C# Referencia Szimulátor

**Cél:** Bithibátlan, TDD-vel fejlesztett szoftveres CLI-CPU szimulátor, amelyhez minden CIL-T0 opkódnak dedikált xUnit tesztje van.

**Platform:** .NET 10, C# 13, xUnit.

**Kimenet:**
- `src/CilCpu.Sim/` — szimulátor könyvtár (fetch, decode, execute)
- `src/CilCpu.Sim.Tests/` — xUnit teszt projekt
- `src/CilCpu.Sim.Runner/` — CLI futtató, ami egy CIL-T0 bináris formátumot tud olvasni és futtatni
- `samples/` — néhány egyszerű C# program (Fibonacci, integer sum, GCD), `ilasm`-mal vagy Roslyn-nal CIL-T0-ba fordítva

**Kész kritérium:**
- 100% opkód lefedettség tesztekkel
- Egy Fibonacci(20) C# kódból fordított CIL-T0 bináris helyesen futtatható a szimulátoron
- A szimulátor **mindent trap-el**, amit a spec előír (stack overflow, invalid branch target, stb.)

**Függőség:** F0 kész.

---

### F2 — RTL (Register Transfer Level)

**Cél:** A CLI-CPU szintetizálható RTL leírása, amely bitről-bitre ugyanúgy viselkedik, mint az F1 szimulátor.

**Platform:**
- **Nyelv:** Verilog (TT mainstream) vagy Amaranth HDL (Python, modernebb) — a végleges döntés F2 indulásakor
- **Szimuláció:** Verilator + cocotb
- **Aranypélda:** F1 C# szimulátor — minden CIL-T0 teszt futtatása egyszerre RTL-en és szimulátoron, eredmény-összehasonlítás

**Kimenet:**
- `rtl/` — RTL források
- `rtl/tb/` — cocotb testbench
- `rtl/scripts/` — szintézis és szimuláció scriptek (OpenLane2 kompatibilis)

**Kész kritérium:**
- Verilator szimuláció minden F1 teszten zöld
- Yosys szintézis Sky130 PDK-ra sikeres
- Timing analízis: min. 30 MHz @ Sky130, cél 50 MHz
- Terület becslés a Tiny Tapeout multi-tile budget-be fér (max 8×2 = 16 tile)

**Függőség:** F1 kész, minden teszt zöld.

---

### F3 — Tiny Tapeout Submission (CIL-T0)

**Cél:** Az első valódi CLI-CPU szilícium. Sky130 PDK-n, Tiny Tapeout shuttle-n, CIL-T0 subset funkcionalitással.

**Platform:** Tiny Tapeout (jelenlegi shuttle — TT10/TT11/..., amelyik időben elérhető), Sky130, OpenLane2.

**Kimenet:**
- `tt/` — Tiny Tapeout submission könyvtár (`info.yaml`, `src/`, `docs/`, stb.)
- `tt/test/` — post-silicon bring-up tesztek
- `hw/bringup/` — bring-up board tervei (KiCad): QSPI flash socket, QSPI PSRAM socket, FTDI USB-UART, power, debug LEDek, PMOD csatlakozók

**Kész kritérium:**
- GDS elfogadva a Tiny Tapeout shuttle-re
- Gate-level szimuláció zöld
- Bring-up board legyártatva (JLCPCB), bekábelezve
- **Fizikailag futó `Fibonacci(10)` a saját chipeden**, UART-on kiíratva

**Függőség:** F2 kész.

**Költség-nagyságrend:** ~$150 (TT submission) + ~$80 (bring-up PCB + alkatrészek).

---

### F4 — CIL Object Model + GC FPGA-n

**Cél:** A CLI-CPU kibővítése az objektum-modellel, statikus/virtuális metódushívással, és egy egyszerű stop-the-world GC-vel. **FPGA-n** fut, nem szilíciumon — itt még drága lenne gyártani.

**Új opkódok:** `newobj`, `newarr`, `ldfld`, `stfld`, `ldelem.*`, `stelem.*`, `callvirt`, `ldtoken`, `ldftn`, `ldvirtftn`, `isinst`, `castclass`, `box`, `unbox`, `ldstr`.

**Új mikroarchitektúra:**
- Metaadat TLB + token-resolver (PE/COFF táblák)
- vtable inline cache
- GC assist unit: bump allocator, write barrier, kártyatábla
- μop cache (Transmeta-stílus, lásd `architecture.md`)

**Platform:** Xilinx Artix-7 (Digilent Arty A7-100T, ~$250) vagy Lattice ECP5 (OrangeCrab, ~$130).

**Kész kritérium:**
- Egy C# „hello objektum" program (osztály, virtuális metódus, tömb, string) fut FPGA-n
- Allokáció → GC → allokáció ciklus stabil

**Függőség:** F3 kész, post-silicon tanulságok visszaportolva az RTL-re.

---

### F5 — Exception Handling, FP, 64-bit, Generikusok

**Cél:** A teljes ECMA-335 CIL lefedése, továbbra is FPGA-n.

**Új funkciók:**
- Kivételkezelés (`throw`, `leave`, `endfinally`, `rethrow`, filter) — shadow register file + checkpoint rollback (Transmeta-inspiráció)
- IEEE-754 FPU (R4, R8)
- 64-bit integer utasítások
- Generikus típusok (runtime típusparaméter feloldás)
- Delegate hívás

**Kész kritérium:**
- A nanoFramework alapkönyvtár egy valós értelmes részhalmaza fut a CLI-CPU-n
- Minden ECMA-335 opkódra van teszt
- Exception throw/catch ciklus alatti throughput mérve és dokumentálva

**Függőség:** F4 kész.

---

### F6 — eFabless ChipIgnite / Open MPW Submission

**Cél:** **A teljes CLI-CPU valódi szilíciumon.** Nem Tiny Tapeout, mert nem fér el — eFabless Caravel harness-en, full MPW shuttle-n, Sky130 PDK-n.

**Platform:**
- Sky130 @ Caravel harness (~10 mm² user area, ~38 GPIO, Wishbone bus, management core)
- OpenLane2 toolchain (ugyanaz, amit F3-ban már használtunk — a tudás hordozható)

**Új funkciók a mikroarchitektúrában:**
- **Writable microcode** SRAM — firmware-ből frissíthető opkód viselkedés
- μop cache aktív F4-ből átemelve
- Shadow register file F5-ből átemelve
- Gated store buffer (GC write barrier batch)
- Agresszív power-gating

**Kimenet:**
- `mpw/` — eFabless submission könyvtár
- `mpw/firmware/` — boot-loader, mikrokód image
- `hw/chipignite-board/` — ChipIgnite bring-up board

**Kész kritérium:**
- ChipIgnite lapka legyártva és a kezedben
- Egy valós C# alkalmazás (pl. mérőeszköz firmware, IoT szenzor node) fut natívan a chipen
- **Energia / teljesítmény mérés** a ARM Cortex-M4 ellen, nanoFramework interpreter módban

**Függőség:** F5 kész, FPGA stabil, minden teszt zöld.

**Költség-nagyságrend:** ~$9,750 (ChipIgnite, 100 db bring-up chip-pel) vagy $0 (Open MPW free shuttle, ha elérhető).

---

### F7 — Termék Bring-up + Demo

**Cél:** A CLI-CPU ne csak egy lapka legyen, hanem egy **demonstrálható rendszer** egy valós use-case-re.

**Kimenet:**
- Egy IoT szenzor node referencia termék (QSPI flash, QSPI PSRAM, LoRa/WiFi, néhány szenzor)
- Példa C# alkalmazás, amit közvetlenül Roslyn-nal lehet fordítani a CLI-CPU-ra
- Energia-benchmark a versenyzőkkel szemben
- Cikk / előadás / demo video

**Függőség:** F6 kész, chip a kézben.

---

## Függőségi gráf

```
F0 ──► F1 ──► F2 ──► F3 ──► F4 ──► F5 ──► F6 ──► F7
              │              ▲
              │              │
              └──── FPGA ────┘
                 (opcionális
                  korai F2 után)
```

Az F2 után opcionálisan FPGA-n is futtatható a CIL-T0 subset, még F3 (Tiny Tapeout) előtt — ez segít a bring-up board tervezésében, mert FPGA-n pontosan ugyanaz a QSPI interfész tesztelhető.

## Mai státusz

**F0 folyamatban.** Ez a dokumentum, `architecture.md`, és `ISA-CIL-T0.md` íródnak.
