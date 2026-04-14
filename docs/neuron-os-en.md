# Neuron OS -- the actor-based operating system of CLI-CPU

> **Vision document.** This is the long-term plan for the OS, which begins to take shape with the F4 multi-core simulator, reaches its first real usability with F5-F6 hardware, and reaches mature developer platform level in F7.
>
> **The content is a compass, not a final spec.** Details will be refined along the way, based on F4-F6 experience. The goal here is to give design decisions a **direction**, so we don't re-debate fundamentals at every F4 iteration.

> Magyar verzió: [neuron-os-hu.md](neuron-os-hu.md)

> Version: 1.0

## Philosophy -- replacing the Unix legacy, realizing the Erlang vision

The purpose of **Neuron OS** is to build an operating system where **every entity is an actor**, and communication happens **exclusively through message passing**. But this is not just an alternative approach alongside Linux -- it is **a new paradigm that, in the long run, replaces the inherited 1970s decisions carried by current operating systems**.

### The Linux and Unix legacy -- why it is an outdated foundation

Linux was **born in 1991**, and Unix in **1970**. The kernel design decisions were made in an **era** when:

- There was **one CPU** in the server, single-core
- **Little memory** was available (on the order of kilobytes)
- **Expensive hardware** forced minimalism
- **Networking did not exist** in the modern sense
- There was **no comprehensive security threat landscape** (no internet, no AI, no supply chain attacks)
- A **single user per machine** model dominated
- **Shared memory was cheap**, message passing was expensive
- **The kind of parallelism we see today** (1000+ cores, NUMA, distributed) did not exist

The **fork/exec/fd/signal/shared memory + mutex/POSIX permissions** model was designed for these conditions. **This decades-old design** carries within it **most of the vulnerabilities and limitations** of today's CPU architectures:

- **Monolithic kernel** -- 40 million lines of C, 500+ CVEs per year, a single driver bug leads to a full system crash
- **Shared memory + mutex** -- race conditions, deadlocks, Spectre/Meltdown cache attacks
- **fork/exec** -- heavy context, expensive system call
- **POSIX permission model** -- 1970s thinking, everything is a global namespace
- **Kernel / user mode switch** -- expensive, every system call incurs ~1000+ cycles of overhead
- **Signal handlers** -- not reentrant, encoding race conditions into the semantics
- **Filesystem as universal abstraction** -- everything is a byte stream, which does not fit many modern data structures
- **Shared library loading** -- DLL hell, ABI bugs, supply chain attacks
- **systemd + cgroups + namespaces + containers** -- layered complexity stacked on top, because the foundation is not enough

**These problems cannot be fixed with patches.** They are architectural, and as hardware changes (more cores, more memory, faster networks, more serious security threats, AI-generated code), they become **increasingly painful**. Linux engineers are constantly battling them (copy-on-write, RCU, lockless algorithms, eBPF, seccomp, io_uring), but **the fundamental paradigm cannot be changed**, because backward compatibility requirements bind it.

### Neuron OS as a clean slate

Neuron OS is designed in a **modern era**, for modern conditions:

- **Many cores** (10k+ will be the norm) -- not with shared memory, but with shared-nothing
- **AI-era threats** -- hardware memory safety, capability-based security
- **Distributed systems by default** -- location transparency between local and remote
- **High expectations for fault tolerance** -- let it crash + supervision proven for 40+ years in Erlang
- **Immutable data and functional paradigm** -- not shared mutation, but message passing
- **Type safety by default** -- not an optional add-on, but a hardware guarantee
- **Hot code loading** -- zero downtime, not reboot-patch cycles

This is not "yet another OS" -- it is **a new paradigm** built on what **Erlang/OTP has proven for 40 years** (fault tolerance, actor model, supervision), **what seL4 formally verifies** (capability security, microkernel), **what CHERI enforces in hardware** (capability enforcement), **what Singularity (Microsoft Research) demonstrated** (type-safe OS), and **what QNX has commercially demonstrated** (deterministic message passing). **All of this integrated into a single system, with hardware support** -- something that has never existed before.

### Why now, and why this moment

Until now, actor-based operating systems have remained in a **marginal niche** because the software implementation was slower than traditional shared-memory OSes. Joe Armstrong (the father of Erlang) spoke precisely about this in his 2014 talk "The Mess We're In": **there is a need for hardware whose architecture is natively actor-oriented**. Back then it did not exist -- open-source chip design, Tiny Tapeout, eFabless Caravel all appeared after 2020.

**Now it does.** The CLI-CPU cognitive fabric architecture is the first **hardware foundation** where the actor model is **not software overhead, but the basis of the architecture**:

- Every core is **physically isolated** with its own SRAM -- there is no shared memory trick
- Inter-core messaging runs on **hardware mailbox FIFOs**, not software queues
- Context switch takes **~5-8 cycles** (just the TOS cache and the PC), not 500-2000
- The supervisor trap arrives on a **hardware interrupt line** to another core, not signal-based
- The capability model is **enforced in hardware**, not by software checks

In this architecture, **the actor model's biggest disadvantage (performance overhead) vanishes**, and what remains is all of its advantages -- **far stronger than what Linux could ever provide** under the burden of backward compatibility.

Neuron OS therefore does **not sit alongside Linux**, but is **the successor to Linux**. Just as x86 replaced the mainframe, mobile replaced the desktop, and cloud replaced the physical server -- **Cognitive Fabric + Neuron OS replaces the shared-memory + Linux combination** in the now-emerging AI-driven, safety-critical, massively distributed era.

## Design principles

### 1. Everything is an actor

No exceptions. The kernel itself is a hierarchy of actors. Device drivers are actors. The filesystem is actors. Every application is an actor. If something has state and processes messages, it is an **actor**.

This **drastically simplifies** the system: a developer needs to understand a single fundamental abstraction, and **the same tool** applies to kernel programming, application development, and distributed systems.

### 2. No shared memory, ever

Between cores, there is **no and will never be** shared memory. Every actor lives in its own private SRAM, and data can only reach from one actor to another **through messages**. This is not a performance limitation but an **architectural safety guarantee**.

Messages are **immutable value types** (CIL `struct`s or immutable classes) that the runtime copies (or forwards zero-copy within the same core). **No aliasing**, no data race.

### 3. Let it crash -- structured fault tolerance

No single actor **defends** against every possible error. When a fault occurs, the actor **dies**, and the **supervisor** decides what happens: restart, escalate, or shut down. This is the Erlang OTP model, proven for 40+ years in telecommunications, financial, and critical infrastructure environments.

In Neuron OS this applies **at every level**, from the smallest device driver to the topmost application actor.

### 4. Supervision hierarchy

Every actor has a **supervisor**. The supervisor is another actor (the very first actor has a primary "root supervisor" created by the boot loader). The supervisor-child relationship forms a **tree**:

```
            root_supervisor
                 │
       ┌─────────┼─────────┐
       │         │         │
   device_sup   app_sup   net_sup
     │            │         │
   ┌─┴─┐       ┌──┴──┐   ┌──┴──┐
 uart gpio   neural worker tcp  ble
```

A fault **propagates only to the bottom of its own supervisor subtree** and stops there. If a leaf actor fails, only that one is restarted. If an interior node fails, the entire substructure restarts. If the `root_supervisor` fails, the system reboots -- but this is rare, because it is very simple.

### 5. Location transparency

An actor reference **does not reveal** whether the target is local (on this same core), on another core, or on another chip. The same `send(actor_ref, msg)` works in every case, and the router (hardware + software) decides where the message goes.

**Consequences:**
- Actors **can be relocated** between cores at runtime (load balancing)
- A single Neuron OS instance **can span multiple chips** (F7+ distributed)
- Local and distributed systems **run the same code**

### 6. Capability-based security

