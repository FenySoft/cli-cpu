---
status: vision
---

# Use Case: 4K videó feldolgozás CFPU-n — core-igény becslés

> English version: [use-case-video-en.md](use-case-video-en.md)

> Version: 1.0

> **⚠️ Vízió-szintű becslés.** Az itt szereplő core-számok irodalmi adatokból (x265 referencia profilok, FFmpeg benchmark adatok, ISSCC dedikált videó encoder publikációk) extrapolált munkahipotézisek. A pontos értékek csak F4 RTL multi-core szimuláció és F6 első szilícium (Cognitive Fabric One) után validálhatók. A dokumentum célja a tervezési irányt és a workload-illesztést rögzíteni, nem a végleges paramétereket.

Ez a dokumentum a **4K videó feldolgozás** core-igényét becsüli a CFPU referencia konfigurációján (5nm chiplet, 10 240 core). A célközönség: alkalmazás-tervezők, akik el akarják helyezni a video pipeline-t a CFPU hierarchiájában (core / cluster / tile / régió).

## Mit jelent „4K videó feldolgozás"?

A „videó feldolgozás" gyűjtőfogalom — a konkrét compute-igény drámaian eltér aszerint, hogy mi a tényleges művelet:

| Művelet | Compute igény | Memória sávszélesség | Tipikus felhasználás |
|---|---|---|---|
| **Lossless cut** (vágás újrakódolás nélkül) | Alacsony | ~25–100 Mbps stream I/O | Timeline editor, klip készítés |
| **Decode + display** (lejátszás) | Közepes | ~50–100 MB/s | Media player, monitoring, preview |
| **Re-encode / transcode** (codec konverzió) | **Nagy** | ~373 MB/s YUV uncompressed | Broadcast, VOD pipeline, archiválás |
| **Color grading / NR / filters** | Közepes (pixel-parallel) | ~373 MB/s | Színkorrekció, post-production |
| **AI super-res / upscale** | Tensor (MAC Slice külön) | ~373 MB/s | 4K → 8K, denoise, frame interpoláció |

## Referencia adatok

### CFPU core teljesítmény (5nm @ 500 MHz, in-order, 1 issue/cycle)

| Core típus | MIPS / core | FP? | SRAM/core | Megjegyzés |
|---|---|---|---|---|
| **Nano** (CIL-T0, int32) | 500 | nincs | 4–64 KB | Egyszerű streamelés, I/O orchestrator |
| **Actor** (teljes CIL) | 500 | nincs | 64–256 KB | GC, objektumok, codec inner loop |
| **Rich** (Actor + FPU) | 500 | IEEE-754 | 128–512 KB | Color science, FP filters |

A reference chiplet konfigurációban (`core-types-hu.md` v2.4):
- ~87 900 Nano, ~46 700 Actor, ~21 000 Rich core / chiplet (alternatív SRAM-méretezés szerint változik)
- L0 cluster = 16 core (4×4 mesh)
- L1 tile = 8 cluster = 128 core
- L2 régió = 8 tile = 1024 core

### 4K videó paraméterek

```
Felbontás:        3840 × 2160 = 8,3 Mpixel/frame
Frame rate:       30 fps (250 Mpixel/sec) vagy 60 fps (500 Mpixel/sec)
YUV 4:2:0:        12,4 MB/frame uncompressed → 373 MB/s @ 30 fps, 746 MB/s @ 60 fps
H.265 CTU:        64×64 → ~2 025 CTU/frame → 60 750 CTU/sec @ 30 fps
H.265 bitráta:    25–100 Mbps tipikusan
```

A DDR5 sávszélesség (`ddr5-architecture-hu.md`): ~76 GB/s — a 4K@60 nyers YUV streamje (~750 MB/s) ennek **<1%-a**, vagyis a memória-busz **nem szűk keresztmetszet**.

## Konkrét becslések

### 1. Lossless cut — vágás újrakódolás nélkül

A leggyakoribb „4K videó vágás" feladat: timeline-on kijelölt szegmensek mentén a stream újra-multiplexelése **újrakódolás nélkül** (csak I-frame határokon).

| Komponens | Core típus | Mennyi | Indok |
|---|---|---|---|
| Stream parser (H.265 NAL unit) | Actor | 1–2 | CIL-alapú parser |
| I-frame detect + cut point | Actor | 1 | Bytes-alapú keresés |
| Demux (timeline → szegmensek) | Actor | 1 | Lineáris pipeline |
| Mux (szegmensek → output container) | Actor | 1 | Lineáris pipeline |
| File I/O orchestrator | Actor | 1 | DDR5 capability slotokkal |
| **Összesen** | | **~5–7 Actor core** | |

