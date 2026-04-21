# CFPU Core Family

> Magyar verzió: [core-types-hu.md](core-types-hu.md)

> Version: 2.2

This document specifies the **four core types** of the Cognitive Fabric Processing Unit (CFPU): ISA differences, area impact, SRAM sizing, power domains, product family variants, and market positioning. The ML inference-optimized MAC Slice (non-programmable compute unit) specification can be found in the [CFPU-ML-Max](cfpu-ml-max-en.md) document.

## Dual Specialization

The CFPU core family is **not a linear hierarchy** — it specializes in two distinct directions from the Nano base:

```
                Nano (CIL-T0)
               /             \
      Actor (+GC+Obj)    Seal (+Crypto)
         |
      Rich (+FPU)
```

**Left:** the general-purpose programming direction — objects, GC, exception handling, then FPU.
**Right:** the security direction — cryptographic primitives (SHA-256, WOTS+, Merkle), code authentication, eFuse management.

This dual specialization is the unique characteristic of the CFPU: no other processor family offers both directions on the same interconnect, with the same message format, parameterized from the same RTL.

> For ML inference, the CFPU-ML chip uses **MAC Slices** — these are not programmable cores but FSM-driven compute units. Specification: [CFPU-ML-Max](cfpu-ml-max-en.md).

## The Four Core Types

| Property | **Nano** | **Actor** | **Rich** | **Seal** |
|----------|---------|----------|---------|---------|
| **ISA** | CIL-T0 (48 opcodes, int32) | Full CIL (obj, GC, generics) | Full CIL + FPU opcodes | CIL-Seal (CIL-T0 subset + crypto) |
| **FPU** | None | None | IEEE-754 R4+R8, power-gated | Crypto HW (AES, ECC) |
| **GC + Object model** | None | **Present** (bump alloc, mark-sweep) | **Present** | None |
| **Exception handling** | Trap only | Full (throw/catch/finally) | Full | Trap only |
| **Crypto** | None | None | None | **SHA-256, WOTS+, Merkle, eFuse, TRNG** |
| **Logic (5nm)** | 0.005 mm² | 0.010 mm² | 0.012 mm² | ~0.11 mm² |
| **SRAM range** | 4–64 KB | 64–256 KB | 128–512 KB | ~32 KB (key + hash) |
| **Power gating** | Per-core clock gating | Per-core clock gating | FPU separate domain | Wake-on-demand |
| **Count/chip** | 100–87,900 | 10–46,700 | 10–21,000 | 1+ (throughput, redundancy) |
| **Purpose** | Spike, sensor, simple worker | General actor, supervisor, ML coordinator | FP-intensive computation, .NET | Code authentication, boot, audit |

### Nano Core

The smallest execution unit — 48 CIL-T0 opcodes, integer-only. Minimal size → maximum core count.

**When:** SNN spikes, IoT sensor actors, large numbers of simple workers in a pipeline.

### Actor Core

The "standard" CFPU core — full CIL, GC, objects, exceptions, **without FPU**. In the CFPU-ML chip, the Actor Core handles non-MAC operations (LayerNorm, Softmax, Residual).

**When:** Actor cluster, stream processing, supervisor, edge gateway, ML coordinator.

### Rich Core

Actor Core + **IEEE-754 FPU** (power-gated). If the code does not use FP, the FPU sleeps.

**When:** Scientific computation, financial modeling, general .NET `float`/`double` applications.

### Seal Core

The chip's **authentication gatekeeper** — not a compute unit. All code (boot, hot loading, migration) passes through AuthCode verification. Located at the center of the L3 crossbar. In the CFPU-ML chip, it resides on the IOD.

**When:** Every CFPU chip. The count depends on throughput requirements and redundancy needs.

Scalability: at 10,240 cores, ~25% L3 crossbar utilization (boot: ~320 ms, runtime: <0.1%).

## Area Comparison

### Core Sizes (5nm)

| Core type | Logic | Optimal SRAM | **Core total** | Router variant | Router area | **Node total** | **Core count (18 tine)** | **Chip SRAM** |
|-----------|-------|--------------|----------------|:--------------:|------------:|---------------:|-------------------------:|---:|
| Nano | 0.005 mm² | 4 KB (0.0007 mm²) | 0.008 mm² | Compact | 0.003 mm² | 0.017 mm² | **~87,900** | ~344 MB |
| Actor | 0.010 mm² | 64 KB (0.011 mm²) | 0.023 mm² | Compact | 0.003 mm² | 0.032 mm² | **~46,700** | ~2.9 GB |
| Rich | 0.012 mm² | 256 KB (0.042 mm²) | 0.059 mm² | Turbo | 0.006 mm² | 0.071 mm² | **~21,000** | ~5.1 GB |
| Seal | 0.110 mm² | 32 KB | 0.120 mm² | — | — | 0.120 mm² | **1+** | — |

