# CFPU-ML-Max: ML/SNN Inference Accelerator

> English version: [cfpu-ml-max-en.md](cfpu-ml-max-en.md)

> Version: 1.0

## Státusz

> ⚠️ Ez a dokumentum **aritmetikai projekciókon** alapul — szintézis és RTL-szintű validáció előtti állapot. A számok a tervezési irányokat jelzik, nem mért teljesítményadatokat. Validált értékekhez legalább RTL-szintű power analízis és szilícium mérés szükséges.

## Összefoglaló

A CFPU-ML-Max a Cognitive Fabric Processing Unit (CFPU) processzorcsalád ML/SNN inference-re optimalizált variánsa. A standard Matrix Core architektúrából kiindulva hat optimalizálási lépésen ment keresztül — cella méret csökkentés, systolic router, szélesebb link, post-MAC pipeline, SRAM sweet spot megfordítás, órajel optimalizálás —, amelyek együttesen **90–95%-os sustained MAC kihasználtságot** eredményeznek. Az NVIDIA-val azonos die méret és gyártási csomópont (5nm) mellett a CFPU-ML-Max kis/közepes inference modellekre (MobileNet, ResNet, YOLOv8, BERT-Base) kínál versenyképes sustained TOPS-t, 4–7× jobb TOPS/W hatékonysággal, kizárólag on-chip SRAM-mal, DRAM controller nélkül.

## Optimalizálási lépések

### 1. Cella payload 128 → 64 byte

**Mit csináltunk:** Az interconnect cella payload méretét 128 byte-ról 64 byte-ra csökkentettük.

**Miért:** A Matrix Core MAC array-ja 4×4-es INT8 tile-okban dolgozik — egy tile 32 byte input. A 128 byte-os cella kétszeresen túlméretezett volt, feleslegesen nagy buffert és routert igényelt.

**Hatás:** 39% latencia csökkenés, 24% kisebb router terület. A 2-hatvány cella méret megmaradt, az illesztés egyszerű.

### 2. Systolic router — kommunikációs útvonalak csökkentése

**Mit csináltunk:** A Turbo router (5 portos, XY routing, VOQ, iSLIP) helyett 2 irányú, egyirányú systolic routert vezettünk be. Az XY routing, VOQ és iSLIP teljes egészében eltávolítva.

**Miért:** Az ML inference-ben az adat egy irányba folyik — nincs szükség általános célú, tetszőleges irányú routing-ra. A systolic adatfolyam természetesen illeszkedik a mesh topológiához.

**Hatás:** ~5 000 GE router (0,001 mm²) — 81% kisebb, mint a Turbo. A felszabadult vezeték-büdzsé lett a következő lépés alapja.

### 3. Szélesebb link — a vezeték-büdzsé átcsoportosítása

**Mit csináltunk:** A Turbo router ~340 vezetéket használt per core (4 irány × 85). A Systolic-kal ez ~98-ra csökkent. A felszabadult büdzsét a két fő adatútvonal szélesítésére fordítottuk: 42 → 128 bit per irány (W→E aktiváció, N→S súly).

**Miért:** A MAC 32 byte/cc-t fogyaszt (16 byte aktiváció + 16 byte súly). A 128-bit link 16 byte/cc-t szállít irányonként, ami pontosan megfelel a MAC igényének.

**Hatás:** ~274 vezeték/core (kevesebb mint a Turbo ~340), de 3× sávszélesség (128 vs 42 bit/cc). A MAC kihasználtság ~15%-ról ~90–95%-ra nő.

### 4. Post-MAC pipeline

**Mit csináltunk:** Három feldolgozási lépést integráltunk a MAC kimenetére, hardverben:
- **ReLU** aktiváció — 160 GE (egyetlen komparátor)
- **Quantize** INT32→INT8 — 300 GE
- **Max-Pool 2×2** — 200 GE

**Miért:** A nyers MAC kimenet 64 byte/tile (16 × INT32). A post-MAC pipeline ezt 4 byte-ra csökkenti — **16× kimeneti forgalom csökkenés**. Ezzel a kimeneti link sávszélessége felszabadul.

**Hatás:** 660 GE összesen (~0,0001 mm²), gyakorlatilag nulla terület-költség. A hálózati terhelés drasztikusan csökken.

### 5. SRAM sweet spot megfordulás (32 → 8 KB)

**Mit csináltunk:** A korábbi 32 KB-os SRAM optimumot 8 KB-ra csökkentettük.

**Miért:** A Systolic Wide router 128-bit linkjei önmagukban elegendőek a MAC táplálásához — a weight cache előnye nem kompenzálja az elvesztett core-okat. A 8 KB-os konfiguráció adja a legjobb sustained TOPS-t, mert a kisebb node méret több core-t tesz lehetővé.

