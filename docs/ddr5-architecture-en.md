---
status: vision
---

# CFPU DDR5 Memory Architecture — Hardware Design Decisions

> Magyar verzió: [ddr5-architecture-hu.md](ddr5-architecture-hu.md)

> Version: 1.6

This document records the **hardware architecture** of the interface between the CFPU and external DDR5 memory. It documents not only the final result, but also the **reasoning trail**: what alternatives were evaluated, why they were rejected, and what trade-offs led to the final decisions.

> **Target audience:** HW developers, RTL designers, FPGA implementors. For the OS-side (Symphact) perspective, see [Symphact docs/ddr5-memory-model-hu.md](https://github.com/FenySoft/Symphact/blob/main/docs/ddr5-memory-model-hu.md).

## Starting Point: What Role Does DDR5 Play in the CFPU?

The CFPU is a **shared-nothing** architecture: every core has its own SRAM (CODE + DATA + STACK), there is no shared memory, no cache coherence. This raises the question: **how do cores access large external datasets** (database, image, ML dataset)?

DDR5 in the CFPU is **not working memory** (as in traditional CPUs), but **storage** from which content is loaded into the cores' SRAM:

- **Code loading** — loading actor code into SRAM CODE
- **Data loading** — loading objects, lookup tables into SRAM DATA
- **Result write-back** — writing processed data back
- **Large datasets** — via scatter/gather, pipeline, chunked streaming patterns

---

## Decision 1: Who Mediates Between Cores and DDR5?

### 1.a) Rejected Solution: Software Gateway Cores

The first idea was that dedicated CFPU cores (gateway actors) mediate between the NoC and the DDR5 PHY — just as any peripheral-handling actor does.

**Why rejected:**

```
Single core mailbox throughput:    ~500 MB/s - 1 GB/s
  (128 bit flit × 500 MHz ÷ ~15 cycles processing per request)

DDR5 2-channel bandwidth:          ~76 GB/s

76 GB/s ÷ 0.5 GB/s = ~150 gateway cores needed
```

150 cores to utilize full bandwidth — and even then, every request pays **two extra NoC hops** (core → gateway → DDR5, DDR5 → gateway → core). Unacceptable.

### 1.b) Rejected Solution: Single Arbiter Core

Next idea: gateway cores handle authorization checks, but a single Arbiter Core manages the PHY.

**Why rejected:** The Arbiter Core itself is a software core, with ~500 MB/s – 1 GB/s throughput. It would utilize ~1% of the DDR5 bandwidth. The bottleneck merely shifted, it didn't disappear.

### 1.c) Final Decision: Hardware RTL DDR5 Controller

The DDR5 Controller is **not a programmable core**, but a **fixed RTL block** connected to the NoC as an endpoint. Its 128-bit ports directly accept requests from cores.

**Decision rationale:**
- DDR5 scheduling (row activation, bank interleaving, refresh timing) is **time-critical, fixed logic** — not suited for a general-purpose core
- The 128-bit data path natively matches the NoC flit size
- No software bottleneck on the path
- HW capability checking (see below) operates at zero cycle overhead

### DDR5 Controller Architecture (v1.3)

```
                     NoC (128 bit wide)
                      |
        +-------------+-------------+
        |             |             |
     port 0        port 1    ...  port 9
        |             |             |
+-------+-------------+-------------+-------+
| DDR5 Controller (RTL, not programmable)    |
|                                            |
|  10 x 128 bit port @ 500 MHz              |
|  = 10 x 8 GB/s = 80 GB/s                  |
|  ~ DDR5 2ch full bandwidth                |
|                                            |
|  +-----------+  +------------+  +--------+ |
|  | DDR5_CAP  |  | Bank-aware |  | PHY    | |
|  | check     |->| Scheduler  |->| Iface  |->--> DDR5
|  | (~100 GE) |  | (HW FSM)   |  +--------+ |
|  +-----------+  +------------+              |
|       ^                                     |
|       | flag and range/perms check          |
|       | (token in payload, already HW-      |
|       |  attached at source core)           |
|                                             |
| Config port <-- Seal Core / root_supervisor |
| (hardwired, keyless, permission only)       |
+---------------------------------------------+
```

**The capability data does NOT reside in the DDR5 Controller.** The Controller only checks the incoming cell's `flags.DDR5_CAP` bit and the region/offset/perms triplet arriving in the payload. The capability **resides in the source core's QRAM**, and the source core's HW request assembler attaches it to the request.

---

## Decision 2: How Do We Prevent a Core from Reading/Writing Another Core's Data?

This is the critical question for the shared-nothing model. If any core can read any DDR5 address, isolation is an **illusion**.

### 2.a) Identifying the Sender — NoC Header src + src_actor

The NoC router **fills in the flit header `src` (24 bit) and `src_actor` (8 bit) fields in hardware** with the sending core's physical identifier and active actor context register. The sending core's software **cannot override this** (see `interconnect-hu.md` v3.2 + `cell-format-hu.md` v2.4).

```
NoC cell --> DDR5 Controller port
+---------------------------------+
| src[24]:        14 bit  <-- HW   |
| src_actor[8]:   8 bit   <-- HW   |
| dst:            DDR5 ctrl        |
| flags.DDR5_CAP: 1       <-- HW   |
| payload[0..15]: capability bytes |
| payload[16..]: offset, op, data  |
+---------------------------------+
```

**Analogy:** Like the physical MAC address in networking — the switch knows which port the frame came from, not from the frame's content.

### 2.b) Authorization Check — HW Capability Slot (QRAM)

In v1.2, this was done by a large CAM table in the DDR5 Controller. The **CAM size showed scaling problems** (see alternatives 5.b and 5.d). In v1.3, capabilities are **stored in the source core's QRAM**, and the HW request assembler attaches them to the request. The DDR5 Controller only checks the bounds — **no central table, no HMAC**.

#### Capability Slot Format (8 bytes = 64 bits)

```
+---------------------------------------------------+
| Bit 63..32:  region_base[32]   4 KB-aligned        |
|                                page number → 16 TB |
| Bit 31..24:  reserved[8]       base ext-able to 40b |
| Bit 23..8:   region_size[16]   in 4 KB pages        |
|                                → max 256 MB         |
| Bit 7:       valid                                 |
| Bit 6..4:    perms[3]          R / W / X (X: below) |
| Bit 3..0:    reserved (4 bits)                     |
+---------------------------------------------------+
```

The controller reconstructs the actual byte address as `(region_base << 12) + offset` and checks the bound as `offset < (region_size << 12)` — the slot is **fully page-granular** (4 KB), except the `valid`/`perms` bits.

**Full page granularity — why?** Since **two actors never share a page**, isolation is inherently page-level, so both `region_base` AND `region_size` are expressed in 4 KB pages. No sub-page sharing → no need for byte-precise bounds (reading into the slack of one's own last page is not a cross-actor leak, only intra-actor).

Decision trail:

| Field | Alternative | Chosen |
|-------|-------------|--------|
| `region_base` | byte-36 (64 GB, under) / byte-40 (1 TB, +slot) | **page-32 → 16 TB** (in the 8-byte slot) |
| `region_size` | byte-24 (16 MB, granularity mismatch) / byte-16 (64 KB) | **page-16 → 256 MB** (consistent, no page-share) |

The `reserved[8]` next to the base holds room for a future **40-bit page → 4 PB** extension. The core ISA stays **32-bit regardless** — `region_base` is a descriptor (data), not a pointer dereferenced by the core (see below).

**The `perms` X (execute) bit:** for **Seal-verified code only** (e.g., already-verified code cached in DRAM to speed up slow flash). **Running runtime-generated / unverified code is FORBIDDEN** — no signature → no trust. ⚠️ Its relationship to [decision 6](#code-data-separation) (»DDR5 is primarily data«) and the integrity mechanism of the cached code (tamper protection post-verification) is an **OPEN question** — requires a separate decision.

**Storage:** **per core, in QRAM (Quench-RAM)**, under SEAL invariant.

| Parameter        | Value                               |
| ---------------- | ----------------------------------- |
| Slots per actor  | 256 (`slot_id[8]`)                  |
| Actors per core  | 256 (see v3.0 header)               |
| Slot size        | 8 bytes                             |
| Slot table / core | 256 × 256 × 8 bytes = **512 KB**? — TOO MUCH |
| **Realistic allocation** | **4 slots per actor** = 256 × 4 × 8 bytes = **8 KB / core** |

In the realistic model, each actor gets **at most 4 DDR5 capability slots** (4 concurrent regions — more than enough for typical workloads). If an actor needs more, it can dynamically reassign its slots through `kernel_io_sup`.

**Stored data:**
```
slot_table[actor_id][slot_id] = {region_base, region_size, perms, valid}
                                                        ^
                                                Quench-RAM under SEAL:
                                                  - Only Seal Core can write (RELEASE+re-SEAL)
                                                  - Actor SW cannot read directly
                                                  - HW request assembler can read (read-only path)
```

#### Request Flow

```
Actor CIL-T0 code:
   ddr5_load  slot_id=N, offset=0x100, dest=R5

HW instruction decoder (at the source core):
1. QRAM read:     slot[active_actor][N] = (region_base, size, perms, valid)
2. Valid check:   valid == 1?         (1 cycle)
3. Offset check:  offset < size?      (1 cycle, combinational)
4. Perms check:   op permitted?       (1 cycle, combinational)
5. Cell assembly (HW, NOT software):
     header.flags.DDR5_CAP = 1   <-- HW-only writable bit
     payload[0..7]   = (region_base, size, perms)
     payload[8..11]  = offset_in_region
     payload[12..]   = op + data
6. NoC cell --> DDR5 Controller
```

#### DDR5 Controller Validation

The controller checks the following on the incoming cell:

```
1. flags.DDR5_CAP == 1?
   - NO  → trap (legacy software-as-DMA, already rejected model)
   - YES → 2.

2. (region_base + offset) < region_base + region_size? (sanity check)
   (the source core already checked, but the controller re-checks for defense-in-depth)

3. op permitted? (perms check)

4. PASS  → to DDR5 PHY (through Bank-aware Scheduler)
   FAIL → trap flit to sender (InvalidMemoryAccess)
```

**Why no HMAC?** The capability bytes **never reach software**. The QRAM lives under SEAL, the HW request assembler reads it, and the `flags.DDR5_CAP` bit guarantees that the first 8 bytes of the payload are **HW-attached** (not SW-written). If actor software attempts to manually assemble a cell with the `DDR5_CAP` bit, the NoC router at the source core **filters** this bit — only the HW assembler can set it (see 2.c).

### 2.c) HW Gate-keep — `DDR5_CAP` Flag Bit

One bit in the cell header `flags` field (`flags.DDR5_CAP`) is **writable only by the source core's HW request assembler**:

| Component                          | Can write DDR5_CAP? |
| ---------------------------------- | ------------------- |
| Actor CIL-T0 SW (`send` opcode)    | ❌ filtered (HW masks to 0) |
| HW request assembler (`ddr5_load`) | ✓ can set it        |
| NoC router (forwarding)            | ✓ forwards, does not modify |
| DDR5 Controller (validation)       | read-only, does not write |

The HW filter is ~10 gates / core (a simple AND-mask in the actor's `send` cell assembler).

### 2.d) Revocation — Quench-RAM RELEASE

Capability revocation builds on the Quench-RAM SEAL/RELEASE pattern:

```
Seal Core: RELEASE(slot[actor_id][N])
   → atomic wipe: the slot is physically zeroed (1 cycle)
   → invariant: from this moment the HW assembler CANNOT assemble a request
                with this slot (valid==0, fail-stop)
```

**Speed:** 1 cycle (slot zero-write). No epoch, no window, no broadcast — Quench-RAM is atomic.

**In-flight requests:** If there is already a DDR5 request on the NoC at the moment of slot RELEASE, it passes through (the controller already received the payload). This is **acceptable**: the actor logically sees it as if the RELEASE happened slightly later. Revocation **feasibility** is guaranteed, **strict atomicity** is not (similar to TLB shootdown in traditional OSes).

### 2.e) Who Configures the Slots?

Capability slots can **only be written by the Seal Core**, upon request from the `kernel_io_sup` actor. The flow:

```
1. Actor    → kernel_io_sup: MsgGrantRequest(region, size, perms)
2. kernel_io_sup: policy check, quota, isolation
3. kernel_io_sup → Seal Core: via dedicated hardwired config port
                              "write slot[actor][N] = (region, size, perms)"
4. Seal Core: in the target core's QRAM:
              RELEASE(slot[actor][N])    ← atomic wipe
              SEAL(slot[actor][N] = new capability)
5. kernel_io_sup → Actor: MsgGranted(slot_id=N)
6. Actor: ddr5_load slot=N, offset=..., dest=...
```

**Why not over the NoC?** If config commands went over the NoC, any compromised core could send a forged config message. The dedicated physical wire from the Seal Core to each core's QRAM guarantees that **only the Seal Core** can write slots.

---

## Decision 3: How Does an Actor Get DDR5 Access?

### 3.a) Rejected Solution: Central Mediator for Every Request

The first idea was that a Memory Service actor mediates every DDR5 read/write request. The actor sends a message requesting data, the Memory Service performs the DDR5 operation, and sends back the result.

**Why rejected:** Every single DDR5 access would have required **three messages** (request → service → DDR5, DDR5 → service → response). This triples latency and halves throughput.

### 3.b) Rejected Solution: root_supervisor Decides Every Load

Next idea: the `root_supervisor` (OS) schedules when and what to load into the core's SRAM — DMA-style, in stream mode.

**Why rejected:** The `root_supervisor` cannot know when and what data the actor needs. Only the actor itself knows what object it wants to process.

### 3.c) Final Decision: Capability Slot — One-Time Grant, Free Use

The actor **requests a slot once** from the `kernel_io_sup` actor. Once granted, it **freely and directly** reads/writes the DDR5 region using `ddr5_load`/`ddr5_store` opcodes, without further authorization:

```
1. Actor             → kernel_io_sup: MsgGrantRequest(ObjectId, Access: RW)
2. kernel_io_sup checks, then:
   kernel_io_sup     → Seal Core (config port): write slot to target core's QRAM
   Seal Core         → target core QRAM: SEAL(slot[actor][N] = (region, size, perms))
3. kernel_io_sup     → Actor: MsgGranted(slot_id=N)
4. Actor: freely reads/writes (ddr5_load/store --> NoC --> DDR5 Controller --> DDR5)
   ... as many times as needed, without further authorization
5. Actor             → kernel_io_sup: MsgReleaseRegion(slot_id=N)
6. kernel_io_sup     → Seal Core: RELEASE(slot[actor][N])
   Seal Core         → target core QRAM: atomic wipe
```

**Single owner** — only one actor at a time can have rights to a given region. Until Actor 7 releases it, no other actor can get access to the same region. (Rust ownership analogy.)

**Decision rationale:**
- The actor itself decides when it needs data — not the kernel scheduling it
- The authorization request is a one-time cost (message round-trip) — after that, zero overhead
- The capability is revocable: if the actor finishes or crashes, `kernel_io_sup` RELEASEs the slot

---

## Decision 4: Stream Mode vs. Request Mode

The DDR5 Controller supports two modes, because there are two fundamentally different usage patterns:

### Request Mode — Actor Actively Working with a DDR5 Region

The actor, after receiving the slot, directly reads/writes with `ddr5_load`/`ddr5_store` opcodes. In any order, any number of times.

**When:** During active processing — the actor knows what it wants to read/write.

### Stream Mode — Bulk DMA Transfer

The DDR5 Controller sequentially reads/writes large blocks and **pushes** them toward cores over the NoC. The stream command is also capability-based: `kernel_io_sup` grants a special stream-slot that authorizes a large, sequential region.

**When:**
- Initial data loading into SRAM DATA
- Result write-back to DDR5

> **Note:** Code loading does **not** happen from DDR5. Authenticated code is stored in **SealFlash** (non-volatile) and **SealRAM** (volatile cache) — see the [Code and Data Storage Separation](#code-data-separation) section.

**Why both?** Stream mode maximally exploits DDR5 burst (sequential reads), but the actor doesn't always work sequentially. Request mode is flexible, but DDR5 burst utilization is weaker. The combination covers the real workflow: stream-load, request-process, stream-write-back.

---

## Addressing Model: Capability Segmentation and >4 GB Data

> **Status:** the capability slot widening (2.b) and the low-level primitives (`ddr5_load`/stream) are finalized; the high-level programmer lowering (streaming abstraction → chunk-stream) is **design intent** (CFPU toolchain, F2/F3), not a finished feature.

### The mechanism: capability-based segmentation

The `slot_id + offset` addressing is structurally a descendant of **segmentation** (DS/CS): the slot provides a base (`region_base`), the offset is added to it. The reason for the choice is **not programmer convenience** — a managed runtime (.NET) hides **any** memory model, flat or segmented alike (.NET forbids the raw cross-object pointer arithmetic that would expose it). The real reasons are two:

1. **HW-enforced isolation.** A capability is not a bare base but `base + size + perms + valid`, QRAM-protected, HW-attached, unforgeable → this is the foundation of hardware isolation between actors, which the runtime alone could not guarantee against a compromised actor.
2. **Area.** Protection has to live somewhere: x86 had segmentation AND paging — it kept paging (flat + per-page) and dropped segmentation. The CFPU does the reverse: it **drops the MMU/paging** (a full MMU + TLB + page-walk × thousands of cores = too much area) and provides isolation via **capability segmentation** — cheaper per core → more cores fit (see [`microarch-philosophy-en.md`](microarch-philosophy-en.md): TLP > ILP).

### >4 GB data: descriptor, not pointer

The core ISA stays **32-bit**. Nobody accesses >4 GB data via a flat pointer:

- The wide physical address (`region_base`) is a **descriptor (data)** that software computes and passes along — not a pointer it dereferences. A 32-bit core can compute with a 40-bit descriptor (multi-word) because it never dereferences it; the actual access is performed by the **controller**.
- The **OS/runtime** (`kernel_io_sup`) knows the full dataset's location/size (TB scale) and **chunks** it for streaming/partitioning. It thus manages TBs on 32-bit cores.
- The **actor** sees only its own ≤256 MB window (`region_size[16]`, in 4 KB pages), with a 32-bit bounded offset, ~256 KB at a time in local SRAM.

### Programmer model (design intent)

The programmer writes a **streaming/windowed abstraction** (idiomatic .NET — `foreach`, `Span`, LINQ), and the toolchain/runtime generates the chunk transitions (new grant, `region_base` advance) — the source code does not juggle the "segment". This is the difference from the DOS-era `far`-pointer model, where segment handling leaked into the source. (A managed runtime would hide classic DS/CS too — so the distinction is not ergonomic, see above.)

### The irreducible limit

One case **no runtime can hide**: random access over a single >4 GB flat structure (e.g., a 10 GB hash table with scattered access). Here flat-64 hardware genuinely wins; the capability/streaming model pays a grant round per chunk transition. The CFPU **deliberately concedes** this workload class — it optimizes for partitionable/streamable load (system throughput is the metric, not single-thread random latency).

---

## Decision 5: Where Should the Capability Table Live?

This is the main architectural question of v1.3. Five alternatives were evaluated:

### 5.a) Rejected: Software Capability Service (Memory Service Actor)

See 3.a). Throughput bottleneck, 3× latency.

### 5.b) Rejected: Central CAM Table in the DDR5 Controller (v1.0–v1.2 Model)

Every capability entry in a large CAM, checked per port.

**Calculation:**
- Max entries: 10,240 cores × 256 actors × 1 grant = **2.6 million**
- Realistic (10–50%): 260K–1.3M entries
- Per entry: ~21 bytes (key + region + perms)
- Total CAM: **~21 MB** at 1M entries
- Per port × 10 ports: **~210 MB CAM** (replicated) or shared (latency contention)

**Industry references:** Cisco router TCAMs are in the tens-of-MB range, **in dedicated ASIC chips**. On-chip CPU CAMs are 1K–16K entries. A 1M+ entry on-chip CAM **would occupy 10–20% of the die** at 5nm.

**Why rejected:** unrealistically large. The v1.0–v1.2 model's scaling failure.

### 5.c) Rejected: Capability Token + HMAC (CHERI/seL4 Pattern)

The actor receives a 16-byte token at grant time (region + perms + epoch + HMAC). The token is stored in its own SRAM, and attached to every DDR5 request. The controller validates with HMAC.

**Why rejected:** HMAC is necessary when the token **reaches software** (because actor SW could modify it). In the CFPU, however, Quench-RAM SEAL exists — slots can be kept in HW-managed QRAM where actor SW **cannot write** (5.d). HMAC is then redundant crypto overhead; HW guarantees alone are sufficient.

**HW cost (saved):** ~3,250 gates / port × 10 ports = ~32,500 gates (SipHash-128 engine + epoch logic). Small, but unnecessary.

### 5.d) Rejected: Per-Core CAM, in the Central DDR5 Controller

10,240 cores × 1 entry/core × 21 bytes = ~215 KB CAM. Manageable in size, but:
- Only core-level ACL, **no actor-level isolation**
- Other actors on the same core also get access if any actor has a grant

**Why rejected:** violates the actor-level isolation principle (`interconnect-hu.md` v3.0 CST model is actor-level, this must be preserved).

### 5.e) **Final Decision: HW Capability Slot in the Source Core's QRAM**

The capability table is **not** in the DDR5 Controller, but **per core, in QRAM**, under SEAL invariant. The HW request assembler reads it, and the `flags.DDR5_CAP` bit guarantees HW-attachment.

**Cost:**
- Per core: ~8 KB QRAM (256 actors × 4 slots × 8 bytes) — allocated within SRAM per `core-types-hu.md`
- Per core: ~500 gates (HW request assembler + filter)
- Per DDR5 controller port: ~100 gates (range + perms check)
- × 10 ports: ~1,000 gates
- × 10,240 cores: ~5.1 M gates (assembler) + ~84 MB QRAM total — but **per-core, local**, not centralized → **not a scaling problem**

**Why this choice:**
- **Scales:** slot storage is per-core, a chip cannot fail just from slot count
- **Actor-level isolation:** the slot table is indexed by actor_id
- **No crypto:** Quench-RAM SEAL is sufficient
- **Atomic revocation:** Quench-RAM RELEASE
- **Consistent with the v3.0 CST model:** same philosophy (HW-managed capability), separate implementation

**Security ultimately rests on the Seal Core's integrity.** This is guaranteed by the Seal Core's HW FSM (not microcode, not programmable): it protects the boot process with signature verification, and monitors the operation of `root_supervisor` and `kernel_io_sup` with a watchdog.

---

## Capacity Summary

```
10 ports x 128 bit x 500 MHz = ~5 billion requests/sec
DDR5 2ch bandwidth:              ~76 GB/s = ~4.75 billion x 16 byte requests/sec
```

| Access frequency / core | Serviceable cores |
|------------------------|-------------------|
| Every cycle            | ~10               |
| Every 100th cycle      | ~1,000            |
| Every 1000th cycle     | ~10,000 (full chip)|

CFPU cores work from SRAM, typically falling in the "every 1000th cycle" category — **the 10-port DDR5 Controller can serve the entire chip**.

---

## General Peripheral Handling Pattern

The DDR5 Controller design decisions provide a **general pattern** for other peripherals as well:

**Rule:** if the peripheral's bandwidth approaches a single core's throughput (~500 MB/s), a **hardware RTL controller** is needed. If it's well below that, a **software gateway actor** will suffice.

| Peripheral | Bandwidth | Solution | Rationale |
|------------|-----------|----------|-----------|
| DDR5 (2ch) | ~76 GB/s | **HW Controller, multi-port, RTL + capability slot** | Core cannot serve it |
| NVMe (x4) | ~8 GB/s | HW Controller, 1-2 ports + capability slot | Near core's limit |
| 10G Ethernet | ~1.25 GB/s | Gateway core (software) | Fits within a single core |
| USB / SPI / I2C | ~MB/s | Gateway core (software) | Easily fits |

For low-bandwidth peripherals, the gateway core is **physically wired** to the PHY (MMIO, hardwired). No other core can reach it — there is no physical path.

In all cases, the same security model applies:
- **src + src_actor** is hardware-identified in the NoC
- **HW capability slot** (for high bandwidth) or **gateway actor authorization check** (for low bandwidth)
- **Slot configuration** exclusively through the Seal Core (`kernel_io_sup` policy-based)

## Code and Data Storage Separation <a name="code-data-separation"></a>

### Decision 6: Where Is Authenticated Code Stored?

#### 6.a) Rejected Solution: Code and Data Together in DDR5

The first idea was that DDR5 stores code as well (loaded via stream mode into the core's SRAM CODE region).

**Why rejected:** DDR5 access is managed by `kernel_io_sup` — a software actor. If compromised, it could grant RW access to the code region, allowing an attacker to overwrite code. The integrity of DDR5-stored code depends on software trust, not hardware guarantees.

#### 6.b) Rejected Solution: QRAM (Quench-RAM) for Code Storage

Quench-RAM has per-block status bits with SEAL/RELEASE semantics — excellent for per-core data protection (use-after-free prevention, atomic wipe, zero-init guarantee). But for code storage it's **overkill**: code doesn't need per-block seal/release cycles, just simple read-only protection.

#### 6.c) Final Decision: SealRAM / SealFlash

Two new memory types that are **standard SRAM/Flash**, but their Write Enable (WE) line is **physically wired to the Seal Core**:

```
                     NoC (128 bit wide)
                      |
        Core read requests (MsgCodeRead)
                      |
              +-------+--------+
              | SealRAM / SealFlash Controller (RTL) |
              |                                      |
              |  NoC port: READ ONLY                 |
              |    - accepts: MsgCodeRead(addr)       |
              |    - responds: NoC flit (code data)   |
              |    - write request: REJECTED (trap)   |
              |                                      |
              |  WE port: Seal Core (hardwired)       |
              |    - physical wire                    |
              |    - NOT reachable via NoC            |
              +-------+--------+
                      |
                      | WE line (hardwired, not NoC)
                      |
                +-----+-----+
                | Seal Core  |
                | (HW FSM)   |
                +------------+
```

Cores **request code via NoC messages** — there is no direct bus. The Controller is a NoC endpoint that:
- **Accepts read requests** from any core (no ACL, because the code is authenticated and shared)
- **Rejects write requests from the NoC** — the controller simply doesn't implement them
- **Writes exclusively via the WE line** — a physical wire from the Seal Core

| Type | Memory | Volatility | Role |
|------|--------|------------|------|
| **SealFlash** | Standard NOR Flash | Non-volatile (persists) | **Persistent storage** of authenticated code |
| **SealRAM** | Standard SRAM | Volatile (lost on power-off) | Fast code cache (loaded from SealFlash at boot) |

**Decision rationale:**
- **Zero custom IP required** — standard memory, only the WE wiring is special
- **Hardware guarantee** — write access is not decided by software, but by silicon topology
- **Not hackable** — there is no software path to the WE line, the Seal Core is a HW FSM (not microcode)
- Compromising the `root_supervisor` doesn't help — the Seal Core is an independent, hardware entity

**Full code loading path:**

```
Update:
  Signed code package --> Seal Core (HW signature verification) --> SealFlash write

Boot:
  Seal Core --> SealFlash --> SealRAM (copy, cache)

Runtime:
  Core SRAM CODE <-- SealRAM (NoC read, anyone can read)
```

**By default, no code is stored in DDR5.** This means DDR5 compromise can only affect data, not code — the attack surface is architecturally reduced.

> ⚠️ **Open question (v1.5):** the capability slot `perms` X bit reserves a future case where **Seal-verified code may be cached in DRAM** (to speed up slow flash). This is in tension with the "by default, no code" principle above. The reconciliation — and the **integrity mechanism** for the cached code (tamper protection post-verification, e.g. W⊕X) — is **not yet decided**. Until then, DDR5 stores **data only**; running runtime-generated / unverified code is **FORBIDDEN in all cases**.

### Three Memory Types Summary

| | SealRAM / SealFlash | QRAM (Quench-RAM) | DDR5 |
|---|---|---|---|
| **Content** | Authenticated code | Per-core data (objects, **DDR5 capability slots**) | Working data, large datasets |
| **Who can write** | Seal Core only (HW) | SEAL/RELEASE HW FSM trigger | Actor, with capability slot |
| **Protection type** | Physical WE line | Per-block status bit | **HW capability slot** (in per-core QRAM, under SEAL) + `flags.DDR5_CAP` HW-only bit |
| **Trust root** | Seal Core (HW FSM) | Seal Core + HW FSM | **Seal Core (manages capability slots)** + `kernel_io_sup` (policy) |
| **Spec** | This document | `docs/quench-ram-hu.md` | This document |

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.6 | 2026-07-17 | **Stale cell-format reference updated:** `cell-format-hu.md` v2.1 → **v2.4** (cascade from the current spec). |
| 1.5 | 2026-06-02 | **Capability slot full page granularity + perms X clarification.** `region_size` is now also **byte → 4 KB page-granular** (16-bit → 256 MB max region), with **`reserved[8]`** next to the base for a future 40-bit page (4 PB) extension. Rationale: since **two actors never share a page** (user decision), isolation is page-level → byte-precise size is unnecessary (it would have been an intra-actor bug-catcher, not isolation). New layout: `region_base[32] + reserved[8] + region_size[16] + valid[1] + perms[3] + reserved[4]`. **`perms` X bit:** for **Seal-verified code only** (DRAM-as-flash-cache); **runtime-generated code FORBIDDEN** (not authenticatable). ⚠️ The X bit's relationship to decision 6 (»DDR5 = data«) + the cached-code integrity mechanism is **OPEN**. The bit format lives only here + in quench-ram-en.md (sweep confirmed). |
| 1.4 | 2026-06-01 | **Capability slot: `region_base` 36-bit byte address → 32-bit page-aligned (4 KB) → 16 TB.** The earlier 36-bit (64 GB) is under-provisioned for today's capacities (128 GB consumer RAM, 1+ TB server/accelerator horizon). Page alignment yields 16 TB in the same 8-byte slot (32+24+1+3=60 bits). Decision trail: byte-36 (under) / byte-40 (larger slot) / **page-32 (chosen)**. **New "Addressing Model" section:** (1) the `slot_id + offset` is capability-based **segmentation** — the real justification is HW isolation + area (NOT ergonomics, since a managed runtime hides any model, including classic DS/CS); (2) >4 GB data is a **descriptor (data), not a pointer** — the core ISA stays 32-bit, the wide address lives in the controller/capability, the OS chunks and streams it; (3) programmer model = streaming lowering (**design intent**, F2/F3); (4) irreducible limit: random access over a >4 GB flat structure — flat-64 wins here, the CFPU deliberately concedes it. Core ISA stays 32-bit. |
| 1.3 | 2026-04-28 | **CAM table → HW Capability Slot (in QRAM).** Instead of the 21 MB central CAM rejected in 5.b: each core's QRAM holds an 8 KB capability slot table (256 actors × 4 slots × 8 bytes), managed by Seal Core SEAL/RELEASE. New `flags.DDR5_CAP` HW-only header bit on the cell (only the source core's HW request assembler can set it, actor SW cannot). The 5.c capability token + HMAC alternative also rejected (HMAC is redundant when Quench-RAM SEAL gate-keep is sufficient). New decision trail: 5.a–5.e (software / CAM / HMAC token / per-core CAM / **HW Capability Slot**). Revocation = QRAM RELEASE (atomic, 1 cycle). Memory summary table DDR5 row updated. **Rationale:** central CAM doesn't scale on-chip, Quench-RAM and the v3.0 CST model provide a pattern for a stateless, HW-only capability mechanism |
| 1.2 | 2026-04-24 | src_actor field narrowed from 16→8 bits (max 256 actors/core), consistent with the CST model and interconnect specs. |
| 1.1 | 2026-04-22 | SealRAM / SealFlash introduced for code storage, DDR5 = data only. Three memory types summary table. |
| 1.0 | 2026-04-22 | First version — DDR5 Controller decision process, security model, capability grant, peripheral handling |
