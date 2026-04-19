# Hardware Boot Sequence (HW Boot)

> Magyar verzió: [hw-boot-hu.md](hw-boot-hu.md)

> Version: 1.0

The purely **hardware-driven** process from CFPU chip power-on to Rich core start. This sequence occurs **before** the operating system (Neuron OS) — no software is involved.

> For the Neuron OS boot sequence (steps 4-11), see: [FenySoft/NeuronOS — boot-sequence-hu.md](https://github.com/FenySoft/NeuronOS/docs/boot-sequence-hu.md)

## Contents

1. [Overview](#overview)
2. [Step 1 — Power-On Reset (POR)](#por)
3. [Step 2 — Seal Core boot](#sealcore)
4. [Step 3 — Rich core start](#richcore)
5. [HW Register summary (MMIO)](#mmio)
6. [SRAM Layout (Rich core)](#sram)
7. [Core types from boot perspective](#coretypes)
8. [Changelog](#changelog)

---

## Overview <a name="overview"></a>

```
[Power supply]
     │
     ▼
[1. Power-On Reset] ──── POR circuit, all cores reset
     │
     ▼
[2. Seal Core starts] ── Mask ROM firmware (immutable)
     │                    Self-test, eFuse root hash read
     │                    QSPI flash → SRAM copy
     │                    SHA-256 + WOTS+/LMS HW verification
     │
     ├── FAIL → ZEROIZATION + HALT
     │
     ▼ OK
[3. Rich core starts] ── Seal Core signals: verified code ready
     │                    Rich core boots from Quench-RAM CODE region
     ▼
[Neuron OS boot] ─────── Software from here on (→ NeuronOS repo)
```

---

## Step 1 — Power-On Reset (POR) <a name="por"></a>

The POR circuit holds all cores in reset until the power supply stabilizes.

| Element | State after POR |
|---------|----------------|
| Seal Core | **Starts first** — mask ROM entry point |
| Rich core | Held in reset — **waits** for Seal Core enable |
| Nano cores (10,000+) | **Sleep mode** — wake-on-mailbox-interrupt |
| All SRAM | Contents undefined |
| Mailbox FIFOs | Empty |
| Program counter | 0 (all cores) |

**HW requirements:**
- POR (Power-On Reset) circuit
- Seal Core mask ROM address hardwired
- Rich core reset latch (controlled by Seal Core)
- Nano cores default sleep state

---

## Step 2 — Seal Core boot <a name="sealcore"></a>

The Seal Core is a **dedicated, non-programmable security core**. It runs from mask ROM firmware — not from flash, not from SRAM. Detailed description: [sealcore-en.md](sealcore-en.md)

### 2a. Self-test

The Seal Core verifies its own integrity:
- SHA-256 HW unit functional?
- WOTS+ HW verifier functional?
- SRAM clean (all zeros)?
- eFuse root hash readable?

### 2b. eFuse root hash read

32-byte SHA-256 hash — burned at manufacturing, **immutable**, 30+ year lifetime.

This is the root of the trust chain. Detailed trust chain description: [authcode-en.md §7](authcode-en.md#trustchain)

### 2c. QSPI flash read

The Seal Core reads the external flash via MMIO (`0xF0001000`):
- Neuron OS CIL binary
- Associated signature and certificate

### 2d. Hardware cryptographic verification

Verification is performed **entirely in hardware** using dedicated accelerators:

```
1. SHA-256(CIL bytecode) computation             ← HW SHA-256 unit (~80 cycles/block)
2. Compare with certificate hash field            ← code-hash check
3. WOTS+ public key reconstruction                ← HW WOTS+ verifier (~500 SHA-256 ops)
4. Leaf hash → Merkle root computation            ← HW Merkle path verifier (h=10 → 10 hashes)
5. Compare with eFuse root hash                   ← root-of-trust check
```

**Total verification:** ~512 SHA-256 operations = ~41,000 cycles @ 1 GHz = **~41 µs**

For the certificate format and signing model (PQC, WOTS+/LMS), see: [authcode-en.md](authcode-en.md)

### Seal Core HW accelerators

| Unit | Gate count | Function |
|------|-----------|----------|
| SHA-256 HW unit | ~5K gates | ~80 cycles/block (512-bit input) |
| WOTS+ verifier | ~3K gates | SHA-256 chain reconstruction (67 chains × ~7.5 hashes) |
| Merkle path verifier | ~2K gates | h=10 iterations = 10 SHA-256 hashes |
| **Total** | **~10K gates** | Full verify ~41 µs |

### Verification outcome

| Result | Action |
|--------|--------|
| **VALID** | Verified code is written to the **Quench-RAM CODE region**, SEAL-ed (immutable), Seal Core signals the Rich core: start. |
| **INVALID** | **ZEROIZATION** — all RAM and caches cleared. Chip enters **lockdown** mode. No code runs. |

---

## Step 3 — Rich core start <a name="richcore"></a>

| Event | Description |
|-------|-------------|
| Seal Core → Rich core signal | Register `0xF0002024`: `0` = wait, `1` = verified + go, `2` = fail + halt |
| Rich core reset released | Rich core boots from Quench-RAM CODE region |
| CODE region is read-only | SEAL-ed — the Rich core cannot modify it |
| CIL execution engine active | Eval stack, locals, call frames initialized |

The Rich core calls the first CIL method: `NeuronOS.Boot.Main()` — **software from here on** (→ [NeuronOS repo](https://github.com/FenySoft/NeuronOS)).

**HW requirements:**
- Quench-RAM CODE region (SEAL-ed, R/O for the Rich core)
- Rich core start signal receive (`0xF0002024`)
- CIL execution engine

---

## HW Register summary (MMIO) <a name="mmio"></a>

Boot-relevant registers. For the full MMIO map, see: [osreq-002 — MMIO Memory Map](osreq-from-os/osreq-002-mmio-memory-map-en.md)

### Seal Core registers

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| eFuse root hash | `0xF0002000` | R/O | 32 bytes | SHA-256 root hash — burned at manufacturing, **immutable** |
| Seal Core status | `0xF0002020` | R/O | 4 bytes | Self-test result, verify result, heartbeat |
| Seal Core → Rich core signal | `0xF0002024` | R/O | 4 bytes | 0 = wait, 1 = verified + go, 2 = fail + halt |
| Quench-RAM CODE base | `0xF0002030` | R/O | 4 bytes | Verified CIL binary start address |
| Quench-RAM CODE size | `0xF0002034` | R/O | 4 bytes | Verified CIL binary size |

### Flash controller

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| QSPI config | `0xF0001000` | R/W | 4 bytes | Enable, SPI mode, clock divider |
| QSPI flash addr | `0xF0001004` | R/W | 4 bytes | Flash read address |
| QSPI binary size | `0xF0001008` | R/O | 4 bytes | Binary size (from flash header) |
| QSPI data | `0xF000100C` | R/O | 1 byte | Next byte from flash |

### Core discovery and control

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| Core count (Nano) | `0xF0000100` | R/O | 4 bytes | Number of Nano cores |
| Core count (Rich) | `0xF0000104` | R/O | 4 bytes | Number of Rich cores |
| Mailbox base address | `0xF0000200` | R/O | 4 bytes | Mailbox FIFO physical address range start |
| Mailbox enable (per core) | `0xF0000300 + core_id × 4` | R/W | 4 bytes | Mailbox FIFO enable bit |
| Core status (per core) | `0xF0000400 + core_id × 4` | R/O | 4 bytes | Sleeping / Running / Error / Reset |
| Interrupt controller | `0xF0000600` | R/W | 16 bytes | Interrupt vector configuration |
| Mailbox address table | `0xF0000800 + core_id × 4` | R/O | 4 bytes | core-id → mailbox FIFO physical address |

---

## SRAM Layout (Rich core) <a name="sram"></a>

Rich core SRAM contents at the end of HW boot (step 3), before Neuron OS starts:

```
┌─────────────────────────────────┐ 0x00000000
│ CIL Code (SEAL-ed by Seal Core) │ ~16-48 KB (NeuronOS binary, VERIFIED, R/O)
├─────────────────────────────────┤ 0x0000C000
│ Eval Stack                      │ ~2-4 KB (CIL execution stack)
├─────────────────────────────────┤ 0x0000D000
│ Call Frames + Local Variables   │ ~4-8 KB (method calls)
├─────────────────────────────────┤ 0x0000F000
│ Heap (free)                     │ ~16-64 KB (populated after OS init)
├─────────────────────────────────┤ 0x0002F000
│ Mailbox FIFO (Rich core own)    │ ~64-512 bytes (8-64 slots)
├─────────────────────────────────┤ 0x0002F200
│ Free                            │
└─────────────────────────────────┘ 0x0003FFFF (256 KB)
```

---

## Core types from boot perspective <a name="coretypes"></a>

| Property | Seal Core | Rich Core | Nano Core |
|----------|-----------|-----------|-----------|
| **Boot order** | **FIRST** | Second (after Seal Core) | Last (started by OS) |
| **Firmware** | Mask ROM (immutable) | From flash (verified) | From flash (verified, T0) |
| **Programmable?** | **NO** (HW-burned) | Yes | Yes |
| **SRAM** | 64 KB (trusted zone) | 64-256 KB | 4-16 KB |
| **SHA-256 + WOTS+ HW** | **Yes** (dedicated) | No | No |
| **Mailbox FIFO** | None (not an actor) | Yes (HW) | Yes (HW) |
| **Count per chip** | 1 (or 2 for redundancy) | 1-4 | 10,000+ |

Detailed core description: [core-types-en.md](core-types-en.md)

---

## Changelog <a name="changelog"></a>

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-04-19 | Initial version — HW boot separated from NeuronOS boot-sequence-hu.md |
