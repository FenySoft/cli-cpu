# CLI-CPU -- Frequently Asked Questions (FAQ)

> Magyar verzio: [faq-hu.md](faq-hu.md)

> Version: 1.0

This document collects conceptual questions that are essential for understanding the project but do not fit neatly into the detailed spec documents (`architecture-en.md`, `ISA-CIL-T0-en.md`, `security-en.md`, [`Symphact/docs/vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md), `secure-element-en.md`).

The purpose of this FAQ is to help a **new reader** (whether engineer, investor, or curious observer) quickly orient themselves without having to wade through the full ~3,500+ lines of documentation.

## Contents

- [1. What is the CFPU and how does it relate to CLI-CPU?](#1-what-is-the-cfpu-and-how-does-it-relate-to-cli-cpu)
- [2. CLI or CIL -- which is the correct term?](#2-cli-or-cil--which-is-the-correct-term)
- [3. Can CLI be implemented in hardware?](#3-can-cli-be-implemented-in-hardware)
- [4. Can a single physical core serve multiple logical actors?](#4-can-a-single-physical-core-serve-multiple-logical-actors)
- [5. Why is F6-FPGA verification mandatory before silicon tape-out?](#5-why-is-f6-fpga-verification-mandatory-before-silicon-tape-out)
- [6. How do modern CPUs achieve high performance?](#6-how-do-modern-cpus-achieve-high-performance)
- [7. What are the differences between RISC-V, ARM, x86/x64, and CLI-CPU?](#7-what-are-the-differences-between-risc-v-arm-x86x64-and-cli-cpu)
- [8. What are the task scheduling costs?](#8-what-are-the-task-scheduling-costs)

---

## 1. What is the CFPU and how does it relate to CLI-CPU?

**Short answer:** The **CFPU** is the *category* of processing unit. The **CLI-CPU** is the first open-source *implementation* of the CFPU (this project).

### Naming hierarchy

```
Cognitive Fabric       <- architecture family / marketing narrative
  `- CFPU              <- the processing-unit category
       |- CFPU Nano    <- integer-only, small, worker
       `- CFPU Rich    <- full CIL, GC, FPU, supervisor
  `- CLI-CPU           <- the open-source reference implementation of the CFPU (this project)
       |- GitHub: FenySoft/CLI-CPU
       |- C# simulator: CilCpu.Sim
       `- ISA spec: CIL-T0
```

### Analogy

| Category (the *type*) | Implementation (the *product*) |
|-----------------------|--------------------------------|
| **CPU** (Central Processing Unit) | x86, ARM, RISC-V, POWER, MIPS |
| **GPU** (Graphics Processing Unit) | NVIDIA RTX, AMD Radeon, Intel Arc |
| **TPU** (Tensor Processing Unit) | Google TPU v5, Groq LPU |
| **NPU** (Neural Processing Unit) | Apple Neural Engine, Qualcomm Hexagon |
| **CFPU** (Cognitive Fabric Processing Unit) | **CLI-CPU** (first open-source implementation) |

Just as "CPU" is not a specific product but a **category**, so is "CFPU": many small, independent CIL-native cores on a single chip, communicating via shared-nothing mailboxes. CLI-CPU is the **first** such processor, but need not be the last -- the CFPU category is open, and other implementations may follow.

### Why the CFPU fits the \*PU family

The CFPU is **MIMD actor-native** -- every core runs a **different** CIL program with its own state. This distinguishes it from the other PUs:

| Type | Paradigm | Example workload |
|------|----------|------------------|
| CPU | SISD / MIMD (shared memory) | general purpose |
| GPU | SIMD (data parallel) | matrix, shader |
| TPU | Systolic array | neural inference (fixed) |
| NPU | Fixed neuron model | neural inference (edge) |
| **CFPU** | **MIMD (shared-nothing, actor)** | **actor systems, SNN, multi-agent, IoT edge** |

### When to use which term

- **CFPU** -- when talking about the **chip category**, architecture, or processor type
  - *"The CFPU is a new category of processing unit"*
  - *"CFPU Nano vs. CFPU Rich heterogeneous multi-core"*
- **CLI-CPU** -- when talking about the **project**, repo, or concrete implementation
  - *"The CLI-CPU project status is F1.5 DONE"*
  - *"Clone: `git clone https://github.com/FenySoft/CLI-CPU`"*
  - *"The CLI-CPU reference simulator has 250+ tests"*
- **Cognitive Fabric** -- when talking about the **architecture family / marketing narrative**
  - *"Cognitive Fabric + Symphact is the successor to Linux"*

### Why not "CFP"

Because the **CFP** abbreviation is heavily reserved in the hardware industry (*C Form-factor Pluggable* -- 100G/400G optical transceiver MSA standard, data centers, telecom). The **CFPU** with the trailing **\*PU** suffix is **unambiguously** a processing unit, with no industry collision.

---

## 2. CLI or CIL -- which is the correct term?

**Both are correct, but they mean different things.** The two acronyms are siblings, not synonyms.

### Definitions (per the ECMA-335 standard)

| Abbreviation | Full name | Meaning |
|-----------|-----------|----------|
| **CLI** | **Common Language Infrastructure** | The **entire runtime standard** -- type system (CTS), metadata format, file format (PE/COFF assembly), verification, GC model, exception handling, **and** the bytecode language. This is "everything that makes .NET what it is." |
| **CIL** | **Common Intermediate Language** | **The bytecode itself**, which C#/F#/VB.NET compile to. ~220 opcodes, stack-based. It is **one component** of CLI. Formerly known as MSIL (Microsoft IL). |

**Analogy:**
- **CLI** ~ "the JVM" (the entire Java platform: runtime + classfile format + GC + bytecode language)
- **CIL** ~ "Java bytecode" (exclusively the bytecode language in `.class` files)

### How we use these terms in the project

The `docs/` documents **consistently** follow this pattern:

**CLI -- when referring to the full standard, the platform, or the project:**
- **`CLI-CPU`** (project name) -- because the processor implements **the whole CLI** (bytecode + metadata + type system + verification)
- **"full CLI core"** -- because the Rich core supports **every** aspect of ECMA-335
- **"CLI standard"**, **"ECMA-335 CLI"** -- the name of the reference standard

**CIL -- when referring specifically to bytecode or opcodes:**
- **`CIL-T0`** (the ISA name) -- because this is a 48-element **subset of CIL opcodes**
- **"CIL bytecode"**, **"CIL opcodes"** -- the instructions being executed
- **"CIL bytes directly into hardware"** -- the raw bytecode stream

### Why they are not interchangeable

These are **not synonyms**. Swapping them changes the meaning of a sentence, or makes it misleading:

- `"CIL-CPU"` -- wrong, because the processor implements not just the bytecode but the entire CLI infrastructure (e.g., metadata token resolution, verification, GC support)
- `"CLI-T0 ISA"` -- wrong, because the ISA is a set of **opcodes**, and opcodes are CIL, not CLI
- `"CLI bytecode"` -- misleading, because CLI **is not** bytecode; it is the entire standard
- `"CIL standard"` -- the standard (ECMA-335) defines the **CLI**, which contains CIL as one component

### Rule of thumb

> **CLI = the platform / standard / project**
> **CIL = the bytecode / opcodes / ISA**
>
> If you are talking about bytes, instructions, or the ISA --> **CIL**
> If you are talking about the full runtime, the standard, or the processor itself --> **CLI**

---

## 3. Can CLI be implemented in hardware?

**Short answer:** roughly **~95% of CLI maps onto hardware + microcode**. The remaining 5% (dynamic codegen, P/Invoke, reflection.emit) is **intentionally excluded**, and this exclusion is a **virtue, not a deficiency** -- it yields formal verifiability, silicon-grade security, and ultra-low power consumption in return.

This is not a new question: it has been tried before (picoJava, Jazelle, Azul Vega). CLI-CPU builds on their lessons and provides a **concrete, well-reasoned answer**.

### CLI component by component -- what can go into hardware?

The ECMA-335 CLI standard defines seven major layers. Let us examine each one in terms of hardware difficulty and the project's response:

| CLI component | Hardware difficulty | CLI-CPU's answer |
|---------------|-------------------|-------------------|
| **CIL bytecode** (~220 opcodes) | Easy | ~75% hardwired (1 cycle), ~25% microcoded -- see `architecture-en.md` "Hardwired vs microcoded classification" |
| **Stack VM** model | Very easy | Stack cache (TOS in registers), native stack machine |
| **Integer arithmetic** | Easy | Hardwired ALU |
| **Floating point** (R4/R8) | Moderate | FPU **only** on the Rich core (from F5) |
| **Memory safety** (bounds check, null check) | Easy | Hardware side-effect -- every load/store is checked |
| **Control Flow Integrity** | Easy | Hardware branch target validation |
| **Object model** (`newobj`, `ldfld`, `stfld`) | Moderate | Rich core only; not on Nano core |
| **Virtual dispatch** (`callvirt`) | Moderate | **vtable inline cache** (Rich core) |
| **Metadata token resolution** (`ldtoken`, etc.) | Hard | **Metadata Walker coprocessor** |
| **Garbage collection** | Very hard | **Hardware bump allocator** + **per-core private heap** + **microcode GC subroutine** |
| **Exception handling** (try/catch/finally) | Moderate | **Shadow register file** + microcode unwind |
| **Generics** (runtime type parameters) | Hard | Rich core, metadata walker + per-type specialization |
| **String handling** | Moderate | Rich core, standard object treatment |
| **Dynamic code loading** | Excluded | Static `.t0` / `.tr` binaries, build-time linking |
| **Reflection.Emit** (runtime codegen) | Excluded | Replaced by **Roslyn source generator** at build-time |
| **P/Invoke** (native interop) | Excluded | **No native world** -- everything is CIL, there is nothing to invoke |

### The six key decisions that make it possible

The `docs/architecture-en.md` contains six specific architectural decisions that together enable a hardware implementation of CLI:

#### 1. Hybrid decoding (75/25 split)

Common, simple opcodes (`ldc.i4`, `add`, `ldloc`, `stloc`, `br`) are executed by **direct hardware** in 1 cycle. Rare, complex opcodes (`newobj`, `castclass`, `isinst`, `callvirt`) are **trapped by the decoder** and executed via a microcode sequence from ROM.

**This is the picoJava lesson:** it is not worth casting all 220 opcodes in silicon. Optimize for the hot 48, handle the rest with microcode.

#### 2. Shared-nothing model --> no global GC

The biggest headache of a classic CLI implementation is **stop-the-world GC** on a shared heap. CLI-CPU **sidesteps this entirely**:

> "Each core has its own 16 KB SRAM... (from F5) its own object heap" (`architecture-en.md`)

This means:
- **No global GC coordination** --> no stop-the-world
- **No MESI / cache coherency** --> no cross-core synchronization
- **Every GC is core-local** --> simple mark/sweep in microcode
- **No lock contention** on the heap

**This is one of CLI-CPU's strongest innovations regarding "CLI on hardware."** In traditional .NET, this is enormous complexity; here, the problem simply does not exist.

#### 3. Hardware bump allocator + hardware write barrier

The essence of `newobj` executes in roughly ~5-8 cycles:

```
TOS_SIZE  <- object_size
NEW_ADDR  <- HEAP_TOP
HEAP_TOP  <- HEAP_TOP + TOS_SIZE
if HEAP_TOP > HEAP_LIMIT -> TRAP #GC
```

The write barrier (`stfld`/`stelem.ref` for reference types) updates the **card table**, also in hardware. The actual GC (mark/sweep) runs in microcode **only on trap**.

This is an **Azul Vega-style** approach, but open source.

#### 4. Metadata Walker coprocessor

CIL uses **metadata tokens** in most complex opcodes (e.g., `newobj 0x06000042`). A software JIT typically resolves these through table lookups. In CLI-CPU, the Metadata Walker is a **dedicated coprocessor** that:
- Runs in parallel with the main pipeline
- Lives in a separate power domain (sleeps when there is no resolution to perform)
- Reads the PE/COFF metadata tables directly

This is a **classic hardware assist pattern** -- the heavy lifting is done by a dedicated unit, not the main pipeline.

#### 5. Shadow register file for exceptions

CLI exception handling (`try`/`catch`/`finally`) on traditional processors involves **slow stack unwind table stepping**. CLI-CPU instead:

- On `try` entry, microcode **copies the TOS cache + SP + BP + PC** to a **shadow register file** in a single cycle
- On `throw`, microcode restores state from the shadow file and walks the method's exception table to find the handler

**Dramatically faster**, and feasible in hardware because the shadow file is a simple SRAM.

#### 6. Writable microcode (from F6)

The F6 tape-out will include a **writable microcode SRAM** (`roadmap-en.md`):

> "Writable microcode SRAM -- opcode behavior updatable from firmware"

This means that if an ECMA-335 corner case is later found to be incorrectly implemented, **a new chip is not needed** -- a firmware update is loaded into the microcode SRAM. **This is the Transmeta inspiration** (Crusoe/Efficeon), one of the most important patterns in the design.

### What CLI-CPU does NOT do (and why that is a good thing)

These CLI features are **intentionally excluded**, and this is a **virtue**, not a deficiency:

#### Reflection.Emit (dynamic code generation)

In traditional .NET, `Reflection.Emit` allows **generating and executing new IL at runtime**. This:
- Is required by the software JIT (`System.Linq.Expressions`, `ExpressionTree.Compile()`)
- Represents a **massive security hole** (JIT spraying attacks)
- Is **practically impossible in hardware** (self-modifying code, D-cache / I-cache coherence)

The project uses **Roslyn source generators** at build-time instead. This fits the open source philosophy (code is **published**, not runtime-generated) and is **immune to JIT spraying**.

#### P/Invoke (native interop)

In .NET, `DllImport` calls C or Win32 code. On CLI-CPU, **there is no native code** -- **everything is CIL**. There is nothing to invoke.

**This is not a deficiency:** in a Secure Element or safety-critical environment, P/Invoke is precisely the **attack surface** you **do not want** to allow. If everything is CIL, then everything is **verifiable** and **type-safe**.

#### AppDomains (runtime isolation)

In .NET, AppDomains provide software-based isolation. CLI-CPU has **none** -- instead it provides **physical core isolation**. Each actor runs on its own core with its own private SRAM. This is **hardware silicon-grade isolation**, far stronger than a software sandbox.

#### Dynamic assembly loading — varies by core type

In .NET, new DLLs can be loaded at runtime. On CLI-CPU, this **differs by core type**:

- **Nano core (CIL-T0):** **Not possible** -- binaries are **statically linked** `.t0` files, loaded once by the boot-loader. **This is a prerequisite for formal verification**: once the static image has been verified, nobody can modify it at runtime.
- **Rich core (F5+):** **Yes** -- writable microcode SRAM and the Symphact hot code loading feature enable actor-level code replacement at runtime, **without downtime** (Erlang OTP-inspired). All dynamically loaded code must pass **mandatory PQC signature verification** before execution. Use cases: firmware updates, plugin loading, actor migration Nano → Rich, zero-downtime security patches.

#### Thread, async/await runtime

The C# `async/await` keywords compile to **build-time state machine compilation** (done by Roslyn). There is no "async runtime" on CLI-CPU -- just **an actor message on the mailbox**. The async/await and Task patterns **naturally map** to mailbox-based messaging (details in [`Symphact/docs/vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md)).

### Historical lessons -- what CLI-CPU does differently

Four serious attempts at "bytecode CPU in hardware" have been made:

| Project | Year | What it did | Why it failed / succeeded |
|---------|-----|-------------|-------------------------|
| **Sun picoJava** | 1997 | Full JVM bytecode in hardware | Failed: tried to compete on single-core speed against software JIT. Lost to Moore's Law + JIT improvements |
| **ARM Jazelle** | 2001 | Hardware JVM mode on ARM | Failed: trapped on complex opcodes, hybrid approach, but the software JIT overtook it. Removed in 2011 |
| **Azul Vega / Vega2** | 2005 | Custom Java processor with hardware GC assist | Succeeded -- but expensive, narrow market segment, high-frequency trading only |
| **JOP** (research) | 2002-- | Real-time Java on FPGA | Academic success, limited production |

**CLI-CPU extends the Vega model**, but with **open source** and **shared-nothing multi-core**:

> "CLI-CPU does not repeat this mistake. It does not try to compete in single-core speed against modern OoO CPUs -- that would be impossible. Instead, it positions itself in a different dimension." (`README.md`)

According to the "Strategic positioning: Cognitive Fabric" section in `docs/architecture-en.md`, CLI-CPU **does not play the traditional 1 core = 1 thread game**, but rather targets the **many small cores + event-driven + shared-nothing** terrain. On this terrain, a hardware CIL implementation **makes sense** because:

1. **The GC problem disappears** (per-core heap)
2. **The synchronization problem disappears** (mailbox only)
3. **Single-core speed does not matter** (many cores in parallel)
4. **Each idle core-per-task is sleeping** (low power consumption)
5. **Formal verification becomes possible** (no dynamic codegen)

### The key takeaway

> **CLI is NOT 100% mappable to hardware**, because certain features (dynamic loading, reflection.emit, appdomain) are inherently runtime-bound.
>
> **However, ~95% of CLI maps onto hardware + microcode**, provided that:
> 1. We do not use a 1 core = 1 thread model (shared-nothing instead)
> 2. We use per-core private heaps instead of a shared heap (no global GC)
> 3. We use hybrid decoding (hardwired + microcode)
> 4. We accept that the remaining 5% (dynamic codegen, P/Invoke, reflection) **is excluded**
> 5. In return, the reward is **formal verification**, **silicon-grade security**, and **ultra-low power consumption**

**CLI-CPU is exactly this path.** The `docs/architecture-en.md` articulates this clearly, and the seven phases (F0-F7) walk through the steps of this victory path:

- **F3 Tiny Tapeout:** the CIL-T0 48 opcodes in hardware --> proof that it works
- **F4 Multi-core FPGA:** the shared-nothing model --> proof that it scales
- **F5 Rich core:** full CLI --> proof that it is feasible
- **F6-FPGA:** FPGA-verified distributed heterogeneous fabric (3x A7-200T) --> proof that it is production-ready
- **F6-Silicon:** (only after FPGA verification) real silicon --> the commercial proof

---

## 4. Can a single physical core serve multiple logical actors?

**Short answer: yes, and this is not an optional optimization but a fundamental part of the Symphact vision.** A physical core is a hardware resource, a logical actor is an execution unit -- the ratio between them is a **design decision**, not a fixed 1:1 mapping.

### The project documentation explicitly supports this

The [`Symphact/docs/vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md) records the "multiple actors on one core" model in four distinct places:

**Location transparency** (line 107):
> "An actor reference **does not reveal** whether the target is **local (on the same core)**, on another core, or on another chip."

If the architecture were "1 core = 1 actor," the local case would not exist.

**Zero-copy on the same core** (line 365):
> "When an actor sends a message to another actor **on the same core**, the runtime forwards it in zero-copy mode."

The runtime actively **detects and optimizes** the case where two actors live on the same core.

**Local message as a latency category** (line 314):
> "Local (on the same core, internal messages within the same actor) -- ~1-3 cycles, zero copy"

This is a concrete performance category in the project's message latency model.

**Actor migration** (line 110):
> "Actors **can be relocated between cores** at runtime (load balancing)"

This implies that a core has enough capacity to host multiple actors -- otherwise there would be nothing to relocate.

### The key: physical core != logical actor

This distinction must be kept clear, because it is easy to conflate:

| Concept | What it is | How many |
|---------|-------|------------|
| **Physical core** | Hardware execution unit (Nano or Rich) | F6-FPGA: ~26 Nano + 2 Rich (3x A7-200T) |
| **Logical actor** | State + mailbox + behavior (CIL code) | **Thousands or more** total |

A **physical core** is a **hardware resource**. A **logical actor** is an **execution unit** that the runtime schedules onto a core.

### How it works in practice

A physical core's `private SRAM` holds **runtime + multiple actor states**:

```
+--------------------------------+
|      Physical Nano Core        |
|                                |
|  +--------------------------+  |
|  |  Pipeline + stack cache  |  |
|  +--------------------------+  |
|                                |
|  +--------------------------+  |
|  |  Private SRAM: 4 KB      |  |
|  |  +------------------+    |  |
|  |  | Actor runtime    |    |  |
|  |  +------------------+    |  |
|  |  | Actor A state    |    |  |
|  |  | Actor B state    |    |  |
|  |  | Actor C state    |    |  |
|  |  | ... (N actors)   |    |  |
|  |  +------------------+    |  |
|  +--------------------------+  |
|                                |
|  +--------------------------+  |
|  |  Hardware mailbox FIFO   |  |
|  |  (8-deep inbox/outbox)   |  |
|  +--------------------------+  |
+--------------------------------+
```

Message processing steps:

1. **Hardware** --> a message arrives in the mailbox FIFO
2. **Runtime** --> reads it, checks the destination actor ID
3. **Runtime** --> looks up the actor in the local actor table (in private SRAM)
4. **Runtime** --> switches to that actor's state, executes the message handler
5. **Actor** --> returns, the runtime waits for the next message (possibly for a different actor)

This is exactly like an **Akka.NET / Erlang runtime**, but with **hardware mailbox and private SRAM** support -- **cooperative multitasking** where the scheduler does not interrupt message processing ([`Symphact/vision-en.md#2-start`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#2-start)).

### How many actors fit on a single core?

The hard constraint is the private SRAM size. The runtime itself uses ~2-3 KB (Nano) or ~10-20 KB (Rich), with the remainder available for actors:

**Nano core (4 KB private SRAM):**
- Very small actor (~50-100 bytes) --> **~10-20 actors**
- Average actor (~500 bytes) --> **~2-3 actors**
- Large-state actor (~2 KB) --> **~1 actor**

**Rich core (64-256 KB private SRAM + heap):**
- Simple actor (~200-500 bytes) --> **~100-500 actors**
- Complex actor with objects (~5-10 KB) --> **~10-50 actors**

**F6-FPGA full capacity (~26 Nano + 2 Rich, 3x A7-200T multi-board):**
- Average workload: **~1,200-4,000 logical actors** simultaneously
- Optimized for small actors: **up to 8,000+**

**F6-Silicon (optional scale-up to 32 Nano + 2 Rich):**
- Average workload: **~1,500-5,000 logical actors** simultaneously
- Optimized for small actors: **up to 10,000+**

### When should you use the "1 core = 1 actor" model?

There are cases where an actor is intentionally given a dedicated core:

- **Critical timing** -- real-time control, hot network path, audio pipeline
- **Isolation** -- security domain (e.g., crypto key management in the Secure Element)
- **Performance worker** -- SNN neuron, where deterministic time-step matters
- **Fault isolation** -- a leaf node in a supervisor tree that can be restarted without affecting the rest

### When should you use the "1 core = many actors" model?

- **Large actor population** -- thousands or more actors (e.g., web server: 1 request = 1 actor, [`Symphact/vision-en.md#starting-a-new-actor-dynamically`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#starting-a-new-actor-dynamically))
- **Hot/cold workload** -- many actors, but only a few active at any given time (e.g., session handler)
- **Internal nodes of a supervisor tree** -- rarely do work, a dedicated core would be wasteful
- **Kernel actors together** -- `root_supervisor` + `scheduler` + `router` sharing a Rich core

### The full picture -- heterogeneous mapping

The Symphact uses a **flexible N:M actor-to-core mapping**:

```
+--- Rich core 0 ------------------+
| - root_supervisor                |  <- multiple "kernel actors"
| - scheduler                      |    on one core
| - router                         |
+----------------------------------+

+--- Rich core 1 ------------------+
| - http_server                    |  <- many small actors
| - 1000 x session actor           |    on one core
+----------------------------------+

+--- Nano core 5 ------------------+
| - network_packet_filter          |  <- single dedicated actor
+----------------------------------+    on one core (hot path)

+--- Nano core 12-43 --------------+
| - neuron_0 ... neuron_31         |  <- one-actor-per-core
+----------------------------------+    (SNN worker)
```

Same chip, different actor/core ratios tailored to the workload.

### F3 Tiny Tapeout -- a special case

Watch out for a potential apparent contradiction: the `docs/roadmap-en.md` **F3 Tiny Tapeout** version runs a single CIL program on a single core. This does **not** mean the core can only host 1 actor -- in F3, the Tiny Tapeout tile's SRAM is simply too small to justify a runtime.

**The multi-actor runtime arrives in F4** ([`Symphact/vision-en.md#f4----multi-core-scheduler--router`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#f4----multi-core-scheduler--router)), when the `scheduler` + `router` take on real roles, and from F5 onward, multiple actors on a single core is natural.

### The differentiating point versus other neuromorphic chips

This is precisely what **distinguishes CLI-CPU** from traditional neuromorphic chips (Intel Loihi, IBM TrueNorth, BrainChip Akida): **not a fixed 1 neuron = 1 compute unit** topology, but a **flexible N actor x M core** mapping through a runtime. The hardware provides the foundations of isolation and message passing, while the runtime handles flexible placement of logical actors.

---

## 5. Why is F6-FPGA verification mandatory before silicon tape-out?

**Short answer:** because **no silicon tape-out proceeds with a design that has not run on FPGA**. Three MicroPhase A7-Lite XC7A200T boards (134K LUT each, in a Gigabit Ethernet mesh, ~EUR960 total) are sufficient to fully verify the heterogeneous Cognitive Fabric (2 Rich + 26 Nano distributed) -- and it is a **more realistic test**, because the real Cognitive Fabric is also multi-chip. F6-FPGA is a **mandatory prerequisite** for F6-Silicon.

### Why this ordering

A silicon tape-out costs ~$10k and takes 4-6 months. If the design has a bug, that is money and time wasted. FPGA verification runs **the same RTL** on real hardware, but:

| Criterion | F6-Silicon | **F6-FPGA (mandatory first)** |
|----------|-----------|-------------------------------|
| **Cost** | ~$10,000 | **~EUR960 (3 boards)** |
| **Build time** | 4-6 months | **hours** (rebuild) |
| **Cost of bugs** | One bug --> ~$10k + 6 months | One bug --> **immediately fixable** |
| **Iterability** | One-time tape-out | **Unlimited** modifications |
| **Reproducibility** | Unique MPW chip | **Anyone** can reproduce with the same hardware |
| **Finding the sweet spot** | Only one attempt | **Multiple (Rich, Nano) configurations** systematically |
| **Toolchain** | OpenLane2 (open, mature) | OpenXC7 (open, mature on 7-series) |

### The platform: 3 x A7-Lite 200T multi-board mesh

Development uses **3 x MicroPhase A7-Lite XC7A200T** boards (134K LUT each, 512 MB DDR3, Gigabit Ethernet, ~EUR320/board). Vivado ML Standard (WebPACK) supports the Artix-7 family (up to XC7A200T) **free of charge**.

**Single board** (134K LUT, target <=85%):

| (Rich, Nano) | Estimated LUT | Utilization | Purpose |
|--------------|-------------|-------------|-----|
| (0, 20) | ~115K | 86% | Pure Nano fabric (SNN max) |
| (1, 14) | ~105K | 78% | "1 supervisor + many workers" |
| **(2, 8)** | **~105K** | **78%** | **Heterogeneous sweet spot** |
| (2, 10) | ~115K | 86% | Heterogeneous max |

**3 boards in Ethernet mesh** (3 x 134K = 402K LUT aggregate):

| Configuration | Total | Purpose |
|-------------|---------|-----|
| (2,6) + (0,10) + (0,10) | **2R + 26N** | **F6 distributed Cognitive Fabric** |
| (1,8) + (1,8) + (0,10) | 2R + 26N | Symmetric supervisor |

The multi-board configuration is a **more realistic test**, because the real Cognitive Fabric is also multi-chip -- location transparency and the inter-chip mailbox bridge **can only be tested this way**. Optionally, Kintex-7 K325T if a suitable board becomes available.

### The hardware, concretely

- **F4-F6 platform:** 3 x MicroPhase A7-Lite XC7A200T (~EUR320/board) -- in a Gigabit Ethernet mesh
- **Total: ~EUR960** (~$1,030) for the complete F4-F6 FPGA hardware -- the F4-F5 boards are reused

### What FPGA does not provide

- **Power efficiency measurement** -- FPGA power consumption is ~10-20x worse than Sky130 silicon. The energy savings from event-driven operation can only be proven with real numbers on silicon.
- **Maximum clock frequency** -- ~100-200 MHz on FPGA, ~300-600 MHz possible on silicon for the same RTL.
- **F6.5 Secure Edition** -- the Crypto Actor, TRNG, PUF, and tamper detection require silicon-specific hardware, so F6.5 builds on **F6-Silicon**.

### F6-Silicon -- only after FPGA verification

F6-Silicon **may only proceed** when every readiness criterion of F6-FPGA has been met, and at least one of the following is true:

1. The project has received **funding or an industrial partner** to cover the tape-out
2. The **commercial product path** (F6.5 Secure Edition, F7 demo hardware) **requires silicon as a prerequisite**
3. Measuring **real energy efficiency** and **>500 MHz clock frequency** is **critical** for the next milestone

The silicon target builds on the configuration verified on the FPGA multi-board mesh (2R + 26N distributed across 3 chips --> single silicon chip). On ASIC, cores are smaller (std cell vs FPGA LUT), so the configuration verified on multi-board **fits on a single chip**, and can optionally be scaled up -- but only as a straightforward extension of the verified router topology.

**Details:** [`docs/roadmap-en.md`](roadmap-en.md) F6 section and "Three key pivots" subsection.

---

## 6. How do modern CPUs achieve high performance?

**Short answer:** Through three layered techniques: **pipelining** (overlapping), **superscalar execution** (multiple pipelines in parallel), and **out-of-order execution** (processing instructions as operands become available). CLI-CPU deliberately uses none of these -- it pursues performance through a different path.

### 5.1 Pipelining -- the foundation (1985, MIPS R2000)

Executing a single instruction involves 5 stages. The trick: **we do not speed up one instruction**; instead, we **overlap 5 instructions**:

```
Clock:     1     2     3     4     5     6     7     8
         +-----+-----+-----+-----+-----+
Instr 1: | IF  | ID  | EX  | MEM | WB  |
         +-----+-----+-----+-----+-----+-----+
Instr 2:       | IF  | ID  | EX  | MEM | WB  |
               +-----+-----+-----+-----+-----+-----+
Instr 3:             | IF  | ID  | EX  | MEM | WB  |
                     +-----+-----+-----+-----+-----+
```

| Stage | What it does |
|---------|-----------|
| **IF** (Fetch) | Load instruction from memory |
| **ID** (Decode) | Decode + register read |
| **EX** (Execute) | ALU operation or address calculation |
| **MEM** (Memory) | Load/store memory access |
| **WB** (Write Back) | Write result back to register |

One instruction takes **5 cycles**, but since 5 are in the pipe simultaneously, the **throughput** is still 1 instruction/clock.

**Why does this work for RISC?**
1. **Fixed-length instructions** (32 bits) --> IF knows exactly where the next one starts
2. **Load/Store architecture** --> only `ld`/`st` touch memory; arithmetic is register-register
3. **Simple addressing modes** --> no complex `[base + index*scale + disp]`
4. **Many registers** (32) --> fewer memory spills

**Pipeline hazards** (when throughput drops below 1 instruction/clock):
- **Data hazard** -- an instruction waits for a previous result --> **forwarding** (routing EX output back)
- **Control hazard** -- branch instruction: destination unknown --> **branch prediction** (99%+ accuracy)
- **Structural hazard** -- two stages want the same resource --> **Harvard architecture** (separate I/D memory)

### 5.2 Superscalar -- multiple pipelines (1993, Pentium)

Why just 1 pipeline? Add more and **execute multiple instructions simultaneously**:

```
1-wide (classic RISC, 1985):    1 instruction / clock

  ===[IF]===[ID]===[EX]===[MEM]===[WB]===

4-wide (superscalar, 2006):    4 instructions / clock

  ===[IF]===[ID]===[EX]===[MEM]===[WB]===
  ===[IF]===[ID]===[EX]===[MEM]===[WB]===
  ===[IF]===[ID]===[EX]===[MEM]===[WB]===
  ===[IF]===[ID]===[EX]===[MEM]===[WB]===

8-wide (Apple M4 P-core, 2024):   8 instructions / clock

  ===[IF]===[ID]===[EX]===[MEM]===[WB]===  x 8 + OoO
```

### 5.3 Out-of-Order (OoO) -- breaking the sequence (1995, Pentium Pro)

The CPU does **not execute instructions in order**, but rather **as soon as operands are ready**:

```asm
LDR  x1, [x0]        ; slow memory read (~100 clk)
ADD  x2, x3, x4      ; does NOT wait for x1 -> runs on ALU NOW!
MUL  x5, x1, x2      ; WAITS for x1, but x2 is already ready
SUB  x6, x7, x8      ; independent -> can overtake MUL
```

The **Reorder Buffer (ROB)** ensures that results are still **committed in program order** (architectural consistency).

### 5.4 All three techniques together -- modern CPU profile

| | Classic RISC (1985) | Apple M4 P-core (2024) | CLI-CPU Nano |
|---|---|---|---|
| Pipeline | 5-stage, in-order | 14+ stage, OoO | **3-stage, in-order** |
| Decode width | 1-wide | 8-10-wide | **1-wide** |
| ROB | -- | ~700+ entries | **--** |
| Execution units | 1 | ~15 | **1** |
| IPC (theoretical) | 1 | 8-10 | **~0.3-0.5** |
| IPC (actual) | ~0.8 | ~5-6 | **~0.3-0.5** |
| Transistors / core | ~25K | ~300M | **~20-50K** |

**Why does CLI-CPU not use these techniques?**
1. **Area** -- OoO and superscalar require ~1,000x more transistors. We prefer to build ~1,000 Nano cores instead.
2. **Determinism** -- OoO and speculation open Spectre-class side channels. Event-driven and security workloads require deterministic execution.
3. **Power** -- OoO ROB and rename logic account for ~30-40% of power consumption. Sleeping cores consume 0W.
4. **Philosophy** -- CLI-CPU does not compete on single-core IPC, but rather on **message passing between many simple cores**.

### 5.5 The special case of x86/x64 -- CISC outside, RISC inside

x86 is a legacy from 1978 (8086): variable-length instructions (1-15 bytes), complex addressing modes. Modern x86 CPUs **internally translate instructions to RISC**:

```
+----------------------------------------------------------+
|                    x86 FRONTEND                           |
|                                                           |
|  Fetch -> Pre-decode -> Decode -> uop translation -> uop Queue |
|            (length         (breaks x86 instructions into  |
|            determination)   RISC-like uops)               |
|                                                           |
|  ADD [RBX+RCX*4+0x10], RAX                                |
|    -> uop1: LEA  tmp, [addr]      (address calculation)   |
|    -> uop2: LOAD tmp2, [tmp]      (memory read)           |
|    -> uop3: ADD  tmp2, RAX        (addition)              |
|    -> uop4: STORE [tmp], tmp2     (memory write-back)     |
+----------------------------------------------------------+
                         |
+----------------------------------------------------------+
|                    RISC BACKEND                           |
|  (same as ARM: OoO, superscalar)                          |
|  Rename -> ROB -> Scheduler -> Execute -> Retire          |
+----------------------------------------------------------+
```

x86 is essentially a **hardware translator** (frontend) + a **RISC execution engine** (backend).

The **variable instruction length** is expensive: the pre-decoder must figure out where the next instruction starts before decoding it. The solution: a **uop cache** (~4,000-6,000 entries) -- on hot loops, the frontend cost vanishes.

| | ARM (AArch64) | x86/x64 |
|---|---|---|
| Instruction length | Fixed 4 bytes | Variable 1-15 bytes |
| Pre-decode | Not needed (always PC+4) | Required (expensive!) |
| Decode | ARM -> internal op (~1:1) | x86 -> uop translation (complex) |
| uop cache | Not needed | ~4,000-6,000 entries |
| Backend | RISC OoO | RISC OoO (essentially the same) |
| Frontend cost | Low | ~15-20% extra transistors and power |

**x86 performance approaches ARM** (IPC ~5-6 for both), but achieves it at **higher clock frequencies and power consumption**. The extra transistors and energy are consumed by the frontend translator.

---

## 7. What are the differences between RISC-V, ARM, x86/x64, and CLI-CPU?

**Short answer:** Each solves a different problem and makes different trade-offs. x86 optimizes for compatibility, ARM for power efficiency, RISC-V for openness, and CLI-CPU for **efficient message passing between many cores**.

### Architectural profile

| | x86/x64 | ARM (AArch64) | RISC-V | CLI-CPU Nano | CLI-CPU Rich |
|---|---|---|---|---|---|
| **Year of origin** | 1978 (8086) | 1985 (ARM1) | 2010 (Berkeley) | 2025 | 2025 (F5 target) |
| **Philosophy** | CISC -> internally RISC | RISC, pragmatic | RISC, minimalist | Stack machine, actor fabric | Stack machine, full CIL |
| **License** | Intel/AMD closed | ARM Ltd. ~$1-5M | Open (BSD) | Open (MIT/Apache) | Open (MIT/Apache) |
| **Instruction length** | 1-15 bytes | Fixed 4 bytes | 2 or 4 bytes | 1-5 bytes | 1-5 bytes |
| **Registers** | 16 GP + 32 SIMD | 31 GP + 32 NEON | 31 GP + 32 FP | **0** (stack) | **0** (stack + TOS cache) |
| **Operands** | Register + memory | Register-register | Register-register | **Stack (implicit)** | **Stack (implicit)** |
| **Pipeline** | 19+ stage, OoO | 11-14+ stage, OoO | 5-8 stage, in-order/OoO | **3 stage, in-order** | **5 stage, in-order** |
| **Std cells / core** | ~500M tr. | ~50-300M tr. | ~1-2M tr. | **~10K** | **~80K** |

### The same operation (`c = a + b`) -- in four ISAs

```asm
x86/x64:                      ARM (AArch64):
  MOV  EAX, [a]                 LDR  W0, [X1]
  ADD  EAX, [b]   <- can read   LDR  W2, [X3]    <- ONLY load/store
  MOV  [c], EAX     from mem!  ADD  W4, W0, W2     touches memory
                               STR  W4, [X5]

RISC-V:                        CLI-CPU (CIL-T0):
  LW   a0, 0(a1)                ldind.i4        <- reads from addr at stack[TOS]
  LW   a2, 0(a3)                ldind.i4
  ADD  a4, a0, a2               add             <- pop 2, push(a+b)
  SW   a4, 0(a5)                stind.i4
```

**Register machine** (x86, ARM, RISC-V): the instruction **specifies** which register to use --> longer instructions, but the compiler can optimize.

**Stack machine** (CLI-CPU): the instruction **always works from the top of the stack** --> shorter instructions (1 byte!), but more instructions needed.

### Instruction encoding comparison

```
x86/x64 -- variable, complex (historical layers):
+--------+--------+--------+---------+--------+----------+
| Prefix |  REX   | Opcode | ModR/M  |  SIB   | Imm/Disp |
| 0-4 B  | 0-1 B  | 1-3 B  | 0-1 B   | 0-1 B  | 0-8 B    |  1-15 bytes
+--------+--------+--------+---------+--------+----------+

ARM -- fixed, regular:
+----------+-------+-------+-------+-----------+
|  Opcode  |  Rd   |  Rn   |  Rm   |  Imm      |  always 4 bytes
+----------+-------+-------+-------+-----------+

RISC-V -- fixed, minimal:
+----------+-------+-------+-------+-----------+
|  Opcode  |  rd   |  rs1  |  rs2  |  funct    |  4 bytes (or 2B C ext.)
+----------+-------+-------+-------+-----------+

CLI-CPU -- variable, but simple:
+----------+--------------+
|  Opcode  |  Operand     |
|  1-2 B   |  0-4 B       |  1-5 bytes -- no register field!
+----------+--------------+
```

### Code density -- Fibonacci(n)

| ISA | Instruction count | Code size (bytes) |
|-----|--------------|-------------------|
| x86/x64 | ~12 | ~35 |
| ARM AArch64 | ~14 | 56 (fixed 4B) |
| RISC-V (RV32I) | ~14 | 56 (fixed 4B) |
| RISC-V (RV32IC) | ~14 | ~32 (compressed) |
| CIL-T0 | ~18 | ~22 |

CIL-T0 requires **more instructions** but **fewer bytes** -- because there is no register field in the instructions.

### Multi-core model -- the real difference

| | x86/ARM/RISC-V | CLI-CPU |
|---|---|---|
| **Communication** | Shared memory + cache coherence | **Mailbox FIFO (shared-nothing)** |
| **Coherence protocol** | MOESI/MESIF (complex, expensive) | **None (not needed!)** |
| **Synchronization** | Mutex, atomic CAS, memory barrier | **Message passing (lock-free)** |
| **Scaling limit** | Degrades beyond ~8-16 cores (contention) | **1,000+ cores linear** |
| **Heterogeneous** | P+E cores (Apple, Intel, ARM) | **Nano + Rich core** |

```
Traditional shared-memory:         CLI-CPU shared-nothing:

+------+------+------+----+       +----+ +----+ +----+ +----+
|Core 0|Core 1|Core 2|Core|       |Nano|->|Nano|->|Nano|->|Nano|
| L1/L2| L1/L2| L1/L2|L1/2|       +--+-+ +--+-+ +--+-+ +--+-+
+------+------+------+----+          |      |      |      |
|    Shared L3 Cache      |       +--+------+------+------+--+
|  (coherence protocol)   |       |     Mailbox Router       |
+-------------------------+       |  (no shared state!)      |
                                  +--------------------------+
Any core sees any memory          Each core ONLY sends messages
-> coherence protocol needed      -> no coherence needed
-> EXPENSIVE                      -> CHEAP, scales linearly
```

### What is each one best at?

| Use case | Best choice | Why |
|---|---|---|
| Desktop / laptop | x86, Apple M-series ARM | High IPC, ecosystem |
| Server (cloud) | x86, ARM (Graviton) | Virtualization, compatibility |
| Mobile | ARM | Power efficiency |
| Embedded (MCU) | RISC-V, ARM Cortex-M | Small area, inexpensive |
| **Event-driven (IoT, routing)** | **CLI-CPU Nano** | Mailbox, sleep/wake, 0 overhead |
| **Actor systems (Akka.NET, Erlang)** | **CLI-CPU** | Native hardware message passing |
| **Spiking neural network** | **CLI-CPU Nano** | 1 core = 1 neuron |
| **Heterogeneous C# workload** | **CLI-CPU Rich + Nano** | Supervisor (Rich) + workers (Nano) |

### In one sentence

- **x86** -- 45 years of compatibility: does everything, but at a cost (CISC outside, RISC inside)
- **ARM** -- pragmatic RISC: good IPC/watt, but requires a license
- **RISC-V** -- open RISC: minimalist, free, but young ecosystem
- **CLI-CPU** -- a different dimension: does not compete on single-core speed, but on **efficient message passing between many simple cores**

---

## 8. What are the task scheduling costs?

**Short answer:** Context switching on CLI-CPU requires **3-4 orders of magnitude** (1,000-20,000x) fewer clock cycles than on traditional architectures -- and this is **an architectural property**, not a manufacturing technology property. The comparison is in clock cycles to avoid distortion from technology differences.

### Important: CLI-CPU DOES have context switching

The previous FAQ question (question 3) establishes that CLI-CPU uses **N:M actor-to-core mapping**, not a fixed 1:1 mapping. When multiple actors share a core, cooperative actor switching occurs at message processing boundaries. Three modes exist:

| Mode | When | Context switch cost |
|---|---|---|
| **1:1** (dedicated) | SNN neurons, real-time, latency-critical | 0 cycles (no switching) |
| **N:M** (cooperative) | Web server, many sessions, kernel actors | ~10-60 cycles |
| **Migration** (core-->core) | Load balancing, Nano-->Rich upgrade | ~100-500 cycles |

### Context switch cost -- in clock cycles (technology-independent)

| Cost component | x86/x64 | Apple M4 P | Apple M4 E | ARM A720 | RISC-V U74 | CLI-CPU Nano | CLI-CPU Rich |
|---|---|---|---|---|---|---|---|
| Register save/load | ~300-500 | ~150-250 | ~100-170 | ~100-200 | ~30-60 | **~1-2** | **~5-10** |
| TLB flush + refill | ~20K-180K | ~7K-55K | ~3K-22K | ~7K-40K | ~5K-15K | **0** | **~4-8** |
| Cache cooling | ~10K-110K | ~5K-70K | ~1.5K-14K | ~7K-50K | ~1.5K-15K | **0** | **0** |
| Pipeline refill | ~19-25 | ~14-18 | ~8-12 | ~11-15 | ~8-10 | **~3** | **~5** |
| Scheduler decision | ~3K-11K | ~1.5K-5K | ~1K-3K | ~2K-7K | ~300-750 | **~2-5** | **~2-5** |
| **TOTAL** | **~33K-300K** | **~14K-130K** | **~5.5K-39K** | **~16K-97K** | **~7K-31K** | **~10-15** | **~30-60** |

### Why such a large difference?

The general-purpose design of traditional architectures requires the following infrastructure, each of which incurs a penalty on context switch:

| Infrastructure | Traditional | CLI-CPU | Impact |
|---|---|---|---|
| **Register file** (16-31 x 64-bit + SIMD) | Must be saved/loaded | **None** (stack machine) | ~300 clk saved |
| **Virtual memory** (TLB + MMU) | TLB flush + page walk | **No MMU**, physical addressing | ~20K-180K clk saved |
| **Shared cache** (L1/L2/L3 hierarchy) | Cache cooling | **Private SRAM**, never cools | ~10K-110K clk saved |
| **OS kernel scheduler** | Complex algorithm (CFS/XNU) | **HW FIFO poll** (~2-5 clk) | ~3K-11K clk saved |
| **Deep pipeline** (14-19+ stages) | Full pipeline flush | **3-5 stage** flush | ~15 clk saved |

CLI-CPU does not incorporate these infrastructure elements because the shared-nothing actor model does not require them. This is not a deficiency, but a **deliberate design decision**: general-purpose flexibility is traded for scheduling efficiency.

### What happens during a context switch -- step by step

**x86/x64 (OS scheduler, preemptive):**
```
1. Timer interrupt -> kernel mode switch            ~5-10 clk
2. Scheduler decision (CFS red-black tree walk)     ~3K-11K clk
3. XSAVE: 16 GP + 32 ZMM register save -> RAM      ~300-500 clk
4. CR3 write (page table switch)                    ~20-30 clk
5. TLB flush (PCID partial flush)                   ~10-20 clk
   +-> After: ~200-800 TLB misses x ~100-200 clk   ~20K-160K clk
6. XRSTOR: new task register load                   ~300-500 clk
7. Pipeline refill (19+ stages)                     ~19-25 clk
8. L1/L2 cache cooling (cold misses)                ~10K-100K clk
--------------------------------------------
TOTAL:                                              ~33K-300K clk
```

**Apple M4 P-core (OS scheduler, preemptive):**
```
1. Timer interrupt -> EL1 switch                    ~3-5 clk
2. Scheduler decision (XNU)                         ~1.5K-5K clk
3. 31 GP + 32 NEON register save                    ~150-250 clk
4. TTBR0 write (page table switch)                  ~10-15 clk
5. TLB: ASID-based selective flush                  ~5-10 clk
   +-> After: ~100-400 TLB misses x ~60-130 clk    ~6K-52K clk
6. Register load                                    ~150-250 clk
7. Pipeline refill (14+ stages)                     ~14-18 clk
8. L1 cache cooling (128 KB L1D)                    ~5K-70K clk
--------------------------------------------
TOTAL:                                              ~14K-130K clk
```

**CLI-CPU Nano (cooperative actor switch):**
```
1. Actor A: ret (message processing done)           ~1 clk
2. Scheduler: inbox FIFO poll (hardware)            ~2-5 clk
3. PC + SP save -> SRAM (8 bytes)                   ~1-2 clk
4. New actor PC + SP load <- SRAM                   ~1-2 clk
5. Pipeline refill (3 stages)                       ~3 clk
6. TLB flush: no MMU                                ~0
7. Cache cooling: none (private SRAM)               ~0
--------------------------------------------
TOTAL:                                              ~10-15 clk
```

**CLI-CPU Rich (cooperative actor switch):**
```
1. Actor A: ret (message processing done)           ~1 clk
2. Scheduler: inbox FIFO poll (hardware)            ~2-5 clk
3. PC + SP + TOS cache (8x32b) save                 ~5-10 clk
4. Shadow register file save                        ~2-4 clk
5. GC state pointer switch                          ~1 clk
6. Metadata TLB flush (vtable cache)                ~4-8 clk
7. New actor state load                             ~5-10 clk
8. Pipeline refill (5 stages)                       ~5 clk
9. Metadata TLB warmup (first callvirt)             ~10-20 clk
--------------------------------------------
TOTAL:                                              ~30-60 clk
```

### Multi-core synchronization (in cycles)

| Operation | x86/x64 | M4 P | M4 E | ARM A720 | RISC-V | Nano | Rich |
|---|---|---|---|---|---|---|---|
| Mutex lock/unlock | ~200-1000 | ~100-500 | ~60-300 | ~150-700 | ~50-250 | **N/A** | **N/A** |
| Atomic CAS | ~50-300 | ~40-150 | ~25-100 | ~50-200 | ~20-70 | **N/A** | **N/A** |
| Cache line bounce | ~200-500 | ~100-250 | ~60-150 | ~150-300 | ~50-100 | **N/A** | **N/A** |
| **Message send** | ~1K-3K (SW) | ~700-2K | ~500-1.5K | ~700-2K | ~200-500 | **~2-10** | **~2-10** |
| Lock contention (8+ cores) | ~5K-60K | ~2K-25K | ~2K-15K | ~4K-40K | ~1K-10K | **0** | **0** |

On CLI-CPU, **there is no mutex, no atomic, no cache bounce** -- message passing goes through the hardware mailbox FIFO at ~2-10 cycles.

### Fair comparison: on the same manufacturing process

The comparison so far has been in cycles, which is technology-independent. But what would happen if CLI-CPU were built on **the same process node** as today's top CPUs?

| Technology | x86 clock | M4 P clock | Nano clock (est.) | Rich clock (est.) |
|---|---|---|---|---|
| Sky130 (130 nm) -- F3 target | -- | -- | 50-200 MHz | 50-150 MHz |
| TSMC 28nm | ~2-3 GHz | -- | 500-1,000 MHz | 400-800 MHz |
| TSMC 7nm | ~4-5 GHz | -- | 1.0-2.0 GHz | 0.8-1.5 GHz |
| **TSMC 3nm** | **5.7 GHz** | **4.5 GHz** | **2.0-4.0 GHz** | **1.5-3.0 GHz** |

The Nano core (3-stage in-order, ~10K std cells) **scales well** in clock frequency because it is simple. A complex OoO core (19-stage, ~500M transistors) has a harder time raising frequency.

### Area-normalized comparison -- TSMC 3nm, same 12 mm2

| Core type | Area (3nm, est.) | How many fit in 12 mm2 |
|---|---|---|
| x86 Zen 5 core | ~8-12 mm2 | ~1 |
| Apple M4 P-core | ~12 mm2 | 1 (reference) |
| Apple M4 E-core | ~2-3 mm2 | ~4-6 |
| ARM Cortex-A720 | ~3-5 mm2 | ~2-4 |
| RISC-V U74 | ~0.5-1 mm2 | ~12-24 |
| **CLI-CPU Rich** | **~0.02-0.08 mm2** | **~150-600** |
| **CLI-CPU Nano** | **~0.002-0.01 mm2** | **~1,200-6,000** |

### Aggregate throughput -- actor workload, same area and technology

10,000 independent actor tasks: receive message --> ~100 instructions of processing --> reply.

| Architecture | Core count (12 mm2) | Clock (3nm) | Ctx switch (clk) | **Throughput** |
|---|---|---|---|---|
| x86 Zen 5 | 1 | 5.7 GHz | ~166K | ~34K msg/s |
| M4 P-core | 1 | 4.5 GHz | ~72K | ~62K msg/s |
| M4 E-core | 5 | 2.8 GHz | ~22K | ~632K msg/s |
| ARM A720 | 3 | 3.3 GHz | ~56K | ~177K msg/s |
| RISC-V U74 | 18 | 1.5 GHz | ~19K | ~1.4M msg/s |
| **CLI-CPU Rich** | **300** | **2.0 GHz** | **~45** | **~41M msg/s** |
| **CLI-CPU Nano** | **3,000** | **3.0 GHz** | **~12** | **~80M msg/s** |

```
Aggregate actor throughput -- log scale (same 12 mm2, TSMC 3nm):

                   10K      100K       1M        10M       100M
                    |         |         |          |          |
  x86 (1 core):    |||                                          34K
  M4 P (1 core):   ||||                                        62K
  ARM A720 (3):    ||||||                                      177K
  M4 E (5 core):   |||||||||                                   632K
  RISC-V (18):     |||||||||||.                                1.4M
  Rich (300):      ||||||||||||||||||||||||||||||.               41M
  Nano (3,000):    ||||||||||||||||||||||||||||||||.             80M
                    |         |         |          |          |
                   10K      100K       1M        10M       100M

  Log scale: each | ~ 2x multiplier. Nano ~2,350x above x86.
```

CLI-CPU delivers **~1,000-2,000x higher throughput** on the same silicon area for actor workloads.

### Power efficiency

| | Power/core (3nm) | Msg throughput/watt |
|---|---|---|
| x86 Zen 5 | ~10-15 W | ~3K msg/s/W |
| M4 P-core | ~5-8 W | ~8K msg/s/W |
| M4 E-core | ~0.5-1 W | ~130K msg/s/W |
| RISC-V U74 | ~0.1-0.3 W | ~500K msg/s/W |
| **CLI-CPU Rich** | **~0.01-0.05 W** | **~2-8M msg/s/W** |
| **CLI-CPU Nano** | **~0.001-0.005 W** | **~5-20M msg/s/W** |

Thanks to the sleep/wake model, an idle Nano core consumes **~0 W** -- on traditional CPUs, an idle core still consumes power (leakage, clock distribution).

### Single-thread: where CLI-CPU loses

| | Single-thread IPC x GHz (3nm) |
|---|---|
| x86 Zen 5 | 5.5 x 5.7 = **31.4 GIPS** |
| M4 P-core | 5.5 x 4.5 = **24.8 GIPS** |
| M4 E-core | 2.5 x 2.8 = **7.0 GIPS** |
| ARM A720 | 4.0 x 3.3 = **13.2 GIPS** |
| RISC-V U74 | 2.0 x 1.5 = **3.0 GIPS** |
| **CLI-CPU Rich** | 0.7 x 2.0 = **1.4 GIPS** |
| **CLI-CPU Nano** | 0.4 x 3.0 = **1.2 GIPS** |

In single-thread, CLI-CPU is **~20x slower** -- but this is not the arena it was designed for.

### Summary -- a fair comparison

| Metric | Traditional wins | CLI-CPU wins | Ratio |
|---|---|---|---|
| Single-thread speed | M4 P / x86 | -- | ~20x traditional advantage |
| Ctx switch (in cycles) | -- | Nano / Rich | **~1,000-20,000x** CLI-CPU |
| Throughput / mm2 (actor) | -- | Nano | **~1,000-2,000x** CLI-CPU |
| Throughput / watt (actor) | -- | Nano | **~1,000-4,000x** CLI-CPU |
| Scalability | Linear up to ~8-16 cores | 1,000+ cores linear | CLI-CPU does not degrade |
| Determinism | None (OoO, speculation) | Full (in-order) | CLI-CPU guaranteed |

**The bottom line:** what matters is not the clock frequency, but what you do with it. A 3 GHz Nano core needs **~12 cycles** for an actor switch, while a 5.7 GHz Zen 5 needs **~166,000 cycles** for the same. The clock frequency disadvantage (~2x) is dwarfed by the architectural advantage (~10,000x).

---

## Extending this FAQ

This document is **living**. Whenever a recurring conceptual question arises during the project (whether from an internal development discussion or from an external reader), it should be added here.

**Format for new entries:**

1. New H2 section with the next sequential number
2. First paragraph: **short answer** (1-3 sentences)
3. Then detailed reasoning, with tables and code snippets as needed
4. References to the relevant `docs/` files where deeper details reside
5. Update the table of contents at the top of the document

**What NOT to put in the FAQ:**

- Detailed specifications (see `ISA-CIL-T0-en.md`, `architecture-en.md`)
- Developer guides (see `CONTRIBUTING.md`)
- Build and installation instructions (see `README.md` or `BUILDING.md`)
- One-off, non-recurring questions (see GitHub Issues)

The FAQ provides **conceptual anchors**, not documentation duplication.

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
