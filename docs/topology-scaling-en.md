---
status: vision
---

# NoC Topology Scaling — general analysis

> Magyar verzió: [topology-scaling-hu.md](topology-scaling-hu.md)

> Version: 1.1

> **⚠️ Vision-level background document.** The area, BW, and latency figures presented here are working hypotheses extrapolated from documented sources (academic NoC measurements, ARM CoreLink CMN, Synopsys/Cadence NoC IP, Adapteva Epiphany, Tenstorrent Tensix) for a 5 nm node. General background, decoupled from CFPU specifics — for the actual CFPU parameterization see [`interconnect-en.md`](interconnect-en.md) and [`internal-bus-en.md`](internal-bus-en.md).

## Goal

This document analyzes how **different on-chip network topologies** scale with core count (N), assuming the **message unit is fixed at 144 bytes** (16-byte header + 128-byte payload). Three primary metrics are examined:

1. **Silicon area** (router logic + buffer SRAM + wires)
2. **Throughput** (per-core BW, aggregate BW, bisection BW)
3. **Latency** (diameter, average hop count, message delivery time)

The target: **constant per-core BW with linear area cost**. The tables below show which topology achieves this — and when.

## Message unit and link assumptions

| Parameter | Value |
|-----------|-------|
| Message size | M = 144 byte = 1 152 bit |
| Header | 16 byte = 128 bit (1 flit on a 128-bit link) |
| Payload | 1–128 byte (max 8 flits) |
| Link width (default) | w = 128 bit |
| Link frequency | f = 1 GHz (5 nm typical) |
| Per-link BW | B = w · f = 128 Gb/s = **16 GB/s** |
| Message length | F = ⌈M / (w/8)⌉ = **9 flits** (on 128-bit link) |
| Wormhole router pipeline | 2 cycles / hop |
| Maximum messages/sec/link | B / M = ~111 M msg/s |

The 128-bit link is industry-standard for small/medium chips (see `internal-bus-en.md` v1.3 industry references).

## Topology catalogue

### 1. Shared bus

```
[C0]──┬──[C1]──┬──[C2]──┬──[C3]──...──[Cn]
      │        │        │
   shared wire across all cores
```

All cores connect to a single shared bus. Only one message at a time. A bus arbiter decides who gets access.

### 2. Ring (bidirectional)

```
   [C0]───[C1]───[C2]
    │              │
   [C7]          [C3]
    │              │
   [C6]───[C5]───[C4]
```

Cores connect in a ring with two directions (CW and CCW). A core only talks directly to its two neighbours; distant cores require multiple hops.

### 3. 2D Mesh (√N × √N)

```
   [C0]──[C1]──[C2]──[C3]
    │     │     │     │
   [C4]──[C5]──[C6]──[C7]
    │     │     │     │
   [C8]──[C9]──[CA]──[CB]
    │     │     │     │
   [CC]──[CD]──[CE]──[CF]
```

Square grid, each router has 5 ports (4 neighbours + 1 local). XY routing is acyclic and deadlock-free.

### 4. 2D Torus

Like a mesh, but edge cores wrap around (toroidal surface). Halves the maximum hop count, but wraparound wires are long.

### 5. Crossbar (N×N)

```
       C0  C1  C2  C3  ...  Cn
       │   │   │   │
   C0──┼───┼───┼───┼─── ...
       ×   ×   ×   ×
   C1──┼───┼───┼───┼─── ...
       ×   ×   ×   ×
   ...
```

Every core connects directly to every other core (1 hop). N² crosspoint switches.

### 6. Fat-tree (k-ary)

```
              [Root]
             /  |  \
        [Sw1]  [Sw2]  [Sw3]
         /\     /\     /\
       C0 C1  C2 C3  C4 C5
```

Hierarchical tree where bandwidth does not decrease toward the root (hence "fat"). Bisection = N · B.

