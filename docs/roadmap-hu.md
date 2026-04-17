# CLI-CPU — Roadmap

> English version: [roadmap-en.md](roadmap-en.md)

> Version: 1.1

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
- `docs/roadmap-hu.md` — ez a dokumentum
- `docs/architecture-hu.md` — CLI-CPU architektúra: stack-gép, pipeline, memória modell, prior art
- `docs/ISA-CIL-T0-hu.md` — CIL-T0 subset teljes specifikáció (~40 opkód)

**Kész kritérium:** A három dokumentum elolvasása után egy kívülálló mérnök meg tudja mondani, hogy *pontosan* melyik CIL opkód mit csinál a CLI-CPU-n, és hogyan illeszkedik a mikroarchitektúrába.

---

### F1 — C# Referencia Szimulátor — **KÉSZ**

**Cél:** Bithibátlan, TDD-vel fejlesztett szoftveres CLI-CPU szimulátor, amelyhez minden CIL-T0 opkódnak dedikált xUnit tesztje van.

**Platform:** .NET 10, C# 13, xUnit.

**Kimenet:**
- `src/CilCpu.Sim/` — szimulátor könyvtár (fetch, decode, execute) — **kész**
- `src/CilCpu.Sim.Tests/` — xUnit teszt projekt — **kész, 218 zöld teszt**

**Kész kritérium — teljesítve:**
- ✅ 100% opkód lefedettség tesztekkel — mind a 48 CIL-T0 opkód külön teszttel
- ✅ Egy Fibonacci(20) C# kódból fordított CIL-T0 bináris helyesen futtatható a szimulátoron — `Fibonacci(20) = 6765` zöld
- ✅ A szimulátor **mindent trap-el**, amit a spec előír (stack overflow, invalid branch target, invalid memory access, call depth exceeded, stb.)
- ✅ TDD-vel fejlesztve, 4 iteráció (konstansok → stack/local/arg → arit/branch/cmp → call/ret/mem/break)
- ✅ Devil's Advocate review minden iteráció után, finalizálás QR pass-szal

**Függőség:** F0 kész.

---

### F1.5 — Linker, Runner, Samples — **KÉSZ**

**Cél:** Az F1 szimulátor köré épített eszközlánc, amely lehetővé teszi a teljes fejlesztői workflow-t: natív C# forrás → Roslyn → .dll → CIL-T0 linkelés → szimulátor futtatás. Az F1-ből halasztott deliverable-ök teljesítése.

**Platform:** .NET 10, C# 13, xUnit.

**Kimenet:**
- `src/CilCpu.Linker/` — Roslyn .dll → CIL-T0 bináris linker (tranzitív call-target discovery, token→RVA feloldás, opkód-kompatibilitás ellenőrzés) — **kész**
- `src/CilCpu.Sim.Runner/` — CLI futtatóeszköz (`run` és `link` parancsok, trap kezelés, TRunResult) — **kész**
- `samples/PureMath/` — C# példaprogram (Add, Fibonacci, Factorial, GCD, IsPrime, stb.) — **kész**
- `src/CilCpu.Sim.Tests/` — kibővítve linker + runner tesztekkel — **kész, 259 zöld teszt**

**CLI használat:**
```bash
# .t0 bináris futtatása
dotnet run --project src/CilCpu.Sim.Runner -- run program.t0 --args 2,3

# .dll linkelése .t0-ra
dotnet run --project src/CilCpu.Sim.Runner -- link assembly.dll --class Pure --method Add -o output.t0
```

