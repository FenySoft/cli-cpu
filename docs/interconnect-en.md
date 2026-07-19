---
status: vision
---

# CFPU Interconnect Architecture

> Magyar verzió: [interconnect-hu.md](interconnect-hu.md)

> Version: 3.8

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
| `CELL_SIZE` | Variable | 128 (default) | Max payload size (bytes) — `BUS_WIDTH`/8 × 8 |
| `BUS_WIDTH` | Variable | 128 (default) | L0 link width (bits), v3.1 default; 256/512/1024 for future upscale |
| `CORE_TYPE` | Variable | NANO/ACTOR/RICH/MATRIX | Application-dependent (mixed on heterogeneous chips) |
| `ROUTER_VARIANT` | Variable | TURBO/COMPACT/SYSTOLIC | Core type dependent (cluster-level) |
| `SERDES_RATIO` | Variable | 4–12 | Core clock dependent (see SerDes Scaling) |
| `SERIAL_WIRES` | Variable | 8–16 | Die size, wire budget |

## Switching Model

### ATM-Inspired Fixed Cell

Every message is segmented into **fixed cells** that travel through the network: **16-byte header + up to 128-byte payload = up to 144 bytes**. Buffers are fixed-size (144-byte slots), but **only the actual payload travels on the link** — the `len` field determines how many bytes are actually forwarded (`len` value + 1, i.e. 1–128 bytes; zero-byte payload does not exist, signaled via flags instead).

```
Cell = Header (16 bytes) + Payload (1-128 bytes) = 17-144 bytes on the link

Header (16 bytes = 128 bits = 4 × 32 bits) — stored in Header SRAM:
┌─────────────────────────────────────────────────────────────────────┐
│  Word 0:  dst[24] + dst_actor[8]                — target (HW+actor)│
│  Word 1:  src[24] + src_actor[8]                — source (HW+actor)│
│  Word 2:  seq[16] + flags[8] + len[8]           — control          │
│  Word 3:  reserved[8] + CRC-16[16] + CRC-8[8]  — integrity        │
│                                             Total: 128 bits         │
└─────────────────────────────────────────────────────────────────────┘

Payload (1-128 bytes) — stored in Payload SRAM:
┌────────────────────────────────────────────────────────────┐
│  1-128 bytes application data (determined by len+1)        │
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
| `flags` | 8 bits | Sender SW + HW | `[VN:1][relay:1][Pri:2][zero_len:1][ddr5_cap:1][reserved:2]` — VN0/VN1, relay flag, message priority (4 levels), zero-payload signal, **DDR5 capability flag (settable only by core HW, see `ddr5-architecture-hu.md` v1.3)**. Detailed bit allocation: [`specs/cell-format-en.md`](../specs/cell-format-en.md) v2.4 |
| `len` | 8 bits | Sender | Payload size: value + 1 byte (v3.1: max 128 bytes; the 8-bit field is reserved for future upscale, see `decision-bus-rollback-en.md`). Zero-byte payload does not exist, signaled via flags |
| `CRC-16` | 16 bits | HW | Payload integrity check (stored in header, computed over the payload) |
| `CRC-8` | 8 bits | HW | Header integrity check (last field, computed over the entire header including CRC-16) |
| `reserved` | 8 bits | — | Future extensions |

**Why `src_actor` / `dst_actor` in the header?** In v1.8, the actor ID was moved to the payload (software dispatch). With N:M actor-to-core mapping (multiple actors per core, including sleeping actors), having actor IDs in the header provides **hardware-level advantages**:
- **DDR5 capability slot** (`ddr5-architecture-hu.md` v1.3) — actor-level access right stored in the source core's QRAM; `src[24] + src_actor[8]` provides defence-in-depth at the controller
- **Crash recovery** — only the crashed actor's capabilities need to be revoked, not the entire core's
- **Router-level dispatch** — the receiving core's scheduler knows which actor the message is for from the header, without reading the payload
- **8 bits** — 256 actors / core, covers sleeping actors as well (in practice, 256 contexts/core is sufficient: warm-context cache holds 4–8 active + 248 sleeping actors)

**Capability model (v3.0):** Software **never sees raw `dst`/`src` addresses** — only a 32-bit CST index (Capability Slot Table). The sending core's HW resolves the CST index into header `dst` + `dst_actor` fields. The CST resides in QSRAM with actor-level permissions (`perms`). The sending HW checks permissions at send time — `perms` does not travel in the header. HMAC is also unnecessary in the header: the CST is HW-managed, software cannot directly manipulate raw addresses.

**Variable link occupancy:** router buffers are always fixed-size (144-byte slots), but **only the header + (len+1) payload bytes travel on the link**. The router computes the number of payload flits from the header's `len` field:

```
128-bit L0 data path (1 flit = 16 bytes):
  payload_bytes = len + 1                    ← 1–128 bytes
  payload_flits = ceil(payload_bytes / 16)   ← 4-bit right shift + carry
  total_flits = 1 (header) + payload_flits