### 7. Hierarchical (k-mesh + crossbar tree)

```
[16-core mesh] [16-core mesh] [16-core mesh] ...
       \           |           /
        \          |          /
         [Tile crossbar (8 ports)]
                   |
         [Region crossbar (8 ports)]
                   |
              [Chip root]
```

Lowest level is a mesh (physical adjacency), upper levels are crossbars (logical centre). 4-level hierarchy (chip → region → tile → cluster).

## Scaling formulas

### Wires / link count (~ area cost)

| Topology | Number of links | Area |
|---|---|---|
| Shared bus | O(1) | but N driver capacitance → repeaters O(N) |
| Ring | 2N | O(N) |
| 2D Mesh √N×√N | 2N − 2√N ≈ **2N** | O(N) |
| 2D Torus | 2N | O(N) |
| Fat-tree (k-ary) | O(N · log_k N) | O(N log N) |
| Crossbar N×N | **N²** crosspoints | **O(N²)** |
| Hierarchical (k-mesh + crossbar tree) | O(N) + O((N/k)² / level) | **O(N)** + lower-order |

### Diameter (max hops)

| Topology | Diameter |
|---|---|
| Shared bus, Crossbar | 1 |
| Ring | N/2 |
| 2D Mesh √N×√N | 2(√N − 1) |
| 2D Torus | √N |
| Fat-tree (k-ary) | 2 · log_k N |
| Hierarchical (4-level) | √16 + 3 · log_k(N/16) |

### Bisection bandwidth (BW cutting the network in half)

Bisection BW is the **most important scaling metric** because it caps aggregate traffic when traffic is non-local.

| Topology | Bisection BW |
|---|---|
| Shared bus | B (single wire) |
| Ring | 2B (bidirectional) |
| 2D Mesh √N×√N | 2√N · B |
| 2D Torus | 4√N · B |
| Fat-tree | N · B |
| Crossbar | N · B |
| Hierarchical | N · B (stepped) |

### Per-core BW (uniform-random traffic)

| Topology | BW/core | Scaling |
|---|---|---|
| Shared bus | B / N | **1/N** — collapses |
| Ring | ~ 4B / N | **1/N** |
| 2D Mesh | ~ (3/2) · B / √N | **1/√N** |
| 2D Torus | ~ 2B / √N | **1/√N** (~30% better than mesh) |
| Fat-tree | B | **constant** |
| Crossbar | B | **constant** |
| Hierarchical | B (within cluster) | **constant** |

## Concrete numbers with 128-bit link, 1 GHz, 144-byte messages

### Per-core BW (uniform-random, GB/s)

| N | Bus | Ring | 2D Mesh | Torus | Crossbar | Hierarch. (16-mesh + xbar tree) |
|---|---|---|---|---|---|---|
| **16** (4×4) | 1.0 | 4.0 | **6.0** | 8.0 | 16.0 | 16.0 |
| **64** (8×8) | 0.25 | 1.0 | 3.0 | 4.0 | 16.0 | ~12 |
| **256** (16×16) | 0.06 | 0.25 | 1.5 | 2.0 | 16.0 | ~10 |
| **1 024** (32×32) | 0.015 | 0.06 | 0.75 | 1.0 | 16.0 | ~8 |
| **10 240** | 0.0015 | 0.006 | 0.24 | 0.32 | 16.0 | ~5 |

### Crosspoint / wire requirements

| N | Bus links | Mesh links | Crossbar crosspoints | Hierarchical crosspoints |
|---|---|---|---|---|
| 16 | 1 | 24 | 256 | 24 + 1 |
| 64 | 1 | 112 | 4 096 | 96 + 16 |
| 256 | 1 | 480 | **65 536** | 384 + 256 |
| 1 024 | 1 | 1 984 | **>1 M** ❌ | 1 536 + 4 096 |
| 10 240 | 1 | ~20 480 | **>100 M** ❌ | ~15 360 + ~6 400 |

