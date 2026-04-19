# CFPU Core Család

> English version: [core-types-en.md](core-types-en.md)

> Version: 1.6

Ez a dokumentum a Cognitive Fabric Processing Unit (CFPU) **öt core típusát** specifikálja: az ISA különbségeket, a terület-hatást, az SRAM méretezést, a power domain-eket, a termékcsalád variánsokat és a piaci pozíciót.

## Kettős specializáció

A CFPU core család **nem lineáris hierarchia** — két különböző irányba specializálódik a Nano alapból:

```
                Nano (CIL-T0)
               /             \
      Actor (+GC+Obj)    Matrix (+FPU+MAC+SFU)
         |
      Rich (+FPU)
```

**Balra:** az általános célú programozás irány — objektumok, GC, kivételkezelés, majd FPU.
**Jobbra:** a numerikus számítás irány — FPU, mátrix szorzás, transzcendens függvények, GC és objektumok **nélkül**.

Ez a kettős specializáció a CFPU egyedi vonása: egyetlen más processzor-család sem kínálja mindkét irányt azonos interconnecten, azonos üzenetformátummal, azonos RTL-ből paraméterezve.

## Az öt core típus

### Nano Core

| Tulajdonság | Érték |
|------------|-------|
| **ISA** | CIL-T0 — 48 opkód, int32-only |
| **FPU** | Nincs |
| **MAC+SFU** | Nincs |
| **GC + Objektum modell** | Nincs |
| **Kivételkezelés** | Trap only (TTrapException) |
| **Logika terület (7nm)** | ~0.009 mm² |
| **SRAM tartomány** | 4–64 KB |
| **Cél** | Spike, szenzor, egyszerű aktor, maximális core szám |

A Nano Core a legkisebb végrehajtó egység — az F1 szimulátorban implementált 48 CIL-T0 opkódot futtatja. Nincs benne semmi, ami nem szükséges egy egyszerű integer aktor működéséhez. A minimális méret maximális core számot jelent: 800 mm²-en 7nm-en akár **~32 000 Nano Core** fér el 4 KB SRAM-mal (Compact routerrel és L1–L3 infrastruktúra overhead-del együtt).

**Mikor válaszd a Nano-t:**
- Spiking Neural Network spike-ok (1-bit események, egyszerű LIF neuron)
- IoT szenzor aktorok (hőmérséklet, nyomás, rezgés → int érték → üzenet)
- Nagyszámú egyszerű worker (sort, filter, count) actor pipeline-ban

### Actor Core

| Tulajdonság | Érték |
|------------|-------|
| **ISA** | Teljes CIL — objektumok, tömbök, stringek, virtuális hívás, kivételkezelés, generikusok |
| **FPU** | Nincs |
| **MAC+SFU** | Nincs |
| **GC + Objektum modell** | **Van** — per-core GC assist, bump allocator, mark-sweep |
| **Kivételkezelés** | Teljes (throw, catch, finally) |
| **Logika terület (7nm)** | ~0.018 mm² |
| **SRAM tartomány** | 64–256 KB |
| **Cél** | Általános aktor, stream processing, supervisor, edge computing |

Az Actor Core a „standard" CFPU mag — teljes CIL támogatás, objektum modellel, GC-vel, kivételekkel, de **FPU nélkül**. A legtöbb aktor-alapú workload nem igényel lebegőpontos számítást: üzenetkezelés, állapotgépek, routing, scheduling, szövegfeldolgozás, protokoll implementáció mind integer-alapú.

**Mikor válaszd az Actor-t:**
- Akka.NET-szerű actor cluster (supervisor hierarchia, message passing)
- Stream processing pipeline (map, filter, reduce)
- Supervisor és scheduler aktorok (ML/SNN rendszerben is — a menedzser nem számol, csak koordinál)
- Edge computing gateway (protokoll kezelés, routing, aggregálás)
- Bármely feladat, ahol teljes CIL kell, de FP nem

### Rich Core

