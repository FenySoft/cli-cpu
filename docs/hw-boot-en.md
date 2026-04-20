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

### 2c. Boot source selection

The Seal Core can load the binary to verify from **multiple sources**. The boot source is determined by the `BOOT_SRC` configuration (FPGA: synthesis-time parameter; ASIC: eFuse/pin-strap).

#### Boot source table (XC7A200T FPGA prototype)

| # | Source | MMIO base | Speed | Use case |
|---|--------|-----------|-------|----------|
| 0 | **QSPI Flash** | `0xF0001000` | ~50 MB/s (Quad) | Normal production boot — reuses on-board configuration flash |
| 1 | **UART** | `0xF0001100` | ~1 MB/s | Development, debug, recovery — streamed from host |
| 2 | **BRAM (on-chip)** | `0xF0001200` | Immediate (1 cc) | Firmware baked at synthesis time — test / CI |
| 3 | **Ethernet** | `0xF0001300` | ~12 MB/s | Remote boot — from network (PXE-like), multi-board cluster |
| 4 | **JTAG** | — (dedicated) | ~10 MB/s | Debug-boot — directly from OpenOCD / Vivado |

#### Boot device scan order

After POR, the Seal Core firmware **probes** boot sources in a fixed priority order. At each source, it attempts to read a binary header magic. The first source that returns a valid header → boot proceeds from there.

```
Seal Core firmware (boot device scan):

  for each source in priority order:
      1. Initialize source (QSPI: config, UART: wait RTS, ETH: PHY link, ...)
      2. Read header with timeout (magic + size + cert offset)
      3. If valid magic ("TSCL" or "T0CL") → SELECTED, exit loop
      4. If timeout or invalid magic → next source

  If none valid → HALT + FAULT signal
```

**Priority order:**

| Priority | Source | Timeout | Rationale |
|----------|--------|---------|-----------|
| 1. | **JTAG** | 10 ms | Debug-boot — if JTAG is active, it always wins (developer intentional) |
| 2. | **BRAM** | 0 (immediate) | If synthesis-baked firmware exists, it's always valid |
| 3. | **UART** | 50 ms | Host-initiated — if the host sends RTS within timeout |
| 4. | **Ethernet** | 100 ms | Remote boot — waits for PHY link-up + magic frame |
| 5. | **QSPI Flash** | 200 ms | Production default — tried last but is the "safe fallback" |

**Note:** the order is designed so that developer/debug sources (JTAG, BRAM, UART) take precedence over the production source (QSPI). This ensures a "bricked" flash system can always be recovered via JTAG or UART.

**On FPGA:** the presence of each source is a synthesis-time parameter (`HAS_UART_BOOT`, `HAS_ETH_BOOT`, etc.). If a source is not synthesized, the scan skips it.

**On ASIC (F6+):** all sources are present in hardware; individual sources can be disabled via eFuse (production lockdown: only QSPI remains).

#### Boot flow from the discovered source

Once a source is selected, the flow is identical in all cases:

```
Seal Core firmware (boot load + verify):
  1. Read binary header (size, cert offset, flags)
  2. Stream binary + cert → SRAM buffer (64-byte chunks)
  3. SHA-256 HW verify (streaming, per chunk)
  4. WOTS+/Merkle verify (on the cert)
  5. If VALID → SEAL into QRAM CODE region
  6. If INVALID → ZEROIZATION + HALT
```

#### QSPI Flash registers (source #0)

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

### Boot source selector

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| BOOT_SRC_FOUND | `0xF0000F00` | R/O | 4 bytes | Discovered boot source (0=JTAG, 1=BRAM, 2=UART, 3=ETH, 4=QSPI, 0xFF=none) |
| BOOT_STATUS | `0xF0000F04` | R/O | 4 bytes | 0=scanning, 1=loading, 2=verifying, 3=done, 0xFF=fail |
| BOOT_SRC_MASK | `0xF0000F08` | R/O | 4 bytes | Synthesis/eFuse: which sources are present (bit0=JTAG, bit1=BRAM, bit2=UART, bit3=ETH, bit4=QSPI) |

### Flash controller (boot source #0)

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| QSPI config | `0xF0001000` | R/W | 4 bytes | Enable, SPI mode, clock divider |
| QSPI flash addr | `0xF0001004` | R/W | 4 bytes | Flash read address |
| QSPI binary size | `0xF0001008` | R/O | 4 bytes | Binary size (from flash header) |
| QSPI data | `0xF000100C` | R/O | 64 bytes | Next 64-byte chunk from flash (= cell payload size) |

### UART boot controller (boot source #1)

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| UART config | `0xF0001100` | R/W | 4 bytes | Baud rate, parity, enable |
| UART status | `0xF0001104` | R/O | 4 bytes | RX ready, TX empty, error flags |
| UART data | `0xF0001108` | R/W | 64 bytes | RX/TX buffer (64-byte chunk) |

### BRAM boot (boot source #2)

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| BRAM base | `0xF0001200` | R/O | 4 bytes | Start address of firmware stored in BRAM |
| BRAM size | `0xF0001204` | R/O | 4 bytes | Firmware size (fixed at synthesis time) |

### Ethernet boot controller (boot source #3)

| Register | Address | Type | Size | Description |
|----------|---------|------|------|-------------|
| ETH config | `0xF0001300` | R/W | 4 bytes | PHY init, MAC address[31:0] |
| ETH config2 | `0xF0001304` | R/W | 4 bytes | MAC address[47:32], VLAN, enable |
| ETH status | `0xF0001308` | R/O | 4 bytes | Link up, RX ready, frame count |
| ETH data | `0xF000130C` | R/O | 64 bytes | Next 64-byte chunk (from Ethernet frame payload) |

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
| 1.1 | 2026-04-20 | Boot source selection: 5 sources (QSPI, UART, BRAM, Ethernet, JTAG) aligned to XC7A200T FPGA capabilities. MMIO registers extended for all boot sources. 64-byte chunk data reads (= cell payload size). |
| 1.0 | 2026-04-19 | Initial version — HW boot separated from NeuronOS boot-sequence-hu.md |