Examples:
  len = 7   (8 bytes)   → 1 + 1 = 2 flits   (32 bytes on link, not 144)
  len = 15  (16 bytes)  → 1 + 1 = 2 flits   (32 bytes on link)
  len = 31  (32 bytes)  → 1 + 2 = 3 flits   (48 bytes on link)
  len = 47  (48 bytes)  → 1 + 3 = 4 flits   (64 bytes on link — typical actor message)
  len = 63  (64 bytes)  → 1 + 4 = 5 flits   (80 bytes on link)
  len = 127 (128 bytes) → 1 + 8 = 9 flits   (144 bytes on link, full cell)
```

**HW cost:** 4-bit counter per port + shift. No LUT, no tail bit, no link-width overhead.

**Impact on network throughput:** an estimated ~80% of actor messages have ≤48 byte payloads (**design assumption, not measured** — based on the typically small messages of Akka.NET/Erlang-style actor workloads; real distribution measurement scheduled for a future phase). With variable link occupancy, links are **occupied ~43% less on average**, nearly doubling effective network throughput.

**Split SRAM design:** header and payload are stored in **separate SRAMs** inside the router. This is natural because they serve different functions: the scheduler reads the header for routing decisions while the payload is still arriving — **1 cycle latency saving**. No port contention between scheduler and crossbar. Both SRAMs are power-of-2 aligned: header = slot × 16, payload = slot × 128 — simple shift addressing, no multiplier needed.

**Why 16-byte header?** 128 bits is the natural power-of-2 boundary, and **exactly 1 flit** on the 128-bit L0 bus — the header never occupies half a flit, no padding waste. The fields (dst, dst_actor, src, src_actor, seq, flags, len, CRC-16, CRC-8) require 120 bits, leaving 8 reserved bits for future extensions. The 4 × 32-bit word-aligned layout simplifies the HW parser. The 128-byte max payload is exactly 8 flits on the 128-bit L0 link, so the full cell is **1 + 8 = 9 flits** — header overhead is a constant 11%. The scaling rule (see `decision-bus-rollback-en.md`): `header = 1 flit = BUS_WIDTH/8 byte`, `max payload = 8 flit = 8 × header byte`. The 128-byte payload aligns with the DDR5 BL32 (×4 byte) burst size and is 2× the industry-standard SRAM cache line.

**Why fixed buffers, variable links?** Fixed buffer size yields deterministic buffer management and simple SRAM addressing (the ATM networks' foundational principle). Variable link occupancy **does not increase buffer complexity** — only the forwarding counter changes — while significantly improving link utilization.

### Why 128-byte Payload?

In v3.1, the max payload size is **128 bytes** (was 256 bytes in v3.0). For full rationale see [`decision-bus-rollback-en.md`](decision-bus-rollback-en.md). In short:

- **128-bit L0 bus:** the rollback from 256-bit is a conservative step for the F2.7 FPGA bring-up (Vivado/OpenXC7 routing — half the wire budget). The scaling rule (`header = 1 flit, payload = 8 flit`) is preserved; future upscale (256/512/1024-bit) via the `BUS_WIDTH` parameter.
- **Header is exactly 1 flit:** 16 bytes = 128 bits = 1 flit on the 128-bit link — no padding waste in the header flit (in v3.0 the 256-bit bus had the header occupying half a flit).
- **128-byte payload = 8 flits:** max cell is 9 flits (1 header + 8 payload), constant 11% header overhead.

| Aspect | **v3.1: 128B payload (144B cell, 128-bit L0)** | v3.0: 256B payload (272B cell, 256-bit L0) | v2.4: 64B payload (80B cell, 42-bit L0) |
|--------|-------------------------------------------------|--------------------------------------------|-------------------------------------------|
| Header overhead (worst case) | **11%** | 6% | 20% |
| Max flit count on L0 | **9 flits** | 9 flits | 16 flits |
| Header padding in flit | **0** (1 full flit) | 16 bytes (half flit) | 0 |
| Neighbor latency (worst case) | **2H + 8 = 10 cc** | 2H + 8 = 10 cc | 2H + 15 = 17 cc |
| Neighbor latency (typical 48B) | **2H + 3 = 5 cc** | 2H + 1 = 3 cc | 2H + 9 = 11 cc |
| Router VOQ SRAM | **~1.7×** vs v2.4 | ~3.4× vs v2.4 | reference |
| L0 throughput @ 500 MHz | **8 GB/s** | 16 GB/s | ~2.6 GB/s |

> **Note:** thanks to variable link occupancy, the worst-case flit counts above are rare. A typical 32-byte actor message: 3 flits on the 128-bit L0 (header + 2 payload) — the link **frees up quickly**.

**Decisive argument: clean flit alignment.** The 128-bit L0 bus makes the header exactly 1 flit with no padding waste. Typical actor messages (estimated ~80% ≤48 bytes, see the note above) traverse in 2–4 flits. Large messages (state migration, code-load chunks) split into 2× more cells than v3.0 (but worst-case latency is unchanged, since the flit count is the same).

In Akka/actor-style systems, the vast majority of messages are small (commands, events, short responses: 16–64 bytes), which fit easily in a single 128B cell — without multi-cell fragmentation.

The `CELL_SIZE` and `BUS_WIDTH` RTL parameters serve as a safety net: configurable at fabrication time (default 128, future upscale 256/512/1024).

**v3.1 rollback decision (2026-04-28):** L0 256→128 bit, payload 256→128 bytes. Rationale: [`decision-bus-rollback-en.md`](decision-bus-rollback-en.md).

#### Detailed analysis

**1. The 128-bit L0 link scaling principle.**
The header (16 bytes) and max payload (128 bytes) are **proportional** to the bus width: header = 1 flit, payload = 8 flits. If the `BUS_WIDTH` parameter is raised to 256-bit, the header grows to 32 bytes and the payload to 256 bytes (future v3.2+).

**2. Aggregate throughput analysis — 128-bit L0 @ 500 MHz:**

| Payload size | Flit count (128-bit) | Payload throughput | Link efficiency |
|--------------|----------------------|--------------------|----------------|
| 16B (small) | 2 flits | 16B / 2 cc = 8.0 B/cc | 50% |
| 32B | 3 flits | 32B / 3 cc = 10.7 B/cc | 67% |
| 48B (typical) | 4 flits | 48B / 4 cc = 12.0 B/cc | 75% |
| 64B | 5 flits | 64B / 5 cc = 12.8 B/cc | 80% |
| 128B (worst case) | 9 flits | 128B / 9 cc = 14.2 B/cc | 89% |

**L0 link throughput:** 128 bits × 500 MHz / 8 = **8 GB/s** (vs v3.0 16 GB/s, vs v2.4 ~2.6 GB/s — still 3× v2.4).

**3. Wormhole routing and HOL blocking.**

On the 128-bit link, worst-case 128B payload is 9 flits. Over 6 hops:

```
H=6 (max L0 hops):
  128B cell, 128-bit link:  occupancy = 2H + 8 = 20 cc
  typical 48B, 128-bit link: occupancy = 2H + 3 = 15 cc
