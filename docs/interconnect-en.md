# CFPU Interconnect Architecture

> Magyar verzió: [interconnect-hu.md](interconnect-hu.md)

> Version: 3.0

This document specifies the **on-chip interconnect network** of the Cognitive Fabric Processing Unit (CFPU): the topology, switching model, router internals, physical layout, core family, and node-scaling strategy.

## Core Family

The CFPU defines four programmable core types (Nano, Actor, Rich, Seal) and six product variants (CFPU-N/A/R/ML/H/X). ML inference uses MAC Slices (FSM-driven, non-programmable). For full details — ISA differences, area impact, SRAM sizing, power domains, and market positioning — see [`core-types-en.md`](core-types-en.md); for MAC Slice specification: [`cfpu-ml-max-hu.md`](cfpu-ml-max-hu.md).

## Design Principles (in priority order)

1. **Security is non-negotiable** — shared-nothing is mandatory; no shared memory or cell pool. Cores send messages by copying, not by passing pointers.
2. **Core count = compute throughput** — every gate spent on the router is a gate missing from a core. Router area must be minimized. Three router variants (Turbo, Compact, Systolic) keep overhead at 4–29% depending on core type (see L0 Router Variants).
3. **Message speed = system speed** — but with a simple, small router, not a smart, large one. Only techniques that increase effective core count are used.

## 4-Level Hierarchy

The CFPU on-chip network is a **4-level hierarchy**, where the bottom level is a mesh and the upper levels are crossbars:

```
L3: Chip ── N₃ regions, star topology
            Seal Core + crossbar at the geometric center of the chip
 └── L2: Region ── N₂ tiles, crossbar at the region center, serial links
      └── L1: Tile ── N₁ clusters, crossbar at the tile center
           └── L0: Cluster ── 16 cores (Nano/Actor/Rich), 4×4 mesh (fixed)
```

### Why mesh at the bottom, crossbar at the top?

| Criterion | Mesh | Crossbar |
|-----------|------|----------|
| Many ports (64+) | Efficient: short wires, low gate count | Expensive: N² scaling |
| Few ports (8–16) | Wasteful: many hops, variable latency | **Efficient: 1 hop, fixed, deterministic** |
| Physical adjacency | **Natural**: 2D chip = 2D mesh | Must be placed at center |
| Routing decision | Required at every hop | **None**: crossbar = direct connection |

The mesh is used where physically justified (between cores, ~300 µm). The crossbar is used where logically justified (between gateways, 8–18 ports).

### Reference Configuration (5nm, 800 mm²)

```
L0: 16 cores × L1: 8 clusters × L2: 8 tiles × L3: 10 regions = 10,240 cores
```

### Configurable Parameters

| Parameter | Fixed/Variable | Range | Determined by |
|-----------|----------------|-------|---------------|
| `CORES_PER_CLUSTER` | **Fixed** | 16 (4×4) | Physical optimum: ~1.1 mm, 2-cycle wormhole pipeline/hop |
| `CLUSTERS_PER_TILE` | Variable | 4–12 | Node, die size |
| `TILES_PER_REGION` | Variable | 4–12 | Node, die size |
| `REGIONS` | Variable | 4–24 | Die size |
| `SRAM_KB_PER_CORE` | Variable | 16–1024 | Node |
| `CELL_SIZE` | Variable | 256 (default) | Max payload size (bytes) |
| `CORE_TYPE` | Variable | NANO/ACTOR/RICH/MATRIX | Application-dependent (mixed on heterogeneous chips) |
| `ROUTER_VARIANT` | Variable | TURBO/COMPACT/SYSTOLIC | Core type dependent (cluster-level) |
| `SERDES_RATIO` | Variable | 4–12 | Core clock dependent (see SerDes Scaling) |
| `SERIAL_WIRES` | Variable | 8–16 | Die size, wire budget |

## Switching Model

### ATM-Inspired Fixed Cell

Every message is segmented into **fixed cells** that travel through the network: **16-byte header + up to 256-byte payload = up to 272 bytes**. Buffers are fixed-size (272-byte slots), but **only the actual payload travels on the link** — the `len` field determines how many bytes are actually forwarded (`len` value + 1, i.e. 1–256 bytes; zero-byte payload does not exist, signaled via flags instead).

```
Cell = Header (16 bytes) + Payload (1-256 bytes) = 17-272 bytes on the link

Header (16 bytes = 128 bits = 4 × 32 bits) — stored in Header SRAM:
┌─────────────────────────────────────────────────────────────────────┐
│  Word 0:  dst[24] + dst_actor[8]                — target (HW+actor)│
│  Word 1:  src[24] + src_actor[8]                — source (HW+actor)│
│  Word 2:  seq[16] + flags[8] + len[8]           — control          │
│  Word 3:  reserved[8] + CRC-16[16] + CRC-8[8]  — integrity        │
│                                             Total: 128 bits         │
└─────────────────────────────────────────────────────────────────────┘

Payload (1-256 bytes) — stored in Payload SRAM:
┌────────────────────────────────────────────────────────────┐
│  1-256 bytes application data (determined by len+1)        │
└────────────────────────────────────────────────────────────┘
```

**Header fields:**

| Field | Size | Written by | Description |
|-------|------|-----------|-------------|
| `dst` | 24 bits | Sending core HW | Destination hierarchical HW address (region.tile.cluster.core) — resolved by sending core HW from CST index |
| `dst_actor` | 8 bits | Sending core HW | Destination actor identifier (max 256 actors / core) — resolved from CST index |
| `src` | 24 bits | **NoC router HW** | Source HW address — hardware-filled, cannot be spoofed |
| `src_actor` | 8 bits | **Core HW** | Sending actor identifier — from the active actor context register, cannot be spoofed |
| `seq` | 16 bits | Sender | Sequence number (ordering for fragmented messages, max 65,536 fragments) |
| `flags` | 8 bits | Sender | `[VN:1][relay:1][Pri:2][reserved:4]` — VN0/VN1, relay flag, message priority (4 levels) |
| `len` | 8 bits | Sender | Payload size: value + 1 = 1–256 bytes (zero-byte payload does not exist, signaled via flags) |
| `CRC-16` | 16 bits | HW | Payload integrity check (stored in header, computed over the payload) |
| `CRC-8` | 8 bits | HW | Header integrity check (last field, computed over the entire header including CRC-16) |
| `reserved` | 8 bits | — | Future extensions |

**Why `src_actor` / `dst_actor` in the header?** In v1.8, the actor ID was moved to the payload (software dispatch). With N:M actor-to-core mapping (multiple actors per core, including sleeping actors), having actor IDs in the header provides **hardware-level advantages**:
- **DDR5 Controller CAM table** — actor-level access control via `src[24] + src_actor[8]`
- **Crash recovery** — only the crashed actor's capabilities need to be revoked, not the entire core's
- **Router-level dispatch** — the receiving core's scheduler knows which actor the message is for from the header, without reading the payload
- **8 bits** — 256 actors / core, covers sleeping actors as well (in practice, 256 contexts/core is sufficient: warm-context cache holds 4–8 active + 248 sleeping actors)

**Capability model (v3.0):** Software **never sees raw `dst`/`src` addresses** — only a 32-bit CST index (Capability Slot Table). The sending core's HW resolves the CST index into header `dst` + `dst_actor` fields. The CST resides in QSRAM with actor-level permissions (`perms`). The sending HW checks permissions at send time — `perms` does not travel in the header. HMAC is also unnecessary in the header: the CST is HW-managed, software cannot directly manipulate raw addresses.

