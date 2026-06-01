# CFPU NoC Cell Format

> Magyar verzió: [cell-format-hu.md](cell-format-hu.md)

> Version: 2.4

> Source: `docs/interconnect-en.md` v3.1 (2026-04-28)

This specification defines the exact binary format of the **cell** (message packet) traveling on the CFPU NoC network.

## Cell structure

ATM-inspired fixed buffer, variable link occupancy: **16-byte header + 1–128 byte payload** (v3.1 default; scalable via the `BUS_WIDTH` parameter, see `decision-bus-rollback-en.md`).

Router buffers are fixed-size (144-byte slots). Only the header + actual payload bytes travel on the link.

```
Cell = Header (16 bytes) + Payload (1-128 bytes)

Buffer:  always 144-byte slot (fixed, deterministic SRAM management)
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
| `len` | 39..32 | 8 bits | Sender | — | Payload size: `len + 1` byte. v3.1: max 128 bytes (`len ≤ 127`); the upper 128 values are reserved for future `BUS_WIDTH` upscale. Zero-byte payload → `flags.zero_len` |
| `reserved` | 31..24 | 8 bits | — | — | Future extensions (QoS, etc.) |
| `CRC-16` | 23..8 | 16 bits | HW | — | Payload integrity check — computed over payload |
| `CRC-8` | 7..0 | 8 bits | HW | — | Header integrity check — computed over header bits 127..8 (including CRC-16) |

### flags field detail

| Bit | Name | Writable by | Meaning |
|-----|------|-------------|---------|
| 7 | `vn` | Sender SW | 0 = VN1 (actor message), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 6 | `relay` | NoC HW | 1 = relay message (L3 fault tolerance, see interconnect spec) |
| 5..4 | `pri` | Sender SW | Priority (00 = normal, 01–11 = future QoS levels) |
| 3 | `zero_len` | Sender SW | 1 = no payload (0 bytes), the `len` field is not interpreted |
| 2 | `ddr5_cap` | **Core HW only** | 1 = the first 8 bytes of payload are HW-attached DDR5 capability slot. The SW `send` opcode has this bit masked to 0 (HW filter). See [`ddr5-architecture-hu.md`](../docs/ddr5-architecture-hu.md) v1.3 |
| 1..0 | reserved | — | Future use |

## Payload (1–128 bytes)

Application data. The `len` field (`len + 1`) determines the actual size. If `flags.zero_len = 1`, there is no payload. The router **does not inspect** payload contents — that is solely the receiving core's responsibility.

The Actor ID was previously (interconnect v1.8) in the first payload bytes (software dispatch). Since v2.4, `src_actor` and `dst_actor` are in the header — the payload is **entirely application data**.

## Variable link occupancy

Router buffers are fixed (144-byte slots), but **only the actual data travels on the link**.

### 128-bit L0 data path (v3.1 default)

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
| 48 (typical actor) | 3 | 4 | 64 |
| 64 | 4 | 5 | 80 |
| 96 | 6 | 7 | 112 |
| 128 (max v3.1) | 8 | 9 | 144 |

The scaling rule: the **header is exactly 1 flit** on the 128-bit link (16 bytes = 128 bits), the max payload is **8 flits** (128 bytes / 16 bytes/flit). Header overhead is a constant 11%.

### Future upscale (256 / 512 / 1024-bit `BUS_WIDTH`)

When the `BUS_WIDTH` RTL parameter is upscaled, the header size and max payload scale proportionally to keep the `header = 1 flit, payload = 8 flits` rule valid:

| `BUS_WIDTH` | Header | Max payload | Cell | Cell flits | **@ 50 MHz** | **@ 500 MHz** | **@ 1 GHz** |
|---|---|---|---|---|---|---|---|
| **128 (v3.1)** | **16 bytes** | **128 bytes** | **144 bytes** | **9 flits** | **0.8 GB/s** | **8 GB/s** | **16 GB/s** |
| 256 (future) | 32 bytes | 256 bytes | 288 bytes | 9 flits | 1.6 GB/s | 16 GB/s | 32 GB/s |
| 512 (future) | 64 bytes | 512 bytes | 576 bytes | 9 flits | 3.2 GB/s | 32 GB/s | 64 GB/s |
| 1024 (future) | 128 bytes | 1024 bytes | 1152 bytes | 9 flits | 6.4 GB/s | 64 GB/s | 128 GB/s |

> **Bandwidth formula:** `BUS_WIDTH / 8 × f` — one flit per cycle, raw link capacity (header + payload combined, SI: 1 GB/s = 10⁹ bytes/s).
>
> **Frequency columns rationale:**
> - **50 MHz** — F3 Tiny Tapeout / Sky130 I/O target (see [`docs/architecture-en.md`](../docs/architecture-en.md) § OPI Octal SPI)
> - **500 MHz** — CFPU reference core clock (see [`docs/architecture-en.md`](../docs/architecture-en.md) § OPI PSRAM transfer rates, "core cycle @ 500 MHz")
> - **1 GHz** — aspirational F6+ silicon target
>
> **Effective payload bandwidth:** worst-case 9-flit cell (1 header + 8 payload) yields ~**88.9% × raw** (constant 11% header overhead). For a typical 48-byte actor message (1 header + 3 payload flits) this drops to ~75% × raw — but with variable link occupancy, the remaining time is reusable by other cells.

Details: [`docs/decision-bus-rollback-en.md`](../docs/decision-bus-rollback-en.md).

**HW cost (v3.1):** Down counter per router port + right shift. No LUT, no tail bit, no link-width overhead.

## Split SRAM design

Header and payload are stored in **separate SRAMs** inside the router:

```
Header SRAM:   slot x 16 bytes    (shift addressing)
Payload SRAM:  slot x 128 bytes   (shift addressing, power-of-2) — v3.1 default
```

The scheduler reads the header for routing decisions while the payload is still arriving — **1 cycle latency saving**. No port contention between scheduler and crossbar.

## DDR5 burst alignment

The 128-byte payload (v3.1 default) corresponds to **DDR5 BL32** (Burst Length 32 × 4 bytes) native burst unit, or 2× DDR5 BL16 (64 bytes) bursts:

| DDR5 burst count | Payload size | Cell count |
|-----------------|--------------|------------|
| 1× BL16 (64 bytes) | 64 | 1 |
| 2× BL16 (128 bytes) | 128 | 1 |
| 1× **BL32** (128 bytes) | 128 | 1 |
| 3× BL16 (192 bytes) | 128 + 64 | 2 |
| 4× BL16 (256 bytes) | 128 + 128 | 2 |

With future `BUS_WIDTH=256` upscale, a 256B payload will fit 4× BL16 (or 1× BL64) bursts in a single cell — exactly as v3.0 envisioned.

## RTL parameters

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `BUS_WIDTH` | 128 | 128 / 256 / 512 / 1024 | L0 link width (bits). Header and payload size scale proportionally. |
| `CELL_SIZE` | 128 | 8 × `BUS_WIDTH/8` | Max payload size (bytes). Buffer slot = 16 (header) + CELL_SIZE (payload) — at `BUS_WIDTH=128` the slot is 144 bytes. |

## Decision log

### Decision 1: Why fixed buffers, variable links?

**Rejected:** Fully fixed cell (always full size on link). An estimated ~80% of actor messages are ≤48 bytes (design assumption, not measured — see `docs/interconnect-en.md`) — fixed occupancy wastes a large portion of link capacity.

**Rejected:** Variable-size buffers. Fragmentation, complex SRAM management, non-deterministic timing.

**Final decision:** Fixed buffer + variable link. Buffers are deterministic (ATM principle), links are efficient. HW cost: 5-bit counter per port.

### Decision 2: Why 128-byte payload (v3.1 rollback)?

**Previous decisions:**
- **2026-04-20:** 64 bytes was the default, because with fixed link occupancy a larger cell gave slower worst-case latency.
- **2026-04-22 (v1.0 of this spec):** 256 bytes default — variable link occupancy eliminated large-cell drawbacks.
- **2026-04-28 (v2.0):** 256 bytes alongside the 256-bit L0 bus.

**Revision (2026-04-28, v2.1):** The v3.1 interconnect rollback (256→128 bit L0 bus) proportionally reduced max payload size. Per the **scaling rule**:
- header = 1 flit = `BUS_WIDTH/8` bytes
- payload = 8 flits = 8 × header bytes
- cell = 9 flits, header overhead constant 11%

**Rationale for 128 bytes (v3.1):**
- **Header is exactly 1 flit** on the 128-bit L0 bus — in v3.0 the header was half a flit on the 256-bit bus (50% padding waste).
- **DDR5 BL32** (128 bytes) native burst alignment.
- **F2.7 FPGA-friendly** wire budget — a 128-bit parallel link is trivial in Vivado/OpenXC7.
- **Upscaling** via `BUS_WIDTH` parameter remains available — if F4+ experience justifies, 256-bit upscale is supported.

**Final decision (v2.1, 2026-04-28):** 128 bytes is the default (`CELL_SIZE = 128`, `BUS_WIDTH = 128`). Detailed rationale: [`docs/decision-bus-rollback-en.md`](../docs/decision-bus-rollback-en.md).

### Decision 3: Why `src_actor` / `dst_actor` in the header?

**Rejected (v1.8):** Actor ID in payload, software dispatch. With N:M actor-to-core mapping, the DDR5 Controller and crash recovery could not distinguish actors at the core level.

**v2.4 decision:** Actor IDs moved into the header.

**v2.0 revision (2026-04-28):** 16 bits → 8 bits per actor ID, because:
- 256 actors/core is sufficient: the CST (Context Switch Table) is HW-managed — the active actor context register fills the `src_actor` field in hardware, **unspoofable** (core software cannot override it)
- The freed 2 × 8 bits (16 bits total) expand the `seq` field from 8 → 16 bits, enabling larger fragmented message sequences
- DDR5 capability slot actor-level ACL still works (`src[24] + src_actor[8]` defence-in-depth at the controller, see `ddr5-architecture-hu.md` v1.3)
- Crash recovery: only the crashed actor's capabilities are revoked
- Router dispatch: readable from header, no need to inspect payload

**Final decision (v2.0):** 8-bit src_actor + 8-bit dst_actor in the header. The `src_actor` is filled by core HW (CST active context register), the router fills `src` — both are unspoofable.

### Decision 4: Why `len[8]` (len+1 encoding)?

**Rejected (v1.0):** `len[9]` (max 511). Covers 256 bytes, but 1 bit wasted — the 257–511 range is never used.

**Rejected:** `len[16]` (max 65,535). Oversized — the freed bits are more useful elsewhere.

**Rejected:** `len[8]` direct encoding (max 255). Does not cover the 256-byte payload in v3.0.

**Final decision (v2.0/v2.1):** `len[8]` with +1 encoding: stored value 0–255, actual payload size `len + 1` bytes. Zero-byte (header-only) messages are indicated by the `flags.zero_len` bit. In v3.1 the max payload is 128 bytes (`len ≤ 127`); the upper 128 values (`len = 128..255`) are reserved for the future `BUS_WIDTH=256` upscale. Advantages:
- 8 bits: word-boundary alignment (as part of a 32-bit word)
- Full 1–256 range coverage without waste (forward-compatible to future upscale)
- The freed 1 bit (len[9] → len[8]) + former reserved bits made room for CRC-16

### Decision 5: Why CRC-16 for payload?

**In v1.0:** Only CRC-8 over the header. Payload integrity was not hardware-checked.

**Final decision (v2.0):** CRC-16 (16 bits) computed over payload, stored in header Word 3. CRC-8 (8 bits) is then computed over the full header (bits 127..8), **including the CRC-16 value**. This way, header integrity also protects the payload CRC — no single bit-flip goes undetected.

## Changelog

| Version | Date | Change |
|---------|------|--------|
| 2.4 | 2026-06-01 | **The "~80% ≤48 byte" distribution marked as a design assumption (not measured).** In the "Rejected: fully fixed cell" rationale the figure is now "estimated", pointing to the main note in `interconnect-en.md`. Annotation clarification only; format spec unchanged. |
| 2.3 | 2026-05-03 | **Bandwidth table expansion** in the "Future upscale" section — for every `BUS_WIDTH` value (128/256/512/1024 bit) raw link bandwidth at 50 MHz / 500 MHz / 1 GHz clocks. Rationale for the frequency columns: 50 MHz Sky130 I/O target, 500 MHz CFPU reference core clock, 1 GHz aspirational F6+. Effective payload bandwidth (~88.9% raw worst-case) recorded as a note. Additive change only; format spec unchanged. |
| 2.2 | 2026-04-28 | **`flags.ddr5_cap` HW-only bit allocated.** From the former `reserved[3]` field, one bit (bit 2) was named `ddr5_cap` with the meaning: the first 8 bytes of payload are a HW-attached DDR5 capability slot. The bit can **only be set by the core HW request assembler**; the actor SW `send` opcode has it masked to 0. The flags table now has a "Writable by" column. Details: [`docs/ddr5-architecture-hu.md`](../docs/ddr5-architecture-hu.md) v1.3 |
| 2.1 | 2026-04-28 | **v3.1 interconnect rollback synchronization:** L0 bus 256→128 bits, max payload 256→128 bytes (`CELL_SIZE = 128`), buffer slot 272→144 bytes. Header layout **unchanged** (16 bytes, 4×32 bits). `len[8]` semantics unchanged (`len+1`), but v3.1 max is 128 (`len ≤ 127`); the upper 128 values reserved for future `BUS_WIDTH` upscale. `BUS_WIDTH` RTL parameter introduced (default 128, future 256/512/1024). DDR5 burst alignment updated (BL32 = 128 bytes native). Rationale: [`docs/decision-bus-rollback-en.md`](../docs/decision-bus-rollback-en.md) |
| 2.0 | 2026-04-28 | Header reorganization: 4 × 32-bit word layout; src_actor/dst_actor 16→8 bits (HW-managed CST); seq 8→16 bits; len[9]→len[8] (len+1 encoding); CRC-16 added (payload integrity); flags expansion (pri, zero_len); 256-bit link flit table; decision log update (decisions 3–5) |
| 1.0 | 2026-04-22 | Initial version — 256-byte payload, len[9], header bit fields, variable link occupancy, DDR5 burst alignment, decision log |
