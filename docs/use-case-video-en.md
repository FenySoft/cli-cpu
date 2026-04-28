# Use Case: 4K Video Processing on CFPU — Core Count Estimates

> Magyar verzió: [use-case-video-hu.md](use-case-video-hu.md)

> Version: 1.0

> **⚠️ Vision-level estimate.** The core counts presented here are working hypotheses extrapolated from documented sources (x265 reference profiles, FFmpeg benchmark data, ISSCC dedicated video encoder publications). Precise values can only be validated after F4 RTL multi-core simulation and F6 first silicon (Cognitive Fabric One). The document records design direction and workload fit, not final parameters.

This document estimates the **4K video processing** core requirements on the CFPU reference configuration (5nm chiplet, 10,240 cores). Audience: application designers placing the video pipeline within the CFPU hierarchy (core / cluster / tile / region).

## What does "4K video processing" mean?

"Video processing" is a broad term — actual compute requirement varies dramatically by operation:

| Operation | Compute load | Memory bandwidth | Typical use |
|---|---|---|---|
| **Lossless cut** (no re-encode) | Low | ~25–100 Mbps stream I/O | Timeline editor, clip extraction |
| **Decode + display** (playback) | Medium | ~50–100 MB/s | Media player, monitoring, preview |
| **Re-encode / transcode** (codec conversion) | **High** | ~373 MB/s YUV uncompressed | Broadcast, VOD pipeline, archiving |
| **Color grading / NR / filters** | Medium (pixel-parallel) | ~373 MB/s | Color correction, post-production |
| **AI super-res / upscale** | Tensor (separate MAC Slice) | ~373 MB/s | 4K → 8K, denoise, frame interpolation |

## Reference data

### CFPU core performance (5nm @ 500 MHz, in-order, 1 issue/cycle)

| Core type | MIPS / core | FP? | SRAM/core | Notes |
|---|---|---|---|---|
| **Nano** (CIL-T0, int32) | 500 | none | 4–64 KB | Simple streaming, I/O orchestrator |
| **Actor** (full CIL) | 500 | none | 64–256 KB | GC, objects, codec inner loop |
| **Rich** (Actor + FPU) | 500 | IEEE-754 | 128–512 KB | Color science, FP filters |

In the reference chiplet configuration (`core-types-en.md` v2.4):
- ~87,900 Nano, ~46,700 Actor, ~21,000 Rich cores / chiplet (varies by SRAM sizing)
- L0 cluster = 16 cores (4×4 mesh)
- L1 tile = 8 clusters = 128 cores
- L2 region = 8 tiles = 1,024 cores

### 4K video parameters

```
Resolution:       3840 × 2160 = 8.3 Mpixel/frame
Frame rate:       30 fps (250 Mpixel/sec) or 60 fps (500 Mpixel/sec)
YUV 4:2:0:        12.4 MB/frame uncompressed → 373 MB/s @ 30 fps, 746 MB/s @ 60 fps
H.265 CTU:        64×64 → ~2,025 CTU/frame → 60,750 CTU/sec @ 30 fps
H.265 bitrate:    25–100 Mbps typical
```

DDR5 bandwidth (`ddr5-architecture-hu.md`): ~76 GB/s — the 4K@60 raw YUV stream (~750 MB/s) is **<1%** of this, so memory bandwidth is **not the bottleneck**.

## Concrete estimates

### 1. Lossless cut — no re-encode

The most common "4K video cut" task: timeline-based segment selection and remuxing **without re-encoding** (only at I-frame boundaries).

| Component | Core type | Count | Reason |
|---|---|---|---|
| Stream parser (H.265 NAL unit) | Actor | 1–2 | CIL-based parser |
| I-frame detect + cut point | Actor | 1 | Byte-based search |
| Demux (timeline → segments) | Actor | 1 | Linear pipeline |
| Mux (segments → output container) | Actor | 1 | Linear pipeline |
| File I/O orchestrator | Actor | 1 | With DDR5 capability slots |
| **Total** | | **~5–7 Actor cores** | |

**Configuration:** **1 L0 cluster** (16 cores) is more than enough for real-time 4K cutting.

### 2. Decode + display — real-time playback

