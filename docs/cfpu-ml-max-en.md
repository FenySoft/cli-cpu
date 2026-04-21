# CFPU-ML-Max v2.0 — ML Inference Accelerator (500 MHz, chiplet)

> Magyar verzió: [cfpu-ml-max-hu.md](cfpu-ml-max-hu.md)

> Version: 2.0-draft
> Date: 2026-04-20

## Status

> ⚠️ **Arithmetic projections** — pre-synthesis and pre-RTL state. Numbers include +25% logic design margin, ISSCC reference SRAM density (0.021 mm²/Mbit), and KV cache memory budget. Pure SRAM-only, chiplet architecture.

## Architecture Summary

- **MAC Slice:** 8×8 INT8 MAC, FSM-driven (no CIL-T0 CPU), zero-skip sparsity base, dual-mode (WS + AS)
- **Cluster:** 2×4 (8 cores, 8×8 MAC), shared 128-bit systolic router
- **Tine die:** ~85 mm² (5nm), single design — the building block of the product family
- **Package:** 2×9 tine (18 die SoIC+CoWoS, ~850 mm² footprint), flip-chip BGA
- **Packaging:** SoIC hybrid bond within pair (1–2 cycles, invisible), CoWoS interposer between pairs (3–5 cycles)
- **Clock:** 500 MHz (low voltage → better TOPS/W)
- **IOD:** Actor Cores (~150, FP16) + Seal Core + I/O PHY — on cheap node (N28/N7)
- **SKU family:** tine count (1–18) × SRAM size (8–256 KB/core)

## MAC Slice Specification

| Component | Area | Notes |
|-----------|---:|---|
| MAC 8×8 + zero-skip | 0.01050 mm² | +25% routing, +~500 GE sparsity |
| FSM (dual-mode: WS + AS) | 0.000375 mm² | Weight-stationary + Activation-stationary |
| Post-MAC | 0.000625 mm² | 2,500 GE (8 output lanes) |
| **Logic total** | **0.0135 mm²** | |

### Base Features (every MAC Slice)

- **Zero-skip sparsity:** If weight == 0, the MAC skips the multiplication (~500 GE, ~2% area). Both structured (2:4) and unstructured sparsity supported. Effective 1.5–2× speedup on typical models.
- **Dual-mode FSM:** Weight-stationary (for FFN layers) AND Activation-stationary (for Attention Q×K^T, scores×V). 1-bit mode register, MAC hardware unchanged.
- **Post-MAC pipeline** (2,500 GE): ReLU (~300), INT32→INT8 quantize (~1,200), 2×2 Max-Pool (~400), pipeline registers (~600).

> **Not included:** per-channel quantization parameters. Per-channel adds +3,000–5,000 GE.

## SRAM Density

TSMC 5nm 6T SRAM: **0.021 mm²/Mbit** (ISSCC reference, including periphery).

| SRAM/core | Area |
|---:|---:|
| 4 KB | 0.00067 mm² |
| 8 KB | 0.00134 mm² |
| 16 KB | 0.00269 mm² |
| 32 KB | 0.00538 mm² |
| 64 KB | 0.01075 mm² |
| 128 KB | 0.02150 mm² |
| 256 KB | 0.04200 mm² |

## SKU Family — from Cluster to Chip

2×4 Cluster: 8 × 8×8 MAC Slices, 128-bit systolic link, overhead 0.007 mm². The western edge 2 cores × 8 bytes = 16 bytes = 128 bits (exactly matching link capacity). All values at 500 MHz, with 2:4 sparsity.

### SKUs: cluster → tine (85 mm²) → chip (18 tine)

| SKU | SRAM/core | Core size | Cluster | Cores/tine | Peak/tine | SRAM/tine | Cores/chip | **Peak/chip** | **SRAM/chip** | **TDP/chip** | **TOPS/W** |
|-----|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **S** | 4 KB | 0.014 mm² | 0.120 mm² | 5,536 | 354 TOPS | 22 MB | 99,648 | **6,379 TOPS** | **390 MB** | **~500W** | **~13** |
| **M** | 8 KB | 0.015 mm² | 0.126 mm² | 5,264 | 337 TOPS | 41 MB | 94,752 | **6,066 TOPS** | **740 MB** | **~500W** | **~12** |
| **L** | 16 KB | 0.016 mm² | 0.137 mm² | 4,848 | 310 TOPS | 76 MB | 87,264 | **5,586 TOPS** | **1.3 GB** | **~480W** | **~12** |
| **H** | 256 KB | 0.056 mm² | 0.451 mm² | 1,472 | 94 TOPS | 368 MB | 26,496 | **1,696 TOPS** | **6.5 GB** | **~300W** | **~6** |