The crossbar is **not synthesizable from N = 256 onward** at reasonable chip area.

## Traffic pattern — aggregate vs per-core BW

> **Important:** the "Per-core BW" table above assumes **uniform random traffic** (every core communicates with every other core with equal probability) — this is **worst case**. Under local traffic with parallelism, the actual per-core BW is orders of magnitude better.

### Aggregate BW — all links operating in parallel

In a mesh (or hierarchical network), **every link can carry a message simultaneously** — the network's aggregate maximum is the sum of link capacities:

| Topology | Aggregate BW formula | Reasoning |
|---|---|---|
| Shared bus | B | Single wire, serialized |
| Ring | 2N · B | 2N links, each B |
| 2D Mesh √N×√N | **2N · B** (~ 2(N − √N) · B precisely) | All links in parallel |
| 2D Torus | 2N · B | Like mesh + wraparound |
| Crossbar | N · B | N output ports × B (1 hop, but unsegmented) |
| Hierarchical | ≥ N · B (cluster-locally) + upper levels | For cluster-local traffic ~full link capacity |

### Concrete aggregate numbers (B = 16 GB/s)

| N | Bus aggregate | **Mesh aggregate** | Crossbar aggregate | Hierarchical (cluster-local) |
|---|---|---|---|---|
| **16** | 16 GB/s | **384 GB/s** | 256 GB/s | 384 GB/s |
| **64** | 16 GB/s | **1.8 TB/s** | 1.0 TB/s | ~1.5 TB/s |
| **256** | 16 GB/s | **7.7 TB/s** | 4.1 TB/s | ~6 TB/s |
| **1 024** | 16 GB/s | **31.7 TB/s** | 16.4 TB/s | ~25 TB/s |
| **10 240** | 16 GB/s | **~324 TB/s** | not buildable | ~250 TB/s |

**Notable observation:** mesh aggregate BW > crossbar aggregate BW for the same N. A crossbar links any two cores in 1 hop, but the mesh has **multiple links operating in parallel** (more hops, but segmentable — every link can carry its own message simultaneously).

### Traffic locality factor

The actual per-core BW depends strongly on traffic pattern. Example for a **1024-core mesh**:

| Traffic pattern | Bisection load | Per-core BW | Scaling |
|---|---|---|---|
| Neighbour-only (90%+ local) | minimal | **~16 GB/s** = B | constant |
| Cluster-local (within 4×4) | minimal | ~12 GB/s | constant |
| Tile-local (~64 cores) | moderate | ~5 GB/s | slow decrease |
| Region-local (~256 cores) | significant | ~2 GB/s | √N decrease |
| Uniform random | saturated | **~0.75 GB/s** ← earlier table | 1/√N |
| Adversarial (anti-pattern) | critical | ~0.4 GB/s | 1/√N + congestion |

**The difference is 40× between the two extremes.** Locality-aware actor placement (e.g., tightly communicating actors placed in the same cluster) sustains **~B** per-core BW, while the worst-case traffic degrades with 1/√N scaling.

### When does the "Per-core BW" table's 1/√N scaling apply?

The earlier 1/√N scaling **only** caps when bisection BW is the bottleneck — i.e., when traffic direction is **on average uniform**. The three typical regimes:

1. **Local communication dominates** (>80% neighbour or cluster-local) → per-core BW ≈ B (constant)
2. **Mixed traffic** (~50% local, 50% remote) → per-core BW ≈ B/√(N/k) where k is the local domain size
3. **Pure uniform random** → per-core BW = (3/2)B/√N (the table formula)

The CFPU actor model targets case 1: HW addresses are hierarchical, NoC router topology is neighbour-aware, and actor placement is the OS's responsibility for ensuring locality.

### Crossbar vs mesh — a different angle

The crossbar is not the "perfect" solution from every perspective:

| Metric | Crossbar (N=1024) | Mesh (N=1024) |
|---|---|---|
| Aggregate BW | 16 TB/s | **31.7 TB/s** (2×) |
| Per-core BW (uniform) | **16 GB/s** | 0.75 GB/s |
| Per-core BW (local) | 16 GB/s | **~16 GB/s** (equal) |
| Latency | **11 ns** | 51 ns |
| Area | 25-35 mm² ❌ | **3.2 mm²** |

The crossbar wins on **latency and uniform-random per-core BW**; the mesh wins on **aggregate BW and area**. **Under local traffic, the per-core BW of the two topologies is practically equal**, while the mesh achieves it on a fraction of the area.

## Silicon area (5 nm)

### Unit costs

| Component | Typical size at 5 nm |
|---|---|
| 1 GE (NAND2 equivalent) | ~0.16 µm² |
| 1 SRAM bit cell (HD) | ~0.021 µm² |
| 1 flit slot (144 byte = 1 152 bit) buffer | ~25–30 µm² |
| 1 crossbar crosspoint | ~10 µm² (~50 GE switch) |
| 5-port mesh router (Compact, 2 VC × 4 slots) | ~14.5k GE ≈ **0.003 mm²** |
| 5-port mesh router (Turbo, full VOQ × 4 VC) | ~40k GE ≈ **0.008 mm²** |
| 1 mm wire (128-bit, M3-M4 metal) | ~256 repeaters + tracks |

### Router buffer sizing from the 144-byte cell

A 5-port mesh router buffer cost (>50% of router area at small N):

```
Slot size      : 144 byte = 1 152 bit
Slots/port/VC  : 4 (typical wormhole pipeline)
VCs/port       : 2 (priority + normal)
Ports          : 5 (N, S, E, W, local)
Total slots    : 5 × 2 × 4 = 40 slots
Buffer SRAM    : 40 × 144 byte = 5.76 kB / router
Area (5 nm)    : ~0.002 mm² SRAM + ~0.001 mm² logic
Total/router   : ~0.003 mm² (Compact variant)
```

→ **Total buffer SRAM in a 1024-core mesh = ~5.9 MB**, ~10–15% of the total mesh area.

If the message unit grew to **288 bytes** (2× cell):
- Buffer area 2× → ~0.006 mm²/router
- 1024-core mesh: 6.4 mm² (twice as much)

Mesh router area is **near-linearly sensitive to cell size**.

### Total NoC area in mm²

| N | Bus | Ring | 2D Mesh | Torus | Crossbar | Fat-tree (k=8) | Hierarch. |
|---|---|---|---|---|---|---|---|
| **16** | ~0.01 ⚠️ | 0.03 | 0.05 | 0.06 | 0.18 | – | 0.05 |
| **64** | ❌ | 0.1 | 0.2 | 0.22 | **1.0** | 0.5 | 0.25 |
| **256** | ❌ | 0.4 | 0.8 | 0.9 | **5–7** | 2.0 | 1.0 |
| **1 024** | ❌ | 1.5 | 3.2 | 3.5 | **25–35** | 10 | 4 |
| **10 240** | ❌ | 15 | 32 | 35 | **>1 000** ❌ | ~120 | 40 |

The **bus** is not viable from N ≥ 8 (capacitance → driver + repeater → frequency collapses).
The **crossbar** consumes more area than the cores themselves from N ≥ 256.

### Component breakdown (1024-core case)

| Topology | Router/Logic | Buffer SRAM | Wires | **Total** |
|---|---|---|---|---|
| 2D Mesh 32×32 | 1024 × 0.003 = 3.1 mm² | ~0.15 mm² (router-integrated) | included | **~3.2 mm²** |
| Torus 32×32 | same | same | +10% wraparound | **~3.5 mm²** |
| Crossbar 1024² | 0.5 mm² (arbiter) | ~12 mm² (1024 inputs × 9 kB) | ~10 mm² (N² xpoints) | **~25 mm²** |
| Fat-tree k=8 | 512 routers × 0.02 = 10 mm² | included | included | **~10 mm²** |
| Hierarch. (64×16+tree) | 1024 × 0.003 + ~0.5 | ~0.2 mm² | included | **~4 mm²** |

