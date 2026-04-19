# CFPU Core Family

> Magyar verzió: [core-types-hu.md](core-types-hu.md)

> Version: 1.6

This document specifies the **five core types** of the Cognitive Fabric Processing Unit (CFPU): ISA differences, area impact, SRAM sizing, power domains, product family variants, and market positioning.

## Dual Specialization

The CFPU core family is **not a linear hierarchy** — it specializes in two distinct directions from the Nano base:

```
                Nano (CIL-T0)
               /             \
      Actor (+GC+Obj)    Matrix (+FPU+MAC+SFU)
         |
      Rich (+FPU)
```

**Left:** the general-purpose programming direction — objects, GC, exception handling, then FPU.
**Right:** the numeric computation direction — FPU, matrix multiply, transcendental functions, **without** GC and objects.

This dual specialization is the unique characteristic of the CFPU: no other processor family offers both directions on the same interconnect, with the same message format, parameterized from the same RTL.

## The Five Core Types

### Nano Core

| Property | Value |
|----------|-------|
| **ISA** | CIL-T0 — 48 opcodes, int32-only |
| **FPU** | None |
| **MAC+SFU** | None |
| **GC + Object model** | None |
| **Exception handling** | Trap only (TTrapException) |
| **Logic area (7nm)** | ~0.009 mm² |
| **SRAM range** | 4–64 KB |
| **Purpose** | Spike, sensor, simple actor, maximum core count |

The Nano Core is the smallest execution unit — it runs the 48 CIL-T0 opcodes implemented in the F1 simulator. Nothing is included that is not required for a simple integer actor to function. The minimal size enables maximum core count: on 800 mm² at 7nm, up to **~32,000 Nano Cores** fit with 4 KB SRAM (including Compact router and L1–L3 infrastructure overhead).

**When to choose Nano:**
- Spiking Neural Network spikes (1-bit events, simple LIF neuron)
- IoT sensor actors (temperature, pressure, vibration → int value → message)
- Large numbers of simple workers (sort, filter, count) in an actor pipeline

### Actor Core

| Property | Value |
|----------|-------|
| **ISA** | Full CIL — objects, arrays, strings, virtual dispatch, exception handling, generics |
| **FPU** | None |
| **MAC+SFU** | None |
| **GC + Object model** | **Present** — per-core GC assist, bump allocator, mark-sweep |
| **Exception handling** | Full (throw, catch, finally) |
| **Logic area (7nm)** | ~0.018 mm² |
| **SRAM range** | 64–256 KB |
| **Purpose** | General actor, stream processing, supervisor, edge computing |

The Actor Core is the "standard" CFPU core — full CIL support with object model, GC, exceptions, but **without FPU**. Most actor-based workloads do not require floating-point computation: message handling, state machines, routing, scheduling, text processing, protocol implementation are all integer-based.

**When to choose Actor:**
- Akka.NET-style actor cluster (supervisor hierarchy, message passing)
- Stream processing pipeline (map, filter, reduce)
- Supervisor and scheduler actors (also in ML/SNN systems — the manager coordinates, not computes)
- Edge computing gateway (protocol handling, routing, aggregation)
- Any task requiring full CIL but not FP

### Rich Core

| Property | Value |
|----------|-------|
| **ISA** | Full CIL + FPU opcodes |
| **FPU** | **Present** — IEEE-754 R4 (float) + R8 (double), power-gated |
| **MAC+SFU** | None |
| **GC + Object model** | **Present** |
| **Exception handling** | Full |
| **Logic area (7nm)** | ~0.022 mm² |
| **SRAM range** | 128–512 KB |
| **Purpose** | FP-intensive actors, scientific computation, full .NET compatibility |

The Rich Core is the Actor Core + **IEEE-754 FPU**. Most .NET applications using `float` or `double` types require a Rich Core. The FPU is **power-gated** — when the code does not use FP operations, the FPU sleeps and the Rich Core is equivalent in power consumption to the Actor Core.