| Tulajdonság | Érték |
|------------|-------|
| **ISA** | Teljes CIL + FPU opkódok |
| **FPU** | **Van** — IEEE-754 R4 (float) + R8 (double), power-gated |
| **MAC+SFU** | Nincs |
| **GC + Objektum modell** | **Van** |
| **Kivételkezelés** | Teljes |
| **Logika terület (7nm)** | ~0.022 mm² |
| **SRAM tartomány** | 128–512 KB |
| **Cél** | FP-igényes aktorok, tudományos számítás, teljes .NET kompatibilitás |

A Rich Core az Actor Core + **IEEE-754 FPU**. A legtöbb .NET alkalmazás, amely `float` vagy `double` típusokat használ, Rich Core-t igényel. A FPU **power-gated** — ha a kód nem használ FP műveleteket, a FPU alszik és a Rich Core az Actor Core fogyasztásával egyenértékű.

**Mikor válaszd a Rich-et:**
- Tudományos számítás (fizikai szimuláció, statisztika, pénzügyi modell)
- Általános .NET alkalmazás, ahol `float`/`double` típusok előfordulnak
- ML/SNN koordinátor (súly-aggregálás, normalizáció, learning rate — FP-ben, de nem mátrix szorzás)
- Bármely feladat, ahol teljes CIL + FP kell, de a MAC array túlzás

### Matrix Core

| Tulajdonság | Érték |
|------------|-------|
| **ISA** | CIL-T0 + FP opkódok (nem teljes CIL!) |
| **FPU** | **Van** — IEEE-754 R4 + R8, power-gated |
| **MAC+SFU** | **Van** — 4×4 MAC array (16 multiply-accumulate / ciklus) + SFU (sin/cos/exp/rsqrt), power-gated |
| **GC + Objektum modell** | **Nincs** — nincs GC, nincs objektum, nincs kivételkezelés |
| **Kivételkezelés** | Trap only |
| **Logika terület (7nm)** | ~0.019 mm² |
| **SRAM tartomány** | 4–64 KB (sweet spot: **8 KB**) |
| **Cél** | ML inference, SNN neuron modell, DSP, mátrix számítás |

A Matrix Core a Nano Core **numerikus specializációja** — CIL-T0 ISA kiegészítve FP opkódokkal és hardveres MAC+SFU-val. **Nincs benne GC, objektum modell, kivételkezelés, virtuális dispatch, string, generikusok** — ezek nem szükségesek a numerikus feldolgozáshoz, és elhagyásukkal a core ~40%-kal kisebb, mint a Rich Core.

A Matrix Core a hálózatból **streaming módban** kapja az adatot: a MAC array 4×4-es tile-okban dolgozza fel a mátrixokat, a hálózat táplálja, az eredmény azonnal tovább megy. Ezért **kis SRAM elég** — nem kell a teljes mátrixot lokálisan tartani.

**Az optimális SRAM méret 8 KB:**

| SRAM | Core+SRAM | Node összesen | Core szám (800 mm²) | TOPS (INT8, 500 MHz) | SRAM aránya |
|------|-----------|---------------|---------------------|---------------------|------------|
| 4 KB | 0,024 mm² | 0,038 mm² | ~21 100 | 338 | 4% — szoros, kód alig fér el |
| **8 KB** | **0,025 mm²** | **0,039 mm²** | **~20 500** | **328** | **7% — kód + 2 KB lokális cache** |
| 16 KB | 0,027 mm² | 0,041 mm² | ~19 500 | 312 | 13% |
| 64 KB | 0,037 mm² | 0,051 mm² | ~15 700 | 251 | 38% |

> Node összesen = Core+SRAM + Turbo router (0,007 mm²) + L1–L3 infrastruktúra (0,007 mm²).

A 8 KB-nál a kód + stack + MAC buffer kényelmesen elfér, marad ~2 KB lokális cache a streaming adatnak, és a core szám közel maximális.

**Mikor válaszd a Matrix-ot:**
- ML inference (konvolúció, dense layer, batch normalization)
- SNN neuron modellek (Izhikevich, Hodgkin-Huxley, LIF — FP-ben, MAC-kal)
- DSP pipeline (FIR/IIR filter, FFT butterfly)
- Bármely feladat, ahol a számítás mátrix szorzás + transzcendens függvények, és a teljes CIL nem szükséges