**Hatás:** +18% core szám a 32 KB-os variánshoz képest.

### 6. Órajel optimalizálás (1 GHz)

**Mit csináltunk:** Az órajelet 500 MHz-ről 1 GHz-re emeltük.

**Miért:** A TOPS lineárisan nő az órajellel, de a fogyasztás szupra-lineárisan. Az 1 GHz a legjobb kompromisszum a nyers TOPS és a TOPS/W hatékonyság között — ennél magasabb órajelen a fogyasztás/TOPS arány rohamosan romlik.

**Hatás:** 2× TOPS növekedés az 500 MHz-es variánshoz képest, TOPS/W ~4,3–4,7 fenntartható.

## Core specifikáció

| Paraméter | Érték |
|-----------|-------|
| **Gyártási csomópont** | 5nm |
| **Órajel** | 1 GHz |
| **Node terület** | 0,019 mm² |
| **MAC array** | 4×4 INT8 (16 MAC/core/ciklus) |
| **Router** | Systolic Wide (~5 000 GE, 0,001 mm²) |
| **Post-MAC pipeline** | ReLU + Quantize + Max-Pool 2×2 (~660 GE) |
| **Router + Post-MAC összesen** | ~5 660 GE ≈ 0,001 mm² |
| **SRAM** | 8 KB |
| **Sustained MAC kihasználtság** | 90–95% |
| **Linkek** | 128-bit W→E + 128-bit N→S + ~10 control uplink |
| **Vezetékek/core** | ~274 |

## Die variánsok

5nm, 1 GHz, 8 KB SRAM:

| Die | Core | Peak TOPS | Sustained TOPS | SRAM | TDP | TOPS/W |
|-----|------|-----------|----------------|------|-----|--------|
| 80 mm² | ~4 200 | 134 | ~121–128 | 34 MB | ~28 W | ~4,3–4,6 |
| 159 mm² | ~8 400 | 269 | ~242–256 | 67 MB | ~55 W | ~4,4–4,7 |
| 200 mm² | ~10 500 | 336 | ~302–319 | 84 MB | ~69 W | ~4,4–4,6 |
| 400 mm² | ~21 000 | 672 | ~605–638 | 168 MB | ~138 W | ~4,4–4,6 |
| 609 mm² | ~32 000 | 1 024 | ~922–973 | 256 MB | ~210 W | ~4,4–4,6 |
| 814 mm² | ~42 800 | 1 370 | ~1 233–1 301 | 342 MB | ~280 W | ~4,4–4,6 |

> A TDP becslések szintézis előttiek — aritmetikai projekciók. Validált fogyasztási adatokhoz legalább RTL-szintű power analízis szükséges.

## Célmodellek

Az on-chip SRAM mérete határozza meg, melyik ML modell fér el teljesen a chipen (DRAM controller nélkül):

| Modell | Súly méret | Minimális die | Megjegyzés |
|--------|-----------|---------------|------------|
| MobileNet v2 | 3,4 MB | 80 mm² (34 MB) | Bőven elfér, edge deployment |
| ResNet-50 | 25 MB | 200 mm² (84 MB) | Kényelmesen elfér |
| YOLOv8-S | 22 MB | 200 mm² (84 MB) | Valós idejű objektum detekció |
| EfficientNet-B4 | 75 MB | 400 mm² (168 MB) | Közepes méretű képosztályozó |
| BERT-Base | 110 MB | 814 mm² (342 MB) | NLP inference, nagy die |
| LLaMA-7B | 7 GB | — | Nem fér el, DRAM szükséges |

> A CFPU-ML-Max **nem LLM accelerator**. Kis és közepes inference modellekre optimalizált, ahol a teljes modell elfér az elosztott SRAM-ban.

## Versenytárs összehasonlítás

Azonos die méret, azonos gyártási csomópont (~5nm/4nm), dense INT8 (sparsity nélkül):

### vs RTX 4060 (159 mm²)

| Metrika | CFPU-ML-Max (becsült) | NVIDIA RTX 4060 |
|---------|-------------|-----------------|
| Die | 159 mm² | 159 mm² |
| Peak TOPS (INT8) | 269 | ~175 |
| Sustained TOPS (INT8) | 242–256 | 70–122 |
| CFPU becsült előny (sustained) | — | **2,0–3,7×** |
| Becsült TOPS/W előny | — | **4–7×** |

### vs RTX 4090 (609 mm²)

