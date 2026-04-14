# NLnet NGI Zero Commons Fund — Pályázati vázlat

> **Deadline:** 2026. június 1., 12:00 CEST
> **Form:** https://nlnet.nl/propose/
> **Kiírás:** NGI Zero Commons Fund (13. kör)
> **Státusz:** VÁZLAT — felülvizsgálatra vár
> **Megjegyzés:** A pályázat **angolul kerül beadásra** (NLnet követelmény). Ez a magyar változat a te tájékoztatásodra készült — hogy tudd, mit mond az angol szöveg, és véleményezhesd mielőtt beadjuk. A beadandó angol verzió: `nlnet-application-draft-en.md`.

> English version: [nlnet-application-draft-en.md](nlnet-application-draft-en.md)

> Version: 1.0

---

## Pályázati kiírás

NGI Zero Commons Fund

## Pályázat neve

**CLI-CPU: Nyílt forráskódú Cognitive Fabric processzor — natív CIL végrehajtás libre szilíciumon**

## Weboldal / Wiki

https://github.com/FenySoft/cli-cpu

---

## Kivonat

A projekt referencia implementációs fázisa (F1.5) **kész és tesztelve van**: a C# szimulátor lefedi mind a 48 CIL-T0 opkódot (**267 zöld xUnit teszt**), a Roslyn-alapú CIL-T0 linker működik (C# forráskód → .dll → CIL-T0 bináris), és a CLI futtatóeszköz (`run` / `link` parancsok) kész. Minden TDD módszertannal fejlesztve, Devil's Advocate review-val. **Ez a pályázat a bizonyított szoftveres szimulációból a fizikai hardverbe való átmenetet finanszírozza.**

A CLI-CPU egy nyílt forráskódú processzor-architektúra, amely a .NET Common Intermediate Language (CIL) bájtkódot **natívan, hardveresen hajtja végre** — JIT fordítás, AOT transzláció vagy interpreter nélkül. Ahelyett, hogy egymagos sebességben versenyezne (ezt a picoJava és a Jazelle már megpróbálta és megbukott), a CLI-CPU **sok kis, független CIL-natív core-t** helyez egyetlen chipre, amelyek kizárólag **hardveres mailbox FIFO-kon** kommunikálnak, shared-nothing modellben. Ez a „Cognitive Fabric" architektúra **teljesen kiküszöböli a cache koherencia overhead-et**, és a teljesítmény lineárisan skálázódik a core-számmal.

**A pályázat három konkrét eredményt céloz:**

1. **RTL implementáció (F2):** A meglévő, teljesen tesztelt C# referencia szimulátor átültetése szintetizálható Verilog/Amaranth HDL-re, cocotb golden-vector teszteléssel a szimulátor ellen.

2. **Első szilícium (F3):** Egyetlen Nano core + hardveres mailbox tape-out Tiny Tapeout Sky130 shuttle-ön — a projekt első fizikai chipje, Fibonacci(20) és „echo neuron" demóval UART-on.

3. **Multi-core FPGA verifikáció (F4):** 4 Nano core demonstráció MicroPhase A7-Lite XC7A200T FPGA board-on, hardveres mailbox-okkal, shared-nothing, event-driven működéssel — az első bizonyíték, hogy a Cognitive Fabric skálázódik.

**Miért releváns az NGI ökoszisztéma számára:**