An actor can **only** send a message to another if it knows its reference. The reference is a **capability** -- possession equals authorization. There is no global namespace (like Unix `/dev/sda`), no all-powerful "root" user.

This is the security model of CHERI and seL4, which Neuron OS uses natively, **because the hardware (CLI-CPU) is inherently shared-nothing**.

### 7. Hot code loading

**New CIL code can be loaded into a running system** without downtime. An actor can receive its last message with `v1` and the next one with `v2` -- the **supervisor** coordinates the transition. This is a 40-year-old feature of Erlang OTP, which Neuron OS natively supports.

The **writable microcode SRAM** (F6+ Rich core) makes it possible to **override opcode semantics at runtime** as well, if needed -- e.g., pushing a hotfix into a live system.

### 8. Determinism by default

Neuron OS is **deterministic by default**: the same sequence of inputs produces the same state. This:
- Yields reproducible bugs
- Enables **message replay** based debugging
- Is amenable to formal verification
- Fits certifiable systems (IEC 61508, ISO 26262)

Non-deterministic behavior is **explicit** -- timing, random numbers, external I/O -- and is always visible in the code.

## The inherited problems of Linux and the Neuron OS answer

This section provides a concrete comparison showing why we do **not** want to exist **alongside** Linux, but rather **replace the Linux legacy** on foundations tailored to modern requirements.

| Problem category | Linux (Unix legacy) | Neuron OS |
|-----------------|---------------------|-----------|
| **Kernel architecture** | Monolithic kernel, ~40M lines of C, a single driver bug = system crash | Microkernel actor hierarchy, ~1-2k lines of kernel, driver crash = supervisor restart |
| **Security incidents** | ~500+ CVEs/year, kernel exploits are common (Dirty Pipe, Dirty COW, etc.) | Architecturally excluded ROP/JOP/buffer overflow/JIT spray, formally verifiable |
| **Concurrency model** | pthread + mutex + shared memory leads to race conditions, deadlocks, memory corruption | Actor model, immutable messages, **architecturally race-free** |
| **Scaling to many cores** | Lock contention, RCU complexity, NUMA effects, difficult beyond 128+ cores | **Linear** scaling, no locks, no cache coherency traffic |
| **Error handling** | Kernel panic leads to reboot, segfault leads to crash, supervisor via systemd is bolted on | Let it crash + supervision tree, 9-nines availability (proven by Erlang) |
| **Distributed systems** | POSIX != network API, two different programming models, Docker/K8s bolted on | **Location transparency** natively -- local and remote use the same code |
| **Updates** | Restart required, kernel live patching is complex and limited | **Hot code loading** without downtime, Erlang-style |
| **Driver model** | Runs in kernel mode, bug = kernel crash | User-space actor, crash = supervisor restart |
| **Memory safety** | Manual (C), unsafe by default, Rust is the new hope but the existing 30M lines of C remain | **Per-actor GC, type-safe by default, architecturally guaranteed** |
| **Namespace model** | Global (/dev/sda, filesystem, PID table) | **Capability-based** -- no global namespace, possession = authorization |
| **Kernel/user mode** | Expensive context switch (~1000+ cycles per syscall) | **No kernel/user mode** -- everything is an actor, hardware isolation |
| **POSIX permissions** | 1970s thinking (user, group, other, rwx) | Capability (fine-grained, delegatable, revocable, HMAC-signed) |
| **IPC primitives** | 7+ mechanisms (pipes, sockets, shared memory, message queues, signals, semaphores, futex) | A **single** primitive -- mailbox message passing (everything else is reducible to it) |
| **Filesystem** | Universal abstraction (byte stream), but does not fit every data structure | Actor-based storage service, structured |
| **Shared libraries** | DLL hell, ABI bugs, supply chain attacks (log4j, xz-utils) | Hot code loading at actor level, each standalone, tree-shaken |
| **Container technology** | Docker/K8s as a bolted-on layer over namespace+cgroups | Native actor isolation, no need for containers |
| **Determinism** | Non-deterministic (scheduler, kernel preemption, cache behavior) | **Deterministic** by default |
| **Formal verification** | Practically impossible due to size and complexity | **Achievable** (proven by seL4), the CLI-CPU ISA is formally describable |
| **Safety certification** | Possible, but 10+ years for an EAL-5+ Linux distribution | Natively certifiable (IEC 61508, ISO 26262, DO-178C, IEC 62304) |
| **Historical roots** | Multics 1964, Unix 1970, Linux 1991 | 2020+, incorporating every modern lesson (Erlang 1986, seL4 2009, Singularity 2003) |

**This is not a minor optimization** of the Linux model -- **it is a fundamentally different paradigm** that solves problems Linux architecturally cannot.

### What we learn from the success of Linux

Let us be honest: Linux is a **tremendous success**. A $15+ billion annual enterprise ecosystem, running every modern cloud, every Android phone, every supercomputer. This **cannot be ignored**, and Neuron OS should not believe it will replace it overnight.

What we learn from the success of Linux:
- **Open source** -- community development, transparent decisions
- **Permissive license** -- Apache 2.0 or MIT, not strict GPL
- **Modularity** -- every component is replaceable
- **Good documentation** -- Linux kernel docs have been improving for years
- **Tool ecosystem** -- compilers, debuggers, profilers, testers
- **Hardware support** -- many drivers, many platforms

Neuron OS **aspires to all of these**, but **on different foundations**.

### What will happen to Linux?

Neuron OS **does not want Linux to disappear from one day to the next**. The real transition is long-term, perhaps **10-20 years**:

| Period | Linux position | Neuron OS position |
|--------|---------------|-------------------|
| **2026-2030** | Dominant everywhere | F1-F6 development, F6 first silicon, Cognitive Fabric proof, embedded niche |
| **2030-2035** | Dominant on desktop, server, mobile; facing challenges in regulated industries | Commercial products in specific verticals: AI safety, critical infra, automotive, medical |
| **2035-2040** | Conservative cloud, legacy | New cloud architectures on Cognitive Fabric (actor-based hyperscalers); edge computing dominant |
| **2040-2050** | Legacy support | Default platform for new systems, Neuron OS fills the role Linux once held |

**This is not a guarantee**, just one possible future. But **let us be clear**: the goal is not to **coexist alongside** Linux, but to **fill the role of Linux's successor** through a long, organic transition. Just as x86 replaced the mainframe (1980-2000), mobile replaced the desktop (2007-2020), and cloud replaced on-prem (2010-2025) -- **Cognitive Fabric + Neuron OS will be the next replacement cycle**, starting in 2026.

## System architecture -- as a hierarchy of actors

Neuron OS is **not a kernel/user mode** system. There is no kernel space and user space separation, because **hardware isolation** (shared-nothing multi-core) already guarantees what other OSes achieve with kernel/user mode switches. Instead, **privilege levels are expressed through actor relationships**: an actor can perform a privileged operation (e.g., DMA, network hardware) only if it knows the **device actor** reference.

### Boot-time actor hierarchy

```
  [bootloader]         -- the Rich core runs from flash, R/O CIL code
       │
       ▼  creates
  [root_supervisor]    -- the first actor that runs
       │
       ▼  creates the kernel actors
  ┌────┴────────────────────────────┐
  │                                 │
[kernel_core_sup]            [kernel_io_sup]
  │                                 │
  ├─ [scheduler]                    ├─ [uart_device]
  ├─ [router]                       ├─ [gpio_device]
  ├─ [memory_manager]               ├─ [timer_device]
  ├─ [capability_registry]          └─ [flash_device]
  └─ [hot_code_loader]
       │
       ▼  when application actors are started
  [app_supervisor]
       │
  ┌────┴────────────────────────┐
[neural_worker_sup]         [network_sup]
  │                             │
  ├─ [neuron_0001]             ├─ [tcp_manager]
  ├─ [neuron_0002]             ├─ [udp_manager]
  ├─ ... (e.g. 48 neurons)    └─ [ble_manager]
  └─ [neuron_coordinator]
```