```

Worst-case link occupancy is **unchanged** vs v3.0 (both 9 flits), only the flits are smaller.

**4. Code-load throughput — 2× more cells, same worst-case delivery.**

Seal Core code-load with 128B cells:
- 16 KB method = 128 cells (128B payload each), pipelined (vs v3.0: 64 cells × 256B; vs v2.4: 256 cells × 64B)
- L0 throughput @ 500 MHz: **~8 GB/s** (vs v3.0 ~16 GB/s)
- Worst-case delivery: ~2.6 µs @ 500 MHz (vs v3.0 ~1.3 µs; vs v2.4 ~8 µs)

**5. Memory alignment — DDR5 burst compatible.**

| Memory type | Native burst size | Alignment |
|-------------|-------------------|-----------|
| DDR4 | 64 bytes (BL8 × 8B) | 2× bursts in a 128B cell |
| DDR5 | 64 bytes (BL16 × 4B, dual sub-channel) | 2× bursts in a 128B cell |
| **DDR5 BL32** | **128 bytes (BL32 × 4B)** | **= 128B payload** ✓ |
| LPDDR5 | 32–64 bytes | ≤ 128B |
| HBM2e/HBM3 | 32–256 bytes (pseudo-channel) | 32-128 bytes native |
| QSPI Flash | 64–256 bytes (page: 256B) | ≥ 128B (page split) |
| On-chip SRAM | Cache line: 64 bytes (industry standard) | 2× cache lines in one cell |

The 128-byte payload **exactly matches one DDR5 BL32 burst**, and consolidates 2 cache lines into one cell.

**Summary:** the 128B payload + 128-bit L0 link combination is the v3.1 conservative choice. The scaling principle is preserved (header = 1 flit, payload = 8 flits), with future upscale via the `BUS_WIDTH` parameter.

### Addressing: 24-bit Hierarchical

```
HW address: [region:4-6].[tile:3-4].[cluster:3-4].[core:4] = 18 bits (of 24)
Actor ID:   software-dispatched (payload bytes, not part of the HW address)
```

The hardware address routes cells to a **core**, not to an individual actor. Actor dispatch is handled in software by the destination core's local scheduler — the actor ID is carried in the cell payload. This design allows the actor count per core to vary by core type, SRAM size, and workload without a fixed hardware limit. The remaining 6 bits (24 − 18) are reserved for future addressing extensions. See [Architecture — Actor Scheduling Pipeline](architecture-en.md#actor-scheduling-pipeline) for details.

Routing decisions are O(1): the address prefix immediately determines which level's crossbar/mesh to forward to.

### Hybrid Switching: Wormhole (L0) + Virtual Cut-Through (L1–L3)

The CFPU uses two switching modes, matched to each hierarchy level:

**L0 (mesh) — Wormhole routing:** the header flit (128 bits, containing the destination address) is forwarded immediately after route computation; body flits follow in a pipeline, one per cycle. A max 144-byte cell = max 9 flits on the 128-bit link (1 header + 8 payload). For H hops, the header traverses the mesh in 2H cycles (2-cycle router pipeline: route + switch), and the last body flit arrives up to 8 cycles later. **Worst case: 2H + 8 cycles. Typical (48B payload): 2H + 3 cycles.**

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
| Link type | Parallel, 128-bit, 1× core clock |
| Wire length | ~330 µm (neighboring core) |
| Max hops | 6 |
| Router area / core | 0.001–0.006 mm² (see L0 Router Variants) |
| Gateway | Uplink port integrated into corner core router |

#### L0 Router Variants

The L0 router is the largest per-core overhead in the CFPU. The original 5-port baseline router (~44,300 GE ≈ 0.011 mm²) was designed for Rich Core clusters. For smaller core types (Nano, Actor, Matrix), this router would consume more area than the core itself. Therefore, the CFPU defines two router variants, selected per-cluster via the `ROUTER_VARIANT` RTL parameter.

**Baseline router breakdown (5-port, Rich Core):**

| Component | GE | Function |
|-----------|---:|----------|
| Crossbar (5×5, 144 B) | 2,950 | Input→output data switching |
| VOQ logic (5×5×4 = 100 slots) | 5,000 | Enqueue/dequeue, pointers, flags |
| VOQ SRAM (100 × 144 B = 14 KB) | 14,700 | Cell storage (gate estimate inherited from v3.0, F4 RTL will refine) |
| iSLIP scheduler (5×5) | 3,000 | Round-robin fair scheduling |
| XY routing | 1,000 | Address → direction decode |
| Credit flow control (5 × 4 credits) | 2,000 | Overflow prevention |
| 2 VN demux | 2,000 | Control / Actor traffic separation |
| Cell assembly + CRC-8 | 1,670 | Cell framing, integrity |
| Misc control | 12,000 | FSM, reset, power-gate interface |
| **Total** | **~44,300** | **≈ 0.011 mm²** |

> **Area convention:** GE-to-area conversion assumes ~0.21 µm²/GE at 5nm (logic + routing overhead), SRAM uses dense 6T cells (~0.021 µm²/bit). These estimates are pre-synthesis; final area will be determined by RTL synthesis (F4+). The baseline router in v3.1 is sized for 144-byte cells (16B header + max 128B payload). Gate counts are inherited from v3.0; actual F4 synthesis may show ~30% smaller VOQ SRAM due to the halved cell size.

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
| 2 directions (W→E, N→S), 128-bit | Systolic pipeline fixed data flow | Systolic-dedicated bandwidth (128 bit/cc per direction, 256 bit/cc aggregate over 2 directions — **2× bandwidth** over the v3.1 128-bit L0 main, dedicated to systolic dataflow) |
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
| FIFO (2 directions × 2 slots × 144B) | 600 | Minimal buffering |
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

**Cell serialization on Systolic Wide link:** max 144 bytes = 1152 bits → ⌈1152/128⌉ = 9 flits. Neighbor worst-case latency: ~10 cc (2 hop pipeline + 8 body drain). Model: 2H + (flits-1). Typical 48B payload: 64 bytes = 512 bits → ⌈512/128⌉ = 4 flits, latency: 2H + 3 = 5 cc.

The Systolic variant is **not general purpose** — it is exclusively for ML/SNN workloads where data flow direction is known at compile time. General actor workloads require the Turbo or Compact variant.

**How it differs from other variants:**
- No XY routing (fixed directions: W→E, N→S)
- No VOQ (systolic pipeline is synchronous, no conflict)
- No iSLIP (no arbitration, fixed data flow)
- No 2 VN (control uplink only)
- 128-bit data path × 2 directions (vs 128-bit × 4-5 ports Turbo/Compact) — Systolic aggregate 256 bit/cc, dedicated unidirectional
- 2 directions (vs 4–5 Turbo/Compact)

**Speed comparison:**

| Metric | Turbo | Compact | **Systolic** |
|--------|:-----:|:-------:|:------------:|
| Bandwidth / link | 128 bit/cc | 128 bit/cc | **128 bit/cc × 2 directions** |
| Sustained throughput | ~98% | ~75% | **~95% (systolic)** |
| Neighbor latency (worst case) | ~10 cc | ~12–14 cc | **~10 cc** |
| Neighbor latency (typical 48B) | ~5 cc | ~7–9 cc | **~5 cc** |
| Worst-case intra-cluster | ~20 cc | ~23–27 cc | **~10 cc (1 hop)** |
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
| Link type | Parallel, 128-bit data + 8-bit control (= 136 wires/direction, bidirectional) |
| Max distance (GW → crossbar) | ~1.6 mm |
| Hop count | Always 1 (deterministic) |
| Gate count | ~16,000 |
| VOQ buffer | ~30 KB SRAM |

#### L1 link control bits (8 bits)

In addition to the 128-bit data path, 8 control wires:

| Bit | Name | Function |
|-----|------|----------|
| 0 | `valid` | Flit-valid signal (1 = data on the wire) |
| 1 | `head` | First flit in the cell (header flit) |
| 2 | `tail` | Last flit in the cell |
| 3 | `vn` | Virtual Network (0 = VN1 actor, 1 = VN0 control) |
| 4..5 | `credit_back` | 2-bit credit return on the reverse direction (free benefit of bidirectional link) |
| 6 | `parity` | Link-level simple parity bit (~99% bit-flip detection per flit) |
| 7 | `spare` | Future extension (e.g., priority-bit slot for v3.x+ messages) |

The `head/tail` bits explicitly mark cell boundaries — simpler HW (the router does not need to count `len`, just watches `tail`). The `valid` bit enables stalled-link handling. `credit_back` is a "free" benefit of the bidirectional link: 2 of the reverse-direction wires are reused for credit-flow control.

**Scaling rule consistency:** The L1 link 128-bit data path **matches the L0 cluster mesh width** (`BUS_WIDTH = 128`) — no width transition at the cluster gateway, the header is exactly 1 flit on L1 too.

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

### NoC-Wide Link-Failure and Backpressure Semantics

The relay mechanism above addresses a **specific, permanent hardware fault** (a persistently faulty L3 crosspoint, detected via BIST/watchdog). Beyond that, the **general fault policy** of the entire NoC (from the L0 mesh to the L3 crossbar) is as follows:

- **Best-effort delivery — no guarantee at the network layer.** The NoC does not guarantee delivery of any single cell; reliability is provided by the **actor protocol** (supervision, "let it crash"), not by the network.
- **Deterministic DOR — no adaptive rerouting.** The L0 mesh's XY dimension-order routing (DOR) remains **deterministic** even under runtime congestion or a transient link failure — there is no adaptive path selection. Rationale: (1) adaptive rerouting would break the deadlock-freedom that follows from the XY ordering (see "Deadlock Freedom" above), (2) it would duplicate fault-recovery logic that already exists at the actor-supervision level.
- **Detection:** credit-timeout (the sender does not receive a credit acknowledgment within the expected window) and CRC-8/16 integrity checking on the cell header/payload.
- **Timeout-drop.** If a cell remains stuck beyond the timeout window due to congestion or an in-flight link failure, the router **drops** it — this deliberately prevents a backpressure cascade from spreading through the fabric, instead of letting a single stuck cell chain-react and stall the VOQs behind it, and with them the entire region.
- **Recovery via actor supervision.** The missing response/acknowledgment caused by a dropped cell is resolved through the sender-side actor supervision hierarchy: the supervisor detects the timeout and, per its strategy, resends, restarts the sending/receiving actor, or escalates (see [Symphact vision-en.md](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md), "Let it crash -- structured fault tolerance").

This policy **complements**, rather than replaces, the L3 crosspoint relay above: the relay is a static structural response to a **permanent** fault detected at boot-time/via watchdog, routed around using a precomputed relay table, whereas timeout-drop is the runtime response to normal operational congestion and **transient** link problems.

## Code Loading over the Network

The communication network does not only carry actor messages — **program code** also reaches core SRAM through the same network. Three scenarios:

| Scenario | Size | When | Path |
|----------|------|------|------|
| **Boot** | Full program, KB–MB | System startup | Flash → Seal Core (AuthCode verify) → L3 → L2 → L1 → broadcast to all cores |
| **Hot code loading** | 1 method, 128B–16KB | At runtime | Flash/Rich Core → Seal Core (re-auth) → targeted core |
| **Actor migration** | Actor state + code, KB | At runtime | Source core → Seal Core (re-auth) → destination core |

**All code passes through the Seal Core** — unauthenticated code cannot reach any core. The star topology provides this for free: the Seal Core is at the center of the L3 crossbar, so all cross-region traffic passes through it.

Code loading is normal 144-byte cell traffic on the VN0 (control) channel. A 16 KB method = ~128 cells (128-byte payload each); pipeline throughput is limited by the narrowest link (L0, 128-bit @ 500 MHz = ~8 GB/s). Worst-case delivery: ~2.6 µs @ 500 MHz.

## Quench-RAM Integration with the Network

The [Quench-RAM](quench-ram-en.md) memory-security layer and the packet-switched network **reinforce each other**. Because of the shared-nothing model, the QRAM invariant does not need to be synchronized across the network — each core manages its own QRAM locally.

### Message sending (SEND) — with QRAM semantics

```
SEND(dst_actor, payload_block):
  1. SEAL(payload_block)            ← payload becomes immutable (source core QRAM)
  2. Copy → 144-byte cell(s)         ← placed on the network (wormhole at L0, VCT at crossbars)
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
| L0 Turbo/Compact | Parallel | 128-bit (unidirectional) | 1× core | ~8 GB/s |
| **L0 Systolic** | **Parallel** | **128-bit (unidirectional, 2 directions)** | **1× core** | **~16 GB/s aggregate (2 directions)** |
| L1 (cluster → tile xbar) | Parallel | 128-bit data + 8-bit ctrl (bidirectional) | 1× core | ~8 GB/s |
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

