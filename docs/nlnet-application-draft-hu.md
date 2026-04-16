# NLnet NGI Zero Commons Fund — Pályázati vázlat

> **Deadline:** 2026. június 1., 12:00 CEST
> **Form:** https://nlnet.nl/propose/
> **Kiírás:** NGI Zero Commons Fund (13. kör)
> **Státusz:** BEADVA (v1.1-es verzió ahogy benyújtva). A dokumentáció beadás után frissítve a CFPU elnevezéssel — lásd Changelog.
> **Megjegyzés:** A pályázat **angolul került beadásra** (NLnet követelmény). Ez a magyar változat tájékoztató jellegű — bemutatja, mit mondott az angol szöveg. A beadott angol verzió: `nlnet-application-draft-en.md`.

> English version: [nlnet-application-draft-en.md](nlnet-application-draft-en.md)

> Version: 1.2

---

## Pályázati kiírás

NGI Zero Commons Fund

## Pályázat neve

**CLI-CPU: Nyílt forráskódú Cognitive Fabric Processing Unit (CFPU) — natív CIL végrehajtás libre szilíciumon**

## Weboldal / Wiki

https://github.com/FenySoft/cli-cpu

---

## Kivonat

A projekt referencia implementációs fázisa (F1.5) **kész és tesztelve van**: a C# szimulátor lefedi mind a 48 CIL-T0 opkódot (**250+ zöld xUnit teszt**), a Roslyn-alapú CIL-T0 linker működik (C# forráskód → .dll → CIL-T0 bináris), és a CLI futtatóeszköz (`run` / `link` parancsok) kész. Minden TDD módszertannal fejlesztve, Devil's Advocate review-val. **Ez a pályázat a bizonyított szoftveres szimulációból a fizikai hardverbe való átmenetet finanszírozza.**

A CLI-CPU a **Cognitive Fabric Processing Unit (CFPU)** nyílt forráskódú referencia implementációja — egy új kategóriájú feldolgozó egység, amely a .NET Common Intermediate Language (CIL) bájtkódot **natívan, hardveresen hajtja végre**, JIT fordítás, AOT transzláció vagy interpreter nélkül. A *CPU / GPU / TPU / NPU* család mellé a **CFPU** az első **MIMD aktor-natív** feldolgozó egység: sok kis, független CIL-natív core egyetlen chipen, kizárólag **hardveres mailbox FIFO-kon** kommunikálva, shared-nothing modellben. Ahelyett, hogy egymagos sebességben versenyezne (ezt a picoJava és a Jazelle már megpróbálta és megbukott), a CFPU architektúra **teljesen kiküszöböli a cache koherencia overhead-et**, és a teljesítmény lineárisan skálázódik a core-számmal.

**A pályázat három konkrét eredményt céloz:**

1. **RTL implementáció (F2):** A meglévő, teljesen tesztelt C# referencia szimulátor átültetése szintetizálható Verilog/Amaranth HDL-re, cocotb golden-vector teszteléssel a szimulátor ellen.

2. **Első szilícium (F3):** Egyetlen Nano core + hardveres mailbox tape-out Tiny Tapeout Sky130 shuttle-ön — a projekt első fizikai chipje, Fibonacci(20) és „echo neuron" demóval UART-on.

3. **Multi-core FPGA verifikáció (F4):** 4 Nano core demonstráció MicroPhase A7-Lite XC7A200T FPGA board-on, hardveres mailbox-okkal, shared-nothing, event-driven működéssel — az első bizonyíték, hogy a Cognitive Fabric skálázódik.

**Miért releváns az NGI ökoszisztéma számára:**