**Variable link occupancy:** router buffers are always fixed-size (272-byte slots), but **only the header + (len+1) payload bytes travel on the link**. The router computes the number of payload flits from the header's `len` field:

```
256-bit L0 data path (1 flit = 32 bytes):
  payload_bytes = len + 1                    ← 1–256 bytes
  payload_flits = ceil(payload_bytes / 32)   ← 5-bit right shift + carry
  total_flits = 1 (header) + payload_flits

Examples:
  len = 7   (8 bytes)   → 1 + 1 = 2 flits   (64 bytes on link, not 272)
  len = 31  (32 bytes)  → 1 + 1 = 2 flits   (64 bytes on link)
  len = 63  (64 bytes)  → 1 + 2 = 3 flits   (96 bytes on link)
  len = 127 (128 bytes) → 1 + 4 = 5 flits   (160 bytes on link)
  len = 255 (256 bytes) → 1 + 8 = 9 flits   (272 bytes on link, full cell)
```

**HW cost:** 5-bit counter per port + shift. No LUT, no tail bit, no link-width overhead.

**Impact on network throughput:** ~80% of actor messages have ≤48 byte payloads. With variable link occupancy, links are **occupied ~43% less on average**, nearly doubling effective network throughput.

**Split SRAM design:** header and payload are stored in **separate SRAMs** inside the router. This is natural because they serve different functions: the scheduler reads the header for routing decisions while the payload is still arriving — **1 cycle latency saving**. No port contention between scheduler and crossbar. Both SRAMs are power-of-2 aligned: header = slot × 16, payload = slot × 256 — simple shift addressing, no multiplier needed.

**Why 16-byte header?** 128 bits is the natural power-of-2 boundary. The fields (dst, dst_actor, src, src_actor, seq, flags, len, CRC-16, CRC-8) require 120 bits, leaving 8 reserved bits for future extensions. The 4 × 32-bit word-aligned layout simplifies the HW parser. The 256-byte payload is also a natural power-of-2 boundary, aligned with DDR5 burst and on-chip SRAM cache line sizes.