| Metrika | CFPU-ML-Max (becsült) | NVIDIA RTX 4090 |
|---------|-------------|-----------------|
| Die | 609 mm² | 609 mm² |
| Peak TOPS (INT8) | 1 024 | ~660 |
| Sustained TOPS (INT8) | 922–973 | 264–462 |
| CFPU becsült előny (sustained) | — | **2,0–3,7×** |
| Becsült TOPS/W előny | — | **4–7×** |

### vs H100 (814 mm²)

| Metrika | CFPU-ML-Max (becsült) | NVIDIA H100 |
|---------|-------------|-------------|
| Die | 814 mm² | 814 mm² |
| Peak TOPS (INT8) | 1 370 | ~1 979 |
| Sustained TOPS (INT8) | 1 233–1 301 | 792–1 385 |
| CFPU becsült tartomány (sustained) | — | **0,9–1,6×** |
| Becsült TOPS/W előny | — | **2–4×** |

### Fontos megjegyzések

1. **NVIDIA dense** — sparsity nélküli értékek. Az NVIDIA structured sparsity-vel magasabb csúcsértéket hirdet, de a legtöbb workload nem képes azt kihasználni.
2. **NVIDIA sustained = 40–70% of peak** — a valós kihasználtság workload-függő. A GPU die ~30–35%-a ML hardver (RTX 4060/4090 esetén), a többi raszterizáció, video, display engine stb.
3. **CFPU sustained = 90–95% of peak** — a Systolic Wide router és a post-MAC pipeline szinte teljes MAC kihasználtságot biztosít.
4. **CFPU 100% ML die** — nincs raszterizációs hardver, nincs video dekóder, nincs display engine. Minden tranzisztor ML inference-re fordítódik.
5. **TDP becslések szintézis előttiek** — a CFPU fogyasztási adatok aritmetikai projekciók, RTL-szintű power analízis még nem áll rendelkezésre.
6. **CFPU nem LLM accelerator** — a DRAM controller hiánya miatt csak azok a modellek futtathatók, amelyek elférnek az on-chip SRAM-ban.

### Miért alacsony az NVIDIA sustained?

Három fő ok:

1. **Die terület megosztás** — az RTX 4060/4090 die-jának ~30–35%-a ML (Tensor Core). A maradék raszterizáció, RT core, video, display. A CFPU-ML-Max 100% ML.
2. **GDDR memória szűk keresztmetszet** — a GPU Tensor Core-jai gyorsabban fogyasztják az adatot, mint amennyit a GDDR6X szállítani tud. A CFPU lokális SRAM-ból dolgozik, nincs DRAM latencia.
3. **Nem-ML hardver fogyaszt** — a GPU TDP-jébe beleszámít a raszterizáció, video dekóder, display engine fogyasztása is.

## Pozíció

### Hol erős a CFPU-ML-Max

- **Kis/közepes inference modellek** (MobileNet, ResNet, YOLOv8, EfficientNet) — a teljes modell elfér az on-chip SRAM-ban, nincs DRAM latencia
- **Determinisztikus latencia** — SRAM-only, nincs DRAM refresh, nincs cache miss
- **Energiahatékonyság** — 4–7× TOPS/W előny az NVIDIA-val szemben azonos die-on
- **Edge deployment** — a 80 mm²-es variáns 121–128 sustained TOPS-t ad ~28 W-on
- **Biztonsági követelmények** — Seal Core hardver-szintű kódhitelesítés minden betöltött modellhez
- **Nyílt forráskód** — teljes ISA, RTL (tervezett), toolchain — auditálható, fork-olható

### Hol nem a jó választás

- **LLM inference** (GPT, LLaMA-7B+) — nem fér el az SRAM-ban, nincs DRAM controller
- **Tanítás (training)** — nincs backpropagation hardver, nincs nagy sávszélességű memória
- **FP32/FP16 workload-ok** — a MAC array INT8-optimalizált, FP32 számítás nem hatékony
- **Dinamikus modell méretezés** — az SRAM méret fix, futásidőben nem bővíthető

## Kapcsolódó dokumentumok

- [Core család](core-types-hu.md) — az öt CFPU core típus specifikációja
- [Interconnect architektúra](interconnect-hu.md) — 4-szintű hierarchia, Systolic Wide router
- [Quench-RAM](quench-ram-hu.md) — per-blokk immutabilitás
- [Seal Core](sealcore-hu.md) — hardveres kódhitelesítés
- [ISA-CIL-T0](ISA-CIL-T0-hu.md) — a Matrix Core ISA alapja
- [Architektúra](architecture-hu.md) — a teljes CFPU áttekintés

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-19 | Kezdeti verzió — 5 optimalizálási lépés, core specifikáció, 6 die variáns, célmodellek, NVIDIA összehasonlítás (RTX 4060, 4090, H100), pozícionálás |