Component-level compute estimate for H.265 decoding:

| Component | Compute | Estimate (4K@60) |
|---|---|---|
| Motion compensation | ~50 GOPS | ~100 Actor cores |
| Deblocking + SAO | ~20 GOPS | ~40 Actor cores |
| IDCT + dequant | ~30 GOPS | ~60 Actor cores |
| Bitstream parse (CABAC) | ~5 GOPS | ~10 Actor cores |
| Color space conversion (YUV→RGB) | ~10 GOPS | ~20 Actor cores |
| **Total** | **~115 GOPS** | **~230 Actor cores** |

**Configuration:**
- 4K@30 fps: ~115 Actor cores → **1 L1 tile** (128 cores)
- 4K@60 fps: ~230 Actor cores → **2 L1 tiles** (256 cores) or 1 large tile

### 3. Re-encode / transcode 4K H.265 — the hard case

Motion estimation accounts for 70-80% of compute, and is the dominant quality/speed trade-off.

| Component | Compute (medium preset) | Estimate (4K@30) |
|---|---|---|
| Motion estimation (hierarchical) | ~300–1000 GOPS | ~600–2000 Actor cores |
| Mode decision + RDO | ~100 GOPS | ~200 Actor cores |
| Transform (DCT) + quantize | ~50 GOPS | ~100 Actor cores |
| Entropy encode (CABAC) | ~30 GOPS | ~60 Actor cores |
| Loop filter (deblocking + SAO) | ~20 GOPS | ~40 Actor cores |
| **Total** | **~500–1200 GOPS** | **~1,000–2,400 Actor cores** |

**Configuration:**
- 4K@30 transcode: **~1 L2 region** (1,024 cores) is enough for medium preset
- 4K@30 ultra-high quality: **~2-3 L2 regions** (2,048-3,072 cores)
- A reference 5nm chiplet (10,240 cores) is **5–10× over-provisioned** for real-time 4K transcoding → **multiple parallel streams** at once.

### 4. Color grading / NR / filters — pixel-parallel

```
4K@30 fps × 8.3 Mpixel × ~30 ops/pixel = ~7.5 GOPS
```

| Filter type | Compute | Estimate |
|---|---|---|
| Simple LUT-based color grading | ~7 GOPS | ~15 Actor (or 5–10 Rich for float pipeline) |
| Spatial NR (5×5 bilateral kernel) | ~15 GOPS | ~30 Actor cores |
| Sharpening + edge detect | ~10 GOPS | ~20 Actor cores |
| **Combined pipeline** (NR + grade + sharpen) | ~30 GOPS | **~60–80 Actor cores** |

**Configuration:**
- Simple filter pipeline: **1 L0 cluster** (16 cores)
- Complex realtime grading + NR: **1/2 L1 tile** (~64 cores)
- HDR tone-mapping (FP16/FP32): **5–10 Rich cores** sufficient

### 5. AI super-res / denoise — separate category

Neural-network-based video processing (super-res, denoise, frame interpolation) does **not run on programmable cores**, but on **CFPU-ML MAC Slices** — FSM-driven, tile-load baseline (1024-bit bus).

→ See: [`cfpu-ml-max-en.md`](cfpu-ml-max-en.md). This document **omits** it as it is not core-count-sensitive.

## Summary table

| Workflow | Core requirement | CFPU tier | Cores (~) |
|---|---|---|---|
| **Lossless cut** (timeline editor) | ~10 Actor | **1 L0 cluster** | 16 |
| **Real-time decode 4K30** | ~115 Actor | **1 L1 tile** | 128 |
| **Real-time decode 4K60** | ~230 Actor | **2 L1 tiles** | 256 |
| **Color grade + NR pipeline** | ~80 Actor + ~10 Rich | **1 L1 tile** | 128 |
| **Transcode 4K30 H.265→H.264** (medium) | ~1,000 Actor | **1 L2 region** | 1,024 |
| **Transcode 4K30 ultra-high quality** | ~2,000 Actor | **2 L2 regions** | 2,048 |
| **N parallel 4K30 transcodes** | N × 1 region | **N regions** | N × 1,024 |
| **Full 1 chiplet capacity** | — | **10 regions** | **10,240** (5–10× transcode 4K30) |

