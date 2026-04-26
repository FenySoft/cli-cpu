# CFPU Internal Bus Sizing

> Magyar verzió: [internal-bus-hu.md](internal-bus-hu.md)

> Version: 1.0

> **⚠️ Vision-level document.** The bus widths, area, and power figures presented here are working hypotheses extrapolated from documented sources (TSMC 5nm SRAM macro datasheets, AMD Zen, Apple M, NVIDIA H100 published parameters). Precise values can only be validated after F2.7 FPGA bring-up and F6 silicon. The document records design direction and decision trail, not final parameters.

## Why internal bus width matters

The two slowest data movements within a CFPU core are:

1. **Stack/local ↔ register file** (within a core's pipeline) — an `add` operation requires 3 register-port accesses in one cycle
2. **Actor context ↔ SRAM** (warm-context cache spill/fill) — moving the entire register frame on actor switch

Per the `microarch-philosophy-en.md` decision, every CFPU core is in-order with static ILP. In this model, **bus width directly determines** how many cycles it takes to switch actors, and what multi-issue rate is permissible — because OoO and scoreboarding cannot help with the port bottleneck.

## The fundamental dilemma — port count, not latency

Single-cycle on-chip SRAM latency is 1–2 cycles, **near register-level**. The problem is not speed but port count:

| Storage form | Port configuration | `add` op in 1 cycle |
|---|---|---|
| Single-port SRAM (1R1W) | 1 read + 1 write/cycle | **NO** — 2 reads + 1 write needed |
| Dual-port SRAM (2R1W) | 2 reads + 1 write/cycle | Yes |
| Multi-port reg file (3R2W) | 3 reads + 2 writes/cycle | Yes, even 2-issue fits |

Multi-port SRAM cost:
- 1R1W → 2R1W: ~1.8× area
- 2R1W → 3R1W: another ~1.7× area (~3× total)
- 3R1W → 3R2W: another ~1.3× (~4× total)

A 32 KB Rich core SRAM macro at 5nm is ~0.005 mm² with 1R1W; ~0.02 mm² with 3R2W. The register file (32×32-bit = 128 byte) is trivial in 3R2W (~0.001 mm²).

**Consequence**: the hot path content (TOS, locals) must live in a register file; SRAM is only for passive contexts.

## Actor context size

Per `core-types-en.md`, the Rich core runs full CIL (objects, GC, exceptions). "Context" here is the execution state, not the entire heap:

| Component | Size |
|---|---|
| Register stack (max stack + locals) | 16–32 × 32-bit = 512–1024 bit |
| PC, SP, flags | ~64–96 bit |
| Actor state (mailbox pointer, priority, supervisor link) | ~96–128 bit |
| **Total** | **~672–1248 bit, rounded to 1024 bit** |

An actor context is therefore **~1 Kb** — this is what must move on a warm-context cache miss.

## Cycle count as a function of bus width

Total cycle count for a 1024-bit context move as a function of internal bus width:

| Internal bus | Context move | Spill+fill in parallel |
|---|---|---|
| 32-bit | 32 cycles | 64 cycles |
| 64-bit | 16 cycles | 32 cycles |
| 128-bit | 8 cycles | 16 cycles |
| **256-bit** | **4 cycles** | **8 cycles** (good compromise for small cores) |
| **512-bit** | **2 cycles** | **4 cycles** (good compromise for Rich) |
| **1024-bit** | **1 cycle** | **2 cycles** (only needed for ML core) |

The **64-cycle stall** (assumed by earlier analyses with a 32-bit bus) **shrinks to a few cycles at 256+ bit**. The warm-context cache concept becomes viable only at this point: with a background prefetch hint the stall can drop to **0 cycles** on the hot path.

## HW cost — area and power

Estimates at 5nm node, 1 mm bus length:

| Layer | 32-bit | 256-bit | 512-bit | 1024-bit |
|---|---|---|---|---|
| Wire trace | ~32 | 256 | 512 | 1024 |
| Metal layer usage | M3–M4 | M3–M5 | M4–M6 | M4–M7 + tile routing |
| Repeater cells (every 500 µm) | ~64/mm | ~512/mm | ~1K/mm | ~2K/mm |
| SRAM macro port width | 32-bit | 256-bit (8 banks × 32) | 512-bit (8 banks × 64) | 1024-bit (16 banks × 64) |
| Dynamic power (1 GHz, 50% activity) | ~0.3 mW | ~2.5 mW | ~5 mW | ~10 mW |
| Reg file area increase (relative) | 1× | ~1.3× | ~1.8× | ~2.8× |

**Critical thresholds:**

- **256-bit** fits in a simple tile routing at 5nm node, ~5–7% area overhead at tile level
- **512-bit** is tight within a tile, ideal as a Rich core back-end bus
- **1024-bit** within a tile is expensive; better solved as 4-bank × 256-bit local + 1024-bit logical view (HBM-style)

## Industry references

| Chip / block | Internal bus | Note |
|---|---|---|
| AMD Zen 4 — L1↔reg path | 512-bit | OoO core, multi-issue background |
| Apple M4 P-core — L1↔reg | 256-bit | OoO core |
| NVIDIA H100 SM — reg file BW | ~8 Kbit/cycle aggregate | many warps in parallel |
| Cerebras WSE local fabric | 256-bit | many small cores |
| Tenstorrent Tensix NoC | 1024-bit | tile-load baseline |
| HBM3 die interface | 1024-bit | chiplet scale |
| **CFPU Rich (target)** | **512-bit** | many cores, in-order |
| **CFPU Nano (target)** | **256-bit** | minimum core, many actors |
| **CFPU ML/Matrix (target)** | **1024-bit** | tile-load baseline |

256–512 bit is **industry standard** in modern 5nm AI/many-core chips, not extravagant.

## Selected sizing — per core type

| Layer | Bus width | Reason |
|---|---|---|
| **Nano** internal reg ↔ SRAM | **256-bit** | 4–8 actor warm contexts, 4-cycle full move; minimal core, many actors |
| **Actor core** | **256-bit** | Close to Rich, same building block; compatibility preserved |
| **Rich core** internal back-end | **512-bit** | 32 reg + multi-issue + headroom for 64-bit ISA option |
| **ML/Matrix core (CFPU-ML MAC Slice)** | **1024-bit** | Tile-load baseline, vector pipe (32 elements × 32-bit / cycle) |
| **Seal core** | **64-bit** | Auditability > speed, minimum logic |
| **Tile-level NoC** (4–8 cores) | **256-bit** | Shared lane for mailbox + context spill |
| **Chip-level NoC** (tile ↔ tile) | **128-bit** | Current value in `interconnect-en.md` v2.4, retained |
| **Toward DDR5 hub** | **128-bit** (2 channels × 64-bit) | DDR5 physical limit |

## Alternatives — decision trail

### A) Uniform 32-bit internal bus everywhere

- Simple layout, small area
- 32-cycle context move → warm-context cache concept collapses
- Multi-issue impossible (port bottleneck)
- **Rejected**: this kills the real win of the many-core model in the context cache

### B) Uniform 256-bit everywhere

- Sufficient for Nano and Rich
- Underprovisioned on the ML core (4-cycle context vs 1-cycle ideal)
- Simpler design
- **Partially adopted**: this is the fallback if the ML-tile 1024-bit bus is not worth the complexity

### C) Heterogeneous bus (selected)

- Per-core optimum
- Nano 256, Rich 512, ML 1024
- More complex floorplan, but architectural heterogeneity (`core-types-en.md`) requires it anyway
- **Selected**: consistent with the core family design

### D) Uniform 1024-bit on every core

- Maximum performance
- Overprovisioned for Nano (10× area overrun on the small core)
- Power budget stretched across idle cycles
- **Rejected**: wasteful, against the Nano philosophy (small and many)

## Trade-offs to accept

- **Power hierarchy**: wide bus toggle power increases. Tile-level clock gating is mandatory so inactive tiles do not consume.
- **Layout tightness**: a 512+ bit bus forces the tile floorplan into a constrained pattern. Cores must be laid out "bus-spine-oriented" (Cerebras style), not freely.
- **DDR5 hub remains a bottleneck**: the 1024-bit tile bus does not reach DDR. Global memory access patterns must be cautious — handled by the [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) capability grant + CAM ACL model.

## Validation plan

1. **F1.5 (now)**: only a theoretical decision; bus width is parameterizable in RTL.
2. **F2.7 (FPGA, A7-Lite)**: a 1-core Rich prototype with 256-bit internal bus is buildable on FPGA (BRAM is strong). 512-bit is hard on FPGA, 1024-bit practically impossible — validated in simulation here.
3. **F4 (multi-core RTL)**: cycle-accurate verification on Verilator with sized SRAM macros.
4. **F6 (silicon)**: actual layout, post-silicon power and perf validation.

## Related documents

- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — TLP > ILP philosophy that motivates bus sizing
- [`core-types-en.md`](core-types-en.md) — core types, where bus size differs per core
- [`interconnect-en.md`](interconnect-en.md) — chip-level NoC bus (separate layer)
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — memory hub bottleneck
- [`cfpu-ml-max-en.md`](cfpu-ml-max-en.md) — ML core 1024-bit bus rationale

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-25 | Initial version — port bottleneck analysis, context move cycle counting from 32–1024 bit, selected sizing per core type, decision trail (uniform 32 / uniform 256 / heterogeneous / uniform 1024) |
