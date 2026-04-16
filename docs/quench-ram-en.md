# Quench-RAM — Self-Quenching, Per-Block Immutable Hardware Memory Cell

> Magyar verzió: [quench-ram-hu.md](quench-ram-hu.md)

> Version: 1.1

This document describes the **architecture and ISA integration of the Quench-RAM** memory cell: per-block status-bit semantics, the two hardware microcode primitives (`SEAL`, `RELEASE`), the NAND-flash-derived "erase-on-release" pattern, and its relationship to ECMA-335 default-initialization semantics, the actor-model capability system, and the per-core garbage collector.

> **v1.1 security fix:** `SEAL` and `RELEASE` are **not CIL opcodes** but microcode-level primitives invoked only by well-defined trigger events (`SEND`, `newobj`, `newarr`, `GC_SWEEP`, `hot_code_loader`). This prevents a malicious actor from sealing or releasing arbitrary blocks. Details: [Trust boundary](#trust-boundary) section.

> **Vision-level document.** Quench-RAM may begin appearing in F5 RTL as an optional hardware layer above the SRAM arrays, and may become a mandatory building block of the CFPU memory hierarchy in F6. The invariants captured here are amenable to formal verification.

## Table of Contents

1. [Motivation](#motivation)
2. [Core rule](#core-rule)
3. [State machine and invariant](#state-machine)
4. [Microcode primitives and trigger events](#isa-primitives)
5. [Trust boundary](#trust-boundary)
6. [Hardware implementation](#hardware)
6. [Relationship to ECMA-335 default-init semantics](#ecma335)
7. [Synergy with per-core GC](#gc-synergy)
8. [Synergy with the actor-model capability system](#actor-synergy)
9. [Security guarantees](#security)
10. [Formal verification profile](#formal)
11. [Granularity and area overhead](#granularity)
12. [Related technologies](#related)
13. [Open questions](#open)
14. [Phase introduction](#phases)
15. [Changelog](#changelog)

## Motivation <a name="motivation"></a>

The largest portion of **memory-safety bugs** in modern CPU architectures fall into three categories:

- **Use-after-free (CWE-416)** — a freed memory region is read or written while another context has begun using it for a new purpose
- **Information leak in freed memory (CWE-244, CWE-226)** — a re-allocated block contains data from its previous use (Heartbleed-class)
- **Cold boot key recovery** — secrets recoverable from DRAM/SRAM of a powered-off device

All three are symptoms of **the same root cause**: **memory release is a software flag flip**, not a physical event. The "free()" operation in Linux/Windows/macOS can be skipped, sabotaged, or forgotten by anyone.

Quench-RAM provides a **physical answer** to this problem: release is no longer a bit in a table, but **an atomic hardware event** that mandatorily forces every bit of the block to zero **in the same cycle** that resets the status bit.

The concept is **a generalization of NAND flash erase semantics** to general-purpose RAM, with finer granularity and integration into the CIL-T0 ISA.

## Core rule <a name="core-rule"></a>

Every Quench-RAM block carries **a single extra status bit** alongside its data payload. The bit's meaning:

| Status bit | Meaning | Permitted operations |
|-----------|---------|----------------------|
| 0 | mutable, normal RAM | read, write, allocate |
| 1 | sealed (committed, immutable) | read only |

Transitions between the two states occur on **only two precisely defined paths**:

- **`SEAL`** — `0 → 1` transition. The current data is "committed", no longer modifiable.
- **`RELEASE`** — `1 → 0` transition. The status bit resets, **and in the same atomic operation** all data bits are forced to zero.

No other state transitions exist. The block can never enter a state of "sealed-but-uniform" or "released-but-dirty".

## State machine and invariant <a name="state-machine"></a>

```
                        SEAL                       RELEASE
   ┌──────────────┐  ──────────►  ┌──────────────┐  ──────────────────►  ┌──────────────┐
   │ status = 0   │               │ status = 1   │   atomic, 1 cycle     │ status = 0   │
   │ data = any   │               │ data = comm. │  ─────────────────►   │ data = 0...0 │
   │ (writable)   │               │ (immutable)  │   data ← 0^N           │ (re-alloc.)  │
   └──────────────┘               └──────────────┘                        └──────────────┘
          ▲                                                                       │
          │                                                                       │
          └───────────────────────────────────────────────────────────────────────┘
                              allocator: only status=0 + data=0 blocks dispensed
```

The system's single invariant, true after every cycle:

> **`status = 0` ⟹ `data = 0...0` for every allocatable block.**
>
> A freshly allocated block is **guaranteed zero-initialized**, because the release event **by definition** makes it so.

This invariant is **minimal from a formal-verification perspective**: a single predicate, no disjunction, no runtime-checkable property — purely a constructive guarantee.

## Microcode primitives and trigger events <a name="isa-primitives"></a>

`SEAL` and `RELEASE` are **NOT CIL opcodes** — they cannot be invoked directly from CIL code. They are **hardware microcode primitives**, triggered only by **well-defined ISA-level events**. This prevents a malicious actor from sealing or releasing arbitrary blocks (see [Trust boundary](#trust-boundary)).

### `SEAL addr` — microcode primitive

```
SEAL addr        ; status: 0 → 1   (atomic)
```

- **Effect:** the block's status bit transitions from 0 to 1. Data is unchanged.
- **Idempotent:** if the block is already sealed, no-op (no trap).
- **Triggers (the only paths by which it may be invoked):**
  - `newobj` / `newarr` microcode seals the object's header region after init-only fields are written
  - `SEND mailbox_ref, block_addr` microcode seals the payload atomically together with cap transfer
  - `hot_code_loader` actor seals the CODE region after AuthCode verify (see `docs/authcode-en.md`)
- **From CIL applications:** unreachable by any path. There is no `[SealAttribute]`, no `Asm.Seal(...)` API.

### `RELEASE addr` — microcode primitive

```
RELEASE addr     ; status: 1 → 0,  data ← 0^N   (atomic, 1 cycle)
```

- **Effect:** the status bit resets to 0 **and** all data bits are forced to zero **in the same cycle**.
- **Memory ordering:** RELEASE acts as a **release barrier** — a subsequent allocation is guaranteed to see the freshly-wiped block.
- **Triggers (the only paths):**
  - `GC_SWEEP` ISA opcode — operates **exclusively on the caller actor's own heap** (per-core SRAM isolation); releases unreached sealed blocks
  - `hot_code_loader` actor — when unloading a CODE region
- **From CIL applications:** also not directly. An actor may only invoke `GC_SWEEP` on its own heap, which only releases already-unreachable blocks of its own. Other actors' blocks are **physically unreachable** (shared-nothing).

### Why this way

The previous version (v1.0) described SEAL and RELEASE as **direct CIL opcodes**, which opened an attack vector: a malicious actor that somehow acquired caps to another actor's sealed block could have RELEASED it, rewritten it, and SEALED it again — leaving the "sealed" status seemingly untouched. In the new model, this is **physically impossible**: SEAL and RELEASE are unreachable from arbitrary context, only the well-defined trigger events invoke them.

### No separate `WIPE` primitive

Earlier drafts proposed a separate `WIPE` primitive for "pre-release sanitization". The current model **does not need this**, because RELEASE performs the wipe atomically. Two benefits: (1) no awkward "sealed-but-cleaned" intermediate state; (2) two primitives instead of three, easing formal verification.

## Trust boundary <a name="trust-boundary"></a>

Quench-RAM security is **not based on privilege separation** (no kernel mode vs. user mode — Neuron OS explicitly rejects this, see `docs/neuron-os-en.md` line 731). It rests instead on **the combination of two existing mechanisms**:

### 1. Microcode-only primitives (SEAL, RELEASE)

Since these are not callable from CIL application level, a malicious actor **cannot directly** trigger them. Only the runtime (microcode) invokes them, reacting to the well-defined trigger events.

### 2. Per-actor heap isolation (shared-nothing)

This **already exists** in Neuron OS (lines 366-369). Every actor lives in its own per-core SRAM heap with its own capability system. Consequence:

| Attack attempt | Why it fails |
|----------------|--------------|
| Malicious actor invokes `GC_SWEEP` | operates only on **its own heap** → cleans up its own garbage, cannot reach others' |
| Malicious actor tries to obtain cap to another actor's block | capability tag is HMAC'd, unforgeable — router checks (line 398) |
| Malicious actor writes code calling SEAL or RELEASE | the linker (`cli-cpu-link`) rejects it — no such CIL opcode exists |
| Malicious actor compromises `hot_code_loader` | `hot_code_loader` is itself a **signed, verified actor** (AuthCode), its code cannot be tampered with |

**Result:** the trust boundary is **the runtime itself** (a few thousand lines of microcode), not application code (potentially millions of lines of CIL). This is seL4 / CHERI-style minimized TCB (Trusted Computing Base).

## Hardware implementation <a name="hardware"></a>

The implementation completes in **a single cycle**:

```
RELEASE(addr):
  ┌─ status_bit[addr] ← 0
  ├─ row_select[addr] ← active
  ├─ all_bitlines    ← 0           ◄── all columns in parallel
  └─ commit clock edge
```

The key is a single extra hardware signal: a **"broadcast clear"** line from the row decoder that, instead of the normal `wordline + bitline_input` mechanism, **pulls all bitlines to ground** for the selected row. This technique **already exists in most modern SRAMs** for built-in self-test (BIST) — it just needs to be exposed to the ISA.

### Memory technology mapping

| Technology | RELEASE realization | Notes |
|-----------|---------------------|-------|
| 6T SRAM | broadcast bitline-clear, 1 cycle | BIST hardware typically already present |
| 8T/10T SRAM | dedicated clear-port | area-positive, but faster |
| eMRAM | single-step "reset to AP state" | naturally polarity-aware |
| eFRAM | bipolar pulse, ~5-10 ns | compatible, slower |
| PCM | crystalline reset | one step slower, energy-intensive |
| eFlash NAND | no Quench-RAM here — flash itself works this way | Quench-RAM appears **above** as an abstraction |

### Estimated area overhead

| Granularity | Status bit overhead vs. data | Note |
|-------------|------------------------------|------|
| 4 KB page | 0.003% | OS-level page protection |
| 256 byte block | 0.05% | typical CIL object size |
| 64 byte cache line | 0.2% | cache-aligned |
| 16 byte mini-block | 0.8% | fine-grained capability tags |

The broadcast-clear circuit itself is **negligible** — one extra wordline-class wire per row, plus small decoder logic.

**Total:** ~0.5% chip area overhead for full Quench-RAM integration, including status-bit storage and clear-broadcast wiring.

## Relationship to ECMA-335 default-init semantics <a name="ecma335"></a>

ECMA-335 (the CLI bytecode standard) **mandates** that every managed object's fields be initialized to the type's **`default(T)`** value at allocation:

| Type | `default(T)` |
|------|--------------|
| `int`, `long`, `byte`, `bool`, `enum` | 0 / false |
| `float`, `double` | 0.0 |
| reference type | `null` |
| `struct` | each field recursively default |

**All zeros.** No exception.

Quench-RAM's RELEASE semantics **satisfy this requirement in hardware**. A freshly allocated CIL object's fields require **no software zero-init step** — the memory is **already** zero-initialized thanks to the preceding RELEASE event.

### Concrete performance gain

In the current .NET runtime, `newobj` and `newarr` opcodes require **explicit zero-init** that takes hundreds of cycles for large objects (e.g., a 4 KB struct array). On Quench-RAM this step **disappears**:

```
// On a traditional CPU:
newarr int32[1024]:
  - allocation:       ~5 cycles
  - zero-init 4 KB:   ~250 cycles  ◄── disappears on Quench-RAM
  - return ref:       ~1 cycle
                      ─────────
                      ~256 cycles

// On Quench-RAM (CIL-T0):
newarr int32[1024]:
  - allocation:       ~5 cycles
  - zero-init:        0 (already zero since RELEASE)
  - return ref:       ~1 cycle
                      ─────────
                      ~6 cycles    ◄── ~40× faster on large allocs
```

### Invariant restated

> **Quench-RAM + ECMA-335 = zero-init guarantee for every CIL allocation, with zero runtime overhead.**

This is simultaneously a **security** and a **performance** advantage from a single mechanism — a rare combination in hardware design.

## Synergy with per-core GC <a name="gc-synergy"></a>

`docs/neuron-os-en.md` lines 366–369 establish that every Rich core has its own **bump allocator + mark-sweep GC**. Quench-RAM **dramatically simplifies** this GC:

### Mark phase
Unchanged: the GC walks the reference graph and marks every reachable object.

### Sweep phase
For unmarked objects, the GC **issues a `RELEASE` opcode**. That's it.

```csharp
// Pseudocode for the per-core GC sweep
foreach (var obj in heap.Blocks)
{
    if (!obj.IsMarked)
    {
        Asm.RELEASE(obj.Address);   // 1 cycle, atomic: status=0 + data=0
    }
}
```

### Allocation

The bump allocator only dispenses **`status=0 + data=0`** blocks. Since the invariant guarantees that **every status=0 block is uniform-zero**, the allocator has no work to do for content initialization.

### What the system gains

| Aspect | Traditional GC | Quench-RAM GC |
|--------|---------------|----------------|
| Sweep ops per object | mark-clear, freelist update, possible compaction | a single RELEASE opcode |
| Zero-fill after free | software loop | hardware atomic |
| Forgotten zero-fill GC bug | recurring CVE source | **physically impossible** |
| GC pause measurability | complex (heap-traversal time) | simple (RELEASE count × 1 cycle) |
| Per-core parallel GC | hard (lock-free freelist) | **trivial** (only local RELEASEs) |

### Pinning for free

The "pinned object" notion in traditional .NET GC: an object the GC cannot move (e.g., for interop). On Quench-RAM, **every sealed object is automatically pinned**, because its content is immutable. This is a natural guarantee for the interop layer.

## Synergy with the actor-model capability system <a name="actor-synergy"></a>

The `ActorRef` capability token defined in `docs/neuron-os-en.md` lines 388–398 becomes **physically defendable** with Quench-RAM:

```csharp
public readonly struct ActorRef
{
    public int  CoreId;
    public int  MailboxIndex;
    public long CapabilityTag;   // HMAC-style, only the registry can write
    public int  Permissions;
}
```

An `ActorRef` instance stored in a **sealed Quench-RAM block** becomes **tamper-proof at the hardware level**:

- The capability tag cannot be rewritten — the block is sealed
- An actor bug attempting to forge another actor's capability is **physically incapable** of doing so (a write attempt after SEAL traps)
- The capability registry itself (`capability_registry`, see line 243) stores issued tags in sealed blocks

### Hybrid object layout

A CIL object can be split into two regions:

```
┌──────────────────────────────────────────────┐
│ SEALED region (status=1, immutable):         │
│   TypeToken      ─┐                           │
│   ObjectId       ─├── identity, capability    │
│   CapabilityTag  ─┘                           │
│   init-only fields (readonly properties)     │
├──────────────────────────────────────────────┤
│ MUTABLE region (status=0):                   │
│   variable fields (mutable state)            │
│   GC mark bit, generation                    │
└──────────────────────────────────────────────┘
```

The linker (`cli-cpu-link`) decides at build time which region every field belongs to, based on `init` and `readonly` markers:

- C# `init` and `readonly` fields → SEALED region
- Mutable fields → MUTABLE region
- Object reference (`ActorRef`) **always** points to the SEALED region

### What the system gains

- **Type confusion physically eliminated:** the `TypeToken` is sealed; a memory-corruption bug cannot forge it
- **Capability forging physically eliminated:** the `CapabilityTag` is sealed; cannot be overwritten
- **Object identity stability:** the `ObjectId` is sealed; remains consistent across GC moves

## Security guarantees <a name="security"></a>

Quench-RAM provides physical-level defense against **seven new attack classes** that the current `docs/security-en.md` table either omits or only partially addresses:

| Attack class | CWE | Traditional CPU | With Quench-RAM |
|-------------|-----|-----------------|------------------|
| Use-after-free | CWE-416 | Vulnerable | **Physically eliminated** — re-alloc only from uniform blocks |
| Double-free | CWE-415 | Vulnerable | **Trap** — second RELEASE no-op trap |
| Information leak in freed memory | CWE-244, CWE-226 | Heartbleed-class, common | **Constructively eliminated** — RELEASE = wipe |
| Uninitialized memory read | CWE-457 | Common (legacy C/C++) | **Eliminated** — every alloc provably zero-init |
| Cold boot key recovery | — | Recoverable from DRAM | **Eliminated** — sealed key only released via RELEASE, which wipes |
| Sensitive data in swap | CWE-200 | OS-dependent | **Eliminated** — no swap (per-core SRAM) + sealed unswappable |
| Capability tag forging | — | Possible via RAM patching | **Eliminated** — stored in sealed region |

### What is NOT defended

For honesty, Quench-RAM **does not** defend against:

- **Side-channel attacks** — a SEAL/RELEASE opcode is timing-detectable; if this is sensitive (e.g., in a cryptographic context), constant-time runtime is required
- **Physical attacks** (FIB, probing) — tamper resistance is a separate design layer; see `docs/secure-element-en.md`
- **Spoofing the wake-up signal** — the status bit can fall victim to an SEU (single-event upset); ECC protection is required around it
- **GC-overrun DoS** — an actor can intentionally cycle SEAL-RELEASE rapidly to load the GC; rate limiting is required

## Formal verification profile <a name="formal"></a>

Quench-RAM ISA semantics are **explicitly designed for formal verification**. The complete specification is one invariant plus two state-transition rules:

```
Invariant:    ∀ block b. status(b) = 0 ⟹ ∀ bit i ∈ b. data(b, i) = 0

SEAL b:       pre:  status(b) = 0
              post: status(b) = 1  ∧  data(b) unchanged

              pre:  status(b) = 1
              post: no-op (idempotent)

RELEASE b:    pre:  status(b) = 1  ∧  hold(release_cap, b)
              post: status(b) = 0  ∧  ∀ bit i. data(b, i) = 0
```

This is **three lines of operational semantics**, translating into a few hundred lines of formal code in Coq, Isabelle/HOL, Lean 4, or F\*. Invariant preservation across each transition is **directly derivable** from the rules.

The F5 timeline in `docs/security-en.md` line 184 (refinement proof of RTL against ISA) is **directly applicable** to the Quench-RAM hardware implementation.

## Granularity and area overhead <a name="granularity"></a>

Quench-RAM block size has decisive impact on usage patterns. The four relevant granularities:

### 4 KB page
- **Use:** OS-level memory protection in systems without virtual memory
- **Overhead:** 0.003%
- **Disadvantage:** too coarse for typical CIL objects; pinning a 16-byte object pins the whole 4 KB page

### 256 byte block
- **Use:** typical CIL object size, good compromise
- **Overhead:** 0.05%
- **Advantage:** most objects fit in one block; sealed/mutable split is easily managed

### 64 byte cache line
- **Use:** F6+ Rich cores with cache
- **Overhead:** 0.2%
- **Advantage:** cache-coherent RELEASE is natural; fine-grained sealing

### 16 byte mini-block
- **Use:** capability tag storage, small structs
- **Overhead:** 0.8%
- **Disadvantage:** many status bits, more complex decoder

### Recommended heterogeneous solution

A single F6 Rich core may support **multiple granularities** simultaneously across different memory regions:

| Region | Granularity | Use |
|--------|-------------|-----|
| `CODE` | n/a | always sealed from boot (separate QSPI flash, R/O) |
| `DATA-fine` | 16 byte | capability registry, ActorRef pool |
| `DATA-medium` | 256 byte | actor state objects |
| `STACK` | n/a | no Quench-RAM (per-frame allocation is fast) |
| `MAILBOX` | 64 byte | sealed message payloads |

The Nano core (F4) is simpler: only **256 byte block** granularity, designed for simplicity.

## Related technologies <a name="related"></a>

Quench-RAM is **not the first attempt** at these problems; the following systems offer partial solutions:

| System | Matching feature | What it does NOT provide |
|--------|------------------|---------------------------|
| **NAND Flash erase** | block-level wipe + immutability | not a hardware ISA primitive, granularity coarse |
| **CHERI sealed capabilities** | sealed pointer immutability | the memory itself is not wiped on release |
| **ARM MTE (Memory Tagging)** | 4-bit color tag per region | not immutability, no auto-wipe |
| **Intel CET shadow stack** | write-once stack region | special-purpose, not general |
| **Trusted Platform Module monotonic counters** | write-once counter | single value, not general memory |
| **Forth `here`/`forget` model** | append-only dictionary | software, not hardware-enforced |
| **Erlang persistent_term** | immutable runtime constants | software, BEAM-level |

Quench-RAM's **unique combination**:

- Hardware-enforced
- ISA primitives directly accessible
- Atomic RELEASE = wipe + free in one cycle
- Constructive zero-init guarantee for every allocation
- Minimal semantics suited for formal verification

## Open questions <a name="open"></a>

This document records the **architectural direction**; the following details are to be finalized during F5 RTL design:

### 1. SEAL idempotency
**Current proposal:** idempotent (second SEAL is no-op).
**Alternative:** trap on second SEAL so programmer errors surface earlier.
**Decision:** after F5 RTL prototype, based on measurement.

### 2. Granularity configurability
**Current proposal:** fixed granularity per region (see section 11).
**Alternative:** runtime-configurable per actor.
**Decision:** likely fixed, because runtime configurability would add significant complexity to the router.

### 3. Release-cap delegability
**Current proposal:** at SEAL time, release-cap is routed to the owning actor and its supervisor.
**Alternative:** owner can delegate to a temporary "cleaner" actor (e.g., a timed GC trigger).
**Decision:** delegable, but the delegate **cannot** further delegate — single-step.

### 4. ECC integration with the status bit
**Current proposal:** the status bit lives in the same ECC word as its data.
**Alternative:** separate ECC-protected small status array.
**Decision:** combined ECC, because a status-bit flip + data-bit flip combination is then detectable.

### 5. Cache coherence on F6+ Rich cores
**Current proposal:** sealed blocks **never** evict — they can live in the read-only cache forever.
**Alternative:** standard LRU, periodic re-fetch.
**Decision:** sealed = no-evict, because this is a free optimization and simplifies cache coherence.

### 6. Power-loss recovery for NVRAM
**Current proposal:** if RELEASE is interrupted, the status remains at 1 → safe default (sealed = data preserved).
**Alternative:** transactional journal in the sealed region.
**Decision:** safe-default suffices for typical usage; transactional journal only in F7+ enterprise variant.

## Phase introduction <a name="phases"></a>

Quench-RAM is **not a prerequisite** for F0-F4; these continue to operate on the existing SRAM model. Introduction is **gradual**:

| Phase | Quench-RAM role |
|-------|-----------------|
| F0–F2 (simulator) | software emulation in `TCpu`: extra status bit per block, RELEASE wipes in software; optional, switch-enabled |
| F3 (Tiny Tapeout) | no hardware Quench-RAM (area limit), but the CIL-T0 ISA spec **already includes** SEAL/RELEASE opcodes, emulated in microcode |
| F4 (multi-core sim) | software emulation on every core; we collect measurements on typical SEAL/RELEASE ratio |
| **F5 (RTL prototype)** | **first hardware implementation** on a 64-byte cache-line granularity Quench-RAM array; we measure area overhead and power cost |
| F6 (ChipIgnite tape-out) | **mandatory hardware feature** in every DATA and MAILBOX region; F6 Cognitive Fabric One is the first real Quench-RAM chip |
| F6.5 (Secure Edition) | finer granularity (16 byte) for the capability registry attached |
| F7 (silicon iter 2) | possible NVRAM integration (eMRAM/eFRAM), transactional journal options |

## Cross-references

- `docs/architecture-en.md` — the CFPU microarchitecture into which Quench-RAM integrates
- `docs/security-en.md` — security model that Quench-RAM extends
- `docs/neuron-os-en.md` — the per-core GC and capability registry that use Quench-RAM
- `docs/secure-element-en.md` — F6.5 Secure Edition, where fine-grained Quench-RAM is mandatory

## Changelog <a name="changelog"></a>

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-16 | Initial versioned release. Two-opcode model (SEAL + RELEASE), atomic wipe-on-release, ECMA-335 default-init compatibility, integration with per-core GC and actor-capability system. |
| 1.1 | 2026-04-16 | **Security fix:** SEAL and RELEASE are NOT CIL opcodes but microcode primitives, invokable only via well-defined trigger events (`SEND`, `newobj`, `GC_SWEEP`, `hot_code_loader`). New section: [Trust boundary](#trust-boundary). The mechanism builds on per-actor heap isolation (shared-nothing), not a new privilege bit. |
