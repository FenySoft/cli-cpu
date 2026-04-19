# Cognitive Fabric — Vision: The Shared-Nothing Future

> Magyar verzio: [vision-hu.md](vision-hu.md)

This document explores what happens when we **redesign the entire software stack** around the **Cognitive Fabric Processing Unit (CFPU)** hardware model — operating system, GUI, database, networking, programming model. Instead of measuring the hardware by today's software, we design the software to fit the hardware.

> *CFPU is the official name for the Cognitive Fabric architecture. **CLI-CPU** is its first open-source reference implementation — see [FAQ #1](faq-en.md#1-what-is-the-cfpu-and-how-does-it-relate-to-cli-cpu) for details.*

> **Joe Armstrong, creator of Erlang, 2014:**
> *"Current software systems are built on fundamentally flawed models. We need hardware where every core is an actor."*

---

## Today's software: an imprint of hardware limitations

Modern software architecture is not a law of nature — it is a consequence of specific hardware constraints:

| Today's convention | Why it exists | The real reason |
|---|---|---|
| **Central kernel** | Someone needs to coordinate shared resources | Because **shared memory exists** |
| **Mutex / lock** | Two threads must not write the same data | Because **shared memory exists** |
| **Single UI thread** | The GUI framework is not thread-safe | Because **shared memory exists** |
| **B-tree index** | Fast lookup on a single disk | Because **there is a single storage device** |
| **Async/await** | Do not block a thread waiting for I/O | Because **there are few threads** |
| **Virtual memory** | Process isolation | Because **shared memory exists** |
| **GPU** | The CPU cannot draw enough pixels | Because **there are few cores** |

**Remove shared memory and add 1000+ cores: every one of these conventions becomes unnecessary.**

---

## 1. The future operating system — No kernel

### Today: the kernel as a central dictator

```
┌─────────────────────────────────────┐
│           User Space                │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐    │
│  │App 1│ │App 2│ │App 3│ │App 4│    │
│  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘    │
│─────┼───────┼───────┼───────┼───────│ ← syscall boundary (expensive!)
│     ▼       ▼       ▼       ▼       │
│  ┌─────────────────────────────┐    │
│  │          KERNEL             │    │
│  │  scheduler, VFS, TCP/IP,    │    │
│  │  memory manager, driver...  │    │
│  │  ONE HUGE PROGRAM           │    │
│  │  THAT COORDINATES EVERYTHING│    │
│  └─────────────────────────────┘    │
│           Kernel Space              │
└─────────────────────────────────────┘

The kernel exists because someone has to GUARD
the shared memory. That is 50+ years of complexity.
Linux kernel: ~40 million lines of code (2025, v6.14).
(Source: https://www.stackscale.com/blog/linux-kernel-surpasses-40-million-lines-code/)
```

### Neuron OS: peer actors, hardware isolation

```
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│Core 0│ │Core 1│ │Core 2│ │Core 3│ │Core 4│ │Core 5│
│      │ │      │ │      │ │      │ │      │ │      │
│ sup. │→│ app  │→│ app  │→│ uart │→│ file │→│ net  │
│      │ │ actor│ │ actor│ │device│ │device│ │device│
└──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘
   └────────┴────────┴────────┴────────┴────────┘
                  Mailbox Router
              (NO kernel, no syscall)

No "kernel space" vs "user space" — because there is no shared memory
to protect. Every actor is PHYSICALLY isolated.
Isolation is not software-based (MMU + page table) — it is HARDWARE-BASED.
```

### What does this gain?

| Aspect | Today (Linux/Windows/macOS) | Neuron OS |
|---|---|---|
| Syscall overhead | ~1-5 us (mode switch) | **~5-20 ns** (mailbox message) |
| Kernel bug impact | System crash | Supervisor **restarts** the faulty actor |
| Kernel size | ~40M lines (Linux) | **~5K lines** Neuron OS core |
| Isolation type | Software (MMU + page table) | **Hardware** (physical SRAM) |
| Hot code reload | Impossible (kernel restart) | **Native** — actor code is swappable at runtime |
| Boot time | ~1-30 seconds | **~1-10 us** (no init, no driver scan) |

**The 40 million lines of the Linux kernel exist because shared memory must be protected in software.** If the hardware guarantees isolation, the kernel's **purpose disappears**.

Details: [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md).

---

## 2. The future GUI — No single UI thread

### Today: everything on one thread; if anything is slow, everything stutters

Every GUI framework (WPF, SwiftUI, Flutter, Qt, Avalonia) is built around a single main thread:

```
  ┌──────────────────────────────┐
  │     SINGLE UI THREAD         │  ← EVERYTHING happens here
  │                              │
  │  • Event dispatch            │
  │  • Layout calculation        │
  │  • Data binding              │
  │  • Animation tick            │
  │  • Rendering commands        │
  │                              │
  │  If ANYTHING is slow → the   │
  │  ENTIRE UI stutters (16ms    │
  │  budget!)                    │
  └──────────┬───────────────────┘
             ▼
  ┌──────────────────────────────┐
  │          GPU                 │
  │  Rasterization, composition  │
  └──────────────────────────────┘
```

**Why a single thread?** Because the scene graph (the widget tree) is **shared mutable state** — if two threads modify it simultaneously, things break. Protecting it with mutexes would be too slow. So every framework invented the `Dispatcher.Invoke()` / `InvokeOnMainThread()` / `runOnUiThread()` anti-pattern.

### Actor GUI: every widget is an actor

```
  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
  │Toolbar │  │Sidebar │  │Content │  │Status  │
  │ actor  │  │ actor  │  │ actor  │  │ actor  │
  │        │  │        │  │        │  │        │
  │ own    │  │ own    │  │ own    │  │ own    │
  │ layout │  │ layout │  │ layout │  │ layout │
  │ render │  │ render │  │ render │  │ render │
  └───┬────┘  └───┬────┘  └───┬────┘  └───┬────┘
      │           │           │           │
      └─────┬─────┴─────┬─────┘           │
            ▼           ▼                 ▼
  ┌──────────────────────────────────────────┐
  │         Compositor actor                │
  │  (merges the regions, ~1 core)          │
  └──────────────────────────────────────────┘

No UI thread bottleneck. Every widget computes its layout
and renders its own region IN PARALLEL.
```

### In practice

| Today (single UI thread) | Actor GUI |
|---|---|
| 60 FPS = 16ms / frame **for everything** | 60 FPS = 16ms / frame **per region** |
| Complex list (10K items) → scroll stutters | Each item is its own actor → **parallel layout** |
| Animation + data loading → UI freezes | Animation actor is **independent** of the data actor |
| `Dispatcher.Invoke()` anti-pattern | **Does not exist** — there is no "main thread" |
| GPU required for rasterization | **1000 Nano cores** are the "GPU" — vector rendering in an actor mesh |

### GPU-free rendering — the numbers

Today the GPU is needed because a single CPU core cannot draw enough pixels within 16ms. But what if 1000 cores draw, each handling a piece of the screen?

```
1920x1080 = ~2M pixels / frame
1000 Nano cores = ~2000 pixels / core / frame

2000 pixels x 32 bit color = ~8 KB processing
@ 3 GHz x 0.4 IPC = ~1.2 GIPS → ~6.7 us / core

Uses ~7 us out of a 16ms frame budget = ~0.04%
Plenty of room. Software rendering without a GPU,
but with HARDWARE parallelism.
```

This does not mean the GPU is useless — texturing, 3D, ML inference still need it. But **2D vector GUI** (the way every business application, OS interface, and dashboard looks) can be **handled without a GPU, using a Nano core actor mesh**.

---

## 3. The future database — No locks, no B-tree

### Today: shared buffer pool, locks everywhere

```
┌─────────────────────────────────┐
│        Shared Buffer Pool       │  ← EVERY transaction writes here
│  ┌─────┐ ┌─────┐ ┌─────┐        │
│  │Page1│ │Page2│ │Page3│ ...    │  B-tree pages, in shared memory
│  └──┬──┘ └──┬──┘ └──┬──┘        │
│     │ LOCK  │ LOCK  │ LOCK      │  ← MVCC / 2PL / mutex
│  ┌──┴───────┴───────┴───┐       │
│  │  WAL (Write Ahead    │       │
│  │  Log) — sequential   │       │
│  │  writes to a single  │       │
│  │  file                │       │
│  └──────────────────────┘       │
└─────────────────────────────────┘

The performance bottleneck: LOCK CONTENTION in the buffer pool.
The WAL is a single sequential stream → bottleneck.
```

### Actor database: every partition is an actor

```
  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
  │ users   │  │ orders  │  │ products│  │ logs    │
  │ actor   │  │ actor   │  │ actor   │  │ actor   │
  │         │  │         │  │         │  │         │
  │ private │  │ private │  │ private │  │ private │
  │ SRAM    │  │ SRAM    │  │ SRAM    │  │ SRAM    │
  │ index   │  │ index   │  │ index   │  │ index   │
  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
       │            │            │            │
       └──── query actor ←── SQL parser actor
              (JOIN = message between the two table actors)

NO locks — each table actor processes its own messages
sequentially. Consistency = message ordering.
NO WAL — the message log IS the event log.
```

### What does this gain?

| Aspect | Today's RDBMS (PostgreSQL) | Actor DB |
|---|---|---|
| INSERT latency | ~5-50 us (WAL + buffer lock + fsync) | **~50-500 ns** (SRAM write) |
| Lock contention | Degrades with core count | **0** — no shared state |
| Horizontal scaling | Complex (replication, sharding) | **Trivial** — new partition = new actor |
| Event sourcing | Separate framework (EventStore, Marten) | **Native** — the message log is the data |
| CQRS | Architectural pattern, software-level | **Natural** — read actor + write actor |
| JOIN | On shared buffer pool | **Message** between table actors, pipelined |
| Replication | WAL shipping, complex | **Message forwarding** — copies the actor's messages |

**The relational model does not die** — the query language (SQL) and relational algebra remain valuable. What dies is the **shared buffer pool + lock + WAL** implementation. The actor model delivers **the same relational semantics**, without locks.

---

## 4. The future network — No kernel TCP/IP stack

### Today: 80% overhead in the kernel

```
Application
    ↓ syscall (~1-5 us)
Kernel socket layer
    ↓ copy (~0.5-2 us)
TCP/IP stack (kernel)
    ↓ copy (~0.5-2 us)
NIC driver
    ↓
Hardware

Processing one packet: ~3-10 us
~80% of that is kernel overhead (mode switch, copy, lock).
```

### Actor network: every protocol layer is an actor

```
┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐
│ NIC     │→ │ TCP     │→ │ HTTP     │→ │ App      │
│ device  │  │ actor   │  │ parser   │  │ handler  │
│ actor   │  │         │  │ actor    │  │ actor    │
└─────────┘  └─────────┘  └──────────┘  └──────────┘
    Mailbox →   Mailbox →   Mailbox →   Mailbox

Processing one packet: ~20-100 ns (4x mailbox hops)
No syscall, no copy, no kernel.
Every layer is an actor, pipelined.
```

This is the **Erlang/BEAM telecom model, but in hardware**. The Ericsson AXD 301 switch (1998) achieved 99.9999999% (nine nines) uptime in Erlang — in software, on an Erlang VM, on top of x86. CLI-CPU implements the same model in hardware, ~100x faster.

### The performance difference

| | x86 + Linux kernel TCP/IP | CLI-CPU actor pipeline |
|---|---|---|
| Packet latency | ~3-10 us | **~20-100 ns** |
| Packet throughput (1 core) | ~1-5M pkt/s (without DPDK) | **~30-100M pkt/s** |
| Kernel bypass (DPDK) needed? | Yes, complex | **No kernel, nothing to bypass** |

---

## 5. The future programming model — No async/await

### Today: the "function color" problem

```csharp
// The biggest pain point of modern C# development
async Task<User> GetUserAsync(int id)
{
    var data = await _db.QueryAsync("SELECT...");
    var profile = await _cache.GetAsync(data.Key);
    return new User(data, profile);
}

// If ANY caller forgets the await → bug
// If you change ANY layer from sync to async
//   → EVERY caller must be rewritten
// Two worlds: sync and async — incompatible
// This is the "What Color is Your Function?" problem (Bob Nystrom, 2015)
```

### Actor model: no function color

```csharp
// Everything is a message, everything is synchronous within the actor
class UserActor : Actor
{
    void OnGetUser(int id, ActorRef replyTo)
    {
        var data = Ask(dbActor, new Query("SELECT..."));
        var profile = Ask(cacheActor, new Get(data.Key));
        replyTo.Tell(new User(data, profile));
    }
}

// No async/await — NO function color problem.
// Every call is synchronous WITHIN the actor.
// Parallelism exists BETWEEN actors.
// No race condition — the actor processes one message at a time.
```

**Why does this work?** Because `Ask()` **does not block the core** — the scheduler switches to another actor until the reply arrives. The switching cost is ~10-60 cycles, not ~1-5 us.

### Programming model comparison

| Aspect | Today's C# (async/await) | Actor model (Neuron OS) |
|---|---|---|
| Unit of concurrency | Thread / Task | **Actor** |
| Synchronization | lock, Mutex, SemaphoreSlim | **None** — messages |
| Shared state | Explicit protection (lock) | **None** — private state |
| Async/await needed? | Yes, everywhere | **Does not exist** |
| Race condition | Possible, hard to debug | **Impossible** |
| Deadlock | Possible (lock ordering) | **Impossible** (no locks) |
| Testability | Mocks, integration tests | **Deterministic message replay** |

---

## 6. The big picture — the layers disappear

```
Today's world (7 layers):              CLI-CPU world (1 layer):

┌─────────────────────┐             ┌─────────────────────┐
│ App (C#/Java/Go)    │             │                     │
│ async/await         │             │  Actors (C#)        │
├─────────────────────┤             │  synchronous msgs   │
│ Framework (ASP.NET) │             │                     │
│ thread pool         │             │  ← no boundary      │
├─────────────────────┤             │  every actor        │
│ OS kernel (Linux)   │             │  is a peer          │
│ syscall, scheduler  │             │                     │
├─────────────────────┤             │  no kernel          │
│ TCP/IP stack        │             │  no syscall         │
│ socket API          │             │  no scheduler       │
├─────────────────────┤             │  (HW FIFO poll)     │
│ Filesystem (ext4)   │             │                     │
│ B-tree, WAL, lock   │             │  no lock            │
├─────────────────────┤             │  no B-tree          │
│ Hardware (x86)      │             │  no WAL             │
│ shared memory       │             │  no cache coher.    │
│ cache coherence     │             │  no VMM             │
│ MMU, TLB            │             │                     │
└─────────────────────┘             └─────────────────────┘

7 layers, each with                  1 layer:
its own complexity,                  actors send messages.
interfaces, overhead.                The hardware supports it natively.
```

Every layer boundary is an **abstraction tax**: syscall overhead, copy overhead, lock contention, context switch. On CLI-CPU, these boundaries **disappear**, because the single primitive — the message — lives in hardware.

---

## 7. The inverted metrics

Where CLI-CPU is at a disadvantage today, redesigning the software stack **flips the advantage**:

| Area | Today: CLI-CPU disadvantage | With rethought software: CLI-CPU ADVANTAGE |
|---|---|---|
| **Desktop app** | ~20x slower single-thread | Actor GUI: **parallel layout/render**, no UI thread bottleneck |
| **Database** | No shared memory for SQL | Actor DB: **lock-free**, ~100x faster INSERT, native event sourcing |
| **Web server** | Low IPC | 1 request = 1 actor: **~80M req/s** in an actor pipeline |
| **Filesystem** | No block device driver | Every file/dir is an actor: **parallel I/O**, no VFS lock |
| **Network** | No kernel TCP/IP | Actor pipeline: **~100x lower latency**, no kernel copy |
| **Development** | Unknown platform | **No async/await**, no locks, no race conditions — **simpler code** |

---

## 8. Why has nobody done this before?

**Because the hardware did not exist.**

The idea is not new — Erlang/BEAM has used the actor model since 1986, and Ericsson's telecom infrastructure proved it works. But Erlang runs **in software**, on top of x86 — paying the shared-memory overhead.

Academic experiments (MIT Alewife, Stanford DASH, Tilera TILE-Gx) demonstrated that many-core, message-passing architectures are possible — but all were **register machines**, not managed runtimes, and their programming model remained C/C++.

CLI-CPU is the first attempt where:
1. **The hardware natively supports the actor model** (mailbox FIFO, sleep/wake, shared-nothing)
2. **The programming language is managed** (CIL/.NET — GC, type safety, verification)
3. **The entire stack can be redesigned** (Neuron OS, actor GUI, actor DB — we are not emulating x86)

These three elements together **did not exist before** — and the vision rests on the premise that **all three must be present simultaneously**, or we fall back into the shared-memory model.

---

## 9. The road ahead

The vision does not materialize all at once. The development phases (`docs/roadmap-hu.md`) build it up incrementally:

| Phase | Software vision element | Status |
|---|---|---|
| **F1-F1.5** | C# reference simulator + linker + runner | **DONE** |
| **F2** | RTL — the hardware is born | Next |
| **F3** | Tiny Tapeout — first physical chip | — |
| **F4** | Multi-core FPGA — first actor system, scheduler + router | — |
| **F5** | Rich core — full C#, heterogeneous Nano+Rich | — |
| **F6** | Cognitive Fabric — 32-48 cores on FPGA, the vision becomes demonstrable | — |
| **F7** | Neuron OS SDK — first developers can write actor GUI, actor DB | — |

After F7, the vision elements are built **incrementally**: actor GUI toolkit, actor database engine, actor network stack. Each one in **C#**, built on the Neuron OS API, and each one **open source**.

The goal is not to replace Linux or PostgreSQL — but to create a **new category** where the actor model is the natural primitive, and developers can write software in C# that fits the hardware.

---

## References

- [`docs/architecture-en.md`](architecture-en.md) — microarchitecture, pipeline, memory model, heterogeneous Nano+Rich design
- [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md) — detailed Neuron OS vision, actor API, supervisor tree, scheduler, hot code reload
- [`docs/roadmap-en.md`](roadmap-en.md) — F0-F7 phase plan
- [`docs/faq-en.md`](faq-en.md) — FAQ 5-7: CPU comparison, scheduling costs, fair benchmarking
- [`docs/security-en.md`](security-en.md) — security model, formal verification plan
- [`docs/secure-element-en.md`](secure-element-en.md) — Secure Edition, multi-domain hardware isolation