#### Matrix Core: Sustained vs. Peak Throughput

> **Fogalmak:** A *peak throughput* (csúcsteljesítmény) az elméleti maximum — MAC kapacitás × core szám × órajel, feltételezve hogy minden MAC egység minden ciklusban dolgozik. Mint az autó sebességmérőjén a 250 km/h: a motor képes lenne rá, de az út, a forgalom és az üzemanyag-ellátás nem engedi tartósan. A *sustained throughput* (tartós teljesítmény) a reálisan, folyamatosan fenntartható érték, amelyet az adatbetáplálás sebessége korlátoz — a valós 130 km/h, amit tényleg mész.

A 4×4 MAC array ciklusonként 16 multiply-accumulate műveletet produkál, de a **hálózat nem tudja teljes sebességgel táplálni**. Egy L0 link ~5,2 byte/ciklust szállít (42 bites wormhole, 500 MHz), míg a MAC 32 byte/ciklus bemenetet fogyaszt (16 × 2 byte INT8). Ez azt jelenti, hogy a MAC **~6×-osan túlméretezett** egyetlen linkhez képest — a peak TOPS soha nem tartható fenn egyidejűleg minden core-on.

Három architekturális stratégia enyhíti ezt a szűk keresztmetszetet:

**1. Weight Reuse nagyobb SRAM-mal**

Konvolúciós és dense rétegekben a súlymátrix újra és újra felhasználódik különböző input tile-okra. Ha a súlyok elférnek a lokális SRAM-ban, csak az input stream-et kell a hálózaton küldeni — a hálózati igény közel felére csökken.

| SRAM | Node összesen | Core szám | Peak TOPS | Becs. MAC kihasználtság | **Sustained TOPS** |
|------|---------------|-----------|-----------|------------------------|---------------------|
| 8 KB | 0,039 mm² | ~20 500 | 328 | ~15% | ~49 |
| 32 KB | 0,045 mm² | ~17 800 | 285 | ~40–50% | ~114–143 |
| 64 KB | 0,051 mm² | ~15 700 | 251 | ~60–70% | ~151–176 |

A nagyobb SRAM csökkenti a core számot, de **növeli a sustained TOPS-t**, mert több adat lokális. A 32 KB-os sweet spot ~2,5×-ös sustained throughput javulást hozhat a 8 KB-os variánshoz képest, kevesebb core ellenére.

**Systolic router variánssal (ML/SNN chip):**

A Systolic router 128-bites linkjei eliminálják a hálózati szűk keresztmetszetet: W→E 16 byte/cc aktiváció + N→S 16 byte/cc súly = 32 byte/cc, ami a MAC 32 byte/cc fogyasztásával egyezik. A MAC kihasználtság ~85–95%-ra nő, SRAM mérettől szinte függetlenül:

| SRAM | Node összesen | Core szám | Peak TOPS | MAC kihasználtság (ws) | **Sustained TOPS** |
|------|---------------|-----------|-----------|------------------------|---------------------|
| 8 KB | 0,033 mm² | ~24 200 | 387 | ~85–95% | **~329–368** |
| 32 KB | 0,039 mm² | ~20 500 | 328 | ~90–95% | **~295–312** |
| 64 KB | 0,045 mm² | ~17 800 | 285 | ~90–95% | **~257–271** |

> A Systolic variáns megfordítja az SRAM sweet spot-ot: a 8 KB-os konfiguráció adja a **legjobb sustained TOPS-t** (329–368), mert a link sávszélesség önmagában elegendő a MAC táplálásához — a nagyobb SRAM weight caching előnye nem kompenzálja az elvesztett core-okat.

**2. Post-MAC feldolgozás (ReLU, Quantize, Pool)**

Ha a MAC kimenete lokálisan feldolgozódik a hálózatra küldés előtt, a kimeneti forgalom drasztikusan csökken:

| Lépés | Kimeneti méret (4×4 tile-onként) | Csökkenés |
|-------|----------------------------------|-----------|
| Nyers MAC kimenet | 64 byte (16 × INT32) | — |
| + ReLU aktiváció | 64 byte (nullák tömöríthetőek) | sparse |
| + Kvantálás INT8-ra | 16 byte | **4×** |
| + 2×2 Max-Pool | 4 byte | **16×** |

A ReLU hardverben egyetlen komparátor — gyakorlatilag nulla terület-költség. A kvantálás és pooling minimális extra logikát igényel. A kimeneti forgalom csökkentésével a **kétirányú link sávszélessége felszabadul több bemeneti adatnak**, javítva a MAC kihasználtságot.

**3. Systolic láncolás (szoftver-definiált, nulla hardver költség)**

A mesh topológia természetesen támogatja a **core-to-core pipeline láncokat**:

```
Core₁ → Core₂ → Core₃ → Core₄
  W₁       W₂       W₃       W₄     (súlyok stacionáriusan minden core SRAM-jában)
  ↓        ↓        ↓        ↓
  A×W₁  → A×W₂  → A×W₃  → A×W₄    (A bemenet végigfolyik a láncon)
```

Minden core a saját súly-szeletét tartja SRAM-ban. A bemeneti adat szomszédról szomszédra halad — **1 hop, ~5,2 byte/ciklus, nincs hálózati torlódás**. Ez teljesen eliminálja a hálózati szűk keresztmetszetet a pipeline-olt workload-oknál.

Ehhez **nem szükséges hardver módosítás** — csak scheduler szoftver, ami a core-okat láncba szervezi, és CIL kód, ami a „fogadj szomszédtól → MAC → küldj szomszédnak" mintát követi. A CFPU üzenetküldő architektúrája és mesh topológiája természetesen támogatja ezt.

**Systolic router variáns:** A Systolic router (lásd [Interconnect — L0 Router variánsok](interconnect-hu.md)) 128-bites egyirányú linkeket használ a 42-bites mesh helyett. Ez a MAC array-t teljes sebességgel táplálja: 128 bit/cc = 16 byte/cc, ami a weight-stationary mintában a MAC 16 byte/cc fogyasztásával egyezik. A router mindössze ~5 000 GE (0,001 mm²) — 86%-kal kisebb a Turbo-nál —, mert nincs szükség XY routing-ra, VOQ-ra és iSLIP-re. A Systolic variánssal az 8 KB-os Matrix Core node 0,033 mm²-re csökken (vs 0,039 mm² Turbo-val), lehetővé téve **~24 200 core-t** (+18%).

**Kombinált hatás**

A három stratégia komplementer:

| Stratégia | Hardver költség | Hatás |
|-----------|----------------|-------|
| SRAM 8→32 KB | +0,006 mm²/core | Weight reuse, ~2,5× sustained TOPS |
| Post-MAC pipeline | ~0 (ReLU) – minimális (pool) | Kimeneti forgalom 4–16× csökkenés |
| Systolic láncolás | **Nincs** (csak szoftver) | Bemeneti szűk keresztmetszet eliminálása |

> A sustained TOPS becslések aritmetikai projekciók a hálózati sávszélesség-korlátok alapján. Validált értékekhez RTL-szintű szimuláció szükséges reprezentatív workload-okkal.

### Seal Core

| Tulajdonság | Érték |
|------------|-------|
| **ISA** | CIL-Seal (CIL-T0 subset + crypto kiterjesztések: SHA-256, WOTS+, Merkle path, eFuse kezelés) — *opkód lista: F5 specifikáció* |
| **FPU** | Crypto HW (AES, ECC — nem IEEE-754 FPU) |
| **MAC+SFU** | Nincs |
| **GC + Objektum modell** | Nincs |
| **Logika terület (7nm)** | ~0.2 mm² (beleértve eFuse, TRNG) |
| **SRAM** | ~32 KB (kulcs-tárolás, hash buffer) |
| **Elhelyezés** | **Mindig a chip geometriai közepén**, az L3 crossbar-ral egyben |
| **Darabszám** | **Alapesetben 1; nagyobb chipeken (F6+) 2–64 redundáns példány** párhuzamos verifikációval — lásd [Seal Core](sealcore-hu.md) |
| **Power** | Power-gated, wake-on-demand (kód betöltéskor ébred) |

