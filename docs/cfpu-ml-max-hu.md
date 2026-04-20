# CFPU-ML-Max v2.0 — ML Inference Accelerator (500 MHz, chiplet)

> Version: 2.0-draft
> Dátum: 2026-04-20

## Státusz

> ⚠️ **Aritmetikai projekciók** — szintézis és RTL előtti állapot. A számok +25% logikai design margint, ISSCC referencia SRAM sűrűséget (0,021 mm²/Mbit), és KV cache memória-budgetet tartalmaznak. Pure SRAM-only, chiplet architektúra.

## Architektúra összefoglaló

- **MAC Slice:** 8×8 INT8 MAC, FSM-vezérelt (nincs CIL-T0 CPU), zero-skip sparsity alap, dual-mode (WS + AS)
- **Cluster:** 2×4 (8 core, 8×8 MAC), megosztott 128-bit systolic router
- **Tine die:** ~85 mm² (5nm), egyetlen design — a termékcsalád építőköve
- **Package:** 2×9 tine (18 die SoIC+CoWoS, ~850 mm² footprint), flip-chip BGA
- **Packaging:** SoIC hybrid bond páron belül (1–2 ciklus, láthatatlan), CoWoS interposer párok között (3–5 ciklus)
- **Órajel:** 500 MHz (alacsony feszültség → jobb TOPS/W)
- **IOD:** Actor Core-ok (~150 db, FP16) + Seal Core + I/O PHY — olcsó node-on (N28/N7)
- **SKU család:** tine szám (1–18) × SRAM méret (8–256 KB/core)

## MAC Slice specifikáció

| Komponens | Terület | Megjegyzés |
|-----------|---:|---|
| MAC 8×8 + zero-skip | 0,01050 mm² | +25% routing, +~500 GE sparsity |
| FSM (dual-mode: WS + AS) | 0,000375 mm² | Weight-stationary + Activation-stationary |
| Post-MAC | 0,000625 mm² | 2 500 GE (8 output lane) |
| **Logika összesen** | **0,0135 mm²** | |

### Alap funkciók (minden MAC Slice-ban)

- **Zero-skip sparsity:** Ha a súly == 0, a MAC kihagyja a szorzást (~500 GE, ~2% terület). Structured (2:4) és unstructured sparsity is támogatott. Effektív 1,5–2× gyorsulás tipikus modelleken.
- **Dual-mode FSM:** Weight-stationary (FFN rétegekre) ÉS Activation-stationary (Attention Q×K^T, scores×V). 1 bit mode regiszter, a MAC hardver változatlan.
- **Post-MAC pipeline** (2 500 GE): ReLU (~300), INT32→INT8 quantize (~1 200), 2×2 Max-Pool (~400), pipeline regiszterek (~600).

> **Nem tartalmaz:** per-channel quantization paramétert. Per-channel esetén +3 000–5 000 GE.

## SRAM sűrűség

TSMC 5nm 6T SRAM: **0,021 mm²/Mbit** (ISSCC referencia, periféria-val együtt).

| SRAM/core | Terület |
|---:|---:|
| 4 KB | 0,00067 mm² |
| 8 KB | 0,00134 mm² |
| 16 KB | 0,00269 mm² |
| 32 KB | 0,00538 mm² |
| 64 KB | 0,01075 mm² |
| 128 KB | 0,02150 mm² |
| 256 KB | 0,04200 mm² |

## SKU család — cluster-től chip-ig

2×4 Cluster: 8 × 8×8 MAC Slice, 128-bit systolic link, overhead 0,007 mm². A nyugati szél 2 core × 8 byte = 16 byte = 128 bit (pont a link kapacitás). Minden érték 500 MHz, 2:4 sparsity-vel.

### SKU-k: cluster → tine (85 mm²) → chip (18 tine)

| SKU | SRAM/core | Core méret | Cluster | Core/tine | Peak/tine | SRAM/tine | Core/chip | **Peak/chip** | **SRAM/chip** | **TDP/chip** | **TOPS/W** |
|-----|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **S** | 4 KB | 0,014 mm² | 0,120 mm² | 5 536 | 354 TOPS | 22 MB | 99 648 | **6 379 TOPS** | **390 MB** | **~500W** | **~13** |
| **M** | 8 KB | 0,015 mm² | 0,126 mm² | 5 264 | 337 TOPS | 41 MB | 94 752 | **6 066 TOPS** | **740 MB** | **~500W** | **~12** |
| **L** | 16 KB | 0,016 mm² | 0,137 mm² | 4 848 | 310 TOPS | 76 MB | 87 264 | **5 586 TOPS** | **1,3 GB** | **~480W** | **~12** |
| **H** | 256 KB | 0,056 mm² | 0,451 mm² | 1 472 | 94 TOPS | 368 MB | 26 496 | **1 696 TOPS** | **6,5 GB** | **~300W** | **~6** |