**When to choose Rich:**
- Scientific computation (physics simulation, statistics, financial modeling)
- General .NET applications where `float`/`double` types appear
- ML/SNN coordinator (weight aggregation, normalization, learning rate — in FP, but not matrix multiply)
- Any task requiring full CIL + FP, but where the MAC array would be overkill

### Matrix Core

| Property | Value |
|----------|-------|
| **ISA** | CIL-T0 + FP opcodes (not full CIL!) |
| **FPU** | **Present** — IEEE-754 R4 + R8, power-gated |
| **MAC+SFU** | **Present** — 4×4 MAC array (16 multiply-accumulate / cycle) + SFU (sin/cos/exp/rsqrt), power-gated |
| **GC + Object model** | **None** — no GC, no objects, no exception handling |
| **Exception handling** | Trap only |
| **Logic area (7nm)** | ~0.019 mm² |
| **SRAM range** | 4–64 KB (sweet spot: **8 KB**) |
| **Purpose** | ML inference, SNN neuron model, DSP, matrix computation |

The Matrix Core is the **numeric specialization** of the Nano Core — the CIL-T0 ISA extended with FP opcodes and hardware MAC+SFU. **It contains no GC, object model, exception handling, virtual dispatch, strings, or generics** — these are not needed for numeric processing, and omitting them makes the core ~40% smaller than the Rich Core.

The Matrix Core receives data from the network in **streaming mode**: the MAC array processes matrices in 4×4 tiles, the network feeds it, and results flow out immediately. This is why **small SRAM is sufficient** — the full matrix does not need to be held locally.

**The optimal SRAM size is 8 KB:**

| SRAM | Core+SRAM | Node total | Core count (800 mm²) | TOPS (INT8, 500 MHz) | SRAM ratio |
|------|-----------|------------|----------------------|----------------------|------------|
| 4 KB | 0.024 mm² | 0.038 mm² | ~21,100 | 338 | 4% — tight, code barely fits |
| **8 KB** | **0.025 mm²** | **0.039 mm²** | **~20,500** | **328** | **7% — code + 2 KB local cache** |
| 16 KB | 0.027 mm² | 0.041 mm² | ~19,500 | 312 | 13% |
| 64 KB | 0.037 mm² | 0.051 mm² | ~15,700 | 251 | 38% |

> Node total = Core+SRAM + Turbo router (0.007 mm²) + L1–L3 infrastructure (0.007 mm²).

At 8 KB, code + stack + MAC buffer fit comfortably, ~2 KB local cache remains for streaming data, and core count is near maximum.

**When to choose Matrix:**
- ML inference (convolution, dense layer, batch normalization)
- SNN neuron models (Izhikevich, Hodgkin-Huxley, LIF — in FP, with MAC)
- DSP pipeline (FIR/IIR filter, FFT butterfly)
- Any task where computation is matrix multiply + transcendental functions and full CIL is not needed

#### Matrix Core: Sustained vs. Peak Throughput

> **Terminology:** *Peak throughput* is the theoretical maximum — MAC capacity × core count × clock, assuming every MAC unit is busy every cycle. Like a car's speedometer showing 250 km/h: the engine could do it, but the road, traffic, and fuel supply won't let you sustain it. *Sustained throughput* is the realistic, continuously maintainable rate, limited by data feeding speed — the actual 130 km/h you drive.

The 4×4 MAC array produces 16 multiply-accumulate operations per cycle, but the **network cannot feed it at full rate**. An L0 link delivers ~5.2 bytes/cycle (42-bit wormhole, 500 MHz), while the MAC consumes 32 bytes/cycle input (16 × 2 bytes INT8). This means the MAC is **~6× over-provisioned** relative to a single link — peak TOPS can never be sustained simultaneously across all cores.

Three architectural strategies mitigate this bottleneck:

**1. Weight Reuse via Larger SRAM**

In convolution and dense layers, the weight matrix is reused across many input tiles. If weights fit in local SRAM, only the input stream needs to traverse the network — cutting network demand by ~2×.