A Seal Core nem számítási egység — a chip **hitelesítő kapuőre**. Minden kód (boot, hot code loading, aktor migráció) a Seal Core-on megy át AuthCode verifikációra. Az L3 crossbar-ral egyben a chip közepén helyezkedik el: a csillag topológia középpontja, minden cross-régió forgalom természetesen áthalad rajta.

**A Seal Core ~30 000 core-ig skálázódik** szaturáció nélkül:
- Boot (8 192 core): ~256 ms
- Runtime hot code loading: <0.1% kihasználtság
- L3 crossbar: ~25% terhelés 8k core-nál

## Terület összehasonlítás

### Core méretek (7nm)

| Core típus | Logika | Optimális SRAM | **Core összesen** | Router variáns | Router terület | **Node összesen** | **Core szám (800 mm²)** |
|-----------|--------|---------------|------------------|:--------------:|---------------:|------------------:|------------------------:|
| Nano | 0,009 mm² | 4 KB | 0,014 mm² | Compact | 0,004 mm² | 0,025 mm² | **~32 000** |
| Actor | 0,018 mm² | 64 KB | 0,036 mm² | Compact | 0,004 mm² | 0,047 mm² | **~17 000** |
| Matrix | 0,019 mm² | 8 KB | 0,025 mm² | Turbo | 0,007 mm² | 0,039 mm² | **~20 500** |
| Rich | 0,022 mm² | 256 KB | 0,083 mm² | Turbo | 0,007 mm² | 0,097 mm² | **~8 250** |
| Seal | 0,200 mm² | 32 KB | 0,210 mm² | — | — | 0,210 mm² | **1** (mindig) |

**Megjegyzés:** A core-számok tartalmazzák az ajánlott L0 router variáns területét és az L1–L3 infrastruktúra per-core részét (~0,007 mm²). Részletekért lásd [`interconnect-hu.md`](interconnect-hu.md), L0 Router variánsok.

**Megjegyzés:** a Matrix Core logikája (0,019 mm²) közel van az Actor-éhoz (0,018 mm²), de a kis SRAM (8 KB vs 64 KB) miatt a Matrix Core **összességében kisebb** (0,025 vs 0,036 mm²). Az SRAM dominálja a core méretet, nem a logika.

### Miért kisebb a Matrix a Rich-nél, ha több hardver van benne?

| Komponens | Rich Core | Matrix Core | Különbség |
|-----------|----------|-------------|-----------|
| Bázis (decoder, pipeline, ALU, stack) | Actor bázis: 0.018 mm² | Nano bázis: 0.009 mm² | **Matrix -50%** |
| FPU | 0.004 mm² | 0.004 mm² | Azonos |
| MAC (4×4) | — | +0.006 mm² | Matrix + |
| SFU | — | +0.003 mm² | Matrix + |
| **Logika összesen** | **0.022 mm²** | **0.019 mm²** | **Matrix -14%** |
| Optimális SRAM | 256 KB (0.057 mm²) | 8 KB (0.002 mm²) | **Matrix -96%** |
| **Core összesen** | **0.083 mm²** | **0.025 mm²** | **Matrix -70%** |

A Matrix Core 70%-kal kisebb a Rich-nél, mert:
1. Nano bázisra épül (nem Actor bázisra) → nincs GC, objektum modell, kivételkezelés
2. Kis SRAM elég (streaming MAC, nem kell nagy lokális memória)

## Power domain-ek

| Egység | Power state | Mikor alszik? | Wake trigger |
|--------|-----------|--------------|-------------|
| Bármely core | Per-core clock gating | Üres mailbox | Mailbox interrupt |
| Rich/Matrix FPU | Külön power domain | Nincs FP művelet | FP opkód detektálása |
| Matrix MAC array | Külön power domain | Nincs mátrix szorzás | MAC opkód detektálása |
| Matrix SFU | Külön power domain | Nincs transzcendens fv | SFU opkód detektálása |
| Cluster (16 core) | Per-cluster power gating | Mind a 16 core alszik | Bármely core-nak érkező cella |
| Tile (L1 crossbar) | Per-tile power gating | Minden cluster alszik | Cella érkezés |
| Régió (L2 crossbar) | Per-régió power gating | Minden tile alszik | Cella érkezés |
| L3 crossbar | Power-gated | Nincs cross-régió forgalom | Cross-régió cella |
| Seal Core | Power-gated | Nincs kód betöltés | Kód-betöltési kérés |

