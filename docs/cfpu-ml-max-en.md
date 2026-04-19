# CFPU-ML-Max: ML/SNN Inference Accelerator

> Magyar verzió: [cfpu-ml-max-hu.md](cfpu-ml-max-hu.md)

> Version: 1.0

## Status

> ⚠️ This document is based on **arithmetic projections** — pre-synthesis, pre-RTL validation state. The numbers indicate design directions, not measured performance data. Validated figures require at minimum RTL-level power analysis and silicon measurement.

## Summary

CFPU-ML-Max is the ML/SNN inference-optimized variant of the Cognitive Fabric Processing Unit (CFPU) processor family. Starting from the standard Matrix Core architecture, it underwent six optimization steps — cell size reduction, systolic router, wider links, post-MAC pipeline, SRAM sweet spot reversal, clock optimization — that together achieve **90–95% sustained MAC utilization**. At the same die size and process node (5nm) as NVIDIA, CFPU-ML-Max delivers competitive sustained TOPS for small/medium inference models (MobileNet, ResNet, YOLOv8, BERT-Base) with 4–7x better TOPS/W efficiency, using exclusively on-chip SRAM with no DRAM controller.

## Optimization Steps

### 1. Cell Payload 128 → 64 Bytes

**What we did:** Reduced the interconnect cell payload from 128 bytes to 64 bytes.

**Why:** The Matrix Core MAC array works in 4×4 INT8 tiles — one tile is 32 bytes of input. The 128-byte cell was 2x oversized, requiring unnecessarily large buffers and routers.

**Impact:** 39% latency reduction, 24% smaller router area. The power-of-two cell size is preserved, alignment remains straightforward.

### 2. Systolic Router — Reducing Communication Paths

**What we did:** Replaced the Turbo router (5-port, XY routing, VOQ, iSLIP) with a 2-direction, unidirectional systolic router. Full XY routing, VOQ, and iSLIP removed.

**Why:** In ML inference, data flows in one direction — there is no need for general-purpose, arbitrary-direction routing. The systolic dataflow naturally fits the mesh topology.

**Impact:** ~5,000 GE router (0.001 mm²) — 81% smaller than Turbo. The freed wire budget became the basis for the next step.

### 3. Wider Links — Reallocating the Wire Budget

**What we did:** The Turbo router used ~340 wires per core (4 directions × 85). The Systolic reduced this to ~98. We reallocated the freed budget to widen the two main data paths: 42 → 128 bits per direction (W→E activation, N→S weight).

**Why:** The MAC consumes 32 bytes/cc (16 bytes activation + 16 bytes weight). A 128-bit link delivers 16 bytes/cc per direction, exactly matching the MAC's demand.