| SRAM | Node total | Core count | Peak TOPS | Est. MAC utilization | **Sustained TOPS** |
|------|------------|------------|-----------|---------------------|---------------------|
| 8 KB | 0.039 mm² | ~20,500 | 328 | ~15% | ~49 |
| 32 KB | 0.045 mm² | ~17,800 | 285 | ~40–50% | ~114–143 |
| 64 KB | 0.051 mm² | ~15,700 | 251 | ~60–70% | ~151–176 |

Larger SRAM reduces core count but **increases sustained TOPS** because more data is local. The 32 KB sweet spot may yield ~2.5× the sustained throughput of the 8 KB variant despite having fewer cores.

**With Systolic router variant (ML/SNN chip):**

The Systolic router's 128-bit links eliminate the network bottleneck: W→E 16 bytes/cc activation + N→S 16 bytes/cc weights = 32 bytes/cc, matching the MAC's 32 bytes/cc consumption. MAC utilization rises to ~85–95%, nearly independent of SRAM size:

| SRAM | Node total | Core count | Peak TOPS | MAC utilization (ws) | **Sustained TOPS** |
|------|------------|------------|-----------|---------------------|---------------------|
| 8 KB | 0.033 mm² | ~24,200 | 387 | ~85–95% | **~329–368** |
| 32 KB | 0.039 mm² | ~20,500 | 328 | ~90–95% | **~295–312** |
| 64 KB | 0.045 mm² | ~17,800 | 285 | ~90–95% | **~257–271** |

> The Systolic variant reverses the SRAM sweet spot: the 8 KB configuration delivers the **best sustained TOPS** (329–368), because the link bandwidth alone is sufficient to feed the MAC — the weight caching advantage of larger SRAM does not compensate for the lost cores.

**2. Post-MAC Processing (ReLU, Quantize, Pool)**

If the MAC output is post-processed locally before being sent to the network, output traffic decreases dramatically:

| Stage | Output size (per 4×4 tile) | Reduction |
|-------|---------------------------|-----------|
| Raw MAC output | 64 bytes (16 × INT32) | — |
| + ReLU activation | 64 bytes (zeros become compressible) | sparse |
| + Quantize to INT8 | 16 bytes | **4×** |
| + 2×2 Max-Pool | 4 bytes | **16×** |

ReLU in hardware is a single comparator — effectively zero area cost. Quantization and pooling require minimal additional logic. By reducing output traffic, the **bidirectional link bandwidth is freed for more input data**, improving MAC utilization.

**3. Systolic Chaining (Software-Defined, Zero Hardware Cost)**

The mesh topology naturally supports **core-to-core pipeline chains**:

```
Core₁ → Core₂ → Core₃ → Core₄
  W₁       W₂       W₃       W₄     (weights stationary in each core's SRAM)
  ↓        ↓        ↓        ↓
  A×W₁  → A×W₂  → A×W₃  → A×W₄    (input A flows through the chain)
```

Each core holds its own weight slab in SRAM. The input data flows from neighbor to neighbor — **1 hop, ~5.2 bytes/cycle, no network congestion**. This eliminates the network bottleneck entirely for pipelined workloads.

This requires **no hardware modification** — only scheduler software that organizes cores into chains, and CIL code following the "receive from neighbor → MAC → send to neighbor" pattern. The CFPU's message-passing architecture and mesh topology make this a natural fit.

**Systolic router variant:** The Systolic router (see [Interconnect — L0 Router Variants](interconnect-en.md)) uses 128-bit unidirectional links instead of the 42-bit mesh. This feeds the MAC array at full speed: 128 bit/cc = 16 bytes/cc, matching the MAC's 16 bytes/cc consumption in weight-stationary mode. The router is only ~5,000 GE (0.001 mm²) — 86% smaller than Turbo — because XY routing, VOQ, and iSLIP are not needed. With the Systolic variant, the 8 KB Matrix Core node shrinks to 0.033 mm² (vs 0.039 mm² with Turbo), enabling **~24,200 cores** (+18%).

