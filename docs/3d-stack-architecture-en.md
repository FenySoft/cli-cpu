---
status: vision
---

# CFPU 3D Stack Architecture — Memory Integration and Layering

> Magyar verzió: [3d-stack-architecture-hu.md](3d-stack-architecture-hu.md)

> Version: 1.1

> **⚠️ Vision-level positioning document.** The CFPU-side layering is a vision-level plan; the exact parameters (layer count, TSV density, per-tile SRAM size, memory-mesh granularity) are fixed in the detailed design (RTL/implementation) phases. The real-chip data (AMD MI300, Intel Ponte Vecchio, CEA-Leti IntAct, Cerebras WSE, Tenstorrent) come from public sources — see the [External sources](#external-sources-real-chips) section.

This document specifies the CFPU **3D vertical stacking vision** for large (tens of thousands of cores) meshes: how memory can be attached at **maximum speed** to a many-core 2D mesh, what the layered stack looks like (compute mesh / per-tile SRAM / memory mesh / edge DRAM), why **two separate physical NoC planes**, what the thermal orientation is, and **where the CFPU novelty begins** relative to real silicon.

This document is the **vertical (3D) complement** to [`chiplet-packaging-en.md`](chiplet-packaging-en.md): the latter covers the 2.5D **horizontal** chiplet layout (C/R chiplet, interposer, CoWoS), this one the **vertical** memory/mesh stack. In reality the two together form a "3.5D" package (see MI300).

## The problem: the flat 2D mesh memory wall at large N

In a √N × √N 2D mesh the **bisection bandwidth ∝ √N**, while the core count is **N** — so the cross-chip per-core bandwidth is **∝ 1/√N** (see [`topology-scaling-en.md`](topology-scaling-en.md)). If memory sits **only on the 4 edges**, the interior links **choke** toward the edges before the memory chip itself saturates.

Concretely for **256×256 = 65,536 cores**:

| Metric | Value |
|--------|-------|
| Perimeter nodes (potential memory taps) | 4·256 − 4 = **1,020** |
| Cores per tap | 65,536 / 1,020 ≈ **64** |
| Average distance to nearest edge | tens of hops; ~**128 hops** at the center |
| Bisection (center cut) | **256 links** → per-core cross-chip share ≈ **1/256** |

> The **256 links** is the number of (unidirectional) physical links crossing the center cut (√N); [`topology-scaling-en.md`](topology-scaling-en.md) expresses the same as **bidirectional bandwidth** (2√N·B). The scaling (∝ 1/√N) is identical in both conventions; only the constant factor differs by 2×.

**The killer relation:** core count grows **quadratically** (N), the center throughput only **linearly** (√N) — so **more cores = less per-core** cross-chip bandwidth. Putting memory on the 4 edges does **not** solve this; the bottleneck is not the edge but the **interior mesh links**. The solution is not in the plane.

## Decision trail: how to attach memory to the mesh

| Alternative | Essence | Verdict |
|-------------|---------|---------|
| **A** — Memory only on the 4 edges (2D) | all 4 edges used, interleaved address space | 4× edge BW, but the interior funnel + the 1/√N wall remain → **insufficient** on its own at large N |
| **B** — Diamond / interior taps (2D, Abts 2009) | memory insertion points scattered into the fabric interior too | the **2D optimum** (balanced hops + link load), but **still hits the plane** |
| **C** — 3D-stacked DRAM (HBM-on-logic) | DRAM stacked directly above/below the compute | high capacity, but **process mismatch** (DRAM ≠ logic), slower, and putting **thermally sensitive DRAM next to the hot compute** is bad → **rejected as primary** |
| **D — CHOSEN** — 3D-stacked SRAM + separate memory-mesh plane | per-tile SRAM stacked with the compute; the cold DRAM on the edges of a separate memory mesh | see below |

**Reasons for choosing D:**

1. **Same fabrication process.** SRAM is built in the same logic CMOS process as the cores → stacking is **easy** (hybrid bond), unlike DRAM's process mismatch. This is not theory: **AMD 3D V-Cache** does exactly this in volume production.
2. **Speed + bandwidth over capacity.** SRAM is a few cycles away with enormous vertical bandwidth — exactly what the working set needs; the capacity demand is covered by the cold DRAM tier.
3. **SRAM area moves out of the logic.** On a flat die every KB of scratchpad **steals compute area**; in 3D the SRAM goes to a separate die → **more cores/die + better yield** on the logic, and the SRAM on an SRAM-optimized node. (SRAM has stopped shrinking on new nodes anyway — see [`chiplet-packaging-en.md`](chiplet-packaging-en.md) "SRAM wall".)
4. **Memory leaves the mesh.** The per-tile SRAM is reachable vertically with **0 mesh hops** → memory traffic **does not load** the core mesh, and the 1/√N wall above **disappears** from the hot path.

## The chosen architecture: the layered stack

```
   [ heatsink ]
   ┌────────────────────────────────────────────┐
   │ CORE mesh (2D mesh #1 — actor messages)      │ ← TOP (thermal decision)
   ├────────────────────────────────────────────┤
   │ per-tile 3D SRAM (PRIVATE scratchpad, 0-hop) │
   ├────────────────────────────────────────────┤
   │ MEMORY mesh (2D mesh #2)                      │      ┌─ DRAM/HBM
   │   active interposer + memory controllers      │◄────►│  (at the mesh EDGES)
   ├────────────────────────────────────────────┤
   │ interposer + substrate                       │
   └────────────────────────────────────────────┘
```

| Layer | Role |
|-------|------|
| **Core mesh** (top) | the Cognitive Fabric messaging network: many small, independent cores, actor message passing (shared-nothing) |
| **per-tile 3D SRAM** | private scratchpad below/above each core, vertical TSV, ~1–2 cycles, **0 mesh hops** |
| **Memory mesh** (bottom) | dedicated, bandwidth-tuned network for the SRAM↔DRAM (cold) traffic; also an **active interposer** (routing + memory controllers) |
| **DRAM/HBM** | the capacity tier on the **edges of the memory mesh** (2.5D HBM stack / off-package) — not under the hot compute |

### Two physical NoC planes (by traffic class)

The key decision is that **two different kinds of traffic are carried by two separate networks**:

| | **Core mesh** (top) | **Memory mesh** (bottom) |
|---|---|---|
| Carries | inter-core actor messages | SRAM↔DRAM (spill/fill, cold tier) |
| Nature | small, latency-sensitive | bulk, bandwidth-hungry |
| Optimization | fast, narrow links | wide links, **coarser granularity** (aggregating) |

**Trade-off — physical plane vs virtual network (VN):** so far the CFPU separated traffic classes on one mesh with **virtual networks** (2VN, see [`interconnect-en.md`](interconnect-en.md)) over shared wires. Here we **promote the memory VN to its own physical plane**: more expensive (an extra layer), but **perfect isolation** (bulk memory traffic never chokes the latency-critical messaging) and **independent optimizability**. The two planes also give **two separate "4 edges"**: the core-mesh edges → host I/O + chip-to-chip link; the memory-mesh edges → DRAM.

### SRAM as a bandwidth filter

The memory mesh is also 2D, so the same 1/√N wall would in principle threaten it — **but SRAM as a bandwidth filter saves it:**

- The hot working set is served by the **vertical SRAM** (0 hops). Only the **miss** goes down to the memory mesh.
- With a good SRAM hit rate the memory mesh carries a **fraction** of total traffic.
- If the working set fits in SRAM → DRAM traffic drops to **~0** (Cerebras principle).
- CFPU actor working sets are modest (comfort ~100–300 KB/core, see [`core-types-en.md`](core-types-en.md)) → the per-tile 3D SRAM can **realistically hold** them.

### Thermal orientation: compute on top

**Sub-decision:** SRAM on top (logic below) **or** compute on top (SRAM/memory below)?

The hot compute must be close to the cooler. Evidence: the evolution of **AMD 3D V-Cache**:

| Generation | Layout | Consequence |
|------------|--------|-------------|
| Zen 3/4 (5800X3D, 7800X3D) | cache **on top**, structural silicon | heat trap → **downclock** |
| Zen 5 (9800X3D) | cache **below the CCD** | **full clock**, ~46% better thermal resistance, overclock |

→ **CFPU: compute (core mesh) on top.** Cost: **power must be delivered up** to the top logic — either via power TSVs through the intermediate layers, or more elegantly via **backside power delivery** (BSPDN — Intel PowerVia / TSMC backside), which feeds power from the top (the same side heat leaves) and frees the bottom side for data TSVs.

## Real-silicon positioning

**Every single piece** of this architecture **exists in real, shipping silicon** — but the *exact combination at this scale* is not a finished product.

| CFPU architecture element | Real chip that already does it | Status |
|---------------------------|--------------------------------|--------|
| Many small cores in a 2D mesh (messaging NoC) | Tenstorrent (Tensix), Cerebras WSE, Tilera, Intel mesh | shipping |
| SRAM 3D-stacked on the compute | **AMD 3D V-Cache** (on the compute), Intel Ponte Vecchio RAMBO (on the base tile) | shipping |
| Logic on top / cache below (thermal) | **AMD Zen 5 X3D (9800X3D)** | shipping |
| Separate memory network in a base die / active interposer | **AMD MI300 IOD/AID**, Intel PV Foveros base tile, **CEA-Leti IntAct** | shipping (MI300/PV) + research (IntAct) |
| DRAM at the edges (2.5D HBM), not on the hot path | AMD MI300, Intel Ponte Vecchio | shipping |
| SRAM-everywhere, no DRAM on the hot path | **Cerebras WSE** | shipping |

**The closest whole systems:**

- **AMD MI300 (closest commercial).** Compute dies (XCD/CCD) **3D-stacked on top** (SoIC, 9µm hybrid bond) sit on the **IODs** (AMD's official name; analysts also label these the **AID / Active Interposer Die**). The IOD contains the **memory network (Infinity Fabric AP) + memory controllers + 256 MB Infinity Cache** (shared LLC, 128 × 2 MB slices). The **8× HBM3** sits on the **CoWoS-S interposer, next to the IODs** (2.5D). AMD calls this "**3.5D**" (SoIC 3D + CoWoS 2.5D).
- **Intel Ponte Vecchio.** 63 tiles: 16 compute + **8 RAMBO SRAM cache** (15 MB/tile, 3D-stacked) + 2 **Foveros base tiles** (memory controller + fabric + FIVR) + 8 HBM2E + Xe-Link + EMIB.
- **CEA-Leti IntAct (closest research).** 96 cores, 6 chiplets **3D-stacked on an active interposer**, and **the NoC lives inside the active interposer** (chiplet-to-chiplet network + L1/L2/L3 + integrated power). This is **literally** our "memory mesh one layer below" concept at demonstrator level.
- **Cerebras WSE / Tenstorrent (philosophical relatives).** Cerebras: ~850k tiles in a uniform 2D mesh, 48 KB SRAM/tile, **zero external DRAM** (but 2D, not 3D). Tenstorrent: Tensix mesh + NoC, ~1.5 MB SRAM/tile, hybrid memory — the **CFPU's closest commercial cousin** in messaging-mesh philosophy.

### MI300 layer comparison

| Dimension | MI300 | CFPU (ours) | |
|-----------|-------|-------------|:--:|
| Compute on top (thermal) | XCD/CCD on top, SoIC | core mesh on top | ✅ matches |
| Base die = active interposer with memory network | IOD/AID: Infinity Fabric + MC + LLC | memory-mesh layer | ✅ matches the principle |
| DRAM at the edges (2.5D) | 8× HBM3 on CoWoS, next to IOD | HBM at the memory-mesh edges | ✅ matches |
| 3D integration (hybrid bond + TSV) | SoIC 9µm + CoWoS | TSV/hybrid bond | ✅ matches (tech) |
| **Granularity** | ~12–13 big chiplets (8 XCD × 38 CU) | ~65,000 tiny, independent cores | ❌ differs (coarse vs fine) |
| **Network** | **ONE** coherent fabric (Infinity Fabric AP), with VCs | **TWO** separate physical mesh planes, by traffic class | ❌ differs |
| **SRAM/cache** | 256 MB **shared**, memory-side LLC in the IOD | per-tile **private** 3D scratchpad, 0-hop | ❌ differs |
| **Memory model** | cache-**COHERENT**, unified/shared (NUMA) | shared-**NOTHING**, message passing + capability | ❌ differs (the deepest) |
| **Execution / ISA** | GPU CUs (CDNA3) | native CIL bytecode, in-order actor core | ❌ differs |

> **Clarification:** MI300 **does not stack a separate SRAM die on the compute** (that's V-Cache / Ponte Vecchio RAMBO). MI300's cache sits in the **base IOD** as a shared, memory-side LLC. So the parallel to our **per-tile 3D SRAM layer is not MI300** but V-Cache/RAMBO — MI300 validates the **memory-network-in-the-base-die + edge-HBM + compute-on-top** part.

## Where the CFPU novelty begins

> **The PACKAGE (the physical "how to stack") is proven — the NOVELTY is in the CONTENT and BEHAVIOR of the layers.**

MI300 proves that the stacked layout (**compute on top + active-interposer memory base + edge HBM + hybrid bond**) is a **commercial, volume-manufactured reality** → the CFPU **packaging is low-risk**. The CFPU does not innovate in the package but in what it puts into the layers:

1. **Granularity** — 65k fine, independent cores (Cerebras-fine) instead of MI300's dozen big chiplets; **nobody has combined** this with the memory base.
2. **Two physically separated NoC planes** (messaging vs memory) instead of MI300's **single** coherent fabric.
3. **Shared-nothing message passing + capability memory** instead of MI300's **cache-coherent shared** memory — the deepest divergence and the CFPU's scaling + security **moat**.
4. **Per-tile private 3D scratchpad (0-hop)** instead of MI300's shared, memory-side LLC.
5. **Native CIL execution + HW capability/security + Symphact static co-design** — an orthogonal software/ISA moat none of the above chips provides.

**In summary:** MI300 proves that the stacked layout is **physically manufacturable and alive**; the CFPU novelty begins when this proven package is filled with a **fine-grained many-core mesh, two traffic-class-separated network planes, shared-nothing capability memory, and native CIL execution** — which nobody has done together. The risk is low in the physics; the differentiation is in the **architecture, the security, and the software**.

## Open questions / future directions

1. **TSV granularity** — per-tile (best locality, 0 hop, max TSV) **vs** per-cluster (fewer TSV/bond, but a few hops within the cluster to the SRAM port). A real trade-off: TSV density ↔ in-plane hops.
2. **Thermal with 3 active layers** — the memory mesh is at the bottom, farthest from the cooler; fortunately lower power density (wires + DRAM PHY), but this is a design axis.
3. **Capacity tier** — the cold DRAM remains at the memory-mesh edges; the **integrity of cached code** (W⊕X?) and its relation to capability grants is open (see [`ddr5-architecture-en.md`](ddr5-architecture-en.md)).
4. **Power delivery** — BSPDN vs power TSVs across the whole stack (compute on top → power must be delivered up).
5. **Granularity matching** — e.g., a 16×16 memory mesh under a 256×256 core mesh; the path of an SRAM miss down to DRAM.

## Related documents

- [`chiplet-packaging-en.md`](chiplet-packaging-en.md) — 2.5D **horizontal** chiplet layout (this doc's counterpart); already includes a "3D SRAM" and "3D package" section
- [`topology-scaling-en.md`](topology-scaling-en.md) — bisection math, 1/√N scaling, mesh vs crossbar vs hierarchical
- [`interconnect-en.md`](interconnect-en.md) — CFPU NoC, 2VN, XY routing, router variants
- [`ddr5-architecture-en.md`](ddr5-architecture-en.md) — HW Capability Slot, cold memory tier
- [`core-types-en.md`](core-types-en.md) — SRAM sizing (per-core comfort 100–300 KB)
- [`architecture-en.md`](architecture-en.md) — full CFPU overview

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-07-02 | Initial version — the CFPU 3D vertical stacking vision for large meshes: the flat 2D mesh memory wall (1/√N, concrete 256×256 numbers), decision trail (A edge-only / B diamond / C 3D-DRAM / **D 3D-SRAM + memory mesh — chosen**), the layered stack (core mesh / per-tile SRAM / memory mesh / edge DRAM), two physical NoC planes (vs 2VN), thermal orientation (compute on top, V-Cache evidence), SRAM as a bandwidth filter. Real-silicon positioning (MI300/PV/IntAct/Cerebras/Tenstorrent) + MI300 layer comparison + "where the CFPU novelty begins". The vertical complement of [`chiplet-packaging`](chiplet-packaging-en.md). |
| 1.1 | 2026-07-17 | **DDR5 cross-reference terminology:** the stale "CAM ACL" corrected to the current **HW Capability Slot** model (ddr5-architecture v1.3). |

## External sources (real chips)

- AMD MI300 3D packaging (TechInsights): https://www.techinsights.com/blog/amd-mi300-family-adopts-3d-packaging
- MI300 "3.5D", SoIC+CoWoS, IOD/AID (SemiAnalysis): https://newsletter.semianalysis.com/p/amd-mi300-taming-the-hype-ai-performance
- MI300A memory subsystem, Infinity Fabric/Coherent Master (Chips and Cheese): https://chipsandcheese.com/p/inside-the-amd-radeon-instinct-mi300as
- MI300 microarchitecture, 256 MB Infinity Cache (ROCm): https://rocm.docs.amd.com/en/latest/conceptual/gpu-arch/mi300.html
- AMD 9800X3D — V-Cache below the CCD (TechPowerUp): https://www.techpowerup.com/328225/de-lidded-ryzen-7-9800x3d-pic-confirms-3d-v-cache-die-moved-below-the-ccd
- Intel Ponte Vecchio 3D packaging (ServeTheHome): https://www.servethehome.com/intel-xe-hpc-ponte-vecchio-shows-next-gen-packaging-direction/
- CEA-Leti IntAct active interposer (WikiChip Fuse): https://fuse.wikichip.org/news/3364/cea-leti-demos-a-6-chiplet-96-core-3d-stacked-mips-processor/
- Cerebras WSE overview (WikiChip Fuse): https://fuse.wikichip.org/news/3010/a-look-at-cerebras-wafer-scale-engine-half-square-foot-silicon-chip/
- Tenstorrent Wormhole analysis (SemiAnalysis): https://newsletter.semianalysis.com/p/tenstorrent-wormhole-analysis-a-scale
- D. Abts et al., "Achieving Predictable Performance through Better Memory Controller Placement in Many-Core CMPs", ISCA 2009 (diamond placement)