## Industry comparison

| Solution | 4K@30 H.265 encode capacity | Notes |
|---|---|---|
| Intel i9-13900K (24 cores) | ~realtime (low quality) | Software x265 medium preset |
| AMD Threadripper 7980X (64 cores) | ~3-5× realtime | Software x265, high core count |
| NVIDIA RTX 4090 NVENC | 4× realtime 4K60 | Dedicated HW encoder ASIC (~5 mm² area) |
| Apple M3 Pro Media Engine | 8× realtime 4K30 | Dedicated HW (~8 mm² area) |
| **CFPU 1 region (~1,024 Actor cores)** | **~1× realtime 4K30** | Software pipeline (CIL-based, x86-like) |
| **CFPU full chiplet (10,240 cores)** | **~10× realtime 4K30** or 1× realtime 4K120 | General-purpose cores, ~10% chip area for video |
| **Hypothetical CFPU + dedicated video MAC Slice** | **20-50× realtime 4K30** | Off-roadmap, option |

The CFPU is **general-purpose** — video is just one of many workloads, and the **same hardware** runs compilers, databases, simulations, etc. An NVENC ASIC can only do video.

## Design notes

### Why is Rich core not needed for video?

The video codec is **integer-only**: DCT, motion estimation, quantize, deblocking — all int32 operations. The Actor core (without FP) is sufficient. **Rich core is only needed when:**
- HDR tone-mapping float pipeline (BT.2020 → BT.709 color space conversion)
- Wide-gamut color science (ACES color management)
- Scientific simulation in the processing chain (e.g., lens distortion correction with mathematical models)

→ Typically **5–10 Rich cores** are sufficient for a professional video pipeline, the rest can stay Actor.

### Why is Nano core not suitable?

The Nano core's SRAM is small (4–64 KB). A 4K H.265 CTU buffer (64×64 × 1.5 byte = 6 KB), two neighboring CTU references (12 KB), motion vector context (~4 KB), quantization tables (~2 KB) → **~25 KB minimum** working memory for CTU processing. The 4 KB Nano variant is too small.

The Nano **is suitable for:**
- Stream byte-level processing (NAL unit parsing)
- I/O orchestrator (DDR5 capability slot management, file read/write)
- Simple command-receiving actor (timeline UI bus)

### Memory model fit

```
4K frame uncompressed YUV 4:2:0:     12.4 MB
One Actor core (256 KB SRAM):        0.256 MB → tile-based processing (32×32 or 64×64 CTU buffer)
One Rich core (512 KB SRAM):         0.512 MB → 2-3 CTUs + reference frame window
```

**CTU-level parallelism** (one core = one 64×64 block) is the natural choice:
- 2,025 CTU/frame × 30 fps = 60,750 CTU/sec
- 1 core processes ~500 CTU/sec at medium preset
- → ~120 cores sufficient for real-time encode with **CTU-level parallelism**

### DDR5 capability slot allocation

A video pipeline typically uses 3-5 large memory regions:
- Input stream buffer (compressed)
- Decoded YUV frame buffer (working set)
- Reference frame queue (~3-5 frames for ME)
- Output stream buffer
- Temp / scratch (DCT, quantize)

→ Per actor, **3-5 DDR5 capability slots** are sufficient (the 4 slots/actor allocation is comfortably enough, see `ddr5-architecture-hu.md` v1.3).

## Related documents

- [`core-types-en.md`](core-types-en.md) — core types, counts, area
- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — TLP > ILP, in-order, no OoO
- [`internal-bus-en.md`](internal-bus-en.md) — intra-core bus, context move
- [`interconnect-en.md`](interconnect-en.md) — L0/L1/L2/L3 hierarchy, cell format
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — DDR5 controller, capability slot
- [`cfpu-ml-max-en.md`](cfpu-ml-max-en.md) — ML inference (AI super-res, denoise)

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-28 | Initial version — 4K video workload categories (cut/decode/transcode/filter/AI), per-category core count estimates, industry comparison (NVENC, Apple Media Engine), design notes (FP-free, CTU parallelism, DDR5 capability slot allocation) |