> **M**: compute-focused (Vision, BERT, batch serving). **H**: SRAM-focused (LLM model + KV cache). **S** and **L** are the extremes. The chip count (1–18 tines) is determined by binning from yield.

## Tine Die Usable Area

The tine die (85 mm², 5nm) contains **exclusively MAC Slice clusters and SRAM**. The Actor Cores, Seal Core, I/O PHY, and PLLs reside on the **IOD** (separate die, cheap node). Flip-chip BGA: no pad ring on the tine die.

| Element | Location | Area |
|---------|----------|---:|
| MAC Slice clusters + SRAM | Tine die (5nm) | ~83 mm² usable |
| ~~Actor Core, Seal, I/O, PLL~~ | ~~Tine die~~ | → **Moved to IOD** |
| SoIC bond pads | Tine die edge | ~2 mm² |
| **Usable per tine** | | **~83 mm²** |

| IOD element | Area | Node |
|-------------|---:|---|
| ~150 Actor Cores (FP16) | ~3.75 mm² | N28/N7 |
| Seal Core | ~0.12 mm² | N28/N7 |
| PCIe/CXL PHY | ~10 mm² | N28/N7 |
| PLL, clock distribution | ~2 mm² | N28/N7 |
| **IOD total** | **~50 mm²** | **Cheap node** |

## Performance Evaluation Methodology

### Impact of Three Base Features on Utilization

| Feature | Effect | Area cost |
|---------|--------|---:|
| **Zero-skip sparsity** | 1.5–2× effective speedup on sparse models | ~500 GE (~2%) |
| **Dual-mode FSM (WS+AS)** | Attention utilization 50→65–78% | ~1 bit register |
| **8×8 MAC (2×4 cluster)** | 64 MACs/core, 512 MACs/cluster | 128-bit link match |

### Utilization Levels

| Level | Vision | Transformer | Notes |
|-------|---:|---:|---|
| **Peak** | 100% | 100% | Theoretical max |
| **Realistic (without sparsity)** | 65–78% | 65–78% | AS mode for Attention too |
| **Realistic (with sparsity)** | 100–156%* | 100–156%* | Zero-skip: effective > 100% |

> *With sparsity, effective utilization can exceed 100% because skipping zero weights increases useful compute per cycle. Tables report effective TOPS (peak × utilization × sparsity_factor).

### Sparsity Factor by Model

| Model | Typical zero weights | Sparsity factor |
|-------|---:|---:|
| ResNet-50 | ~30% | 1.3× |
| BERT-Base | ~40% | 1.5× |
| LLaMA-7B (INT4, pruned) | ~50% (2:4) | 2.0× |
| LLaMA-70B (INT4, pruned) | ~50% (2:4) | 2.0× |
| Dense (unpruned) | 0% | 1.0× |

> 2:4 structured sparsity (50% zeros) is the industry-standard pruning method. Calculations assume 2:4 sparsity where indicated.

### Dual-Mode FSM — the Attention Fix

The Attention mechanism is inherently NOT weight-stationary:

```
FFN layer:   Input × W_FFN       → W stays in place ✅ (full weight-stationary benefit)
Attention:   Q × K^T             → both are activations ❌ (no WS benefit)
             softmax(scores) × V → also ❌
```

~40–50% of Transformer compute time is attention → the weight-stationary benefit applies only to the FFN portion (~50–60%). Blended utilization is therefore lower.

Vision models (ResNet, YOLO, MobileNet) have no attention mechanism → full WS benefit.

## Tine Die and Package Summary

