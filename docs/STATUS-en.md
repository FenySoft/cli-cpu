---
status: living
---

# Document status index

> Magyar verzió: [STATUS-hu.md](STATUS-hu.md)

This file records the **status** of every document under `docs/`. It is the single source of truth for status; the `status:` frontmatter field embedded in each file matches this table.

> **Purpose:** to prevent a vision-level proposal (e.g. an AI-generated concept) from later appearing as established fact merely because it lives in a markdown table. Every reader (human or AI) **must see** the content's status before relying on it.

## Status rubric

| Status | Meaning | Reference weight |
|---|---|---|
| **`vision`** | Creative design. Numbers are working hypotheses; validatable only after F4–F6 RTL/silicon. | Inspirational. **Do not** cite precise numbers from such docs without cross-checking. |
| **`draft`** | Detailed proposal, no ADR or decision behind it. | Starting point. Promote → `decision` or `specs/` is required before treating as fact. |
| **`decision`** | Formal Architecture Decision Record (ADR). | **Mandatory.** In case of conflict, overrides `vision` / `draft` docs. |
| **`spec-candidate`** | Implemented and tested; worth promoting to `specs/`. | Reliable. After promotion lives in `specs/`, here only as reference. |
| **`policy`** | Project-strategic direction (brand, openness, communication). | Mandatory in its area, but not technical spec. |
| **`living`** | Continuously evolving planning document (e.g. roadmap). | Current; check the date on every reference. |
| **`archived`** | Historical snapshot. | **Not** a reference basis; only records the past. |
| **`reference`** | External documentation (datasheet, board reference). | Mandatory for the relevant hardware. |
| **`mirror`** | Mirrored from another repo (e.g. `FenySoft/Symphact`). Original location in the `> Source:` field. | The original repo is authoritative. |

## Addition rule

**A new doc under `docs/` MAY be added ONLY** with an entry in the STATUS table. A new concept inside an existing doc MAY leave `vision`/`draft` status ONLY by promotion to `decision`.

## Promotion path

```
vision → draft → decision → spec-candidate → specs/<file>.md (versioned, authoritative)
```

A step may be skipped (e.g. `draft → spec-candidate`), but going backwards is not allowed.

## Current status table

Last audit: **2026-05-03**

### `vision` (38 files, 19 pairs)

> Validatable after F4 RTL and F6 silicon. Numbers are working hypotheses.

| File pair | Note |
|---|---|
| `architecture-{hu,en}.md` | 1432 lines; **stacked AI-generated layers** (Actor Scheduling Pipeline, QRAM Ext, AES/CMAC F5+). Needs cleanup. |
| `authcode-{hu,en}.md` | Validatable in F5 RTL. |
| `cfpu-ml-max-{hu,en}.md` | "v2.0-draft", but content is F6+ ML chip vision. |
| `chiplet-packaging-{hu,en}.md` | F6+ silicon packaging. |
| `core-types-{hu,en}.md` | Validatable after F4 RTL. **Conflicts** with `architecture-hu.md` AES/CMAC engine accounting. |
| `ddr5-architecture-{hu,en}.md` | F5+ DDR5 capability slot. |
| `faq-{hu,en}.md` | Mixed (policy + vision-level numbers). |
| `hw-attack-immunity-{hu,en}.md` | Recent (2026-05-02), but immunity table still vision. |
| `hw-boot-{hu,en}.md` | F5+ HW boot sequence. |
| `interconnect-{hu,en}.md` | The cell-format part has been **promoted** → `specs/cell-format-{hu,en}.md`. Remainder: vision. |
| `internal-bus-{hu,en}.md` | Bus-width estimates. |
| `microarch-philosophy-{hu,en}.md` | F1.5 references. |
| `perf-vs-riscv-{hu,en}.md` | Based on literature precedents. |
| `quench-ram-{hu,en}.md` | May start to materialize in F5 RTL. |
| `sealcore-{hu,en}.md` | Validatable in F5 RTL. |
| `secure-element-{hu,en}.md` | F6+ secure element vision. |
| `security-{hu,en}.md` | Threat model + immunity vision. |
| `use-case-video-{hu,en}.md` | Core-count estimate from literature data. |
| `vision-{hu,en}.md` | The high-level vision. |