**Konfiguráció:** **1 L0 cluster** (16 core) bőven elég real-time 4K cuthoz.

### 2. Decode + display — real-time lejátszás

Komponens-szintű compute becslés H.265 dekódolásra:

| Komponens | Compute | Becslés (4K@60) |
|---|---|---|
| Motion compensation | ~50 GOPS | ~100 Actor core |
| Deblocking + SAO | ~20 GOPS | ~40 Actor core |
| IDCT + dequant | ~30 GOPS | ~60 Actor core |
| Bitstream parse (CABAC) | ~5 GOPS | ~10 Actor core |
| Color space conv (YUV→RGB) | ~10 GOPS | ~20 Actor core |
| **Összesen** | **~115 GOPS** | **~230 Actor core** |

**Konfiguráció:**
- 4K@30 fps: ~115 Actor core → **1 L1 tile** (128 core)
- 4K@60 fps: ~230 Actor core → **2 L1 tile** (256 core) vagy 1 nagyobb tile

### 3. Re-encode / transcode 4K H.265 — kemény eset

A motion estimation viszi a compute 70-80%-át, ami egyben a quality/speed trade-off domináns része.

| Komponens | Compute (medium preset) | Becslés (4K@30) |
|---|---|---|
| Motion estimation (hierarchical) | ~300–1000 GOPS | ~600–2000 Actor core |
| Mode decision + RDO | ~100 GOPS | ~200 Actor core |
| Transform (DCT) + quantize | ~50 GOPS | ~100 Actor core |
| Entropy encode (CABAC) | ~30 GOPS | ~60 Actor core |
| Loop filter (deblocking + SAO) | ~20 GOPS | ~40 Actor core |
| **Összesen** | **~500–1200 GOPS** | **~1 000–2 400 Actor core** |

**Konfiguráció:**
- 4K@30 transcode: **~1 L2 régió** (1024 core) elég medium preset-re
- 4K@30 ultra-high quality: **~2-3 L2 régió** (2048-3072 core)
- Egy referencia 5nm chiplet (10 240 core) **5–10× over-provisioned** real-time 4K transcode-hoz → **több párhuzamos stream** is megy egyszerre.

### 4. Color grading / NR / filters — pixel-parallel

```
4K@30 fps × 8,3 Mpixel × ~30 ops/pixel = ~7,5 GOPS
```

| Filter típus | Compute | Becslés |
|---|---|---|
| Egyszerű LUT-alapú color grading | ~7 GOPS | ~15 Actor (vagy 5–10 Rich, ha float pipeline) |
| Spatial NR (5×5 bilateral kernel) | ~15 GOPS | ~30 Actor core |
| Sharpening + edge detect | ~10 GOPS | ~20 Actor core |
| **Combined pipeline** (NR + grade + sharpen) | ~30 GOPS | **~60–80 Actor core** |

**Konfiguráció:**
- Egyszerű filter pipeline: **1 L0 cluster** (16 core)
- Komplex realtime grading + NR: **1/2 L1 tile** (~64 core)
- HDR tone-mapping (FP16/FP32): **5–10 Rich core** elég

### 5. AI super-res / denoise — külön kategória

A neurális háló-alapú videó feldolgozás (super-res, denoise, frame interpoláció) **nem programozható core-okon megy**, hanem a **CFPU-ML MAC Slice**-okon — FSM-vezérelt, tile-load alapelvárás (1024-bit busz).

→ Lásd külön: [`cfpu-ml-max-hu.md`](cfpu-ml-max-hu.md). Ez a dokumentum **kihagyja**, mivel nem core-szám-érzékeny.

## Összesítő tábla

| Workflow | Core igény | CFPU tier | Mennyi core (~) |
|---|---|---|---|
| **Lossless cut** (timeline editor) | ~10 Actor | **1 L0 cluster** | 16 |
| **Real-time decode 4K30** | ~115 Actor | **1 L1 tile** | 128 |
| **Real-time decode 4K60** | ~230 Actor | **2 L1 tile** | 256 |
| **Color grade + NR pipeline** | ~80 Actor + ~10 Rich | **1 L1 tile** | 128 |
| **Transcode 4K30 H.265→H.264** (medium) | ~1 000 Actor | **1 L2 régió** | 1024 |
| **Transcode 4K30 ultra-high quality** | ~2 000 Actor | **2 L2 régió** | 2048 |
| **N × párhuzamos 4K30 transcode** | N × 1 régió | **N régió** | N × 1024 |
| **Teljes 1 chiplet kapacitás** | — | **10 régió** | **10 240** (5–10× transcode 4K30) |

## Iparági összehasonlítás

