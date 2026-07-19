---
status: vision
---

# Seal Core — The CFPU Authentication Gatekeeper Core

> Magyar verzió: [sealcore-hu.md](sealcore-hu.md)

> Version: 1.6

This document describes the **Seal Core** component: a dedicated, simple, hardware-burned-firmware core that ensures **code-loading authenticity** on the CFPU chip. The Seal Core operates via two distinct mechanisms depending on CFPU phase — **pre-QRAM era** (F3-F5) through physical WE-pin routing, **QRAM era** (F5+) as an AuthCode verification gatekeeper. These are **two distinct mechanisms**, which this document treats in deliberately separated sections.

> **Vision-level document.** The Seal Core is present in the CFPU from F3 and persists across chip generations. However, its role stands **fundamentally differently** in pre-QRAM vs. post-QRAM contexts, so the document splits the two into separate sections with explicit transition-point marking.

## Table of Contents

1. [Motivation](#motivation)
2. [What is the Seal Core](#what-is-sealcore)
3. [Role in the CFPU brand family](#brand)
4. [General architecture](#architecture)
5. [The three SEAL touchpoints](#seal-points)
6. [Seal Core in the pre-QRAM era (F3-F5)](#preqram)
7. [Seal Core in the QRAM era (F5+)](#qram)
8. [The transition point](#transition)
9. [Boot and firmware immutability](#boot)
10. [Authority delegation — runtime CST policy](#authority)
11. [Redundancy and graceful degradation](#redundancy)
12. [Accelerator functions](#accelerators)
13. [Security guarantees](#security)
14. [Open questions](#open)
15. [Phase introduction](#phases)
16. [References](#references)
17. [Changelog](#changelog)

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
- **DDR5 capability slot management** — SEAL/RELEASE per-core capability slots via NoC mailbox messages handled by the target core's **QGate**, based on `kernel_io_sup` policy (see `ddr5-architecture-hu.md` v1.3, "5.e) HW Capability Slot")
- **CST (Capability Slot Table) management** — SEAL/RELEASE of the NoC actor-to-actor capability table likewise via NoC mailbox messages handled by the target core's **QGate** (see `interconnect-en.md` v3.0, `quench-ram-en.md`)
- **Single-instance peripheral config** — the **whole-peripheral** configuration of the DDR5 Controller, QSPI Controller, etc. via a **dedicated hardwired config port** (1 destination, see `ddr5-architecture-hu.md` v1.3 line 85-86) — **not** a QGate, since the peripheral is not a core
- **Authority delegation gatekeeper** — at boot time the Seal Core writes a GRANT_ALL CST entry to the OS root actor; at runtime it validates spawn / revoke / delegate requests originating from the OS root actor (or its delegates) against the supervisor link and the requester's own CST capability, then sends a NoC mailbox message to the target core's **QGate**. Details: ["Authority delegation — runtime CST policy"](#authority) and ["The three SEAL touchpoints"](#seal-points).

## Role in the CFPU brand family <a name="brand"></a>

The Seal Core fits into the family of complementary CFPU security mechanisms:

```
               ┌───────────────────────────────────────────┐
               │           CFPU security family            │
               └───────────────────────────────────────────┘
                                    │
   ┌──────────────┬──────────┬──────────┬──────────────┬──────────┬──────────────┐
   │              │          │          │              │          │              │
[Quench-RAM] [AuthCode] [CodeLock] [Seal Core]    [QGate]   [Symphact
 memory       code        runtime    chip-wide      per-core    HSM Card]
 cell         signing     W⊕X        gatekeeper     Quench-RAM  crypto +
                                     core           gate        signing
```

| Component | Scope | Role |
|-----------|-------|------|
| **Quench-RAM** | per-bit | Memory cell, status-bit-based immutability |
| **AuthCode** | per-binary | CIL code signature verification (LMS+WOTS+) |
| **CodeLock** | per-region | Runtime W⊕X (pre-QRAM: WE-pin routing) |
| **Seal Core** | chip-wide | Global gatekeeper, AuthCode flow, capability authority root |
| **QGate** | **per-core** | **Local Quench-RAM gate — the only write path to the core's CST QSRAM / DDR5 cap-slot QRAM; activated by NoC mailbox SEAL/RELEASE messages** |
| **Symphact HSM Card** | system-wide | External key management, signing |

The Seal Core is the **physical component** that **practically activates** the other mechanisms:
- The **AuthCode** verification flow runs here
- The **CodeLock** W⊕X enforcement (in pre-QRAM era) originates from WE-pin routing here
- The **Quench-RAM** CODE-region SEAL HW trigger is invoked here
- The per-core **QGate**s are driven via NoC mailbox messages (CST/cap-slot SEAL/RELEASE)

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
│  │    Simple CPU core (CIL-Seal ISA — F5)           │    │
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

## The three SEAL touchpoints <a name="seal-points"></a>

The Seal Core drives **three distinct SEAL/RELEASE event types**, each running on **a different channel and a different executor**. Their explicit separation matters because earlier doc versions (sealcore-en v1.1–v1.2) conflated the term "hardwired config port" — that applies only to event types 1 and 3, **not** to type 2.

> **Brand-name introduction (v1.4):** the executor of event type 2 — the per-core local SEAL/RELEASE FSM — is hereafter called **QGate** (Quench-RAM Gate). This is a new member of the CFPU security brand family; see ["Role in the CFPU brand family"](#brand) for its position.

| # | Event | Authority | Channel | Executor | Speed |
|---|-------|-----------|---------|----------|-------|
| 1. | **CODE region SEAL** (boot / hot-load) | Seal Core | Local (in the Seal Core's own address space — write port + SEAL trigger) | Seal Core HW FSM | Slow path (once per code load) |
| 2. | **Capability slot SEAL/RELEASE** (per-core CST, per-core DDR5 cap slot) | Seal Core / supervisor actor | **NoC mailbox** message to the target core | **QGate** (per-core local Quench-RAM gate FSM) | Fast path (frequent, runtime) |
| 3. | **Single-instance peripheral config** (DDR5 Controller, QSPI Controller, etc.) | Seal Core / `root_supervisor` | **Hardwired config port** (1 source → 1 destination, key-less, enable-only) | Peripheral HW | Slow path (config-only, rare) |

### Why no hardwired config port for CST/capability-slot writes?

The per-core CST and per-core DDR5 capability slot table **physically live in the target core's QSRAM** (see `ddr5-architecture-hu.md` v1.3 §2.b, "Storage: per core, in QRAM"). There is no central capability table. If we wrote these via a global hardwired config bus:

- ~10,000 cores × n_slots × m_bit-wide wires = **physically infeasible** routing
- Every core would need its own config port to the Seal Core → enormous area + power
- The shared-nothing chip principle would be violated (central data path)

Instead, per-core SEAL/RELEASE travels as a **NoC mailbox message**: the sender (Seal Core or supervisor actor) sends a SEAL command to `dst=(target_core, 0)`, and the target core's **QGate** writes its own QSRAM. This:

- **Scales** on the existing NoC; no new wires required
- **HW-attested** — the QGate checks that the `(src, src_actor)` pair is the Seal Core's hardwired address or a delegated supervisor (see `interconnect-en.md` v3.0, header v3.1)
- **Local execution** — the QGate has exclusive write access to its own CST/cap-slot QSRAM; no other core has a wire to that QSRAM

### The QGate component

The **QGate** (Quench-RAM Gate) is a **per-core HW state machine** with a single function: CRC-gating the write port to the core's own Quench-RAM-based capability tables (CST QSRAM, DDR5 cap-slot QRAM). For QGate's brand-family position, see section 3 ["Role in the CFPU brand family"](#brand).

```
┌──────────────────────────── core_i ───────────────────────────┐
│                                                                │
│   NoC inbox ──► [QGate] ──► CST QSRAM (per-actor capability)  │
│                  │     └──► DDR5 cap-slot QRAM (per-actor)    │
│                  │                                             │
│                  ├─ CRC-8 header check                         │
│                  ├─ CRC-16 payload check                       │
│                  └─ op decode (SEAL_INSTALL / UPDATE / RELEASE)│
│                  │                                             │
│                  └─ on CRC fail → silent drop                  │
│                                                                │
│   core SW ────────X─► (NO path to write the QSRAM)            │
└────────────────────────────────────────────────────────────────┘
```

| Property | Value |
|----------|-------|
| Instances | **1 / core** (present on Nano, Actor, Rich) |
| Internal state | minimal (FSM state + CRC checker shift register) |
| Input | NoC inbox dedicated port (only SEAL/RELEASE message types) |
| Output | CST QSRAM write port, DDR5 cap-slot QRAM write port |
| Validation | **CRC-8 (header) + CRC-16 (payload) only** — no logical validation |
| Drop condition | CRC mismatch → silent drop, counter increment |
| Estimated area (5nm) | **~600–800 gates / core** (CRC-8 ~200 + CRC-16 ~400 + write-mux + FSM ~150) |

### Why no logical validation — CFPU single-layer trust principle

The QGate **does not check** anything along the following dimensions:

- ❌ `src` field authority comparator (eFuse address vs. supervisor capability)
- ❌ Payload range check (`target_actor` ∈ [0..255], `perms` valid mask)
- ❌ Op validity (valid opcode value)
- ❌ Supervisor link well-formedness

**This is deliberate design, not an oversight.** The CFPU single-layer trust principle states:

> Trust the immutable + HW-managed source; defend only against physical errors.

Messages reaching the QGate always originate from the Seal Core firmware (or a delegated supervisor actor) — no other actor can send, because the CST router-level filter screens them out (a non-authority actor has no capability for the QGate target in its own CST entry). Therefore:

- The sender is **authority by construction** (the CST guarantees it)
- The Seal Core firmware is **immutable** (mask ROM / eFuse) → it does not send malformed payloads
- The only realistic failure mode: **physical bit-flip during NoC transit** (SEU, cosmic radiation)
- For this, **CRC-8 (header) and CRC-16 (payload) are sufficient**

Adding logical validation would be **defense-in-depth rhetoric** — the opposite of the principle that:
- Removed the HMAC field from header v3.0 (`interconnect-en.md` v3.0): "the CST is HW-managed, software cannot manipulate it"
- The sending core's HW resolves the CST index → not actor SW

Same applies here: if the Seal Core firmware has a logical bug (sends the wrong `target_actor`), that is **out of threat model**. There is no threat model in which immutable mask ROM runs faulty code — if it did, we would have far worse problems.

**Consequence:** the QGate is essentially a **CRC-gated write port**, nothing more. This is the minimal HW that guarantees Quench-RAM SEAL/RELEASE semantics on the NoC mailbox channel.

### Why a hardwired config port for single-instance peripherals?

The DDR5 Controller, QSPI Controller, etc. are **single-instance** components on the chip — their config (PHY parameters, bank policy, etc.) likewise lives in one place. Here:

- The "1 source → 1 destination" topology is trivial (a single wire from the Seal Core)
- Config happens at boot; runtime modifications are rare
- The NoC mailbox would be overkill for such a low-frequency config channel

Therefore single-instance peripheral config runs on a **hardwired, key-less, enable-only** port from the Seal Core (see `ddr5-architecture-hu.md` v1.3 line 85-86). This is **not** the same mechanism as per-core CST/cap-slot SEAL/RELEASE.

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

The QRAM era begins in the late F5 RTL prototype phase and is complete by F6 ChipIgnite. Here CODE lives in an **on-chip Quench-RAM array**, whose protection comes from the **per-block status bit** (SEAL/RELEASE hardware state-machine operations, see `docs/quench-ram-en.md`).

### Core principle — verification gatekeeper

> **The Seal Core here does NOT defend physical pin routing.** CODE protection comes from the Quench-RAM status bit. The Seal Core's role is solely **AuthCode verification** — it decides whether an incoming `.acode` container is authentic, and it triggers the Quench-RAM SEAL hardware state machine to seal the CODE region.

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
      - Seal Core invokes the SEAL hardware state-machine operation to close it
      - Quench-RAM HW: status=1, bytecode is immutable henceforth
5. Seal Core notifies Symphact scheduler: "new actor loaded, may start"
```

In **step 4**, the Seal Core uses no special WE pin. It performs ordinary memory writes to the Quench-RAM mutable region (granted by its capability), then SEALs to lock. Protection comes from the fact that **only the Seal Core firmware can trigger the `SEAL` hardware state-machine operation in the AuthCode verify context** — the SEAL trigger list is closed: CODE region (Seal Core boot / hot_code_loader), SEND (payload leaves the Core), swap-out (DMA evict to external QRAM).

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
- **Yes** the SEAL HW-trigger source
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

## Authority delegation — runtime CST policy <a name="authority"></a>

This section captures **how responsibility is split** between the Seal Core (HW mechanism) and the OS root actor (runtime policy) for CST table writes and actor-level capability delegation. The model follows the [`feedback_mechanism_separation`](../docs/architecture-en.md) principle: **the Seal Core firmware does not understand OS structure** — the Seal Core is only a check-and-write mechanism, while the actual policy lies with the OS root actor.

### Core principle

> A per-core CST is writable **exclusively** by that core's **QGate**, and the QGate only ever receives messages from authority sources — guaranteed by the CST router-level filter: capability for the QGate target is grantable only by the Seal Core / delegated supervisor, so a non-authority actor's send is rejected at its own core HW. The QGate itself **only checks CRC** (single-layer trust principle, see ["The QGate component"](#seal-points) section v1.5). No other core **has a wire** to the target core's CST QSRAM. This is physically enforced, not software-configurable. See: ["The three SEAL touchpoints"](#seal-points) — per-core CST is event type 2 (NoC mailbox + QGate), not type 3 (hardwired config port).

The Seal Core firmware, however, **does not decide on its own** who deserves which capability. Post-boot runtime CST changes are **requested by the OS root actor** via messages — the Seal Core firmware policy only validates the **authenticity** and **consistency** of those requests. This is a classic mechanism / policy separation (microkernel philosophy).

### Boot-time delegation — initial GRANT_ALL

At the end of step 2 in `hw-boot-en.md`, before the Rich core reset is released:

```
1. Seal Core verifies the OS root binary (LMS+WOTS+ signature)
2. Seal Core sends a NoC mailbox message to the Rich core's QGate:
     dst   = (Rich_core, 0)    ← Rich core QGate mailbox address
     src   = (Seal_core, 0)    ← Seal Core hardwired HW address (HW-attested)
     op    = SEAL_CST_INSTALL
     entry = (target_actor=1, perms=GRANT_ALL, supervisor=(Seal_core, 0))
3. Rich core QGate verifies CRC-8 + CRC-16, and (if OK) writes its own CST QSRAM:
     CST[1] = (perms=GRANT_ALL, supervisor=(Seal_core, 0))
4. Seal Core signals the Rich core: 0xF0002024 ← 1 (verified + go)
5. Rich core starts; the OS root actor (actor_id=1) takes on the runtime authority role
```

The QGate **does not check** the `src` field — that has already been screened by the CST router-level filter at send time (every core has capability for the Seal Core's hardwired address; non-authority actors have none for the QGate target). The QGate only verifies CRC-8 + CRC-16, and on OK, writes the CST. See: ["The QGate component"](#seal-points) "Why no logical validation" subsection.

The post-boot CST table thus starts with a **single** entry: the OS root actor sees everything and may delegate everything. From there, CFPU runtime policy is the **OS root actor's responsibility**, not the Seal Core firmware's.

### Runtime delegation — message API

> **Clarification — NoC-attested, not cryptographically signed:** the CFPU does **not use HMAC or digital signatures at the message level** (see `interconnect-en.md` v3.0: the HMAC field was REMOVED in header v3.0). Authority-command authenticity is provided **exclusively by HW-attributed origin**: the `src_actor[8]` field in the header is filled by the sending core's HW context register (not forgeable), and the `src[24]` field is filled by the NoC router HW from the sender's physical position. The CRC-16 / CRC-8 fields serve **integrity only**, **not authentication**. The operations below are therefore **NoC-attested authority commands**, not signed messages.

The OS root actor (or a delegate holding appropriate capability) sends a message to the Seal Core (`(Seal_core, 0)` address) to request a CST operation. Functionally, the message types are:

| Operation | Request payload | Seal Core check |
|-----------|-----------------|-----------------|
| **Spawn** — create new actor | `target_core, code_hash, parent, perms` | (a) `parent == src_actor` (requester is the to-be parent), (b) `perms ⊆ requester's CST entry`, (c) `code_hash` AuthCode-verified |
| **Delegate** — grant capability to existing actor | `target_actor, perms_subset` | (a) `target_actor`'s parent is the requester (supervisor link), (b) `perms_subset ⊆ requester's delegate rights` |
| **Revoke** — revoke capability | `target_actor` | (a) `target_actor`'s parent is the requester, or the requester is the OS root actor |

The concrete message opcodes and payload formats are an **F4-F5 RTL decision** — to be defined by the `CIL-Seal ISA` (see [Open questions](#open) #1).

The requester's identity is **not forgeable**: in header v3.1, the `src_actor` field originates from the core HW context register (see `specs/cell-format-en.md` v2.4, "Decision 3"), and the `src` field is filled by the NoC router HW from the physical origin. The Seal Core firmware compares this (HW-attested) `(src, src_actor)` pair against the request's `parent` / `target_actor` fields — **no crypto, only HW-attributed origin**.

### Validation algorithm (Seal Core firmware)

```
on_request(MsgCstOp from src):
    1. lookup CST[src_core, src_actor] → caller_perms, caller_supervisor
       (if no entry → REJECT, src is not an active actor)

    2. switch(op):
         case Spawn:
             if request.parent != src                    → REJECT
             if request.perms ⊄ caller_perms             → REJECT
             if AuthCodeVerify(request.code_hash) fails  → REJECT
             allocate target_actor on target_core
             send NoC mailbox: SEAL_CST_INSTALL →
                  dst=(target_core, 0),
                  payload=(target_actor, request.perms, supervisor=src)
             # target core QGate:
             #   verifies CRC-8 + CRC-16
             #   writes: CST[target_actor] = (perms, supervisor=src)

         case Delegate:
             if supervisor_link[request.target] != src   → REJECT
             if request.perms_subset ⊄ caller_perms      → REJECT
             send NoC mailbox: SEAL_CST_UPDATE →
                  dst=(target.core, 0),
                  payload=(target.actor, perms_or=request.perms_subset)

         case Revoke:
             if supervisor_link[request.target] != src
                AND src != OS_root_actor                 → REJECT
             send NoC mailbox: RELEASE_CST_ENTRY →
                  dst=(target.core, 0),
                  payload=(target.actor)
             cascade revoke children (supervision tree-walk + RELEASE messages)

    3. reply MsgCstOpResult(success / error_code)
```

The **cascade revoke** semantics follow the classic actor supervision tree: revoking a parent must clear children's CST entries as well. The Seal Core firmware walks the supervision tree and sends a separate RELEASE_CST_ENTRY message to each affected target core — each target core's **QGate** performs the write in its own QSRAM. The sweep itself is firmware-driven (not a single HW broadcast), but execution at the target cores is HW-only (QGate).

### Why the Seal Core firmware does not contain the policy

The Seal Core firmware lives in **mask ROM / eFuse** and is not updatable across the chip's lifetime. If the delegation policy lived here:

- OS structural changes (new actor types, new capability classes) would require **chip re-tape-out** to track
- The microkernel philosophy would be violated: the Seal Core would "understand" high-level OS concepts, not just the HW mechanism
- A policy bug would be unfixable via software update

Therefore, the Seal Core firmware implements **only the mechanism** (CST write, request validation per fixed rules), and high-level decisions (who gets what, when, why) are made by the OS root actor. The OS root actor is **updatable** (a new AuthCode-verified binary for a new OS version), so policy evolution never requires new silicon.

### Threat model — what is excluded

| Attack | Defense |
|--------|---------|
| Malicious actor tries to write its own core's CST QSRAM directly | The CST QSRAM is writable only by the core's **QGate** (write-port strictly FSM-controlled). The actor's SW has no instruction in its address space targeting the CST QSRAM. |
| Malicious actor tries to send a forged `SEAL_CST_INSTALL` to a target core | **Physically impossible.** Sending requires a CST entry for the `(target_core, 0)` destination, and capability for the QGate target is grantable only by the Seal Core / authority delegate. A non-authority actor has no CST entry → its own core HW rejects the send. The QGate only ever receives messages from authority sources. |
| Actor sends a forged `src_actor` field to request capability | The sending core's HW fills the `src_actor` field from a context register; not forgeable (see `cell-format-en.md` v2.4 Decision 3). |
| Bit-flip / SEU during NoC transit | CRC-8 (header) and CRC-16 (payload) — the QGate handles via silent drop. |
| Malicious actor delegates capability as a parent to a non-child | The Seal Core firmware validates the `supervisor_link[target] == src` invariant at every delegation (against its firmware-internal supervisor tree). |
| Actor tries to grant capability to itself | The actor's own `src_actor` cannot simultaneously be the request's `parent` and `target` — the Seal Core firmware excludes this. |
| OS root actor is compromised | Out of threat model: the OS root actor is AuthCode-verified, and the Seal Core mechanism still enforces structural invariants. A full system takeover would require an AuthCode-verified malicious OS. |

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
| Memory controller write-path bypass | software check bypassable | **Eliminated** (pre-QRAM: physical WE routing; QRAM: SEAL HW FSM triggered only from Seal Core firmware) |
| Hot code loader tamper | kernel-level attack | **Eliminated** (Seal Core firmware is immutable, mask ROM / eFuse) |
| Unsigned code introduction | ring-0 exploit | **Eliminated** (every code-load passes through Seal Core) |
| DoS on the authenticator | single signing service | **Redundant** (multiple Seal Cores, graceful degradation) |
| HW fault on signing path | The only service stops | **Tolerated** (ring/mesh takeover) |

## Open questions <a name="open"></a>

This v1.0 document captures the vision-level architecture. Details are to be resolved in the appropriate F-phases:

### F4-F5 (sim + RTL)

1. **Seal Core CPU architecture** — CIL-Seal ISA: which CIL-T0 opcodes to keep, which crypto opcodes to add?
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
- [`Symphact/docs/vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md) — the `hot_code_loader` actor hosted by the Seal Core

### External references

- BitIce project: `github.com/BitIce.io/BitIce` (cryptographic primitive source)
- NIST SP 800-208: Stateful Hash-Based Signature Schemes
- NIST FIPS 180-4: SHA-256 specification

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.6 | 2026-07-17 | **Stale cell-format reference updated:** `cell-format-en.md` v2.2 → **v2.4** (2 references, cascade from the current spec). |
| 1.5 | 2026-05-02 | **QGate single-layer trust principle — drastic simplification.** The v1.4 QGate spec carried redundant logical validation (`src` authority comparator, payload range check, op validity, trap-flit) — these are unnecessary under the **CFPU single-layer trust principle**: the CST router-level filter already guarantees that only authority can send to the QGate, and the Seal Core firmware is immutable (mask ROM), hence correct by construction. The QGate v1.5 performs **only CRC-8 + CRC-16 checks**; CRC mismatch → silent drop. Estimated area 500–2000 → **600–800 gates**. New subsection: "Why no logical validation — CFPU single-layer trust principle". Threat model updated: the "malicious actor sends a forged SEAL_CST_INSTALL" row is **not a realistic threat** (excluded at CST router level); replaced with "bit-flip / SEU during NoC transit" (CRC handles). Consistent with the header v3.0 HMAC-removal rationale. |
| 1.4 | 2026-05-02 | **QGate brand name introduced** for the per-core local Quench-RAM gate FSM. Previously called "local SEAL FSM" / "target core's local SEAL FSM" / "MailBox SEAL trigger" — these all refer to the same component, now uniformly **QGate**. The brand-family diagram (section 3) gained a new row, and the new ["The QGate component"](#seal-points) subsection records component properties (1 / core, ~500–2000 gates, NoC inbox input, CST QSRAM + DDR5 cap-slot QRAM output). QGate's brand position: per-core gate at **Quench-RAM**-based capability tables, complementing the Seal Core's chip-wide AuthCode-gatekeeper role. References propagated throughout. |
| 1.3 | 2026-05-02 | **"The three SEAL touchpoints" section added** (1. CODE region SEAL — local Seal Core HW; 2. per-core CST/cap-slot SEAL/RELEASE — NoC mailbox + target core's local SEAL FSM; 3. single-instance peripheral config — hardwired config port). **Corrected v1.1–v1.2 misformulation:** earlier we described per-core CST writes as happening "via a dedicated hardwired config port"; this is **WRONG**, because the CST QSRAM lives per-core and is written via NoC mailbox messages handled by the target core's local SEAL FSM. The hardwired config port belongs only to single-instance peripherals (DDR5 Controller, etc.). Boot step 2e and the validation algorithm rewritten with NoC mailbox semantics (`SEAL_CST_INSTALL`, `SEAL_CST_UPDATE`, `RELEASE_CST_ENTRY` messages). Threat model updated: protection comes from the target core's local SEAL FSM `src` field check, not from the absence of a hardwired wire. |
| 1.2 | 2026-05-02 | **"Authority delegation — runtime CST policy" section added.** The Seal Core as mechanism (HW config port write + request validation) is split from the OS root actor as runtime policy. At boot, the Seal Core writes a single GRANT_ALL CST entry to the OS root actor; runtime CST operations (spawn / delegate / revoke) are requested by the OS root actor (or its delegate) via messages, validated by the Seal Core firmware against the supervisor link and the requester's own CST capability. Concrete message opcodes left as F4-F5 RTL decision (CIL-Seal ISA). |
| 1.1 | 2026-04-28 | **DDR5 capability slot management and CST writes added** to Seal Core duties. Per the `ddr5-architecture-hu.md` v1.3 HW Capability Slot model, the Seal Core SEAL/RELEASE-s the per-core 8 KB capability slot table (256 actors × 4 slots × 8 bytes) via a dedicated hardwired config port. The NoC-side CST (Capability Slot Table, `interconnect-en.md` v3.0) is similarly written via a hardwired port. |
| 1.0 | 2026-04-16 | Initial vision-level release. Seal Core as two distinct mechanisms: (1) pre-QRAM era physical WE pin routing to the CODE RAM chip; (2) QRAM era AuthCode verification gatekeeper acting as SEAL HW-trigger source. Explicit separation between eras, no cross-contamination. Ring and 2D mesh failover topologies, graceful degradation. Firmware immutability via mask ROM / eFuse. |