**Combined Effect**

The three strategies are complementary:

| Strategy | Hardware cost | Effect |
|----------|--------------|--------|
| SRAM 8→32 KB | +0.006 mm²/core | Weight reuse, ~2.5× sustained TOPS |
| Post-MAC pipeline | ~0 (ReLU) to minimal (pool) | Output traffic 4–16× reduction |
| Systolic chaining | **None** (software only) | Input bottleneck elimination |

> Sustained TOPS estimates are arithmetic projections based on network bandwidth constraints. Validated figures require RTL-level simulation with representative workloads.

### Seal Core

| Property | Value |
|----------|-------|
| **ISA** | CIL-Seal (CIL-T0 subset + crypto extensions: SHA-256, WOTS+, Merkle path, eFuse management) — *opcode list: F5 specification* |
| **FPU** | Crypto HW (AES, ECC — not IEEE-754 FPU) |
| **MAC+SFU** | None |
| **GC + Object model** | None |
| **Logic area (7nm)** | ~0.2 mm² (including eFuse, TRNG) |
| **SRAM** | ~32 KB (key storage, hash buffer) |
| **Placement** | **Always at the geometric center of the chip**, co-located with the L3 crossbar |
| **Count** | **1 by default; 2–64 for redundancy and parallel verification on larger chips (F6+)** — see [Seal Core](sealcore-en.md) |
| **Power** | Power-gated, wake-on-demand (wakes on code load) |

The Seal Core is not a compute unit — it is the chip's **authentication gatekeeper**. All code (boot, hot code loading, actor migration) passes through the Seal Core for AuthCode verification. Co-located with the L3 crossbar at the center of the chip: the hub of the star topology, through which all cross-region traffic naturally passes.

**The Seal Core scales to ~30,000 cores** without saturation:
- Boot (8,192 cores): ~256 ms
- Runtime hot code loading: <0.1% utilization
- L3 crossbar: ~25% load at 8k cores

## Area Comparison

### Core Sizes (7nm)

| Core type | Logic | Optimal SRAM | **Core total** | Router variant | Router area | **Node total** | **Core count (800 mm²)** |
|-----------|-------|--------------|----------------|:--------------:|------------:|---------------:|-------------------------:|
| Nano | 0.009 mm² | 4 KB | 0.014 mm² | Compact | 0.004 mm² | 0.025 mm² | **~32,000** |
| Actor | 0.018 mm² | 64 KB | 0.036 mm² | Compact | 0.004 mm² | 0.047 mm² | **~17,000** |
| Matrix | 0.019 mm² | 8 KB | 0.025 mm² | Turbo | 0.007 mm² | 0.039 mm² | **~20,500** |
| Rich | 0.022 mm² | 256 KB | 0.083 mm² | Turbo | 0.007 mm² | 0.097 mm² | **~8,250** |
| Seal | 0.200 mm² | 32 KB | 0.210 mm² | — | — | 0.210 mm² | **1** (always) |

**Note:** Core counts include the recommended L0 router variant area plus per-core share of L1–L3 infrastructure (~0.007 mm²). See [`interconnect-en.md`](interconnect-en.md), L0 Router Variants for details.

**Note:** the Matrix Core logic (0.019 mm²) is close to the Actor (0.018 mm²), but due to the small SRAM (8 KB vs 64 KB) the Matrix Core is **smaller overall** (0.025 vs 0.036 mm²). SRAM dominates core size, not logic.

### Why is Matrix smaller than Rich if it has more hardware?

