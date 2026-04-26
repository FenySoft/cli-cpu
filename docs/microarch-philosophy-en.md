# CFPU Microarchitecture Philosophy

> Magyar verzió: [microarch-philosophy-hu.md](microarch-philosophy-hu.md)

> Version: 1.0

> **⚠️ Vision-level document.** This analysis records the theoretical architectural direction formulated during the F1.5 phase (reference simulator + linker). Numerical estimates are extrapolations from documented precedents (picoJava-2, Cerebras WSE, Adapteva Epiphany, Tilera, Groq, SpiNNaker), **not RTL-level measurements**. Actual performance, area, and power figures can only be validated after F4 RTL and F6 silicon (Cognitive Fabric One MPW) — until then every number is a working hypothesis subject to revision at each roadmap phase.

## Thesis

The CFPU microarchitectural philosophy in a single sentence:

> **We do not maximize ILP within a core; we maximize TLP across cores.**

Every transistor we would spend making a single core "smarter" (Out-of-Order, deep pipeline, dynamic branch predictor, register rename, speculative execution) is a transistor missing from another core. Modern OS workloads are naturally **thousands of threads**; the CFPU distributes them across cores at a **1:1 or near-1:1 ratio** — sacrificing single-thread speed for core count.

This aligns with the `feedback_security_first.md` priority (security > area > speed): speculative execution opens the door to Spectre/Meltdown-class attacks, and auditability (Seal core) demands a deterministic pipeline.

## The data point that motivates the thesis

### Modern iMac workload (snapshot, 2026-04, M-class chip)

| Metric | Value |
|---|---|
| Processes | 930+ |
| Threads | 4,300+ |
| Physical cores | 10–12 (4 P + 6–8 E) |
| Thread/core ratio | **~360–430** |
| Active threads at any moment (estimate from Activity Monitor 5–15% idle) | ~50–150 |

Most of the 4,300 threads are **blocked** — waiting on I/O, mailbox, timer, or GUI events. But even if only ~100 threads are running at any moment, the 12 cores must rotate among them with a 10 ms quantum.

### Conventional approach: few OoO cores with time-slicing

- 4,300 threads / 12 cores = 360 threads/core
- 10 ms quantum, scheduler manages a complex priority queue
- Partial cache thrash (L1/L2 invalidation) on every context switch
- Modern Linux scheduler-overhead in literature: ~3–8% system time on pure scheduling
- Each additional thread strictly **degrades** core utilization

### CFPU approach: many in-order cores with persistent affinity

- 4,300 threads / ~300 Rich cores = ~14 threads/core
- Active thread / core: **<1**
- **Every active thread gets its own core, no preemption**
- Blocked threads do not physically occupy a core — they wait passively in an SRAM-frame for a mailbox message
- Hardware router dispatches incoming messages to idle cores → **scheduler role ~0**

The difference is not gradual but categorical: on the CFPU, single-core *efficiency* matters less because the workload is inherently parallel.

## Alternatives — decision trail

### A) Few cores + strong OoO/ILP (x86, Apple M, ARM Cortex-A75+)

- ~70 cores in 100 mm², each at 4-IPC OoO
- Aggregate: ~280 instructions/cycle
- **Speculative execution**: Spectre/Meltdown-class attack surface
- Determinism is lost → audit is impossible
- Cache coherence protocol (MOESI/MESIF) required → expensive, does not scale

**Rejected.** Reasons:
- The `feedback_security_first.md` priority excludes speculation
- Seal core auditability requires a deterministic pipeline
- For multi-task workloads, per-core IPC matters less than aggregate

### B) Many cores + in-order, static ILP (CFPU choice; Cerebras, Groq, Tenstorrent, Adapteva, SpiNNaker)

- ~300 Rich cores in 100 mm², each at ~1.2-IPC in-order
- Aggregate: ~360 instructions/cycle (when the Linker has paired what it can)
- Speculation excluded → side-channel free
- Linker is responsible for instruction-level parallelism (EPIC-style pair-bit + macro-op fusion)
- Deterministic pipeline → every instruction cycle-accurately predictable

**Selected.** Reasons:
- Consistent with the security-first priority
- Naturally pairs with the many-core, actor-model approach
- Linker-level optimization is cheaper in an open source project than dynamic HW

### C) Massive cores + minimal ISA (Cerebras WSE-3 style extreme)

- ~10,000+ cores in 100 mm², each trivial
- Aggregate is enormous, but the ISA is too poor for general C# code
- Ideal for specialized workloads (ML inference, neuron simulation)
- Not suitable for general-purpose execution

**Partially adopted.** The Nano core embodies this spirit (48 opcodes, int32, 0.005 mm² at 5nm); but Rich/Actor cores are retained for general .NET code so the CFPU runs **both** profiles on a single substrate.

## What we do not build