The tine die is 85 mm² (5nm), ~83 mm² usable. The package contains 18 tines (2×9 ring + IOD). The main SKU performance figures come from the **[SKU family](#sku-family--from-cluster-to-chip)** section tables. Calculation: clusters/tine = 83 mm² / cluster_area, cores = clusters × cores/cluster, Peak TOPS = cores × MACs/core × 2 × 500 MHz / 1T, sparsity 2:4 effective.

## Model Coverage (chiplet, 18 tine package)

### Memory Budget (batch=1, 2K context)

| Model | Weights | KV cache | Act. | **Total** | M chip (740 MB) | H chip (6.5 GB) |
|-------|---:|---:|---:|---:|:---:|:---:|
| ResNet-50 | 25 MB | — | 10 MB | 35 MB | ✅ | ✅ |
| BERT-Large | 340 MB | 50 MB | 25 MB | 415 MB | ✅ | ✅ |
| GPT-2 | 500 MB | 75 MB | 20 MB | 595 MB | ✅ | ✅ |
| LLaMA-7B INT4 | 3.5 GB | 0.5 GB | 0.2 GB | 4.2 GB | ❌ | ✅ (1 chip) |
| LLaMA-13B INT4 | 6.5 GB | 1.0 GB | 0.3 GB | 7.8 GB | ❌ | ❌ (2 chips) |
| LLaMA-70B INT4 | 35 GB | 2.7 GB | 0.4 GB | 38 GB | ❌ | ❌ (6 chips) |
| LLaMA-405B INT4 | 203 GB | 8.5 GB | 0.8 GB | 212 GB | ❌ | ❌ (33 chips) |
| DeepSeek R1 (671B) | 700 GB | 5 GB | 1 GB | 706 GB | ❌ | ❌ (109 chips) |
| GPT-4o class (~1.8T) | 900 GB | 10 GB | 2 GB | 912 GB | ❌ | ❌ (141 chips) |

### Package Count per Model (H SKU, 6.5 GB/chip)

| Model | Memory | Packages | Total TDP | Total Peak TOPS |
|-------|---:|---:|---:|---:|
| LLaMA-7B INT4 | 4.2 GB | **1** | ~350W | 1,696 |
| LLaMA-13B INT4 | 7.8 GB | **2** | ~700W | 3,392 |
| LLaMA-70B INT4 | 38 GB | **6** | ~2,100W | 10,176 |
| LLaMA-405B INT4 | 212 GB | **33** | ~11,550W | 55,968 |
| DeepSeek R1 | 706 GB | **109** | ~38,150W | 184,864 |
| GPT-4o class | 912 GB | **141** | ~49,350W | 239,136 |

## Competitive Comparison

### Competitor Chip Reference Data

| Chip | Node | Die mm² | INT8 TOPS (dense) | Memory | Mem BW | TDP | Type |
|------|------|---:|---:|---|---:|---:|---|
| **CFPU H** | **5nm** | **18×85** | **1,696** | **6.5 GB SRAM** | **on-chip** | **~300W** | **SRAM-only chiplet** |
| NVIDIA H100 SXM | 4nm | 814 | 1,979 | 80 GB HBM3 | 3,350 GB/s | 700W | GPU + HBM |
| NVIDIA L4 | 4nm | 294 | 242 | 24 GB GDDR6 | 300 GB/s | 72W | GPU + GDDR |
| NVIDIA B200 | 4nm | 2×858 | 4,500 | 192 GB HBM3e | 8,000 GB/s | 1,000W | GPU + HBM |
| Groq LPU v1 | **14nm** | 725 | ~750 | 230 MB SRAM | 80 TB/s on-chip | ~300W | SRAM-only |
| Groq 5nm (hyp.) | 5nm | ~725 | ~2,000 | ~2.6 GB SRAM | on-chip | ~350W | SRAM-only (does not exist) |
| Google TPU v5e | ~7nm | ~350 | 393 | 16 GB HBM2e | 819 GB/s | ~160W | ASIC + HBM |
| QC Cloud AI 100 Pro | 7nm | n/a | 400 | 32 GB LPDDR4x | 136 GB/s | 75W | ASIC + LPDDR |
| QC Cloud AI 100 Ultra | 7nm | n/a | 870 | 128 GB LPDDR4x | 548 GB/s | 150W | ASIC + LPDDR |

### Methodology

- **Production deployment** — the comparison basis: how many chips are needed to achieve a given system throughput (tok/s) and what is the power consumption
- Memory requirement = model weights + **active KV cache** (not all registered users, only those currently generating)
- NVIDIA: TensorRT-LLM, continuous batching, TBP includes GPU + HBM power
- CFPU: realistic values (+25% design margin), SRAM-only, ~300W/chip (H)
- tok/sec values are **system throughput** (not per-user)

### KV Cache — the Reality

The KV cache is NOT persistent. It exists during a user request processing (~1–5 seconds), then is freed. With a user base of millions, the chance that the next request comes from the same user whose KV cache is still "warm": ~0.01%. Therefore **every request is new prefill + new KV cache → temporary, seconds**.

| Model | GQA KV heads | KV/user (500 tok, typical) | KV/user (2K tok) |
|-------|---:|---:|---:|
| LLaMA-70B | 8 | 80 MB | 320 MB |
| LLaMA-405B | 8 | 413 MB | 1.6 GB |
| DeepSeek R1 | 128 (MLA) | ~13 MB | ~50 MB |
| Claude class (~175B) | ~8 | 88 MB | 350 MB |


### Production Model Sizes (2025–2026)

| Model | Architecture | Total params | Active/token | Weights (FP8) | KV/user (500 tok) |
|-------|-------------|---:|---:|---:|---:|
| LLaMA-70B | Dense, GQA | 70B | 70B | 35 GB | 80 MB |
| LLaMA 4 Scout | MoE 16 exp, GQA | 109B | 17B | ~55 GB | ~25 MB |
| Claude class | Dense, GQA | ~175B | ~175B | ~88 GB | ~88 MB |
| DeepSeek R1 | MoE 2048, MLA | 671B | 37B | ~335 GB | ~13 MB |
| GPT-4o class | MoE ~16 exp | ~1.8T | ~280B | ~900 GB | ~200 MB |

### Deployment Scenarios — LLaMA-70B, 30 tok/s per user

At any given moment, the **concurrently generating** users matter, not the registered ones. Among those, generation lasts ~2 seconds → the KV cache is temporary.

| Scenario | Concurrent generation | Throughput | Weights + active KV | Compute required |
|----------|---:|---:|---:|---:|
| Small team | 10 | 300 tok/s | 35 + 0.8 = **36 GB** | 44 TOPS |
| Startup | 100 | 3,000 tok/s | 35 + 8 = **43 GB** | 435 TOPS |
| Enterprise | 1,000 | 30,000 tok/s | 35 + 80 = **115 GB** | 4,350 TOPS |
| Large enterprise | 10,000 | 300,000 tok/s | 35 + 800 = **835 GB** | 43,500 TOPS |

> Compute required = throughput × 145 GOPS/token (LLaMA-70B). The chip count is determined by the larger of memory OR compute.

### LLaMA-70B — 100 Concurrent Generation (Startup)

| | NVIDIA (8× H100 GPU) | CFPU H | Groq 5nm (hyp.) | TPU v5e |
|--|---:|---:|---:|---:|
| Memory needed | 43 GB | 43 GB | 43 GB | 43 GB |
| Chips (memory) | 1 node (640 GB) | 7 (45 GB) | 17 (44 GB) | 3 (48 GB) |
| Chips (compute, 3K tok/s) | 1 node | 4 (540 TOPS) | 2 (2,700 TOPS) | 8 (3,144 TOPS) |
| **Limiting factor** | **1 node** | **7 (memory)** | **17 (memory)** | **8 (compute)** |
| Total TDP | 5,600W | 2,100W | ~5,950W | ~1,280W |
| Throughput | ~3,000 tok/s | ~3,000 tok/s | ~3,000 tok/s | ~3,000 tok/s |
| **J/token** | **1.87** | **0.70** | **~1.98** | **~0.43** |
| Manufacturing cost | ~$13K (4×$3.3K) | **~$7.7K** | n/a | n/a |

### LLaMA-70B — 1,000 Concurrent Generation (Enterprise)

| | NVIDIA (80× H100 GPU) | CFPU H | Groq 5nm (hyp.) |
|--|---:|---:|---:|
| Memory needed | 115 GB | 115 GB | 115 GB |
| Chips (memory) | 2 nodes (1,280 GB) | 18 (117 GB) | 45 (117 GB) |
| Chips (compute, 30K tok/s) | 80× H100 GPU (10 servers) | 32 CFPU chips (4,350 TOPS) | 15 chips (20,250 TOPS) |
| **Limiting factor** | **10 nodes (compute)** | **32 (compute)** | **45 (memory)** |
| Total TDP | 56,000W | 9,600W | ~15,750W |
| Throughput | ~30,000 tok/s | ~30,000 tok/s | ~30,000 tok/s |
| **J/token** | **1.87** | **0.32** | **~0.53** |
| Manufacturing cost | ~$265K (80×$3.3K) | **~$35K** | n/a |

### LLaMA-70B — 10,000 Concurrent Generation (Large Enterprise)

| | NVIDIA (800× H100 GPU) | CFPU H |
|--|---:|---:|
| Memory needed | 835 GB | 835 GB |
| Chips (memory) | 11 nodes (1,408 GB) | 129 (839 GB) |
| Chips (compute, 300K tok/s) | 100 nodes (800 GPUs) | 321 (43,600 TOPS) |
| **Limiting factor** | **100 nodes (compute)** | **321 (compute)** |
| Total TDP | 560,000W | 96,300W |
| **J/token** | **1.87** | **0.32** |
| Manufacturing cost | ~$2.7M (800×$3.3K) | **~$353K** |

### Summary — All Scenarios

| Scenario | CFPU J/token | NVIDIA J/token | **CFPU advantage** | CFPU chip cost | NVIDIA cost |
|----------|---:|---:|---:|---:|---:|
| Batch=1 (latency) | 0.05 | 1.75 | **35×** | — | — |
| 100 users | 0.70 | 1.87 | **2.7×** | ~$7.7K | ~$13K |
| 1,000 users | 0.32 | 1.87 | **5.8×** | ~$35K | ~$265K |
| 10,000 users | 0.32 | 1.87 | **5.8×** | ~$353K | ~$2.7M |

```
CFPU wins in EVERY scenario:
  J/token:  2.7–35× better
  Chip cost: 31–68× cheaper

Why?
  1. KV cache with GQA is small (80 MB/user, not 2.7 GB) → few extra chips needed
  2. KV cache is temporary (~2 sec) → does not accumulate
  3. Compute is the real bottleneck on both sides → CFPU SRAM is not wasted
  4. NVIDIA manufacturing cost (~$3,300/GPU) vs CFPU (~$1,100/chip) → ~3× CAPEX difference
```

> ⚠️ CFPU values are arithmetic projections. NVIDIA: TensorRT-LLM benchmarks. Both sides use **manufacturing cost** (not selling price). NVIDIA H100 manufacturing cost is ~$3,300/GPU (die + HBM + CoWoS + test), CFPU ~$1,100/chip (18 tines + IOD + SoIC/CoWoS). Selling price on both sides would be higher (R&D, margin, software).

## Chiplet Layout — 2×9 Tine, Ring, SoIC+CoWoS

### Why Chiplet?

Monolithic large die yield is catastrophic at 5nm:

| Die size | Yield (5nm) | Notes |
|---:|---:|---|
| 85 mm² | ~94% | Tine die ← what we use |
| 200 mm² | ~80% | |
| 400 mm² | ~55% | |
| 814 mm² | ~22% | H100 — the last monolithic large die |

The CFPU designs a single 85 mm² tine die. The product family comes from **packaging** (how many tines are assembled together), not from die design.

### The Reference Package: 2×9 Tine, Ring Topology (~800 mm²)

9 stacks (2 tines per stack, SoIC) in a **3×3 ring** on the CoWoS interposer. The center stack is 3-level: 2 tines + IOD at bottom. Each stack communicates only with its neighbors — no remote hops. Total **18 tines**.

```
Top view (CoWoS interposer):

  ┌──────────────────────────────────────┐
  │                                      │
  │   [S7]       [S0]       [S1]         │     S = Stack (2 tines, SoIC)
  │    T14,15     T0,1       T2,3        │     T = Tine die
  │                                      │
  │   [S6]      [S8+IOD]    [S2]         │     S8 = center stack (3-level):
  │    T12,13    T16,17      T4,5        │       top: Tine 17
  │              +Actor                  │       mid: Tine 16
  │              +Seal                   │       bot: IOD (Actor+Seal+I/O)
  │              +I/O                    │
  │                                      │
  │   [S5]       [S4]       [S3]         │
  │    T10,11     T8,9       T6,7        │
  │                                      │
  │         CoWoS-S interposer           │
  └──────────────────────────────────────┘
    ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○   ← BGA bumps (bottom)
  
  Ring: S0 → S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 → S0
  Every step is ADJACENT → 3–5 cycles CoWoS
  IOD (bottom of S8) → any stack: 1 hop

Side view (edge stack):           Side view (center stack, 3-level):

  ┌─ 85 mm²─┐                      ┌─ 85 mm²─┐
  │ Tine 1  │ top                  │ Tine 17 │ top
  ├─────────┤ SoIC (1–2 cyc)       ├─────────┤ SoIC (1–2 cyc)
  │ Tine 0  │ bottom               │ Tine 16 │ mid
  └────┬────┘                      ├─────────┤ SoIC (1–2 cyc)
  ═════╪═════ CoWoS                │   IOD   │ bot (Actor+Seal+I/O)
                                   └────┬────┘
                                   ═════╪═════ CoWoS
```

```
Footprint: 3×3 grid (9 stacks, center is 3-level)
  9 × 85 mm² + IOD ~50 mm² = ~815 mm² → ~850 mm² interposer
  18 tines + IOD, shared-nothing architecture
```

### Packaging Technology

| Connection | Technology | Pitch | Latency | Bandwidth |
|------------|------------|---:|---:|---:|
| Tine internal (cluster→cluster) | On-die systolic | — | 1 cycle | 8 GB/s |
| **Tine↔Tine within pair** | **SoIC hybrid bond** | **<10 µm** | **1–2 cycles** | **10+ TB/s** |
| Pair↔Pair (neighbor) | CoWoS interposer | 40–55 µm | 3–5 cycles | 1–2 TB/s |
| Tine↔IOD | CoWoS interposer | 40–55 µm | 3–5 cycles | 1–2 TB/s |

Within a SoIC pair, the tine boundary is **invisible** — the systolic pipeline flows through as if it were a single die. The 3–5 cycles between CoWoS pairs represent <0.1% of total inference time.

### Tine Die Internal Structure (85 mm², 5nm)

Every tine uses serpentine organization (even rows →, odd rows ←, mirrored cluster placement). The router hardware is unchanged.

```
Tine input →→→→→→→→→→→→→→→→→  FFN (MAC rows, W→E)
                               ↓  N→S turn
              ←←←←←←←←←←←←←←←←  Attention (MAC rows, AS mode)
              ↓
              →→→→→→→→→→→→→→→→→  FFN
                               ↓
              ←←←←←←←←←←←←←←←←  Attention → Tine output
```

### The IOD (I/O Die) — on Cheap Node

The Actor Cores, Seal Core, and I/O PHY **do not need 5nm** — they are not compute-intensive.

| IOD component | Function | Why 5nm is not needed |
|---------------|----------|---|
| ~150 Actor Cores (FP16) | LayerNorm, Softmax, Residual | Infrequent use, not a bottleneck |
| Seal Core | Code authentication | Boot-time, low frequency |
| PCIe/CXL PHY | Host I/O | Analog, does not scale with node |
| Chip-link PHY | Multi-package | Analog |

**IOD node: N28 or N7** — cheap, high yield, proven process.

### Data Flow — Circular Pipeline (18 tines)

Data travels through the ring, always stepping to the adjacent stack:

```
  S8/IOD (input, from PCIe)
   ↓ SoIC (1–2 cyc, IOD → Tine 16)
  S8: Tine 16 (→←) ──SoIC──→ Tine 17 (→←)
   ↓ CoWoS (neighbor, 3–5 cyc)
  S0: Tine 0 ──SoIC──→ Tine 1
   ↓ CoWoS
  S1: Tine 2 ──SoIC──→ Tine 3
   ↓ CoWoS
  S2–S7: ... (6 stacks, 12 tines) ...
   ↓ CoWoS
  S7: Tine 14 ──SoIC──→ Tine 15
   ↓ CoWoS (neighbor → S8)
  S8/IOD (output, to PCIe)

  The ring is CLOSED: S8 → S0 → S1 → ... → S7 → S8
  INPUT and OUTPUT are the same: the IOD (bottom of S8)
  Every step is adjacent → max 3–5 cycles, never more.
```

The Actor Cores (LayerNorm, Softmax) run on the IOD (bottom of S8). At layer transitions, the activation goes from the tine to the IOD for processing, then to the next tine. Due to the center position, the IOD is adjacent to every stack — max 1 CoWoS hop.

### Communication Summary (one token, 18 tines)

| Step type | Count | Latency/each | Total |
|-----------|---:|---:|---:|
| IOD → Tine 16 (SoIC, S8 internal) | 1 | 1–2 cyc | 1–2 |
| Within pair (SoIC) | 9 | 1–2 cyc | 9–18 |
| Stack → neighbor (CoWoS) | 8 | 3–5 cyc | 24–40 |
| S7 → S8/IOD (CoWoS) | 1 | 3–5 cyc | 3–5 |
| **Total communication** | | | **37–65 cycles** |
| **Total compute** | | | **~90,000+ cycles** |
| **Overhead** | | | **<0.07%** |

### Yield and Binning — the Main Chiplet Advantage

From 18 tine dies, depending on how many are good:

| Good tines | Product | Tine count | Capacity |
|---:|---|---:|---:|
| 16 | **CFPU-ML Ultra** | 16 | 100% |
| 12 | **CFPU-ML Pro** | 12 | 75% |
| 8 | **CFPU-ML Standard** | 8 | 50% |
| 4 | **CFPU-ML Lite** | 4 | 25% |
| 2 | **CFPU-ML Edge** | 2 | 12.5% |
| 1 | **CFPU-ML Nano** | 1 | 6.25% |

With monolithic die, 1 defect = entire chip scrapped. With chiplets, the **defective tine is excluded**, the rest goes into a smaller package. Scrap → cheaper product.

### Manufacturing Cost Comparison

| | Monolithic 814 mm² | **2×9 tine chiplet (18 tines)** |
|--|---:|---:|
| Tine die yield | ~22% | **~94%** |
| Tine die cost | ~$1,300 | **18 × $30 = $540** |
| IOD | — | ~$15 |
| Packaging | — | SoIC + CoWoS ~$500 |
| **Total** | **~$1,300** | **~$995** |
| Binning | 1 product | **6+ products** |
| TOPS (M, 18 tines) | 3,263 | **6,066** |
| **TOPS per $** | **2.5** | **2.7** |

### Thermal Profile

```
18 tines (H), 500 MHz:
  Total TDP: ~250-400W
  Per stack (2 tines): ~28-44W (9 stacks)
  Power density: 0.16-0.26 W/mm² (per stack, 2×85 mm²)
  
  vs H100: 0.86 W/mm² (liquid cooling mandatory)
  → CFPU: air cooling is sufficient!
```

### Multi-Package Scaling

The ring topology continues across packages: one package's IOD connects to another's IOD via CXL link. The pipeline exits the last tine of one package, crosses to the next, and continues there.

```
Package 0                          Package 1
┌──────────────────────┐          ┌──────────────────────┐
│  [S7][S0][S1]        │          │  [S7][S0][S1]        │
│  [S6][IOD][S2]       │          │  [S6][IOD][S2]       │
│  [S5][S4][S3]        │          │  [S5][S4][S3]        │
│  ring: 18 tines      │          │  ring: 18 tines      │
└────────┬─────────────┘          └────────┬─────────────┘
         └─────── IOD↔IOD CXL link ────────┘

Inter-package: IOD → CXL → IOD
  Data: ~16 KB activation per transition
  Latency: ~0.5–2 µs (CXL)
  Frequency: once per 18 tines → negligible
```

## Memory — Pure SRAM-only

```
The model size is limited by the chip's SRAM capacity.
No DRAM controller, no external memory, no HBM.

Advantage: No memory bandwidth bottleneck (weights are local), deterministic latency, simple system
Limit:    Max ~6.5 GB in a single 18-tine H chip (500 MHz)
          Multi-package: linearly scalable (2 chips = 13 GB, 6 chips = 39 GB)
```

Multi-chip scaling enables running larger models — inter-chip communication only carries the layer output (KB-sized), not the weights.

> **Why not eDRAM?** eDRAM is not available at 5nm or 7nm from any foundry (TSMC, Samsung, Intel). The last manufactured eDRAM was IBM z15/Power9 (14nm FD-SOI). 5nm SRAM (47.6 Mbit/mm²) is denser than 14nm eDRAM (38 Mbit/mm²), so eDRAM has no advantage across nodes.

## Known Limitations and Open Questions

### Architectural

1. **Attention dataflow** — The Q×K^T and scores×V operations are not weight-stationary. Solution directions: (a) temporarily load Q/K into SRAM as weights, (b) output-stationary mode in the FSM, (c) Actor Cores handle it. → **Design decision required.**
2. **Actor Core throughput** — 150 Actor Cores per chip specified, but their Softmax/LayerNorm throughput is not modeled. → **RTL-level analysis required.**
3. **INT8-only precision** — Softmax and LayerNorm require FP16 accumulators. The Actor Cores are FP16-capable, but the MAC→Actor→MAC pipeline overhead is not measured.
4. **Per-channel quantization** — The current Post-MAC uses fixed-scale. Modern models require per-channel. → **Area impact analysis required.**

### Non-Existent Components

5. **Chip-to-chip interconnect** — Required for multi-chip configurations, not specified.
6. **Software stack** — ONNX compiler, weight partitioner, runtime, debugger. → **The project's most critical missing element.**
7. **Host interface** — PCIe/CXL PHY, driver. Not included in the area calculations.

### To Be Validated

8. **Area estimates** — +25% margin applied, but RTL synthesis is required for real numbers.
9. **TDP** — Wide range (250–600W on 18-tine package, SKU-dependent). SPICE/RTL power analysis required.
10. **SRAM Vmin** — Lower voltage is possible at 500 MHz, but SRAM Vmin (0.65–0.70V) limits. Assist circuits may be needed.

## Positioning Summary

### Where CFPU-ML-Max Clearly Wins

| Segment | CFPU advantage | Confidence |
|---------|---:|---|
| Edge Vision (ResNet, YOLO, MobileNet) | 1.5–2.5× TOPS/W | Medium–High |
| BERT inference (enterprise) | 1.0–2.8× TOPS/W | Medium |
| Deterministic latency | SRAM-only, no cache miss | High |
| Auditable AI (Seal Core) | Unique, no competitor | High |
| Open source ISA/RTL | Differentiator | High |

### Where the Situation Is Uncertain

| Segment | Question | Validation needed |
|---------|----------|-------------------|
| Transformer inference (BERT, GPT) | Attention overhead? | Attention dataflow design |
| LLaMA-7B (2 chips) | Does KV cache fit? | Detailed memory budget analysis |
| TOPS/W vs TPU v5e | TPU is also efficient | Groq/TPU benchmark comparison |

### Where CFPU Is Not a Good Choice

- **Training** (no backpropagation — inference-only architecture)
- **FP32/FP16 native workloads** (INT8-only MAC — the MAC Slice does not support floating-point arithmetic)

> **Why is LLaMA-13B+ NOT a limitation?** Multi-package scaling linearly increases SRAM capacity (1 chip = 6.5 GB, 6 chips = 39 GB, 33 chips = 215 GB). The question is not "does it fit" but whether the J/token is competitive at the required package count. See: [Competitive Comparison](#competitive-comparison).

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 2.0 | 2026-04-20 | Chiplet architecture: 85 mm² tine die (5nm), 2×9 ring (18 tines + IOD, SoIC+CoWoS), 500 MHz, 8×8 MAC Slice, zero-skip sparsity, dual-mode FSM (WS+AS), flip-chip BGA, +25% design margin, KV cache memory budget (GQA), production deployment comparison (NVIDIA, Groq, TPU, QC) |
| 1.0 | 2026-04-19 | Initial version — monolithic die, 6 optimization steps |