A Matrix Core három **független** power domain-nel rendelkezik (FPU, MAC, SFU) — ha csak skalár FP kell, a MAC és SFU alszik; ha csak MAC kell, az SFU alszik. Ez lehetővé teszi, hogy a Matrix Core **a feladathoz igazítsa a fogyasztását**.

## CFPU termékcsalád

| Variáns | Seal | Core-ok | Célpiac | Példa (7nm, 800 mm²) |
|---------|------|---------|---------|----------------------|
| **CFPU-N** | 1 Seal | Nano only | IoT, masszív SNN spike háló | 1S + ~32 000N (4 KB) |
| **CFPU-A** | 1 Seal | Actor only | Actor cluster, stream processing | 1S + ~17 000A (64 KB) |
| **CFPU-R** | 1 Seal | Rich only | Teljes .NET, FP-igényes | 1S + ~8 250R (256 KB) |
| **CFPU-ML** | 1 Seal | Matrix + Actor | ML/SNN optimalizált | 1S + ~19 500M + ~1 000A |
| **CFPU-H** | 1 Seal | Actor + Nano | Heterogén supervisor+worker | 1S + 2 000A + ~24 000N |
| **CFPU-X** | 1 Seal | Vegyes (bármely kombináció) | Alkalmazás-specifikus | Egyedi |

### CFPU-ML: az ML/SNN-re optimalizált chip

A CFPU-ML a legérdekesebb variáns ML/SNN szempontból:

| Metrika | Érték |
|---------|-------|
| Matrix Core-ok | ~19 500 (8 KB SRAM, Turbo router) |
| Actor Core-ok | ~1 000 (64 KB, Compact router, supervisor/scheduler) |
| Párhuzamos MAC egységek | 19 500 × 16 = **312 000** |
| INT8 peak throughput (500 MHz) | **~312 TOPS** ⁽¹⁾ |
| INT8 sustained throughput | **~49–176 TOPS** ⁽¹⁾ |
| Becsült TDP (10% aktív) | ~3-5 W ⁽²⁾ |
| On-chip SRAM | ~200 MB |