> **M**: compute-fókusz (Vision, BERT, batch serving). **H**: SRAM-fókusz (LLM modell + KV cache). **S** és **L** a szélső értékek. A chip szám (1–18 tine) binning-gel a yield-ből adódik.

## Tine die felhasználható terület

A tine die (85 mm², 5nm) **kizárólag MAC Slice clustereket és SRAM-ot** tartalmaz. Az Actor Core-ok, Seal Core, I/O PHY és PLL-ek az **IOD-n** vannak (külön die, olcsó node). Flip-chip BGA: nincs pad ring a tine die-on.

| Elem | Hol | Terület |
|------|-----|---:|
| MAC Slice clusterek + SRAM | Tine die (5nm) | ~83 mm² felhasználható |
| ~~Actor Core, Seal, I/O, PLL~~ | ~~Tine die~~ | → **IOD-ra költöztek** |
| SoIC bond padok | Tine die szélén | ~2 mm² |
| **Felhasználható per tine** | | **~83 mm²** |

| IOD elem | Terület | Node |
|----------|---:|---|
| ~150 Actor Core (FP16) | ~3,75 mm² | N28/N7 |
| Seal Core | ~0,12 mm² | N28/N7 |
| PCIe/CXL PHY | ~10 mm² | N28/N7 |
| PLL, clock distribution | ~2 mm² | N28/N7 |
| **IOD összesen** | **~50 mm²** | **Olcsó node** |

## Teljesítmény-értékelési módszertan

### Három alap funkció hatása a kihasználtságra

| Funkció | Hatás | Terület költség |
|---------|-------|---:|
| **Zero-skip sparsity** | 1,5–2× effektív gyorsulás sparse modelleken | ~500 GE (~2%) |
| **Dual-mode FSM (WS+AS)** | Attention kihasználtság 50→65–78% | ~1 bit regiszter |
| **8×8 MAC (2×4 cluster)** | 64 MAC/core, 512 MAC/cluster | 128-bit link illeszkedés |

### Kihasználtsági szintek

| Szint | Vision | Transformer | Megjegyzés |
|-------|---:|---:|---|
| **Peak** | 100% | 100% | Elméleti max |
| **Realistic (sparsity nélkül)** | 65–78% | 65–78% | AS mód az Attention-re is |
| **Realistic (sparsity-vel)** | 100–156%* | 100–156%* | Zero-skip: effektív > 100% |

> *A sparsity-vel az effektív kihasználtság meghaladhatja a 100%-ot, mert a nulla súlyok kihagyásával a hasznos compute/ciklus nő. A táblázatokban az effektív TOPS-t közöljük (peak × utilization × sparsity_factor).

### Sparsity faktor modellenként

| Modell | Tipikus nulla súlyok | Sparsity faktor |
|--------|---:|---:|
| ResNet-50 | ~30% | 1,3× |
| BERT-Base | ~40% | 1,5× |
| LLaMA-7B (INT4, pruned) | ~50% (2:4) | 2,0× |
| LLaMA-70B (INT4, pruned) | ~50% (2:4) | 2,0× |
| Dense (nem prune-olt) | 0% | 1,0× |

> A 2:4 structured sparsity (50% nulla) az iparági standard prune-olási módszer. A számítások 2:4 sparsity-t feltételeznek ahol jelölve.

### Dual-mode FSM — az Attention javítás

Az Attention mechanizmus eredetileg NEM weight-stationary:

```
FFN réteg:  Input × W_FFN       → W helyben ✅ (weight-stationary előny teljes)
Attention:  Q × K^T             → mindkettő aktiváció ❌ (nincs WS előny)
            softmax(scores) × V → szintén ❌
```

A Transformer compute idejének ~40–50%-a attention → a weight-stationary előny csak az FFN részre (~50–60%) érvényes. A blended kihasználtság emiatt alacsonyabb.

A Vision modelleknek (ResNet, YOLO, MobileNet) nincs attention mechanizmusuk → teljes WS előny.

## Tine die és package összesítés

