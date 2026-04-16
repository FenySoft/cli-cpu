# CLI-CPU — Security Model and Threat Analysis

> Magyar verzio: [security-hu.md](security-hu.md)
> Version: 1.0

This document describes the CLI-CPU **security model**: what it protects at the hardware level, what it does not, which attack classes it is immune to, what formal verification is feasible, and which certification paths it targets long-term.

## Why it matters now

In the AI era, the security landscape has **fundamentally** changed, and traditional CPU architectures (x86, ARM, RISC-V) **are not prepared** for it:

1. **AI-generated code is everywhere.** Copilot, ChatGPT, Claude, and similar tools generate billions of lines of code daily, a significant portion of which is vulnerable. The "trust the developer" model is dead.
2. **Supply chain attacks.** Packages on `npm`, `PyPI`, `NuGet`, `crates.io` are being compromised. The SolarWinds, log4j, and xz-utils incidents demonstrated that software-level defenses alone are insufficient.
3. **Autonomous AI agents.** An LLM-based agent can independently make decisions and execute operations. When manipulated through prompt injection, it can cause real damage.
4. **Microarchitectural vulnerabilities.** Spectre, Meltdown, L1TF, Rowhammer, Retbleed, Inception — modern OoO CPUs are riddled with architectural bugs that cannot be patched in software without performance penalties.
5. **The post-quantum threat is approaching.** By 2030, new cryptographic algorithms will be needed, along with new hardware primitives to support them.

In this environment, the "security = software abstraction" paradigm has failed. The CLI-CPU answer: **security = a physical property of the silicon**, which neither software nor firmware-level attacks can circumvent.

## Threat Model

### What we protect (in-scope)

- **Data integrity** — one program cannot write to another program's memory
- **Control Flow Integrity** — a program cannot jump to an arbitrary address (ROP/JOP protection)
- **Type safety** — an object cannot be reinterpreted as a different type
- **Method contracts** — a method can only be called with its declared parameters
- **Memory management correctness** — no use-after-free, no double-free, no buffer overflow
- **Stack safety** — stack overflow and underflow are hardware-checked
- **Cross-core isolation** — compromise of one core does not propagate to others
- **Code integrity** — running code cannot be modified at runtime (R/O CODE region)

### What we do NOT protect (out-of-scope — honest disclaimer)

- **Physical attacks** — if someone gains physical access to the chip and decapsulates it, the contents become visible (FIB, probing attacks). This is the domain of tamper resistance, which is a separate design layer (e.g., SEAL, mesh shielding), and the current design **does not** include it.
- **Full side-channel protection** — power analysis, EM emission, and thermal side-channel attacks are not addressed in the current design. The CLI-CPU's simpler pipeline makes these **harder**, but not impossible.
- **Fault injection** — protection against laser/glitch attacks requires the tamper-resistance design layer.
- **Denial of Service** — a malicious core can flood the mailboxes, slowing the system down. Rate limiting is the responsibility of the software runtime (Neuron OS).
- **Business logic bugs** — if the C# code itself incorrectly checks permissions, the hardware cannot fix that. This remains the responsibility of secure-by-design software development.
- **Quantum attacks** — the current design does not include post-quantum crypto primitives; this is a post-F7 addition.

### Assumed attacker capabilities

The security model assumes the attacker:
- **Can run malicious CIL code** on the chip (at user level)
- **Can send arbitrary input messages** to the mailbox
- **Does NOT have** physical access to the chip
- **Cannot modify** the firmware / microcode (this is protected by secure boot)
- **Cannot modify** the manufacturing GDS (this is a supply chain audit concern)

## Architectural guarantees

### 1. Hardware memory safety

Every memory access is **hardware-checked**:

| Check | Where it happens | Trap |
|-------|-----------------|------|
| Stack overflow | Every push | `STACK_OVERFLOW` |
| Stack underflow | Every pop | `STACK_UNDERFLOW` |
| Local variable index >= count | `ldloc`, `stloc` | `INVALID_LOCAL` |
| Argument index >= count | `ldarg`, `starg` | `INVALID_ARG` |
| Branch target outside code region | `br*` | `INVALID_BRANCH_TARGET` |
| Call RVA outside code region | `call` | `INVALID_CALL_TARGET` |
| Div by zero | `div`, `rem` | `DIV_BY_ZERO` |
| Array bounds (F5+) | `ldelem`, `stelem` | `ARRAY_INDEX_OUT_OF_RANGE` |
| Null dereference (F5+) | `ldfld`, `stfld`, `callvirt` | `NULL_REFERENCE` |
| Type check failure (F5+) | `castclass`, `isinst` | `INVALID_CAST` |

**Consequence:** **the entire buffer overflow attack class (CWE-119, CWE-120, CWE-121, CWE-122) is eliminated at the architecture level**. This is not a software mitigation — the hardware physically cannot perform an unauthorized access.

### 2. Type safety

CIL per ECMA-335 mandates a **verifiable code** concept that is type-safe. CLI-CPU enforces this in hardware:

- Every stack slot carries an **implicit type tag** (F5+)
- `castclass` and `isinst` traverse the type hierarchy in hardware based on runtime metadata
- An `int32` **cannot** be interpreted as an `object`, nor vice versa
- There is no pointer-cast, no `reinterpret_cast<T*>`

**Consequence:** **type confusion attacks** (CWE-843, one of the most common critical browser vulnerabilities) **are eliminated**.

### 3. Control Flow Integrity (CFI)

On traditional CPUs, CFI is a software-level defense (Clang CFI, Intel CET, ARM PAC) that is **supplementary** and **bypassable**. On CLI-CPU, CFI is **not optional** — it is part of the ISA:

- **Call target verification:** every `call` and `callvirt` opcode takes an address that **must be a method entry point according to the CIL metadata**. Arbitrary addresses cannot be jumped to.
- **Return target verification:** `ret` jumps to an address from a **frame pointer structure** placed by hardware frame setup. ROP gadget chaining is impossible because the return address stored on the stack is in a **separate memory region**, not on the user stack.
- **Branch target verification:** every unconditional and conditional branch target must be **within the current method's code range**. Cross-method jumps can only occur via `call`/`ret`.

**Consequence:** **ROP (Return-Oriented Programming) and JOP (Jump-Oriented Programming) attacks are eliminated.** Not made harder — **physically impossible**. This alone accounts for roughly 30-40% of published kernel exploits.

### 4. Shared-nothing isolation

On a multi-core CLI-CPU (F4+), **there is no shared memory** between cores. Each core operates in its own private SRAM, and cores communicate **exclusively** through mailbox FIFOs.

**Consequence:**
- **Cross-core side-channels** (such as Foreshadow, L1TF, Fallout) **are eliminated** — no shared cache, no shared TLB
- **False sharing covert channels are eliminated** — no shared cache lines
- **Rowhammer cross-process** — harder, because each core's SRAM is local, not DRAM
- A compromised core **cannot** communicate with another core through memory; only through router-authorized mailbox messages, which can be logged

### 5. Code-data separation (Harvard architecture)

The CODE region on the chip resides in a **separate address space** from the DATA/STACK regions and is physically accessible on separate QSPI flash, which is **hardware read-only**. Code **cannot be modified** at runtime.

**Consequence:**
- **No shellcode injection** — bytes cannot be written to the CODE region
- **No JIT spraying** — **because there is no JIT**. This is one of CLI-CPU's strongest security arguments: CIL runs natively, there is no JIT compiler that could be exploited (Firefox, Chrome, and Safari JITs are exploited annually).
- **No self-modifying code** — neither accidentally nor intentionally

### 6. Absence of speculative execution

The CLI-CPU uses an in-order, non-speculative pipeline. **There is no branch prediction bypass, no out-of-order execution** (at least through F6).

