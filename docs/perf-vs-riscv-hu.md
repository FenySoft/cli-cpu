# CFPU vs RISC-V — Single-thread teljesítmény-elemzés

> English version: [perf-vs-riscv-en.md](perf-vs-riscv-en.md)

> Version: 1.0

> **⚠️ Vízió-szintű dokumentum.** A számszerű becslések irodalmi precedensek (picoJava-2 perf paper, Jazelle DBX measurement, Krall & Probst 1998, Azul Vega) extrapolációi. **Nem RTL-szintű mérés, nem szilikon-mérés.** A pontos arányok csak F1.5 dynamic instruction count baseline + F2.7 FPGA cycle-accurate prototípus + F4 multi-core RTL + F6 szilícium után validálhatók. A dokumentum célja a **methodológia rögzítése** és a felmért becslések reprodukálható alapra hozása, nem a végleges számok deklarálása.

## A kérdés

Egy adott C# program (Roslyn → IL → CFPU CIL-T0 link → CFPU futás) **single-thread wall-clock ideje** miként viszonyul ugyanazon program (Roslyn → IL → NativeAOT/Mono LLVM → RV32IM futás) idejéhez ugyanazon technológiai csomóponton, ugyanazon órajelen?

Ez a kérdés **nem a CFPU fő érve** — a fő érv a sok-magos throughput (`microarch-philosophy-hu.md`). De a **per-mag perf is releváns**, mert legacy C# kód többsége nem egyszerre több ezer aktorra bontva fut. A „Rich core elég gyors-e egy értelmes baseline-hoz" kérdés tartható válaszra szorul.

## Ami ellen összehasonlítunk — referencia mindig in-order RV

A [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) szerint a CFPU minden core-ja in-order. A fair összehasonlítás tehát **csak in-order RV ellen** lehet — soha nem RV-OoO Cortex-A75 vagy Apple M-osztály ellen, mert azok a CFPU mikroarch-tervezésén kívüli kategóriát képviselnek.

| RV referencia | CFPU referencia | Indok |
|---|---|---|
| SiFive E31 (RV32IMC, in-order, 1-issue, 5-stage) | F4 Rich (in-order, 1-issue, reg stack, macro-op fusion) | Alap baseline |
| SiFive U74 (RV32IMC, in-order, **2-issue**, 8-stage) | F5 Rich (in-order, **2-issue**, reg stack, fusion, statikus pair-bit) | Optimalizált |
| Spike emulátor (RV32IMC, statikus IPC=1) | F1.5 referencia szimulátor (statikus IPC=1) | Dynamic instruction count baseline |

**Tilos referencia:** ARM Cortex-A55/A75, Apple M-series P-core, Intel Lakefield E-core, AMD Zen — ezek mind OoO/spekulatív, nem releváns a CFPU-ra.

## A korábbi extrapoláció visszavonása

A korábbi (a microarchitektúra-filozófia rögzítése előtti) munka-becsléseink feltételezték az OoO opciót, és ezt használták a teljesítmény-modellben. Ez két szempontból is hibás volt:

1. **Architekturális**: az OoO nem opció a CFPU-n (lásd [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md))
2. **Methodológiai**: a számok extrapoláció voltak, nem mérés — ez a doc maga adja meg a reprodukálható mérési alapot

A korábbi „F5 Rich + OoO 2-issue ≈ RV-OoO 2-issue" érvelés **törlődik**. A reális becslés:

| Konfiguráció | RV referencia | Becsült lassulás | Indok |
|---|---|---|---|
| F1.5 referencia szim (3-stage, nincs cache) | RV32I in-order, nincs cache | ~3–5× | mindkettő naív, **nem érdemi mérés** |
| F4 Rich (5-stage in-order, 1-issue, reg stack, macro-op fusion) | RV32IM 5-stage in-order 1-issue (SiFive E31 osztály) | **~1,3–1,5×** | stack ISA + statikus mintázat-felismerés |
| F5 Rich (5-stage in-order, 2-issue statikus pair-bit, reg stack, fusion, statikus branch hint) | RV32IMC 5-stage in-order 2-issue (SiFive U74 osztály) | **~1,1–1,3×** | EPIC-stílus statikus ILP |

A „matchel az RV-OoO 2-issue-t" érv **törölve**. Reális mérce: in-order RV ellen in-order CFPU, és ott **~1,2× a hot path-on** elérhető — ez a megcélzott középérték F5 után.

## Methodológia — hogyan mérjünk reálisan

A „X×-szer lassabb" állítások **csak az alábbi módszerek egyikével** alátámaszthatók:

### Módszer 1: Dynamic instruction count arány (F1.5-ben elérhető)

```
RV_dyn_count(P) / CFPU_dyn_count(P) = utasítás-szám arány
```

A CFPU oldalán: `CilCpu.Sim.TCpu.Execute()` egy számlálóval bővítve, minden végrehajtott opkód +1.
A RV oldalán: Spike emulátor `--instructions=count` flaggel.

