# Seal Core — The CFPU Authentication Gatekeeper Core

> Magyar verzió: [sealcore-hu.md](sealcore-hu.md)

> Version: 1.0

This document describes the **Seal Core** component: a dedicated, simple, hardware-burned-firmware core that ensures **code-loading authenticity** on the CFPU chip. The Seal Core operates via two distinct mechanisms depending on CFPU phase — **pre-QRAM era** (F3-F5) through physical WE-pin routing, **QRAM era** (F5+) as an AuthCode verification gatekeeper. These are **two distinct mechanisms**, which this document treats in deliberately separated sections.

> **Vision-level document.** The Seal Core is present in the CFPU from F3 and persists across chip generations. However, its role stands **fundamentally differently** in pre-QRAM vs. post-QRAM contexts, so the document splits the two into separate sections with explicit transition-point marking.

## Table of Contents

1. [Motivation](#motivation)
2. [What is the Seal Core](#what-is-sealcore)
3. [Role in the CFPU brand family](#brand)
4. [General architecture](#architecture)
5. [Seal Core in the pre-QRAM era (F3-F5)](#preqram)
6. [Seal Core in the QRAM era (F5+)](#qram)
7. [The transition point](#transition)
8. [Boot and firmware immutability](#boot)
9. [Redundancy and graceful degradation](#redundancy)
10. [Accelerator functions](#accelerators)
11. [Security guarantees](#security)
12. [Open questions](#open)
13. [Phase introduction](#phases)
14. [References](#references)
15. [Changelog](#changelog)

## Motivation <a name="motivation"></a>

The CFPU security model (`docs/security-en.md`, `docs/authcode-en.md`) rests on one critical claim:

> Only authenticated, verified CIL bytecode may execute.

This guarantee presupposes **a single hardware gate** through which all incoming code passes. The gate is:
- **Trustworthy**: its own firmware is hardware-burned (mask ROM or eFuse), untamperable
- **Isolated**: its own code and operation are inaccessible to other cores
- **Dedicated**: its sole task is authentication and code-load control, not running application actors

This component is the **Seal Core**. A minimal, simple, audit-friendly core that enforces the authenticity of all CIL bytecode arriving at the CFPU.

## What is the Seal Core <a name="what-is-sealcore"></a>

The Seal Core is a **third core category** in the CFPU, alongside Nano and Rich cores:

| Attribute | Nano Core | Rich Core | **Seal Core** |
|-----------|-----------|-----------|----------------|
| CIL execution | subset CIL-T0 | full CIL + GC + FP | internal firmware only |
| Introduction phase | F3+ | F6+ | **F3+** (earliest) |
| Programmable with application code | yes | yes | **no** (code hardware-burned) |
| SRAM | 16 KB | 256 KB | 64 KB (trusted zone) |
| SHA-256 + WOTS+ accelerators | no | no | **yes** (dedicated HW) |
| Multiple instances on chip | 10-100 | 1-16 | **1 or more** (redundancy) |
| Boot | signed CIL load | signed CIL load | **immutable mask ROM / eFuse** |

The Seal Core **does not run application code**. Its firmware is hardware-burned (mask ROM or high-reliability eFuse array), and it **exclusively** performs:

- **Boot-time self-test** (verifies its own integrity at startup)
- **AuthCode verification** — signature checking of incoming `.acode` containers (see `docs/authcode-en.md`)
- **Code-loader duties** — writing verified bytecode into the CODE region
- **Heartbeat signal** to a central health monitor (for redundancy)

## Role in the CFPU brand family <a name="brand"></a>

The Seal Core fits into the family of complementary CFPU security mechanisms:

```
               ┌───────────────────────────────────────────┐
               │           CFPU security family            │
               └───────────────────────────────────────────┘
                                    │
       ┌────────────────┬───────────┼───────────┬───────────────┐
       │                │           │           │               │
  [Quench-RAM]    [AuthCode]   [CodeLock]   [Seal Core]   [BitIce +
   memory cell     code sign.   runtime W⊕X   gatekeeper    Neuron OS
                                              core          Card]
                                                           crypto + signing
```

The Seal Core is the **physical component** that **practically activates** the other mechanisms:
- The **AuthCode** verification flow runs here
- The **CodeLock** W⊕X enforcement (in pre-QRAM era) originates from WE-pin routing here
- The **Quench-RAM** CODE-region SEAL microcode-trigger is invoked here

## General architecture <a name="architecture"></a>

Seal Core internal components (identical across phases):

```
┌──────────────────────────────────────────────────────────┐
│                       Seal Core                           │
│                                                           │
│  ┌────────────────┐    ┌────────────────────────────┐    │
│  │  Boot firmware │    │  SRAM (64 KB trusted zone) │    │
│  │  mask ROM /    │    │  - AuthCode verify stack   │    │
│  │  immutable     │    │  - Session state           │    │
│  │  eFuse         │    │  - Revocation list cache   │    │
│  └────────┬───────┘    └────────────────┬───────────┘    │
│           │                             │                 │
│           ▼                             ▼                 │
│  ┌──────────────────────────────────────────────────┐    │
│  │    Simple CPU core (RISC-V or custom, small)     │    │
│  │    - 5-stage in-order pipeline                   │    │
│  │    - 16 register file                            │    │
│  └────────────┬─────────────────────────────────────┘    │
│               │                                           │
│   ┌───────────┼───────────┬────────────────┐             │
│   ▼           ▼           ▼                ▼             │
│ [SHA-256  ][WOTS+    ][Merkle path  ][Heartbeat          │
│  HW unit ][ verifier][  verifier   ][  output pin]       │
│                                                           │
│   ┌───────────────────┐                                   │
│   │ Output interface  │ ─── differs per era              │
│   │ (CODE RAM access) │    (see below)                   │
│   └───────────────────┘                                   │
└──────────────────────────────────────────────────────────┘
```

The **"Output interface"** is the only part that **materially changes** between phases — everything else (firmware, SRAM, SHA-256 HW, verifiers) is identical across phases.

## Seal Core in the pre-QRAM era (F3-F5) <a name="preqram"></a>

The pre-QRAM era runs from F3 Tiny Tapeout through the F5 RTL prototype. In this phase, CODE RAM is **an external commodity SRAM chip** with a single WE pin. Protection derives from **physical pin routing**.

### Core principle — defense by topology

> **The CODE RAM chip's WE pin is wired only to the Seal Core within the CFPU chip. No other core (Nano, Rich) has a wire to the WE.**

This is **not configurable**, not bypassable in software. Only FIB-attack-level silicon rewiring could defeat it — outside the threat model.

### Physical topology

```
        ┌───────────────────────────────────────────────┐
        │                  CFPU CHIP                     │
        │                                                │
        │  [Seal Core]   [Nano][Nano]...[Rich][Rich]    │
        │      │              │   │        │   │         │
        │      │              └───┴────────┴───┘         │
        │      │                    │                    │
        │      │              CODE read bus              │
        │      │              (shared, OE only)          │
        │      │                    │                    │
        │      │                    │                    │
        │      │  CODE write bus (private)               │
        │      └───────────────────┐│                    │
        │                          ││                    │
        │                CODE RAM pins (WE + OE + data) │
        └──────────────────────────┬┬────────────────────┘
                                   ││
                          ┌────────┴┴────────┐
                          │  CODE RAM chip  │  (external commercial SRAM)
                          └─────────────────┘
                                   
                                   
        ┌───────────────────────────────────────────────┐
        │                  CFPU CHIP                     │
        │                                                │
        │  DATA bus (all cores, anyone WE)               │
        │                          │                     │
        │                DATA RAM pins (WE, OE, ...)    │
        └──────────────────────────┬─────────────────────┘
                                   │
                          ┌────────┴────────┐
                          │  DATA RAM chip  │  (separate chip)
                          └─────────────────┘
```

**Critical:** CODE and DATA live in separate physical chips. Unavoidable in the pre-QRAM era, because a commercial RAM chip has **one WE pin** — either fully Seal-restricted or not at all.

### One WE pin → multiple CODE RAM chips (fan-out)

**Key observation:** a single WE output of a Seal Core can, through standard bus fan-out, drive **the WE pin of any number of CODE RAM chips** in parallel. The address bus (memory map) decides which RAM chip responds to a given write cycle — exactly as in every conventional embedded system.

For a 4-RAM-chip configuration example:

| RAM chip | Address range |
|----------|---------------|
| CODE RAM 1 | 0x0000 – 0x1FFF |
| CODE RAM 2 | 0x2000 – 0x3FFF |
| CODE RAM 3 | 0x4000 – 0x5FFF |
| CODE RAM 4 | 0x6000 – 0x7FFF |

The Seal Core's single WE pin fans out to all four RAM WE pins (in parallel); the CS (Chip Select) signals come from standard address decoding. When the Seal Core writes to address 0x2500, only CODE RAM 2's CS is active → only it writes. The others receive the WE signal but ignore it without CS.

```
           CFPU CHIP                                external RAM chips
┌──────────────────────────────┐
│  [Seal Core] ─WE─┐            │               ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│                   ├── fan-out ──── WE bus ──> │ WE  │ │ WE  │ │ WE  │ │ WE  │
│  [Nano][Rich]... │            │               │     │ │     │ │     │ │     │
│  (Nano/Rich: no  │ ADDR bus ──────────────>   │ RAM │ │ RAM │ │ RAM │ │ RAM │
│   WE wires)      │ DATA bus ──────────────>   │  1  │ │  2  │ │  3  │ │  4  │
│                   │                            │0x000│ │0x200│ │0x400│ │0x600│
│                   │ CS decode ─────────────>   │ CS  │ │ CS  │ │ CS  │ │ CS  │
│                   │                            └─────┘ └─────┘ └─────┘ └─────┘
└──────────────────────────────┘
```

Nano/Rich core WE wires are **physically not routed** to any RAM chip — only the Seal Core's WE is. So they **can read** (address + OE signals are available to them), but **cannot write**.

### Redundancy with multiple Seal Cores — equally simple

With multiple Seal Cores, each WE output connects to a **shared WE bus**. A small on-chip arbiter ensures only one Seal Core drives the bus in any clock cycle (tri-state or MUX):

```
[Seal Core 1] ─WE─┐
[Seal Core 2] ─WE─┤
[Seal Core 3] ─WE─┼──> arbiter ──> shared WE bus ──> every CODE RAM
[Seal Core 4] ─WE─┘    (between Seal Cores)
```

The memory map is partitioned in software (within Seal Core firmware): which Seal Core handles which address range. **No extra hardware** is required in the RAM chips — they remain standard commodity SRAMs with no "WE switch".

If a Seal Core dies, a neighbor simply takes over its address range — the neighbor's WE was already on the shared bus. Takeover is **trivial** in hardware.

### Limitations in the pre-QRAM era

The limit is **not WE pins or board complexity**, because WE fans out and addressing is standard memory decode:

- **Address-space size:** the CFPU CODE address space is finite, constraining the total RAM count
- **External RAM chip count:** practical PCB / board-design limits (but not WE pins)
- **Cost per Seal Core:** each Seal Core ships with its own SHA-256 + WOTS+ HW — manufacturing cost sets realistic counts

### Practical configurations

| Phase | Seal Core count | CODE RAM chips | Redundancy |
|-------|-----------------|----------------|------------|
| F3 Tiny Tapeout | 1 | 1 | none |
| F5 RTL prototype | 1-2 | 1-2 | minimal |
| F6 ChipIgnite (pre-QRAM) | 2-4 | 1-4 | WE bus + arbiter, free takeover |

Multi-Seal Core redundancy in the pre-QRAM era is **as cheap** as it will be in the QRAM era — thanks to standard bus design.

## Seal Core in the QRAM era (F5+) <a name="qram"></a>

The QRAM era begins in the late F5 RTL prototype phase and is complete by F6 ChipIgnite. Here CODE lives in an **on-chip Quench-RAM array**, whose protection comes from the **per-block status bit** (SEAL/RELEASE microcode primitives, see `docs/quench-ram-en.md`).

### Core principle — verification gatekeeper

> **The Seal Core here does NOT defend physical pin routing.** CODE protection comes from the Quench-RAM status bit. The Seal Core's role is solely **AuthCode verification** — it decides whether an incoming `.acode` container is authentic, and it triggers the Quench-RAM SEAL microcode to seal the CODE region.

This is a **fundamentally different role** than in the pre-QRAM era. The protection source is a different mechanism; the Seal Core only runs the verification pipeline.

### The flow

```
1. .acode container arrives (network, USB, hot-update)
2. router → Seal Core (dedicated inbox)
3. Seal Core firmware runs the AuthCode verify flow:
      - SHA-256(bytecode) == cert.PkHash ?
      - BitIceCertificateV1.Verify(cert, eFuse.CaRootHash) ?
      - cert.SubjectId ∉ revocation_list ?
4. If all OK:
      - Seal Core writes bytecode via normal writes to a mutable
        (status=0) Quench-RAM region
      - Seal Core invokes the SEAL microcode primitive to close it
      - Quench-RAM HW: status=1, bytecode is immutable henceforth
5. Seal Core notifies Neuron OS scheduler: "new actor loaded, may start"
```

In **step 4**, the Seal Core uses no special WE pin. It performs ordinary memory writes to the Quench-RAM mutable region (granted by its capability), then SEALs to lock. Protection comes from the fact that **only the Seal Core firmware can trigger the `SEAL` microcode primitive in the AuthCode verify context** — an actor on another core might write a mutable block, but cannot call SEAL (the SEAL trigger list is closed: `SEND`, `newobj`, `newarr`, `GC_SWEEP`, or Seal Core hot_code_loader).

### Redundancy — from a verification throughput perspective

Multiple Seal Cores in the QRAM era are **not for memory-write protection**, but for:

| Aspect | Explanation |
|--------|-------------|
| **Verification throughput** | 4 Seal Cores = 4× faster parallel code loading |
| **Verification redundancy** | One Seal Core fails → another takes over its role |
| **Failure isolation** | A Seal Core stall / disturbance doesn't block others |

The ring/mesh topology is for **hot_code_loader actor host migration** (if Seal Core 2 dies, Seal Core 1 starts running the loader actor), not for memory protection.

### Seal Core in QRAM — summary

- **Not** a physical gatekeeper over the WE pin (no separate CODE chip either)
- **Yes** a logical gatekeeper on the AuthCode flow
- **Yes** the SEAL microcode-trigger source
- Multiple Seal Cores = **parallel verify + redundancy**
- CODE memory protection is **entirely** via the Quench-RAM status-bit mechanism

## The transition point <a name="transition"></a>

The transition **between the two eras** is tied to a concrete CFPU chip generation:

| Phase | Memory | Seal Core primary role | Protection source |
|-------|--------|--------------------------|--------------------|
| F3 Tiny Tapeout | external SRAM | physical WE routing | topology |
| F5 early | external SRAM | physical WE routing | topology |
| F5 late (QRAM prototype) | on-chip QRAM | AuthCode verify + SEAL trigger | status bit |
| F6 ChipIgnite | on-chip QRAM | AuthCode verify + SEAL trigger | status bit |
| F7+ | on-chip QRAM | AuthCode verify + SEAL trigger | status bit |

In the late F5 phase, the appearance of the QRAM prototype **changes** the Seal Core role. The two mechanisms **are not concurrent** — they succeed each other in time, not simultaneously.

A brief transition phase (late F5 → early F6) might see **both mechanisms active** (external CODE RAM + on-chip QRAM zone), but even here with **strict separation**: the external RAM zone uses WE routing, the on-chip QRAM zone uses status bit, and **a bytecode is either in one or the other** — never hybrid.

## Boot and firmware immutability <a name="boot"></a>

The Seal Core's own code **cannot be loaded as a signed binary** — that would be paradoxical (who authenticates the authenticator?). Three possible sources for Seal Core firmware:

### Option 1 — Mask ROM (burned at chip manufacture)

- Mask-level silicon circuits
- **Never modifiable** over the chip lifetime
- Very secure but unupgradable → a bug fix requires a new chip tape-out

### Option 2 — OTP eFuse array

- One-time programmable eFuse cells
- Written at manufacture or first boot
- **Never modifiable** after first write
- More flexible than mask ROM (can be updated between production runs)

### Option 3 — Flash + boot-time integrity check

- Code stored in flash, SHA-256 hash in eFuse
- Verify at boot
- Upgradable (new flash + new hash write), but larger security risk

**In the v1.0 model, Option 1 or 2 is the baseline.** The specific choice is an **F5 RTL decision** dependent on manufacturing reality.

### The boot flow

```
1. Chip power-on
2. Seal Core firmware runs from mask ROM / eFuse
3. Self-test:
      - Does the SHA-256 unit work?
      - Does the WOTS+ unit work?
      - Is SRAM clean (all zero)?
      - Is the eFuse CA Root Hash readable?
4. Health monitor check: do other Seal Cores heartbeat?
5. Ready state: Seal Core ready to accept .acode containers
6. Parent supervisor notification: "Seal Core active"
```

## Redundancy and graceful degradation <a name="redundancy"></a>

Depending on CFPU chip type and size, **1-64+ Seal Cores** may be present. Redundancy goals:

### Goals

- **Redundancy** — if one Seal Core has a HW fault (SEU, wear-out), others keep running
- **Throughput** — parallel AuthCode verify for high code-load speed
- **Load balancing** — distribution of code-load requests

### Health monitor and heartbeat

Every Seal Core emits a **heartbeat pulse** to a central health monitor logic:

```
health monitor (central, on-chip FSM):
  - each Seal Core → heartbeat signal (cyclic pulse)
  - expected: pulse within N clock cycles
  - if no pulse for N×10 cycles → dead[i] ← 1
  - dead[i] flip-flop: HW-set only, clear on chip reset
  - dead[i] readable by other cores, but NOT writable
```

Roughly **~50-100 transistors** for the health monitor, local and autonomous. **Not software-controlled** — a malicious actor cannot "play dead" for a neighbor.

### Topology

**Pre-QRAM era (F3-F5):**
- Ring-neighbor: N Seal Cores with separate CODE RAM chips, neighbor takeover
- Limit: max 4-8 Seal Cores practically (pin budget)

**QRAM era (F5+):**
- Ring or 2D mesh, depending on chip size
- Takeover here means **hot_code_loader actor host role**, not WE routing
- Scaling: 4-64+ Seal Cores feasible

### Fixed-priority takeover

For predictability, each Seal Core has a **fixed-priority neighbor list** for failover:

```
Ring topology (N Seal Cores):
  Seal[i] dead → Seal[i-1 mod N] takes over

2D mesh topology (4-neighbor):
  Seal[i] dead → priority N > W > E > S
  if all dead → dead Cluster, graceful degradation
```

### Graceful degradation

If a whole Seal Core cluster dies (e.g., power domain failure):

- Code-load throughput decreases (fewer parallel verifiers)
- The CODE RAM regions (pre-QRAM) / verification duties (QRAM) assigned to them move to other Seal Cores
- **The system keeps running** — just spawns new actors more slowly
- Already-loaded actors are **completely unaffected** (their code is already SEALed)

## Accelerator functions <a name="accelerators"></a>

Every Seal Core contains dedicated hardware accelerators for cryptographic operations. They are directly accessible from Seal Core firmware:

### SHA-256 HW unit

- ~5K gates
- ~80 cycles per block (512-bit input)
- Pipelineable over an input stream

### WOTS+ verifier

- ~3K gates
- SHA-256 chain reconstruction (67 chains × ~7.5 avg hash)
- ~500 SHA-256 calls for one complete WOTS+ verify

### Merkle path verifier

- ~2K gates
- h=10 iteration = 10 SHA-256 hashes per verify

### Full verify cycle

A complete BitIce cert verify (TBS hash + WOTS+ recompute + leaf hash + Merkle path):

- ~512 SHA-256 ops total
- ~41K cycles at 1 GHz = **~41 µs**

### Optional: BLAKE3 unit (future)

If a different hash function is needed in the future (e.g., for a new BitIce version), an additional ~5K gate BLAKE3 unit can be added to the Seal Core.

## Security guarantees <a name="security"></a>

The Seal Core's **unique contribution** to the CFPU security model:

| Attack class | Traditional system | CFPU with Seal Core |
|--------------|---------------------|----------------------|
| Memory controller write-path bypass | software check bypassable | **Eliminated** (pre-QRAM: physical WE routing; QRAM: SEAL microcode triggered only from Seal Core firmware) |
| Hot code loader tamper | kernel-level attack | **Eliminated** (Seal Core firmware is immutable, mask ROM / eFuse) |
| Unsigned code introduction | ring-0 exploit | **Eliminated** (every code-load passes through Seal Core) |
| DoS on the authenticator | single signing service | **Redundant** (multiple Seal Cores, graceful degradation) |
| HW fault on signing path | The only service stops | **Tolerated** (ring/mesh takeover) |

## Open questions <a name="open"></a>

This v1.0 document captures the vision-level architecture. Details are to be resolved in the appropriate F-phases:

### F4-F5 (sim + RTL)

1. **Seal Core CPU architecture** — RISC-V subset, custom ISA, or trimmed CIL-T0 variant?
2. **Firmware store** — mask ROM vs. eFuse vs. flash+integrity check
3. **Heartbeat frequency and timeout** — what N, acceptable response time?

### F5-F6 (first hardware)

4. **Pre-QRAM CODE RAM chip size and pin layout** — which commercial SRAM chip is supported
5. **QRAM transition point** — when does on-chip CODE memory appear
6. **Number of Seal Cores in F6** — 2, 4, or more?

### F7+ (scaling)

7. **Mesh topology** — 4-neighbor vs. 8-neighbor (with diagonals)
8. **Power-domain boundaries** — how many Seal Cores share a power domain
9. **Inter-chip multi-CFPU context** — each CFPU chip has its own Seal Core set (explicit: yes)
10. **Hot-plug Seal Core quadrant** — on very large chips (F8+)

## Phase introduction <a name="phases"></a>

| Phase | Seal Core role |
|-------|-----------------|
| F0–F2 (simulator) | Software emulation, AuthCode verify mock in `TCpu` |
| F3 Tiny Tapeout | Single-core Seal Core, WE pin routing, 1 external CODE RAM |
| F4 multi-core sim | 2-4 Seal Cores in sim, ring-neighbor failover, WE routing emulated |
| **F5 RTL prototype** | First **real** Seal Core in RTL; SHA-256 + WOTS+ HW units; pre-QRAM with external RAM |
| **F5 late (QRAM prototype)** | **Transition**: on-chip QRAM array appears; Seal Core role **shifts** to AuthCode gatekeeper |
| F6 ChipIgnite | Full on-chip QRAM, 2-4 Seal Cores in a ring, production AuthCode flow |
| F6.5 Secure Edition | 4 Seal Cores mandatory, extra accelerators (optional BLAKE3) |
| F7 Cognitive Fabric | 8-16 Seal Cores 2D mesh, large-chip scale |
| F8+ server-class | 64-256 Seal Cores 2D mesh, power-domain boundaries, hot-plug cluster |

## References <a name="references"></a>

### Internal documents

- `docs/authcode-en.md` — the AuthCode mechanism run by Seal Core
- `docs/quench-ram-en.md` — the QRAM cell providing CODE protection in the QRAM era
- `docs/security-en.md` — the CFPU security model
- `docs/architecture-en.md` — the CFPU microarchitecture hosting Seal Core as third core category
- `docs/neuron-os-en.md` — the `hot_code_loader` actor hosted by the Seal Core

### External references

- BitIce project: `github.com/BitIce.io/BitIce` (cryptographic primitive source)
- NIST SP 800-208: Stateful Hash-Based Signature Schemes
- NIST FIPS 180-4: SHA-256 specification

## Changelog <a name="changelog"></a>

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-16 | Initial vision-level release. Seal Core as two distinct mechanisms: (1) pre-QRAM era physical WE pin routing to the CODE RAM chip; (2) QRAM era AuthCode verification gatekeeper acting as SEAL microcode-trigger source. Explicit separation between eras, no cross-contamination. Ring and 2D mesh failover topologies, graceful degradation. Firmware immutability via mask ROM / eFuse. |