**Why fixed buffers, variable links?** Fixed buffer size yields deterministic buffer management and simple SRAM addressing (the ATM networks' foundational principle). Variable link occupancy **does not increase buffer complexity** — only the forwarding counter changes — while significantly improving link utilization.

### Why 256-byte Payload?

In the v2.x series, the payload was 64 bytes. In v3.0 it grew to 256 bytes — the `len[8]` field with `len+1` semantics covers 1–256 bytes. This decision is based on the combined effect of the 256-bit L0 link and variable link occupancy:

| Aspect | 256B payload (272B cell, 256-bit L0) | 64B payload (80B cell, 42-bit L0) |
|--------|---------------------------------------|-------------------------------------|
| Header overhead (worst case) | 6% | 20% |
| Max flit count (256-bit L0 link) | 9 flits | 3 flits |
| Neighbor latency (worst case) | 2H + 8 = 10 cc | 2H + 2 = 4 cc |
| Neighbor latency (typical 48B) | 2H + 1 = 3 cc | 2H + 1 = 3 cc |
| Router VOQ SRAM | ~3.4× larger | smaller |

> **Note:** thanks to variable link occupancy, the worst-case flit counts above are rare. A typical 32-byte actor message: 2 flits on the 256-bit L0 (header + 1 payload) — the link **frees up very quickly**.

**Decisive argument: variable link occupancy.** On the 256-bit L0 link, typical actor messages (≤48 bytes) take only 2–3 flits — **faster** than the old 42-bit link with a 64B cell. The 256B max payload also enables large messages (state migration, code-load chunks) to use **fewer cells**, reducing header overhead and per-cell routing decisions.

In Akka/actor-style systems, the vast majority of messages are small (commands, events, short responses: 16–64 bytes), which fit easily in a single 256B cell — without multi-cell fragmentation. For large messages (4–16 KB state migration), the 256B payload requires 4× fewer cells than the former 64B.

The `CELL_SIZE` RTL parameter serves as a safety net: the max payload size is configurable at fabrication time.

**Final decision (2026-04-28):** 256B payload on the main mesh, with 256-bit L0 links.

#### Why 256B? — Detailed analysis

**1. The 256-bit L0 link changes the math.**
In v2.x, the 42-bit L0 link was the bottleneck: an 80B cell took 16 flits. On the 256-bit L0 link (tile-level NoC, see `internal-bus-en.md`), the header is a single flit and the full 256B payload takes only 8 flits. With variable link occupancy, typical small messages (≤48 bytes) traverse in 2–3 flits — **faster** than the old 42-bit link with a smaller cell.

**2. Aggregate throughput analysis — 256-bit L0 @ 500 MHz:**

| Payload size | Flit count (256-bit) | Payload throughput | Link efficiency |
|--------------|----------------------|--------------------|----------------|
| 32B (typical) | 2 flits | 32B / 2 cc = 16.0 B/cc | 50% |
| 64B | 3 flits | 64B / 3 cc = 21.3 B/cc | 67% |
| 128B | 5 flits | 128B / 5 cc = 25.6 B/cc | 80% |
| 256B (worst case) | 9 flits | 256B / 9 cc = 28.4 B/cc | 89% |

**L0 link throughput:** 256 bits × 500 MHz / 8 = **16 GB/s** (vs old 42-bit: ~2.6 GB/s, **~6× improvement**).

**3. Wormhole routing and HOL blocking — improved.**

On the 256-bit link, worst-case 256B payload is 9 flits — **shorter link occupancy** compared to the old 42-bit link's 16 flits:

```
H=6 (max L0 hops):
  256B cell, 256-bit link:  occupancy = 2H + 8 = 20 cc
  typical 48B, 256-bit link: occupancy = 2H + 1 = 13 cc
```

Shorter link occupancy reduces HOL blocking probability.

**4. Code-load throughput — 4× fewer cells.**

Seal Core code-load with 256B cells requires 4× fewer cells:
- 16 KB method = 64 cells (256B payload each), pipelined (vs old 256 cells × 64B)
- L0 throughput @ 500 MHz: **~16 GB/s** (vs old ~2.6 GB/s)
- Worst-case delivery: ~1.3 µs @ 500 MHz (vs old ~8 µs)

**5. Memory alignment — 256B covers the industry spectrum.**

| Memory type | Native burst size | Alignment |
|-------------|-------------------|-----------|
| DDR4 | 64 bytes (BL8 × 8B) | ≤ 256B, 4× bursts in one cell |
| DDR5 | 64 bytes (BL16 × 4B, dual sub-channel) | ≤ 256B, 4× bursts in one cell |
| LPDDR5 | 32–64 bytes | ≤ 256B |
| HBM2e/HBM3 | 32–256 bytes (pseudo-channel) | **= 256B payload** |
| QSPI Flash | 64–256 bytes (page: 256B) | **= 256B payload** |
| On-chip SRAM | Cache line: 64 bytes (industry standard) | ≤ 256B, 4× cache lines in one cell |

The 256-byte payload **exactly matches one QSPI page and one HBM max burst**, while consolidating 4 DDR5 bursts into a single cell — moved without additional routing decisions.

**Summary:** the 256B payload + 256-bit L0 link combination is the right decision. Variable link occupancy means small messages (≤48 bytes, ~80%) occupy only 2–3 flits — faster than the old system. Large messages (state migration, code-load) fragment into 4× fewer cells.

### Addressing: 24-bit Hierarchical

```
HW address: [region:4-6].[tile:3-4].[cluster:3-4].[core:4] = 18 bits (of 24)
Actor ID:   software-dispatched (payload bytes, not part of the HW address)
```

The hardware address routes cells to a **core**, not to an individual actor. Actor dispatch is handled in software by the destination core's local scheduler — the actor ID is carried in the cell payload. This design allows the actor count per core to vary by core type, SRAM size, and workload without a fixed hardware limit. The remaining 6 bits (24 − 18) are reserved for future addressing extensions. See [Architecture — Actor Scheduling Pipeline](architecture-en.md#actor-scheduling-pipeline) for details.

Routing decisions are O(1): the address prefix immediately determines which level's crossbar/mesh to forward to.

### Hybrid Switching: Wormhole (L0) + Virtual Cut-Through (L1–L3)

The CFPU uses two switching modes, matched to each hierarchy level:

**L0 (mesh) — Wormhole routing:** the header flit (256 bits, containing the destination address) is forwarded immediately after route computation; body flits follow in a pipeline, one per cycle. A max 272-byte cell = max 9 flits on the 256-bit link (1 header + 8 payload). For H hops, the header traverses the mesh in 2H cycles (2-cycle router pipeline: route + switch), and the last body flit arrives up to 8 cycles later. **Worst case: 2H + 8 cycles. Typical (48B payload): 2H + 1 cycles.**

**L1–L3 (crossbars) — Virtual Cut-Through (VCT):** the cell is fully buffered at the crossbar input before switching. The iSLIP scheduler reads the header during reception (1-cycle overlap), then the cell is forwarded in one crossbar cycle. VCT preserves the deadlock-freedom property of store-and-forward (no chained buffer reservation) while allowing pipelined header inspection.

### Virtual Output Queuing (VOQ)

Each input port maintains a separate queue **per output port**. If we are blocked toward port A, packets destined for port B proceed unimpeded. Throughput: ~58% (simple FIFO) → **~99% (VOQ)**.

**Cost-benefit:** VOQ costs ~900 gate-equivalents (extra gates) but gains ~3,800 effective cores (due to throughput improvement). A clear win.

### iSLIP Scheduler

Nick McKeown's algorithm (Stanford, 1999): schedules the maximum number of parallel transfers with round-robin fairness, in **1 clock cycle**. ~3,000 gates — negligible cost.

### Credit-Based Flow Control

Every link advertises in advance how many cells it can accept (4 credits/channel). The sender only transmits with available credits — congestion does not propagate through the network.

### Deadlock Freedom

**Wormhole (L0) + VCT (L1–L3) + VOQ + credit-based flow control = deadlock-free by construction.**

- **L0 mesh:** XY dimension-ordered routing creates a total order on channels — no cyclic dependency can form (Dally & Seitz, 1987). Wormhole is safe here precisely because the routing function is acyclic.
- **L1–L3 crossbars:** VCT means the cell is fully buffered before switching — no chained buffer reservation across hops. VOQ prevents HOL-blocking spillover. Credit-based flow control prevents buffer overflow.

The combination eliminates deadlock at every level without requiring Virtual Channels or additional routing constraints beyond the natural XY order at L0.

## Per-Level Details

### L0: Cluster (4×4 mesh, 16 cores)

| Parameter | Value |
|-----------|-------|
| Topology | 4×4 mesh, XY routing |
| Cores | 16 cores (any single type per cluster) |
| Physical size | ~1.1 mm × 1.1 mm (5nm) |
| Link type | Parallel, 256-bit, 1× core clock |
| Wire length | ~330 µm (neighboring core) |
| Max hops | 6 |
| Router area / core | 0.001–0.006 mm² (see L0 Router Variants) |
| Gateway | Uplink port integrated into corner core router |

#### L0 Router Variants

The L0 router is the largest per-core overhead in the CFPU. The original 5-port baseline router (~44,300 GE ≈ 0.011 mm²) was designed for Rich Core clusters. For smaller core types (Nano, Actor, Matrix), this router would consume more area than the core itself. Therefore, the CFPU defines two router variants, selected per-cluster via the `ROUTER_VARIANT` RTL parameter.

**Baseline router breakdown (5-port, Rich Core):**

| Component | GE | Function |
|-----------|---:|----------|
| Crossbar (5×5, 272 B) | 2,950 | Input→output data switching |
| VOQ logic (5×5×4 = 100 slots) | 5,000 | Enqueue/dequeue, pointers, flags |
| VOQ SRAM (100 × 272 B = 27 KB) | 14,700 | Cell storage |
| iSLIP scheduler (5×5) | 3,000 | Round-robin fair scheduling |
| XY routing | 1,000 | Address → direction decode |
| Credit flow control (5 × 4 credits) | 2,000 | Overflow prevention |
| 2 VN demux | 2,000 | Control / Actor traffic separation |
| Cell assembly + CRC-8 | 1,670 | Cell framing, integrity |
| Misc control | 12,000 | FSM, reset, power-gate interface |
| **Total** | **~44,300** | **≈ 0.011 mm²** |

> **Area convention:** GE-to-area conversion assumes ~0.21 µm²/GE at 5nm (logic + routing overhead), SRAM uses dense 6T cells (~0.021 µm²/bit). These estimates are pre-synthesis; final area will be determined by RTL synthesis (F4+). The baseline router is sized for 272-byte cells (16B header + max 256B payload).

**Variant A: Turbo — Speed > Area**

Optimizes for throughput and latency. Reduces area without sacrificing performance.

| Change | Rationale | Speed impact |
|--------|-----------|--------------|
| Heterogeneous port count (corner=3, edge=4, inner=5) | Not all mesh nodes need 5 ports. Average: 4.0 ports. | None |
| VOQ depth 3 (not 4) | 25% less buffer SRAM | Throughput: 99% → 98% |
| iSLIP retained | 3,000 GE for near-optimal throughput | None |
| 2 VN retained | Control plane isolation is critical | None |
| Credits: 3 (not 4) | 1 fewer register per port | Negligible |

**Result: ~26,000 GE ≈ 0.006 mm²** (−41% GE, −36% area vs baseline)

**Variant B: Compact — Area > Speed**

Aggressively minimizes router area. Accepts moderate throughput reduction.

| Change | Rationale | Speed impact |
|--------|-----------|--------------|
| Heterogeneous port count | Same as Turbo. Average: 4.0 ports. | None |
| VOQ → 2 queues/input (priority + normal) | Full VOQ is the largest area cost. Priority queue serves as VN0 equivalent. | Throughput: 99% → ~75%, moderate HOL blocking |
| iSLIP → fixed-priority round-robin | 1 arbiter per output instead of N×N iSLIP matrix | Slightly less fair under burst |
| 1 VN + priority bit (not 2 VN) | Priority bit in header; priority cells jump the queue | Control plane ~95% isolated |
| Credits: 2 (not 4) | More stalls under burst | Minor |
| Queue depth: 2 (not 4) | Minimal buffering | More stalls under burst |

**Result: ~14,500 GE ≈ 0.003 mm²** (−67% GE, −64% area vs baseline)

**Variant C: Systolic — ML/SNN > General Purpose**

Dedicated ML/SNN pipeline router. Two 128-bit unidirectional links (W→E activation, N→S weight loading), without XY routing, VOQ, or iSLIP. The freed wire budget is spent on wider (128-bit) forward links to feed the MAC array at full speed.

| Change | Rationale | Speed impact |
|--------|-----------|--------------|
| 2 directions (W→E, N→S), 128-bit | Systolic pipeline fixed data flow | Systolic-dedicated bandwidth (128 bit/cc, half of 256-bit L0, sufficient for systolic) |
| VOQ removed | No routing conflict in systolic mode | No negative impact |
| iSLIP removed | No arbitration, fixed directions | No negative impact |
| XY routing removed | Fixed directions, no routing decisions | No negative impact |
| 2 VN → control uplink only | Data on systolic link, control on thin uplink | Control ~95% isolated |
| Credits: 4 | Backpressure on 128-bit link | None |

**Result: ~5,000 GE ≈ 0.001 mm²** (−81% vs Turbo, −93% vs baseline)

**Router breakdown (~5,000 GE):**

| Component | GE | Function |
|-----------|---:|----------|
| Data path MUX (2 × 128-bit) | 1,000 | Local ↔ pass-through switching |
| FIFO (2 directions × 2 slots × 272B) | 600 | Minimal buffering |
| Credit flow control (2 × 4 credits) | 400 | Backpressure |
| Control uplink (thin, VN0 only) | 1,500 | Code loading, supervisor |
| Cell assembly + CRC-8 | 500 | Cell integrity |
| Misc control | 1,000 | FSM, reset |
| **Total** | **~5,000** | **≈ 0.001 mm²** |

**Link structure (~274 wires/core):**

```
W → [128 bit activation] → E     128 wires + 4 credit = 132
N → [128 bit weight load] → S    128 wires + 4 credit = 132
Control uplink                    ~10 wires
───────────────────────────────────────
Total:                            ~274 wires/core
```

This is **fewer** than Turbo (~600 wires/core) but sufficient bandwidth for systolic pipeline.

**Cell serialization on Systolic Wide link:** max 272 bytes = 2176 bits → ⌈2176/128⌉ = 17 flits. Neighbor worst-case latency: ~19 cc (2 hop pipeline + 17 body drain). Model: 2H + (flits-1). Typical 48B payload: 64 bytes = 512 bits → ⌈512/128⌉ = 4 flits, latency: 2H + 3 = 5 cc.

The Systolic variant is **not general purpose** — it is exclusively for ML/SNN workloads where data flow direction is known at compile time. General actor workloads require the Turbo or Compact variant.

**How it differs from other variants:**
- No XY routing (fixed directions: W→E, N→S)
- No VOQ (systolic pipeline is synchronous, no conflict)
- No iSLIP (no arbitration, fixed data flow)
- No 2 VN (control uplink only)
- 128-bit data path (vs 256-bit Turbo/Compact)
- 2 directions (vs 4–5 Turbo/Compact)

**Speed comparison:**

| Metric | Turbo | Compact | **Systolic** |
|--------|:-----:|:-------:|:------------:|
| Bandwidth / link | 256 bit/cc | 256 bit/cc | **128 bit/cc** |
| Sustained throughput | ~98% | ~75% | **~95% (systolic)** |
| Neighbor latency (worst case) | ~10 cc | ~12–14 cc | **~19 cc** |
| Neighbor latency (typical 48B) | ~3 cc | ~5–7 cc | **~5 cc** |
| Worst-case intra-cluster | ~20 cc | ~23–27 cc | **~19 cc (1 hop)** |
| MAC utilization (ws) | ~15% | ~12% | **~100%** |
| Communication | Any-to-any | Any-to-any | **W→E, N→S only** |
| Control plane isolation | Full (VN0) | Priority bit (~95%) | Control uplink (~95%) |

*(ws = weight-stationary)*

**Recommended variant per core type:**

| Core type | Variant | Router area | Router / core | Rationale |
|-----------|:-------:|------------:|--------------:|-----------|
| **Nano** | Compact | 0.003 mm² | 38% | Core is tiny (0.008 mm²); simple actors rarely saturate 75% throughput |
| **Actor** | Compact | 0.003 mm² | 13% | Message processing time >> network transit; 75% throughput rarely bottlenecks |
| **Matrix (actor)** | Turbo | 0.006 mm² | 43% | General actor workload on Matrix core |
| **Matrix (ML/SNN)** | **Systolic** | **0.001 mm²** | **7%** | Systolic pipeline: 128-bit link → MAC ~100% utilization |
| **Rich** | Turbo | 0.006 mm² | 10% | Core is large enough (0.059 mm²) that Turbo overhead is acceptable |

**Corrected core counts (5nm, 800 mm²):**

The original core counts in [`core-types-en.md`](core-types-en.md) were computed as `die_area / (core + SRAM)` with a flat efficiency factor, without explicitly accounting for the per-core router area. The corrected counts include the recommended router variant plus per-core share of L1–L3 infrastructure (~0.006 mm²):

| Core type | Core+SRAM | Router | Infra | **Node** | **Count** | Δ vs Turbo |
|-----------|----------:|-------:|------:|---------:|---------:|--:|
| Nano (4 KB) | 0.008 | 0.003 | 0.006 | 0.017 | **~47,000** | — |
| Actor (64 KB) | 0.023 | 0.003 | 0.006 | 0.032 | **~25,000** | — |
| Matrix Turbo (8 KB) | 0.014 | 0.006 | 0.006 | 0.026 | **~30,800** | — |
| **Matrix Systolic (8 KB)** | **0.014** | **0.001** | **0.006** | **0.021** | **~38,100** | **+24%** |
| Rich (256 KB) | 0.059 | 0.006 | 0.006 | 0.071 | **~11,300** | — |

> **Note:** The Systolic variant enables +24% more Matrix cores compared to Turbo, thanks to the router's 83% area reduction. All counts are pre-synthesis estimates.

### L1: Tile (crossbar, 8 clusters)

| Parameter | Value |
|-----------|-------|
| Topology | 8×8 crossbar (VOQ + iSLIP) |
| Placement | Geometric center of the tile |
| Physical size | ~3.2 mm × 3.2 mm (5nm) |
| Link type | Parallel, 84-bit |
| Max distance (GW → crossbar) | ~1.6 mm |
| Hop count | Always 1 (deterministic) |
| Gate count | ~16,000 |
| VOQ buffer | ~30 KB SRAM |

### L2: Region (crossbar, 8 tiles)

| Parameter | Value |
|-----------|-------|
| Topology | 8×8 crossbar (VOQ + iSLIP) |
| Placement | Geometric center of the region |
| Physical size | ~9 mm × 9 mm (5nm) |
| Link type | Serial `SERDES_RATIO`×, `SERIAL_WIRES` wires + clock |
| Max distance (tile GW → crossbar) | ~4.5 mm |
| Hop count | Always 1 (deterministic) |
| Gate count | ~16,000 |
| VOQ buffer | ~30 KB SRAM |

### L3: Chip (star, Seal Core + crossbar)

| Parameter | Value |
|-----------|-------|
| Topology | Star — every region connects directly to the center |
| Placement | Geometric center of the chip, co-located with Seal Core |
| Physical size | ~28 mm × 28 mm (5nm, 800 mm²) |
| Link type | Serial `SERDES_RATIO`×, `SERIAL_WIRES` wires + clock |
| Max distance (region GW → center) | ~14 mm |
| Hop count | Always 2 (region → center → region) |
| Gate count | ~42,000 (crossbar) + ~200,000 (Seal Core) |
| VOQ buffer | ~77 KB SRAM |

## Seal Core Placement

The Seal Core is co-located with the L3 crossbar at the **geometric center** of the chip. This placement is driven by **network topology**, not physical tamper resistance:

- **Minimal wire length:** the star topology center minimizes the maximum distance from any region gateway (~14 mm at 5nm), yielding deterministic latency.
- **Cross-region inspection point:** all cross-region traffic passes through the L3 crossbar, enabling the Seal Core to perform security inspection (AuthCode verification, traffic monitoring) without additional routing.
- **Single RTL instantiation:** the Seal Core + L3 crossbar form a single parameterizable block at the chip center — no special placement logic needed.

Unified with the L3 crossbar, all cross-region traffic passes through the Seal Core — enabling security inspection.

> **Note on physical tamper resistance:** The center placement does **not** constitute physical protection against microprobing, FIB, laser fault injection, or EM side-channel attacks. Modern physical attacks (e.g., backside FIB through the silicon substrate) can target any die position. Physical tamper resistance requires dedicated countermeasures (active mesh shielding, voltage/light/frequency sensors, encrypted buses) — these are a separate design layer, currently out of scope (see `docs/security-en.md`, "What we do NOT protect").

## Power Domains

Each hierarchy level has its own power domain — power consumption of sleeping units is ~0:

| Unit | Power state | When asleep? | Wake trigger |
|------|-------------|--------------|--------------|
| Core (Nano/Actor/Rich) | Per-core clock gating | Empty mailbox | Mailbox interrupt (cell arrival) |
| Rich Core FPU | Separate power domain | No FP operations | FP opcode detected |
| Cluster (16 cores) | Per-cluster power gating | All 16 cores asleep | Cell arriving for any core |
| Tile (L1 crossbar + clusters) | Per-tile power gating | All 8 clusters asleep | Cell addressed to any cluster |
| Region (L2 crossbar + tiles) | Per-region power gating | All 8 tiles asleep | Cell addressed to any tile |
| **L3 crossbar** | **Power-gated** | No cross-region traffic | Any region GW sends a cross-region cell |
| **Seal Core** | **Power-gated** | No code loading | Code-load request (boot, hot code, migration) |

At the chip center **everything can sleep** — the L3 crossbar and Seal Core are both power-gated, wake-on-demand. The crossbar's ~40k gate static current is negligible, but if there is no cross-region traffic it can be powered off as well.

## Seal Core Capacity

The Seal Core serves two functions: **code authentication** (infrequent but heavy) and **L3 crossbar routing** (the L3 crossbar handles routing autonomously; the Seal Core crypto engine is not involved).

### Code Authentication Load

| Operation | When | Seal Core load |
|-----------|------|----------------|
| Boot (all core code) | Once, at startup | ~128 MB hash = ~256 ms @ 500 MHz |
| Hot code loading | ~10/sec chip-wide | ~160 KB/s = **<0.1%** utilization |
| Actor migration | ~1–100/sec | Negligible |

### L3 Crossbar Scaling Limit

| Core count | Cross-region traffic | L3 crossbar utilization | Bottleneck? |
|------------|----------------------|--------------------------|-------------|
| 2,000 | ~2.5 GB/s | ~6% | No |
| 8,192 | ~10 GB/s | ~25% | No |
| 18,432 | ~23 GB/s | ~58% | Not yet |
As core count grows, cross-region traffic increases proportionally. At 8,192 cores the L3 crossbar runs at ~25% utilization — significant headroom remains. Larger chips (F6+) may include **2–64 Seal Cores** for redundancy and parallel AuthCode verification (see [Seal Core](sealcore-en.md)).

### L3 Crosspoint Fault Tolerance

The L3 crossbar is an N×N iSLIP switch (N = `REGIONS`, typically 8). Internally it consists of N² crosspoints — each crosspoint is a single input→output connection. If one crosspoint fails, the affected path is a **single directional route** between two regions (e.g., R2→R4), while all other region pairs remain operational.

#### Failure Model

```
        Output (destination region)
        R0  R1  R2  R3  R4  R5  R6  R7
Input ┌───┬───┬───┬───┬───┬───┬───┬───┐
  R0  │ — │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │
  R1  │ ✓ │ — │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │
  R2  │ ✓ │ ✓ │ — │ ✓ │ ✗ │ ✓ │ ✓ │ ✓ │  ← R2→R4 crosspoint dead
  R3  │ ✓ │ ✓ │ ✓ │ — │ ✓ │ ✓ │ ✓ │ ✓ │
  ...
```

- **R2→R4** traffic cannot pass (dead crosspoint)
- **R4→R2** still works (separate crosspoint)
- **All other region pairs** unaffected
- Without mitigation: R4-destined cells accumulate in R2's VOQ → backpressure → cores in R2 targeting R4 stall

#### Mitigation: Relay via Neighbor Region

The iSLIP scheduler maintains a **fault bitmap** — one bit per crosspoint (N² = 64 bits for 8 regions). The bitmap is set at boot via BIST (Built-In Self-Test) or updated at runtime when a crosspoint fails to acknowledge within a timeout window.

When the scheduler detects that the direct crosspoint is marked faulty, it performs a **relay**:

```
R2 ─╳→ R4           (direct path — dead crosspoint)
R2 → R3 → L3 → R4   (relay: R3 acts as intermediate hop)
```

**Relay mechanism:**

1. The scheduler selects an **alternate output port** (the relay region) from a pre-computed relay table
2. The cell is forwarded to the relay region's GW with a **relay flag** set in the header's flags field (bit 6)
3. The relay region GW re-injects the cell into the L3 crossbar toward the original destination
4. The destination region receives the cell normally — the relay is transparent to cores

**Relay region selection:** The scheduler picks the relay region that has a working crosspoint from the source AND to the destination. With 8 regions and 1 dead crosspoint, there are always 6 valid relay candidates.

#### Cost Analysis

| Component | Gate cost | SRAM cost | Notes |
|-----------|-----------|-----------|-------|
| Fault bitmap register | ~130 gates | — | 64 FF + read logic |
| Relay table (precomputed) | ~200 gates | — | 8×3-bit best-relay LUT |
| Scheduler modification | ~300 gates | — | Bitmap check + relay path selection |
| Header relay flag | 0 | 0 | flags[6] relay bit (dedicated) |
| **Total** | **~630 gates** | **0** | **< 1.5% of L3 crossbar** |

#### Performance Impact

| Scenario | Latency | Throughput |
|----------|---------|------------|
| No fault | 2 hops (unchanged) | 100% |
| 1 crosspoint fault, relayed | 4 hops (source→relay→center→dest) | ~50% for the affected pair, 100% for all others |
| Multiple faults | Degrades gracefully — each faulty pair uses relay | Throughput reduction proportional to relay traffic |

The relay adds 2 extra crossbar traversals for the affected region pair. At typical cross-region loads (~25% utilization), even multiple relayed pairs do not saturate the crossbar.

#### Detection: Crosspoint Health Monitoring

- **Boot-time BIST:** each crosspoint is tested with a known pattern; failures are recorded in the fault bitmap before normal operation begins
- **Runtime watchdog:** if a cell granted to a crosspoint does not produce an output-side acknowledgment within 4 cycles, the crosspoint is marked faulty and future cells are relayed
- **Seal Core notification:** crosspoint faults are reported to the Seal Core as a diagnostic event (logged, optionally forwarded off-chip via management interface)

## Code Loading over the Network

The communication network does not only carry actor messages — **program code** also reaches core SRAM through the same network. Three scenarios:

| Scenario | Size | When | Path |
|----------|------|------|------|
| **Boot** | Full program, KB–MB | System startup | Flash → Seal Core (AuthCode verify) → L3 → L2 → L1 → broadcast to all cores |
| **Hot code loading** | 1 method, 256B–16KB | At runtime | Flash/Rich Core → Seal Core (re-auth) → targeted core |
| **Actor migration** | Actor state + code, KB | At runtime | Source core → Seal Core (re-auth) → destination core |

**All code passes through the Seal Core** — unauthenticated code cannot reach any core. The star topology provides this for free: the Seal Core is at the center of the L3 crossbar, so all cross-region traffic passes through it.

Code loading is normal 272-byte cell traffic on the VN0 (control) channel. A 16 KB method = ~64 cells (256-byte payload each); pipeline throughput is limited by the narrowest link (L0, 256-bit @ 500 MHz = ~16 GB/s). Worst-case delivery: ~1.3 µs @ 500 MHz.

## Quench-RAM Integration with the Network

The [Quench-RAM](quench-ram-en.md) memory-security layer and the packet-switched network **reinforce each other**. Because of the shared-nothing model, the QRAM invariant does not need to be synchronized across the network — each core manages its own QRAM locally.

### Message sending (SEND) — with QRAM semantics

```
SEND(dst_actor, payload_block):
  1. SEAL(payload_block)            ← payload becomes immutable (source core QRAM)
  2. Copy → 272-byte cell(s)         ← placed on the network (wormhole at L0, VCT at crossbars)
  3. Cells → router → ... → destination core SRAM
  4. Destination core: block alloc  ← QRAM: guaranteed zero-init (RELEASE invariant)
  5. Cell contents → new block      ← in destination core QRAM
  6. Source: GC_SWEEP → RELEASE     ← atomic wipe, old data physically destroyed
```

| Phase | Source core QRAM | Network | Destination core QRAM |
|-------|-----------------|---------|----------------------|
| Before send | Mutable (actor writes) | — | — |
| SEAL trigger | **Immutable** → cannot change during send | — | — |
| In transit | — | Wormhole (L0) / VCT (crossbars) cells, copy | — |
| On arrival | — | — | Allocation: **guaranteed zero** (RELEASE invariant) |
| Processing | — | — | **SEAL** (capability tag tamper-proof) |
| GC | **RELEASE** → atomic wipe | — | — |

### Code loading — with QRAM semantics

```
Flash → Seal Core (AuthCode verify) → network → destination core CODE region → SEAL

CODE region after SEAL is IMMUTABLE:
  → self-modifying code is physically impossible
  → hot_code_loader: RELEASE (atomic wipe) → new code load → SEAL
```

### Why do they reinforce each other?

- **Source side:** SEAL guarantees that the data being sent cannot change during copying
- **Destination side:** RELEASE invariant guarantees zero-init — no information leak from previous use
- **Network:** only cells, no pointers, no shared state → the QRAM invariant **cannot be violated** during transfer
- **Code:** SEAL-ed CODE region is immutable → running code cannot be modified; hot code loading is an atomic swap via RELEASE

The shared-nothing network model and Quench-RAM are in **symbiosis**: QRAM works locally (per-core) precisely because the network carries copies, not pointers.

## Virtual Networks (VN)

2 VNs for traffic isolation:

| VN | Name | Traffic | Priority |
|----|------|---------|----------|
| **VN0** | Control | Supervisor restart, trap signal, heartbeat, system broadcast | Highest — preemptive |
| **VN1** | Actor | Normal actor message exchange, data traffic | Normal |

VN0 guarantees that supervisor messages **never wait** behind normal traffic.

## Multicast

HW multicast **only in cluster gateways** (L1 crossbar, not in every L0 router). Supervisor restart and SNN fan-out are efficient: 1 multicast packet notifies all cores in 1 cluster in ~5 cycles (vs. N×unicast = ~192 cycles).

**Cost:** +2,500 gates × (CLUSTERS_PER_TILE × TILES_PER_REGION × REGIONS) gateways = negligible at chip level.

## Link Types

| Level | Type | Wires | Clock | Bandwidth |
|-------|------|-------|-------|-----------|
| L0 Turbo/Compact | Parallel | 256-bit (unidirectional) | 1× core | ~16 GB/s |
| **L0 Systolic** | **Parallel** | **128-bit (unidirectional, 2 directions)** | **1× core** | **~8 GB/s** |
| L1 (cluster → tile xbar) | Parallel | 84-bit (bidirectional) | 1× core | ~5.2 GB/s |
| L2 (tile → region xbar) | Serial | `SERIAL_WIRES` + clock | `SERDES_RATIO`× core | see SerDes Scaling |
| L3 (region → chip xbar) | Serial | `SERIAL_WIRES` + clock | `SERDES_RATIO`× core | see SerDes Scaling |

## SerDes Scaling

The L2/L3 serial links use on-chip SerDes with a configurable multiplier (`SERDES_RATIO`). The maximum feasible ratio depends on the core clock frequency — higher clocks require lower ratios to keep the SerDes frequency within silicon limits.

**Constraint:** on-chip SerDes IP at 5nm typically supports up to ~25–32 Gbps/lane. The SerDes frequency = core_clock × `SERDES_RATIO` must stay below this limit.

| Core clock | Max `SERDES_RATIO` | Recommended config | Effective L2/L3 link width | L2/L3 serialization |
|-----------|-------------------|-------------------|---------------------------|---------------------|
| 500 MHz | 12 | 10×, 8 wires | 80 bit/cc | 8 cc |
| 1 GHz | 10 | 8×, 8 wires | 64 bit/cc | 10 cc |
| 2 GHz | 8 | 6×, 8 wires | 48 bit/cc | 14 cc |
| 3 GHz | 6 | 4×, 12 wires | 48 bit/cc | 14 cc |
| 5 GHz | 4 | 4×, 16 wires | 64 bit/cc | 10 cc |

**Compensation strategy:** at higher core clocks, reduce `SERDES_RATIO` and increase `SERIAL_WIRES` to maintain effective link bandwidth. The product `SERDES_RATIO × SERIAL_WIRES` determines the effective bits/core-cycle; the reference target is **80 bit/cc**.

### Area Impact of `SERIAL_WIRES` Scaling

Increasing `SERIAL_WIRES` from 8 to 16 is not free — it has measurable area and routing consequences:

| Component | 8 wires (ref) | 12 wires | 16 wires | Notes |
|-----------|--------------|----------|----------|-------|
| SerDes transceiver (per link endpoint) | ~3,000 GE | ~4,500 GE | ~6,000 GE | PLL shared, but CDR/EQ/driver per lane |
| L2 crossbar I/O mux | ~15,000 GE | ~18,000 GE | ~21,000 GE | Wider input/output ports |
| L3 crossbar I/O mux | ~40,000 GE | ~48,000 GE | ~56,000 GE | Same scaling |
| Physical wires (L3, ~14 mm) | 8 × 2 = 16 wires | 12 × 2 = 24 | 16 × 2 = 32 | Bidirectional; metal layer routing pressure |
| Physical wires (L2, ~4.5 mm) | 16 wires | 24 | 32 | Shorter, less critical |

**Chip-level impact at 16 wires (`SERIAL_WIRES`=16):**
- L2 crossbar area: +~40% (+6,000 GE × 8 tiles/region)
- L3 crossbar area: +~40% (+16,000 GE, single instance)
- Wire routing: L3 links carry 32 wires over ~14 mm — feasible at 5nm (metal pitch ~20 nm, total wire bundle ~0.64 µm wide), but consumes 1–2 dedicated metal layers regionally
- **Total chip area increase: <1%** — crossbar infrastructure is already a small fraction of total die area (~2–3%)

The area cost is acceptable precisely because the L2/L3 crossbar infrastructure is amortized across thousands of cores. The dominant area remains core SRAM.

> **L3 wire length constraint:** the L3 link spans up to ~14 mm (5nm). At 50 GHz (5 GHz × 10×), wire propagation delay alone is ~2–3 ns ≈ 100–150 bit times, requiring multi-stage retiming. Keeping the SerDes frequency ≤ 20 GHz avoids this complexity.

## Hop Count and Latency Summary

Latencies are for the **reference configuration** (500 MHz, `SERDES_RATIO`=10, `SERIAL_WIRES`=8, effective L2/L3 = 80 bit/cc), zero contention. The "typical" column is for 48B payload (the most common actor message size), "worst case" is for 256B payload. Higher core clocks with adjusted SerDes parameters yield similar cycle counts (see SerDes Scaling).

**L0 wormhole model (256-bit link):** 2 cycles/hop router pipeline + payload_flits body flit drain = 2H + payload_flits cycles for H hops. Typical 48B: 2H + 2. Worst case 256B: 2H + 8.
**Crossbar VCT model:** link serialization (⌈cell_bits / link_width⌉ cycles) + 1 cycle iSLIP per crossbar. Output serialization overlaps with next stage's input.

| Path | Hops | Typical (48B) | Worst case (256B) | @500 MHz (typical) |
|------|------|--------------|-------------------|-------------------|
| Neighboring core (L0) | 1 | ~4 cycles | ~10 cycles | 8 ns |
| Cross-cluster, same tile (L0+L1+L0) | 6+1+6 = 13 | ~43 cycles | ~93 cycles | 86 ns |
| Cross-tile, same region (L0+L1+L2+L1+L0) | 6+1+1+1+6 = 15 | ~73 cycles | ~203 cycles | 146 ns |
| Cross-region (L0+L1+L2+L3+L2+L1+L0) | 6+1+1+2+1+1+6 = 18 | ~103 cycles | ~317 cycles | 206 ns |

> **Context:** typical ~206 ns on-chip (48B payload) is competitive with software actor message delivery on conventional CPUs (Erlang/BEAM: ~0.5–2 µs), while the CFPU runs thousands of independent hardware cores in parallel. The worst-case 317 cycles (634 ns) applies to rare 256B payloads — variable link occupancy means ~80% of messages travel at typical latency.

<details>
<summary>Cross-region latency breakdown (18 hops, typical 48B payload)</summary>

| Segment | Link width | Cycles | Notes |
|---------|-----------|--------|-------|
| Source L0 wormhole (6 hops) | 256-bit | 14 | 2×6 + 2 body drain (48B = 2 payload flits) |
| L1 link (GW → xbar) | 84-bit | 7 | ⌈512/84⌉ (64B cell = 512 bits) |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link (xbar → tile GW) | 84-bit | 7 | |
| L2 link (tile GW → xbar) | 80-bit | 7 | ⌈512/80⌉ |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link (xbar → region GW) | 80-bit | 7 | |
| L3 link (region GW → xbar) | 80-bit | 7 | |
| L3 crossbar (iSLIP) | — | 1 | |
| L3 link (xbar → dst region GW) | 80-bit | 7 | |
| L2 link → xbar | 80-bit | 7 | |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link → dst tile GW | 80-bit | 7 | |
| L1 link → xbar | 84-bit | 7 | |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link → dst cluster GW | 84-bit | 7 | |
| Destination L0 wormhole (6 hops) | 256-bit | 14 | 2×6 + 2 body drain |
| **Total** | | **~103** | |

</details>

<details>
<summary>Cross-region latency breakdown (18 hops, worst case 256B payload)</summary>

| Segment | Link width | Cycles | Notes |
|---------|-----------|--------|-------|
| Source L0 wormhole (6 hops) | 256-bit | 20 | 2×6 + 8 body drain (256B = 8 payload flits) |
| L1 link (GW → xbar) | 84-bit | 26 | ⌈2176/84⌉ (272B cell = 2176 bits) |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link (xbar → tile GW) | 84-bit | 26 | |
| L2 link (tile GW → xbar) | 80-bit | 28 | ⌈2176/80⌉ |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link (xbar → region GW) | 80-bit | 28 | |
| L3 link (region GW → xbar) | 80-bit | 28 | |
| L3 crossbar (iSLIP) | — | 1 | |
| L3 link (xbar → dst region GW) | 80-bit | 28 | |
| L2 link → xbar | 80-bit | 28 | |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link → dst tile GW | 80-bit | 28 | |
| L1 link → xbar | 84-bit | 26 | |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link → dst cluster GW | 84-bit | 26 | |
| Destination L0 wormhole (6 hops) | 256-bit | 20 | 2×6 + 8 body drain |
| **Total** | | **~317** | |

</details>

## Node Scaling

The RTL is parameterizable — die size and process node determine core count.

**A) Growing SRAM (richer actors, fewer cores):**

