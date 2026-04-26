# Cognitive Fabric Processing Unit (CFPU) — Architecture Overview

> Magyar verzió: [architecture-hu.md](architecture-hu.md)

> Version: 1.4

This document describes the **Cognitive Fabric Processing Unit (CFPU)** **microarchitecture** at a high level: the stack machine model, the pipeline, the memory map, the decoding strategy, hardware support for GC and exception handling, and the techniques adopted from predecessor projects (picoJava, Jazelle, Transmeta).

> *Throughout this document, "**CFPU**" refers to the chip-level architecture (microarchitecture, pipeline, memory map, security primitives, core types) — the *category*, sibling of CPU/GPU/TPU/NPU. "**CLI-CPU**" refers to the open-source *project* that implements it (roadmap phases F0–F7, simulator, linker, ISA spec, GitHub repo). When a sentence describes the silicon, prefer CFPU; when it describes a phase, build artefact, or test target, prefer CLI-CPU. See [brand-en.md](brand-en.md) for the full nomenclature; the short version is in [FAQ #1](faq-en.md#1-what-is-the-cfpu-and-how-does-it-relate-to-cli-cpu).*

> **Note:** This architecture is built incrementally across phases F0–F7. The full feature set described here will be completed in the **F6-Silicon "Cognitive Fabric One"** chip (ChipIgnite or IHP MPW, 6R+16N+1S, 15 mm²). **Tiny Tapeout (F3)** implements only the single-core CIL-T0 subset, described in a separate document (`ISA-CIL-T0.md`). The "Cognitive Fabric One" section records the concrete reference chip vision and comparison with conventional multi-core CPUs.

## Strategic positioning: Cognitive Fabric

The CFPU **does not position itself as a classical bytecode CPU**, like Sun picoJava or ARM Jazelle once did. That path **has already been tried and failed**: software JIT + conventional CPU turned out to be cheaper and faster than dedicated bytecode hardware. Repeating that same path **would not make sense**.

Instead, the CFPU is a **programmable cognitive substrate** — many small, independent CIL-native cores that form a heterogeneous, event-driven network through **message-based communication**. Each core runs a **complete CIL program** with its own local state; cores communicate through **mailbox FIFOs**, with no shared memory, no cache coherence protocol, and no lock contention. Usage depends on the program: a chip can be an **Akka.NET actor cluster**, a **programmable spiking neural network**, a **multi-agent simulation**, or an **event-driven IoT edge**.

### Why this is different from existing solutions

| System | Programmable? | Hardware? | Open? | .NET native? | Event-driven? | Stack-compact ISA? |
|--------|--------------|-----------|-------|-------------|--------------|-------------------|
| Intel Loihi 2 | No — fixed LIF | Yes | No | No | Yes | No |
| IBM TrueNorth | No — fixed LIF | Yes | No | No | Yes | No |
| BrainChip Akida | No — fixed model | Yes | No | No | Yes | No |
| GrAI Matter Labs GrAI-1 | No — fixed | Yes | No | No | Yes | No |
| SpiNNaker 2 (Manchester) | Yes — C/C++ ARM | Yes | Partial | No | No (polling) | No (ARM ISA) |
| Akka.NET / Orleans | Yes — full C#/F# | No — software | Yes | Yes | No (OS scheduler) | No (host CPU ISA) |
| Erlang BEAM | Yes — Erlang | No — software | Yes | No | No (BEAM scheduler) | No (host CPU ISA) |
| **CFPU (Cognitive Fabric)** | **Yes — full CIL** | **Yes** | **Yes** | **Yes** | **Yes** (hw mailbox wake) | **Yes** (CIL stack machine) |

The **neuromorphic competitors** (Loihi, TrueNorth, Akida, GrAI) all use **fixed neuron models** — you cannot run arbitrary algorithms on them, only configure weights and topology. **SpiNNaker** is the only one offering programmable nodes, but on **C/C++ ARM cores**, with significant engineering effort in an academic setting. **Software actor systems** (Akka.NET, Erlang) are flexible, but compete with scheduler, GC, and lock overhead on the host CPU.

**The CFPU occupies the only position** where **all six columns** are satisfied: programmable nodes + hardware + open + .NET native + event-driven + stack-compact ISA. This is not just "yet another bytecode CPU" — it is **a new category**.

### Neuromorphic-inspired, but not neuromorphic

The CFPU **adopts** the most valuable principles of neuromorphic architectures:

- **Many small independent units** with their own local state
- **Message-based communication** (not shared memory)
- **Event-driven working mode** (the core sleeps until a message arrives)
- **Ultra-low idle power consumption**
- **Linear scaling** with core count

But it is **not neuromorphic** in the strict sense, because:

- The nodes do not send **1-bit spikes** but rather **32-bit messages** (which provide sufficient precision for any digitized continuous value)
- The nodes can run **arbitrary CIL algorithms** — a LIF neuron, an Izhikevich neuron, a DSP filter, an Akka actor, a state machine, or anything else
- **Digital, deterministic** — not analog, not stochastic
- **Dynamically reprogrammable** at runtime — the core can load new CIL code

This means that the **same hardware chip**, depending on the chosen program, can become:

| Program | What the chip becomes |
|---------|-----------------------|
| C# + Akka.NET actors | Native hardware actor cluster |
| Leaky Integrate-and-Fire neurons | Spiking Neural Network simulator |
| Izhikevich model + STDP | More biologically plausible SNN research platform |
| Conway's Game of Life + complex rules | Cellular automata substrate |
| Dataflow pipeline (FIR, IIR, FFT) | DSP processing fabric |
| Multi-agent AI / game simulation | Swarm intelligence platform |
| Per-request web handler | Embedded web server |
| IoT edge sensor fusion | Event-driven IoT gateway |

**This "one hardware, many paradigms" approach** is what could give the project its historical significance — if it succeeds.

### Multi-language platform — the entire .NET ecosystem in hardware

The CFPU **does not run C# — it runs CIL**. The ECMA-335 Common Intermediate Language is the target format that **every .NET language** compiles to. This means the CFPU natively executes:

| Language | Paradigm | CFPU fit |
|----------|----------|------------|
| **C#** | OOP + functional | Akka.NET, largest community (~6M developers) |
| **F#** | Functional-first | **Natural fit** — immutable by default, pattern matching, algebraic types, actor-friendly |
| **VB.NET** | OOP | Porting legacy codebases |
| **IronPython** | Dynamic | Rapid prototyping, scripting on-chip |
| **PowerShell** | Shell/scripting | Device management, configuration |

**That is ~8 million developers' existing codebases** that can run natively on the CFPU — without compilation, interpreter, or runtime overhead.

#### Why this is different from Jazelle

ARM Jazelle (2001) and Sun picoJava (1997) **failed** because:
1. **Single-language** — they targeted only Java bytecode, a single ecosystem
2. **Single-core** — on a shared-memory CPU, software JIT became faster
3. **Not actor-native** — no hardware messaging, no mailbox

The CFPU is fundamentally different:
1. **Multi-language** — every .NET language compiles to CIL, the hardware executes CIL
2. **Multi-core, shared-nothing** — software JIT cannot run in parallel across 18 cores without cache coherency
3. **Actor-native** — the mailbox is in hardware, context switch takes 5-8 cycles (not 500-2000)

#### F# — the "perfect CFPU language"

F# is a particularly strong fit because the language paradigm is **identical** to the Cognitive Fabric architecture:

- **Immutable by default** — the shared-nothing model arises naturally
- **Pattern matching** — actor message dispatch is elegant and safe
- **Pipe operator (`|>`)** — actor pipeline chains are readable
- **Discriminated unions** — message types are checked at compile time
- **Computation expressions** — async actor workflows are natively expressible
- **No null** — fewer TTrapReason traps, safer code

```fsharp
// F# actor on a CFPU Nano core
[<RunsOn(CoreType.Nano)>]
let ledController = actor {
    let! msg = receive ()
    match msg with
    | SetLed (id, color) -> setGpio id color
    | BlinkLed (id, hz)  -> startBlink id hz
    | GetState            -> reply (currentState ())
}

// F# actor on a CFPU Rich core
[<RunsOn(CoreType.Rich)>]
let navSupervisor = actor {
    let! msg = receive ()
    match msg with
    | SubmitDocument doc ->
        let! signed = ask cryptoActor (Sign doc)
        let! result = ask navClient (Send signed)
        reply result
    | ChildFailed (child, _) ->
        restart child    // let it crash + supervision
}
```

#### Comparison: RISC-V vs CFPU on .NET workloads

On the same ~10 mm² Sky130 silicon:

| Metric | CFPU (10R+8N) | RISC-V 4-core + CIL interpreter | RISC-V 4-core + AOT |
|--------|------------------|--------------------------------|---------------------|
| **CIL execution** | Native (1x) | 10-50x slower (sw interpret) | ~1x but 10-50x larger binary |
| **Core count** (same die) | **18** | 4 | 4 |
| **.NET binary size** | ~1-2 MB (CIL compact) | +100KB interpreter | ~20-50 MB (AOT native) |
| **Actor msg/sec** | **~5M** (hw mailbox) | ~25-100K (sw queue + lock) | ~100-250K (sw queue) |
| **Context switch** | 5-8 cycles | 500-2000 cycles | 500-2000 cycles |
| **Cache coherency** | **0%** overhead | 10-20% overhead | 10-20% overhead |
| **GC** | Per-core, small heap | Global stop-the-world | Global stop-the-world |
| **.NET language compatibility** | **All** (C#, F#, VB.NET, ...) | Interpreter: limited | AOT: most, but large binary |

RISC-V has **two bad options** for .NET code: interpreter (10-50x slower) or AOT (10-50x larger binary, I-cache pressure). The CFPU **natively executes CIL** in compact form, with hardware actor support.

**The narrative:** The CFPU is **not "yet another CPU"** — it is **the first hardware platform that provides native silicon for an 8-million developer ecosystem**. Every C#, F#, VB.NET code that compiles to CIL runs natively on the Cognitive Fabric — without rewriting, interpreter, or JIT.

## Design principles

1. **CIL is the native ISA.** The CPU's fetch unit reads the CIL bytes emitted by Roslyn/ilasm directly. There is no JIT, no AOT, no interpreter layer. The CIL bytes in memory **remain unchanged**.
2. **Stack machine with Top-of-Stack Caching.** Externally a pure ECMA-335 evaluation stack; internally, the top 4-8 stack elements live in physical registers, the rest spills to RAM. This is the lesson from picoJava and HotSpot.
3. **Harvard model with external memory.** Separate code flash and separate PSRAM for data (F3–F5: QSPI, CF One: shared OPI bus). On-chip SRAM is used exclusively as cache.
4. **Hybrid decoding.** Simple opcodes (~75%) through direct hardware, 1 cycle. Complex opcodes (~25%) through microcode ROM, multiple cycles.
5. **Managed memory safety in silicon.** The GC write barrier, stack bounds check, branch target validation, type check — all are hardware side-effects, not software runtime tasks.
6. **Shared-nothing multi-core.** From phase F4 onward, multiple cores operate together on a single chip, **without shared memory**. Each core has its own local SRAM and communicates exclusively through **mailbox-based messages**. This automatically eliminates cache coherence, lock contention, and memory ordering problems.
7. **Event-driven, not clock-driven.** The core is in sleep mode by default and **only wakes** when a mailbox message arrives (or a timer fires). This results in ultra-low idle power consumption.
8. **Aggressive power-gating.** Every unused unit stays cold — FPU, GC coprocessor, metadata walker, mailbox router are all separate power domains.

## Multi-core block diagram (F4+ cognitive fabric)

In phase F4 of the CLI-CPU project, the CFPU becomes a **real network** for the first time. The 4 cores independently run their own CIL programs, each with its own local SRAM, and communicate exclusively through the mailbox interfaces. There is no shared heap, no cache coherence:

```
  ┌──────────────────────────────────────────────────────────────────────────┐
  │                    CFPU Cognitive Fabric (F4)                            │
  │                                                                          │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
  │  │  Core 0      │  │  Core 1      │  │  Core 2      │  │  Core 3      │  │
  │  │              │  │              │  │              │  │              │  │
  │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │  │
  │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │  │
  │  │              │  │              │  │              │  │              │  │
  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │  │
  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │
  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │
  │  │  │ private│  │  │  │ private│  │  │  │ private│  │  │  │ private│  │  │
  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │  │
  │  │              │  │              │  │              │  │              │  │
  │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │  │
  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │  │
  │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │  │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
  │         │                 │                 │                 │          │
  │  ═══════╧═════════════════╧═════════════════╧═════════════════╧═══════   │
  │                         Shared Bus (4-port arbiter)                      │
  │                                   │                                      │
  │              ┌────────────────────┼────────────────────┐                 │
  │              ▼                    ▼                    ▼                 │
  │    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
  │    │ QSPI Flash ctrl │  │   UART / GPIO   │  │  Timer / IRQ    │         │
  │    │   (code, R/O)   │  │  (I/O interf.)  │  │  (global clock) │         │
  │    └─────────────────┘  └─────────────────┘  └─────────────────┘         │
  └──────────────────────────────────────────────────────────────────────────┘
```

**Key observations:**

- **Every core is identical** to the F3 Tiny Tapeout single-core CIL-T0. The pipeline, decoder, microcode, stack cache — **unchanged**. Simply instantiated 4 times.
- **No shared data SRAM.** Each core has its own 16 KB SRAM containing its own eval stack, local variables, frames, and (from F5) its own object heap.
- **The shared bus is only for "slow" resources** — QSPI flash (code loading, infrequent), UART, timer. These are not on the critical path for the cores.
- **Inter-core communication** goes through mailbox FIFOs, **bypassing the shared bus** — the router is a direct connection between the 4 cores (at the F4 level, a 4-port cross-connection, not yet a full crossbar, just a simple mux bundle).
- **Sleep/Wake logic:** when a core's CIL program executes a `WAIT` microcode (or enters polling on an empty inbox), the core goes to sleep and only wakes when a mailbox message arrives. This is the **event-driven** operating mode of phase F4.

### Scaling to F6 (16-64 cores)

The F4 4-core design **scales linearly** up to 16 cores without bus congestion — most CIL programs work in private SRAM anyway, and the bus is only needed for infrequent events (flash fetch, I/O). **Above 16 cores**, the bus topology must be changed to a **mesh** (2D grid), where each core communicates with its neighbors and a local I/O channel. This is the physical structure of the F6 ChipIgnite tape-out.

## Heterogeneous multi-core: Nano + Rich

From phase F5 of the CLI-CPU project, the CFPU transitions to a **heterogeneous multi-core** architecture, unifying three proven industry concepts in a single chip:

- **ARM big.LITTLE (2011):** Two types of CPU cores on one chip — "big" (fast, power-hungry) and "LITTLE" (slow, efficient). The phone runs light tasks on LITTLE, heavy tasks on big. **In the CFPU: Rich = big, Nano = LITTLE.**
- **Apple Secure Enclave (2013):** A separate, isolated chip-within-a-chip in the iPhone, whose sole purpose is security operations (Face ID, fingerprint, payments). Even if the phone is compromised, keys stored in the Secure Enclave remain safe. **In the CFPU: Secure Core = Secure Enclave.**
- **Intel Alder Lake (2021):** P-core (Performance) + E-core (Efficiency) heterogeneous mix, with the OS scheduler assigning tasks. **In the CFPU: the Symphact supervisor distributes tasks between Rich and Nano cores.**

A single chip contains **three element types** — two computational, one security:

| | **Nano core** | **Rich core** |
|-|---------------|---------------|
| **ISA** | CIL-T0 subset (~48 opcodes, integer-only, static calls) | Full ECMA-335 CIL (~220 opcodes) |
| **Size** | ~10,000 std cells | ~80,000 std cells |
| **Features** | Integer ALU, stack cache, mailbox, microcode (mul/div/call/ret) | Nano + object model + GC + metadata walker + vtable cache + FPU (R4/R8) + 64-bit + exception handling + generics |
| **Clock** | ~50-200 MHz | ~50-150 MHz (slightly slower due to more pipeline stages) |
| **Typical role** | Worker / neuron / filter / simple actor / state machine | Supervisor / orchestrator / complex domain logic / error handler |
| **Per-core SRAM** | 16-64 KB | 64-256 KB (including heap) |
| **Transistor ratio** | ~8x more fit in the same area | ~8x fewer |

### Why this works — Apple big.LITTLE for CIL

Commercial heterogeneous multi-core CPUs (ARM big.LITTLE since 2011, Apple M1+ since 2020, Intel Alder Lake since 2021, AMD Zen 5c since 2024) are **all successful** because real workloads are **not homogeneous**. Most tasks are simple, few are complex. **Using a full Rich core for a LIF neuron would be wasteful, and a Nano core is not enough for an orchestrator.**

Workload distribution in a real application:

| Task type | Example | Core type |
|-----------|---------|-----------|
| Sensor interpretation | ADC sample -> threshold | **Nano** |
| Neuron simulation (LIF, Izhikevich) | `potential += weight; if (potential>th) fire()` | **Nano** |
| DSP filter (FIR, IIR) | Simple integer pipeline | **Nano** |
| Filter chain | Stream processor on a single core | **Nano** |
| Akka.NET worker actor | `Receive(msg) { state = f(state, msg); }` | **Nano** (if integer) |
| Akka.NET supervisor | Exception handling, child restart | **Rich** |
| Complex domain logic | `Order.Validate()`, `User.Authorize()` | **Rich** |
| Orchestrator / coordinator | Multi-actor coordination, transactional logic | **Rich** |
| Dynamic CIL loading | Runtime new code load | **Rich** |
| Error handler / logger | Exception -> log + alert | **Rich** |
| FP / scientific computing | NN forward pass in double precision | **Rich** |
| String / text processing | `ldstr`, `string.Concat` | **Rich** |

The **Nano** cores are the majority (that is where the real work happens), while the **Rich** cores supervise in small numbers.

### Design economy — why this does not increase the budget

This is the most important part: the heterogeneous model requires **no fundamentally new hardware design work**. Both core types **already appear in the roadmap**, just previously in separate phases:

```
F3 (Tiny Tapeout)  ─►  Nano core 1x  ───┐
                                        │
F4 (FPGA multi-core) ─►  Nano core 4x  ─┤
                                        │
F5 (FPGA Rich)     ─►  Rich core 1x  ───┤
                                        │
                                        ▼
F6-FPGA (3xA7-200T) ─►  Heterogeneous: Rich 2x + Nano ~26x distributed (multi-board)
F6-Silicon (MPW)    ─►  FPGA-verified design onto a single chip, optionally scaled up
```

The **additional design work for F6 is ~1-2 engineer-months**: floorplan optimization, Roslyn source generator `[RunsOn]` attribute support, and a few registers in the message router that handle Nano/Rich interoperability. **This is marginal** compared to what designing the Nano and Rich cores separately requires.

### Programming model — C# attributes

The .NET compiler level already supports such markers. On the CLI-CPU, a **Roslyn source generator** watches for the `[RunsOn]` attribute and compiles the method into the appropriate binary (`.t0` for Nano, `.tr` for Rich):

```csharp
[RunsOn(CoreType.Nano)]
public class LifNeuron : CoreProgram {
    int potential, threshold, lastTime;

    public void OnSpike(int weight) {
        potential += weight;
        if (potential >= threshold) {
            Fire();
            potential = 0;
        }
    }
}

[RunsOn(CoreType.Rich)]
public class NetworkSupervisor : Actor {
    Dictionary<int, NeuronRef> neurons = new();

    public void OnStartup() {
        try {
            LoadTopologyFromFlash();
            InitializeNeurons();
        } catch (Exception ex) {
            Log.Error(ex);
            Restart();
        }
    }
}
```

The compiler verifies that `[RunsOn(CoreType.Nano)]` code contains **only CIL-T0 opcodes** — if a Nano method tries to use `newobj`, the compilation produces a **compile-time error**. This is a stricter variant of the CIL ECMA-335 `verifiable code` concept.

### Suggested chip ratios by phase

| Phase | Platform | Nano cores | Rich cores | Aggregate capability |
|-------|----------|-----------|-----------|---------------------|
| F3 | Tiny Tapeout | **1** | 0 | Proof of life, first "network node" |
| F4 | FPGA multi-core | **4** | 0 | First shared-nothing fabric, pure Nano |
| F5 | FPGA heterogeneous | **4** | **1** | **First heterogeneous system**, Rich core test |
| F6-FPGA | 3x A7-Lite 200T multi-board (3x134K LUT, Ethernet mesh) | **8-10/board, ~26 total** | **2** | FPGA-verified distributed Cognitive Fabric |
| F6-Silicon Zero | IHP SG13G2 MPW (3 mm², EUR 0-EUR 4,500) | **8** | **1** | **"Cognitive Fabric Zero"** — first heterogeneous silicon |
| F6-Silicon One | ChipIgnite Sky130 (15 mm², ~$15K) | **23** | **2** | **"Cognitive Fabric One"** — full demonstration, benchmark |
| F7 | Product chip (future) | **64+** | **4-8** | Commercial Cognitive Fabric |

### State migration Nano <-> Rich

If a Nano core's program outgrows its own capabilities (e.g., complex exception, generic struct, floating-point needed), it can **request via message** that a Rich core take over its state. This is not "migration" in the classical sense (memory copy), but rather **an actor-serialized message** that naturally fits our shared-nothing model.

The Nano core's steps:
1. Interrupts the current task with a `STATE_OVERFLOW` trap
2. Current local variables and arguments are serialized in a JSON-like fashion (MessagePack ECMA-335-compatible)
3. A message goes to a designated Rich core with a "take over" request + serialized state
4. The Rich core continues the task natively with full CIL
5. If needed, sends the result back to the Nano core or another address

**This is a rare case** — the compiler type check catches most cases at build-time. Runtime migration is only for edge cases like dynamic reflection, which is not typical in cognitive fabric usage anyway.

### Secure Core — dedicated code verification trust anchor

Alongside Nano and Rich, the CFPU includes a **third, infrastructure-level core type**: the **Secure Core**. This is **not a compute core** (no user code runs on it) — it is the system's **trust anchor**, through which all code must pass before loading.

**Responsibilities:**
1. **SHA-256 hash** computation on the code to be loaded
2. **PQC digital signature verification** (Dilithium / XMSS) on the hash
3. **CIL opcode validation** (CIL-T0 compatibility check when loading to Nano core)
4. **Result:** PASS → code is loaded into operative memory; FAIL → rejection, trap

```
   QSPI Flash / Ethernet / UART
              │
              ▼
   ┌──────────────────────┐
   │    Secure Core       │  ← dedicated, single responsibility
   │                      │
   │  1. SHA-256 hash     │
   │  2. PQC signature    │
   │     verification     │
   │  3. CIL opcode       │
   │     validation       │
   │                      │
   │  ✅ PASS → load      │
   │  ❌ FAIL → reject    │
   └──────────┬───────────┘
              │ only after PASS
              ▼
   ┌──────────────────────┐
   │  Operative memory    │
   │  Nano / Rich cores   │
   │  can execute         │
   └──────────────────────┘
```

**Why a dedicated core instead of the Rich core?**

| | On Rich core | **Dedicated Secure Core** |
|--|-------------|------------------------|
| Responsibility | Everything: supervision + GC + crypto + logic | **Single**: code verification |
| Attack surface | Large (full CIL, complex) | **Minimal** (only hash + verify) |
| Formally verifiable | Difficult (too complex) | **Yes** (small, focused codebase) |
| Reliability | A Rich core bug → crypto may be compromised | **Isolated** — other core bugs cannot affect it |

**Estimated size:** ~20-30K std cells — larger than Nano (~10K), smaller than Rich (~80K).

**Per phase:**

| Phase | Secure Core |
|-------|------------|
| F3-F4 | None — host machine verifies at build-time |
| **F5** | Introduction — SHA-256 + simple signature verification |
| **F6** | PQC signature (Dilithium / XMSS) |
| **F6.5** | Full Crypto Actor (Secure Core + TRNG + PUF + tamper detection) |

**The "2 compute core types" rule remains:** Nano and Rich are the compute cores (big.LITTLE analogy). The Secure Core is an **infrastructure element** (like ARM CryptoCell or Apple Secure Enclave) — no user code runs on it, it exclusively ensures system integrity.

### Why not introduce additional core types?

A core type is defined by its **ISA** (which opcodes it can execute), not by cache or SRAM size — that is just configuration. In theory, there could be a "Micro" (even smaller ISA, only 16 opcodes), but this **complicates the programming model**: developers would need to target three different opcode sets. Commercial examples (Apple, ARM, Intel) **all** use exactly 2 compute core types, and this is the sweet spot. The CFPU also **stays at 2 compute cores** (Nano and Rich), complemented by the Secure Core infrastructure element.

## Cognitive Fabric One — the reference silicon target (F6-Silicon)

This section records the concrete vision for the CLI-CPU's **first true heterogeneous silicon chip**: what it contains, why we target this particular configuration, and why it is "compelling" — that is, why it demonstrates that the Cognitive Fabric paradigm is a **better alternative** to conventional multi-threaded CPUs **on the same silicon die**.

### Silicon platform: ChipIgnite OpenFrame

The chip is built on the eFabless **ChipIgnite OpenFrame** harness (~$14,950), which is an alternative to Caravel:

| | Caravel | **OpenFrame** |
|--|---------|-------------|
| User area | 10 mm² | **~15 mm²** (+50%) |
| User GPIO | 38 | **44** (all pins available) |
| Built-in SoC | RISC-V mgmt core, SPI, UART, DLL | **None** — only padframe + POR + ID ROM |
| Price | ~$14,950 | **~$14,950** (same) |

We choose OpenFrame because:
- **15 mm²** area fits the 6R+16N+1S configuration **comfortably** (~9.73 mm²), with ~5 mm² remaining for extra SRAM or future expansion
- **44 GPIO** — 6 more pins than Caravel's 38, giving more comfortable pin allocation
- **No unnecessary RISC-V management core** — the CFPU has its own Rich cores, no external CPU needed
- Same price ($14,950), more area and flexibility

### Chip specification

```
┌──────────────────────────────────────────────────────────────┐
│              CFPU "Cognitive Fabric One"                     │
│                    15 mm² Sky130 (OpenFrame)                 │
│                                                              │
│ ┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐ │
│ │Rich #0 ││Rich #1 ││Rich #2 ││Rich #3 ││Rich #4 ││Rich #5 │ │
│ │ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   │ │
│ │Kernel  ││Device  ││App Sup ││Domain  ││Crypto  ││Standby │ │
│ └───┬────┘└───┬────┘└───┬────┘└───┬────┘└───┬────┘└───┬────┘ │
│     │    Mesh Router (2D grid)    │         │         │      │
│     │         │         │         │         │         │      │
│ ┌───┴────┬────┴───┬─────┴───┬─────┴──┬──────┴──┬──────┘      │
│ │N0  4KB │N1  4KB │N2   4KB │N3  4KB │N4   4KB │             │
│ │N5  4KB │N6  4KB │N7   4KB │N8  4KB │N9   4KB │ ← 16 Nano   │
│ │N10 4KB │N11 4KB │N12  4KB │N13 4KB │N14  4KB │   worker    │
│ │N15 4KB │        │         │        │         │   cores     │
│ └────────┴────────┴─────────┴────────┴─────────┘             │
│ Each Nano: own 4 KB SRAM + Mailbox FIFO + Sleep/Wake         │
│                                                              │
│ ┌──────────────┐                                             │
│ │ Secure Core  │  ← trust anchor (SHA-256 + PQC verify)      │
│ └──────────────┘                                             │
│                                                              │
│ Shared OPI bus (8 data + CLK, 2-to-4 CS mux):                │
│ ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌─────────┐             │
│ │OPI Flash│ │OPI PSRAM │ │OPI FRAM │ │(reserve) │            │
│ │ code,RO │ │ data, RW │ │ persist │ │         │             │
│ └─────────┘ └──────────┘ └─────────┘ └─────────┘             │
│                                                              │
│ USB 1.1 FS ── Timer ── GPIO                                  │
└──────────────────────────────────────────────────────────────┘

Rich core roles:
  #0: Symphact kernel — root supervisor, scheduler
  #1: Device drivers — OPI, USB, GPIO (crash → restart)
  #2: Application supervisor — app lifecycle, hot code loading
  #3: Complex domain logic — orchestrator, string/FP
  #4: Crypto / PQC dedicated computation
  #5: Hot standby / redundancy
```

### Sky130 area estimation reference

The chip design decisions are based on the physical parameters of the Sky130 PDK (130nm, SkyWater):

| Parameter | Value | Source |
|-----------|-------|--------|
| **Std cell density** (sky130_fd_sc_hd) | ~160K gates/mm² (routed) | SkyWater PDK docs |
| **Raw gate density** (sky130_fd_sc_hd) | ~266K gates/mm² (unrouted) | SkyWater PDK docs |
| **SRAM density** (OpenRAM, single-port) | ~0.03 mm²/KB (~30 KB/mm²) | OpenRAM Sky130 reference |
| **SRAM 4 KB block** | ~0.12-0.15 mm² | OpenRAM Sky130 |
| **SRAM 16 KB block** | ~0.45-0.55 mm² | OpenRAM Sky130 |
| **SRAM 64 KB block** | ~1.7-2.0 mm² | OpenRAM Sky130 |
| **Nano core logic** (~9,100 std cells) | ~0.028-0.031 mm² | ISA-CIL-T0.md estimate |
| **Rich core logic** (~80,000 std cells) | ~0.25 mm² | architecture.md estimate |
| **Routing overhead** | ~25-35% | General Sky130 experience |

**Key insight:** **SRAM is the area-dominant element**, not logic. Therefore, the trade-off between core count and SRAM size is the most important design decision.

### Chip area breakdown

| Element | Count | Per-core SRAM | Area (Sky130) |
|---------|-------|-------------|--------------|
| Rich core + mailbox | 6 | 16 KB | 6 × 0.75 mm² = 4.5 mm² |
| Nano core + mailbox | 16 | 4 KB | 16 × 0.18 mm² = 2.88 mm² |
| Secure Core | 1 | — | ~0.18 mm² |
| Mesh router (2D grid) | 1 | — | 0.02 mm² |
| Peripherals (OPI ctrl, USB, timer, GPIO) | — | — | 0.2 mm² |
| Routing overhead (~25%) | — | — | 1.95 mm² |
| **Total** | **23 cores + 1 Secure** | **160 KB** | **~9.73 mm²** |
| **Remaining** | | | **~5.27 mm²** (reserve for extra SRAM, routing/timing closure, or future expansion) |

### External memory interface

The 160 KB on-chip SRAM is sufficient for per-core local cache, but program code and larger data structures come from **external memory**. Sky130 I/O cells are capable of ~50-100 MHz SDR — this determines the interface choice:

| Interface | Latency @50MHz | Bandwidth | Pins | Sky130 compatible? |
|-----------|---------------|-----------|------|-------------------|
| ~~QSPI~~ | 14-20 cycles | 25 MB/s | 6 | Yes, but slow |
| **OPI (Octal SPI)** | **6-10 cycles** | **50 MB/s** | **11** | **Yes (SDR)** |
| ~~HyperRAM~~ | 6-13 cycles | 200 MB/s | 12 | No (DDR signaling required) |
| ~~DDR3~~ | 5-15 cycles | 1-2 GB/s | ~40+ | No (I/O too fast) |

**OPI (Octal SPI)** is the best fit for Sky130's ~50 MHz I/O: **half the latency** and **double the bandwidth** compared to QSPI, but **does not require DDR signaling**. The controller is simple (QSPI extended to 8 data lines), with minimal area cost (~0.08 mm²).

The OPI Flash, OPI PSRAM, and OPI FRAM connect to a **shared bus** with **multiplexed chip select** (2 pins → 2-to-4 on-chip decoder → 4 devices):

```
                   Shared OPI bus (8 data + CLK)
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
     ┌────┴────┐              │                   │
     │ 2-to-4  │              │                   │
     │ decoder │              │                   │
     │(on-chip)│              │                   │
     └─┬──┬──┬──┬─┘           │                   │
      CS0 CS1 CS2 CS3         │                   │
       │   │   │   │          │                   │
   ┌───┘   │   │   └───┐     │                   │
   ▼       ▼   ▼       ▼     │                   │
┌──────┐┌──────┐┌──────┐┌──────┐                  │
│ OPI  ││ OPI  ││ OPI  ││(future)                  │
│Flash ││PSRAM ││FRAM  ││      │                  │
│code, ││data, ││persi-││      │                  │
│RO    ││RW    ││stent ││      │                  │
└──────┘└──────┘└──────┘└──────┘
```

The multiplexed CS handles **4 devices** with only 2 pins (1 reserved for future expansion). Bus contention is minimized by a **prefetch buffer** (64 bytes of sequential code pre-fetch) — code fetch is sequential and predictable, so the bus is mostly free for data accesses.

**Three-tier persistent storage:**

| Tier | Memory | Persistent? | Write latency | Endurance | Typical content |
|------|--------|------------|-------------|-----------|----------------|
| **1. FRAM** | OPI FRAM (256 KB – 4 MB) | **Yes** | **6-10 cycles** (same as read) | **10^12+ cycles** | Actor state, journal, keys, configuration |
| **2. Flash partition** | OPI Flash free area | **Yes** | ~1-100 ms (erase+program) | ~100K cycles | Firmware backup, offline data, log archive |
| **3. Host storage** | Via USB | **Yes** | ~ms (network-dependent) | Unlimited | Database, backup, synchronization |

### Host communication: USB 1.1 FS

Instead of UART, **USB 1.1 Full Speed** (12 Mbps) — feasible on Sky130 @50 MHz:

| | UART | **USB 1.1 FS** |
|--|------|---------------|
| Bandwidth | 115.2 Kbps | **12 Mbps** (~100×) |
| Pin count | 2 (TX, RX) | **2** (D+, D−) |
| Sky130 compatible | Yes | **Yes** (FS PHY is simple) |
| Controller area | ~0.01 mm² | ~0.1-0.2 mm² |
| Host side | USB-UART adapter needed | **Native USB** — any PC/tablet |
| Power | External needed | **5V on cable** (optional) |
| Usage | Mailbox bridge, debug, firmware upload, host storage | Same, but **100× faster** |

**Pin allocation** (ChipIgnite OpenFrame, 44 GPIO):

| Interface | Pin count |
|-----------|----------|
| Shared OPI bus (8 data + CLK) | 9 |
| CS multiplex (2-to-4 decoder) | 2 |
| USB 1.1 FS (D+, D−) | 2 |
| Mailbox bridge (inter-chip) | 4 |
| GPIO / debug | 27 |
| **Total** | **44** |

### Core counts are configurable

**6R+16N+1S** is the reference configuration, but the RTL is **parameterizable** (`#NUM_RICH`, `#NUM_NANO`). The same design can be instantiated with different ratios depending on the target market:

| Configuration | Rich | Nano | Secure | Total | Target market |
|--------------|------|------|--------|-------|--------------|
| 2R + 34N + 1S | 2 | 34 | 1 | 37 | SNN research, IoT sensor farm |
| 4R + 26N + 1S | 4 | 26 | 1 | 31 | Symphact + worker mix |
| **6R + 16N + 1S** | **6** | **16** | **1** | **23** | **Reference — app + demo balance** |
| 8R + 9N + 1S | 8 | 9 | 1 | 18 | General .NET application (JokerQ-style) |

The configuration is chosen **before synthesis** (not at runtime). The FPGA configuration sweep (F6-FPGA) systematically tests different ratios.

### Why 6R+16N+1S as the reference

**SRAM is the area-dominant element, not logic.** The logic for all 6 Rich + 16 Nano + 1 Secure cores totals ~2.06 mm² (6x0.25 + 16x0.031 + 0.06) — only ~14% of the 15 mm² chip. The remaining ~79% is SRAM and routing. This means:
- Cores are **cheap** (a Nano core's logic is ~0.031 mm²)
- Memory is **expensive** (16 KB SRAM is ~0.5 mm²)
- The **sweet spot** is 4 KB/Nano + 16 KB/Rich — enough to keep the TOS cache, local variables, and frames on-chip, with large data coming from OPI PSRAM (shared OPI bus)

Usage of the remaining ~5.3 mm² (F6-Silicon decision):
- **Writable microcode SRAM** — firmware-updatable opcode semantics
- **Gated store buffer** (GC write barrier batch)
- **Reserve** for routing and timing closure

### Why it is "compelling" — comparison with conventional multi-core CPU

The same 10 mm² Sky130 area. RISC-V **requires cache coherency** when using shared memory (Linux, .NET runtime):

**RISC-V configurations on 10 mm² (Sky130):**

| RISC-V config | Core area | Coherency | L2 + peripherals | Routing | Total | Remaining → extra RAM | Total RAM |
|--------------|-----------|-----------|-----------------|---------|-------|---------------------|-----------|
| **4 core** | 1.80 mm² | 0.75 mm² | 1.40 mm² | 0.99 mm² | 4.94 mm² | 5.06 mm² → ~150 KB | **~214 KB** |
| **6 core** | 2.70 mm² | 1.10 mm² | 1.40 mm² | 1.30 mm² | 6.50 mm² | 3.50 mm² → ~105 KB | **~169 KB** |
| **8 core** | 3.60 mm² | 1.50 mm² | 1.40 mm² | 1.63 mm² | 8.13 mm² | 1.87 mm² → ~56 KB | **~152 KB** |
| **12 core** | 5.40 mm² | 2.50 mm² | 1.40 mm² | 2.33 mm² | 11.63 mm² | **Does not fit!** | — |

(One RV32IMC core ~0.15 mm² logic + 4KB L1 I-cache + 4KB L1 D-cache = ~0.45 mm²/core. Cache coherency grows superlinearly with core count.)

**Comparison with the CFPU Cognitive Fabric One:**

| | **CFPU 6R+16N+1S** | **RISC-V 4 core** | **RISC-V 8 core** |
|--|----------------------|------------------|------------------|
| **Cores** | **23** (6 Rich + 16 Nano + 1 Secure) | **4** | **8** |
| **On-chip RAM** | **160 KB** (private, no coherence) | **~214 KB** (L1+L2+extra) | **~152 KB** (L1+L2+extra) |
| **Cache coherency area** | **0 mm²** | **0.75 mm²** (7.5% of chip) | **1.5 mm²** (15% of chip) |
| **Area spent on cores** | 7.3 mm² (73%) | 1.8 mm² (18%) | 3.6 mm² (36%) |
| **.NET execution** | **Native CIL** | Interpreter (10-50× slower) or AOT (20-50MB binary) | Same |
| **Parallel actors** | **23** (hw mailbox) | 4 (sw queue + lock) | 8 (sw queue + lock) |
| **Context switch** | **5-8 cycles** | 500-2000 cycles | 500-2000 cycles |

**The key number:** RISC-V **spends 10-20% of the chip area on cache coherency**. On the CFPU, all that area **goes to extra cores**, because the shared-nothing architecture means the coherence problem **does not exist**. This is why 23 cores fit on 15 mm², while RISC-V stops at 4-8 on 10 mm². RAM quantities are similar (~150 KB), but the CFPU's is **private** (no coherency traffic), while RISC-V's is **shared** (coherency slows it down).

### Performance comparison on actor-based workloads

| Metric | CFPU (6R+16N @50MHz) | RISC-V 4-core (@50MHz, same die) | CFPU advantage |
|--------|------------------------|----------------------------------|-------------------|
| **Actor msg/sec** | ~44M (22 cores × ~2M/core, hardware mailbox) | ~2M (software queue + lock + context switch) | **~22×** |
| **Message latency** | ~10-20 cycles (hardware FIFO) | ~500-2000 cycles (lock acquire + context switch) | **~50-100×** |
| **Context switch** | ~5-8 cycles (TOS cache + PC) | ~500-2000 cycles (register save/restore + TLB flush) | **~100×** |
| **Parallel neurons (SNN)** | 16 (1/Nano core, deterministic) | 4 (threaded, non-deterministic) | **4×** |
| **Scaling per +1 core** | Linear | Sub-linear (Amdahl + coherency overhead) | **Fundamental** |
| **Energy (event-driven)** | ~nJ/event (sleeping cores, wake-on-mailbox) | ~μJ/event (active polling, cache traffic) | **~100-1000×** |
| **Determinism** | Guaranteed (no OoO, no preemption) | Not guaranteed (cache timing, preemption) | **Absolute** |
| **Isolation** | Hardware (private SRAM, Secure Core) | Software (MMU, but Spectre/Meltdown) | **Stronger** |

**Important:** in single-core IPC, RISC-V (especially OoO variants) is faster. The CFPU **does not win in the single-core race**, but rather in the fact that **on the same silicon it performs far more useful parallel work** on actor-based workloads, while remaining deterministic and secure.

### Symphact layers on-chip

| Layer | Where it runs | Function |
|-------|--------------|----------|
| **Symphact kernel** | Rich core #0 | Root supervisor, scheduler, capability registry, hot code loader |
| **Device driver actors** | Rich core #1 | UART, QSPI, GPIO, timer — crash -> supervisor restart, not kernel panic |
| **Application supervisor** | Rich core #0 or #1 | App lifecycle, actor spawn/kill, supervision strategies |
| **Worker actors** (16) | Nano cores | SNN neurons, IoT handlers, filter pipeline, state machines, anything |
| **GUI actors** (future) | Rich + Nano mix | Framebuffer actor (Rich), widget actors (Nano) — everything is an actor, no "UI thread" |

The GUI is also actor-based: every widget is an actor, every input event is a message, rendering is a pipeline actor chain. There is no global state, no race condition. If a widget crashes, the supervisor restarts it — the other widgets are unaffected.

### Reference demos on-chip

| Demo | Core usage | What it proves |
|------|-----------|---------------|
| **Actor ping-pong throughput** | 16 Nano pairs | Msg/sec benchmark — comparable to RISC-V |
| **SNN (Spiking Neural Network)** | 16 Nano (LIF/Izhikevich neurons) + 1 Rich coordinator | Linear scaling, determinism, event-driven energy |
| **IoT edge gateway** | 6 Rich (supervisor + protocol) + 16 Nano (handlers) | Real use-case, latency measurement, fault tolerance demo |
| **Akka.NET actor cluster** | 6 Rich (supervisor) + 16 Nano (workers) | Actor system compiled from C# code, running in hardware |
| **Hot code loading** | Actor update on Rich core | Zero-downtime update, Erlang-style |
| **Fault tolerance** | Worker crash -> supervisor restart | "Let it crash" — the chip does not halt, only the actor restarts |

### Publication narrative

The chip's purpose is not "yet another CPU" but rather **proof of a new category**:

> *"The Cognitive Fabric One is the world's first open-source, heterogeneous, actor-native processor. With its 23 cores (6 Rich + 16 Nano + 1 Secure), without cache coherency, on 15 mm² Sky130 silicon it handles 22x more actor messages per second than a conventional 4-core RISC-V — while remaining deterministic, hardware-isolated, and linearly scalable. This is not a faster CPU — this is a new paradigm."*

## Block diagram (single-core CFPU, F6 single-core target)

```
                         ┌─────────────────────────────────────────┐
                         │               CFPU                      │
                         │                                         │
  ┌──────────────┐       │  ┌────────────────────────────────────┐ │
  │ QSPI Flash   │◄──────┼─►│         I$  (CIL bytecode cache)   │ │
  │ (code)       │       │  │         4 KB, 2-way associative    │ │
  └──────────────┘       │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Prefetch Buffer (16 bytes)        │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Length Decoder                    │ │
                         │  │  (1st byte → full opcode length)   │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  uop Cache (256 x 8 uop)           │ │
                         │  │  PC-based lookup                   │ │
                         │  └──────┬─────────────────┬───────────┘ │
                         │         │ hit             │ miss        │
                         │         │                 ▼             │
                         │         │  ┌──────────────────────┐     │
                         │         │  │  Hardwired Decoder   │──┐  │
                         │         │  │  (trivial opcodes)   │  │  │
                         │         │  └──────────────────────┘  │  │
                         │         │  ┌──────────────────────┐  │  │
                         │         │  │  Microcode ROM/SRAM  │──┤  │
                         │         │  │  (complex opcodes)   │  │  │
                         │         │  └──────────────────────┘  │  │
                         │         │                            ▼  │
                         │         │  ┌──────────────────────────┐ │
                         │         │  │  uop Sequencer           │ │
                         │         │  │  (fill → uop cache)      │ │
                         │         │  └───────────┬──────────────┘ │
                         │         │              │                │
                         │         └──────┬───────┘                │
                         │                │                        │
                         │                ▼                        │
                         │  ┌────────────────────────────────┐     │
                         │  │        Execute Stage           │     │
                         │  │  ┌──────┐ ┌──────┐ ┌────────┐  │     │
                         │  │  │ ALU  │ │ FPU  │ │ Branch │  │     │
                         │  │  │32/64 │ │R4/R8 │ │  Unit  │  │     │
                         │  │  └──────┘ └──────┘ └────────┘  │     │
                         │  │  ┌───────────────────────────┐ │     │
                         │  │  │   Stack Cache (TOS..TOS-7)│ │     │
                         │  │  └───────────────────────────┘ │     │
                         │  │  ┌───────────────────────────┐ │     │
                         │  │  │   Shadow RegFile (exc)    │ │     │
                         │  │  └───────────────────────────┘ │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────┐     │
                         │  │   Load/Store Unit              │     │
                         │  │   + Gated Store Buffer         │     │
                         │  │   + GC Write Barrier           │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────┐     │
                         │  │ D$ (heap + locals + eval-stack)│     │
                         │  │ 4 KB, with card table bits     │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
  ┌──────────────┐       │                 ▼                       │
  │ QSPI PSRAM   │◄──────┼───────── Memory Controller              │
  │ (heap+stack) │       │                                         │
  └──────────────┘       │                                         │
                         │  ┌────────────────────────────────┐     │
                         │  │   Metadata Walker Coproc.      │     │
                         │  │   (PE/COFF table resolution)   │     │
                         │  └────────────────────────────────┘     │
                         │  ┌────────────────────────────────┐     │
                         │  │   GC Assist Unit               │     │
                         │  │   (bump alloc, card mark)      │     │
                         │  └────────────────────────────────┘     │
                         │  ┌────────────────────────────────┐     │
                         │  │   Exception Unwinder           │     │
                         │  │   (shadow regfile rollback)    │     │
                         │  └────────────────────────────────┘     │
                         └─────────────────────────────────────────┘
```

## Pipeline

The CFPU uses a **classic 5-stage in-order pipeline**, adapted for stack machine semantics:

```
 IF  → FETCH:     Bytes from prefetch buffer, I$ with QSPI backing
 ID  → DECODE:    Length decoder + hardwired/microcode branching
 EX  → EXECUTE:   ALU/FPU/Branch, operates on stack cache
 MEM → MEMORY:    Load/store, gated buffer, GC barrier
 WB  → WRITEBACK: Stack cache update, PC update
```

There is no superscalar, no out-of-order execution (F0-F6). This is a deliberate decision for two reasons:

1. **Area:** On Sky130, an OoO core would require a higher area budget than what we can afford even on ChipIgnite. The in-order pipeline is compact.
2. **Determinism:** Both IoT and security profiles require deterministic execution time. OoO and speculation open Spectre-class side channels, which we want to avoid on a "security-first" CIL CPU.

The **uop cache**, however, significantly reduces decoding overhead on hot loops, so the effective IPC stays at ~1, but at low energy.

### Pipeline hazard management

A stack machine pipeline has a unique hazard profile compared to a register machine. On a RISC CPU, data hazards arise only when two instructions reference the **same register** — a situation the compiler can often avoid by choosing different registers. On a stack machine, **every instruction** reads from and writes to the top of the stack, so RAW (Read After Write) hazards are the default, not the exception.

The CFPU addresses this with three mechanisms:

#### 1. TOS cache as register file

The 8×32-bit TOS cache is **not a memory cache** — it is a register file. The stack pointer (`SP_CACHE`, range 0–7) determines which physical register is TOS, TOS-1, etc. When an ALU operation writes its result to TOS-1, it writes to a **physical register** — exactly like a RISC ALU writing to `rd`.

This converts the stack machine's implicit data dependencies into **register-file dependencies**, which are solved by standard forwarding (bypass) logic.

#### 2. EX→EX forwarding (bypass path)

The pipeline implements a single-cycle forwarding path from the EX stage output back to the EX stage input:

```
 Cycle N:   add   (EX stage: TOS-1 ← TOS-1 + TOS, result in bypass latch)
 Cycle N+1: mul   (EX stage: reads TOS-1 from bypass latch, not from WB)
```

Because the TOS cache uses physical register indices, the hazard detection logic is identical to a RISC pipeline's:

```
 if (EX_WB.dst == ID_EX.src1 || EX_WB.dst == ID_EX.src2)
     → forward EX_WB.result instead of register file read
```

**Stall cases** (1-cycle bubble):
- **MEM→EX dependency** — when a memory-read instruction (`ldind.i4`, `ldelem.i4`, `ldarg` from spilled frame) is immediately followed by an instruction that consumes the loaded value. The data is not available until the end of the MEM stage, so the EX stage must wait 1 cycle.
- **TOS cache spill/fill** — when the stack depth crosses the 8-element boundary and a spill (write to SRAM) or fill (read from SRAM) is needed. This costs 1 cycle per spilled/filled slot (hardware manages this transparently).

All other ALU→ALU sequences execute at **1 instruction per cycle** with no stalls.

#### 3. Microcode vs. picoJava stack folding

Sun picoJava (1997) introduced **stack folding**: the decoder combines multiple CIL-like stack operations (e.g., `load; load; add; store`) into a single ALU operation in the decode stage. ARM Jazelle (2000) used a similar approach.

The CFPU achieves **the same effective result** through its microcode system, but with a different mechanism:

| Aspect | picoJava stack folding | CFPU microcode |
|--------|----------------------|----------------|
| **Where** | Decode stage | Microcode ROM → uop issue |
| **How** | Pattern matcher recognizes foldable groups | Each CIL opcode maps to 1+ uops with explicit register operands |
| **Example** | `ldloc.0; ldloc.1; add` → 1 ALU op | `add` = 1 uop (`OP=TOS_ADD, DST=TOS-1, SRC1=TOS-1, SRC2=TOS`) — operands already in TOS cache |
| **Complexity** | High — N-wide pattern matcher, folding groups | Low — fixed uop mapping, no runtime pattern matching |
| **Area cost** | ~15-20% of decode logic | ~5% (microcode ROM is shared with complex opcodes) |

The key difference: picoJava stack folding compensates for the lack of a TOS cache register file — it must fold because otherwise every operation would hit memory. The CFPU **already has** the operands in registers (TOS cache), so the folding benefit is captured by the register file + forwarding, without a complex pattern matcher in the decoder.

#### 4. Determinism guarantee

All stall events are **deterministic and data-independent**:
- Forwarding latency: 0 cycles (bypass)
- MEM→EX stall: exactly 1 cycle
- TOS spill/fill: exactly 1 cycle per slot
- Branch taken: exactly 1 cycle flush

There is no speculation, no variable-latency prediction. This preserves the CFPU's **timing-channel resistance** — the execution time of a code sequence is a function of the instruction sequence alone, not of the data values.

#### 5. Why this is sufficient for the CFPU

On a conventional single-core CPU, IPC is the primary performance metric. On the CFPU, performance scales through **core count**, not single-core IPC:

- **Nano core tight loops** (FIR filter, neuron simulation): the TOS cache + forwarding delivers ~1 IPC, with occasional 1-cycle MEM stalls. This is comparable to picoJava's folded throughput, at a fraction of the area.
- **Actor message processing**: the dominant latency is the mailbox read (~10-20 cycles), not the ALU pipeline. A 1-cycle stall on a MEM→EX hazard is negligible.
- **Rich core complex logic**: the same mechanism applies; the Rich core's extra pipeline stages (FPU, GC) do not change the hazard model for integer operations.

The CFPU trades single-core IPC heroics for **area-efficient many-core scaling** — the area saved by not implementing a picoJava-style pattern matcher pays for additional cores.

## Memory model

### Address space

The CFPU uses a 32-bit virtual address space, logically divided into four regions:

| Region | Address range | Contents | Backing |
|--------|--------------|----------|---------|
| **CODE** | `0x0000_0000` - `0x3FFF_FFFF` | CIL bytecode + PE/COFF metadata tables | QSPI Flash, read-only |
| **HEAP** | `0x4000_0000` - `0x7FFF_FFFF` | Managed object heap (GC) | QSPI PSRAM, read/write |
| **STACK** | `0x8000_0000` - `0x8FFF_FFFF` | Evaluation stack spill + local variables + arguments + frames | QSPI PSRAM |
| **MMIO** | `0xF000_0000` - `0xFFFF_FFFF` | Peripherals: UART, GPIO, timer, IRQ controller | On-chip |

### GC card table

The HEAP region has an associated **card table**: for every 512 bytes of heap data, 1 bit indicates whether a reference write has occurred in that region. The write barrier updates this in hardware. In phase F4+, the GC microcode uses this to decide which cards need to be traversed.

### Stack structure

The stack on the CFPU is **three-tiered**:

1. **Top-of-Stack Cache (TOS cache)** — 8 x 32-bit registers on-chip. The top 8 stack elements live here. Every ALU operation works on these, **without touching RAM**.
2. **L1 D-cache** — 4 KB on-chip SRAM, spilled stack frames, local variables, heap hot lines.
3. **QSPI PSRAM** — full stack backing, ~8 MB.

Spilling to and from the TOS cache is handled automatically by hardware. To the programmer (and the compiler), a **simple, unlimited-depth stack** is visible.

### Frame layout

On the CFPU, CIL **is the machine code** — there is no JIT, no interpreter, no intermediate compilation. What Roslyn generates (method header + opcodes) is **directly executed by the hardware**. Therefore, the frame structure is not freely determined by the hardware designer, but **fixed by the Roslyn output**:

- The **method header** (`arg_count`, `local_count`, `max_stack`) determines the frame size
- The **opcodes** (`ldarg.N`, `ldloc.N`, `stloc.N`) index the slots
- The hardware's job: **compute the physical SRAM addresses** from the header

This differs from conventional .NET, where the JIT can freely decide (put a local in a register, rearrange the frame, inline). On the CFPU, there is no such freedom.

### Hardware frame layout

The `call` microcode computes the frame size from the method header and advances the SP. The simulator (`TCpu.cs`) and the hardware (F2+ RTL) use an **identical SRAM layout** — the simulator's `byte[] FSram` array matches the hardware STACK SRAM byte-for-byte.

**Frame header: 12 bytes**

```
 Offset  Size   Field
 +0       4      ReturnPC       (int32 LE, -1 = root frame)
 +4       4      PrevFrameBase  (int32 LE, -1 = root frame)
 +8       1      ArgCount       (byte, 0..16)
 +9       1      LocalCount     (byte, 0..16)
 +10      2      reserved       (alignment)
```

**Full frame layout in SRAM:**

```
 Stack SRAM (16 KB Nano / 64-256 KB Rich):

 ┌──────────────────────────────────────────────────────────┐
 │                                                          │
 │  Frame 0 (root):  Add(a, b) — 2 args, 0 locals           │
 │  ┌────────────────────────────────────────────────────┐  │
 │  │ [FP₀+0]   ReturnPC = -1 (root)          │  4 bytes │  │
 │  │ [FP₀+4]   PrevFrameBase = -1 (root)     │  4 bytes │  │
 │  │ [FP₀+8]   ArgCount=2, LocalCount=0      │  4 bytes │  │
 │  │ ─ ─ ─ ─ end of header (12 bytes)  ─ ─ ─ │          │  │
 │  │ [FP₀+12]  arg[0] = 2                    │  4 bytes │  │
 │  │ [FP₀+16]  arg[1] = 3                    │  4 bytes │  │
 │  │ ─ ─ ─ ─ end of args ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₀+20]  eval[0] (a+b result)          │  4 bytes │  │
 │  └────────────────────────────────────────────────────┘  │
 │  Frame size: 12 + 2x4 + 0x4 = 20 bytes (+ eval stack)    │
 │                                                          │
 │  Frame 1 (callee):  Gcd(a, b) — 2 args, 1 local          │
 │  ┌────────────────────────────────────────────────────┐  │
 │  │ [FP₁+0]   ReturnPC = (opcode after call)│  4 bytes │  │
 │  │ [FP₁+4]   PrevFrameBase = FP₀           │  4 bytes │  │
 │  │ [FP₁+8]   ArgCount=2, LocalCount=1      │  4 bytes │  │
 │  │ ─ ─ ─ ─ end of header (12 bytes)  ─ ─ ─ │          │  │
 │  │ [FP₁+12]  arg[0] = 48                   │  4 bytes │  │
 │  │ [FP₁+16]  arg[1] = 18                   │  4 bytes │  │
 │  │ ─ ─ ─ ─ end of args ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₁+20]  local[0] = 0                  │  4 bytes │  │
 │  │ ─ ─ ─ ─ end of locals ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₁+24]  eval[0]                       │          │  │
 │  │ [FP₁+28]  eval[1]                       │          │  │
 │  │ [FP₁+32]  eval[2]                       │          │  │
 │  └────────────────────────────────────────────────────┘  │
 │  Frame size: 12 + 2x4 + 1x4 = 24 bytes (+ eval stack)    │
 │                                                          │
 │  [free SRAM]                                             │
 │                                                          │
 └──────────────────────────────────────────────────────────┘
 SP ──► grows upward, points to the next free byte
```

**Address computation** (the `call` microcode sets the `frame_base` and `arg_count` registers):

```
 ldarg.N   →  SRAM[frame_base + 12 + N×4]
 starg.N   →  SRAM[frame_base + 12 + N×4]
 ldloc.N   →  SRAM[frame_base + 12 + arg_count×4 + N×4]
 stloc.N   →  SRAM[frame_base + 12 + arg_count×4 + N×4]
 eval push →  SRAM[SP] = val; SP += 4
 eval pop  →  SP -= 4; val = SRAM[SP]
```

### Capacity

```
 Fibonacci(20) recursive: 21 frames × ~16 bytes = ~336 bytes
 Gcd iterative:           1 frame × ~28 bytes  = ~28 bytes
 Worst case (16 args, 16 locals, 64 eval): 12 + 16×4 + 16×4 + 64×4 = 396 bytes

 In 16 KB Nano SRAM:
   - Typical frame (~20 bytes): ~800 frame depth ← more than enough
   - Worst case frame (396 bytes): ~41 frame depth ← tight, but rare
```

### Simulator = hardware model

After the SRAM refactor, the simulator (`TCpu.cs`) maintains **identical internal state** to the hardware:

| Element | Simulator | Hardware (F2+ RTL) |
|---------|-----------|-------------------|
| SRAM | `byte[] FSram` (16 KB) | Per-core SRAM (16 KB) |
| SP | `int FSp` | SP register |
| Frame base | `int FFrameBase` | FP register |
| `ldarg.1` | `SramReadInt32(FFrameBase + 12 + 1×4)` | `SRAM[FP + 12 + 1×4]` |
| Frame size | Computed from header (variable) | Computed from header (variable) |
| Allocation | `FSp += frameSize` | `SP += frameSize` |
| Debug | `SramSnapshot()` → byte[] | cocotb: SRAM dump |

The F2 RTL cocotb tests can compare the simulator's `SramSnapshot()` output with the Verilog SRAM contents **byte-for-byte**.

**The `call` microcode sequence:**
1. Read header from the target RVA (arg_count, local_count, code_size validation)
2. CallDepthExceeded check (max 512)
3. Frame size computation: `12 + arg_count×4 + local_count×4`
4. SramOverflow check: `SP + frame_size > SRAM_SIZE`
5. Pop arguments from the caller eval stack (in reverse order)
6. Write frame header: ReturnPC, PrevFrameBase, ArgCount, LocalCount
7. Write args to SRAM
8. Zero-initialize locals
9. Update SP, FrameBase, ArgCount, LocalCount registers
10. Set PC to the first byte of the callee body (after header)

**The `ret` microcode sequence:**
1. Pop return value from the callee eval stack (if any)
2. Root frame check (CallDepth == 1 -> Halt)
3. Read PrevFrameBase, ReturnPC from SRAM
4. Reset SP to frame_base (the callee's SRAM is freed)
5. Restore FrameBase, ArgCount, LocalCount from the caller frame
6. Push return value onto the caller eval stack
7. Reset PC to the saved ReturnPC
3. Restore `frame_base` and `arg_count` to the caller's values
4. Push return value onto the **caller** eval stack
5. Reset PC to the saved return PC

## Decoding strategy

For details see `ISA-CIL-T0.md`, but the core strategy is:

### Length decoder

CIL variable-length instructions are **unambiguously deterministic based on the first byte** (except for the `switch` opcode, which derives its length from the 2nd byte). A 256-entry ROM contains the first-byte -> length table:

```
0x00 (nop)      → 1 byte
0x02 (ldarg.0)  → 1 byte
0x06 (ldloc.0)  → 1 byte
...
0x1F (ldc.i4.s) → 2 bytes
0x20 (ldc.i4)   → 5 bytes
...
0x2B (br.s)     → 2 bytes
0x38 (br)       → 5 bytes
...
0xFE (prefix)   → 2 + (ROM2 lookup)
...
```

For prefixed opcodes (0xFE) there is also a second 256-entry ROM.

### Hardwired vs microcoded classification

~75% hardwired, ~25% microcoded. The hardwired group includes the following opcode families:

- Trivial stack: `nop`, `dup`, `pop`
- Constants: `ldc.i4.*`, `ldc.i8`, `ldc.r4`, `ldc.r8`
- Locals / arguments: `ldloc.*`, `stloc.*`, `ldarg.*`, `starg.*`
- Simple ALU: `add`, `sub`, `and`, `or`, `xor`, `neg`, `not`, `shl`, `shr`, `shr.un`
- Comparison: `ceq`, `cgt*`, `clt*`
- Short branches: `br.s`, `brtrue.s`, `brfalse.s`, `beq.s`, etc.
- Simple memory: `ldind.*`, `stind.*`

The microcoded group:

- `mul`, `div`, `rem` (iterative implementation)
- 64-bit integer arithmetic
- FP arithmetic (FPU sequencer)
- `call`, `callvirt`, `ret`
- `newobj`, `newarr`, `box`, `unbox`
- `isinst`, `castclass`
- `ldfld`, `stfld`, `ldelem.*`, `stelem.*`
- `ldtoken`, `ldftn`, `ldvirtftn`
- `throw`, `rethrow`, `leave`, `endfinally`
- `switch`

## uops

The CFPU's internal micro-instruction format (to be finalized in F2, preliminary draft):

```
 Field    | Size  | Description
──────────┼───────┼─────────────────────────────────────────
 OP       | 6 bit | microcode opcode (e.g., TOS_ADD, LOAD, BRANCH)
 DST      | 4 bit | destination: TOS, TOS-1, ..., LOCAL[i], ARG[i]
 SRC1     | 4 bit | source 1
 SRC2     | 4 bit | source 2
 FLAGS    | 6 bit | uses_sp, writes_flags, last_of_op, trap_enable, ...
 IMM      | 8 bit | optional immediate (from the CIL bytes)
──────────┼───────┼─────────────────────────────────────────
           32 bit
```

A CIL `add` = 1 uop (`OP=TOS_ADD, DST=TOS-1, SRC1=TOS-1, SRC2=TOS, FLAGS=pop1 | last`).

A CIL `callvirt` = ~8-10 uops (see `ISA-CIL-T0.md` for a detailed trace).

## Exception handling

**Shadow Register File + Checkpoint** (Transmeta-inspired):

- On `try` entry, the microcode emits a `SAVE_CHECKPOINT` uop that copies the entire TOS cache contents, SP, BP, and PC to a shadow register file **in a single cycle**.
- On normal `try` exit (`leave`), the checkpoint can be discarded (`DROP_CHECKPOINT` uop).
- On `throw`, the microcode traverses the method's exception table (from PE/COFF metadata), finds the appropriate `catch`/`filter` handler, and if found:
  - `RESTORE_CHECKPOINT` uop restores the TOS cache
  - The thrown object reference is placed on TOS
  - PC jumps to the handler's first opcode
- If there is no handler in the method, the microcode emits a `ret` toward the caller and repeats the search.

This is **dramatically faster** than conventional unwind-table stepping, because the microcode uses the hardware shadow file rather than having to unwind the stack sequentially.

## GC (Garbage Collection)

**Generational bump-allocator + stop-the-world mark-sweep** is the simplest implementation, introduced in F4.

### Allocation

The `newobj` / `newarr` / `box` microcode:

```
 TOS_SIZE  ← object_size (from the type or array length)
 NEW_ADDR  ← HEAP_TOP
 HEAP_TOP ← HEAP_TOP + TOS_SIZE
 if HEAP_TOP > HEAP_LIMIT → TRAP #GC
 store type_ptr at NEW_ADDR
 TOS ← NEW_ADDR
```

~5-8 cycles if no GC trap. On GC trap, the microcode invokes the GC subroutine (which also runs in microcode or on a small "housekeeping" coprocessor).

### Write barrier

The `stfld` microcode (when the field is a reference type):

```
 STORE    TOS, [TOS-1 + field_offset]
 CARD     ← (TOS-1 + field_offset) >> 9    ; card index
 CARD_TBL[CARD] ← 1                        ; card mark
```

A single extra cycle compared to a plain `stfld`. **Essentially free in hardware** relative to managed memory safety.

### Gated Store Buffer

In the F4+ microarchitecture, the write barrier card table updates accumulate in a **small store buffer** and are only written back to the D-cache at commit points (method exit, `volatile.` prefix). This Transmeta-inspired optimization reduces the amortized cost of the write barrier to **~0.3 cycles**.

## Metadata Walker

CIL metadata tokens (e.g., `MethodDef 0x06000042`) point into PE/COFF metadata tables. On the CFPU, resolving these is the job of the **Metadata Walker coprocessor** (from F4):

1. The CIL opcode pushes the token into a small FIFO
2. The Walker begins traversing PE/COFF tables (Method table, Type table, Field table, etc.)
3. The result is a **direct pointer** to the object's type descriptor / method entry point / field offset
4. The Walker uses a **small TLB** to accelerate frequently-used tokens

**Important:** this does NOT modify the CIL bytes in memory. The walker is merely an "address resolution service"; the code continues to run unchanged.

## Prior art and adopted techniques

The CFPU is not the first bytecode-native CPU, and it is worth learning from each predecessor.

### Sun picoJava (1997, 1999)

**What it did well:** Natural stack machine for Java bytecode. Top-of-Stack Caching for the top ~4 elements. Hardware array bounds check. Simple, elegant microarchitecture.

**Why it failed:** Plain ARM + HotSpot JIT was faster, and as semiconductor scaling continued over decades, the general-purpose CPU + software runtime caught up with the dedicated hardware to an unexpected degree. Sun could not price it competitively.

**What we adopt:**
- **Top-of-Stack Caching** — fundamental, adopted. 4-8 elements.
- **Hardware array bounds check** — fits the security-first profile.
- **Elegant simplicity** — we do not attempt OoO or superscalar.

### ARM Jazelle (2001)

**What it did well:** A **Java bytecode execution mode** within an ARM core (not a separate CPU). The ARM decoder switches to Java bytecode with a bit toggle, and directly executes the most important ~140 opcodes in hardware. Complex opcodes trap to a software handler.

**Why it is interesting:** This **hybrid** model — we do not want to implement every opcode in hardware; for rare / complex opcodes we can trap to microcode or a small coprocessor.

**What we adopt:**
- **Trapping rare opcodes** to the metadata walker and GC coprocessor, rather than full microcode ROM implementation.
- **Mode switch** — in the F4+ version, there may be a "CIL-T0 compatibility mode" and a "full CIL mode".

### Transmeta Crusoe / Efficeon (2000, 2003)

**What it did well:** Internal VLIW core, **software** x86 -> VLIW translation (Code Morphing Software), trace cache, shadow register file + checkpoint rollback, gated store buffer, writable microcode, aggressive power-gating.

**Why it failed:** Software DBT (Dynamic Binary Translation) warmup was slow, the arrival of Intel Pentium M (Dothan) eliminated the power USP, and the software complexity was an enormous risk.

**What we adopt (and what we do NOT):**

| Technique | Adopt? | Where |
|-----------|--------|-------|
| Code Morphing Software (DBT) | **NO** | Contradicts the "CIL = native ISA" principle |
| Internal VLIW core | **NO** | Stack machine is more natural for CIL |
| uop cache / trace cache | **YES** | F4+, energy savings on hot loops |
| Shadow register file + checkpoint | **YES** | F5 exception handling |
| Gated store buffer | **YES** | F4 GC write barrier batch |
| Writable microcode SRAM | **YES** | F6 ChipIgnite, firmware-updatable opcodes |
| Aggressive power-gating | **YES** | From F0 throughout, IoT profile |

### RISC-V

**Not a predecessor**, but a reference architecture. RISC-V is a purely register-based RISC, the exact **opposite** of the stack machine CFPU. However:

- **OpenLane2 / Sky130 / Caravel tooling** — we learn this from the RISC-V community
- **Open source spirit** — all RTL, documentation, tests will be public
- **Custom extension pattern** — design methodology inspiration (but no RISC-V core in the CFPU — all cores run CIL or CIL-derived ISA)

## Power management

The CFPU is divided into **four power domains** (F6 target):

1. **Core domain** — fetch, decode, execute, stack cache. Always active while the CPU is working.
2. **FPU domain** — only powered on when an FP opcode is detected. Cold during integer loops.
3. **GC / metadata domain** — the walker coprocessor and GC assist. Active only on allocation or metadata miss.
4. **I/O domain** — QSPI controllers, UART, GPIO. Scales down during WFI (wait-for-interrupt).

Clock-gating in every domain, power-gating in domains 2, 3, and 4.

## Actor Scheduling Pipeline

When a core runs multiple actors, it needs a **zero-stall context switch** mechanism. The key insight: the on-chip SRAM is a **cache**, not the actor's permanent home — code, stack, and data live in external PSRAM (OPI bus), and only the "hot context" resides in SRAM at any moment. The actor scheduling pipeline orchestrates prefetch, execution, and eviction so that the core never stalls waiting for an actor's state.

### Hot Context — what must be in SRAM

Not the entire actor state needs to be in SRAM for execution — only the **minimum working set**:

| Component | Size | Required for execution? |
|-----------|------|------------------------|
| TOS cache (4–8 registers) | 16–32 B | Always (hardware registers) |
| PC, SP, frame pointer, actor ID | ~16 B | Always |
| Active frame (locals + args) | ~64–256 B | Active frame only |
| Mailbox (incoming cell) | 128 B | The trigger that starts execution |
| Previous stack frames | 0 – 16 KB | No — stays in PSRAM (cache-fetched on demand) |
| DATA/heap | 0 – 256 KB | No — on-demand cache |

**Minimal hot context per actor:** ~200–512 B. This is what the DMA engine must transfer for a zero-stall context switch.

### DMA Double-Buffer Strategy

The core maintains **two SRAM regions** for actor contexts: an **active buffer** (currently executing actor) and a **shadow buffer** (next actor being prefetched). The DMA engine fills the shadow buffer in the background while the active actor runs:

```
Time →
         ┌─────────────┐
Actor A:  │██ EXECUTING█│── evict ──→ PSRAM (encrypted)
         └─────────────┘
         ┌── prefetch ──┐─────────────┐
Actor B:  │  PSRAM→SRAM  │██ EXECUTING█│── evict ──→
         └──────────────┘─────────────┘
                        ┌── prefetch ──┐─────────────┐
Actor C:                │  PSRAM→SRAM  │██ EXECUTING█│
                        └──────────────┘─────────────┘
```

**Condition for zero-stall switching:** `T_swap ≤ T_exec` — the prefetch must complete before the active actor yields or blocks.

### Message Arrival = Prefetch Trigger

The network provides the **earliest possible signal** that an actor will need to run: the arrival of a message in its mailbox. The mailbox interrupt triggers the DMA prefetch **immediately**, not at context-switch time:

```
1. Cell arrives for Actor B → mailbox interrupt
2. Core HW: DMA start → Actor B hot context: PSRAM → decrypt → SRAM shadow buffer
3. Actor A continues executing (uninterrupted)
4. Actor A blocks / yields → instant switch to B (already in SRAM)
5. Background: Actor A context → encrypt → PSRAM (evict)
```

**Prefetch window:** network latency (29–229 cycles) + DMA transfer (~1,250 cycles for 512 B @ OPI 50 MB/s) = ~1,300–1,500 cycles (slightly higher with 144-byte cells). If Actor A's execution time exceeds this, the switch is zero-stall.

### Timing Budget

Three times must be balanced:

| Parameter | Symbol | Typical values |
|-----------|--------|---------------|
| Actor execution time (until block/yield) | T_exec | ~500–10,000 cycles |
| Hot context DMA transfer (PSRAM ↔ SRAM) | T_swap | ~1,250–5,000 cycles (depends on context size) |
| Network message delivery | T_net | 29–229 cycles ([interconnect](interconnect-en.md)) |

**OPI PSRAM transfer rates** (shared OPI bus @ 50 MB/s):

| Context size | Transfer time | Core cycles @ 500 MHz |
|-------------|---------------|----------------------|
| 256 B | ~5 µs | ~2,500 |
| 512 B | ~10 µs | ~5,000 |
| 2 KB | ~40 µs | ~20,000 |

**Design rule:** if actors are expected to process messages quickly (T_exec < T_swap), the scheduler should keep more actors' contexts resident in SRAM simultaneously (fewer actors, larger SRAM partitions). If actors are compute-heavy (T_exec >> T_swap), more actors can time-share the SRAM through prefetch.

### Code Sharing

When N actors of the **same type** run on a core (e.g., N identical LIF neurons), the CODE region is loaded **once** into SRAM and shared read-only. Only per-actor state (stack + data + mailbox) is swapped. This drastically reduces the hot context size:

| Scenario | Per-actor swap size | Max actors on 64 KB Actor Core |
|----------|--------------------|---------------------------------|
| Unique code per actor | ~2–4 KB (code + state + stack) | ~16–32 |
| Shared code (N identical actors) | ~200–500 B (state + stack + mailbox only) | **~128–320** |

Code sharing is the common case in cognitive fabric workloads (SNN neurons, IoT handlers, worker actors).

### QRAM External Extension — Secure Off-Chip Storage

The [Quench-RAM](quench-ram-en.md) security guarantees must **extend to external PSRAM**. When an actor's context is evicted from on-chip SRAM to external PSRAM, it must remain **confidential** and **tamper-proof** — no other core, no external probe, and no bus snooper may read or modify it.

```
SRAM (on-chip, QRAM-protected)
  │
  │ evict (actor swap-out)
  ▼
┌─────────────────────────────────┐
│ AES-128-CTR encrypt + CMAC tag  │ ← per-core hardware key
└─────────────────────────────────┘
  │
  ▼
PSRAM (external, encrypted + authenticated)
  │
  │ load (actor swap-in / prefetch)
  ▼
┌─────────────────────────────────┐
│ verify CMAC + AES-128-CTR decrypt│ ← MAC mismatch → TRAP
└─────────────────────────────────┘
  │
  ▼
SRAM (on-chip, QRAM-protected)
```

**Security guarantees:**

| Property | Mechanism | Guarantee |
|----------|-----------|-----------|
| **Confidentiality** | AES-128-CTR encryption | External PSRAM contents are ciphertext — physical probing yields nothing |
| **Integrity** | CMAC authentication tag | Any modification (bit flip, bus fault, attack) is detected → `QRAM_INTEGRITY_TRAP` |
| **Isolation** | Per-core key (derived from core ID + PUF) | Core A cannot decrypt Core B's evicted state |
| **Replay protection** | Monotonic counter per eviction | Replaying an old ciphertext is detected |

**Hardware cost:** AES-128 + CMAC engine per core ≈ 15,000–25,000 GE (~0.004–0.006 mm²). For Actor Core (0.036 mm²) this is ~11–17% overhead; for Rich Core (0.083 mm²) it is ~5–7%. For Nano Core (0.014 mm²), the crypto engine would dominate (~30–40%) — Nano cores with limited SRAM (4 KB) may opt out if multi-actor is not required.

**Relationship with on-chip QRAM:** the on-chip QRAM SEAL/RELEASE invariants remain unchanged. The external extension adds a **transport encryption layer** — data is SEAL-ed in QRAM, encrypted for PSRAM transit, and re-SEAL-ed upon return. The two mechanisms are complementary:

- **QRAM** protects against software-level tampering (capability tags, immutability)
- **QRAM External Extension** protects against physical-level tampering (bus probing, PSRAM modification)

### Actor Address — Software Dispatch

The [interconnect](interconnect-en.md) 24-bit hardware address routes cells to a **core**, not to an individual actor:

```
HW address: [region:4-6].[tile:3-4].[cluster:3-4].[core:4] = 18 bits (of 24)
Actor ID:   payload first 1–2 bytes (software dispatch on the destination core)
```

**Rationale:**
- The maximum actor count per core varies by core type, SRAM size, and workload — a fixed HW bit field would be either too narrow (4-bit = 16 actors) or wasteful
- The core already has a single mailbox interrupt (see [Power Domains](#power-management)) — the network delivers to the core, not to an actor
- The on-core dispatcher is trivial: read actor ID from the cell payload, lookup in a local table → route to the actor's context. Cost: ~1–5 cycles, negligible vs. 27–215 cycle network transit
- The 6 remaining bits (24 − 18) are reserved for future addressing extensions (more regions, larger clusters)

### Phase Availability

| Component | Phase | Notes |
|-----------|-------|-------|
| Single-actor per core (no scheduling needed) | **F3–F4** | Current model |
| Multi-actor scheduling + DMA prefetch | **F5+** | DMA engine required |
| QRAM External Extension (encrypt/MAC) | **F5+** | Per-core AES+CMAC engine |
| Code sharing (identical actor types) | **F5+** | Symphact scheduler feature |
| Actor migration between cores | **F6+** | Cross-core state transfer via Seal Core |

## Silicon-grade security

This section discusses the CFPU's security architecture **from an architectural perspective**. The full security model, threat model, attack immunity table, formal verification plan, and certification paths are in a separate document: see [`docs/security-en.md`](security-en.md).

### The CFPU security principle

> **Memory safety, type safety, and control flow integrity are not software abstractions but physical properties in silicon.**

This statement is not marketing but an **architectural design consequence**. The current microarchitecture does not add security **as an extra layer**, but rather it **implicitly follows** from the design principles:

1. **Stack machine model** -> no ROP gadgets, because the return address is not on the user stack but in the hardware frame pointer structure
2. **Unchanged code in memory** -> no JIT, no AOT patching, therefore no JIT spraying, no self-modifying code
3. **Shared-nothing multi-core** -> no cross-core side-channel, no false sharing covert channel, no cache coherency-based attack
4. **In-order pipeline, no speculation** -> immune to the entire Spectre/Meltdown family
5. **Harvard memory model** -> the CODE region is on QSPI flash, physically R/O — shellcode cannot be injected
6. **CIL verified code semantics** -> type safety and memory safety are built into the ISA level

### Hardware checks — the current ISA already includes these

| Check | Where | Trap | Phase |
|-------|-------|------|-------|
| Stack overflow/underflow | Every push/pop | `STACK_OVERFLOW` / `STACK_UNDERFLOW` | **F3** |
| Local/argument index bounds | `ldloc`, `stloc`, `ldarg`, `starg` | `INVALID_LOCAL` / `INVALID_ARG` | **F3** |
| Branch target validation | `br*` | `INVALID_BRANCH_TARGET` | **F3** |
| Call target validation | `call` | `INVALID_CALL_TARGET` | **F3** |
| Division by zero | `div`, `rem` | `DIV_BY_ZERO` | **F3** |
| Call depth limit | `call` | `CALL_DEPTH_EXCEEDED` | **F3** |
| Invalid opcode | Decoder | `INVALID_OPCODE` | **F3** |
| Array bounds check | `ldelem`, `stelem` | `ARRAY_INDEX_OUT_OF_RANGE` | F5 |
| Null reference check | `ldfld`, `stfld`, `callvirt` | `NULL_REFERENCE` | F5 |
| Type check (isinst/castclass) | `isinst`, `castclass` | `INVALID_CAST` | F5 |
| GC write barrier | Reference-type `stfld`/`stelem.ref` | — (side-effect) | F5 |

**Important note:** on the F3 Tiny Tapeout chip, **most of the basic security checks are already live in silicon**. This means the CLI-CPU project's first real silicon **already has security properties that no standard CPU possesses**.

### Attack classes the CFPU is immune to

Brief summary (the detailed table is in [`docs/security-en.md`](security-en.md)):

| Attack family | Status |
|--------------|--------|
| Buffer overflow (CWE-119, 120, 121, 122) | **Excluded** (hardware bounds check) |
| Use-after-free (CWE-416) | **Excluded** from F5 (GC in hardware) |
| Type confusion (CWE-843) | **Excluded** from F5 (hardware type check) |
| Format string (CWE-134) | **Excluded** (no C strings) |
| ROP / JOP | **Excluded** (hardware CFI) |
| Shellcode injection (CWE-94) | **Excluded** (CODE R/O) |
| JIT spraying | **Excluded** (no JIT) |
| Spectre v1/v2/v4, Meltdown, L1TF, MDS | **Excluded** (no speculation) |
| Cross-core side-channel | **Excluded** (shared-nothing) |
| False sharing covert channel | **Excluded** (no shared cache) |
| GC race condition | **Excluded** (per-core private heap) |
| Lock deadlock | **Excluded** (no shared locks) |

### Formal verification feasibility

The CFPU **Nano core's** 48-opcode ISA is **practically smaller than the seL4 microkernel** (~10,000 lines of C), which the UNSW team **formally proved** using Coq + Isabelle tools over 15+ years of work.

This means that **formal verification of the CFPU is feasible** — not simple, not cheap, but **not impossible either**, and **not achievable for x86, ARM, or RISC-V with their full extension sets**.

For formal verification details, see the **"Formal verification"** section of [`docs/security-en.md`](security-en.md).

### Related projects

- **CHERI** (Cambridge) — closest relative, capability-based security in hardware; could be a potential academic partner
- **seL4** — formally verified microkernel, a precedent to learn from
- **CompCert** — formally verified C compiler; a similar long-term goal for the `cli-cpu-link` tool
- **Project Everest** (Microsoft Research) — formally verified HTTPS/TLS stack in F*, potential for Microsoft support

## Dual-track positioning

The CFPU's security profile opens a **second market track** alongside the **Cognitive Fabric** (programmable cognitive substrate) narrative:

- **Track 1 — "Cognitive Fabric"** — for AI researchers, actor systems, neural network simulation, multi-agent systems. Long-term vision.
- **Track 2 — "Trustworthy Silicon"** — for regulated industries: automotive (ISO 26262), aviation (DO-178C), medical (IEC 62304), critical infrastructure (IEC 61508 SIL-3/4), AI safety watchdog chips, confidential computing. Short-to-medium-term revenue opportunity with high margins.

**Same hardware, two different market segments.** Details and specific target markets in the **"What this means for the project's practical goals"** section of [`docs/security-en.md`](security-en.md).

## Next step

The `ISA-CIL-T0.md` document provides the complete opcode specification for the CIL-T0 subset, including encoding tables, stack effects, cycle counts, and trap conditions. **This is the foundation of the F1 C# simulator** — every test there must directly reference a specific point in the ISA-CIL-T0 spec, and the property-based tests already lay the groundwork for future formal verification.

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.4 | 2026-04-25 | Strategic-positioning, microarchitecture, Cognitive Fabric One comparison, block diagram, pipeline, address-space, frame layout, dispatch, metadata walker, related projects, power domains, and security sections renamed CLI-CPU → CFPU per [brand-en.md](brand-en.md). CLI-CPU is retained for project-level references (roadmap phases F4/F5, Roslyn toolchain, "first real silicon" milestone, callout). |
| 1.3 | 2026-04-19 | Actor Scheduling Pipeline section — hot context, DMA double-buffer, message-triggered prefetch, QRAM External Extension (AES+CMAC for off-chip PSRAM), code sharing, software actor dispatch, timing budget |
| 1.2 | 2026-04-19 | Pipeline hazard management section — TOS cache bypass, forwarding, microcode vs. picoJava stack folding, stall catalogue, determinism guarantee |
| 1.1 | 2026-04-16 | Core types, interconnect, Cognitive Fabric One |
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