### NoC overhead ratio

Assuming **0.5 mm²/core** average:

| N | Chip core area | Mesh NoC | Crossbar NoC | Hierarch. NoC |
|---|---|---|---|---|
| 16 | 8 mm² | **0.6%** | 2.3% | 0.6% |
| 64 | 32 mm² | **0.6%** | 3.1% | 0.8% |
| 256 | 128 mm² | **0.6%** | 4.7% | 0.8% |
| 1 024 | 512 mm² | **0.6%** | 5.3% | 0.8% |
| 10 240 | 5 120 mm² | **0.6%** | not buildable | 0.8% |

The **mesh and hierarchical solutions stay at constant ~0.6–0.8% area overhead**, independent of N. The **crossbar overhead grows linearly with N** (because N² area / N · core = N).

## Latency (wormhole, 2 cycles/router)

Latency ≈ F + 2 · hop_count cycles = 9 + 2 · hop cycles (on 128-bit link)

| Topology | Avg hops | Latency at 1 GHz |
|---|---|---|
| Crossbar | 1 | 11 ns |
| Bus (single message) | 1 | 11 ns (but serialized!) |
| 16-core mesh | ~2.7 | 14 ns |
| 64-core mesh | ~5.3 | 20 ns |
| 256-core mesh | ~10.7 | 30 ns |
| 1024-core mesh | ~21.3 | 51 ns |
| Hierarchical 1024 (4-level, ~6 hop + 3 xbar hops) | ~9 | ~21 ns |

The bus latency is misleading — a single message takes 11 ns, but **serializes for N**, so the effective latency under load is N · 11 ns.

## Topology selection algorithm

```
IF N ≤ 8 AND traffic is sparse:
    Shared bus is sufficient
ELSE IF N ≤ 32 AND BW is critical, area is not:
    Crossbar is the cleaner solution
ELSE IF 16 ≤ N ≤ 64 AND uniform neighbouring:
    2D Mesh / Torus is optimal
ELSE IF N ≥ 64:
    Hierarchical (cluster mesh + crossbar tree)
        — only viable choice
        — constant per-core BW
        — linear area
```

The decision boundaries are empirical; exact values vary with node, frequency, and message size (the tables above are for the 144-byte cell).

## Why hierarchical wins — mathematical justification

The hierarchical solution (16-core cluster mesh + crossbar tree) wins from N ≥ 64 because:

```
N = 1024 cores example:

  Pure crossbar:    1024² = 1 048 576 crosspoints  ❌
                    ~25-35 mm² area

  Pure 2D mesh:     1 984 links, but 51 ns latency
                    0.75 GB/s/core (decreases with N)
                    ~3.2 mm² area

  Hierarchical:     64 × (16-core mesh) + 64-port crossbar tree
                  = 64 × 24 + 64² = 1 536 + 4 096 = 5 632 crosspoints
                    21 ns latency
                    ~8 GB/s/core (10× better than pure mesh)
                    ~4 mm² area
```

So at N = 1024 cores the hierarchical:
- **~186× fewer crosspoints** than crossbar (5.6k vs 1M)
- **10× better per-core BW** than pure mesh
- **only 2× worse per-core BW** than the (un-buildable) crossbar
- **~25% more area** than pure mesh (4 vs 3.2 mm²) — slightly higher router count, but the 10× better per-core BW and 2.4× better latency more than compensate
- **2.4× better latency** than pure mesh (21 vs 51 ns)

The hierarchical topology is therefore also the **CFPU choice** (see `interconnect-en.md` 4-level hierarchy).

## Key takeaways