### Kernel actors (root level)

These are the "kernel" of Neuron OS, but they do not run in kernel mode -- rather, they are **special actors running on a few Rich cores**:

1. **`root_supervisor`** -- the first actor, parent of all others. Very simple, only restart logic. It never fails, because there is nothing it can do wrong.
2. **`scheduler`** -- decides which actor runs on which core. Not preemptive (actors cooperatively yield control at message-processing boundaries), **but the supervisor can stop** a stuck actor.
3. **`router`** -- the software complement to the hardware mailbox router. Translates logical actor references to physical addresses (physical core + mailbox offset). Load balancing, migration.
4. **`memory_manager`** -- although every core has its own SRAM, the Rich cores' heaps come from a shared allocation pool. The memory manager administrates this pool.
5. **`capability_registry`** -- the registry of actor reference to capability mappings. An actor can only obtain a reference if the registry issues one.
6. **`hot_code_loader`** -- accepts new CIL binaries (e.g., from a flash update or over the network), verifies them (checking that only permitted opcodes are present), and loads them into running actors.

Every kernel actor runs on a **single core** (Rich), and is **supervised** by the `root_supervisor`.

### Device actors

Every hardware peripheral is a **device actor** that manages the MMIO region of that peripheral. Applications **cannot directly access** the hardware -- only through the device actor's messages.

```
[uart_device] actor:
  - own mailbox (incoming: application requests read/write)
  - manages the 0xF0000000-F00000FF UART MMIO
  - two child actors: uart_tx, uart_rx
  - supervisor: kernel_io_sup
```

The capability: **if an application possesses** the `uart_device` reference, it can write to UART. Otherwise it has **no way** to touch UART.

## Actor lifecycle

The phases of an actor's life:

### 1. Create
The parent actor sends a `spawn(child_code, init_state)` message to the `scheduler`. The scheduler:
- Selects a core (based on load balancing)
- Loads the CIL code onto the core (already there if statically linked; otherwise via hot code loader)
- Initializes the actor state with the given initial value
- Issues a capability for the new actor
- **Returns a reference** to the parent

### 2. Start
The actor enters the `main loop`:
```csharp
while (running) {
    var msg = WaitForMessage();  // sleeps if mailbox is empty
    state = HandleMessage(msg, state);
    if (state.ShouldStop) running = false;
}
```
`WaitForMessage()` is a hardware wait-for-interrupt, so the core **physically sleeps** when there is no message.

### 3. Run
The actor processes messages, changes state, sends messages to other actors. **Cooperative multitasking**: the scheduler does **not** interrupt message processing (unless a watchdog timer triggers).

### 4. Suspend (optional)
The scheduler can **relocate** an actor from one core to another (load balancing). This:
- Waits until the actor finishes the current message
- Serializes the state
- Reconstructs it on the new core
- The router updates the reference

### 5. Migrate (Nano to Rich)
If a Nano core actor requires an operation only available on a Rich core (e.g., object allocation, exceptions, FP), it **can migrate**. Two ways:
- **Explicit migration**: the actor code calls `MigrateToRich()`, and its state is transferred to a Rich core
- **Trap-based migration**: a Nano core fires an `UNSUPPORTED_OPCODE` trap, and the trap handler migrates the state to a Rich core

The second is only for **emergencies**; the design aims for code to be **already** marked for the appropriate core type (`[RunsOn]` attribute).

### 6. Stop
The actor can decide to stop on its own (normal exit), or the supervisor can stop it (explicit stop). In both cases:
- Remaining mailbox messages go to a **deadletter queue** (optionally to the supervisor)
- The state is freed
- The capability is revoked
- The scheduler notifies the parent (enabling respawn)

### 7. Crash + Restart
If the actor causes a fault (`OVERFLOW` trap, `NULL_REFERENCE` trap, etc.), the hardware exception unwinder **notifies the supervisor** on a hardware interrupt line. The supervisor:
- Receives the `{crashed, actor_ref, reason}` message
- Decides: **restart** (to the same state as spawn), **escalate** (to its own supervisor), or **stop** (permanent shutdown)

Erlang OTP defines four restart strategies: `one_for_one`, `one_for_all`, `rest_for_one`, `simple_one_for_one`. Neuron OS supports all of them.

## Message routing

### Levels

A message can reach its target via **four routes**, in order of increasing cost:

1. **Local** (on the same core, internal messages within the same actor) -- ~1-3 cycles, zero copy
2. **Inter-core** (on the same chip, different core) -- ~10-20 cycles, through hardware mailbox FIFO
3. **Inter-chip** (distributed, on another Neuron OS node) -- ~100-1000 cycles, through a dedicated network actor
4. **Wide area** (over the internet to another geographic node) -- ~ms, also through a network actor

The router handles all four **transparently**. The developer uses the same `send(ref, msg)` call.

### Message structure

```csharp
public struct Message {
    public int  MessageId;       // globally unique
    public int  SenderActorRef;  // who sends it
    public int  ReceiverActorRef;// to whom
    public int  MessageKind;     // type (struct hash)
    public long Timestamp;       // when sent (determinism)
    public int  PayloadSize;     // payload size in bytes
    // + payload bytes
}
```

The payload is an **immutable value type**, a CIL `struct` or immutable class. The developer **cannot send** a mutable object reference, because the compiler (`cli-cpu-link`) checks at build time.

### Priority vs FIFO

The mailbox is **FIFO** by default -- messages are processed in arrival order. But an actor can explicitly choose a **priority** mailbox, where high-priority messages (e.g., `system_shutdown`, `supervisor_kill`) can jump the queue. This is **opt-in**, not default.

### Backpressure

When a mailbox fills up (the hardware FIFO is 8 deep in F3, ~64 deep in F6), the sender **blocks** (or receives a `SendError` trap if it used `try_send`). This is **natural flow control** -- there is no need for explicit rate limiting.

## Memory management

### Per-core private SRAM

Every core has its **own 16-256 KB SRAM** that is visible **only to that core**. The core has its own:
- Eval stack
- Local variables
- Frames (per call)
- Heap (on Rich cores; Nano cores have none)

Cores **cannot see each other's memory**. "Sharing" is only possible through message copying.

### Per-core private GC

Rich cores have their own **bump allocator + mark-sweep GC**. There is **no global GC**, **no stop-the-world across the entire chip**. When one core runs GC, all other cores work **completely independently**.

This is **one of the greatest simplifications** of the shared-nothing model. In Akka.NET the global .NET GC is the bottleneck under high load; on Neuron OS **this problem does not exist**.

### Zero-copy messaging (local)

When an actor sends a message to another actor **on the same core**, the runtime can detect this and forward it in **zero-copy** mode (passing only the pointer). The target actor sees the message in its own view.

**For inter-core cases**, the runtime **copies** the message from the sender core's SRAM to the receiver core's SRAM through the mailbox FIFO. This takes ~10-30 cycles, depending on size.

## Capability-based security

### The concept of a capability

A **capability** is an unforgeable token representing a specific authorization. In Neuron OS, **the actor reference itself is a capability**:

```csharp
ActorRef uartDevice = ...;  // this is a capability
uartDevice.Send(new WriteByte(0x41));  // works only because I have the reference
```

The received `ActorRef` is **not a number** but a structured token:
```csharp
public struct ActorRef {
    public int  CoreId;
    public int  MailboxIndex;
    public long CapabilityTag;  // HMAC-like, signed by the capability_registry
    public int  Permissions;    // read, write, forward, revoke, ...
}
```