Latencies are for the **reference configuration** (500 MHz, `SERDES_RATIO`=10, `SERIAL_WIRES`=8, effective L2/L3 = 80 bit/cc), zero contention. The "typical" column is for 48B payload (the most common actor message size), "worst case" is for 128B payload (v3.1 max). Higher core clocks with adjusted SerDes parameters yield similar cycle counts (see SerDes Scaling).

**L0 wormhole model (128-bit link):** 2 cycles/hop router pipeline + payload_flits body flit drain = 2H + payload_flits cycles for H hops. Typical 48B: 2H + 3. Worst case 128B: 2H + 8.
**Crossbar VCT model:** link serialization (⌈cell_bits / link_width⌉ cycles) + 1 cycle iSLIP per crossbar. Output serialization overlaps with next stage's input.

| Path | Hops | Typical (48B) | Worst case (128B) | @500 MHz (typical) |
|------|------|--------------|-------------------|-------------------|
| Neighboring core (L0) | 1 | ~5 cycles | ~10 cycles | 10 ns |
| Cross-cluster, same tile (L0+L1+L0) | 6+1+6 = 13 | ~39 cycles | ~59 cycles | 78 ns |
| Cross-tile, same region (L0+L1+L2+L1+L0) | 6+1+1+1+6 = 15 | ~63 cycles | ~109 cycles | 126 ns |
| Cross-region (L0+L1+L2+L3+L2+L1+L0) | 6+1+1+2+1+1+6 = 18 | ~93 cycles | ~171 cycles | 186 ns |