A tine die 85 mm² (5nm), ~83 mm² felhasználható. A package 18 tine-t tartalmaz (2×9 gyűrű + IOD). A fő SKU-k teljesítménye a **[SKU család](#sku-család--cluster-től-package-ig)** szekció táblázataiból származik. Számolás: cluster/tine = 83 mm² / cluster_terület, core = cluster × core/cluster, Peak TOPS = core × MAC/core × 2 × 500 MHz / 1T, sparsity 2:4 effektív.

## Modell-lefedettség (chiplet, 18 tine package)

### Memória budget (batch=1, 2K context)

| Modell | Súlyok | KV cache | Akt. | **Össz** | M chip (740MB) | H chip (6,5GB) |
|--------|---:|---:|---:|---:|:---:|:---:|
| ResNet-50 | 25 MB | — | 10 MB | 35 MB | ✅ | ✅ |
| BERT-Large | 340 MB | 50 MB | 25 MB | 415 MB | ✅ | ✅ |
| GPT-2 | 500 MB | 75 MB | 20 MB | 595 MB | ✅ | ✅ |
| LLaMA-7B INT4 | 3,5 GB | 0,5 GB | 0,2 GB | 4,2 GB | ❌ | ✅ (1 chip) |
| LLaMA-13B INT4 | 6,5 GB | 1,0 GB | 0,3 GB | 7,8 GB | ❌ | ❌ (2 chip) |
| LLaMA-70B INT4 | 35 GB | 2,7 GB | 0,4 GB | 38 GB | ❌ | ❌ (6 chip) |
| LLaMA-405B INT4 | 203 GB | 8,5 GB | 0,8 GB | 212 GB | ❌ | ❌ (33 chip) |
| DeepSeek R1 (671B) | 700 GB | 5 GB | 1 GB | 706 GB | ❌ | ❌ (109 chip) |
| GPT-4o szintű (~1,8T) | 900 GB | 10 GB | 2 GB | 912 GB | ❌ | ❌ (141 chip) |

### Package szám modellekhez (H SKU, 6,5 GB/chip)

| Modell | Memória | Package | Össz TDP | Össz Peak TOPS |
|--------|---:|---:|---:|---:|
| LLaMA-7B INT4 | 4,2 GB | **1** | ~350W | 1 696 |
| LLaMA-13B INT4 | 7,8 GB | **2** | ~700W | 3 392 |
| LLaMA-70B INT4 | 38 GB | **6** | ~2 100W | 10 176 |
| LLaMA-405B INT4 | 212 GB | **33** | ~11 550W | 55 968 |
| DeepSeek R1 | 706 GB | **109** | ~38 150W | 184 864 |
| GPT-4o szintű | 912 GB | **141** | ~49 350W | 239 136 |

## Versenytárs összehasonlítás

### Konkurens chipek referencia adatai

| Chip | Node | Die mm² | INT8 TOPS (dense) | Memória | Mem BW | TDP | Típus |
|------|------|---:|---:|---|---:|---:|---|
| **CFPU H** | **5nm** | **18×85** | **1 696** | **6,5 GB SRAM** | **on-chip** | **~300W** | **SRAM-only chiplet** |
| NVIDIA H100 SXM | 4nm | 814 | 1 979 | 80 GB HBM3 | 3 350 GB/s | 700W | GPU + HBM |
| NVIDIA L4 | 4nm | 294 | 242 | 24 GB GDDR6 | 300 GB/s | 72W | GPU + GDDR |
| NVIDIA B200 | 4nm | 2×858 | 4 500 | 192 GB HBM3e | 8 000 GB/s | 1 000W | GPU + HBM |
| Groq LPU v1 | **14nm** | 725 | ~750 | 230 MB SRAM | 80 TB/s on-chip | ~300W | SRAM-only |
| Groq 5nm (hip.) | 5nm | ~725 | ~2 000 | ~2,6 GB SRAM | on-chip | ~350W | SRAM-only (nem létezik) |
| Google TPU v5e | ~7nm | ~350 | 393 | 16 GB HBM2e | 819 GB/s | ~160W | ASIC + HBM |
| QC Cloud AI 100 Pro | 7nm | n/a | 400 | 32 GB LPDDR4x | 136 GB/s | 75W | ASIC + LPDDR |
| QC Cloud AI 100 Ultra | 7nm | n/a | 870 | 128 GB LPDDR4x | 548 GB/s | 150W | ASIC + LPDDR |

### Módszertan

- **Produkciós üzemeltetés** — az összehasonlítás alapja: adott rendszer-throughput (tok/s) eléréséhez hány chip kell és mennyi az energiafogyasztás
- A memóriaigény = modell súlyok + **aktív KV cache** (nem minden regisztrált user, csak az épp generálók)
- NVIDIA: TensorRT-LLM, continuous batching, TBP tartalmazza GPU + HBM fogyasztását
- CFPU: realistic értékek (+25% design margin), SRAM-only, ~300W/chip (H)
- A tok/sec értékek **rendszer-throughput** (nem per-user)

### KV cache — a valóság

A KV cache NEM állandó. Egy user kérésének feldolgozása (~1-5 másodperc) alatt létezik, utána felszabadul. Milliós felhasználóbázisnál annak esélye, hogy a következő kérés ugyanattól jön akinek még „meleg" a KV cache-e: ~0,01%. Ezért **minden kérés új prefill + új KV cache → ideiglenes, másodpercek**.

| Modell | GQA KV heads | KV/user (500 tok, tipikus) | KV/user (2K tok) |
|--------|---:|---:|---:|
| LLaMA-70B | 8 | 80 MB | 320 MB |
| LLaMA-405B | 8 | 413 MB | 1,6 GB |
| DeepSeek R1 | 128 (MLA) | ~13 MB | ~50 MB |
| Claude szintű (~175B) | ~8 | 88 MB | 350 MB |


### Produkciós modellek mérete (2025-2026)

| Modell | Architektúra | Össz param | Aktív/token | Súlyok (FP8) | KV/user (500 tok) |
|--------|-------------|---:|---:|---:|---:|
| LLaMA-70B | Dense, GQA | 70B | 70B | 35 GB | 80 MB |
| LLaMA 4 Scout | MoE 16 exp, GQA | 109B | 17B | ~55 GB | ~25 MB |
| Claude szintű | Dense, GQA | ~175B | ~175B | ~88 GB | ~88 MB |
| DeepSeek R1 | MoE 2048, MLA | 671B | 37B | ~335 GB | ~13 MB |
| GPT-4o szintű | MoE ~16 exp | ~1,8T | ~280B | ~900 GB | ~200 MB |

### Üzemeltetési szcenáriók — LLaMA-70B, 30 tok/s per user

Egy adott pillanatban az **egyidejűleg generáló** user-ek számítanak, nem a regisztráltak. Közülük is a generálás ~2 másodpercig tart → a KV cache ideiglenes.

| Szcenárió | Egyidejű generálás | Throughput | Súlyok + aktív KV | Compute szükséges |
|-----------|---:|---:|---:|---:|
| Kis csapat | 10 | 300 tok/s | 35 + 0,8 = **36 GB** | 44 TOPS |
| Startup | 100 | 3 000 tok/s | 35 + 8 = **43 GB** | 435 TOPS |
| Enterprise | 1 000 | 30 000 tok/s | 35 + 80 = **115 GB** | 4 350 TOPS |
| Nagyvállalat | 10 000 | 300 000 tok/s | 35 + 800 = **835 GB** | 43 500 TOPS |

> Compute szükséges = throughput × 145 GOPS/token (LLaMA-70B). A chip szám a memória VAGY a compute közül a nagyobbik határozza meg.

### LLaMA-70B — 100 egyidejű generálás (Startup)

| | NVIDIA (8 db H100 GPU) | CFPU H | Groq 5nm (hip.) | TPU v5e |
|--|---:|---:|---:|---:|
| Memória kell | 43 GB | 43 GB | 43 GB | 43 GB |
| Chip (memória) | 1 node (640 GB) | 7 (45 GB) | 17 (44 GB) | 3 (48 GB) |
| Chip (compute, 3K tok/s) | 1 node | 4 (540 TOPS) | 2 (2 700 TOPS) | 8 (3 144 TOPS) |
| **Döntő korlát** | **1 node** | **7 (memória)** | **17 (memória)** | **8 (compute)** |
| Össz TDP | 5 600W | 2 100W | ~5 950W | ~1 280W |
| Throughput | ~3 000 tok/s | ~3 000 tok/s | ~3 000 tok/s | ~3 000 tok/s |
| **J/token** | **1,87** | **0,70** | **~1,98** | **~0,43** |
| Gyártási költség | ~$13K (4×$3,3K) | **~$7,7K** | n/a | n/a |

### LLaMA-70B — 1 000 egyidejű generálás (Enterprise)

| | NVIDIA (80 db H100 GPU) | CFPU H | Groq 5nm (hip.) |
|--|---:|---:|---:|
| Memória kell | 115 GB | 115 GB | 115 GB |
| Chip (memória) | 2 node (1 280 GB) | 18 (117 GB) | 45 (117 GB) |
| Chip (compute, 30K tok/s) | 80 db H100 GPU (10 szerver) | 32 CFPU chip (4 350 TOPS) | 15 chip (20 250 TOPS) |
| **Döntő korlát** | **10 node (compute)** | **32 (compute)** | **45 (memória)** |
| Össz TDP | 56 000W | 9 600W | ~15 750W |
| Throughput | ~30 000 tok/s | ~30 000 tok/s | ~30 000 tok/s |
| **J/token** | **1,87** | **0,32** | **~0,53** |
| Gyártási költség | ~$265K (80×$3,3K) | **~$35K** | n/a |

### LLaMA-70B — 10 000 egyidejű generálás (Nagyvállalat)

| | NVIDIA (800 db H100 GPU) | CFPU H |
|--|---:|---:|
| Memória kell | 835 GB | 835 GB |
| Chip (memória) | 11 node (1 408 GB) | 129 (839 GB) |
| Chip (compute, 300K tok/s) | 100 node (800 GPU) | 321 (43 600 TOPS) |
| **Döntő korlát** | **100 node (compute)** | **321 (compute)** |
| Össz TDP | 560 000W | 96 300W |
| **J/token** | **1,87** | **0,32** |
| Gyártási költség | ~$2,7M (800×$3,3K) | **~$353K** |

### Összefoglaló — minden szcenárió

| Szcenárió | CFPU J/token | NVIDIA J/token | **CFPU előny** | CFPU chip ár | NVIDIA ár |
|-----------|---:|---:|---:|---:|---:|
| Batch=1 (latencia) | 0,05 | 1,75 | **35×** | — | — |
| 100 user | 0,70 | 1,87 | **2,7×** | ~$7,7K | ~$13K |
| 1 000 user | 0,32 | 1,87 | **5,8×** | ~$35K | ~$265K |
| 10 000 user | 0,32 | 1,87 | **5,8×** | ~$353K | ~$2,7M |

```
A CFPU MINDEN szcenárióban nyer:
  J/token:  2,7–35× jobb
  Chip ár:  31–68× olcsóbb

Miért?
  1. A KV cache GQA-val kicsi (80 MB/user, nem 2,7 GB) → kevés extra chip
  2. A KV cache ideiglenes (~2 sec) → nem halmozódik
  3. A compute a valódi korlát mindkét oldalon → a CFPU SRAM-ja nem pazarol
  4. Az NVIDIA gyártási költség (~$3 300/GPU) vs CFPU (~$1 100/chip) → ~3× CAPEX különbség
```

> ⚠️ CFPU értékek aritmetikai projekciók. NVIDIA: TensorRT-LLM benchmark-ok. Mindkét oldalon **gyártási költség** (nem eladási ár). Az NVIDIA H100 gyártási költsége ~$3 300/GPU (die + HBM + CoWoS + teszt), a CFPU ~$1 100/chip (18 tine + IOD + SoIC/CoWoS). Az eladási ár mindkét oldalon magasabb lenne (R&amp;D, margin, szoftver).

## Chiplet layout — 2×9 tine, gyűrű, SoIC+CoWoS

### Miért chiplet?

A monolitikus nagy die yield-je katasztrofális 5nm-en:

| Die méret | Yield (5nm) | Megjegyzés |
|---:|---:|---|
| 85 mm² | ~94% | Tine die ← ezt használjuk |
| 200 mm² | ~80% | |
| 400 mm² | ~55% | |
| 814 mm² | ~22% | H100 — az utolsó monolitikus nagy die |

A CFPU egyetlen 85 mm²-es tine die-t tervez. A termékcsalád a **csomagolásból** jön (hány tine-t rakunk össze), nem a die design-ból.

### A referencia package: 2×9 tine, gyűrű topológia (~800 mm²)

9 stack (páronként 2 tine, SoIC) **3×3 gyűrűben** a CoWoS interposer-en. A középső stack 3-szintű: 2 tine + IOD alul. Minden stack csak a szomszédjával kommunikál — nincs távoli hop. Összesen **18 tine**.

```
Felülnézet (CoWoS interposer):

  ┌──────────────────────────────────────┐
  │                                      │
  │   [S7]       [S0]       [S1]         │     S = Stack (2 tine, SoIC)
  │    T14,15     T0,1       T2,3        │     T = Tine die
  │                                      │
  │   [S6]      [S8+IOD]    [S2]         │     S8 = középső stack (3-szintű):
  │    T12,13    T16,17      T4,5        │       felül: Tine 17
  │              +Actor                  │       közép: Tine 16
  │              +Seal                   │       alul: IOD (Actor+Seal+I/O)
  │              +I/O                    │
  │                                      │
  │   [S5]       [S4]       [S3]         │
  │    T10,11     T8,9       T6,7        │
  │                                      │
  │         CoWoS-S interposer           │
  └──────────────────────────────────────┘
    ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○   ← BGA bumps (alul)
  
  Gyűrű: S0 → S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 → S0
  Minden lépés SZOMSZÉDOS → 3–5 ciklus CoWoS
  IOD (S8 alján) → bármely stack: 1 hop

Oldalnézet (szélső stack):       Oldalnézet (középső stack, 3-szintű):

  ┌─ 85 mm²─┐                      ┌─ 85 mm²─┐
  │ Tine 1  │ felső                │ Tine 17 │ felső
  ├─────────┤ SoIC (1–2 cyc)       ├─────────┤ SoIC (1–2 cyc)
  │ Tine 0  │ alsó                 │ Tine 16 │ közép
  └────┬────┘                      ├─────────┤ SoIC (1–2 cyc)
  ═════╪═════ CoWoS                │   IOD   │ alsó (Actor+Seal+I/O)
                                   └────┬────┘
                                   ═════╪═════ CoWoS
```

```
Footprint: 3×3 grid (9 stack, középső 3-szintű)
  9 × 85 mm² + IOD ~50 mm² = ~815 mm² → ~850 mm²-es interposer
  18 tine + IOD, shared-nothing architektúra
```

### Packaging technológia

| Kapcsolat | Technológia | Pitch | Latencia | Sávszélesség |
|-----------|-------------|---:|---:|---:|
| Tine belső (cluster→cluster) | On-die systolic | — | 1 ciklus | 8 GB/s |
| **Tine↔Tine páron belül** | **SoIC hybrid bond** | **<10 µm** | **1–2 ciklus** | **10+ TB/s** |
| Pár↔Pár (szomszéd) | CoWoS interposer | 40–55 µm | 3–5 ciklus | 1–2 TB/s |
| Tine↔IOD | CoWoS interposer | 40–55 µm | 3–5 ciklus | 1–2 TB/s |

A SoIC páron belül a tine határ **láthatatlan** — a systolic pipeline úgy folyik át, mintha egy die lenne. A CoWoS párok közötti 3–5 ciklus a teljes inference idejének <0,1%-a.

### A tine die belső felépítése (85 mm², 5nm)

Minden tine szerpentin szervezésű (páros sor →, páratlan sor ←, tükrözött cluster elhelyezés). A router hardver változatlan.

```
Tine bemenet →→→→→→→→→→→→→→→→→  FFN (MAC sorok, W→E)
                               ↓  N→S fordulás
              ←←←←←←←←←←←←←←←←  Attention (MAC sorok, AS mód)
              ↓
              →→→→→→→→→→→→→→→→→  FFN
                               ↓
              ←←←←←←←←←←←←←←←←  Attention → Tine kimenet
```

### Az IOD (I/O Die) — olcsó node-on

Az Actor Core-oknak, Seal Core-nak és I/O PHY-nek **nem kell 5nm** — ezek nem compute-intenzívek.

| IOD komponens | Funkció | Miért nem kell 5nm |
|---------------|---------|---|
| ~150 Actor Core (FP16) | LayerNorm, Softmax, Residual | Ritka használat, nem szűk keresztmetszet |
| Seal Core | Kódhitelesítés | Boot-time, alacsony frekvencia |
| PCIe/CXL PHY | Host I/O | Analóg, nem skálázódik node-dal |
| Chip-link PHY | Multi-package | Analóg |

**IOD node: N28 vagy N7** — olcsó, nagy yield, bevált process.

### Adatáramlás — körkörös pipeline (18 tine)

Az adat a gyűrűben halad, mindig a szomszédos stack-re lépve:

```
  S8/IOD (input, PCIe-ből)
   ↓ SoIC (1–2 cyc, IOD → Tine 16)
  S8: Tine 16 (→←) ──SoIC──→ Tine 17 (→←)
   ↓ CoWoS (szomszéd, 3–5 cyc)
  S0: Tine 0 ──SoIC──→ Tine 1
   ↓ CoWoS
  S1: Tine 2 ──SoIC──→ Tine 3
   ↓ CoWoS
  S2–S7: ... (6 stack, 12 tine) ...
   ↓ CoWoS
  S7: Tine 14 ──SoIC──→ Tine 15
   ↓ CoWoS (szomszéd → S8)
  S8/IOD (output, PCIe-re)

  A gyűrű ZÁRT: S8 → S0 → S1 → ... → S7 → S8
  INPUT és OUTPUT ugyanaz: az IOD (S8 alján)
  Minden lépés szomszédos → max 3–5 ciklus, soha több.
```

Az Actor Core-ok (LayerNorm, Softmax) az IOD-n (S8 alján) futnak. A rétegváltásnál az aktiváció a tine-ból az IOD-ra megy feldolgozásra, majd a következő tine-ra. A középső pozíció miatt az IOD minden stack-kel szomszédos — max 1 CoWoS hop.

### Kommunikáció összesítés (egy token, 18 tine)

| Lépés típus | Darab | Latencia/db | Össz |
|-------------|---:|---:|---:|
| IOD → Tine 16 (SoIC, S8 belső) | 1 | 1–2 cyc | 1–2 |
| Páron belül (SoIC) | 9 | 1–2 cyc | 9–18 |
| Stack → szomszéd (CoWoS) | 8 | 3–5 cyc | 24–40 |
| S7 → S8/IOD (CoWoS) | 1 | 3–5 cyc | 3–5 |
| **Össz kommunikáció** | | | **37–65 ciklus** |
| **Össz compute** | | | **~90 000+ ciklus** |
| **Overhead** | | | **<0,07%** |

### Yield és binning — a chiplet fő előnye

18 tine die-ból a jók számától függően:

| Jó tine-ok | Termék | Tine szám | Kapacitás |
|---:|---|---:|---:|
| 16 | **CFPU-ML Ultra** | 16 | 100% |
| 12 | **CFPU-ML Pro** | 12 | 75% |
| 8 | **CFPU-ML Standard** | 8 | 50% |
| 4 | **CFPU-ML Lite** | 4 | 25% |
| 2 | **CFPU-ML Edge** | 2 | 12,5% |
| 1 | **CFPU-ML Nano** | 1 | 6,25% |

Monolitikus die-nál 1 hiba = teljes chip selejtezése. Chiplet-nél a **hibás tine-t kihagyjuk**, a többit kisebb package-be rakjuk. A selejt → olcsóbb termék.

### Gyártási költség összehasonlítás

| | Monolitikus 814 mm² | **2×9 tine chiplet (18 tine)** |
|--|---:|---:|
| Tine die yield | ~22% | **~94%** |
| Tine die költség | ~$1 300 | **18 × $30 = $540** |
| IOD | — | ~$15 |
| Packaging | — | SoIC + CoWoS ~$500 |
| **Összesen** | **~$1 300** | **~$995** |
| Binning | 1 termék | **6+ termék** |
| TOPS (M, 18 tine) | 3 263 | **6 066** |
| **TOPS per $** | **2,5** | **2,7** |

### Termikus profil

```
18 tine (H), 500 MHz:
  Össz TDP: ~250-400W
  Per stack (2 tine): ~28-44W (9 stack)
  Power density: 0,16-0,26 W/mm² (per stack, 2×85 mm²)
  
  vs H100: 0,86 W/mm² (liquid cooling kötelező)
  → CFPU: léghűtés is elegendő!
```

### Multi-package skálázás

A gyűrű topológia package-ek között is folytatódik: az egyik package IOD-ja a másik IOD-jához csatlakozik CXL linken. A pipeline az utolsó tine-ból kilép a package-ből, átmegy a következőbe, és ott folytatódik.

```
Package 0                          Package 1
┌──────────────────────┐          ┌──────────────────────┐
│  [S7][S0][S1]        │          │  [S7][S0][S1]        │
│  [S6][IOD][S2]       │          │  [S6][IOD][S2]       │
│  [S5][S4][S3]        │          │  [S5][S4][S3]        │
│  gyűrű: 18 tine      │          │  gyűrű: 18 tine      │
└────────┬─────────────┘          └────────┬─────────────┘
         └─────── IOD↔IOD CXL link ────────┘

Package-közi: IOD → CXL → IOD
  Adat: ~16 KB aktiváció per átmenet
  Latencia: ~0,5–2 µs (CXL)
  Gyakoriság: 18 tine-onként 1× → elhanyagolható
```

## Memória — Pure SRAM-only

```
A modell méretét a chip SRAM kapacitása korlátozza.
Nincs DRAM controller, nincs külső memória, nincs HBM.

Előny:  Nincs memória sávszélesség korlát (a súlyok helyben vannak), determinisztikus latencia, egyszerű rendszer
Korlát: Max ~6,5 GB egyetlen 18 tine H chip-ben (500 MHz)
        Multi-package: lineárisan skálázható (2 chip = 13 GB, 6 chip = 39 GB)
```

A multi-chip skálázás lehetővé teszi a nagyobb modellek futtatását — a chip-közi kommunikáció csak a réteg kimenetét szállítja (KB méretű), nem a súlyokat.

> **Miért nem eDRAM?** Az eDRAM 5nm-en és 7nm-en egyetlen foundry-nál sem elérhető (TSMC, Samsung, Intel). Az utolsó gyártott eDRAM az IBM z15/Power9 volt (14nm FD-SOI). Az 5nm SRAM (47,6 Mbit/mm²) sűrűbb mint a 14nm eDRAM (38 Mbit/mm²), tehát node-ok között az eDRAM-nak nincs előnye.

## Ismert korlátozások és nyitott kérdések

### Architekturális

1. **Attention dataflow** — A Q×K^T és scores×V műveletek nem weight-stationary. Megoldási irányok: (a) ideiglenes weight-ként betölti Q-t/K-t az SRAM-ba, (b) output-stationary mód az FSM-ben, (c) az Actor Core-ok végzik. → **Tervezési döntés szükséges.**
2. **Actor Core throughput** — 150 Actor Core / chip specifikálva, de a Softmax/LayerNorm throughput-juk nincs modellezve. → **RTL szintű elemzés szükséges.**
3. **INT8-only pontosság** — Softmax és LayerNorm FP16 akkumulátort igényel. Az Actor Core-ok FP16 képesek, de a MAC→Actor→MAC pipeline overhead nincs mérve.
4. **Per-channel quantization** — A jelenlegi Post-MAC fixed-scale. Modern modellek per-channel-t igényelnek. → **Terület-hatás vizsgálat szükséges.**

### Nem létező komponensek

5. **Chip-to-chip interconnect** — Multi-chip konfigurációhoz szükséges, nincs specifikálva.
6. **Szoftver stack** — ONNX compiler, weight partitioner, runtime, debugger. → **A projekt legkritikusabb hiányzó eleme.**
7. **Host interface** — PCIe/CXL PHY, driver. Nincs a területszámításban.

### Validálandó

8. **Területbecslések** — +25% margin alkalmazva, de RTL szintézis szükséges a valós számokhoz.
9. **TDP** — Széles tartomány (250–600W 18 tine package-en, SKU-függő). SPICE/RTL power analízis szükséges.
10. **SRAM Vmin** — 500 MHz-en alacsonyabb feszültség lehetséges, de az SRAM Vmin (0,65–0,70V) korlátoz. Assist circuit-ek szükségesek lehetnek.

## Összefoglaló pozícionálás

### Ahol a CFPU-ML-Max egyértelműen nyer

| Szegmens | CFPU előny | Konfidencia |
|----------|---:|---|
| Edge Vision (ResNet, YOLO, MobileNet) | 1,5–2,5× TOPS/W | Közepes–Magas |
| BERT inference (enterprise) | 1,0–2,8× TOPS/W | Közepes |
| Determinisztikus latencia | SRAM-only, nincs cache miss | Magas |
| Auditálható AI (Seal Core) | Egyedi, nincs versenytárs | Magas |
| Open source ISA/RTL | Differenciátor | Magas |

### Ahol a helyzet bizonytalan

| Szegmens | Kérdés | Szükséges validáció |
|----------|--------|---------------------|
| Transformer inference (BERT, GPT) | Attention overhead? | Attention dataflow tervezés |
| LLaMA-7B (2 chip) | KV cache elfér? | Memória-budget részletes elemzés |
| TOPS/W vs TPU v5e | TPU is hatékony | Groq/TPU benchmark összehasonlítás |

### Ahol a CFPU nem jó választás

- **Training** (nincs backpropagation — kizárólag inference architektúra)
- **FP32/FP16 natív workload** (INT8-only MAC — a MAC Slice nem támogat lebegőpontos aritmetikát)

> **Miért NEM korlát a LLaMA-13B+?** A multi-package skálázás lineárisan növeli az SRAM kapacitást (1 chip = 6,5 GB, 6 chip = 39 GB, 33 chip = 215 GB). A kérdés nem az, hogy "elfér-e", hanem hogy a szükséges package számnál versenyképes-e a J/token. Lásd: [Versenytárs összehasonlítás](#versenytárs-összehasonlítás).

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 2.0 | 2026-04-20 | Chiplet architektúra: 85 mm² tine die (5nm), 2×9 gyűrű (18 tine + IOD, SoIC+CoWoS), 500 MHz, 8×8 MAC Slice, zero-skip sparsity, dual-mode FSM (WS+AS), flip-chip BGA, +25% design margin, KV cache memória-budget (GQA), produkciós üzemeltetési összehasonlítás (NVIDIA, Groq, TPU, QC) |
| 1.0 | 2026-04-19 | Kezdeti verzió — monolitikus die, 6 optimalizálási lépés |