| Component | Rich Core | Matrix Core | Difference |
|-----------|-----------|-------------|------------|
| Base (decoder, pipeline, ALU, stack) | Actor base: 0.018 mm² | Nano base: 0.009 mm² | **Matrix -50%** |
| FPU | 0.004 mm² | 0.004 mm² | Identical |
| MAC (4×4) | — | +0.006 mm² | Matrix + |
| SFU | — | +0.003 mm² | Matrix + |
| **Logic total** | **0.022 mm²** | **0.019 mm²** | **Matrix -14%** |
| Optimal SRAM | 256 KB (0.057 mm²) | 8 KB (0.002 mm²) | **Matrix -96%** |
| **Core total** | **0.083 mm²** | **0.025 mm²** | **Matrix -70%** |

The Matrix Core is 70% smaller than Rich because:
1. Built on Nano base (not Actor base) → no GC, object model, exception handling
2. Small SRAM is sufficient (streaming MAC, no large local memory needed)

## Power Domains

| Unit | Power state | When sleeping? | Wake trigger |
|------|-------------|----------------|--------------|
| Any core | Per-core clock gating | Empty mailbox | Mailbox interrupt |
| Rich/Matrix FPU | Separate power domain | No FP operations | FP opcode detected |
| Matrix MAC array | Separate power domain | No matrix multiply | MAC opcode detected |
| Matrix SFU | Separate power domain | No transcendental fn | SFU opcode detected |
| Cluster (16 cores) | Per-cluster power gating | All 16 cores sleeping | Cell arriving for any core |
| Tile (L1 crossbar) | Per-tile power gating | All clusters sleeping | Cell arrival |
| Region (L2 crossbar) | Per-region power gating | All tiles sleeping | Cell arrival |
| L3 crossbar | Power-gated | No cross-region traffic | Cross-region cell |
| Seal Core | Power-gated | No code loading | Code-load request |

The Matrix Core has three **independent** power domains (FPU, MAC, SFU) — if only scalar FP is needed, MAC and SFU sleep; if only MAC is needed, SFU sleeps. This allows the Matrix Core to **adapt its power consumption to the workload**.

## CFPU Product Family

| Variant | Seal | Cores | Target market | Example (7nm, 800 mm²) |
|---------|------|-------|---------------|------------------------|
| **CFPU-N** | 1 Seal | Nano only | IoT, massive SNN spike network | 1S + ~32,000N (4 KB) |
| **CFPU-A** | 1 Seal | Actor only | Actor cluster, stream processing | 1S + ~17,000A (64 KB) |
| **CFPU-R** | 1 Seal | Rich only | Full .NET, FP-intensive | 1S + ~8,250R (256 KB) |
| **CFPU-ML** | 1 Seal | Matrix + Actor | ML/SNN optimized | 1S + ~19,500M + ~1,000A |
| **CFPU-H** | 1 Seal | Actor + Nano | Heterogeneous supervisor+worker | 1S + 2,000A + ~24,000N |
| **CFPU-X** | 1 Seal | Mixed (any combination) | Application-specific | Custom |

### CFPU-ML: the ML/SNN-optimized chip

The CFPU-ML is the most compelling variant from an ML/SNN perspective:

| Metric | Value |
|--------|-------|
| Matrix Cores | ~19,500 (8 KB SRAM, Turbo router) |
| Actor Cores | ~1,000 (64 KB, Compact router, supervisor/scheduler) |
| Parallel MAC units | 19,500 × 16 = **312,000** |
| INT8 peak throughput (500 MHz) | **~312 TOPS** ⁽¹⁾ |
| INT8 sustained throughput | **~49–176 TOPS** ⁽¹⁾ |
| Estimated TDP (10% active) | ~3-5 W ⁽²⁾ |
| On-chip SRAM | ~200 MB |