> **Context:** typical ~186 ns on-chip (48B payload) is competitive with software actor message delivery on conventional CPUs (Erlang/BEAM: ~0.5–2 µs), while the CFPU runs thousands of independent hardware cores in parallel. The worst-case 171 cycles (342 ns) applies to rare 128B payloads — variable link occupancy means ~80% of messages travel at typical latency. **The v3.2 L1 link upgrade from 84-bit to 128-bit yielded an additional ~12 cc / ~20 cc gain in typical / worst case (105→93, 191→171): L1 now sends the header in 1 flit and serializes cells in 4 / 9 flits (vs 7 / 14 flits on the old 84-bit).**

<details>
<summary>Cross-region latency breakdown (18 hops, typical 48B payload)</summary>

| Segment | Link width | Cycles | Notes |
|---------|-----------|--------|-------|
| Source L0 wormhole (6 hops) | 128-bit | 15 | 2×6 + 3 body drain (48B = 3 payload flits @ 16B/flit) |
| L1 link (GW → xbar) | 128-bit | 4 | ⌈512/128⌉ (64B cell = 512 bits) |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link (xbar → tile GW) | 128-bit | 4 | |
| L2 link (tile GW → xbar) | 80-bit | 7 | ⌈512/80⌉ |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link (xbar → region GW) | 80-bit | 7 | |
| L3 link (region GW → xbar) | 80-bit | 7 | |
| L3 crossbar (iSLIP) | — | 1 | |
| L3 link (xbar → dst region GW) | 80-bit | 7 | |
| L2 link → xbar | 80-bit | 7 | |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link → dst tile GW | 80-bit | 7 | |
| L1 link → xbar | 128-bit | 4 | |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link → dst cluster GW | 128-bit | 4 | |
| Destination L0 wormhole (6 hops) | 128-bit | 15 | 2×6 + 3 body drain |
| **Total** | | **~93** | |