> ⁽¹⁾ A peak elméleti: core szám × MAC egységek × órajel. A sustained tartomány az SRAM mérettől és az optimalizálási stratégiától függ (weight reuse, systolic láncolás, post-MAC feldolgozás) — lásd [Matrix Core: Sustained vs. Peak Throughput](#matrix-core-sustained-vs-peak-throughput). RTL szimuláció vagy szilícium mérés még nem áll rendelkezésre.
>
> ⁽²⁾ Aritmetikai becslés 10%-os egyidejű core aktivitás mellett. Nem tartalmazza a router/interconnect fogyasztást, SRAM leakage-t, I/O-t és off-chip memória hozzáférést. A valós TDP jelentősen magasabb lesz — validált fogyasztási adatokhoz legalább RTL-szintű power analízis szükséges.

## Tervezési megkülönböztetők

A CFPU-ML architektúrális egyedisége nem a nyers áteresztőképességben rejlik, hanem olyan tulajdonságok kombinációjában, amelyeket egyetlen létező chip sem kínál együtt:

| Tulajdonság | Leírás |
|-------------|--------|
| Programozható neuron modell | Minden core tetszőleges CIL kódot futtat — nem fix LIF/SNN topológia |
| Hardveres MAC | 16 INT8 MAC egység Matrix Core-onként, a végrehajtási pipeline-ba integrálva |
| Event-driven (0W idle) | A core-ok csak mailbox üzenetre ébrednek — nincs polling, nincs idle fogyasztás |
| .NET natív | C# / F# CIL-re fordítva, natívan végrehajtva — nincs driver stack, nincs CUDA |
| Nyílt forráskód | Teljes ISA, RTL (tervezett), toolchain és OS — auditálható, fork-olható |
| Csak on-chip SRAM | Nincs DRAM controller — determinisztikus latencia, de korlátozott modell méret |

> **A CFPU-ML nem TOPS/W benchmarkokban versenyez production szilíciummal.** Az értékajánlata egy teljesen programozható, nyílt forráskódú, event-driven neuromorphic platform. Teljesítmény-összehasonlítást az RTL-szintű power szimuláció elkészülte után publikálunk.

## Miért CFPU-ML?

A CFPU-ML értéke nem a nyers TOPS-ban rejlik, hanem olyan **architekturális tulajdonságok kombinációjában**, amelyet egyetlen meglévő chip sem kínál együtt: programozható neuron modell (tetszőleges CIL), event-driven működés (0W idle), shared memory nélküli izolált core-ok, nyílt forráskódú hardver (CERN-OHL-S), és natív .NET CIL végrehajtás.

A CFPU-ML-Max variáns — Systolic Wide routerrel, post-MAC pipeline-nal és 1 GHz órajellel — **90–95% sustained MAC kihasználtságot** ér el, és azonos die méret mellett 2–3,7× jobb sustained TOPS-t ad, mint az NVIDIA RTX 4060/4090 (dense INT8, sparsity nélkül).

A részletes versenytárs-összehasonlítást, die variánsokat, célmodelleket és pozícionálást lásd: **[CFPU-ML-Max: ML/SNN Inference Accelerator](cfpu-ml-max-hu.md)**.

## Kapcsolódó dokumentumok

- [CFPU-ML-Max](cfpu-ml-max-hu.md) — ML/SNN inference accelerator: optimalizálási lépések, die variánsok, NVIDIA összehasonlítás
- [Interconnect architektúra](interconnect-hu.md) — 4-szintű hierarchia, switching modell, router felépítés
- [Quench-RAM](quench-ram-hu.md) — per-blokk immutability, QRAM+hálózat szimbiózis
- [ISA-CIL-T0](ISA-CIL-T0-hu.md) — a Nano és Matrix Core ISA alapja
- [Architektúra](architecture-hu.md) — a teljes CFPU áttekintés

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|------------|----------------------------------------------|
| 1.6 | 2026-04-19 | „Miért CFPU-ML?" szekció rövidítve, versenytárs-összehasonlító tábla és célterületek áthelyezve a dedikált [CFPU-ML-Max](cfpu-ml-max-hu.md) dokumentumba |
| 1.5 | 2026-04-19 | Systolic router variáns hozzáadva a Matrix Core szekcióhoz: 128-bit linkek, MAC ~100% kihasználtság, sustained TOPS tábla (329–368 TOPS @ 8 KB), 8 KB sweet spot megfordulás |
| 1.4 | 2026-04-19 | Cella payload 128→64 byte: router terület csökkenés (Turbo 0,009→0,007 mm², Compact 0,005→0,004 mm²), infra 0,008→0,007 mm². Core-számok, TOPS és termékcsalád metrikák újraszámolva |
| 1.3 | 2026-04-19 | Peak/sustained fogalom magyarázat. „Miért CFPU-ML?" értékajánlat szekció versenytárs-összehasonlító táblával és célterületekkel |
| 1.2 | 2026-04-19 | Matrix Core sustained vs. peak throughput elemzés: hálózati sávszélesség szűk keresztmetszet, három optimalizálási stratégia (weight reuse nagyobb SRAM-mal, post-MAC feldolgozás, systolic láncolás). CFPU-ML metrikák frissítve sustained TOPS tartománnyal |
| 1.1 | 2026-04-19 | Core-számok korrigálva L0 router területtel (Turbo/Compact variánsok) és L1–L3 infrastruktúra overhead-del. CFPU-ML metrikák frissítve. Matrix Core SRAM tábla node összesen oszloppal |
| 1.0 | 2026-04-18 | Kezdeti verzió — 5 core típus, kettős specializáció, terület összehasonlítás, SRAM méretezés, power domain-ek, termékcsalád, piaci pozíció |