### `draft` (4 files, 2 pairs)

| File pair | Note |
|---|---|
| `ISA-CIL-Seal-{hu,en}.md` | Self-labels as "v0.1 (draft)". F5+ ISA. |
| `certification/CFPU-SEC-v1-{hu,en}.md` | Certification framework. "v1" name suggests spec-grade, but content is F5+. |

### `decision` (2 files, 1 pair) — formal ADR

| File pair | Note |
|---|---|
| `decision-bus-rollback-{hu,en}.md` | L0 256→128 bit rollback. **To be kept as a model.** |

### `spec-candidate` (2 files, 1 pair) — to be promoted

| File pair | Note |
|---|---|
| `ISA-CIL-T0-{hu,en}.md` | The 64 opcodes are implemented in the simulator, 187 tests. **Promote to:** `specs/isa-cil-t0-{hu,en}.md`, `Version: 1.0`. |

### `policy` (6 files, 3 pairs)

| File pair | Note |
|---|---|
| `brand-{hu,en}.md` | Brand and naming guide (CLI-CPU vs CFPU). |
| `tool-openness-{hu,en}.md` | Open-source toolchain strategy. |
| `blog/series-plan-{hu,en}.md` | Blog communication plan. |

### `living` (4 files, 2 pairs)

| File pair | Note |
|---|---|
| `roadmap-{hu,en}.md` | F0–F7 phases, continuous updates. |
| `STATUS-{hu,en}.md` | This index itself. |

### `archived` (10 files, 5 pairs)

| File pair | Note |
|---|---|
| `nlnet-application-draft-{hu,en}.md` | NLnet application material. |
| `nlnet-corrections-{hu,en}.md` | Post-submission corrections. |
| `symphact-{hu,en}.md` | Moved to `FenySoft/Symphact` repo. |

### `reference` (2 files, 1 pair)

| File pair | Note |
|---|---|
| `A7-Lite/A7-Lite-{hu,en}.md` | MicroPhase A7-Lite XC7A200T FPGA board reference. |

### `mirror` (12 files, 6 pairs)

> Original location: `FenySoft/Symphact` repo.

| File pair | Note |
|---|---|
| `osreq-from-os/osreq-001-tree-interconnect-{hu,en}.md` | Tree-topology interconnect requirement. |
| `osreq-from-os/osreq-002-mmio-memory-map-{hu,en}.md` | MMIO memory map. |
| `osreq-from-os/osreq-003-core-reset-{hu,en}.md` | Core reset mechanism. |
| `osreq-from-os/osreq-004-dma-engine-{hu,en}.md` | DMA engine requirement. |
| `osreq-from-os/osreq-005-mailbox-interrupt-{hu,en}.md` | Mailbox interrupt vs polling. |
| `osreq-from-os/osreq-006-interchip-link-{hu,en}.md` | Inter-chip link protocol. |

## Known conflicts

Internal inconsistencies surfaced during the 2026-05-03 audit — to be resolved via ADR or promotion:

| Conflict | Affected docs |
|---|---|
| **AES/CMAC engine present/absent on Actor and Rich cores** | `architecture-{hu,en}.md` (per-core AES F5+) ⚡ `core-types-{hu,en}.md` (Crypto: None) |
| **Actor core area: 0.023 mm² or 0.036 mm²** | `core-types-{hu,en}.md` (5nm rescaling) ⚡ `architecture-{hu,en}.md` line 1308 (legacy 7nm number) |
| **Rich core area: 0.059 mm² or 0.083 mm²** | same as above |
| **PUF availability F5+ or F6.5+** | `architecture-{hu,en}.md` 1305 (per-core key from PUF, F5+) ⚡ `architecture-{hu,en}.md` 384 (Crypto Actor + PUF F6.5) |
| **Multi-cell message buffering for sleeping actor inbox — no spec** | `architecture-{hu,en}.md` Actor Scheduling Pipeline (only single-cell case is described) |

Resolving these is **NOT** part of this audit commit; they are merely recorded. Each requires a separate ADR.