**Impact:** ~274 wires/core (less than Turbo's ~340), but 3× bandwidth (128 vs 42 bit/cc). MAC utilization rises from ~15% to ~90–95%.

### 4. Post-MAC Pipeline

**What we did:** Integrated three processing stages at the MAC output, in hardware:
- **ReLU** activation — 160 GE (single comparator)
- **Quantize** INT32→INT8 — 300 GE
- **Max-Pool 2×2** — 200 GE

**Why:** Raw MAC output is 64 bytes/tile (16 × INT32). The post-MAC pipeline reduces this to 4 bytes — **16x output traffic reduction**. This frees the output link bandwidth.

**Impact:** 660 GE total (~0.0001 mm²), effectively zero area cost. Network load drops dramatically.

### 5. SRAM Sweet Spot Reversal (32 → 8 KB)

**What we did:** Reduced the SRAM optimum from 32 KB to 8 KB.

**Why:** The Systolic Wide router's 128-bit links are sufficient to feed the MAC on their own — the weight cache advantage does not compensate for the lost cores. The 8 KB configuration delivers the best sustained TOPS because the smaller node size enables more cores.

**Impact:** +18% core count compared to the 32 KB variant.

### 6. Clock Optimization (1 GHz)

**What we did:** Raised the clock from 500 MHz to 1 GHz.

**Why:** TOPS scales linearly with clock, but power scales supra-linearly. 1 GHz is the best compromise between raw TOPS and TOPS/W efficiency — above this, the power/TOPS ratio degrades rapidly.

**Impact:** 2x TOPS increase over the 500 MHz variant, TOPS/W of ~4.3–4.7 sustained.

## Core Specification

| Parameter | Value |
|-----------|-------|
| **Process node** | 5nm |
| **Clock** | 1 GHz |
| **Node area** | 0.019 mm² |
| **MAC array** | 4×4 INT8 (16 MAC/core/cycle) |
| **Router** | Systolic Wide (~5,000 GE, 0.001 mm²) |
| **Post-MAC pipeline** | ReLU + Quantize + Max-Pool 2×2 (~660 GE) |
| **Router + Post-MAC total** | ~5,660 GE ≈ 0.001 mm² |
| **SRAM** | 8 KB |
| **Sustained MAC utilization** | 90–95% |
| **Links** | 128-bit W→E + 128-bit N→S + ~10 control uplink |
| **Wires/core** | ~274 |

## Die Variants

5nm, 1 GHz, 8 KB SRAM:

| Die | Cores | Peak TOPS | Sustained TOPS | SRAM | TDP | TOPS/W |
|-----|-------|-----------|----------------|------|-----|--------|
| 80 mm² | ~4,200 | 134 | ~121–128 | 34 MB | ~28 W | ~4.3–4.6 |
| 159 mm² | ~8,400 | 269 | ~242–256 | 67 MB | ~55 W | ~4.4–4.7 |
| 200 mm² | ~10,500 | 336 | ~302–319 | 84 MB | ~69 W | ~4.4–4.6 |
| 400 mm² | ~21,000 | 672 | ~605–638 | 168 MB | ~138 W | ~4.4–4.6 |
| 609 mm² | ~32,000 | 1,024 | ~922–973 | 256 MB | ~210 W | ~4.4–4.6 |
| 814 mm² | ~42,800 | 1,370 | ~1,233–1,301 | 342 MB | ~280 W | ~4.4–4.6 |

> TDP estimates are pre-synthesis — arithmetic projections. Validated power figures require at minimum RTL-level power analysis.

## Target Models

The on-chip SRAM size determines which ML models fit entirely on-chip (no DRAM controller):

| Model | Weight size | Minimum die | Notes |
|-------|-----------|-------------|-------|
| MobileNet v2 | 3.4 MB | 80 mm² (34 MB) | Fits easily, edge deployment |
| ResNet-50 | 25 MB | 200 mm² (84 MB) | Fits comfortably |
| YOLOv8-S | 22 MB | 200 mm² (84 MB) | Real-time object detection |
| EfficientNet-B4 | 75 MB | 400 mm² (168 MB) | Medium image classifier |
| BERT-Base | 110 MB | 814 mm² (342 MB) | NLP inference, large die |
| LLaMA-7B | 7 GB | — | Does not fit, requires DRAM |

> CFPU-ML-Max is **not an LLM accelerator**. It is optimized for small and medium inference models where the entire model fits in distributed on-chip SRAM.

## Competitive Comparison

Same die size, same process node (~5nm/4nm), dense INT8 (without sparsity):

### vs RTX 4060 (159 mm²)

| Metric | CFPU-ML-Max (projected) | NVIDIA RTX 4060 |
|--------|-------------|-----------------|
| Die | 159 mm² | 159 mm² |
| Peak TOPS (INT8) | 269 | ~175 |
| Sustained TOPS (INT8) | 242–256 | 70–122 |
| CFPU projected advantage (sustained) | — | **2.0–3.7x** |
| Projected TOPS/W advantage | — | **4–7x** |

### vs RTX 4090 (609 mm²)

| Metric | CFPU-ML-Max (projected) | NVIDIA RTX 4090 |
|--------|-------------|-----------------|
| Die | 609 mm² | 609 mm² |
| Peak TOPS (INT8) | 1,024 | ~660 |
| Sustained TOPS (INT8) | 922–973 | 264–462 |
| CFPU projected advantage (sustained) | — | **2.0–3.7x** |
| Projected TOPS/W advantage | — | **4–7x** |

### vs H100 (814 mm²)

| Metric | CFPU-ML-Max (projected) | NVIDIA H100 |
|--------|-------------|-------------|
| Die | 814 mm² | 814 mm² |
| Peak TOPS (INT8) | 1,370 | ~1,979 |
| Sustained TOPS (INT8) | 1,233–1,301 | 792–1,385 |
| CFPU projected range (sustained) | — | **0.9–1.6x** |
| Projected TOPS/W advantage | — | **2–4x** |

### Important Notes

1. **NVIDIA dense** — values without sparsity. NVIDIA advertises higher peaks with structured sparsity, but most workloads cannot exploit it.
2. **NVIDIA sustained = 40–70% of peak** — actual utilization is workload-dependent. The GPU die is ~30–35% ML hardware (for RTX 4060/4090), with the rest being rasterization, video, display engine, etc.
3. **CFPU sustained = 90–95% of peak** — the Systolic Wide router and post-MAC pipeline ensure near-complete MAC utilization.
4. **CFPU 100% ML die** — no rasterization hardware, no video decoder, no display engine. Every transistor is dedicated to ML inference.
5. **TDP estimates are pre-synthesis** — CFPU power figures are arithmetic projections; RTL-level power analysis is not yet available.
6. **CFPU is not an LLM accelerator** — due to the absence of a DRAM controller, only models that fit in on-chip SRAM can be executed.

### Why is NVIDIA Sustained Low?

Three main reasons:

1. **Die area sharing** — the RTX 4060/4090 die is ~30–35% ML (Tensor Cores). The rest is rasterization, RT cores, video, display. CFPU-ML-Max is 100% ML.
2. **GDDR memory bottleneck** — GPU Tensor Cores consume data faster than GDDR6X can deliver. CFPU works from local SRAM with no DRAM latency.
3. **Non-ML hardware consumes power** — GPU TDP includes rasterization, video decoder, display engine power.

## Positioning

### Where CFPU-ML-Max Excels

- **Small/medium inference models** (MobileNet, ResNet, YOLOv8, EfficientNet) — the entire model fits in on-chip SRAM, no DRAM latency
- **Deterministic latency** — SRAM-only, no DRAM refresh, no cache misses
- **Energy efficiency** — 4–7x TOPS/W advantage over NVIDIA at the same die size
- **Edge deployment** — the 80 mm² variant delivers 121–128 sustained TOPS at ~28 W
- **Security requirements** — Seal Core provides hardware-rooted code authentication for every loaded model
- **Open source** — full ISA, RTL (planned), toolchain — auditable, forkable

### Where It Is Not the Right Choice

- **LLM inference** (GPT, LLaMA-7B+) — does not fit in SRAM, no DRAM controller
- **Training** — no backpropagation hardware, no high-bandwidth memory
- **FP32/FP16 workloads** — the MAC array is INT8-optimized, FP32 compute is not efficient
- **Dynamic model scaling** — SRAM size is fixed, not expandable at runtime

## Related Documents

- [Core family](core-types-en.md) — specification of the five CFPU core types
- [Interconnect architecture](interconnect-en.md) — 4-level hierarchy, Systolic Wide router
- [Quench-RAM](quench-ram-en.md) — per-block immutability
- [Seal Core](sealcore-en.md) — hardware code authentication
- [ISA-CIL-T0](ISA-CIL-T0-en.md) — the Matrix Core ISA basis
- [Architecture](architecture-en.md) — the complete CFPU overview

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-19 | Initial version — 5 optimization steps, core specification, 6 die variants, target models, NVIDIA comparison (RTX 4060, 4090, H100), positioning |