| Node | Core area | SRAM/core | 800 mm² | 1,400 mm² | Levels |
|------|-----------|-----------|---------|-----------|--------|
| 130nm | 1.06 mm² | 16 KB | 588 | 1,030 | 2 |
| 28nm | 0.18 mm² | 64 KB | 3,467 | 6,067 | 3 |
| 7nm | 0.083 mm² | 256 KB | 7,518 | 13,157 | 4 |
| **5nm (ref)** | **0.103 mm²** | **512 KB** | **6,058** | **10,602** | **4** |

**B) Fixed 256 KB SRAM (maximum parallelism):**

| Node | Core area | SRAM/core | 800 mm² | 1,400 mm² | Levels |
|------|-----------|-----------|---------|-----------|--------|
| 130nm | 2.93 mm² | 256 KB | 213 | 373 | 2 |
| 28nm | 0.37 mm² | 256 KB | 1,686 | 2,951 | 3 |
| 7nm | 0.083 mm² | 256 KB | 7,518 | 13,157 | 4 |
| **5nm (ref)** | **0.059 mm²** | **256 KB** | **10,576** | **18,508** | **4** |

The choice depends on the workload — the RTL `SRAM_KB_PER_CORE` parameter is set at fabrication time.

Typical cross-region latency is ~103 cycles (206 ns @ 500 MHz) for 48B payloads, worst-case 256B payloads ~317 cycles (634 ns) — smaller cluster physical size at advanced nodes partially compensates for the deeper hierarchy.