Ez **nem teljesítmény-arány**, csak utasítás-szám-arány. CPI-modell hozzáadásával válik perf-aránnyá:

```
Perf_arány = (CFPU_dyn / RV_dyn) × (CFPU_CPI / RV_CPI)
```

CPI a F1.5 fázisban analitikusan modellezhető (5-stage in-order pipeline, statikus hazard-lista).

### Módszer 2: Cycle-accurate FPGA prototípus (F2.7-ben elérhető)

Az A7-Lite 200T-n a Rich core RTL-prototípusa cycle-pontosan futtatja a benchmark kódot. Az RV referencia ugyanazon FPGA-n VexRiscv vagy SERV core-ral.

Eredmény: **valódi mért wall-clock**, ugyanazon clock-on, ugyanazon FPGA-n.

### Módszer 3: Szilícium mérés (F6-ban elérhető)

A Cognitive Fabric One MPW (15 mm², 6R+16N+1S) a végső igazság. Egy referencia RV chip ugyanazon node-on (pl. SiFive U74 PMP).

## Reprodukálható baseline — mit csináljunk most (F1.5)

Ezt **a következő lépésként javasoljuk implementálni** a `CilCpu.Sim` projektben:

1. **Instruction counter** a `TCpu`-ban
   - Minden `TExecutor` `Step()` hívásnál +1
   - Per-opcode bontás (48 opkód külön számlálóval)
   - Method header read, branch taken/not-taken bontás
   - TDD: új `TCpuInstructionCountTests`, baseline-érték minden `samples/PureMath` benchmark-ra

2. **Spike RV referencia futás**
   - `samples/PureMath` projektet NativeAOT-ral RV32IMC-re fordítani (`-r linux-riscv32`, ha van; vagy LLVM cross-compile)
   - Spike-on futtatni `--isa=RV32IMC --log-commits`
   - Utasítás-szám kinyerése

3. **Aránytáblázat dokumentálva**
   - `docs/perf-baseline/{benchmark}.md` minden esetre
   - Reprodukálható script-tel (`scripts/perf-baseline.sh`)
   - Verzionált — minden roadmap-fázisnál újra kell futtatni

4. **CPI-modell beépítése**
   - Egy egyszerű analitikus modell: 5-stage in-order, hazard-stall regulák
   - F2.7-ig csak modell, F2.7-után RTL helyettesíti

## Mit nyerünk a baseline-ből

- **Konkrét, hivatkozható szám** minden roadmap-frissítésnél
- **NLnet és blog-poszt számok** valós mérésen alapulva
- **Regression detektálás** — ha új opkód-implementáció rontja a count-ot, kiderül
- **Linker-optimalizáció eredménye mérhető** — a macro-op fusion előtt-után ugyanazon benchmarkon

## Mit nem nyerünk

A dynamic instruction count **nem mond meg mindent**:

- Cache miss arány, branch misprediction rate — ezek RTL-szintűek
- Memóriabandwidth-igény — ezek is RTL/szilikon-mérések
- Power per benchmark — szilikon-mérés
- Skálázódás multi-core-on — F4-ben mérendő

A baseline **tehát egyetlen pont** a teljes kép validálási láncában, nem helyettesíti a többi fázist.

## Kontextusban — a per-mag lassulás miért nem fő probléma

Ahogy a `microarch-philosophy-hu.md` rögzíti: a CFPU érve nem a single-thread sebesség. A 4 300-szál iMac-példa szerint a hagyományos CPU-n a per-mag teljesítményt eleve elnyeli a context switch overhead. Egy 1,2×-os single-thread lassulás CFPU magon **eltörpül** a 7–15× aggregate throughput nyereséghez képest sok-task workloadon.

Ezt a perspektívát **minden összehasonlító kommunikációban explicit fenntartani** — nem azért fontos a per-mag mérés, hogy versenyezzünk az RV-vel, hanem azért, hogy a Rich core ne legyen szégyenletesen lassú a baseline-on és a legacy C# kódon.

## Kapcsolódó dokumentumok

- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — TLP > ILP, miért nem a single-thread perf a fő érv
- [`internal-bus-hu.md`](internal-bus-hu.md) — port-bottleneck a CPI-modell része
- [`core-types-hu.md`](core-types-hu.md) — Rich core spec
- [`ISA-CIL-T0-hu.md`](ISA-CIL-T0-hu.md) — utasítás-készlet, ami a count alapja
- [`roadmap-hu.md`](roadmap-hu.md) — F2.7 / F4 / F6 fázisok, ahol a validálás megtörténik

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-25 | Kezdeti verzió — methodológia (dynamic instruction count, FPGA, szilikon), in-order vs in-order összehasonlítás, OoO-feltételezés visszavonva, F1.5 baseline-mérés terv |
