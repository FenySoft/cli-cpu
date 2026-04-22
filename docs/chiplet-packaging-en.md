# CFPU Chiplet Packaging Architecture

> Magyar verzió: [chiplet-packaging-hu.md](chiplet-packaging-hu.md)

> Version: 1.0

This document specifies the Cognitive Fabric Processing Unit (CFPU) **chiplet packaging architecture**: chiplet types, multi-chiplet configurations, technology scaling, and the impact on Neuron OS.

## Design Principles

1. **Two chiplet types** — one central (C) and one compute (R) chiplet, from the same fabrication line
2. **Power-of-2 core counts** — 2ⁿ at every level (cluster, chiplet, package)
3. **Technology-independent scaling** — Neuron OS runs the same code on 4k and 32k cores
4. **Yield optimization** — chiplet size in the 90%+ yield range

## Chiplet Types

### R Chiplet (Compute)

The compute chiplet contains only cores and the mesh network. All I/O is accessed through the central chiplet.

| Component | Area (5nm) |
|-----------|------------|
| Rich Core node (core + SRAM + router + infra) | 2,048 × 0.071 mm² = 145.4 mm² |
| UCIe PHY (chiplet links) | ~10 mm² |
| ESD + I/O ring | ~10 mm² |
| PLL | ~0.5 mm² |
| **R chiplet total** | **~166 mm²** |
| Headroom (SRAM increase / debug) | ~34 mm² |
| **Yield (~0.09 defect/cm²)** | **~93%** |

> Node size from the [core-types-en.md](core-types-en.md) Rich Core specification: 0.012 mm² logic + 0.042 mm² SRAM (256 KB) + 0.006 mm² Turbo router + ~0.011 mm² L1–L3 infra = 0.071 mm².

**Not in the R chiplet:** Seal Core, DDR5 PHY, PCIe/CXL — all in the C chiplet.

### C Chiplet (Central)

The central chiplet is the chip's "I/O hub" — present in a single instance, all external interfaces are accessed through it.

| Component | Area (5nm) | Why here |
|-----------|------------|----------|
| Seal Core (1–2) | ~0.25 mm² | All code loading passes through it — reaches everything in 1 hop from center |
| DDR5 PHY (2 channels) | ~16 mm² | Needed once, not per chiplet |
| PCIe/CXL (host connection) | ~5 mm² | Single connection to host |
| UCIe (up to 8 links) | ~20 mm² | To all 8 R chiplets |
| DMA controller | ~2 mm² | DDR5 ↔ chiplet SRAM data movement |
| ESD + I/O ring | ~15 mm² | Physical protection |
| PLLs | ~0.5 mm² | Clocks |
| Rich Core (remaining area) | whatever fits | Compute capacity |
| **C chiplet total** | **~200 mm²** | |

## Multi-Chiplet Configurations

### Topology: Combined Mesh + Star

Chiplets are arranged in a 3×3 grid. Adjacent chiplets connect via mesh links; diagonal chiplets connect through the central C chiplet. This is a **combined mesh + star** topology:

```
  ┌───┐ ┌───┐ ┌───┐
  │ R │─│ R │─│ R │
  │   │ │   │ │   │
  └─┬─┘╲└─┬─┘╱└─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ C │─│ R │      C = central chiplet
  │   │ │   │ │   │      R = compute chiplet
  └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐╱┌─┴─┐╲┌─┴─┐
  │ R │─│ R │─│ R │
  │   │ │   │ │   │
  └───┘ └───┘ └───┘

  ─ │ = mesh links (between adjacent chiplets)
  ╲ ╱ = star links (C ↔ diagonal chiplets)
```

**Benefits:**
- **Max 2 hops** between any two chiplets (mesh + through C)
- Adjacent chiplets at **1 hop** (direct mesh link)
- If C fails, mesh links still function (degraded mode)

### Product Variants

| Product | Chiplet Configuration | Rich Cores | Chip SRAM (256 KB/core) |
|---------|-----------------------|------------|------------------------|
| **CFPU-R1** | 1C + 1R | 2,048 | 512 MB |
| **CFPU-R2** | 1C + 2R | 4,096 | 1 GB |
| **CFPU-R4** | 1C + 4R | 8,192 | 2 GB |
| **CFPU-R8** | 1C + 8R | 16,384 | 4 GB |