**1. Bisection BW determines scaling, not link width.**
- 2D mesh: bisection ∝ √N → per-core BW ∝ 1/√N
- Torus / fat-tree / hierarchical: bisection ∝ N → per-core BW constant

**2. Crossbar is the "perfect" solution paying the N² cost.**
- N = 16: 256 crosspoints, manageable
- N = 64: 4 096 crosspoints, borderline
- N ≥ 256: not synthesizable (>65k crosspoints)

**3. The 144-byte message unit determines three things:**
- **Message length in flits:** 9 flits on 128-bit link (header overhead ~11%)
- **Traffic granularity:** too small → router overhead dominates; too large → HOL blocking
- **Buffer size:** every router ~5.76 kB / VC × ports (main mesh router area cost)

**4. NoC overhead is constant in linearly-scaling topologies.**
- Mesh, torus, hierarchical: ~0.6–0.8% chip area, independent of N
- Crossbar: increasing area share (N=1024 → 5%+)

## Industry references

| System | Topology | N | Note |
|---|---|---|---|
| Intel Xeon (Skylake-SP+) | 2D Mesh | 28+ | Server core, non-hierarchical |
| AMD EPYC (Zen 4) | Crossbar (CCD) + Infinity Fabric | 8/CCD | Hierarchical, on-package |
| Apple M4 Max | Ring (P-cluster) + crossbar | 4-12 | Heterogeneous |
| ARM CoreLink CMN | Mesh (mesh-IP) | 1-128 | Configurable mesh |
| Adapteva Epiphany | 2D Mesh (eMesh) | 16/64 | Many-core nano |
| Tenstorrent Tensix | 2D Torus (NoC) | 80-256 | ML-oriented |
| Cerebras WSE-3 | 2D Mesh (local) | 900 000 | Wafer-scale |
| **CFPU (planned)** | **Hierarchical (mesh + crossbar tree)** | **16–10 240** | 4-level, see `interconnect-en.md` |

## Related documents

- [`interconnect-en.md`](interconnect-en.md) — concrete CFPU 4-level hierarchical mesh + crossbar specification
- [`internal-bus-en.md`](internal-bus-en.md) — bus width selection (32–1024 bit) per core type
- [`decision-bus-rollback-en.md`](decision-bus-rollback-en.md) — L0 bus rollback rationale (256→128 bit)
- [`architecture-en.md`](architecture-en.md) — F4 shared bus → F6 mesh transition (16-core boundary)
- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — TLP > ILP philosophy (many small cores due to linear scaling)
- [`osreq-from-os/osreq-001-tree-interconnect-en.md`](osreq-from-os/osreq-001-tree-interconnect-en.md) — Symphact OS hardware requirement on topology

## Changelog

| Version | Date | Summary |
|---------|------|--------|
| 1.1 | 2026-05-03 | **New section: "Traffic pattern — aggregate vs per-core BW"**. v1.0 only showed uniform random traffic (worst case); v1.1 adds the aggregate BW formula (mesh: 2N · B), concrete aggregate numbers (16-core mesh 384 GB/s, 1024-core mesh 31.7 TB/s), traffic locality factor table (40× difference neighbour vs uniform), and a direct crossbar-vs-mesh comparison at equal N. Key conclusion: under local traffic, mesh per-core BW ≈ B (like crossbar), while mesh aggregate > crossbar aggregate. The earlier 1/√N scaling only applies in the bisection-limited (uniform random) case |
| 1.0 | 2026-05-03 | Initial version — general NoC topology scaling decoupled from CFPU. Bus/Ring/Mesh/Torus/Crossbar/Fat-tree/Hierarchical comparison with the 144-byte message unit. Per-core BW, bisection BW, area (5 nm), latency formulas and concrete numbers for N = 16, 64, 256, 1024, 10240 cores. Topology selection algorithm. Mathematical justification for the hierarchical choice from N ≥ 64 |