- **Libre silicon end-to-end:** Sky130 PDK + OpenLane2 (ASIC) és OpenXC7/Yosys (FPGA) — teljesen reprodukálható, auditálható, nyílt toolchain.
- **8 millió fejlesztő kódja natívan fut:** Minden .NET nyelv (C#, F#, VB.NET) CIL-re fordul. A CLI-CPU az első hardver, amely ezt az ökoszisztémát közvetlenül futtatja — runtime overhead és zárt toolchain-függőség nélkül.
- **Actor-natív biztonság:** A per-core memória-izoláció a szilícium fizikai tulajdonsága (privát SRAM, nincs shared memory), nem szoftveres absztrakció. Architektúrálisan immunis a Spectre/Meltdown típusú támadásokra. Determinisztikus végrehajtás, ami lehetővé teszi az ISA formális verifikációját.
- **Európai szuverenitás:** Teljesen nyílt processzor-design, amelyet bármely európai entitás gyárthat, auditálhat és tanúsíthat — függetlenül US/ázsiai IP licenszeléstől (ellentétben az ARM, RISC-V kereskedelmi core-ok vagy x86 esetével).

---

## Volt-e korábbi tapasztalatod releváns projektekkel vagy szervezetekkel?

A pályázó széleskörű tapasztalattal rendelkezik:

- **.NET ökoszisztéma:** 20+ év professzionális C#/.NET fejlesztés, beleértve Akka.NET aktor rendszereket, Avalonia UI cross-platform alkalmazásokat, és Android/iOS telepítést.
- **QuantumAE/JokerQ:** Egy éles, production Akka.NET aktor-alapú rendszer (55+ aktor, NAV-I adóhatósági integráció, NFC smart card kommunikáció, offline-first persistencia) — ez a rendszer szolgál a CLI-CPU aktor-natív architektúrájának valós validációs céljaként.
- **Hardver-közeli:** FPGA fejlesztési workflow-k ismerete, nyílt forráskódú EDA eszközök, és a Sky130/IHP nyílt szilícium ökoszisztéma.

A CLI-CPU projekt önmagában 7 architektúra dokumentumot (~4000+ sor), egy teljesen tesztelt referencia szimulátort, egy CIL-T0 linkert és egy CLI futtatóeszközt hozott létre — mindezt szigorú TDD módszertannal.

---

## Kért összeg

**€35,000**

## Mire megy a kért összeg

| Mérföldkő | Leírás | Összeg | Időkeret |
|-----------|--------|--------|----------|
| **M1: RTL (F2)** | Verilog/Amaranth HDL implementáció: egyetlen Nano core. Verilator + cocotb testbench, ami megfelel mind a 267 C# szimulátor tesztnek. Yosys szintézis Sky130-ra. | €8,000 | 1-4. hónap |
| **M2: Tiny Tapeout (F3)** | 16 tile-os Tiny Tapeout submission: Nano core + mailbox + UART. Bring-up PCB tervezés (KiCad). Post-silicon verifikáció. | €7,000 | 4-7. hónap |
| **M3: FPGA multi-core (F4)** | 3× MicroPhase A7-Lite XC7A200T board (~€960). 4-core Cognitive Fabric FPGA-n: shared-nothing, mailbox mesh, sleep/wake, event-driven. Ping-pong és echo-chain demók. | €8,000 | 6-10. hónap |
| **M4: Rich core RTL (F5 kezdet)** | Rich core (teljes CIL) RTL tervezés kezdete: objektum modell, GC assist, kivételkezelés, FPU. Heterogén Nano+Rich FPGA demó. | €7,000 | 8-12. hónap |
| **M5: Dokumentáció és közösség** | Angol nyelvű architektúra dokumentáció, contribution guide, CI/CD pipeline, közösségi outreach (blogposztok, konferencia lightning talk). | €5,000 | Folyamatos |
| **Összesen** | | **€35,000** | 12 hónap |

**Hardver költségek a mérföldkövekben:**
- 3× A7-Lite XC7A200T FPGA board: ~€960
- 1× Tiny Tapeout 16 tile-os submission: ~€1,200
- Bring-up PCB + alkatrészek: ~€80
- Szállítás, kábelek, adapterek: ~€200
- **Hardver összesen: ~€2,440**

---

## Meglévő finanszírozási források

A projekt jelenleg a pályázó saját finanszírozásából működik. Nem érkezett külső finanszírozás. Nincs más függőben lévő pályázat ugyanerre a munkára.

Tervezett kiegészítő finanszírozás (nem átfedő ezzel a pályázattal):
- **IHP SG13G2 ingyenes MPW:** A 2026 októberi shuttle-re tervezett pályázat (F6 heterogén szilícium — túlmutat ezen pályázat hatáskörén).
- **Közösségi finanszírozás:** GitHub Sponsors / Open Collective a projekt során kerül felállításra (folyamatos karbantartásra, nem ezen pályázat által fedezve).

---

## Összehasonlítás meglévő megoldásokkal

| Projekt | Megközelítés | Korlát | CLI-CPU különbség |
|---------|-------------|--------|------------------|
| **RISC-V** (SiFive, stb.) | Nyílt ISA, regiszter-gép | C/Rust-ot natívan futtat, de a .NET nehéz runtime-ot igényel (JIT/AOT/interpreter) | A CLI-CPU CIL-t natívan futtat — nincs runtime réteg |
| **ARM Jazelle** (2001) | Java bytecode HW-ben | Egymagos, egynyelvű, shared-memory — a JIT gyorsabb lett | Multi-core, többnyelvű (.NET), shared-nothing, actor-natív |
| **Sun picoJava** (1997) | Java bytecode CPU | Ugyanaz a kudarc, mint a Jazelle — egymagos sebességverseny | A CLI-CPU nem egymagos sebességben versenyez; párhuzamossággal nyer |
| **Intel Loihi 2** | Neuromorphic | Rögzített neuron modell, nem programozható | A CLI-CPU core-ok tetszőleges CIL programot futtatnak |
| **SpiNNaker 2** | Programozható neuromorphic (ARM core-ok) | Csak C/C++, akadémiai, nem .NET natív | CLI-CPU: teljes .NET ökoszisztéma, nyílt forráskód |
| **OpenTitan** | Nyílt forráskódú secure element | RISC-V alapú, egymagos, nincs aktor modell | CLI-CPU: multi-core, actor-natív, .NET programozható |

**Egyetlen létező nyílt forráskódú projekt sem kombinálja:** natív CIL végrehajtás + multi-core shared-nothing + hardveres mailbox + libre silicon + actor-natív architektúra. A CLI-CPU egy új kategória.

---

## Jelentős technikai kihívások

1. **CIL-RTL hűség:** A referencia C# szimulátor definiálja a „golden" viselkedést mind a 48 CIL-T0 opkódra. Az RTL-nek bitről-bitre meg kell egyeznie. Kihívás: a CIL stack-gép szemantika (változó hosszúságú utasítások, implicit operandus verem) gondos pipeline tervezést igényel. Mitigáció: cocotb golden-vector tesztelés minden meglévő szimulátor teszt ellen.

2. **Tiny Tapeout terület-budget:** A Nano core (~9,100 std cell) + mailbox + UART-nak el kell férnie 12-16 tile-ban (~12K-16K kapu). Kihívás: a routing overhead a Sky130-on a tile terület 30-40%-át is felemésztheti. Mitigáció: iteratív szintézis terület-optimalizációval, Yosys becslésekkel kezdve a submission előtt.

3. **Multi-core mailbox routing:** A 4-core FPGA fabric fair, deadlock-mentes üzenet-routert igényel. Kihívás: éheztetés elkerülése, ha több core egyszerre küld. Mitigáció: round-robin arbiter per-core FIFO pufferekkel (jól ismert tervezési minta).

4. **QSPI memória latency:** Az on-chip SRAM korlátozott (4-16 KB core-onként). A kód és adat QSPI flash/PSRAM-ról jön 10-50 ciklus latency-vel. Kihívás: elfogadható IPC elérése külső memóriával. Mitigáció: prefetch buffer szekvenciális kód fetch-hez, TOS (top-of-stack) cache a forró stack adatokhoz.

5. **Rich core komplexitás (M4):** A teljes CIL utasításkészlet (~220 opkód) objektum modellt, GC-t, kivételeket, FPU-t igényel. Kihívás: beférni az FPGA LUT budget-be a Nano core-ok mellett. Mitigáció: inkrementális megközelítés — Rich core önállóan, majd integráció a Nano fabric-kel.

---

## A projekt ökoszisztémája

**Upstream függőségek (mind nyílt forráskódú):**
- Sky130 PDK (SkyWater/Google) — ASIC gyártás
- OpenLane2 (eFabless) — ASIC build flow
- Yosys + nextpnr / OpenXC7 — FPGA szintézis
- Verilator + cocotb — szimuláció és verifikáció
- .NET SDK (Microsoft, MIT licensz) — C# szimulátor, linker, teszt framework

**Downstream felhasználók és stakeholderek:**
- **.NET fejlesztői közösség (~8M fejlesztő):** Bármely CIL-re fordított C#/F# kód potenciálisan futhat a CLI-CPU hardveren. Az Akka.NET és Orleans aktor framework közösségek természetes korai adoptálók.
- **Neuromorphic kutatói közösség:** A CLI-CPU programozható core-jai rugalmas SNN szimulációs platformot kínálnak, ellentétben a rögzített modellű chipekkel (Loihi, TrueNorth).
- **IoT / beágyazott biztonság:** A shared-nothing architektúra hardver-szintű izolációt biztosít MMU/TrustZone komplexitás nélkül.
- **Nyílt hardver közösség:** A projekt egy újszerű CIL-natív core designt ad a libre silicon ökoszisztémához, CERN-OHL-S-2.0 licensz alatt.
- **Európai digitális szuverenitás:** Teljesen nyílt, auditálható processzor-design, amely európai foundry-knál gyártható (IHP SG13G2, GlobalFoundries Dresden) nem-EU IP függőség nélkül.

**Közösségépítési terv:**
- GitHub repository CI/CD-vel (minden commit-nál minden teszt zöld)
- Angol nyelvű dokumentáció és contribution guide
- Blogposztok technikai mérföldkövekről
- Lightning talk FOSDEM / ORConf / Tiny Tapeout közösségi meetup-on
- Havi progress report a projekt weboldalán

---

## Melléklet terv

A pályázathoz csatolandó PDF:
1. Architektúra áttekintés (architecture.md kivonata)
2. ISA-CIL-T0 specifikáció összefoglaló
3. Roadmap vizualizáció (F0–F7 diagram)
4. Cognitive Fabric One chip vízió (benchmark összehasonlítás RISC-V-vel)
5. Jelenlegi státusz: 267 teszt, szimulátor, linker, runner screenshotok

---

## Belső megjegyzések (NEM a pályázat része — csak nekünk)

### Miért €35K és nem €50K?
- Az első pályázat max €50K, de a reálisabb, kisebb kérés **jobb elfogadási esélyű**
- A €35K fedezi az F2-F4 + F5 kezdetét — ez **mérhető, demonstrálható eredmény** 12 hónap alatt
- Ha sikeres, a második pályázat (€50K-€150K) fedezheti az F5-F6-ot és a silicon tape-out-ot

### Miért nem probléma, hogy F2-nél tartunk?
- Az NLnet **R&D-t finanszíroz, nem kész terméket** — „Research and development as their primary objective"
- A legtöbb NLnet pályázó **kevesebbet tud felmutatni**: nincs kódjuk, nincs tesztjük, csak ötletük van
- Mi **267 zöld tesztet, működő szimulátort, linkert, CLI runner-t** tudunk mutatni — ez **ritka** és **erős**
- Az F1.5 kész státusz demonstrálja, hogy **képesek vagyunk végrehajtani** — nem csak ígérni

### Értékelési kritériumok illeszkedése
| Kritérium (súly) | CLI-CPU erőssége |
|-------------------|-----------------|
| **Technical excellence (30%)** | 267 zöld teszt, TDD, 48 opkód, működő szimulátor+linker — nem ígéret, hanem kész munka |
| **Relevance/Impact (40%)** | Libre silicon, .NET ökoszisztéma (8M dev), EU szuverenitás, actor-natív biztonság |
| **Cost effectiveness (30%)** | €35K-ból first silicon + FPGA multi-core — összehasonlítva: egyetlen ChipIgnite tape-out $15K |

### Kockázatok és mitigáció
| Kockázat | Valószínűség | Mitigáció |
|----------|-------------|-----------|
| RTL nem fér el a TT tile-ban | Közepes | Korai szintézis becslés, iteratív optimalizáció |
| FPGA board szállítási késés | Alacsony | 3 board rendelés az elején |
| Rich core túl komplex 12 hónap alatt | Közepes | M4 csak „start" — a teljes Rich core a második pályázatban |
| Tiny Tapeout shuttle csúszás | Közepes | Több shuttle-re is beadható (TTSKY26a, TTSKY27a) |

### Következő lépések
1. **Személyes adatok kitöltése** (név, email, szervezet, ország)
2. **GitHub repo publikus URL** véglegesítése
3. **PDF melléklet** készítése (architektúra kivonat + roadmap diagram)
4. **Angol lektorálás** — a beadott verzió angolul megy!
5. **Beadás** — https://nlnet.nl/propose/ — **deadline: 2026. június 1., 12:00 CEST**

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
