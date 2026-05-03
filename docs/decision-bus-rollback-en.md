---
status: decision
---

# Decision: L0 Bus Rollback 256→128 bit (v3.1)

> Magyar verzió: [decision-bus-rollback-hu.md](decision-bus-rollback-hu.md)

> Version: 1.0

> Status: Architecture decision, effective 2026-04-28. Affects `interconnect-en.md` v3.1, `specs/cell-format-en.md` v2.1, and `internal-bus-en.md` v1.1.

## Summary

v3.0 (`interconnect-en.md`) introduced the 256-bit L0 cluster mesh link and the 16-byte header + max 256-byte payload cell format. In v3.1 **we roll back the L0 bus width to 128 bit and the max payload to 128 byte**. The header layout remains unchanged (16 byte). The scaling rule (see below) is preserved so that future upscaling (256/512/1024 bit) can be done cleanly.

## The scaling rule

v3.1 codifies the following design rule for L0 bus and cell sizing:

```
header_size_byte = bus_width_bit / 8       (= 1 flit)
payload_size_byte = 8 × header_size_byte    (= 8 flit)
cell_size_byte = 9 × header_size_byte       (= 9 flit, header overhead 11%)
```

This guarantees:

1. The header is **always exactly 1 flit** — no half-flit waste.
2. The payload is **always an integer flit count** — no sub-flit padding.
3. The header overhead is **constant 11%** at every bus width.

| Bus width | Header | Max payload | Max cell | Cell flits | Header overhead |
|---|---|---|---|---|---|
| **128-bit (v3.1, current)** | **16 byte** | **128 byte** | **144 byte** | **9 flits** | **11%** |
| 256-bit (v3.0, rejected) | 16 byte | 256 byte | 272 byte | 9 flits + 0.5 pad | 50% pad in header flit |
| 256-bit (future upscale) | 32 byte | 256 byte | 288 byte | 9 flits | 11% |
| 512-bit (future) | 64 byte | 512 byte | 576 byte | 9 flits | 11% |

The v3.0 mistake was that the 16-byte header was **kept** at the v2.4 size (designed for the 42-bit bus) while the bus was widened to 256-bit — the header occupied **half a flit**, with 16 byte of padding in every cell.

## Why exactly 128 bit?

### Conservatism for F2.7 FPGA bring-up

The current roadmap phase (F2.7) targets the **A7-Lite 200T FPGA**. A 256-bit parallel NoC link is hard for Vivado/OpenXC7 routing to handle (many global wires, high LUT footprint in the router crossbar). The 128-bit link is **half the wire budget**, and every industrial FPGA NoC reference (Tilera Tile, AsAP, ZedBoard NoC) sits in this range.

### The 16-byte header is exactly 1 flit

The header layout is already 128 bit in v3.0 (4 × 32 bit words, see `interconnect-en.md` v3.0). Keeping it unchanged at 128-bit bus width makes the header **exactly 1 flit** — no spec rewrite, no field rearrangement, only the `len` semantics are constrained to 1-128 (the 8-bit field stays `len+1`, only the upper 128 values are unused; available automatically on future upscale).

### Typical actor messages remain small

The interconnect-hu.md v2.4 analysis shows that ~80% of actor messages have ≤48 byte payload, ~15% are 49-64 byte, ~5% are larger. A 128-byte max payload **covers 95-100% of traffic** in a single cell — state migration and code-load chunks split into 2× more cells (~10% header overhead in those rare large messages), but this does not dominate the system.

### DDR5 burst alignment

The 128-byte payload matches **DDR5 BL32** (Burst Length 32, ×4 byte = 128 byte) native burst unit. 64 byte (BL16) is also supported. The `ddr5-architecture-hu.md` capability grant + CAM ACL model is unchanged, only the fragment size shifts.

### Wire budget within a hop

L0 cluster mesh hop distance: ~330 µm (4×4 mesh, ~1.1 mm cluster). Wire pitch at 5nm: ~0.5 µm. 128-bit link wire bundle: 64 µm — comfortably fits within the 330 µm hop including repeaters. At 256-bit the bundle was 128 µm, still feasible but with higher routing density.

## What we lose

| Metric | v3.0 (256-bit) | **v3.1 (128-bit)** | Change |
|---|---|---|---|
| L0 throughput @ 500 MHz | 16 GB/s | **8 GB/s** | −50% |
| Max cell payload | 256 byte | 128 byte | −50% |
| Typical 48B message flit count | 2 flits | 4 flits (header + 3 × 16B payload) | +2 flits |
| Typical 48B message hop latency | 2H + 1 cc | 2H + 3 cc | +2 cc |
| Worst case cell flits | 9 flits | 9 flits | 0 (unchanged!) |
| Worst case cell latency | 2H + 8 cc | 2H + 8 cc | 0 (unchanged!) |

Worst-case latency is **unchanged** (9 flit drain), because the flit count is the same — only each flit is smaller. Typical actor messages are 2 cc slower per hop; cross-region 18 hops adds 36 cc (~72 ns @ 500 MHz). The system-level effect is small, since mailbox latency is typically ~100-300 ns.

## What we gain