The `CapabilityTag` is issued by the `capability_registry`, and the hardware router **verifies** it on every message send. For a forged or expired capability, the router **drops** the message and generates a trap for the sender.

### Delegation and revocation

- **Delegation**: an actor can **pass** its reference to another (in a message). The recipient can then send messages to the target. This is authorization transfer without the target knowing.
- **Revocation**: the original issuer (e.g., the `root_supervisor`) can **revoke** a capability. After that, anyone holding that tag loses the right. The `capability_registry` handles this.

### Isolation guarantee

The CLI-CPU's hardware **shared-nothing** architecture guarantees:
- An actor **cannot** write to another actor's memory -- the hardware physically does not allow it
- An actor **cannot** call another actor's code -- only through messages
- An actor **cannot** access a peripheral unless it knows the device actor reference
- An actor **cannot** send a deceptive message on behalf of another actor -- the router verifies the sender's capability

**This is a hardware-implemented capability-based OS** -- what until now only seL4 and CHERI offered at an academic level, and what Neuron OS brings to the .NET world.

## Dynamic code loading

### Hot code loading

**New CIL code can be loaded** into a running Neuron OS without downtime. The process:

1. An external source (flash update, network message, USB) sends the new CIL binary to the `hot_code_loader` actor
2. The loader **verifies**: opcode whitelist, capability check, signature check
3. The loader **loads** the new code onto a Rich core (into the code ROM, if writable microcode + writable SRAM segment is available)
4. The loader **sends a message** to every affected actor: "new version available"
5. Each actor **switches to the new code at a message-processing boundary** (i.e., in a consistent state)
6. New messages are processed with the `v2` code, but the **current state is preserved**

**This is critically important** in systems where downtime is not permitted: telecommunications, critical infrastructure, medical, automotive.

### Starting a new actor dynamically

A running actor **can create a new actor** at runtime:

```csharp
public async Task HandleRequest(IncomingRequest req) {
    // create a new actor for the request
    var workerRef = await Spawn<RequestWorker>(req.InitialState);
    workerRef.Send(new ProcessRequestMsg(req));
}
```

The scheduler **dynamically** finds a free core (or builds a waiting queue if all are busy). This is the "one request = one actor" model that Erlang has been doing for 40 years.

### Writable microcode -- from F6

The Rich core will have **writable microcode SRAM** from F6. This makes it possible to **load new CIL opcode semantics** at runtime. Use cases:
- **Bugfix** in a microcoded opcode (e.g., fixing a rare exception case)
- **New opcodes** if a new ECMA-335 version adds important opcodes
- **Specialized workload**-optimized microcode (e.g., crypto acceleration)

## I/O model

### Device actors

Every hardware peripheral is a **device actor** in Neuron OS. The device actor:
- Owns the MMIO region of the given peripheral
- Can receive messages requesting peripheral operations
- Can send messages (e.g., notifying a subscribed reader actor about received UART bytes)

**Example: UART device actor**

```csharp
[RunsOn(CoreType.Rich)]  // part of the kernel_io_sup tree
public class UartDevice : DeviceActor {
    // hardware MMIO address
    const uint UART_DATA = 0xF0000000;
    const uint UART_STATUS = 0xF0000004;

    ActorRef? _subscriber;  // who wants to receive RX bytes

    public override async Task HandleAsync(Message msg) {
        switch (msg) {
            case WriteByteMsg wb:
                // blocking wait until TX ready
                while ((Read(UART_STATUS) & TX_READY_BIT) == 0) await Yield();
                Write(UART_DATA, wb.Byte);
                break;

            case SubscribeRxMsg sub:
                _subscriber = sub.Subscriber;
                break;

            case RxInterruptMsg:
                var byteVal = Read(UART_DATA);
                _subscriber?.Send(new RxByteMsg((byte)byteVal));
                break;
        }
    }
}
```

### Peripheral ownership -- capability

As mentioned: the device actor's **capability** determines who can access the peripheral. The `app_supervisor` decides which application receives the capability for which device actors. If an application did not receive the `uart_device` reference, it **physically cannot** write to UART.

### Filesystem -- as an actor service

The filesystem (if present) is also a **collection of actors**:

- A `flash_device` actor manages the QSPI flash hardware
- A `block_service` actor builds a block abstraction on top
- An `fs_service` actor provides filesystem semantics (read, write, directory)
- A `file_handle` actor for every open file (like an Erlang port)

"Opening a file" = sending a message to the `fs_service` actor, which spawns a new `file_handle` actor. Closing the file = stopping the `file_handle` actor.

**This differs from the POSIX model**, but naturally fits the actor OS, and compatibility can be provided by a **POSIX compatibility layer** on top after F7 -- if it is even needed.

## Developer API -- in C#

The developer does **not** think as a kernel programmer, but as a **C# programmer** with an **actor-oriented framework**. The API roughly resembles Akka.NET, but the runtime is hardware-backed.

### Basic actor

```csharp
using NeuronOS;

public class CounterActor : Actor<CounterState> {
    public override CounterState Init() => new CounterState(Value: 0);

    public override CounterState Handle(CounterState state, Message msg) => msg switch {
        IncrementMsg => state with { Value = state.Value + 1 },
        GetValueMsg g => Reply(g.Sender, new ValueMsg(state.Value)).Then(state),
        _ => state
    };
}

public record CounterState(int Value);
public record IncrementMsg;
public record GetValueMsg(ActorRef Sender);
public record ValueMsg(int Value);
```

### Supervisor

```csharp
public class AppSupervisor : Supervisor {
    public override SupervisorSpec Init() => new SupervisorSpec(
        Strategy: RestartStrategy.OneForOne,
        MaxRestarts: 3,
        Period: TimeSpan.FromMinutes(1),
        Children: [
            new ChildSpec<CounterActor>("counter1", autoStart: true),
            new ChildSpec<CounterActor>("counter2", autoStart: true),
            new ChildSpec<NeuralWorkerSup>("neural_workers", autoStart: true),
        ]);
}
```

### Spawn + messaging

```csharp
var counter = await Spawn<CounterActor>();
counter.Send(new IncrementMsg());
counter.Send(new IncrementMsg());
counter.Send(new IncrementMsg());

// synchronous query (wrapper over a mailbox)
var value = await counter.Ask<ValueMsg>(new GetValueMsg(Self));
Console.WriteLine($"Counter: {value.Value}");
// output: Counter: 3
```

### Core type attribute

```csharp
[RunsOn(CoreType.Nano)]
public class LifNeuronActor : Actor<LifNeuronState> {
    // integer only, fixed-size only, no object allocation inside
    // the cli-cpu-link tool checks at build time
}

[RunsOn(CoreType.Rich)]
public class SnnCoordinatorActor : Actor<CoordinatorState> {
    // full CIL functionality: List<T>, Dictionary, exceptions, FP
}
```

### Distributed actor (F7)

```csharp
// If Neuron OS runs distributed across multiple chips:
var remoteActor = ActorRef.FromUri("neuron://chip2.local/neural_workers/neuron_0042");
remoteActor.Send(new SpikeMsg(weight: 100));
// the local router detects it is remote and routes through the network_device actor
```

## Relationship to the Cognitive Fabric positioning

Neuron OS is **not a separate product** from the CLI-CPU hardware -- **it is the software layer that makes the Cognitive Fabric positioning real**. The same hardware (CLI-CPU multi-core + mailbox + heterogeneous Nano+Rich) supports **different** usage modes on **the same** Neuron OS foundation:

| Usage mode | What the actors run | Supervisor tree characteristics |
|-----------|---------------------|-------------------------------|
| **Akka.NET cluster** | Business logic, services | Hierarchical service supervisor |
| **Spiking Neural Network** | LIF/Izhikevich neuron models | Flat, one coordinator supervisor |
| **Multi-agent simulation** | Agent AI + environment | Per-environment supervisor |
| **Event-driven IoT edge** | Sensor handlers + protocol processors | Device-to-app hierarchical |
| **Telecommunications stack** | Call handling, session management | Per-call supervisor (Erlang style) |
| **Blockchain validator** | Consensus + transaction verification | Flat, peer-based |

**The same operating system**, **the same hardware**, **the same programming model** -- **different** application actors, **different** roles. Neuron OS is the "lingua franca" that places every Cognitive Fabric application on a unified platform.

## Phased implementation

Neuron OS is **not one big leap**, but **builds organically** over the F1-F7 phases, adding the next layer in each phase.

### F1 -- Minimal runtime in the C# simulator
**Output:** a simple "actor runner" that provides actor-like abstractions within the simulator.
- Basic `Actor<T>` class
- In-memory mailbox
- Spawn / send / receive
- A single static supervisor (no restart)

This is **not a real OS**, just a programming framework that already helps write programs in an actor-oriented way.

### F3 -- Tiny Tapeout bootloader
**Output:** a minimal boot CIL program that:
- Loads from QSPI flash
- Initializes the stack, mailbox MMIO, UART
- Starts a single actor (e.g., the "echo neuron")
- Forwards bytes arriving on UART through a mailbox, takes output bytes from there as well

**This is the first real hardware "Neuron OS"**, albeit still single-actor.

### F4 -- Multi-core scheduler + router
**Output:** on the 4-core FPGA system:
- A single `scheduler` actor that allocates others to cores
- A `router` actor that directs inter-core messages
- Minimal supervisor -- crash leads to UART log, manual restart
- Command line over UART: spawn, send, kill

This is a **4-actor system**, where the scheduler + router already play a real role.

### F5 -- Supervision hierarchy + lifecycle + GC
**Output:** on the heterogeneous Nano+Rich FPGA:
- Full supervisor tree (OneForOne, OneForAll, RestForOne)
- Per-core GC on Rich cores
- Capability-based isolation in hardware (mailbox target verification)
- Actor migration from Nano to Rich via trap
- `[RunsOn]` attribute via Roslyn source generator

This is **the first usable Neuron OS**, capable of running real C# programs in an actor-oriented fashion.

### F6-FPGA -- Hot code loading, distributed multi-board
**Output:** on a 3x A7-Lite 200T multi-board Ethernet network:
- Hot code loading at the actor level
- Distributed actor system across multiple chips (Ethernet bridge)
- Real test of location transparency -- cross-chip actor communication
- Full capability registry with signing

This is the **FPGA-verified, distributed** Neuron OS -- the first demonstration of a true multi-chip Cognitive Fabric.

### F6-Silicon -- Writable microcode, silicon verification
**Output:** ChipIgnite real silicon (only after F6-FPGA verification):
- The distributed OS verified on F6-FPGA, integrated onto a single chip
- Writable microcode SRAM (silicon-specific)
- Power efficiency and clock frequency measurement

This is the **silicon-mature** Neuron OS.

### F7 -- Developer SDK + reference applications
**Output:** a public platform:
- `dotnet publish` target for Neuron OS
- VSCode / VS extension debugger
- NuGet packages (`NeuronOS.Core`, `NeuronOS.Actor`, `NeuronOS.Devices`)
- Reference demo applications: SNN, Akka.NET port, IoT gateway, multi-agent sim
- Publication + talks + Linux Foundation project status

**This is Neuron OS graduating from research level to a real developer platform.**

## Prior art -- what we learn from other systems

### Erlang/OTP (Ericsson, 1986)
**The greatest inspiration.** 40 years of production service in telecommunications, financial, and large-scale systems. Supervision, hot code loading, let it crash, location transparency -- all of this comes from them.

**What we adopt:** the entire programming paradigm, supervisor strategies, naming conventions, message passing semantics.