- **Libre silicon end-to-end:** Sky130 PDK + OpenLane2 (ASIC) és OpenXC7/Yosys (FPGA) — teljesen reprodukálható, auditálható, nyílt toolchain.
- **8 millió .NET fejlesztő célozhatja meg ezt a hardvert ismerős eszközökkel:** Minden .NET nyelv (C#, F#, VB.NET) CIL-re fordul. A Nano core a CIL-T0 integer subset-et futtatja natívan; a Rich core (F5+) kiterjeszti a teljes CIL-re objektumokkal, GC-vel és FPU-val. Nincs JIT, nincs interpreter, nincs runtime réteg.
- **Actor-natív biztonság:** A per-core memória-izoláció a szilícium fizikai tulajdonsága (privát SRAM, nincs shared memory), nem szoftveres absztrakció. A shared-nothing architektúra tervezésénél fogva kiküszöböli a cross-core oldal-csatornás támadási felületet (nincs shared cache, nincs spekulatív végrehajtás, nincs branch predictor). Determinisztikus végrehajtás, ami lehetővé teszi az ISA formális verifikációját.
- **Európai szuverenitás:** Teljesen nyílt processzor-design, amelyet bármely európai entitás gyárthat, auditálhat és tanúsíthat — függetlenül US/ázsiai IP licenszeléstől (ellentétben az ARM, RISC-V kereskedelmi core-ok vagy x86 esetével).
- **Konkrét felhasználási eset:** Biztonságos IoT edge csomópont, amely Akka.NET aktor workload-okat futtat per-core hardveres izolációval — kiküszöbölve a hagyományos TEE/TrustZone komplexitást, erősebb garanciákkal.

- **A hardver-szintű biztonság növekvő relevanciája:** Ahogy a személyes adatszivárgások, infrastruktúra-támadások és AI-vezérelt fenyegetések eszkalálódnak, a kizárólag szoftveres biztonsági megoldások egyre kevésbé elegendőek. A CLI-CPU hardveresen kikényszerített memória-biztonsága, típus-biztonsága és vezérlési folyamat integritása semmilyen szoftveres exploit-tal nem kerülhető meg — ami egyre relevánsabbá teszi a jelenlegi és jövőbeli biztonsági kihívások szempontjából, legyen szó személyes eszközökről, kritikus infrastruktúráról vagy IoT-ről.

**Miért most?** A nyílt PDK-k (Sky130, IHP SG13G2), az érett aktor-modell keretrendszerek (Akka.NET, Orleans), a Dennard skálázás végének sok-magos architektúrák felé tolása, a szilícium demokratizálódása (Tiny Tapeout, eFabless), és a **hardver-szintű biztonság növekvő sürgőssége** az eszkalálódó kiberfenyegetésekkel szemben együttesen teszik életképessé és szükségessé a sok-magos bytecode-natív megközelítést 2026-ban — ott, ahol az egymagos picoJava 1997-ben megbukott.

---

## Volt-e korábbi tapasztalatod releváns projektekkel vagy szervezetekkel?

A pályázó 35+ év professzionális szoftver- és hardvertapasztalattal rendelkezik:

- **Hardver alapok (1980-as évek):** Z80 számítógép tervezés és assembly programozás (hobbi/főiskolai szinten), később 8086/80286 assembly + Pascal projektek, majd C/C++ Windows-on. Ez a korai hardveres tapasztalat közvetlenül befolyásolja a CLI-CPU mikroarchitektúra tervezését.
- **Országos szintű éles rendszerek (1990-es évek–2026):** 3 fős csapatban fejlesztett „Atlasz" — vasúti menetirányító rendszer a MÁV számára, amelyet az **országos forgalomirányításban 2026-ig használtak**. Szintén fejlesztette a Visual Restaurant, Visual Hotel & Restaurant szoftvert (Delphi, később .NET) — vendéglátóipari szoftvercsomag, amelyet a Com-Passz Kft. forgalmaz, széles körben használt a magyar étterem- és szállodaiparban — beleértve egy .NET-ben fejlesztett mobil pincér terminált (beágyazott .NET + hardver integráció).
- **.NET ökoszisztéma (20+ év):** Professzionális C#/.NET fejlesztés, beleértve kötelező hatósági adatszolgáltatási integrációkat (NAV adóhatóság, NTAK turizmus), piaci API integrációkat (Wolt, Fooddora, falatozz.hu, D-EDGE, iBar), Akka.NET aktor rendszereket, Avalonia UI cross-platform alkalmazásokat, és Android/iOS telepítést.
- **Magyar Adóügyi Ellenőrző Egység:** Hardverfejlesztési tapasztalat az eredeti Adóügyi Ellenőrző Egység ([48/2013 NGM](https://njt.hu/jogszabaly/2013-48-20-2X)) projektből — **a szoftvert egyedül fejlesztettem**. A jelenlegi **QCassa/JokerQ** ennek korszerűbb, PQC-biztosított utódja (55+ Akka.NET aktor), szintén **egyedül fejlesztett** .NET szoftver + hardver illesztési projekt a [8/2025 NGM rendelet](https://njt.hu/jogszabaly/2025-8-20-2X) szerint. Ez a projekt mélyreható, gyakorlati tapasztalatot ad az aktor-modell architektúrában és a .NET hardver-integrációban, ami közvetlenül befolyásolja a CLI-CPU tervezési döntéseit.
- **CLI-CPU RTL:** Előzetes Verilog RTL fejlesztés már folyamatban — ALU modul teljes cocotb testbench-csel (41/41 zöld teszt). Nyílt forráskódú EDA eszközök (Yosys, Verilator, cocotb) és a Sky130/IHP nyílt szilícium ökoszisztéma ismerete.

A CLI-CPU projekt önmagában 7 architektúra dokumentumot (~4000+ sor), egy teljesen tesztelt referencia szimulátort, egy CIL-T0 linkert és egy CLI futtatóeszközt hozott létre — mindezt szigorú TDD módszertannal.

A projekt 2026 április eleje óta fókuszált fejlesztés alatt áll, szilárd technikai alapot építve a nyilvános bejelentés előtt. Az NLnet támogatás az első teljesen nyilvános fázist finanszírozná, beleértve a közösségi outreach-et és konferencia előadásokat.

---

## Kért összeg

**€35,000**

## Mire megy a kért összeg

| Mérföldkő | Leírás | Összeg | Időkeret |
|-----------|--------|--------|----------|
| **M1: RTL (F2)** | Verilog/Amaranth HDL implementáció: egyetlen Nano core. Verilator + cocotb testbench, ami megfelel az összes C# szimulátor tesztnek (250+). Yosys szintézis Sky130-ra. | €8,000 | 1-6. hónap |
| **M2: Tiny Tapeout (F3)** | 16 tile-os Tiny Tapeout submission: Nano core + mailbox + UART. Bring-up PCB tervezés (KiCad). Post-silicon verifikáció. | €7,000 | 5-10. hónap |
| **M3: FPGA multi-core (F4)** | 3× MicroPhase A7-Lite XC7A200T board (~€960). 4-core Cognitive Fabric FPGA-n: shared-nothing, mailbox mesh, sleep/wake, event-driven. Ping-pong és echo-chain demók. | €8,000 | 8-14. hónap |
| **M4: Rich core RTL (F5 kezdet)** | Rich core (teljes CIL) RTL tervezés kezdete: objektum modell, GC assist, kivételkezelés, FPU. Heterogén Nano+Rich FPGA demó. | €7,000 | 12-18. hónap |
| **M5: Dokumentáció és közösség** | Angol nyelvű architektúra dokumentáció, contribution guide, CI/CD pipeline, közösségi outreach (blogposztok, konferencia lightning talk). | €5,000 | Folyamatos |
| **Összesen** | | **€35,000** | 18 hónap |

**Hardver költségek a mérföldkövekben:**
- 3× A7-Lite XC7A200T FPGA board: ~€960
- 1× Tiny Tapeout 16 tile-os submission: ~€1,200
- Bring-up PCB + alkatrészek: ~€80
- Szállítás, kábelek, adapterek: ~€200
- **Hardver összesen: ~€2,440**

Személyi költség: ~18 hónap részmunkaidő (~900 óra), €32,560 / 900ó ≈ €36/óra. Hardver: €2,440.

---

## Meglévő finanszírozási források

A projekt jelenleg a pályázó saját finanszírozásából működik. Nem érkezett külső finanszírozás. Nincs más függőben lévő pályázat ugyanerre a munkára.

Tervezett kiegészítő finanszírozás (nem átfedő ezzel a pályázattal):
- **IHP SG13G2 ingyenes MPW:** A 2026 októberi shuttle-re tervezett pályázat (F6 heterogén szilícium — túlmutat ezen pályázat hatáskörén).
- **Közösségi finanszírozás:** GitHub Sponsors / Open Collective a projekt során kerül felállításra (folyamatos karbantartásra, nem ezen pályázat által fedezve).

**Fenntarthatósági terv:** (1) Következő NLnet pályázat az F5-F6-ra (Rich core + silicon tape-out). (2) IHP SG13G2 ingyenes MPW pályázat kutatási szilíciumra. (3) Hosszú távon: dual licensing modell (CERN-OHL-S a nyílt verzióra, kereskedelmi licensz a tanúsított termékekre). (4) GitHub Sponsors / Open Collective a folyamatos közösségi karbantartásra.

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

2. **Tiny Tapeout terület-budget:** A Nano core (~9,100 std cell) + mailbox + UART-nak el kell férnie 12-16 tile-ban (~12K-16K kapu). Kihívás: a routing overhead a Sky130-on a tile terület 30-40%-át is felemésztheti. Mitigáció: iteratív szintézis terület-optimalizációval, Yosys becslésekkel kezdve a submission előtt. B terv: Ha a design a routing után nem fér el 16 tile-ban, a Nano core + UART-ra redukáljuk (mailbox nélkül), a mailbox verifikációját FPGA-n (M3) végezzük.

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
- Visual Studio Code / Code - OSS (MIT licensz) — elsődleges fejlesztői környezet, bővíthető C#, Verilog és cocotb eszközökkel

**Downstream felhasználók és stakeholderek:**
- **.NET fejlesztői közösség (~8M fejlesztő):** Bármely CIL-re fordított C#/F# kód potenciálisan futhat a CLI-CPU hardveren. Az Akka.NET és Orleans aktor framework közösségek természetes korai adoptálók.
- **Neuromorphic kutatói közösség:** A CLI-CPU programozható core-jai rugalmas SNN szimulációs platformot kínálnak, ellentétben a rögzített modellű chipekkel (Loihi, TrueNorth).
- **IoT / beágyazott biztonság:** A shared-nothing architektúra hardver-szintű izolációt biztosít MMU/TrustZone komplexitás nélkül.
- **Nyílt hardver közösség:** A projekt egy újszerű CIL-natív core designt ad a libre silicon ökoszisztémához, CERN-OHL-S-2.0 licensz alatt.
- **Európai digitális szuverenitás:** Teljesen nyílt, auditálható processzor-design, amely európai foundry-knál gyártható (IHP SG13G2, GlobalFoundries Dresden) nem-EU IP függőség nélkül.

**Megjegyzés a .NET függetlenségről:** A CIL specifikáció (ECMA-335) egy ISO/IEC által ratifikált nemzetközi szabvány, nem Microsoft tulajdon. A CLI-CPU a bájtkód formátumot célozza, nem a Microsoft runtime-ot. Alternatív CIL fordítók léteznek (Mono, különböző Roslyn-független front-end-ek). A hardver design az ISA szintjén működik, és független bármely upstream runtime változástól.

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
5. Jelenlegi státusz: 250+ teszt, szimulátor, linker, runner screenshotok

---

## Belső megjegyzések (NEM a pályázat része — csak nekünk)

### Miért €35K és nem €50K?
- Az első pályázat max €50K, de a reálisabb, kisebb kérés **jobb elfogadási esélyű**
- A €35K fedezi az F2-F4 + F5 kezdetét — ez **mérhető, demonstrálható eredmény** 18 hónap alatt
- Ha sikeres, a második pályázat (€50K-€150K) fedezheti az F5-F6-ot és a silicon tape-out-ot

### Miért nem probléma, hogy F2-nél tartunk?
- Az NLnet **R&D-t finanszíroz, nem kész terméket** — „Research and development as their primary objective"
- A legtöbb NLnet pályázó **kevesebbet tud felmutatni**: nincs kódjuk, nincs tesztjük, csak ötletük van
- Mi **250+ zöld tesztet, működő szimulátort, linkert, CLI runner-t** tudunk mutatni — ez **ritka** és **erős**
- Az F1.5 kész státusz demonstrálja, hogy **képesek vagyunk végrehajtani** — nem csak ígérni

### Értékelési kritériumok illeszkedése
| Kritérium (súly) | CLI-CPU erőssége |
|-------------------|-----------------|
| **Technical excellence (30%)** | 250+ zöld teszt, TDD, 48 opkód, működő szimulátor+linker — nem ígéret, hanem kész munka |
| **Relevance/Impact (40%)** | Libre silicon, .NET ökoszisztéma (8M dev), EU szuverenitás, actor-natív biztonság |
| **Cost effectiveness (30%)** | €35K-ból first silicon + FPGA multi-core — összehasonlítva: egyetlen ChipIgnite tape-out $15K |

### Kockázatok és mitigáció
| Kockázat | Valószínűség | Mitigáció |
|----------|-------------|-----------|
| RTL nem fér el a TT tile-ban | Közepes | Korai szintézis becslés, iteratív optimalizáció |
| FPGA board szállítási késés | Alacsony | 3 board rendelés az elején |
| Rich core túl komplex 18 hónap alatt | Közepes | M4 csak „start" — a teljes Rich core a második pályázatban |
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
| 1.2 | 2026-04-16 | **Csak dokumentáció frissítés a beadás után** — a „Cognitive Fabric Processing Unit (CFPU)" elnevezés bevezetése a címben és absztraktban. A beadott pályázat (v1.1) még nem használta a CFPU rövidítést. A technikai tartalom, a költségvetés és a mérföldkövek változatlanok. |
| 1.1 | 2026-04-14 | **BEADOTT verzió.** 18 hónapos timeline, €35K mind az 5 mérföldkővel, óradíj bontás, teszt szám 250+, RTL tapasztalat, sustainability plan, Why now, ECMA-335 függetlenség, konkrét use case, Plan B TT-hoz |
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