**Kész kritérium — teljesítve:**
- ✅ A linker tranzitívan felfedezi a hívott metódusokat és feloldja a call tokeneket
- ✅ CIL-T0 inkompatibilis opkódok (ldsfld, ldstr, newarr, stb.) link-time hibát adnak
- ✅ A Runner `.t0` fájlokat olvas és futtat, trap-eket kezeli
- ✅ A Runner `.dll` fájlokat linkel `.t0`-ra a CLI-n keresztül
- ✅ A teljes pipeline (C# → Roslyn → linker → szimulátor) end-to-end tesztelve
- ✅ Fibonacci(20) = 6765 a teljes Roslyn-natív pipeline-on át
- ✅ TDD-vel fejlesztve, Devil's Advocate review minden iteráció után

**Függőség:** F1 kész.

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

**Alszakaszok:**
- F2.1 ALU — 32-bit egész ALU (Verilog + cocotb) — **KÉSZ**
- F2.2a Decoder — hossz dekóder + opkód dekód (jelenlegi sprint)
- F2.2b Decoder — microcode ROM komplex opkódokhoz (következő sprint)
- F2.3 Stack cache — 4×32-bit TOS + spill logika
- F2.4 QSPI vezérlő — kód + adat fetch
- F2.5 Golden vector harness — cocotb vs C# szimulátor
- F2.6 Yosys szintézis — Sky130 PDK, terület becslés
- F2.7 FPGA validáció — egymagos Nano core, valós hardveren (A7-Lite)

**Kész kritérium:**
- Verilator szimuláció minden F1 teszten zöld
- Yosys szintézis Sky130 PDK-ra sikeres
- Timing analízis: min. 30 MHz @ Sky130, cél 50 MHz
- Terület becslés a Tiny Tapeout multi-tile budget-be fér (12–16 tile, ~12K–16K gate)

**Függőség:** F1 kész, minden teszt zöld.

---

### F2.7 — Egymagos FPGA validáció

**Cél:** Az F2 RTL **valós FPGA hardveren** történő validálása a Tiny Tapeout submission (F3) **előtt**. Ez biztosítja, hogy a design működik fizikai hardveren, nem csak szimulációban — csökkentve az F3 tape-out kockázatát.

**Platform:** MicroPhase A7-Lite XC7A200T (a 3 board-ból az első). Vivado WebPACK (ingyenes az Artix-7-re).

**Kimenet:**
- `rtl/fpga/` — FPGA-specifikus top-level wrapper (clock, I/O pin assignment)
- Egyetlen Nano core + UART futtatása az FPGA board-on
- Fibonacci(20) = 6765 demó UART-on keresztül, valós hardveren

**Kész kritérium:**
- A Nano core RTL szintetizálva és futtatva A7-Lite 200T-n
- Fibonacci(20) helyesen fut UART kimeneten
- Timing zárt (min. 50 MHz az FPGA-n)
- A cocotb golden-vector tesztek eredménye megegyezik az FPGA kimenetével

**Függőség:** F2 kész (RTL + cocotb szimuláció zöld).

**Költség:** ~€0 (az FPGA board az F4-hez is kell, már megrendeltük).

**Miért fontos:** *„Nincs silicon tape-out olyan design-nal, ami nem futott FPGA-n."* Az F2.5 ez az elv gyakorlatban — olcsó, gyors, és a hibákat az FPGA-n találjuk meg, nem a Tiny Tapeout chipen.

---

### F3 — Tiny Tapeout Submission (egymagos CIL-T0 + Mailbox)

**Cél:** Az első valódi CLI-CPU szilícium. Sky130 PDK-n, Tiny Tapeout shuttle-n, egymagos CIL-T0 subset + **hardveres mailbox interfésszel**, ami az első „hálózatba illeszthető csomópont" demót teszi lehetővé.

**Platform:** Tiny Tapeout (TTSKY26a vagy későbbi shuttle, amelyik időben elérhető), Sky130 PDK, OpenLane2. Egy tile ~160×100 μm, ~1K logic gate kapacitás. A Nano core + Mailbox + UART **12–16 tile-t** igényel (~12K–16K gate, a routing overhead-del együtt). 24 GPIO (8 in + 8 out + 8 bidi), min. 50 MHz clock.

**Kimenet:**
- `tt/` — Tiny Tapeout submission könyvtár (`info.yaml`, `src/`, `docs/`, stb.)
- `tt/test/` — post-silicon bring-up tesztek
- `hw/bringup/` — bring-up board tervei (KiCad): QSPI flash socket, QSPI PSRAM socket, FTDI USB-UART (a mailbox külső bridge-éhez), power, debug LEDek, PMOD csatlakozók

**Új F3 komponens a spec szerint:**
- **Mailbox MMIO blokk** — 8 mélységű inbox + outbox FIFO, `0xF000_0100` címen, részletek a `docs/ISA-CIL-T0-hu.md`-ben. Lehetővé teszi, hogy egy host számítógép UART-on keresztül üzeneteket küldjön a chipnek, amit a chip CIL programmal dolgoz fel és válaszol vissza.

**Kész kritérium:**
- GDS elfogadva a Tiny Tapeout shuttle-re
- Gate-level szimuláció zöld
- Bring-up board legyártatva (JLCPCB), bekábelezve
- **Fizikailag futó `Fibonacci(10)` a saját chipeden**, UART-on kiíratva
- **Első „echo neuron" demó:** a host üzenetet küld a mailbox-on át, a chip CIL programja feldolgozza és visszaküldi — a cognitive fabric koncepció első szilícium-szintű bizonyítéka

**Függőség:** F2 kész.

**Költség-nagyságrend:** ~$900–$1,300 (12–16 tile TT submission, base + extra tile-ok ~$50/tile) + ~$80 (bring-up PCB + alkatrészek). Az 1 tile-os early bird ár (~$150) a Nano core-hoz nem elég — a ~10K std cell-es core + mailbox + UART minimum 8 tile-t igényel, 12–16 tile ajánlott a routing tartalékra.

---

### F4 — Multi-core Cognitive Fabric FPGA-n

**Cél:** **A stratégiai pivot pillanata.** A CLI-CPU először válik valódi hálózattá — 4 egymagos CIL-T0 core dolgozik együtt egyetlen FPGA chipen, **shared-nothing modellben**, kizárólag mailbox üzenetekkel kommunikálva, eseményvezérelt (event-driven) működéssel.

**Miért itt van a fő pivot:** Ez a fázis megkülönbözteti a CLI-CPU-t a történelmi Jazelle/picoJava „bytecode CPU" bukásoktól. A `docs/architecture-hu.md` „Stratégiai pozicionálás: Cognitive Fabric" szekciója részletesen érvel amellett, hogy miért itt van a projekt valódi értéke, és miért nem az egymagos sebesség-verseny.

**Új funkciók:**
- **4 darab CIL-T0 core** egy FPGA-n (az F3 RTL 4 példányban instanciálva)
- **Mailbox router** — a core-ok közötti üzenetek célzott továbbítása (4-portú mux-köteg, nem crossbar)
- **Per-core privát SRAM** (16 KB/core), shared-nothing modell
- **Sleep/Wake logika** — a core elalszik üres inbox-on, új üzenetre ébred (wake-from-sleep interrupt)
- **Globális időbázis** — egyetlen szinkronizált clock counter, amit minden core olvas (a neuron-modellek időfüggőségéhez)
- **Shared slow bus** — csak a QSPI flash, UART, timer eléréshez, nem a kritikus inter-core kommunikációhoz

**Új mikroarchitektúra elemek:**
- Router FSM (~1000 std cell)
- Per-core mailbox FIFO (már F3-ban megvolt, itt csak kapcsolódik a router-re)
- Wake-from-sleep interrupt vonal
- Globális clock broadcast hálózat

**Platform:** MicroPhase A7-Lite XC7A200T (~€320) — **elsődleges referencia platform F4–F5-höz**. Tiszta Artix-7 FPGA, 215K logic cell, 134K LUT, 740 DSP, 13.1 Mbit Block RAM, **512 MB DDR3**, Gigabit Ethernet, HDMI, beépített USB-JTAG, 2×50-pin GPIO header, 80×56 mm kompakt form factor. Vivado ML Standard (WebPACK) **ingyenesen** támogatja. Alternatíva: Digilent Arty A7-100T (~$332, 101K logic cell, DDR3 nélkül) vagy Lattice ECP5 (OrangeCrab, ~$130, kisebb kapacitás). FPGA-n még 100% megvalósítható.

**Kész kritérium:**
- 4 core egyszerre futtat különböző CIL programokat, üzenetekkel kommunikálnak
- **Ping-pong demó:** Core 0 üzenetet küld Core 1-nek, Core 1 válaszol — minimal actor pattern
- **Echo háló demó:** 4 core láncban továbbad egy üzenetet, az első útnak indítja, a negyedik kiküldi UART-ra
- **Spiking neural network demó:** mind a 4 core egy-egy LIF neuron CIL programot futtat, konfigurálható topológiával — a cognitive fabric első valódi neuromorphic felhasználása
- Event-driven mód: idle energia mérve, megjelenik az alvási állapot nyeresége

**Függőség:** F3 kész, post-silicon tanulságok visszaportolva az RTL-re.

---

### F5 — Rich core (teljes CIL) FPGA-n, első heterogén rendszer

**Cél:** **A Rich core születése.** Ez az a fázis, amikor a CIL-T0 szűk subset mellé **megszületik a „nagy testvér"** — egy teljes ECMA-335 CIL core objektum-modellel, GC-vel, virtuális hívásokkal, kivételekkel, FPU-val, 64-bit integer-rel, generikusokkal. A fázis végén **először futtatunk egy heterogén multi-core rendszert**: 4 Nano core (F4-ből) **mellett** 1 Rich core, közös mailbox hálózaton.

**Miért „Rich core" és nem csak „teljes CIL"?** A `docs/architecture-hu.md` **„Heterogén multi-core: Nano + Rich"** szekciója részletezi: a CLI-CPU heterogén (big.LITTLE-szerű) architektúrát fog használni az F6-tól, **kétféle core típussal**. A Nano (CIL-T0) F3-ban született meg, a Rich (teljes CIL) itt, F5-ben. Ez a terminológia-egységesítés csak átnevezés — a technikai tartalom az, ami eddig is „teljes CIL" volt a roadmap-ben.

**Új opkódok a Rich core-on (a Nano 48 opkódon felül):**
- Objektum modell: `newobj`, `newarr`, `ldfld`, `stfld`, `ldelem.*`, `stelem.*`, `ldlen`, `initobj`
- Virtuális hívás és metadata: `callvirt`, `ldtoken`, `ldftn`, `ldvirtftn`
- Típusellenőrzés: `isinst`, `castclass`, `box`, `unbox`
- String: `ldstr`
- Kivételkezelés: `throw`, `rethrow`, `leave`, `endfinally`, `endfilter`
- 64-bit integer: minden aritmetika `.i8` változata
- Floating point: `ldc.r4`, `ldc.r8`, `add` (FP), `mul` (FP), `div` (FP), `conv.*`
- Generics: runtime típusparaméter feloldás

**Új mikroarchitektúra a Rich core-on:**
- **Metaadat TLB + token-resolver** — PE/COFF táblákat jár be
- **vtable inline cache** — virtuális hívás gyorsítás
- **Per-core GC assist unit** — bump allocator a privát heap-en. **Nincs globális GC**, mert nincs shared heap — ez a shared-nothing modell **nagy egyszerűsítése**, a GC nem kell stop-the-world globálisan
- **Shadow register file + exception unwinder** (Transmeta-inspiráció)
- **μop cache** (Transmeta-stílus, forró loopokon energia-spórolás)
- **FPU** (IEEE-754 R4, R8)

**Új szoftveres munka:**
- **Roslyn source generator** a `[RunsOn(CoreType.Nano)]` / `[RunsOn(CoreType.Rich)]` attribútumokra
- A generator ellenőrzi build-time, hogy a Nano-jelölt metódusok csak CIL-T0 opkódokat használnak (verifikáció)
- Két külön bináris kimenet: `.t0` (Nano) és `.tr` (Rich)

**Platform:** Ugyanaz az A7-Lite XC7A200T, mint F4. A 134K LUT és 13.1 Mbit Block RAM kényelmesen elég 1 Rich + 4 Nano core-hoz (~60K LUT, ~45%), sőt akár **2 Rich + 8 Nano** (~105K LUT, ~78%) is megvalósítható. A 512 MB DDR3 a Rich core GC/heap számára kritikus előny a DDR3 nélküli board-okkal szemben. Alternatíva: Arty A7-100T (63K LUT — 1 Rich + 4 Nano szorosan elfér, de 2 Rich már nem).

**Kész kritérium:**
- Minden ECMA-335 opkódra van teszt a C# referencia szimulátoron és az RTL-en
- Egy C# program osztályokkal, virtuális metódusokkal, tömbökkel, stringekkel, kivételekkel **fut a Rich core-on**
- Egy C# program, ahol **egyes osztályok `[RunsOn(CoreType.Nano)]`, mások `[RunsOn(CoreType.Rich)]`** — fut heterogén rendszerben
- **Multi-core Akka.NET demó:** supervisor a Rich core-on, worker-ek a Nano core-okon, üzenetek a mailbox-on át
- **Multi-core SNN demó:** Izhikevich vagy Hodgkin-Huxley modell mind a 4 Nano core-on, egy Rich core koordinálja

**Függőség:** F4 kész.

---

### F6 — Cognitive Fabric FPGA-verifikált demonstráció (heterogén Nano + Rich)

**Cél:** A Cognitive Fabric architektúra **teljes, FPGA-verifikált demonstrálása**. **Nincs silicon tape-out olyan design-nal, ami nem futott FPGA-n.** Az F6-FPGA az elsődleges és kötelező mérföldkő; az F6-Silicon csak akkor indulhat, ha az F6-FPGA minden teszten zöld.

**Architektúra:** Heterogén Rich + Nano multi-core fabric. Egyetlen A7-Lite 200T board-on **2 Rich + 8–10 Nano** (~105–115K / 134K LUT). Több board Ethernet-tel összekötve a Cognitive Fabric **elosztott multi-chip** változatát demonstrálja — ez a Neuron OS location transparency első valódi próbája.

#### F6-FPGA — Heterogén demonstráció A7-Lite 200T multi-board hálón (elsődleges, kötelező)

**Cél:** A Cognitive Fabric architektúra **verifikálása** MicroPhase A7-Lite XC7A200T board-okon, **egyetlen chipen és multi-chip Ethernet hálóban egyaránt**. Az F6-FPGA **bizonyítja, hogy az architektúra működik**, mielőtt bárki ~$10k-t kockáztatna egy MPW shuttle-re.

**Stratégiai indoklás:** A **MicroPhase A7-Lite XC7A200T** (134K LUT, 512 MB DDR3, Gigabit Ethernet, ~€320) az F4–F5 referencia platform, és **3 darab board Ethernet hálóban összekötve** 3 × 134K = **402K LUT aggregált kapacitást** ad — **kétszer annyi, mint egy Kintex-7 K325T** (204K LUT). Ráadásul a multi-board konfiguráció **reálisabb teszt**, mert a valódi Cognitive Fabric is multi-chip lesz. A Vivado ML Standard (WebPACK) **ingyenesen** támogatja az Artix-7 családot (XC7A200T-ig). Alternatívaként az **OpenXC7** nyílt toolchain is használható.

**Miért nem Kintex-7 K325T?** Jelenleg nem érhető el megfelelő konfigurációjú K7-325T fejlesztői board. Ha a jövőben elérhetővé válik, az F6 konfigurációs sweep kiterjeszthető rá — de az F6 **nem függ tőle**.

**Új munka az F4+F5-höz képest:**
- **Adaptív top-level instanciálás** — paraméterezhető (`#NUM_RICH`, `#NUM_NANO`) az ugyanazon RTL-re
- **Mesh router** skálázhatóság — 4 core-nál nagyobb rendszerhez 2D grid topológia (~1 mérnökhónap)
- **Inter-chip Ethernet bridge** — a board-ok közötti mailbox üzenetek Gigabit Ethernet-en, a Neuron OS location transparency valódi tesztje (~1 mérnökhónap)
- **Heterogén verification** és többkonfigurációs test harness (~1 mérnökhónap)
- **Configuration sweep script** — automatikus szintézis és P&R több (Rich, Nano) párra, LUT/timing/throughput riport
- **Összesen: ~3-4 mérnökhónap**

**Platform:** **3 × MicroPhase A7-Lite XC7A200T** (~€320/db) — per-board: 134K LUT, 740 DSP, 13.1 Mbit Block RAM, 512 MB DDR3, Gigabit Ethernet, HDMI, beépített USB-JTAG, 2×50-pin GPIO header. Vivado ML Standard (WebPACK) **ingyenesen** támogatja. Opcionálisan **Kintex-7 XC7K325T** (204K LUT), ha megfelelő konfigurációjú board elérhetővé válik.

**Board-ok szerepe:**

| Board | Szerep | Konfiguráció |
|-------|--------|-------------|
| **#1** | Fejlesztés, F4–F5, elsődleges single-chip teszt | 2 Rich + 8–10 Nano |
| **#2** | Inter-chip teszt, elosztott fabric | 0–2 Rich + 8–10 Nano |
| **#3** | 3-csomópontos háló, tartalék | 0–2 Rich + 8–10 Nano |

**Multi-board példa konfiguráció (3 board Ethernet hálóban):**
- Board A: 2 Rich (supervisor) + 6 Nano — a „vezérlő csomópont"
- Board B: 0 Rich + 10 Nano — worker farm
- Board C: 0 Rich + 10 Nano — worker farm
- **Összesen: 2 Rich + 26 Nano**, elosztva 3 fizikai chipen, Ethernet bridge-dzsel

**Kimenet:**
- `rtl/top_f6_fpga/` — paraméterezhető top-level (Nano és Rich core szám konfigurációs paraméter)
- `rtl/eth_bridge/` — inter-chip Ethernet mailbox bridge
- `rtl/test_harness/` — single-chip és multi-chip stress teszt szcenáriók
- `bring-up/f6_fpga_results.md` — multi-konfiguráció riport (LUT, timing, throughput, power becslés)
- `bring-up/f6_fpga_sweet_spot.md` — javaslat az F6-Silicon (Rich, Nano) konfigurációra

**Konfigurációs sweep — A7-200T kombinációk (134K LUT per board, cél ≤85% kihasználás):**

*Single-board:*

| (Rich, Nano) | Becsült LUT | Kihasználás | Cél |
|--------------|-------------|-------------|-----|
| (0, 20) | ~115K | 86% | Tiszta Nano fabric (SNN max) |
| (1, 14) | ~105K | 78% | „1 supervisor + sok worker" |
| (2, 8) | ~105K | 78% | **Heterogén sweet spot** |
| (2, 10) | ~115K | 86% | Heterogén max |

*Multi-board (2–3 board, Ethernet hálóban):*

| Konfiguráció | Összesen | Cél |
|-------------|---------|-----|
| 2 board: (2,6) + (0,10) | 2R + 16N | F5+ heterogén elosztott |
| 3 board: (2,6) + (0,10) + (0,10) | **2R + 26N** | **F6 elosztott Cognitive Fabric** |
| 3 board: (1,8) + (1,8) + (0,10) | 2R + 26N | Szimmetrikus supervisor |

**Kész kritérium:**
- **Legalább 4 különböző (Rich, Nano) konfiguráció** szintetizálva és futtatva single-board-on
- **A 2 Rich + 8 Nano konfiguráció** stabilan fut single-board-on, minden teszt zöld
- **Multi-board Ethernet bridge** működik: üzenetek átmennek board-ok között, latency mérve
- **Elosztott demó:** 2–3 board hálóban, aktorok cross-chip kommunikálnak, a küldő nem tudja, hogy a target másik chipen van (location transparency)
- **A négy F4 demó** (ping-pong, echo-chain, ping-network, SNN) **fut single-board-on és multi-board-on is**
- **Rich core demó:** C# kód fut a Rich core-on (tömbök, stringek, kivételek)
- **Heterogén demó:** Rich core supervisor koordinál Nano core-okon futó neurális hálót
- **SNN demó:** LIF/Izhikevich hálózat 16+ Nano core-on elosztva, 1-2 Rich coordinator-ral
- **Akka.NET cluster demó:** valós C# kódból fordított actor rendszer hardveresen futva, multi-chip-en
- **Aggregate throughput** mérés (üzenet/sec — single-chip és cross-chip külön)
- **Power becslés** (FPGA fogyasztás × empirikus FPGA→silicon konverziós faktor)
- **Multi-konfiguráció riport** publikálva (LUT, timing, throughput összehasonlítás)

**Függőség:** F5 kész, FPGA stabil (mind Nano, mind Rich core-ral), minden teszt zöld.

**Költség-nagyságrend:** 3 × ~€320 = **~€960** (~$1030) — az F4–F5 board-ok újrahasznosítva az F6-ban. **Vivado ML Standard (WebPACK): $0**. **Mérnöki munka:** 3-4 mérnökhónap.

#### F6-Silicon Zero — „Cognitive Fabric Zero" (IHP 3 mm², első heterogén szilícium)

**Cél:** Az első **heterogén Cognitive Fabric szilícium** — **1 Rich + 8 Nano core, 48 KB on-chip SRAM, 3 mm² IHP SG13G2**. Ez a lépcsőfok az F3 egymagos Tiny Tapeout és a teljes „Cognitive Fabric One" (15 mm²) között. **Potenciálisan €0 költséggel** elérhető az IHP FMD-QNC ingyenes kutatási MPW programján.

**Miért önálló mérföldkő:**
- Az **F3** (TT, 1 Nano) bizonyítja, hogy a core működik szilíciumon
- A **Cognitive Fabric Zero** (IHP, 1R+8N) bizonyítja, hogy a **heterogén multi-core működik szilíciumon** — supervisor + worker, mailbox mesh, sleep/wake, Neuron OS alapok
- A **Cognitive Fabric One** (ChipIgnite, 6R+16N+1S) a teljes skálán bizonyít — benchmarkokkal, publikációval

**Konfiguráció (3 mm² IHP SG13G2):**

| Elem | Darab | Per-core SRAM | Terület |
|------|-------|-------------|---------|
| Rich core + mailbox | 1 | 16 KB | 0.75 mm² |
| Nano core + mailbox | 8 | 4 KB | 8 × 0.18 = 1.44 mm² |
| Mesh router (8-port) | 1 | — | 0.01 mm² |
| Perifériák (QSPI, UART) | — | — | 0.05 mm² |
| Routing overhead (~25%) | — | — | 0.56 mm² |
| **Összesen** | **9 core** | **48 KB** | **~2.81 mm²** |

**Kész kritérium:**
- 9-core heterogén lapka legyártva és a kezedben
- Rich core supervisor + 8 Nano worker fut, mailbox kommunikáció működik
- Ping-pong és echo-chain demó szilíciumon
- SNN demó: 8 LIF neuron, 1 Rich coordinator
- Összehasonlítás az F3 egymagos TT chipjével — a skálázódás érzékelhető

**Függőség:** F5 kész (Rich core RTL tesztelve FPGA-n), F6-FPGA legalább single-board verifikáció kész.

**Költség:** **€0** (IHP FMD-QNC ingyenes kutatási MPW) vagy ~€4,500 (IHP standard ár, 3 mm²). **Ütemezés:** IHP shuttle-ök 2026: március, október, november.

**Megjegyzés:** A Cognitive Fabric Zero **nem helyettesíti** a Cognitive Fabric One-t — kiegészíti. A Zero a „működik szilíciumon" bizonyíték, a One a „jobb, mint a hagyományos" bizonyíték benchmarkokkal.

---

#### F6-Silicon One — „Cognitive Fabric One" MPW tape-out (a teljes demonstráció)

**Cél:** A **„Cognitive Fabric One"** — az F6-FPGA-ban (A7-Lite 200T multi-board hálón) verifikált és sweet spot-ra optimalizált heterogén design **valós szilíciumon**: **6 Rich + 16 Nano + 1 Secure core, 160 KB on-chip SRAM, 15 mm² Sky130 (OpenFrame)**. Ez a chip bizonyítja, hogy ugyanazon a szilíciumon a Cognitive Fabric paradigma **5–22× több hasznos munkát végez** actor-alapú workload-okon, mint egy hagyományos multi-core CPU — miközben determinisztikus, hardveresen izolált, és lineárisan skálázódik. Részletes chip-vízió és benchmark-összehasonlítás: [`docs/architecture-hu.md`](architecture-hu.md) „Cognitive Fabric One" szekció. **Előfeltétel: az F6-FPGA minden kész kritériuma teljesül** — nem indulhat silicon tape-out FPGA-verifikáció nélkül.

**Mikor indul:** **Csak az F6-FPGA összes kész kritériumának teljesülése után**, és csak akkor, ha legalább egy a következőkből igaz:
- A projekt **finanszírozást vagy ipari partnert** kapott a tape-out fedezésére
- A **kereskedelmi termék útvonalra** ([F6.5 Secure Edition](#f65--secure-edition-parallel-tape-out-opcionális), F7 demó hardver) **silicon-előfeltétel** van
- A **valós energia hatékonyság** és **>500 MHz órajel** mérése **kritikus** a következő mérföldkőhöz

**A silicon target az FPGA-n verifikált konfigurációra épül:** az F6-FPGA multi-board sweep-ből kiválasztott (Rich, Nano) sweet spot — várhatóan **6 Rich + 16 Nano + 1 Secure** (ahogy a multi-board hálóban verifikáltuk) — kerül tape-out-ra egyetlen chipre. **ASIC-on a core-ok kisebbek** (std cell vs FPGA LUT), így a multi-board-on elosztva verifikált konfiguráció **egyetlen silicon chipre elfér**, és opcionálisan **felskálázható**, de csak a verifikált router és mesh topológia egyenes kiterjesztéseként.

**Platform-döntés (F6-Silicon indulása előtt):**
- **Sky130 @ eFabless ChipIgnite** — a **Caravel** harness 10 mm² user area, 38 GPIO; az **OpenFrame** harness **15 mm²**, 44 GPIO. ~$14,950 (2026 ár), 100 QFN chip + eval board, ~5 hónap átfutás. **A referencia konfiguráció (6R+16N+1S) az OpenFrame-re épül.**
- **IHP SG13G2 MPW** — európai, ~€1,500/mm² (standard) vagy **€0** (FMD-QNC ingyenes kutatási program, nyílt forráskódú designre). 3 mm²-ért ~€4,500; ütemezés: 2026 március, október, november.
- **Google Open MPW** — ingyenes shuttle (ha nyílik), Sky130, Caravel harness. Nem rendszeres, de a CLI-CPU nyílt forráskódú státusza erős jelölt.
- **Finanszírozás:** NLnet NGI Zero Commons Fund (€5K–€50K, következő deadline: 2026. június 1.), közösségi crowdfunding, ipari partner.

**Új funkciók az F6-FPGA-hoz képest (silicon-specifikus):**
- **Floorplan optimalizáció** — a Rich core-ok központi helyen, a Nano core-ok köré csoportosítva
- **Writable microcode** SRAM — firmware-ből frissíthető opkód viselkedés (FPGA-n BRAM-mal szimulálva, silicon-on dedikált SRAM)
- **Gated store buffer** (GC write barrier batch, Transmeta-inspiráció)
- **Agresszív power-gating** — a nem használt core-ok teljesen hideg állapotban (FPGA-n nem reális)
- **Core-típusok közötti bridge** — Nano ↔ Rich üzenetek és állapot-migráció hardveres optimalizációval
- **Opcionális felskálázás** — ha a silicon budget engedi, az FPGA-verifikált 2R+16N felskálázása 2R+32N-re (a router topológia lineáris kiterjesztése, nem új design)

**Új tervezési munka F6-Silicon-hoz (az F6-FPGA-n felül):**
- Floorplan: **~2–4 mérnökhét**
- Power gating és clock tree CTS: **~1 mérnökhónap**
- DFT scan chain insertion: **~2 mérnökhét**
- Tape-out checklist és sign-off: **~1 mérnökhónap**
- **Összesen: ~2-3 mérnökhónap plusz munka**

**Kimenet:**
- `mpw/` — eFabless/IHP submission könyvtár
- `mpw/firmware/` — boot-loader, mikrokód image, Nano/Rich kód-loader
- `hw/chipignite-board/` — ChipIgnite (vagy IHP) bring-up board

**Kész kritérium:**
- „Cognitive Fabric One" heterogén lapka legyártva és a kezedben
- **Az F6-FPGA-n verifikált összes demó** megismételve valós szilíciumon
- **Actor throughput benchmark** — üzenet/sec mérés, összehasonlítás ugyanakkora területű RISC-V multi-core referenciával
- **SNN benchmark** — LIF/Izhikevich hálózat, lineáris skálázódás demonstrálva
- **Energia / teljesítmény mérés** — event-driven workload-okon, idle power mérés (alvó core-ok), összehasonlítás ARM Cortex-M4 / RISC-V RV32 ellen
- **Fault tolerance demó** — worker crash → supervisor restart, a rendszer nem áll le
- **Publikációs anyag** — benchmark riport, a „Cognitive Fabric One" narratíva: *„ugyanazon a szilíciumon 5–22× több hasznos munka actor-alapú workload-okon"*

**Függőség:** **F6-FPGA kész** (minden kész kritérium teljesül), sweet spot kiválasztva, multi-konfiguráció riport elérhető.

**Költség-nagyságrend:** ~$14,950 (eFabless ChipIgnite OpenFrame, 15 mm², 100 QFN chip + eval board), vagy ~€4,500 (IHP SG13G2 3 mm², kisebb konfiguráció: 1R+8N), vagy **€0** (IHP ingyenes kutatási MPW / Google Open MPW, ha elérhető). **NLnet NGI Zero Commons Fund** pályázattal akár a teljes F6-Silicon fedezhető (€5K–€50K).

---

### F6.5 — Secure Edition parallel tape-out (opcionális)

**Cél:** A CLI-CPU Secure Edition parallel tape-out változata, amely a Secure Element / TEE / JavaCard piacot célozza. Ugyanaz az alap architektúra (Nano + Rich core), **plusz** Secure Element-specifikus hardveres komponensek: Crypto Actor (SPECT-ihletett), TRNG, PUF, secure boot + attestation, tamper detection, DPA countermeasures, OTP kulcstárolás.

**Részletes dokumentum:** [`docs/secure-element-hu.md`](secure-element-hu.md) — ez rögzíti a teljes Secure Element pozicionálást, a TROPIC01 (Tropic Square első nyílt kereskedelmi SE) részletes elemzését, a megkülönböztető architektúrális előnyöket (multi-core, több független security domain egyetlen chipen), a tanúsítási útvonalat (EAL-5+), és a konkrét termékcsaládot (open banking card, open eSIM, open eID, open FIDO2 authenticator, open TPM, open hardware wallet, open V2X, open medical SE).

**Miért „F6.5" és nem „F6"?** Mert ez **egy parallel tape-out variáns**, nem egy önálló fázis. Ugyanaz a F5 RTL alap, csak kiegészítve a Secure Element hardveres komponensekkel. Az F6-Silicon Cognitive Fabric tape-out után **~6 hónappal** készíthető el — a Secure Edition silicon-előfeltétel, ezért az F6.5 az F6-Silicon variánsra épít, **nem** az F6-FPGA-ra.

**Új funkciók az F6-hoz képest:**
- **Crypto Actor** — SPECT-ihletett dedikált kriptográfiai egység (AES, SHA, ECC, post-quantum: Kyber/Dilithium/Falcon)
- **TRNG** — true random number generator (ring oscillator jitter + whitening)
- **PUF** — Physically Unclonable Function (SRAM PUF + error correction)
- **OTP / eFuse tároló** — write-once root key storage
- **Secure boot + remote attestation** — mérési lánc és chip identity
- **Tamper detection** — 6 komponens (EM pulse, voltage glitch, temperature, laser, active shield, frequency monitor)
- **DPA countermeasures** — masking, hiding, constant-time, noise injection

**Becsült plusz tervezési munka:** ~30-50 mérnökhónap (F6-hoz képest), egy 3-5 fős csapat számára ~1-1.5 év.

**Becsült plusz terület:** ~64k std cell Sky130-on (~32% növekedés az F6 ~200k-hoz képest). **Belefér** egy ChipIgnite OpenFrame MPW-ba (~15 mm²) vagy egy IHP SG13G2 MPW-ba (~15 mm²).

**Kész kritérium:**
- F6.5 tape-out sikeresen elkészül
- Első bring-up board legyártva
- Crypto Actor helyesen implementálja a cél algoritmusokat
- Tamper detection triggerel a tesztelt támadásokra (voltage glitch, EM, laser)
- TRNG megfelel a NIST SP 800-90B entrópia követelményeknek
- Első **Common Criteria pre-evaluation** megkezdődik

**Függőség:** F6-Silicon Cognitive Fabric tape-out kész (az F6-FPGA önmagában nem elegendő, mert a Secure Element komponensek — Crypto Actor, TRNG, PUF, tamper detection — silicon-specifikus hardvert igényelnek).

**Költség-nagyságrend:** ~$10-50k (MPW tape-out) + ~$0.5-1.2M (plusz mérnökbér) + ~$400k-1M (later Common Criteria evaluation).

**Tanúsítási cél (F7 utáni):** **Common Criteria EAL-5+** a BSI (Németország) vagy ANSSI (Franciaország) akkreditált laborban. **Idő**: 2-3 év az evaluation-re. **Várható első kereskedelmi termékek**: 2033-2034.

---

### F7 — Demonstrációs platform + Neuron OS fejlesztői SDK

**Cél:** A Cognitive Fabric + Neuron OS kombináció mint **demonstrálható, fejleszthető platform** több valós use-case-re. A `Neuron OS` itt lép ki kutatási státuszból valós fejlesztői platform szintre.

**A Neuron OS teljes víziója egy külön dokumentumban**: [`NeuronOS/docs/vision-hu.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md). Röviden: aktor-alapú operációs rendszer, amely az Erlang OTP víziót valósítja meg hardveres támogatással (Erlang in silicon). Everything is an actor, shared-nothing, let it crash, supervision hierarchia, capability-alapú biztonság, hot code loading, location transparency.

**Kimenet:**
- **Referencia PCB-k** több use-case-re:
  - IoT szenzor node (QSPI flash, PSRAM, LoRa/WiFi, néhány szenzor)
  - Akka.NET cluster demó dev kit (több chip hálózatban)
  - SNN inference board (MNIST/CIFAR szintű feladatra)
- **Neuron OS fejlesztői SDK**:
  - `NeuronOS.Core` — aktor alapkönyvtár (Actor<T>, Supervisor, Spawn, Send, Receive)
  - `NeuronOS.Devices` — device aktor library (UART, GPIO, QSPI, timer)
  - `NeuronOS.Distributed` — inter-chip aktor protokoll
  - `dotnet publish` target Neuron OS-re
  - VSCode / VS extension debugger aktor message replay-jel
  - NuGet csomagok publikus feed-en
- **Referencia C# demó alkalmazások:**
  - Akka.NET-szerű actor cluster (supervisor hierarchia, hot code loading)
  - LIF spiking neural network 16+ Nano core-on
  - IoT edge gateway (szenzor handlerek + LoRa protokoll)
  - Multi-agent szimuláció (Boids, Conway's Game of Life kiterjesztése)
- **Publikációs anyag:** cikk, előadás, demo video — az egész projektet bemutató narratíva, Linux Foundation projekt-státusz kérelem

**Függőség:** F6 kész, chip a kézben, Neuron OS alfa (F5 óta) stabil.

**Megjegyzés a Neuron OS fázisolásáról:** A Neuron OS **nem önálló fázis**, hanem **organikusan épül fel** az F1-F7 fázisok mentén:
- **F1**: minimal `NeuronOS.Core` library a C# szimulátorban (Actor<T>, in-memory mailbox)
- **F3**: egy-aktoros bootloader a Tiny Tapeout chipen (echo neuron demó)
- **F4**: 4-aktoros rendszer scheduler + router kezdeti implementációval
- **F5**: teljes supervision fa, per-core GC, capability-alapú isolation, Roslyn source generator a `[RunsOn]` attribútumra
- **F6**: hot code loading, writable microcode, elosztott aktorok több chipen
- **F7**: fejlesztői SDK, VSCode integráció, NuGet publikálás, valódi alkalmazás demók

Részletek és fejlesztői API példák: [`NeuronOS/docs/vision-hu.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md).

---

## Becsült munkaóra összesítő

A becslések **AI-asszisztált fejlesztést** feltételeznek (Claude Code pair programming), ami az F0–F2.2b tényleges ráfordítása alapján ~30–40%-os produktivitásnövekedést jelent a kódgenerálás, tesztírás és dokumentáció területén. A fizikai munka (PCB, bring-up, FPGA) esetén az AI hatás kisebb.

| Fázis | Leírás | Becsült óra | Mérnökhónap* | Státusz |
|-------|--------|-------------|-------------|---------|
| **F0** | Specifikáció (3 dokumentum, ~3500+ sor) | ~60 | ~0.4 | ✅ KÉSZ |
| **F1** | C# referencia szimulátor (48 opkód, 218 teszt, 4 iteráció TDD) | ~120 | ~0.8 | ✅ KÉSZ |
| **F1.5** | Linker, Runner, Samples (259 teszt) | ~80 | ~0.5 | ✅ KÉSZ |
| **F2** | RTL (Verilog + cocotb, 7 alszakasz) | ~350 | ~2.2 | 🔧 Folyamatban |
| — F2.1 | ALU (32-bit egész) | ~30 | | ✅ KÉSZ |
| — F2.2a | Decoder (hossz + opkód) | ~40 | | ✅ KÉSZ |
| — F2.2b | Decoder (microcode ROM) | ~50 | | ✅ KÉSZ |
| — F2.3 | Stack cache (4×32-bit TOS + spill) | ~50 | | ⬜ Tervezett |
| — F2.4 | QSPI vezérlő | ~70 | | ⬜ Tervezett |
| — F2.5 | Golden vector harness | ~35 | | ⬜ Tervezett |
| — F2.6 | Yosys szintézis (Sky130) | ~30 | | ⬜ Tervezett |
| — F2.7 | FPGA validáció (A7-Lite) | ~45 | | ⬜ Tervezett |
| **F3** | Tiny Tapeout submission (1 Nano + Mailbox, bring-up board) | ~220 | ~1.4 | ⬜ Tervezett |
| **F4** | Multi-core Cognitive Fabric FPGA (4× Nano, router, sleep/wake) | ~360 | ~2.3 | ⬜ Tervezett |
| **F5** | Rich core + heterogén rendszer (teljes CIL, GC, FPU, source gen.) | ~720 | ~4.5 | ⬜ Tervezett |
| **F6-FPGA** | Heterogén demonstráció (3× A7-Lite, mesh, Ethernet bridge) | ~480 | ~3 | ⬜ Tervezett |
| **F6-Si Zero** | IHP 3 mm² (1R+8N, tape-out + bring-up) | ~360 | ~2.3 | ⬜ Tervezett |
| **F6-Si One** | ChipIgnite 15 mm² (6R+16N+1S, tape-out + bring-up) | ~360 | ~2.3 | ⬜ Tervezett |
| **F6.5** | Secure Edition (Crypto Actor, TRNG, PUF, tamper, DPA) | ~5 600 | ~35 | ⬜ Opcionális |
| **F7** | Neuron OS SDK + demó platform (PCB-k, SDK, alkalmazások) | ~520 | ~3.3 | ⬜ Tervezett |
| | **Összesen (F6.5 nélkül)** | **~3 630** | **~23** | |
| | **Összesen (F6.5-tel)** | **~9 230** | **~58** | |

\* 1 mérnökhónap ≈ 160 óra (4 hét × 40 óra). Az F6.5 külön csapat (3–5 fő), a többi 1 fős AI-asszisztált fejlesztéssel becsülve.

**Megjegyzések:**
- A KÉSZ fázisok (F0, F1, F1.5, F2.1–F2.2b) becsült órái a tényleges ráfordítást tükrözik — ezek **már AI-asszisztált** értékek
- Az F4 becslés alacsonyabb, mint ami core-szám alapján várható, mert a Nano core RTL **újrafelhasználható** az F2/F3-ból — az érdemi új munka a router, sleep/wake és demók
- Az F6-Silicon Zero és One **párhuzamosan** is futhat az F6-FPGA után, de egymás után is — a táblázat az érdemi mérnöki munkát mutatja, a gyártási várakozási időt nem
- Az F6.5 (Secure Edition) egy **külön csapatot** igényel, és a Common Criteria tanúsítás további ~2–3 év
- A becslések **tiszta mérnöki munkaidőt** tartalmaznak — a gyártási átfutás (TT ~5 hó, ChipIgnite ~5 hó, IHP ~4 hó), szállítás és bring-up várakozás nincs benne

### NLnet NGI Zero Commons Fund összehangolás

Az [NLnet pályázat](nlnet-application-draft-en.md) (v1.1, beadva 2026-04-14) **€35 000**-t kért **18 hónapra**, ~900 óra part-time munkát feltételezve (~€36/h, ebből ~€2 440 hardver).

**Mérföldkő-megfeleltetés:**

| NLnet mérföldkő | Roadmap fázis | Pályázat budget | Pályázat óra† | Roadmap becslés | Lefedettség |
|------------------|---------------|-----------------|---------------|-----------------|-------------|
| **M1:** RTL | F2 | €8 000 | ~222 h | ~350 h | teljes |
| **M2:** Tiny Tapeout | F3 | €7 000 | ~159 h | ~220 h | teljes |
| **M3:** FPGA multi-core | F4 | €8 000 | ~190 h | ~360 h | teljes |
| **M4:** Rich core RTL start | F5 (kezdet) | €7 000 | ~194 h | ~200 h (a 720-ból) | ~28% |
| **M5:** Doku & közösség | (beépítve) | €5 000 | ~139 h | ~100 h | teljes |
| **Összesen** | F2–F5 start | **€35 000** | **~904 h** | **~1 230 h** | |

† Személyi óra = (budget − hardverköltség) ÷ €36/h

**Eltérés magyarázata:** A roadmap teljes becslése (~1 230 h az NLnet scope-ra) **~330 órával meghaladja** a pályázatban vállalt ~900 órát. Ez normális nyílt forráskódú pályázatoknál — a támogatás a **költségek fedezését** szolgálja, nem az összes ráfordított idő 100%-os kompenzálását. A különbség (~27%) a fejlesztő **saját hozzájárulása** a projekthez (unfunded own contribution), ami az open-source fejlesztés szokásos modellje.

**A pályázat vállalásai teljesíthetők**, mert:
1. Az F0–F2.2b tényleges tempó (~260 h / ~2 hét intenzív sprint) **meghaladja** a pályázat ütemezését
2. Az AI-asszisztált fejlesztés (Claude Code) a KÉSZ fázisoknál bizonyítottan ~30–40%-os gyorsulást ad a kódgenerálás, teszt és dokumentáció területén
3. Az F2 RTL alapjai (ALU, decoder, microcode ROM) már **készen vannak** — a pályázat indulása előtt
4. Az F4 core-instanciálás az F2/F3 RTL közvetlen újrafelhasználása — az érdemi új munka (router, sleep/wake) jól körülhatárolt

---

## Függőségi gráf

```
                          ┌── Nano core út ──┐        ┌── Rich core út ──┐
                          │                  │        │                  │
F0 ──► F1 ──► F2 ──► F3 ──┘──► F4 ──►────────┘─► F5 ──┴──► F6-FPGA ──► F7
  spec   sim    RTL    TT       multi-         heterogén   verifikált   demo
              │         1×      Nano          (Rich+Nano) demonstráció + Neuron
              │         +        4×            FPGA       (3× A7-Lite    OS SDK
              │        mbox     FPGA         (A7-Lite     200T multi-    ▲
              │              ▲                200T)       board háló)    │
              └──── FPGA ────┘                                │          │
                 (opcionális                                  │          │
                  korai F2 után)                              │          │
                                                              ▼          │
                                                       F6-Silicon Zero ──┤
                                                       „Cognitive        │
                                                        Fabric Zero"     │
                                                       (IHP 3mm²,        │
                                                        1R+8N, €0?)      │
                                                              │          │
                                                              ▼          │
                                                       F6-Silicon One ───┘
                                                       „Cognitive
                                                        Fabric One"
                                                       (ChipIgnite 10mm²,
                                                        6R+16N+1S, ~$15K)
                                                        Sky130 / IHP MPW
                                                        ~$10k)
                                                              │
                                                              ▼
                                                         F6.5 ──► Secure Edition
                                                          parallel tape-out
                                                          (Crypto Actor + TRNG +
                                                          PUF + tamper + DPA)
                                                              │
                                                              ▼
                                                     Common Criteria EAL-5+
                                                     evaluation (~2-3 év)
                                                              │
                                                              ▼
                                                   Kereskedelmi SE termékek
                                                   (open wallet, eSIM, eID,
                                                    FIDO, TPM, V2X, medical)
```

Az F2 után opcionálisan FPGA-n is futtatható a CIL-T0 subset, még F3 (Tiny Tapeout) előtt — ez segít a bring-up board tervezésében.

## Három kulcs pivot a roadmap történetében

**1. pivot — F4: Cognitive Fabric irány (shared-nothing multi-core)**

A **korábbi** F4 a „CIL object model + GC FPGA-n" volt, a mostani **új** F4 viszont a „4-core multi-core FPGA Cognitive Fabric". Az object model + GC átcsúszott F5-re. A **hardware alap (stack-gép core) nem változik** — F3-ból emelődik át F4-be, csak 4 példányban. Ezzel a pivot **minimális kódcserével** megvalósítható, és megőrzi minden eddigi F0-F3 munkát. Ez a lépés megkülönbözteti a CLI-CPU-t a történelmi picoJava/Jazelle bukásoktól.

**2. pivot — F5: Heterogén Nano + Rich terminológia**

A korábbi „F5 — CIL Object Model + GC egymagos kiterjesztés" címet átneveztük **„F5 — Rich core (teljes CIL) FPGA-n, első heterogén rendszer"** címre. Technikailag a tartalom majdnem ugyanaz (teljes CIL kiterjesztés), de most már explicite úgy fogalmazzuk, hogy itt **születik meg a Rich core** mint a Nano core „nagy testvére". Az F6 ezek után egy **heterogén Nano+Rich multi-core chip**, analóg módon az ARM big.LITTLE, Apple P/E-core, Intel Alder Lake modellekhez. Lásd `docs/architecture-hu.md` „Heterogén multi-core: Nano + Rich" szekciót.

**3. pivot — F6: FPGA-verifikáció kötelező a silicon előtt, A7-Lite 200T multi-board**

A **korábbi** F6 egyetlen nagy FPGA-t célzott (K7-480T, majd K7-325T). A **mostani** F6 a **reálisan elérhető és kézben lévő platformra** épít: **3 × MicroPhase A7-Lite XC7A200T** (3 × 134K = 402K LUT aggregált kapacitás, Gigabit Ethernet hálóban). Ez **reálisabb teszt**, mert a valódi Cognitive Fabric is multi-chip lesz — a location transparency és az inter-chip mailbox bridge **csak multi-board-on** tesztelhető. A Kintex-7 K325T opcionális kiegészítés, ha megfelelő konfigurációjú board elérhetővé válik. **Az F6-Silicon csak az F6-FPGA teljes verifikációja után indulhat** — nincs silicon tape-out olyan design-nal, ami nem futott FPGA-n.

## Mai státusz

**F0 koncepcionálisan készen van.** Hét dokumentum a `docs/` és a `README.md` alatt együtt ~3500+ sor, belsőleg konzisztens projekt-terv a **hárompályás pozicionálással** (Cognitive Fabric + Trustworthy Silicon + Secure Edition), a heterogén Nano+Rich multi-core modellel, a silicon-grade security pozicionálással, a Neuron OS vízióval, és a Secure Element stratégiai tervvel (F6.5 parallel tape-out).

**F1 — C# referencia szimulátor lezárva.** Az `src/CilCpu.Sim` és `src/CilCpu.Sim.Tests` projektek minden CIL-T0 spec által rögzített **48 opkódot** implementálják, minden hardveres trap tesztelt. Az **F1 aranypélda**: `Fibonacci(20) = 6765` zöld. A fejlesztés **4 iterációban** zajlott szigorú TDD-vel, minden iterációhoz Devil's Advocate review.

**F1.5 — Linker, Runner, Samples lezárva.** A `CilCpu.Linker` Roslyn .dll → CIL-T0 pipeline, a `CilCpu.Sim.Runner` CLI futtatóeszköz (`run` / `link` parancsok), és a `samples/PureMath` példaprogram kész. **259 zöld xUnit teszt**, **0 warning, 0 error**. A teljes pipeline (C# → Roslyn → linker → szimulátor) end-to-end tesztelve, TDD-vel fejlesztve, Devil's Advocate review-val.

**Következő érdemi lépés:** **F2 — RTL** kezdete (Verilog vagy Amaranth HDL döntés, cocotb testbench infrastruktúra).

## Finanszírozási akcióterv

A CLI-CPU szilícium mérföldkövei (F3 Tiny Tapeout, F6-Silicon Zero/One) külső finanszírozást igényelnek. Az alábbi akcióterv a reálisan elérhető forrásokat priorizálja.

### Pályázati lehetőségek

| Forrás | Összeg | Deadline | Illeszkedés | Prioritás |
|--------|--------|----------|-------------|-----------|
| **NLnet NGI Zero Commons Fund** | €5K–€50K | **2026. június 1.** (13. kör) | Kifejezetten „libre silicon"-t említ, nyílt forráskódú projekt | **#1 — azonnal beadni** |
| **IHP FMD-QNC ingyenes MPW** | €0 (kutatási) | 2026: okt, nov; 2027: márc | Nyílt forráskódú, nem-kereskedelmi design | **#2 — regisztrálni** |
| **Google Open MPW** | $0 (szponzorált) | Nem rendszeres, figyelni | Sky130, Caravel harness, nyílt design | **#3 — figyelni** |
| **EU CHIPS Act** pályázatok | Változó | Folyamatos | Európai nyílt hardver | Hosszú táv |

### Közösségi finanszírozás

| Platform | Cél | Mikor |
|----------|-----|-------|
| **GitHub Sponsors** | Folyamatos kis összegek, láthatóság | Azonnal beállítani |
| **Open Collective** | Transzparens pénzkezelés, közösségi döntéshozatal | F3 előtt |
| **Crowd Supply** | Hardware kampány (bring-up board, chip) | F3 tape-out közeledtével |

### Költségvetés-szcenáriók

| Szcenárió | Összeg | Mit fedez |
|-----------|--------|-----------|
| **A: Saját zseb** | ~€2,400 | 3× A7-Lite 200T (F4–F6 FPGA) + 1× TT 16 tile (F3) + bring-up |
| **B: NLnet €15K** | ~€15K | A szcenárió + IHP „Cognitive Fabric Zero" (1R+8N, 3 mm²) + mérnöki eszközök |
| **C: NLnet €30K** | ~€30K | B szcenárió + ChipIgnite „Cognitive Fabric One" (6R+16N+1S, 15 mm²) |
| **D: NLnet €50K** | ~€50K | C szcenárió + 2. tape-out iteráció + konferencia/publikáció + alvállalkozói mérnöki munka |

### Ütemezés

```
2026 ápr     ─── NLnet pályázat előkészítése (47 nap!)
2026 jún 1   ─── NLnet NGI Zero Commons Fund deadline
2026 jún-szept── F2 RTL fejlesztés + FPGA bring-up
2026 okt     ─── IHP ingyenes MPW regisztrációs deadline
2026 nov     ─── IHP shuttle (ha elfogadták)
2027 Q1      ─── F3 Tiny Tapeout submission (TTSKY26a vagy későbbi)
2027 Q2-Q3   ─── F4–F5 FPGA fejlesztés (3× A7-Lite 200T)
2027 Q4      ─── F6-FPGA verifikáció kész
2028 Q1      ─── F6-Silicon Zero (IHP) / One (ChipIgnite) submission
2028 Q3      ─── Első szilícium a kézben
```

**A legfontosabb azonnali akció:** NLnet NGI Zero Commons Fund pályázat előkészítése — **47 nap van a 2026. június 1-i deadline-ig**. A CLI-CPU projekt profilja (nyílt forráskódú libre silicon, újszerű Cognitive Fabric architektúra, actor-natív processzor, Neuron OS vízió) **kifejezetten erős jelölt**.

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.1 | 2026-04-17 | Becsült munkaóra összesítő + NLnet pályázati összehangolás hozzáadva. AI-asszisztált fejlesztési becslések. |
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