| Megoldás | 4K@30 H.265 encode kapacitás | Megjegyzés |
|---|---|---|
| Intel i9-13900K (24 core) | ~realtime (low quality) | Szoftveres x265 medium preset |
| AMD Threadripper 7980X (64 core) | ~3-5× realtime | Szoftveres x265, magas core |
| NVIDIA RTX 4090 NVENC | 4× realtime 4K60 | Dedikált HW encoder ASIC (~5 mm² area) |
| Apple M3 Pro Media Engine | 8× realtime 4K30 | Dedikált HW (~8 mm² area) |
| **CFPU 1 régió (~1 024 Actor core)** | **~1× realtime 4K30** | Szoftveres pipeline (CIL-alapú, x86-szerű) |
| **CFPU teljes chiplet (10 240 core)** | **~10× realtime 4K30** vagy 1× realtime 4K120 | Általános-célú core-ok, ~10% chip area for video |
| **Hipotetikus CFPU + dedikált videó MAC Slice** | **20-50× realtime 4K30** | Roadmap-on kívüli, opció |

A CFPU **általános-célú** — a videó csak egy a sok workload közül, és a **same hardware** futtat compiler-t, adatbázist, simulation-t, stb. egy NVENC ASIC csak videót tud.

## Tervezési megjegyzések

### Mire nem kell Rich core a videóhoz?

A video codec **integer-only**: DCT, motion estimation, quantize, deblocking — mind int32 művelet. Az Actor core (FP nélkül) elegendő. **Rich core csak akkor kell**, ha:
- HDR tone-mapping float pipeline (BT.2020 → BT.709 színtér konverzió)
- Wide-gamut color science (ACES color management)
- Scientific simulation a feldolgozási láncban (pl. lens distortion correction matematikai modellel)

→ Tipikusan **5–10 Rich core** elegendő egy professzionális videó pipeline-hoz, a többi maradhat Actor.

### Mire nem alkalmas a Nano core?

A Nano core SRAM-ja kicsi (4–64 KB). Egy 4K H.265 CTU buffer (64×64 × 1.5 byte = 6 KB), két szomszéd CTU referencia (12 KB), motion vector context (~4 KB), quantization tables (~2 KB) → **~25 KB minimum** munkamemória CTU feldolgozáshoz. A Nano 4 KB-os változata kevés.

A Nano **megfelelő**:
- Stream byte-szintű feldolgozás (NAL unit parsing)
- I/O orchestrator (DDR5 capability slot kezelés, file read/write)
- Egyszerű parancs-fogadó aktor (timeline UI bus)

### Memória-modell illeszkedés

```
4K frame uncompressed YUV 4:2:0:    12,4 MB
Egy Actor core (256 KB SRAM):       0,256 MB → tile-alapú feldolgozás (32×32 vagy 64×64 CTU buffer)
Egy Rich core (512 KB SRAM):        0,512 MB → 2-3 CTU + referencia frame ablak
```

A **CTU-szintű parallelizmus** (egy core = egy 64×64 blokk) a természetes választás:
- 2025 CTU/frame × 30 fps = 60 750 CTU/sec
- 1 core feldolgoz ~500 CTU/sec medium preset-tel
- → ~120 core elegendő real-time encode-hoz **CTU-szintű parallelizmussal**

### DDR5 capability slot allokáció

A videó pipeline jellemzően 3-5 nagy memória-régiót használ:
- Bemeneti stream buffer (compressed)
- Decoded YUV frame buffer (working set)
- Reference frame queue (~3-5 frame ME-hez)
- Output stream buffer
- Temp / scratch (DCT, quantize)

→ Aktor-onként **3-5 DDR5 capability slot** elegendő (a 4 slot/aktor allokáció kényelmesen elég, lásd `ddr5-architecture-hu.md` v1.3).

## Kapcsolódó dokumentumok

- [`core-types-hu.md`](core-types-hu.md) — core típusok, mennyiség, terület
- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — TLP > ILP, in-order, no OoO
- [`internal-bus-hu.md`](internal-bus-hu.md) — core-belső busz, context move
- [`interconnect-hu.md`](interconnect-hu.md) — L0/L1/L2/L3 hierarchia, cella-formátum
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — DDR5 controller, capability slot
- [`cfpu-ml-max-hu.md`](cfpu-ml-max-hu.md) — ML inference (AI super-res, denoise)

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-28 | Kezdeti verzió — 4K videó workload kategóriák (cut/decode/transcode/filter/AI), core-szám becslések kategóriánként, iparági összehasonlítás (NVENC, Apple Media Engine), tervezési megjegyzések (FP-mentesség, CTU parallelizmus, DDR5 capability slot allokáció) |
