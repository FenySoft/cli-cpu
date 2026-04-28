# CFPU NoC Cell Format

> Magyar verzió: [cell-format-hu.md](cell-format-hu.md)

> Version: 2.0

> Source: `docs/interconnect-en.md` v2.4 (2026-04-22)

This specification defines the exact binary format of the **cell** (message packet) traveling on the CFPU NoC network.

## Cell structure

ATM-inspired fixed buffer, variable link occupancy: **16-byte header + 1–256 byte payload**.

Router buffers are fixed-size (272-byte slots). Only the header + actual payload bytes travel on the link.

```
Cell = Header (16 bytes) + Payload (1-256 bytes)

Buffer:  always 272-byte slot (fixed, deterministic SRAM management)
On link: 16 + payload bytes (variable, efficient link utilization)
```

> **Note:** Zero-byte payload (header only) is indicated by the `flags.zero_len` bit — in that case the `len` field is not interpreted.

## Header (16 bytes = 128 bits)

4 × 32-bit words:

```
Word 0: dst[24] + dst_actor[8]                    = 32 bits — destination
Word 1: src[24] + src_actor[8]                     = 32 bits — source
Word 2: seq[16] + flags[8] + len[8]                = 32 bits — control
Word 3: reserved[8] + CRC-16[16] + CRC-8[8]        = 32 bits — integrity
```

```
┌──────────────────────────────────────────────────────┐
│  Bit 127..104: dst[24]          — dest HW addr       │
│  Bit 103..96:  dst_actor[8]     — dest actor         │
│  Bit 95..72:   src[24]          — source HW addr     │
│  Bit 71..64:   src_actor[8]     — sending actor      │
│  Bit 63..48:   seq[16]          — sequence num       │
│  Bit 47..40:   flags[8]         — control bits       │
│  Bit 39..32:   len[8]           — payload size       │
│  Bit 31..24:   reserved[8]      — future use         │
│  Bit 23..8:    CRC-16[16]       — payload integrity  │
│  Bit 7..0:     CRC-8[8]         — header integrity   │
└──────────────────────────────────────────────────────┘
```

### Fields

| Field | Bits | Size | Written by | Spoofable? | Description |
|-------|------|------|-----------|-----------|-------------|
| `dst` | 127..104 | 24 bits | Sending core | — | Destination hierarchical HW address (region.tile.cluster.core) |
| `dst_actor` | 103..96 | 8 bits | Sending actor | — | Destination actor identifier (0–255) |
| `src` | 95..72 | 24 bits | **NoC router HW** | **No** | Source HW address — hardware-filled based on the sending core's physical position |
| `src_actor` | 71..64 | 8 bits | **Core HW** | **No** | Sending actor identifier (0–255) — filled from the active actor context register, HW-managed, unspoofable |
| `seq` | 63..48 | 16 bits | Sender | — | Sequence number for fragmented message ordering |
| `flags` | 47..40 | 8 bits | Sender | — | Control bits (see below) |
| `len` | 39..32 | 8 bits | Sender | — | Payload size: `len + 1` = 1–256 bytes. Zero-byte payload → `flags.zero_len` |
| `reserved` | 31..24 | 8 bits | — | — | Future extensions (QoS, etc.) |
| `CRC-16` | 23..8 | 16 bits | HW | — | Payload integrity check — computed over payload |
| `CRC-8` | 7..0 | 8 bits | HW | — | Header integrity check — computed over header bits 127..8 (including CRC-16) |

### flags field detail

| Bit | Name | Meaning |
|-----|------|---------|
| 7 | `vn` | 0 = VN1 (actor message), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 6 | `relay` | 1 = relay message (L3 fault tolerance, see interconnect spec) |
| 5..4 | `pri` | Priority (00 = normal, 01–11 = future QoS levels) |
| 3 | `zero_len` | 1 = no payload (0 bytes), the `len` field is not interpreted |
| 2..0 | reserved | Future use |

## Payload (1–256 bytes)

Application data. The `len` field (`len + 1`) determines the actual size. If `flags.zero_len = 1`, there is no payload. The router **does not inspect** payload contents — that is solely the receiving core's responsibility.

The Actor ID was previously (interconnect v1.8) in the first payload bytes (software dispatch). Since v2.4, `src_actor` and `dst_actor` are in the header — the payload is **entirely application data**.

## Variable link occupancy

Router buffers are fixed (272-byte slots), but **only the actual data travels on the link**.

### 128-bit internal data path

```
payload_flits = ceil(len_bytes / 16)    ← 4-bit right shift + carry
total_flits = 1 (header) + payload_flits
```