> Core counts are for the reference chiplet configuration: 18 tine dies (85 mm², ~83 mm² usable per tine, 1,494 mm² total). Area includes the recommended L0 router variant and the per-core share of L1–L3 infrastructure (~0.007 mm²). SRAM dominates core size, not logic. See: [CFPU-ML-Max chiplet layout](cfpu-ml-max-en.md#chiplet-layout--2×9-tine-ring-soiccoWoS).

### SRAM Scaling Impact on Core Count

With large SRAM, logic becomes negligible — core type sizes converge, and the choice becomes almost exclusively about ISA capabilities, not area.

| Core type | SRAM/core | SRAM area | **Node total** | **Core count (18 tine)** | **Chip SRAM** |
|-----------|---:|---:|---:|---:|---:|
| Nano | 512 KB | 0.084 mm² | 0.099 mm² | **~15,100** | ~7.5 GB |
| Actor | 512 KB | 0.084 mm² | 0.104 mm² | **~14,400** | ~7.2 GB |
| Rich | 512 KB | 0.084 mm² | 0.109 mm² | **~13,700** | ~6.7 GB |
| Nano | 1 MB | 0.168 mm² | 0.183 mm² | **~8,200** | ~8.0 GB |
| Actor | 1 MB | 0.168 mm² | 0.188 mm² | **~7,900** | ~7.7 GB |
| Rich | 1 MB | 0.168 mm² | 0.193 mm² | **~7,700** | ~7.5 GB |

> SRAM density: TSMC 5nm 6T SRAM, 0.021 mm²/Mbit (ISSCC reference). Node total includes logic, SRAM, router variant, and per-core share of L1–L3 infrastructure.

## Power Domains

| Unit | Power state | When sleeping? | Wake trigger |
|------|-------------|----------------|--------------|
| Any core | Per-core clock gating | Empty mailbox | Mailbox interrupt |
| Rich FPU | Separate power domain | No FP operations | FP opcode detected |
| Cluster (16 cores) | Per-cluster power gating | All 16 cores sleeping | Cell arriving for any core |
| Tile (L1 crossbar) | Per-tile power gating | All clusters sleeping | Cell arrival |
| Region (L2 crossbar) | Per-region power gating | All tiles sleeping | Cell arrival |
| L3 crossbar | Power-gated | No cross-region traffic | Cross-region cell |
| Seal Core | Power-gated | No code loading | Code-load request |

## CFPU Product Family

| Variant | Seal | Cores / units | Target market |
|---------|------|---------------|---------------|
| **CFPU-N** | Seal | Nano only | IoT, massive SNN spike network |
| **CFPU-A** | Seal | Actor only | Actor cluster, stream processing |
| **CFPU-R** | Seal | Rich only | Full .NET, FP-intensive |
| **CFPU-ML** | Seal | **MAC Slice + Actor** | ML inference — see [CFPU-ML-Max](cfpu-ml-max-en.md) |
| **CFPU-H** | Seal | Actor + Nano | Heterogeneous supervisor+worker | 1S + 3,700A + ~65,000N |
| **CFPU-X** | Seal | Mixed (any combination) | Application-specific | Custom |

### CFPU-ML: the ML/SNN-optimized chip

The CFPU-ML is the most compelling variant from an ML/SNN perspective:

The CFPU-ML chip consists not of programmable cores but of **MAC Slices** (FSM-driven compute units) + Actor Cores + Seal Core. Detailed specification: **[CFPU-ML-Max](cfpu-ml-max-en.md)**.

## Design Differentiators

| Property | Description |
|----------|-------------|
| Event-driven (0W idle) | Cores wake only on mailbox message — no polling, no idle power |
| .NET native | C# / F# compiled to CIL, executed natively — no driver stack, no CUDA |
| Open source | Full ISA, RTL (planned), toolchain, and OS — auditable, forkable |
| Seal Core | Hardware code authentication — auditable ML inference (medical, financial) |
| On-chip SRAM only | No DRAM controller — deterministic latency |

## Related Documents

- [CFPU-ML-Max](cfpu-ml-max-en.md) — ML inference accelerator: chiplet architecture, MAC Slice, J/token comparison
- [Interconnect architecture](interconnect-en.md) — 4-level hierarchy, switching model, router structure
- [Quench-RAM](quench-ram-en.md) — per-block immutability, QRAM+network symbiosis
- [ISA-CIL-T0](ISA-CIL-T0-en.md) — the ISA basis of the Nano Core
- [Architecture](architecture-en.md) — the complete CFPU overview

## Changelog

| Version | Date | Summary |
|---------|------------|----------------------------------------------|
| 2.2 | 2026-04-21 | Core counts recalculated from monolithic 800 mm² to reference chiplet configuration (18 tines × 83 mm² = 1,494 mm²). SRAM scaling section: 512 KB and 1 MB per core variants with core counts and chip SRAM |
| 2.1 | 2026-04-21 | Reference node changed from 7nm to 5nm. All logic areas, core counts, and router areas recalculated using TSMC 5nm parameters (0.021 µm²/bit SRAM, ~171 MTr/mm² logic density) |
| 2.0 | 2026-04-20 | 4 core types (Matrix Core → MAC Slice, moved to separate document: [CFPU-ML-Max](cfpu-ml-max-hu.md)). Dual specialization: Nano→Actor→Rich (programming) + Nano→Seal (security). Product family updated. |
| 1.0 | 2026-04-18 | Initial version — 5 core types, dual specialization, area comparison, SRAM sizing, power domains, product family, market positioning |