</details>

<details>
<summary>Cross-region latency breakdown (18 hops, worst case 128B payload)</summary>

| Segment | Link width | Cycles | Notes |
|---------|-----------|--------|-------|
| Source L0 wormhole (6 hops) | 128-bit | 20 | 2×6 + 8 body drain (128B = 8 payload flits @ 16B/flit) |
| L1 link (GW → xbar) | 128-bit | 9 | ⌈1152/128⌉ (144B cell = 1152 bits) |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link (xbar → tile GW) | 128-bit | 9 | |
| L2 link (tile GW → xbar) | 80-bit | 15 | ⌈1152/80⌉ |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link (xbar → region GW) | 80-bit | 15 | |
| L3 link (region GW → xbar) | 80-bit | 15 | |
| L3 crossbar (iSLIP) | — | 1 | |
| L3 link (xbar → dst region GW) | 80-bit | 15 | |
| L2 link → xbar | 80-bit | 15 | |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link → dst tile GW | 80-bit | 15 | |
| L1 link → xbar | 128-bit | 9 | |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link → dst cluster GW | 128-bit | 9 | |
| Destination L0 wormhole (6 hops) | 128-bit | 20 | 2×6 + 8 body drain |
| **Total** | | **~171** | |

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

Typical cross-region latency is ~93 cycles (186 ns @ 500 MHz) for 48B payloads, worst-case 128B payloads ~171 cycles (342 ns) — smaller cluster physical size at advanced nodes partially compensates for the deeper hierarchy.

## Memory Tier (HBM3)

> **Status: proposal (extrapolation).** The HBM3 spec figures are verified (JEDEC JESD238). The CFPU-specific tier design (port counts, link widths, topology) is a **derived proposal** from the NoC formula, not a finalized decision — to be validated by F4/F5 RTL and the finalized chiplet geometry. The DDR5 memory interface, by contrast, is finalized: see [`ddr5-architecture-en.md`](ddr5-architecture-en.md).

The four-level L0–L3 hierarchy is the **compute fabric**: optimized for small actor messages (≤128 byte cell). HBM3 traffic differs in every dimension (bulk, many-to-few, an order of magnitude more bandwidth), so it requires a **separate memory tier**, not the compute-mesh links.

### Why a separate tier? — the bandwidth mismatch

Verified HBM3 parameters (JEDEC JESD238):

| Parameter | Value |
|-----------|-------|
| Bandwidth | 819 GB/s / stack |
| Channels | 16 channels / 32 pseudo-channels |
| Interface width | 1024 bit (16 × 64-bit) |
| Per-pin data rate | 6.4 Gb/s |