## Excluded Alternatives (and Rationale)

| Alternative | Why excluded |
|-------------|-------------|
| Shared memory / zero-copy cell pool | Security vulnerability — pointer manipulation, side-channel, isolation violation |
| Adaptive routing (2 VC) | Costs ~800 gate-equivalents; latency improvement does not compensate |
| In-network computation | 44% router area; core count halved |
| Fat tree (pure) | Bottleneck and SPOF at root; converges to hierarchical mesh with horizontal links |
| Dragonfly | On-chip all-to-all wire demand ~12× that of mesh — unrealistic |
| Flat mesh (10k nodes) | Max ~200 hops — unacceptable latency |
| Full wormhole (all levels) | Chained buffer reservation at crossbar levels; used only at L0 where XY routing guarantees acyclic channels |
| 3+ VNs | Extra buffer area does not justify marginal QoS improvement |

## OSREQ Cross-References

This document addresses the following Symphact hardware requirements:

| OSREQ | Topic | Status |
|-------|-------|--------|
| [OSREQ-001](osreq-from-os/osreq-001-tree-interconnect-hu.md) | Interconnect topology | **Closed**: 4-level hierarchical mesh + crossbar |
| [OSREQ-004](osreq-from-os/osreq-004-dma-engine-hu.md) | DMA engine | Required from F4 onwards (large messages, actor state transfer) |
| [OSREQ-005](osreq-from-os/osreq-005-mailbox-interrupt-hu.md) | Mailbox interrupt | HW interrupt, triggered by cell arrival |