> ⁽¹⁾ Peak is theoretical: core count × MAC units × clock. Sustained range depends on SRAM size and optimization strategy (weight reuse, systolic chaining, post-MAC processing) — see [Matrix Core: Sustained vs. Peak Throughput](#matrix-core-sustained-vs-peak-throughput). No RTL simulation or silicon measurement exists yet.
>
> ⁽²⁾ Arithmetic estimate assuming 10% simultaneous core activity. Does not include router/interconnect power, SRAM leakage, I/O, or off-chip memory access. Actual TDP will be significantly higher — validated power figures require at minimum RTL-level power analysis.

## Design Differentiators

The CFPU-ML's architectural uniqueness lies not in raw throughput but in a combination of properties that no existing chip offers together:

| Property | Description |
|----------|-------------|
| Programmable neuron model | Each core runs arbitrary CIL code — not a fixed LIF/SNN topology |
| Hardware MAC | 16 INT8 MAC units per Matrix Core, fused into the execution pipeline |
| Event-driven (0W idle) | Cores wake only on mailbox message — no polling, no idle power |
| Native .NET | C# / F# compiled to CIL, executed natively — no driver stack, no CUDA |
| Open source | Full ISA, RTL (planned), toolchain, and OS — auditable, forkable |
| On-chip SRAM only | No DRAM controller — deterministic latency, but limited model size |

> **The CFPU-ML is not competing on TOPS/W benchmarks against production silicon.** Its value proposition is a fully programmable, open-source, event-driven neuromorphic platform. Performance comparisons will be published after RTL-level power simulation is available.

## Why CFPU-ML?

The CFPU-ML's value lies not in raw TOPS but in a **combination of architectural properties** that no existing chip offers together: programmable neuron model (arbitrary CIL), event-driven operation (0W idle), isolated cores without shared memory, open-source hardware (CERN-OHL-S), and native .NET CIL execution.

The CFPU-ML-Max variant — with Systolic Wide router, post-MAC pipeline, and 1 GHz clock — achieves **90–95% sustained MAC utilization** and delivers 2–3.7x better sustained TOPS than NVIDIA RTX 4060/4090 at the same die size (dense INT8, without sparsity).

For detailed competitive comparison, die variants, target models, and positioning, see: **[CFPU-ML-Max: ML/SNN Inference Accelerator](cfpu-ml-max-en.md)**.

## Related Documents

- [CFPU-ML-Max](cfpu-ml-max-en.md) — ML/SNN inference accelerator: optimization steps, die variants, NVIDIA comparison
- [Interconnect architecture](interconnect-en.md) — 4-level hierarchy, switching model, router structure
- [Quench-RAM](quench-ram-en.md) — per-block immutability, QRAM+network symbiosis
- [ISA-CIL-T0](ISA-CIL-T0-en.md) — the ISA basis of the Nano and Matrix Core
- [Architecture](architecture-en.md) — the complete CFPU overview

## Changelog

| Version | Date | Summary |
|---------|------------|----------------------------------------------|
| 1.6 | 2026-04-19 | "Why CFPU-ML?" section shortened, competitive comparison table and target use cases moved to dedicated [CFPU-ML-Max](cfpu-ml-max-en.md) document |
| 1.5 | 2026-04-19 | Systolic router variant added to Matrix Core section: 128-bit links, MAC ~100% utilization, sustained TOPS table (329–368 TOPS @ 8 KB), 8 KB sweet spot reversal |
| 1.4 | 2026-04-19 | Cell payload 128→64 bytes: router area reduction (Turbo 0.009→0.007 mm², Compact 0.005→0.004 mm²), infra 0.008→0.007 mm². Core counts, TOPS, and product family metrics recalculated |
| 1.3 | 2026-04-19 | Peak/sustained terminology explanation. "Why CFPU-ML?" value proposition section with competitive comparison table and target use cases |
| 1.2 | 2026-04-19 | Matrix Core sustained vs. peak throughput analysis: network bandwidth bottleneck, three optimization strategies (weight reuse via larger SRAM, post-MAC processing, systolic chaining). CFPU-ML metrics updated with sustained TOPS range |
| 1.1 | 2026-04-19 | Core counts corrected to include L0 router area (Turbo/Compact variants) and L1–L3 infrastructure overhead. CFPU-ML metrics updated. Matrix Core SRAM table includes node total |
| 1.0 | 2026-04-18 | Initial version — 5 core types, dual specialization, area comparison, SRAM sizing, power domains, product family, market positioning |