The L0 cluster mesh link @ 500 MHz = 8 GB/s (128 bit × 500 MHz / 8). Saturating a single HBM3 stack would need **819 ÷ 8 = ~102 links of 128-bit** — physically unrealistic to route into a single controller.

By comparison, DDR5 (~76 GB/s) ÷ 8 GB/s = ~10 ports, which **fits on the existing NoC** (the DDR5 Controller's 10 × 128-bit ports, see [`ddr5-architecture-en.md`](ddr5-architecture-en.md)). It is HBM3's ~10.7× bandwidth that breaks the 128-bit approach.

### Decision trail

| Alternative | Why (re)jected |
|-------------|----------------|
| A) Reuse the compute L0 128-bit mesh | Rejected — ~102 ports/stack unrealistic; incast hotspot at the mesh edge, XY routing chokes |
| B) Shared VN on the compute mesh (3rd VN for bulk) | Rejected — head-of-line blocking + the bandwidth mismatch starves actor messages |
| C) **Separate, wide memory NoC plane** | **Chosen** — physical isolation + full HBM3 bandwidth |

### Structure of the chosen tier

1. **Separate physical NoC plane** — not the L0–L3 compute hierarchy but a dedicated memory plane. Actor traffic and bulk memory traffic do not share links → no head-of-line blocking.
2. **Wide links + two levers.** Speed grows from `width × clock / 8`: a wider link **and/or** a higher memory-tier clock.
3. **Edge-concentrated topology.** HBM3 stacks sit at the **edge** of the 2.5D interposer → traffic flows to the periphery. A fat-tree / edge-ring aggregates compute-fabric requests toward the peripheral controllers (not a flat XY mesh).
4. **Channel scattering.** The controller interleaves requests across the **32 pseudo-channels** to use the bandwidth.
5. **HW RTL HBM3 Controller as NoC endpoint** — same principle as DDR5 ([`ddr5-architecture-en.md`](ddr5-architecture-en.md) decision 1.c): no software core in the loop, because a software gateway core's throughput is only ~0.5–1 GB/s.
6. **Capability reuse.** The same `flags.DDR5_CAP` / QRAM HW Capability Slot model as DDR5 ([`ddr5-architecture-en.md`](ddr5-architecture-en.md) decision 2) — HBM3 needs no new security mechanism. For TB-scale multi-stack HBM3, the **page-aligned 32-bit `region_base` (16 TB)** applies (see ddr5-architecture-en.md 2.b, v1.4) — the earlier 36-bit byte base covered only 64 GB (1 stack).

### Speed and port requirement (derived, @ 500 MHz)

| Memory-tier link | Raw / port | Ports / HBM3 stack (819 GB/s) |
|------------------|-----------|-------------------------------|
| 128-bit | 8 GB/s | ~102 (unrealistic) |
| 256-bit | 16 GB/s | ~51 |
| 512-bit | 32 GB/s | ~26 |
| **1024-bit** | **64 GB/s** | **~13** |

> The port count halves linearly when the clock doubles: 1024-bit @ 1 GHz = 128 GB/s/port → ~7 ports/stack. The ~11% header overhead (1 header flit / 8 payload flits) also applies here; stream mode amortizes it with large sequential blocks.

### Relationship to DDR5

| | DDR5 (finalized) | HBM3 (proposal) |
|--|------------------|------------------|
| Bandwidth | ~76 GB/s (2ch) | 819 GB/s / stack |
| NoC solution | existing L0, 10 × 128-bit controller ports | separate memory tier, ~13 × 1024-bit @ 500 MHz |
| Topology | NoC endpoint on the fabric | separate edge-concentrated plane |
| Capability | DDR5_CAP / QRAM slot | same |

DDR5 fits on the existing interconnect; HBM3 is what justifies this separate tier.

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
| [OSREQ-001](osreq-from-os/osreq-001-tree-interconnect-hu.md) | Interconnect topology | **Resolved**: 4-level hierarchical mesh + crossbar |
| [OSREQ-004](osreq-from-os/osreq-004-dma-engine-hu.md) | DMA engine | Required from F4 onwards (large messages, actor state transfer) |
| [OSREQ-005](osreq-from-os/osreq-005-mailbox-interrupt-hu.md) | Mailbox interrupt | HW interrupt, triggered by cell arrival |

## Related Documents