## Related Documents

- [Quench-RAM](quench-ram-en.md) — per-block immutability, atomic wipe-on-release, QRAM + network symbiosis
- [AuthCode](authcode-en.md) — code authentication; the Seal Core verifies the signature of every loaded code block
- [Architecture](architecture-en.md) — full CFPU microarchitecture overview
- [ISA-CIL-T0](ISA-CIL-T0-en.md) — the CIL-T0 instruction set specification

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 3.0 | 2026-04-28 | **Header v3.0:** 4×32-bit word-aligned layout. `src_actor`/`dst_actor` 16→8 bits (max 256 actors/core). `src_actor` writer: core scheduler→core HW (active actor context register, cannot be spoofed). `seq` 8→16 bits (max 65,536 fragments). `len[8]` = len+1 semantics (1–256 byte payload, no zero-byte payload). CRC-16 added (payload integrity, stored in header). `flags[8]` expanded: `[VN:1][relay:1][Pri:2][reserved:4]`. `reserved` 16→8 bits. HMAC and perms removed — HW-managed Capability Slot Table (CST) in QSRAM. **L0 link:** 42→256 bits (tile-level NoC, per `internal-bus-hu.md`). **Cell:** max 272 bytes (16B header + 256B payload). Flit model: on 256-bit link header=1 flit, worst case 2H+8, typical 2H+2. Latency tables recalculated (typical 48B + worst case 256B). Cross-region typical ~103 cc (206 ns), worst case ~317 cc (634 ns). L0 throughput ~16 GB/s (vs old ~2.6 GB/s) |
| 2.4 | 2026-04-22 | Header reorganization: `len[16]`→`len[8]`, `src_actor[16]` + `dst_actor[16]` added to header (N:M actor-to-core mapping, DDR5 CAM actor-level ACL, crash recovery). Variable link occupancy: only `len` payload bytes travel on the link (4-bit flit counter, ~43% average link savings), buffers remain fixed 80B slots. Latency tables updated (worst case annotation) |
| 2.3 | 2026-04-21 | L3 Crosspoint Fault Tolerance section: fault bitmap (64-bit), relay via neighbor region (~630 gates, <1.5% overhead), BIST + runtime watchdog detection, graceful degradation model |
| 2.2 | 2026-04-21 | Reference node changed from 7nm to 5nm. Recalculated: router areas (Turbo 0.006, Compact 0.003), core+SRAM sizes, corrected core counts (Nano ~47k, Actor ~25k, Matrix Turbo ~30.8k, Matrix Systolic ~38.1k, Rich ~11.3k), physical sizes (L0 1.1mm, L1 3.2mm, L2 9mm, L3 28mm), Seal Core wire length 14mm. Reference config: 16×8×8×10 = 10,240 cores |
| 2.1 | 2026-04-19 | Systolic router variant (Variant C): 128-bit unidirectional links (W→E, N→S), ~5,000 GE ≈ 0.001 mm², dedicated ML/SNN. Speed table, recommended variant table, corrected core counts, and link types updated |
| 2.0 | 2026-04-19 | Cell payload 128→64 bytes (cell size 144→80 bytes). 16 flits/cell, 2H+15 latency model, L1 8cc, L2/L3 8cc serialization, cross-region 139 cycles (278 ns). Router gate counts, VOQ SRAM, core counts recalculated. CELL_SIZE range: 64/128. Turbo: 0.007 mm², Compact: 0.004 mm² |
| 1.9 | 2026-04-19 | Cell header 8→16 bytes (128-bit, power-of-2). Cell size 136→144 bytes. All derived values recalculated: 28 flits/cell, 2H+27 latency model, L1 14cc, L2/L3 15cc serialization, cross-region 229 cycles (458 ns). VOQ SRAM and gate counts updated |
| 1.8 | 2026-04-19 | Addressing changed: actor field removed from HW address, software-dispatched via payload. Cross-reference to Architecture Actor Scheduling Pipeline |
| 1.7 | 2026-04-19 | SerDes Scaling section: `SERDES_RATIO` + `SERIAL_WIRES` configurable parameters, clock-dependent ratio table (500 MHz–5 GHz), L3 wire length constraint, compensation strategy. L2/L3 link specs parameterized |
| 1.5 | 2026-04-19 | L0 Router Variants: Turbo (speed-first, 0.009 mm²) and Compact (area-first, 0.005 mm²) with per-core-type recommendation. Corrected core counts including router area. Updated design principle #2 and L0 Cluster parameters |
| 1.4.1 | 2026-04-19 | Switching model corrected: hybrid wormhole (L0) + VCT (L1–L3) replaces pure store-and-forward. Latency table recalculated with serialization math (42-bit L0 = 28 flits/cell). Deadlock freedom argument updated (Dally & Seitz 1987 for wormhole + XY). Cross-region breakdown table added |
| 1.4 | 2026-04-18 | Matrix Core redefined: CIL-T0 + FP based (not Rich/Actor), no GC, no object model, no exceptions, no virtual dispatch. Core sizes updated (Matrix logic: 0.019 mm²), two Matrix rows (64KB/256KB), CFPU-ML product variant added, branching diagram |
| 1.3 | 2026-04-18 | Matrix Core added (5th core type: Nano + FPU + 4×4 MAC + SFU), CFPU-ML product variant, CORE_TYPE=MATRIX |
| 1.2 | 2026-04-18 | Core family (Nano/Actor/Rich/Seal), product family (CFPU-N/A/R/H/X), power domains, Seal Core capacity |
| 1.1 | 2026-04-18 | Added Code Loading over the Network and Quench-RAM Integration sections |
| 1.0 | 2026-04-18 | Initial version — 4-level hierarchy, mesh+crossbar hybrid, Seal Core center placement, node scaling |