**Consequence:** **Spectre v1, v2, v4, Meltdown, L1TF, MDS, Inception — the entire speculative attack family is eliminated.** This is significant because on modern CPUs, **new variants emerge every year**, and each fix incurs a 5-30% performance penalty.

## Attack immunity table

| Attack class | CWE | Traditional CPU | CLI-CPU |
|-------------|-----|-----------------|---------|
| Buffer overflow | CWE-119/120/121/122 | Vulnerable | **Eliminated** (hardware bounds check) |
| Use-after-free | CWE-416 | Vulnerable | **Eliminated** (hardware GC) |
| Double-free | CWE-415 | Vulnerable | **Eliminated** (hardware GC) |
| Null dereference | CWE-476 | DoS potential | **Traps** (hardware null check) |
| Type confusion | CWE-843 | Vulnerable | **Eliminated** (hardware isinst/castclass) |
| Integer overflow leading to buffer overflow | CWE-190 | Vulnerable | **Partially protected** (optional overflow trap) |
| Format string | CWE-134 | Vulnerable | **Eliminated** (no printf, no C strings) |
| Stack overflow (unbounded recursion) | CWE-674 | Stack smashing | **Hardware trap** |
| **ROP (return-oriented programming)** | CWE-121 | Primary attack surface | **Eliminated** (CFI in the ISA) |
| **JOP (jump-oriented programming)** | — | Vulnerable | **Eliminated** (branch target verification) |
| Shellcode injection | CWE-94 | Vulnerable | **Eliminated** (hardware R/O CODE) |
| JIT spraying | — | Every JIT-based runtime | **Eliminated** (no JIT) |
| **Spectre v1/v2/v4** | CWE-1037 | Vulnerable | **Eliminated** (no speculation) |
| **Meltdown** | CWE-1037 | Vulnerable | **Eliminated** (no speculation) |
| **Rowhammer** | CWE-1247 | Vulnerable | **Hard** (per-core SRAM, deterministic) |
| Cache timing side-channel | CWE-208 | Vulnerable | **Hard** (shared-nothing, minimal shared cache) |
| Branch predictor side-channel | CWE-1037 | Vulnerable | **Eliminated** (no branch predictor) |
| Foreshadow / L1TF | CWE-1037 | Vulnerable | **Eliminated** |
| Cross-core MDS | CWE-1037 | Vulnerable | **Eliminated** (shared-nothing) |
| Race condition in GC | CWE-362 | Vulnerable | **Eliminated** (per-core private heap, no global GC) |
| Deadlock (lock contention) | CWE-833 | Vulnerable | **Eliminated** (no shared locks, only mailbox) |
| False sharing covert channel | — | Vulnerable | **Eliminated** (no shared cache) |
| Information leak in freed memory | CWE-244, CWE-226 | Heartbleed-class, common | **Eliminated** ([Quench-RAM](quench-ram-en.md): RELEASE = atomic wipe) |
| Uninitialized memory read | CWE-457 | Common (legacy C/C++) | **Eliminated** ([Quench-RAM](quench-ram-en.md) + ECMA-335 zero-init) |
| Cold boot key recovery | — | Recoverable from DRAM | **Eliminated** ([Quench-RAM](quench-ram-en.md): sealed key released only via wipe) |
| Capability tag forging | — | Possible via RAM patching | **Eliminated** ([Quench-RAM](quench-ram-en.md): stored in sealed region) |
| Unsigned code execution | CWE-345 | OS-dependent, bypassable | **Eliminated** ([AuthCode](authcode-en.md): hardware verify of every bytecode) |
| Tampered binary execution | CWE-345 | Software check, bypassable | **Eliminated** ([AuthCode](authcode-en.md): SHA-256(bytecode) ↔ cert.PkHash binding) |
| Stateful signature key reuse | — | Easy with software signer | **Eliminated** ([Neuron OS Card](authcode-en.md#neuroncard): single-use NVRAM) |
| Quantum break of signature | — | Shor breaks ECDSA/Ed25519 | **Eliminated** ([BitIce](authcode-en.md): WOTS+/LMS hash-based PQC) |
| Hot code loader tamper | — | Exposed by kernel-level attack | **Eliminated** ([Seal Core](sealcore-en.md) firmware: mask ROM / eFuse immutable) |
| Memory controller write-path bypass | — | Software check bypassable | **Eliminated** ([Seal Core](sealcore-en.md): pre-QRAM WE routing / QRAM SEAL microcode trigger) |
| Supply chain at hardware level | — | Unverifiable | **Verifiable** (open HDL, reproducible build) |
| Supply chain at code level | — | Few systems defend | **Verifiable** ([AuthCode](authcode-en.md) trust chain: eFuse → CA → vendor → card → binary) |

> **Memory cell details:** the Quench-RAM rows are based on the [Quench-RAM](quench-ram-en.md) hardware memory cell, which physically eliminates memory-reuse bugs via a per-block status bit plus atomic "wipe-on-release" semantics.

> **Code loading details:** the AuthCode / BitIce / Neuron OS Card rows are based on the [AuthCode + CodeLock](authcode-en.md) mechanism, which uses a hash-based PQC certificate chain (eFuse → CA → vendor → developer card → bytecode) plus runtime W⊕X separation to guarantee that only authenticated code runs on the chip, and data can never become code.

**Given the above, it is clear why the CLI-CPU security profile is stronger than that of any existing commercial CPU.** We are not adding a few extra layers — the architecture fundamentally **does not permit** these attacks.

## Formal verification

### What it means

Formal verification is the **mathematical proof** that a system conforms to its specification. It is not testing (which only checks a handful of cases), but rather a **proof covering every possible execution**.

### Why it is feasible for CLI-CPU

Formal verification is **practically impossible** for modern OoO x86/ARM cores because:
- 15,000+ opcode variants (x86)
- Thousands of microarchitectural states
- Speculative execution
- Variable cache states

The **CLI-CPU Nano core**, by contrast:
- **48 opcodes**
- **5-stage in-order pipeline** with simple state
- **No speculation**
- **Stack machine semantics**, which map directly to a mathematical model
- **Shared-nothing** — modeling is scoped to a single core

**This is directly** in the size class of the seL4 microkernel formal proof (~10,000 lines of C code), and **smaller** than the CompCert formally verified C compiler.

### Specific tools

| Tool | Use case | Examples |
|------|----------|----------|
| **Coq** | Interactive theorem prover, depth | seL4, CompCert, CertiKOS |
| **Isabelle/HOL** | Interactive theorem prover | seL4 (other half) |
| **Lean 4** | Modern theorem prover, rapidly growing community | Mathlib, terra-cotta project |
| **F\*** | Dependent types + SMT, more automated | Project Everest (HTTPS stack) |
| **Dafny** | Microsoft, SMT-based | smaller systems |
| **TLA+** | Specification + model checking | AWS, Azure critical systems |
| **SMV / SPIN** | Model checking for hardware | CPU verification |

### CLI-CPU formal verification plan

Verification is feasible at **three levels**:

1. **ISA specification level (starting in F3)** — the semantics of all 48 CIL-T0 opcodes formally specified (e.g., in Lean 4 or Coq). **Goal: precise operational semantics for every opcode**, which can later be checked against the hardware and the simulator.

2. **RTL level (after F5)** — the hardware implementation (Verilog or Amaranth) verified against the ISA spec via **refinement proofs**. **Goal: prove that the hardware conforms to the specification in every state.**

3. **C# simulator level (starting in F1)** — the simulator verified through **unit tests and QuickCheck-style property-based** testing. **Not a formal proof**, but complementary assurance.

**Timeline:**

| Phase | Formal verification step |
|-------|--------------------------|
| F1 | C# simulator + property-based tests (FsCheck / xUnit.Theory) |
| F3 | **ISA specification** formally described (Lean 4 or F\*), ~4-6 engineer-months |
| F5 | **Refinement proof** of RTL against the ISA — this is the **real** formal verification, ~12-18 engineer-months |
| F6 | **Revision** of the proof for the heterogeneous Nano+Rich architecture |
| F7 | **External audit** and publication, pre-assessment for certifications |

**This does not mean** that all of this is ready by F0-F4 — only that the possibility **remains open**, and design decisions **do not preclude it**.

## Certification paths

The CLI-CPU security profile is **potentially suitable** for the following industry standards, **provided** formal verification is complete and accompanied by the appropriate software processes (V-model, FMEDA, MTBF analysis).

### IEC 61508 — Functional Safety

**Purpose:** general industrial functional safety
**Levels:** SIL-1 (lowest) ... SIL-4 (highest)
**Requirements:**
- Deterministic execution -- (CLI-CPU satisfies this)
- Formal methods at higher SIL levels -- (targeted)
- FMEDA (Failure Mode Effects and Diagnostic Analysis) — software-side work
- MTBF calculation — from manufacturing data
**Realistic target:** SIL-3 by end of F7, SIL-4 in a subsequent iteration

### ISO 26262 — Automotive Safety

**Purpose:** automotive functional safety
**Levels:** ASIL-A ... ASIL-D
**Requirements (ASIL-D):**
- Hardware redundancy or self-test -- (heterogeneous Nano+Rich redundancy, plus watchdog capability)
- Deterministic response times --
- Formal proof recommended
**Realistic target:** ASIL-B certifiable in F7, ASIL-D in a separate iteration

### DO-178C — Aviation Software

**Purpose:** aviation software
**Levels:** DAL-A (most stringent) ... DAL-E
**Requirements (DAL-A):**
- Formal methods **mandatorily** usable with DO-333 supplement
- Model checking
- Every line of code provably correct
**Realistic target:** DAL-C in F7, DAL-A long-term

### IEC 62304 — Medical Device Software

**Purpose:** medical device software
**Levels:** Class A (no injury) ... Class C (lethal risk)
**Requirements:**
- Risk analysis
- Source code audit
- Software development process documented
**Realistic target:** Class C is **achievable** for a CLI-CPU-based medical device, provided the software development process is at Microsoft/Amazon/Apple level.

### Related standards

- **Common Criteria (ISO/IEC 15408)** — information security certification, EAL-1 ... EAL-7
- **FIPS 140-3** — cryptographic modules (U.S. government)
- **CC EAL-5+** — Apple Secure Enclave level, **targeted** for CLI-CPU

## Related projects — learning from and potential partners

### CHERI (Cambridge Hardware Enhanced RISC Instructions)

**Closest relative.** A University of Cambridge project that adds **capability-based security** at the hardware level. Memory "pointers" are encapsulated and cannot be incremented, decremented, or overwritten. The **Morello** prototype is ARM-based and already running.

**Why it matters to us:**
- The CLI-CPU philosophy runs **in parallel**, but reaches the same goal by a different path (type-safe CIL instead of capability pointers)
- The Cambridge team is doing **formal verification** on CHERI
- **Potential academic partner**

### seL4 Microkernel

The world's first **formally verified** OS kernel (~10,000 lines of C, Coq + Isabelle). The UNSW (Australia) team spent 15+ years proving that the kernel is **bug-free** and all operational guarantees hold.

**Why it matters to us:**
- A precise precedent that **a simple system can be formally verified**
- The Nano core ISA is **smaller** than seL4
- **Potential technical partner** for formal verification

### CompCert

A formally verified C compiler (in Coq). If software is compiled with CompCert, it is **mathematically certain** that the machine code matches the C source.

**Why it matters to us:**
- An analogous goal: a formally verified **CIL to CLI-CPU binary** compiler
- The current `cli-cpu-link` tool's **long-term goal** is a CompCert-style verified version

### Project Everest (Microsoft Research)

A formally verified **HTTPS/TLS stack** in F\*. Provably correct cryptography, parser, and state machine.

**Why it matters to us:**
- Microsoft is behind the .NET ecosystem
- **Potential supporter** of a formally verified hardware implementation of the .NET runtime
- The current nanoFramework (which we build upon) is **Microsoft-supported**

## Responsibility model

The CLI-CPU does **not** provide an absolute security guarantee. The model is best understood as three clearly separated layers:

### Hardware layer (what CLI-CPU guarantees)

- Every CIL opcode behaves according to specification
- Memory safety enforced in hardware
- Type safety in hardware
- Control Flow Integrity in hardware
- Shared-nothing isolation
- No speculative execution

### Firmware / Neuron OS layer (project responsibility)

- Secure boot (signed firmware verification)
- Core allocation integrity
- Message routing integrity
- Supervisory logic (on Rich cores)
- Logging, monitoring, telemetry

### Application layer (developer responsibility)

- Business logic correctness
- Permission model
- Input validation
- Data and authentication management
- Secure communication

**CLI-CPU guarantees the first layer absolutely.** The second layer is **our design responsibility**, but only becomes a real product after F6-F7. The third layer **always** remains the user's responsibility.

## What this means for the project's practical goals

The security dimension **opens new markets** that are valid in parallel with the existing Cognitive Fabric narrative:

| Market segment | Market size (global, 2030 estimate) | CLI-CPU applicability |
|----------------|--------------------------------------|------------------------|
| **AI safety / watchdog** | ~$5-15B | **High** — small formally verified chip alongside critical AI |
| **Critical infrastructure** | ~$50-100B | **High** — SIL-3/4 certification |
| **Automotive (ISO 26262)** | ~$60B | **Medium-high** — ASIL-B/C/D |
| **Aviation (DO-178C)** | ~$20B | **Medium** — long certification cycle |
| **Medical devices** | ~$30B (embedded processor portion) | **High** — Class C certifiable |
| **Secure enclaves (TEE)** | ~$10B | **High** — CHERI-like advantage |
| **Post-quantum crypto accelerator** | ~$5B (emerging market) | **Medium** — future |
| **Confidential computing** | ~$10B | **High** — shared-nothing is natural |
| **Blockchain validator** | ~$5B | **Medium** — deterministic execution |
| **Zero-trust endpoints** | ~$15B | **Medium-high** |
| **Total** | **~$200-300B** | — |

**This is orders of magnitude larger** than the original "CIL-native IoT CPU" positioning. And this is a **real, existing market** — not a future vision.

## Dual-track strategy

In light of the above, the CLI-CPU project should be communicated with **two parallel narratives**:

### Track 1: "Cognitive Fabric"
- **Target audience:** AI researchers, academic institutions, neural network startups
- **Argument:** programmable cognitive substrate, many simple cores, event-driven, .NET native
- **Timing:** active narrative from F4 onward

### Track 2: "Trustworthy Silicon"
- **Target audience:** regulated industries (automotive, aviation, medical, critical infrastructure), defense, privacy-focused tech
- **Argument:** memory safety in silicon, formally verifiable, auditability, attack immunity
- **Timing:** from F5 onward, when formal verification plans are public

**Same hardware**, **two distinct market segments**. Cognitive Fabric is the long-term vision; Trustworthy Silicon is the near-term revenue opportunity.

---

## Next steps

1. **F1 simulator**: property-based tests (e.g., FsCheck for C#) are being integrated now
2. **F3 Tiny Tapeout**: bounds checking, branch target validation, and call target validation are **all included** in the current ISA spec
3. **After F3**: first external security audit (from a friendly CHERI-adjacent community)
4. **Around F5**: formal ISA specification begins (based on Lean 4 or F\*)
5. **After F6**: certification pre-assessment for IEC 61508
6. **Alongside F7**: active communication of the Trustworthy Silicon narrative, seeking regulated industry partners

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