| Payload (bytes) | Payload flits | Total flits | Bytes on link |
|----------------|--------------|------------|---------------|
| 0 (zero_len) | 0 | 1 | 16 |
| 1 | 1 | 2 | 32 |
| 8 | 1 | 2 | 32 |
| 16 | 1 | 2 | 32 |
| 32 | 2 | 3 | 48 |
| 64 | 4 | 5 | 80 |
| 128 | 8 | 9 | 144 |
| 192 | 12 | 13 | 208 |
| 256 | 16 | 17 | 272 |

### 256-bit internal data path

```
payload_flits = ceil(len_bytes / 32)    ← 5-bit right shift + carry
total_flits = 1 (header) + payload_flits
```

> **Note:** The 128-bit header occupies the lower half of a single 256-bit flit (upper 128 bits = 0 or first 16 bytes of payload). The implementation may choose to merge header + payload in the first flit.

| Payload (bytes) | Payload flits | Total flits | Bytes on link |
|----------------|--------------|------------|---------------|
| 0 (zero_len) | 0 | 1 | 32 |
| 1 | 1 | 2 | 64 |
| 16 | 1 | 2 | 64 |
| 32 | 1 | 2 | 64 |
| 64 | 2 | 3 | 96 |
| 128 | 4 | 5 | 160 |
| 192 | 6 | 7 | 224 |
| 256 | 8 | 9 | 288 |

**HW cost:** Down counter per router port + right shift. No LUT, no tail bit, no link-width overhead.

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
- **`len[8]`** with +1 encoding covers 1–256 bytes; zero-byte payload indicated by a separate flag

**Final decision (2026-04-22):** 256 bytes is the default (`CELL_SIZE = 256`). Smaller values (64, 128) available as RTL parameters.

### Decision 3: Why `src_actor` / `dst_actor` in the header?

**Rejected (v1.8):** Actor ID in payload, software dispatch. With N:M actor-to-core mapping, the DDR5 Controller and crash recovery could not distinguish actors at the core level.

**v2.4 decision:** Actor IDs moved into the header.

**v2.0 revision (2026-04-28):** 16 bits → 8 bits per actor ID, because:
- 256 actors/core is sufficient: the CST (Context Switch Table) is HW-managed — the active actor context register fills the `src_actor` field in hardware, **unspoofable** (core software cannot override it)
- The freed 2 × 8 bits (16 bits total) expand the `seq` field from 8 → 16 bits, enabling larger fragmented message sequences
- DDR5 CAM table actor-level ACL still works (`src[24] + src_actor[8]`)
- Crash recovery: only the crashed actor's capabilities are revoked
- Router dispatch: readable from header, no need to inspect payload

**Final decision (v2.0):** 8-bit src_actor + 8-bit dst_actor in the header. The `src_actor` is filled by core HW (CST active context register), the router fills `src` — both are unspoofable.

### Decision 4: Why `len[8]` (len+1 encoding)?

**Rejected (v1.0):** `len[9]` (max 511). Covers 256 bytes, but 1 bit wasted — the 257–511 range is never used.

**Rejected:** `len[16]` (max 65,535). Oversized — the freed bits are more useful elsewhere.

**Rejected:** `len[8]` direct encoding (max 255). Does not cover the 256-byte payload.

**Final decision (v2.0):** `len[8]` with +1 encoding: stored value 0–255, actual payload size `len + 1` = 1–256 bytes. Zero-byte (header-only) messages are indicated by the `flags.zero_len` bit. Advantages:
- 8 bits: word-boundary alignment (as part of a 32-bit word)
- Full 1–256 range coverage without waste
- The freed 1 bit (len[9] → len[8]) + former reserved bits made room for CRC-16

### Decision 5: Why CRC-16 for payload?

**In v1.0:** Only CRC-8 over the header. Payload integrity was not hardware-checked.

**Final decision (v2.0):** CRC-16 (16 bits) computed over payload, stored in header Word 3. CRC-8 (8 bits) is then computed over the full header (bits 127..8), **including the CRC-16 value**. This way, header integrity also protects the payload CRC — no single bit-flip goes undetected.

## Changelog

| Version | Date | Change |
|---------|------|--------|
| 2.0 | 2026-04-28 | Header reorganization: 4 × 32-bit word layout; src_actor/dst_actor 16→8 bits (HW-managed CST); seq 8→16 bits; len[9]→len[8] (len+1 encoding); CRC-16 added (payload integrity); flags expansion (pri, zero_len); 256-bit link flit table; decision log update (decisions 3–5) |
| 1.0 | 2026-04-22 | Initial version — 256-byte payload, len[9], header bit fields, variable link occupancy, DDR5 burst alignment, decision log |