**What we do NOT adopt:** the BEAM VM (it is software-based; ours is hardware). The dynamically typed language (we use C#). The Prolog-style pattern matching (C# switch expressions suffice).

### QNX (1982)
**A commercial microkernel with message-passing OS.** Embedded, automotive, medical, aviation (BMW iDrive, RIM/BlackBerry, Cisco routers).

**What we adopt:** the message-passing kernel philosophy, deterministic real-time response times, priority inheritance.

**What we do NOT adopt:** POSIX compatibility (we carry the actor model cleanly).

### seL4 (2009, UNSW, NICTA)
**The first formally verified OS kernel.** Capability-based, microkernel, ~10,000 lines of C, Coq + Isabelle proofs.

**What we adopt:** the capability model, the formal verification goal, minimalism.

**What we do NOT adopt:** the L4 IPC abstraction (we use the actor model, not processes + IPC).

### MINIX 3 (Tanenbaum, 2005)
**Multi-server microkernel.** If a server (e.g., file server) crashes, it restarts without affecting the rest.

**What we adopt:** the reincarnation server (supervisor) idea, driver isolation.

### Singularity (Microsoft Research, 2003-2008)
**A C#-based OS research project.** Every component is an isolated "Software Isolated Process" (SIP). They communicate through message channels, and the compiler verifies isolation at build time.

**What we adopt:** the SIP isolation model, the C#-based OS design philosophy, compiler-side verification. **This is our closest intellectual relative**, except it never reached public use as a Microsoft research project.

### Orleans (Microsoft, 2010)
**Virtual actors in .NET**, cloud-scale, Halo 4/5 backend.

**What we adopt:** the virtual actor concept (an actor reference is **logical**, the runtime decides where it physically runs), location transparency, the distributed system API.

### Pony (2014)
**An actor-based programming language with a reference capability type system.** Guaranteed data-race freedom at the compiler level.

**What we adopt:** the "guaranteed isolation at compile time" idea. C# can achieve the same with `readonly struct` and immutable types.

### Akka.NET (2013)
**Scala Akka port to C#.** Productive, mature, but **software-based**.

**What we adopt:** the API in part, the programming model, the toolkit.

## What Neuron OS deliberately does **not** replicate -- conscious architectural decisions

These are **not limitations** but **conscious design decisions** -- rejecting inherited 1970s compromises that no longer meet today's requirements. What we do not do the **same way** as Linux, we do **better**.

### 1. Not POSIX compatibility -- instead, a modern actor API

There is no `fork()`, `exec()`, `open()`, `close()`, `read()`, `write()` in the traditional sense. **Why this is fine:** these APIs were designed for 1970s single-core, low-memory Unix systems operating on character terminals. `fork()`, for instance, **copies an address space identical to another process** -- this is the **least secure** symptom of the shared memory model, and an increasingly severe performance and security problem in modern multi-core systems.

Instead, Neuron OS provides **modern alternatives**: `Spawn<Actor>()` (not `fork`), `Send(actorRef, msg)` (not `write()` to an fd), `Receive()` (not blocking `read()`), `ActorRef` (not `fd`). If porting an old POSIX application is needed, **a software compatibility layer** can be built on Neuron OS (like Windows WSL2 in reverse) -- but **the native programming model is clearly more modern and secure**.

### 2. Not a monolithic kernel -- instead, an actor hierarchy

No kernel space, no user space, no system call overhead. **Why this is better:** the kernel/user mode switch costs ~1000 cycles on every system call, and Spectre/Meltdown/L1TF all attempt to cross privilege boundaries. On Neuron OS **there are no such boundaries** -- every component is an actor, and hardware shared-nothing isolation guarantees what other OSes provide via kernel/user mode switching. An actor cannot write to another actor's memory **not because the kernel stops it**, but because **no such physical path exists**.

### 3. Not a global filesystem scheme -- instead, a structured storage service

A file is **not a byte stream** in Neuron OS. **Why this is better:** the Unix "everything is a file" abstraction obscures many modern data structures (time-series data, graphs, object schemas, eventually-consistent stores). Today these are **all layered on top of the filesystem** (SQLite, RocksDB, LevelDB), adding complexity and vulnerability.

On Neuron OS, **data arrives and departs as actor messages**, and the "storage service" is a **structured actor system** that directly understands data structures. A POSIX compatibility layer at the edge can provide the traditional filesystem API if needed.

### 4. Not shared memory + mutex -- instead, actor message passing

There is no `pthread_mutex_lock`, `pthread_cond_wait`, `shm_open`, `mmap(MAP_SHARED)`. **Why this is better:** these primitives **architecturally enable** race conditions, deadlocks, and data corruption. For decades, they have been the **hardest class of bugs to fix** in programming.

Actor message passing **architecturally excludes** these. It does not make them harder -- it makes them **physically impossible**. The performance that shared memory promised is available in the Neuron OS + CLI-CPU combination as **zero-copy mailbox**, but **without** the risk of race conditions.

### 5. Not POSIX user/group permissions -- instead, capability-based security

There is no `chmod`, `chown`, `setuid`, `setgid`, `/etc/passwd`. **Why this is better:** the Unix permission model was born in 1970, when 10-20 users shared a machine and trust was assumed. In today's world of containers, multi-tenant cloud, and AI agents, this is **absurd**. A single root user holds **every** permission, which with a single bug leads to **total compromise**.

Neuron OS's **capability-based security** model is **more nuanced, finer-grained, and delegatable**. An actor has authorization for an operation **only if** someone has **given** it the appropriate capability. There is no global "root" -- everyone can only do what they have been explicitly authorized to do. This is the model of CHERI and seL4, proven by decades of research.

### 6. Not manual memory management in unsafe-by-default languages -- instead, type-safe, garbage-collected actors

There is no `malloc`/`free`, no `char *`, no `void *`. **Why this is better:** C/C++ memory management is the **primary source** of security bugs. More than 70% of CVEs stem from memory safety errors. Rust solves this at the software level, but the existing 30+ million lines of C/C++ code will **never be fully rewritten**.

On Neuron OS, everything is **type-safe by default**, with hardware GC, built on CIL ECMA-335 verifiable code semantics. A developer **cannot** write a memory corruption bug for Neuron OS, because neither the language (C#), nor the runtime (CLI-CPU), nor the ISA (CIL-T0/Rich) **allows it**.

### 7. Not kernel panic + reboot -- instead, let it crash + supervision

When a driver fails in Linux, it is a **kernel panic**, and the system reboots. Modern Linux does much to avoid this (recovery subsystems, kprobes, live patching), but the **basic model** is "kernel bug leads to system halt."

On Neuron OS, a driver is **an actor**, and when it fails, the **supervisor restarts it**. The rest of the system **remains unaffected**. This is an approach **proven over 40 years** in Erlang (Ericsson AXD301, 9-nines availability), and Neuron OS naturally uses it.

## Long-term possibilities -- what Neuron OS **naturally** opens up

This section describes areas that are **not first-generation goals**, but where the Neuron OS architecture is **inherently** suited, and which **in the long term** (after F7, 2035+ timeframe) can become reality -- and in certain areas can be **dramatically better** than current Linux/Windows/macOS solutions. These are not "someday maybe" afterthoughts, but **the project's future opportunity horizon**.

### 1. Interactive desktop UI -- natively actor-based

On Neuron OS, **a desktop UI is a natural fit**, because every UI element is fundamentally actor-like:

| UI component | On traditional OS | On Neuron OS |
|-------------|-------------------|--------------|
| Widget | Shared state, callback chain | **Actor** (own state, `Receive` method) |
| Window | Kernel+compositor shared resource | **Actor hierarchy** (window + child widgets) |
| Input handler | Global event queue, polling | **Mailbox** on every widget |
| Renderer | GPU driver + compositing | **Render actor**, receiving update messages from window actor |
| Animation | Timer + dirty flag | **Event-driven message** with time-based trigger |

**What is fundamentally better:**
- **If a widget crashes, the rest keep working** -- on Linux a buggy GTK widget can often kill the entire window, the entire X session, or sometimes the whole desktop
- **Hot reload natively** -- a running application's UI can be **modified live** without recompilation, Erlang-style
- **Multi-touch / multi-input** -- every input device is its own actor, no global input queue bottleneck
- **GPU-free vector UI** -- if the system has enough Nano cores, vector graphics **can be computed in an actor network**, no GPU required
- **Deterministic replay** -- a UI bug can be reproduced by replaying the input message sequence

**Modern frameworks that are already actor-like:**
- **React** / **Vue** / **Svelte** -- "component" is roughly an actor, re-render is roughly message processing
- **Flutter** -- widget tree is roughly an actor hierarchy, `setState()` is roughly `Send`
- **SwiftUI** -- view as value, state-based rendering
- **Elm architecture** -- explicit update + view, a clear actor pattern
- **Jetpack Compose** (Android) -- declarative, reactive

**A Neuron OS Desktop** would not replicate the X11/Wayland model, but would be **natively actor-based**: every widget is a `UiWidgetActor`, every window is a `WindowActor`, compositing is a `RenderSupervisorActor`. A **React/Flutter-like API** in C#, built directly on the Neuron OS runtime. This is **much simpler** than the Linux stack, and **much more robust**.

**When:** 2035+ timeframe, after F7 in a separate "Neuron OS Desktop" project. Not first generation, but **not unattainable either** -- there just **isn't time yet**. When the moment comes, the system **will be ready**.

### 2. Gaming platform -- native ECS + deterministic multiplayer

Modern games are **actor-like by nature**. The **Entity Component System (ECS)** paradigm (followed by Unity DOTS, Unreal Engine Mass, and Bevy) approximates the actor model.

| Game component | Traditional implementation | On Neuron OS |
|---------------|--------------------------|--------------|
| Player entity | Shared memory object, protected by mutex | **Actor** (own state, messages) |
| NPC / AI agent | Thread pool, synchronization | **Actor** (one per NPC), native parallelism |
| Physics world | Single thread, or complex partitioning | **Actor network** (every physics object is an actor) |
| Render | Command buffer, GPU sync | **Render actor**, with draw messages |
| Network sync | Custom protocol, delta encoding | **Message replay** + native determinism |
| Sound | Mixer thread, callbacks | **Audio actor**, with stream messages |
| Input | Polling vs event | **Mailbox-based** |

**What is fundamentally better:**
- **No data races** between NPCs -- traditional games are **full of** synchronization bugs that on Neuron OS are **physically impossible**
- **Massively parallel AI** -- 10,000 NPCs in an MMO? Every NPC on its own Nano core, with real parallelism. **A scale** that today's game engines cannot achieve
- **Deterministic multiplayer sync** -- since every message arrives in strict order and every actor is deterministic, **lockstep** multiplayer synchronization is **natively** achievable (which is very difficult on traditional systems)
- **Hot modding** -- new NPC behaviors, new rules, new items can be **loaded at runtime** with Erlang-style hot code loading. The Minecraft modding ecosystem would be **exponentially simpler** on this model
- **Formally verifiable game logic** -- a competitive game's (esport) logic can be **provably fair mathematically** when running on Neuron OS -- no anti-cheat heuristics needed, the system **architecturally** prevents cheating
- **Entity isolation** -- if an NPC AI script fails, **only that NPC** dies, the supervisor restarts it. The game continues

**Current examples already moving toward the actor direction:**
- **Minecraft** -- chunks are **almost** actor-like, but on software emulation
- **EVE Online** -- the entire server architecture is dynamically partitioned, quasi actor-clusters
- **Path of Exile 2** -- the new engine explicitly works on an "everything is an actor" philosophy
- **No Man's Sky** -- procedural generation runs in parallel per entity

**Unity DOTS** and **Unreal Mass** try to achieve in software on traditional CPUs what Neuron OS would provide **in hardware for free**.

**When:** 2030+ timeframe, if a game studio or indie team starts using it **as a partner**. A **realtime engine** takes years to develop, but **architecturally** Neuron OS is the **ideal** foundation for a next-generation game engine.

### 3. AI in a new dimension -- an AI-native operating system

**This is where the project holds its greatest potential.** In the AI era, an operating system that **architecturally** fits AI workloads can **create an entirely new category** -- one that neither GPU+CUDA, nor CPU+software, nor current neuromorphic chips can deliver.

#### Why this is different from current AI platforms

The current AI hardware and software **stack** is a pile of layers:
- Linux kernel
- CUDA / ROCm driver
- PyTorch / TensorFlow / JAX
- Model definition
- Training / inference runtime
- Agent framework (LangChain, AutoGen, Claude Agent)

**Every layer has overhead, vulnerability, and complexity**. Neuron OS **drastically** simplifies this, because **the system itself is actor-oriented, which naturally fits AI**.

#### Seven AI domains where Neuron OS is fundamentally better

##### (1) Hardware neural network execution -- not simulation

Current neural networks are **GPU-simulated** matrix operations. Every neuron is a row in a matrix, every weight is a value. On CLI-CPU's Cognitive Fabric, **every neuron can actually be a core**, with its own program, its own state, **real parallelism**. This is **not** the same as a GPU.

The difference: a GPU is SIMD (Single Instruction Multiple Data) -- every "neuron" does **the same thing**, just on different data. CLI-CPU's cognitive fabric is MIMD (Multiple Instruction Multiple Data) -- **every neuron can run a different** algorithm. **This programmability** is what neither the GPU, nor Loihi, nor TrueNorth can offer.

Result: **new neural architectures** become possible that are not built on the backbone of matrix operations, but on **free-form message-passing graphs**. This is **much closer** to the biological brain.

##### (2) AI-native scheduling -- OS decisions driven by AI

In a traditional OS, the scheduler is a static algorithm (CFS on Linux, O(1) in the past). In an **AI-native OS**, the scheduler itself is an actor that **learns** from system behavior and makes **ML-based** decisions about which actor goes on which core, when.

The memory manager, network router, GC, supervisor strategies -- **all** can be learning ML actors that **optimize** as the system is used. It is as if the OS **itself were intelligent**, not just a servant.

##### (3) Agent hierarchy in hardware

Today's **LLM agent** systems (AutoGen, Claude Agent, OpenAI Swarm) are **software layers** on top of a traditional OS, in Python. On Neuron OS, **every agent is its own hardware actor**, running a full LLM on a Rich core, or a small specialist model on a Nano core.

The agent hierarchy is **natively** a supervisor tree: a supervisor agent oversees worker agents, restarts them on failure, or escalates. This is **production-grade** agent-based AI -- what today's software solutions only **promise**.

##### (4) Formally verified AI -- mathematically provable correctness

**This is the biggest deal.** Today's AI systems (LLMs, neural networks) are **unprovable** -- we cannot mathematically verify that for a given input, the model guarantees a safe response. This blocks AI adoption in safety-critical domains (medical diagnosis, autonomous vehicles, critical infrastructure).

On **Neuron OS**, however:
- The **operating system** is formally verifiable (in the seL4 size class)
- The **CLI-CPU ISA** is formally verifiable
- The **actor system topology** is deterministic and describable
- **Capability security** is enforced in hardware

This means that **an AI agent's range of action is mathematically provable**, even if the AI model itself is stochastic. We know that the agent will **never** reach resource X, **never** send data Y, **never** perform operation Z -- because the capability model **does not allow it**. The non-deterministic LLM runs **within deterministic boundaries**.

This is **revolutionarily important** for the future of **regulated AI**. The EU AI Act and similar regulations will demand precisely **this** -- and Neuron OS is the **only platform** that can provide it **architecturally**.

##### (5) Architectural defense against prompt injection

The biggest security problem of today's LLM agents is **prompt injection**: a malicious input manipulates the agent into performing an unauthorized action. Today's defenses are **software heuristics** (guardrails, output filters, jailbreak detectors) -- all **circumventable**.

Neuron OS provides **architectural** defense:
- An agent can only perform operations for which it has a **capability**
- The agent **cannot modify** its own capabilities (hardware isolation)
- The agent **cannot** reach other actors beyond those whose references it holds
- A supervisor actor can **monitor** agent behavior and **shut it down** if it detects anomalies

This means that **no matter how prompt injection tricks an LLM**, Neuron OS **physically does not allow** the desired malicious operation to be carried out. **This is an entirely new security paradigm for AI agents.**

##### (6) Federated / distributed learning natively

Federated learning (model training across multiple independent datasets without combining the data) today requires complex infrastructure (e.g., NVIDIA FLARE, TensorFlow Federated). On Neuron OS this is **native**: every node is a set of actors, messages (gradients, weights) flow between nodes, and thanks to **location transparency** the developer writes **the same code** locally and distributed.

##### (7) Swarm intelligence and multi-agent simulation

Cognitive Fabric offers **exactly** what swarm intelligence and multi-agent AI systems need: **many small, programmable, communicating units**. Robotic swarms, agent-based economic models, epidemic simulations, traffic optimization systems -- all run **natively**.

#### Concrete opportunities

| AI application | What Neuron OS provides |
|---------------|------------------------|
| **Autonomous vehicle AI** | Formally verifiable perception + planning, deterministic realtime, AI safety watchdog |
| **Medical diagnostic AI** | Class C certifiable, auditability, privacy-preserving |
| **Realtime robotics** | Deterministic latency, multi-agent sensor fusion |
| **LLM agent cluster** | Supervisor hierarchy, capability security, prompt injection defense |
| **Hardware neural network (SNN)** | Every neuron is a core, programmable neuron model |
| **Federated learning edge** | Native location transparency, data never leaves the node |
| **AI safety monitor** | A small Rich core monitors a large AI model's output, shuts down on anomaly |
| **Multi-agent simulation** | Thousands of parallel agents, native message passing |
| **Privacy-preserving ML inference** | No shared memory, no side-channel, shared-nothing isolation |

#### Why this is a new dimension

Because until now, the AI platform race has been about **computational throughput**. "More FLOPS, more parameters, bigger model." Cognitive Fabric + Neuron OS **competes on a different axis**: **programmability, security, scalability, certifiability**.

This **creates a new category**:
- Not an "AI accelerator" (like NVIDIA H100, Google TPU)
- Not a "neuromorphic chip" (like Loihi, TrueNorth)
- Not a "multi-core CPU" (like AMD EPYC, Apple M3)
- Not "FPGA AI" (like Xilinx Versal)

Rather, a **"programmable cognitive substrate"** -- the first platform where AI is **not a layer running on top of a traditional OS, but an integrated part of the system**. Where the operating system itself is **AI-based**, where every agent is **hardware-isolated**, and where **formal verification** is not just a slogan but mathematical reality.

**If the project achieves this, Neuron OS will not only be the successor to Linux, but the first native operating system of the AI era.** This is the CLI-CPU project's **most distant, most ambitious** horizon.

### 4. Ecosystem and platform -- long term

Linux built a massive software ecosystem over 30 years (`apt`, `dnf`, `pacman`, `npm`, `PyPI`, `crates.io`, etc.). Neuron OS **will not replicate this overnight**, because it does not intend to -- the **native .NET ecosystem** (NuGet) + Neuron OS-specific packages will be **built over years**, on a **different** paradigm.

**What is, however, inevitable:** every existing piece of software that compiles with `dotnet publish` and is a NuGet package can **in the long run** run natively on Neuron OS. The .NET ecosystem already has **~400,000+ packages** on NuGet, a significant portion of which **does not require P/Invoke** and **does not require reflection**, meaning they run **natively** on the CLI-CPU + Neuron OS combination.

**This is a huge springboard** that other new OS projects (Redox, Serenity, Haiku) never received. The .NET ecosystem **by itself** is a product line we can build upon.

## What we genuinely do not target (narrowed to a tight, conscious list)

The only area where Neuron OS **explicitly does not want to be present**: **native execution of legacy POSIX binaries**. An existing C/C++ Linux program **will not run natively** on Neuron OS. If someone desperately wants it, a **compatibility layer** (Linux Subsystem for Neuron OS, LSNOS) can be built on top -- but this is **not the fundamental model**, and **we do not recommend** it for new code development.

**Every other** area is potentially open in the long term -- time, team, and community will decide whether we actually get there.

## Open questions (to be answered during F1-F4)

These are questions we **cannot decide now**, because real-world experience is needed, and they must be answered during the simulator + FPGA phases:

1. **Exactly how many actors fit on a single Rich core?** An order of magnitude above one core? Hundreds? Thousands? The per-actor context size will determine this.
2. **Should mailbox depth be dynamic?** In F3 it is fixed at 8, but from F5 onward it may be worth making the depth adjustable at runtime.
3. **Preemptive or cooperative scheduling?** Cooperative is simpler, but a misbehaving actor can consume the core. Perhaps watchdog-based semi-preemptive?
4. **Garbage collection algorithm?** Bump + mark-sweep is simple, but incremental is needed for real-time systems. This is an F5-F6 decision.
5. **Network protocol for inter-chip?** Custom, or existing (e.g., gRPC-like)? Custom is simpler but not portable.
6. **Capability signature algorithm?** HMAC-SHA256? Poly1305? Simpler CRC? Security vs. performance tradeoff.
7. **How do we solve real-time guarantees?** Is a hard real-time actor needed (for ASIL-D targets), or is soft real-time sufficient?
8. **How compatible should the Akka.NET API be?** A 1:1 port, or an inspired API?

These questions will be decided based on **F4 simulator + F5 FPGA** experience.

## Next steps

Neuron OS development is **not a standalone phase** in the roadmap, but **builds organically along** the F1-F7 phases. The first concrete steps:

1. **In F1**: the C# reference simulator should have a minimal `NeuronOS.Core` library project providing actor abstractions (`Actor<T>`, `Spawn`, `Send`, `Receive`). **This is not an OS yet**, just a developer convenience, but already enables writing actor-oriented code.

2. **At F3 Tiny Tapeout bring-up**: the echo neuron demo should be a **real Neuron OS actor**, not just a C# program. The actor interface is minimal, but it is **explicitly** written as an actor.

3. **At the F4 multi-core FPGA demo**: the first **real** Neuron OS alpha -- 4 actors, scheduler, router, minimal supervisor. This is the *project's first milestone* where we can speak of an "OS."

4. **Document updates**: as real work progresses, this `neuron-os.md` document will be **updated**, and open questions will be **resolved**.

## Closing thought -- the birth of a new paradigm

Neuron OS is **not just another operating system** alongside the existing Linux, Windows, macOS family. It is **a new paradigm** that **replaces the 1970s Unix foundations inherited by Linux**, exactly as x86 replaced the mainframe, mobile replaced the desktop, and cloud replaced on-prem data centers.

### Why this replacement **will be** inevitable

1. **Security pressure** -- AI-driven code generation, supply chain attacks, and Spectre successors mean Linux architecturally cannot keep pace. On Neuron OS, **these attack classes are architecturally excluded**.

2. **Scaling pressure** -- future hardware is **not 16-64 cores** but **10,000+ cores**. The shared memory model fails there. The actor model **scales linearly**.

3. **Distributed-first world** -- cloud, edge, IoT, and AI agents are all **distributed** systems by default. Linux inherited the "local machine + networking bolted on" model. Neuron OS is **natively distributed**.

4. **Fault tolerance expectations** -- 9-nines availability, the "never reboot" expectation, and critical applications all demand **supervision**, which Linux can only provide with difficulty and bolted-on layers (systemd + K8s + service mesh). On Neuron OS this is **native**.

5. **The need for formal verification** -- safety-critical systems (medical, automotive, aviation, critical infrastructure) demand increasingly rigorous certification, which a **40M-line C kernel** will never achieve. Neuron OS is **formally verifiable**.

6. **AI paradigm shift** -- in the AI era, the operating system is **not a passive servant** but an **active participant**. Agent-based AI, federated learning, formally verified AI, prompt injection defense -- all are **architectural** requirements that Linux cannot provide with bolted-on layers, but Neuron OS delivers **natively**.

### What might be the long-term impact of Neuron OS

If all planned directions succeed:

- **Critical infrastructure** (automotive, medical, aviation, energy) -- Neuron OS as the certified foundation, from 2030
- **Hyperscale cognitive computing** -- Neuron OS + CLI-CPU as a new-category cloud server, from 2035
- **AI agent-cluster platform** -- secure, auditable, capability-based agent systems, **from 2030**
- **Next-generation game engine** -- actor-native ECS, deterministic multiplayer, hardware NPC crowds, **from 2035**
- **Next-generation desktop UI** -- reactive, hot-reload, crash-resistant widgets, **from 2040**
- **Hardware neural network platform** -- MIMD neuron simulation, new neural architectures, **from 2030**
- **AI operating system** -- ML-driven scheduler, memory manager, self-optimizing kernel, **from 2035**
- **Post-quantum cryptography in hardware** -- post-quantum algorithms in isolated environments, **from 2030**

### "The Mess We're In" ten years later

**Joe Armstrong, the father of Erlang, gave a talk in 2014 titled "The Mess We're In"**, where he explained that current software systems are built on **fundamentally wrong** models, and a new paradigm is needed that takes the Erlang actor model as a natural foundation. **He said there is a need for hardware where every core is an actor.** At the time it seemed unreachable, because **there was no hardware** that natively supported this.

**Now there is.** The CLI-CPU cognitive fabric architecture is the first hardware that **physically makes** the Armstrong vision **possible**. And Neuron OS is the operating system we are building on that hardware.

### The real stakes

If the project reaches F6-F7 and Neuron OS is operational, then **CLI-CPU + Neuron OS together** will be the first physical realization of a new computational paradigm that neither Erlang, nor QNX, nor seL4, nor Singularity could achieve in their own time:

> **The actor model natively in hardware**,
> **faster than a classical shared-memory OS**,
> **far more secure**,
> **formally verifiable**,
> **built for the AI era**,
> **and as the worthy successor to Linux -- not its byproduct.**

This is a future that is still a vision today, but one that is **actually achievable** on **current hardware foundations** (Tiny Tapeout, eFabless, SkyWater, IHP, OpenLane2).

**CLI-CPU is just a chip. Neuron OS is a new era.**

This is the CLI-CPU project's most distant, **most valuable** horizon, and **this is the real stakes**: not building a small bytecode CPU, but **simultaneously laying the hardware and software foundations of a new computational paradigm**, upon which over 10-20 years **an entire ecosystem can be built** -- from embedded systems to AI agent clusters, through game engines to desktop UIs, from critical infrastructure to hardware neural networks.

**When the future looks back at this moment**, the CLI-CPU project may be that small, hobby-scale start from which the operating system of the post-Linux era grew. Just as the 1991 Usenet post by a Finnish student founded a 40-year industry, **the CLI-CPU's 2026 F0 spec documents** may be the foundation of the next 40 years.

**If even 10% of this vision becomes reality, the project will have been a success.**

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
