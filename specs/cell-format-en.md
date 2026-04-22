# CFPU NoC Cell Format

> Magyar verzió: [cell-format-hu.md](cell-format-hu.md)

> Version: 1.0

> Source: `docs/interconnect-en.md` v2.4 (2026-04-22)

This specification defines the exact binary format of the **cell** (message packet) traveling on the CFPU NoC network.

## Cell structure

ATM-inspired fixed buffer, variable link occupancy: **16-byte header + 0–256 byte payload**.

Router buffers are fixed-size (272-byte slots). Only the header + `len` payload bytes travel on the link.

```
Cell = Header (16 bytes) + Payload (0-256 bytes)

Buffer:  always 272-byte slot (fixed, deterministic SRAM management)
On link: 16 + len bytes (variable, efficient link utilization)
```

## Header (16 bytes = 128 bits)

```
┌──────────────────────────────────────────────────────┐
│  Bit 127..104: dst[24]          — dest HW addr       │
│  Bit 103..80:  src[24]          — source HW addr     │
│  Bit 79..64:   src_actor[16]    — sending actor      │
│  Bit 63..48:   dst_actor[16]    — dest actor         │
│  Bit 47..40:   seq[8]           — sequence num       │
│  Bit 39..32:   flags[8]         — control bits       │
│  Bit 31..23:   len[9]           — payload size       │
│  Bit 22..15:   CRC-8[8]         — header integrity   │
│  Bit 14..0:    reserved[15]     — future use         │
└──────────────────────────────────────────────────────┘
```

### Fields

| Field | Bits | Size | Written by | Spoofable? | Description |
|-------|------|------|-----------|-----------|-------------|
| `dst` | 127..104 | 24 bits | Sending core | — | Destination hierarchical HW address (region.tile.cluster.core) |
| `src` | 103..80 | 24 bits | **NoC router HW** | **No** | Source HW address — hardware-filled based on the sending core's physical position |
| `src_actor` | 79..64 | 16 bits | Core scheduler | Within core, yes | Sending actor identifier (0–65,535) |
| `dst_actor` | 63..48 | 16 bits | Sending actor | — | Destination actor identifier (0–65,535) |
| `seq` | 47..40 | 8 bits | Sender | — | Sequence number for fragmented message ordering |
| `flags` | 39..32 | 8 bits | Sender | — | VN0/VN1 (bit 0), relay flag (bit 1), rest reserved |
| `len` | 31..23 | 9 bits | Sender | — | Actual payload size in bytes (0–256) |
| `CRC-8` | 22..15 | 8 bits | HW | — | Header integrity check |
| `reserved` | 14..0 | 15 bits | — | — | Future extensions (QoS, etc.) |

### flags field detail

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `vn` | 0 = VN1 (actor message), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 1 | `relay` | 1 = relay message (L3 fault tolerance, see interconnect spec) |
| 2–7 | reserved | Future use |

## Payload (0–256 bytes)

Application data. The `len` field determines the actual size. The router **does not inspect** payload contents — that is solely the receiving core's responsibility.

The Actor ID was previously (interconnect v1.8) in the first payload bytes (software dispatch). Since v2.4, `src_actor` and `dst_actor` are in the header — the payload is **entirely application data**.

## Variable link occupancy

Router buffers are fixed (272-byte slots), but **only the actual data travels on the link**:

```
128-bit internal data path:
  payload_flits = ceil(len / 16)    ← 5-bit right shift + carry
  total_flits = 1 (header) + payload_flits
```

| len (bytes) | Payload flits | Total flits | Bytes on link |
|------------|--------------|------------|---------------|
| 0 | 0 | 1 | 16 |
| 8 | 1 | 2 | 32 |
| 16 | 1 | 2 | 32 |
| 32 | 2 | 3 | 48 |
| 64 | 4 | 5 | 80 |
| 128 | 8 | 9 | 144 |
| 192 | 12 | 13 | 208 |
| 256 | 16 | 17 | 272 |

**HW cost:** 5-bit down counter per router port + right shift. No LUT, no tail bit, no link-width overhead.

## Split SRAM design

Header and payload are stored in **separate SRAMs** inside the router:

```
Header SRAM:   slot x 16 bytes    (shift addressing)
Payload SRAM:  slot x 256 bytes   (shift addressing, power-of-2)
```

The scheduler reads the header for routing decisions while the payload is still arriving — **1 cycle latency saving**. No port contention between scheduler and crossbar.

## DDR5 burst alignment

The 256-byte payload is exactly **4 × DDR5 burst** (64 bytes/burst):

| DDR5 burst count | Payload size | Cell count |
|-----------------|--------------|------------|
| 1× (64 bytes) | 64 | 1 |
| 2× (128 bytes) | 128 | 1 |
| 3× (192 bytes) | 192 | 1 |
| 4× (256 bytes) | 256 | 1 |
| 5× (320 bytes) | 256 + 64 | 2 |

## RTL parameters

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `CELL_SIZE` | 256 | 64 / 128 / 256 | Max payload size. Buffer slot = 16 (header) + CELL_SIZE (payload) |

## Decision log

### Decision 1: Why fixed buffers, variable links?

**Rejected:** Fully fixed cell (always full size on link). ~80% of actor messages are ≤48 bytes — fixed occupancy wastes a large portion of link capacity.

**Rejected:** Variable-size buffers. Fragmentation, complex SRAM management, non-deterministic timing.

**Final decision:** Fixed buffer + variable link. Buffers are deterministic (ATM principle), links are efficient. HW cost: 5-bit counter per port.

### Decision 2: Why 256-byte payload?

**Previous decision (2026-04-20):** 64 bytes was the default, because with fixed link occupancy a larger cell gave slower worst-case latency.

**Revision (2026-04-22):** With variable link occupancy, large payload disadvantages **disappeared**:
- Short messages (≤64 bytes): **same flit count** — no penalty
- Long messages: **one cell suffices** — no fragmentation, less header overhead

**Decisive arguments for 256 bytes:**
- **4 × DDR5 burst** (64 bytes) fits in a single cell — the natural unit for peripheral handling
- **Power-of-2** payload size — simple shift SRAM addressing
- **`len[9]`** (max 511) covers it amply — only 1 bit more than `len[8]`, 15 bits reserved remain

**Final decision (2026-04-22):** 256 bytes is the default (`CELL_SIZE = 256`). Smaller values (64, 128) available as RTL parameters.

### Decision 3: Why `src_actor` / `dst_actor` in the header?

**Rejected (v1.8):** Actor ID in payload, software dispatch. With N:M actor-to-core mapping, the DDR5 Controller and crash recovery could not distinguish actors at the core level.

**Final decision (v2.4):** 16-bit src_actor + 16-bit dst_actor in the header. Hardware advantages:
- DDR5 CAM table actor-level ACL (`src[24] + src_actor[16]`)
- Crash recovery: only the crashed actor's capabilities are revoked
- Router dispatch: readable from header, no need to inspect payload
- 16 bits: 65,536 actors/core, covers sleeping actors as well

### Decision 4: Why `len[9]` and not `len[8]` or `len[16]`?

**Rejected:** `len[8]` (max 255). Does not cover the 256-byte payload.

**Rejected:** `len[16]` (max 65,535). Oversized — the freed bits are more useful for actor IDs.

**Final decision:** `len[9]` (max 511). Exactly covers the 256-byte payload, and 15 reserved bits remain.

## Changelog

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-04-22 | Initial version — 256-byte payload, len[9], header bit fields, variable link occupancy, DDR5 burst alignment, decision log |