> Product variants are built from **the same two chiplet designs** — the combination creates the product family. Yield binning and chiplet testing (KGD — Known Good Die) ensure only good chiplets enter the package.

### Interposer and Package Size

| Configuration | Interposer Area | Package Type |
|---------------|-----------------|--------------|
| 1C + 1R | ~400 mm² | Small package |
| 1C + 2R | ~600 mm² | Medium |
| 1C + 4R | ~1,000 mm² | CoWoS |
| 1C + 8R | ~2,000 mm² | CoWoS-L |

## DDR5 and External Memory

Core SRAM (128–512 KB / core) is sufficient for actor code and local state. For large datasets (databases, ML inference input), the DDR5 in the C chiplet serves as backing store.

| DDR5 Configuration | Bandwidth | Capacity |
|--------------------|-----------|----------|
| 2 channels (default) | ~100 GB/s | 16–64 GB |
| 4 channels (optional) | ~200 GB/s | 32–128 GB |

### Usage Model

Cores do not see DDR5 directly — the shared-nothing principle is preserved. A **DMA actor** in the C chiplet manages DDR5 access and serves core requests via mailbox messages:

```
Core (R chiplet)                C chiplet
┌──────┐  mailbox request      ┌─────────┐        ┌──────┐
│ Core │──────────────────────►│ DMA     │◄──────►│ DDR5 │
│      │◄──────────────────────│ Actor   │        │      │
└──────┘  mailbox response     └─────────┘        └──────┘
```

## Links and Bandwidth

### On-Chip Links (CMesh 16:1)

Within each cluster, 16 cores share one router. Inter-router mesh links are **256 bits wide at 500 MHz**:

| Parameter | Value |
|-----------|-------|
| Link width | 256 bit |
| Clock | 500 MHz |
| Per-link bandwidth | 16 GB/s |
| Hop latency (128B cell max) | ~4 ns |

> The 500 MHz NoC clock is a power optimization: ~68% lower dynamic power compared to ~1 GHz (f × V² scaling), while the wider link compensates bandwidth.

### Chiplet Boundary (UCIe / CoWoS)

| Parameter | Value |
|-----------|-------|
| Bandwidth | 200–500 GB/s |
| Latency | ~2–5 ns |
| Distance | ~1–5 mm (on interposer) |

### Multi-Package (2D Torus)

Multiple CFPU packages in a system connect via **2D torus** topology:

```
     ┌──────┐     ┌──────┐     ┌──────┐
 ◄══►│ CFPU │◄═══►│ CFPU │◄═══►│ CFPU │◄══►  (wrap)
     └──┬───┘     └──┬───┘     └──┬───┘
        │             │             │
     ┌──┴───┐     ┌──┴───┐     ┌──┴───┐
 ◄══►│ CFPU │◄═══►│ CFPU │◄═══►│ CFPU │◄══►  (wrap)
     └──────┘     └──────┘     └──────┘

  4 links / package (±X, ±Y), edges wrap around
```

| Parameter | Value |
|-----------|-------|
| Bandwidth | 25–100 GB/s |
| Latency | ~50–100 ns |
| Medium | PCB trace / cable |

### Bandwidth Summary

| Level | Per Link | Latency |
|-------|----------|---------|
| On-chip (mesh, 256-bit, 500 MHz) | 16 GB/s | ~4 ns/hop |
| Chiplet boundary (UCIe) | 200–500 GB/s | ~2–5 ns |
| Inter-package (±X/±Y, PCB) | 25–100 GB/s | ~50–100 ns |

## Technology Scaling

### SRAM Wall

SRAM does not scale at the same rate as logic because the 6-transistor SRAM cell hits stability limits at smaller technology nodes:

| Node | Logic Density (vs 5nm) | SRAM Density (vs 5nm) |
|------|------------------------|----------------------|
| 5nm | 1× | 1× |
| 3nm | 1.7× | **1.1×** |
| 2nm (GAA) | 2.5× | **1.2×** |
| 1.4nm | 3.5× | **1.3×** |
| 1nm | 5× | **1.5×** (with 3D SRAM) |

### Chiplet Size Growth

Defect density decreases with each generation, enabling larger chiplets at 90%+ yield:

| Timeframe | Defect Density | 90%+ Yield Chiplet Size |
|-----------|---------------|------------------------|
| 2025 (5nm) | ~0.09 /cm² | ~200 mm² |
| 2028 (3nm mature) | ~0.06 /cm² | ~300 mm² |
| 2030+ (2nm mature) | ~0.04 /cm² | ~400 mm² |
| 2033+ | ~0.02 /cm² | ~600 mm² |