The "do not build" list is as important as the "do build" list:

- **No Out-of-Order Execution** (recorded in branch B of the decision trail above)
- **No speculative execution** — not even branch prediction based on dynamic history tables
- **No register rename engine** — any stack→reg translation is purely decode-time, static
- **No reorder buffer**, scheduler queue, or retire stage
- **No deep pipeline** (>5–7 stages)
- **No SMT** — one core runs one thread at a time (the warm-context cache provides actor-level switching on mailbox arrival, see `core-types-hu.md`)

## What we do build — static ILP in the Linker

Instruction-level parallelism comes not from dynamic reordering, but statically, generated at the `CilCpu.Linker` level:

1. **Macro-op fusion at decode** — common 3–4-instruction patterns (e.g. `ldloc + ldloc + add`) packed into a fused opcode. The HW recognizes them; `.t0` binary compatibility is preserved.
2. **Linker pair-bit annotation** — a flag between two consecutive instructions indicating they may issue in parallel (EPIC style). This is the inverse of the Itanium lesson: less HW speculation, smarter compiler.
3. **In-order N-wide pipeline** — 2-wide in Rich, 1-wide in Nano/Actor/Seal. If the Linker paired them and there is no hazard → 2 issues/cycle, otherwise 1.
4. **TOS register stack** — 16–32 registers as a physical stack frame, not SRAM. Eliminates the port bottleneck (see `internal-bus-hu.md`).
5. **Static branch hint** — Linker decides forward/backward likely (profile-guided or heuristic); HW prefetches based on a single bit. Dynamic history tables are **absent**.
6. **Wide internal bus** — 256/512/1024 bit per core type; context move in 1–3 cycles.

All of these are **deterministic, auditable** techniques — every instruction cycle-accurately predictable, side-channel free.

## Throughput estimate (estimate, not measurement)

| Configuration | Cores | Per-core IPC | Aggregate IPC | Wall-clock on 4300-task workload |
|---|---|---|---|---|
| Apple M3/M4 Pro (12 OoO) | 12 | ~4.0 | 48 | Reference (1×) |
| ARM Cortex-A75 many-core (70× OoO 3-IPC, same area) | 70 | ~3.0 | 210 | ~4× |
| **CFPU Rich (300× in-order 1.2-IPC)** | **300** | **~1.2** | **360** | **~7×** (assuming clock parity) |
| **CFPU mixed (Rich+Actor+Nano, ~1,000× cores)** | 1,000 | ~0.8 average | 800 | **~15×** |

**Correction factors to consider:**

- **Clock difference**: M-chip ~4 GHz, CFPU target ~1.5–2 GHz → 2–3× compensation against the CFPU
- **Memory bandwidth**: CFPU is shared-nothing → DRAM controller demand grows with core count
- **Workload character**: 4,300 tasks is only valid if all tasks are mutually independent; a strict dependency chain (purely sequential algorithm) does not benefit

Net: the CFPU is **expected to deliver 2–5× higher aggregate throughput on multi-task workloads** in the same die area, modulo clock and memory-system compensation.

> **This is an estimate, not a measurement.** Validatable only after F4 RTL and F6 silicon.

## Validation plan

The thesis can only be proven step by step:

1. **F1.5 (now)** — simulator-level dynamic instruction count measurement on `samples/PureMath` benchmarks. Result: instruction count ratio versus RV32 equivalent (Spike emulator).
2. **F2 / F2.7 (FPGA)** — Rich core RTL prototype on A7-Lite 200T, cycle-accurate performance. Result: actually measured IPC, clock domain validated.
3. **F4 (multi-core RTL)** — a 16-core cluster + interconnect, 4,300-thread simulated workload. Result: aggregate throughput, scheduler-overhead ratio.
4. **F6 (silicon)** — Cognitive Fabric One MPW (15 mm², 6R+16N+1S), real workload, real power, real area. Result: empirical confirmation or refutation of the thesis.

The thesis **can only be conclusively proven with F6 silicon.** Until then every number is a working estimate.

## Related documents

- [`core-types-en.md`](core-types-en.md) — the 4 core types, all in-order with static ILP
- [`internal-bus-en.md`](internal-bus-en.md) — bus sizing to eliminate the context-move bottleneck
- [`interconnect-en.md`](interconnect-en.md) — inter-core communication: mailbox + router, lock-free
- [`security-en.md`](security-en.md) — security-first priority that excludes speculative execution
- [`perf-vs-riscv-en.md`](perf-vs-riscv-en.md) — methodology for single-thread perf comparison
- [`architecture-en.md`](architecture-en.md) — overall CFPU architecture

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-25 | Initial version — TLP > ILP thesis, decision trail (few-OoO vs many-in-order vs minimal), 4,300-thread iMac data point, static ILP components, validation plan F1.5 → F6 |