1. **Clean flit alignment** — header is exactly 1 flit, no padding waste.
2. **FPGA-friendly routing** — half the wire budget, easy to route on A7-Lite 200T.
3. **Industry-standard range** — 128-bit on-chip mesh link matches Tilera Tile-Gx, Adapteva Epiphany, and STMicro PNoC references.
4. **DDR5 BL32 alignment** — 128 byte = 1 DDR5 burst (BL32 × 4 byte) native size.
5. **Simple upscaling** — if experience shows 8 GB/s is insufficient, setting the `BUS_WIDTH` RTL parameter to 256-bit (and accordingly header to 32 byte, payload to 256 byte) scales the entire architecture proportionally.

## Upscale criteria

A future v3.1 review would be motivated by these empirical metrics:

1. **L0 link utilization > 60% sustained** — 8 GB/s saturated, workload bandwidth-bound (not latency-bound).
2. **Frequent state migration** — fragment overhead (10-20% on large messages) causing significant system-throughput cost.
3. **DDR5 prefetch streaming** — the 128 byte burst size suboptimal for a specific workload memory access pattern (HBM transition, or DDR5 BL64 extension).

If **two** criteria are met, a v3.2 review may be warranted. F4 multi-core RTL and F2.7 FPGA bring-up real measurements provide the data.

## Alternatives — decision trail

### A) Keep v3.0 256-bit / 16B header / 256B payload combination

- **Pro:** Higher L0 throughput (16 GB/s), larger max cell (256B payload).
- **Contra:** Header occupies half a flit (16B / 32B = 0.5 flit), 50% pad in header flit on every cell. F2.7 FPGA routing hard with the 256-bit parallel link.
- **Rejected:** Wire waste and FPGA-friendliness take priority.

### B) v3.0 256-bit + header expanded to 32 byte (1 flit alignment)

- **Pro:** No header padding, +128 bit free fields (Fragment ID, AuthCode hash, Trace ID, extended QoS).
- **Contra:** Header layout breaking change. F2.7 FPGA routing with 256-bit parallel link remains hard.
- **Rejected for now:** Premature to expand the header without concrete usage experience. If the F4+ phase raises a need (e.g., inline tracing), v3.2 will revisit this variant.

### C) **128-bit bus / 16B header / 128B payload (chosen v3.1)**

- **Pro:** Clean flit alignment (header = 1 flit). FPGA-friendly. Header layout unchanged. Industry-standard range. Simple upscaling via `BUS_WIDTH` parameter.
- **Contra:** 8 GB/s L0 throughput (vs 16 GB/s in v3.0). Max payload 128 byte (vs 256 byte).
- **Chosen:** The conservative path for F2.7, preserving the upscale option.

### D) Bus width = entire cell (272 byte = 2176-bit), 1 cc/hop

- **Pro:** Logically clean, fixed 1 cc/hop latency, no flit pipeline, no body drain, no wormhole.
- **Contra:** Wire bundle ~1.1 mm wide (wider than 0.33 mm hop distance → physically does not fit). At L1/L2/L3 chip-scale crossbar (cm range) impossible. Wire budget ~8.5× the 256-bit. Typical 48B message 6× over-provisioned.
- **Rejected:** Physical layout constraint.

## Implementation impact

v3.1 affects the following documents:

- `docs/interconnect-en.md` v3.0 → **v3.1** — L0 link 256→128 bit, payload 256→128 byte, cell 272→144 byte, throughput, latency tables, link types
- `docs/interconnect-hu.md` — Hungarian mirror
- `specs/cell-format-en.md` v2.0 → **v2.1** — payload 256→128 byte, len semantics
- `specs/cell-format-hu.md` — Hungarian mirror
- `docs/internal-bus-en.md` v1.0 → **v1.1** — "Tile-level NoC: 256→128 bit", terminology fix (cluster = 16 core), L1/L2/L3 link types clarified, v3.1 reference
- `docs/internal-bus-hu.md` — Hungarian mirror
- `docs/ddr5-architecture-en.md` — DDR5 burst alignment check (128B = BL32 × 4B compatible)
- `web/{en,hu}/blog/internet-on-chip.html`, `scaling-cores.html` — reference updates

The RTL parameterization (future F4 phase) introduces the `BUS_WIDTH` RTL parameter, default 128, configurable 256/512/1024 (upscale).

## Related documents

- [`interconnect-en.md`](interconnect-en.md) — L0 cluster mesh, hierarchy, switching model
- [`internal-bus-en.md`](internal-bus-en.md) — intra-core bus sizing (Nano/Actor 256, Rich 512, ML 1024, Seal 64 — independent of NoC bus)
- [`specs/cell-format-en.md`](../specs/cell-format-en.md) — header and payload bit-level layout
- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — TLP > ILP philosophy, static ILP, in-order pipeline
- [`ddr5-architecture-en.md`](ddr5-architecture-en.md) — DDR5 controller, capability grant, CAM ACL

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-28 | Initial version — rationale for L0 bus rollback 256→128 bit, scaling rule (header = 1 flit, payload = 8 flits), alternatives A/B/C/D, upscale criteria |