### 3D SRAM

When the SRAM layer is stacked above the logic (TSMC 3D SRAM, SoIC technology), core footprint shrinks because SRAM no longer occupies chiplet planar area:

```
  2D (today):                  3D SRAM (future):
  ┌──────┬──────┐             ┌──────────────┐ ← SRAM layer
  │ Core │ SRAM │             │    SRAM      │
  └──────┴──────┘             ├──────────────┤
                              │    Core      │ ← logic layer
                              └──────────────┘
```

### Combined Effect: Cores per Chiplet (Nano Core, 64 KB SRAM)

Combined impact of density improvement and chiplet size growth:

| Timeframe | Technology | Chiplet Size | Node Size | **Cores / Chiplet** |
|-----------|------------|-------------|-----------|---------------------|
| 2025 | 5nm, 2D | 200 mm² | 0.0255 mm² | **4,096** (2¹²) |
| 2028 | 3nm, 2D | 300 mm² | 0.0183 mm² | **8,192** (2¹³) |
| 2030 | 2nm, 3D SRAM | 400 mm² | 0.015 mm² | **16,384** (2¹⁴) |
| 2033+ | 1.4nm, 3D SRAM | 600 mm² | 0.012 mm² | **32,768** (2¹⁵) |

> Core count grows ~2× per generation, from the combined effect of both factors (density + chiplet size).

## Neuron OS Impact

### What Remains Fixed Across Generations

| Element | Value | Why Fixed |
|---------|-------|-----------|
| Cores / cluster (CMesh 16:1) | 16 | Router port count — HW decision |
| Mailbox message size | 32 bit | Part of CIL ISA |
| Cell size | max 80 bytes (16B header + 64B payload) | Network protocol |
| Chiplet types | C + R | Functional separation |

### What Changes

| Element | How It Grows |
|---------|-------------|
| Clusters / chiplet | ~2× per generation |
| SRAM / core | Grows (3D SRAM), but core count does not decrease |
| Chiplets / package | Depends on cooling technology |

### Scheduler Scaling

The Neuron OS scheduler has a single parameter: **how many clusters are in the chiplet**. The boot process:

1. Chiplet reports: "I have N clusters"
2. OS builds the scheduler tree
3. Same code runs on 4k and 32k cores

The power-of-2 steps (4k → 8k → 16k → 32k / chiplet) ensure the scheduler tree always remains balanced.

## Future Expansion Directions

### 3D Package (3×3×2)

If cooling technology permits, chiplets can be stacked in two layers via SoIC:

```
  Upper (z=1)              Lower (z=0)
  ┌───┐ ┌───┐ ┌───┐       ┌───┐ ┌───┐ ┌───┐
  │ R │─│ R │─│ R │       │ R │─│ R │─│ R │
  └─┬─┘ └─┬─┘ └─┬─┘       └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐       ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ R │─│ R │       │ R │─│ C │─│ R │
  └─┬─┘ └─┬─┘ └─┬─┘       └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐       ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ R │─│ R │       │ R │─│ R │─│ R │
  └───┘ └───┘ └───┘       └───┘ └───┘ └───┘

  17R + 1C = 18 chiplets, ~34,816 Rich Cores
```

> Upper layer cooling is critical — the Neuron OS scheduler must be layer-aware (reduce load on z=1 cores). The 3×3×3 configuration (27 chiplets) is currently impractical due to middle layer cooling issues.

## Related Documents

- [Core Types](core-types-en.md) — Nano/Actor/Rich/Seal specification, SRAM sizing
- [Interconnect](interconnect-en.md) — 4-level on-chip network, switching model, router variants
- [DDR5 Architecture](ddr5-architecture-hu.md) — DDR5 controller, capability grant, CAM ACL
- [CFPU-ML-Max](cfpu-ml-max-en.md) — ML inference chiplet architecture
- [Architecture](architecture-en.md) — full CFPU overview

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-23 | Initial version — C/R chiplet types, 1+1..8 product variants, combined mesh+star topology, 256-bit 500 MHz link, DDR5 in C chiplet, technology scaling (SRAM wall, 3D SRAM, chiplet size growth), Neuron OS scheduler impact |