- [Topology scaling](topology-scaling-en.md) — general NoC topology comparison (Bus/Ring/Mesh/Torus/Crossbar/Fat-tree/Hierarchical) with area + BW + latency formulas; mathematical justification for the hierarchical choice
- [DDR5 Architecture](ddr5-architecture-en.md) — HW architecture of the external DDR5 memory interface (RTL controller, capability slot, stream/request mode); the HBM3 memory tier builds on this
- [Quench-RAM](quench-ram-en.md) — per-block immutability, atomic wipe-on-release, QRAM + network symbiosis
- [AuthCode](authcode-en.md) — code authentication; the Seal Core verifies the signature of every loaded code block
- [Architecture](architecture-en.md) — full CFPU microarchitecture overview
- [ISA-CIL-T0](ISA-CIL-T0-en.md) — the CIL-T0 instruction set specification

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 3.8 | 2026-07-19 | **Terminology consistency:** in the OSREQ cross-reference table, "Closed" → **"Resolved"**, to match the status wording now set in `osreq-001-tree-interconnect-en.md` v1.2 (Symphact OSREQ documents use English status keywords — "Draft"/"Obsolete"/"Resolved" — even in Hungarian-language docs). No content change — the OSREQ-001 topology decision (4-level hierarchical mesh + crossbar, pure fat tree explicitly excluded) was already recorded earlier. |
| 3.7 | 2026-07-19 | **New "NoC-Wide Link-Failure and Backpressure Semantics" section** (under L3 Crosspoint Fault Tolerance). The previous fault-handling description covered only the permanent L3 crosspoint fault (relay mitigation), which could implicitly suggest blocking-FIFO behavior for the NoC in general. Codified: best-effort delivery (no network-layer guarantee), deterministic DOR without adaptive rerouting, credit-timeout + CRC-8/16 detection, timeout-drop to prevent backpressure cascades, recovery via actor supervision. Cascaded from the 2026-07-07 NoC fault-policy decision; synchronized with Symphact's `vision-en.md` Backpressure section and the hu/en pairs. |
| 3.6 | 2026-07-17 | **Cascade + future-tense fix:** the `cell-format-en.md` bit-allocation reference v2.2 → **v2.4**; the latency-context sentence "In v3.2 … the L1 link upgrade … yields …" rewritten from **future to past tense** (the v3.2 L1 128-bit upgrade has already happened; the latency tables already show the post-v3.2 values). |
| 3.5 | 2026-06-01 | **HBM3 tier capability clarification.** The "capability reuse" point extended: TB-scale multi-stack HBM3 uses the **page-aligned 32-bit `region_base` (16 TB)** model (ddr5-architecture v1.4), not the earlier 36-bit byte base (only 64 GB / 1 stack). Cascade from the ddr5-architecture v1.4 capability-slot revision. |
| 3.4 | 2026-06-01 | **New "Memory Tier (HBM3)" section.** HBM3 (819 GB/s/stack, 16 channels / 32 pseudo-channels, JEDEC JESD238) requires a separate, wide memory NoC plane, because the compute L0 128-bit link would need ~102 ports/stack (unrealistic). Decision trail: reuse L0 (rejected) / shared VN (rejected) / separate memory tier (chosen). Edge-concentrated topology (2.5D interposer edge), 32 pseudo-channel interleaving, HW RTL HBM3 controller, capability reuse (DDR5_CAP/QRAM). Derived port table @ 500 MHz: 1024-bit → ~13 ports/stack. DDR5, by contrast, fits on the existing NoC (10 × 128-bit). **Status: proposal/extrapolation** — HBM3 spec verified, the CFPU tier design to be validated in F4/F5 RTL. Cascade: ddr5-architecture-en.md added to Related Documents. |
| 3.3 | 2026-06-01 | **The "~80% ≤48 byte" actor-message distribution marked as an explicit design assumption (not measured data).** `decision-bus-rollback` previously cited a non-existent "interconnect v2.4 analysis" — a circular self-reference. The figure now appears as "estimated ~80%" with a "not measured, based on Akka/Erlang workloads, real measurement scheduled for a future phase" note. Annotation clarification only; sizing decisions unchanged. |
| 3.2 | 2026-04-28 | **L1 tile crossbar link 84-bit → 128-bit + 8-bit control.** The 84-bit parallel link inherited from v1.0 was not a power of 2 and not aligned with the header (128-bit) or L0 (128-bit) widths — an unjustified design relic. L1 now matches L0: 128-bit data + 8-bit control (valid/head/tail/vn/credit_back/parity/spare) = 136 wires/direction. Header is exactly 1 flit on L1 too, no width transition at the cluster gateway. Latency improvements: cross-cluster typ 45→39 cc (worst 69→59), cross-tile typ 75→63 cc (worst 129→109), cross-region typ 105→93 cc (210→186 ns), worst 191→171 cc (382→342 ns). L1 throughput 5.2→8 GB/s. Cell-format / internal-bus synchronized |
| 3.1 | 2026-04-28 | **L0 bus rollback 256→128 bit** (FPGA-friendly conservative step for F2.7 A7-Lite 200T bring-up). Scaling rule codified: `header = 1 flit = BUS_WIDTH/8 byte`, `payload = 8 flit`. **Header layout unchanged** (16 byte = 1 flit on 128-bit link). **Cell:** max 144 byte (16B header + 128B payload). Flit model: on 128-bit link header=1 flit (no padding waste, vs v3.0 half flit), worst case 2H+8 (unchanged), typical 2H+3. Latency tables recalculated. Cross-region typical ~105 cc (210 ns), worst case ~191 cc (382 ns) — worst case **better than v3.0** (smaller cell → faster L1/L2/L3 serialization). L0 throughput ~8 GB/s (vs v3.0 ~16 GB/s, vs v2.4 ~2.6 GB/s). `BUS_WIDTH` RTL parameter introduced (default 128, future upscale 256/512/1024). Rationale: [`decision-bus-rollback-en.md`](decision-bus-rollback-en.md) |
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
