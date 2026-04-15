# CLI-CPU Blog Series Plan

> Internal planning document — not published on the website.

## Strategy

- **Language:** English (international reach), with Hungarian translations on clicpu.org
- **Platform:** clicpu.org/en/blog/ + clicpu.org/hu/blog/ + Medium
- **Cadence:** One article per week
- **Goal:** Build awareness, GitHub stars, community, support NLnet application

## Planned Articles

| # | Title | Target Audience | Status |
|---|-------|----------------|--------|
| **1** | Why I'm Building a CPU That Runs .NET Natively | Everyone — the big picture | Published |
| **2** | 24 Cores, Zero Cache Coherency: How Shared-Nothing Beats Multi-Threading | CPU architecture enthusiasts | Planned |
| **3** | From 250+ Tests to Silicon: Test-Driven Hardware Development | .NET / software developers | Planned |
| **4** | Hardware-Level Security Without Mitigations: Why Spectre Can't Touch This | Security audience | Planned |
| **5** | The Neuron OS Vision: Why Linux's 1970s Architecture Needs a Successor | OS / systems programmers | Planned |
| **6** | 8 Million .NET Developers, One Hardware Platform: Every Language, Native Silicon | .NET community | Planned |

## Article #2 — Outline

**Title:** 24 Cores, Zero Cache Coherency: How Shared-Nothing Beats Multi-Threading

- The cache coherency tax (15-20% of die area on traditional CPUs)
- Why adding cores has diminishing returns with shared memory
- CLI-CPU's shared-nothing model: private SRAM, hardware mailbox FIFOs
- The math: 6R+16N+1S on 15mm² vs 4-8 RISC-V cores on same area
- Linear scaling: why it matters for actor workloads
- Benchmarks we plan to measure (actor msg/sec, context switch, SNN throughput)

## Article #3 — Outline

**Title:** From 250+ Tests to Silicon: Test-Driven Hardware Development

- TDD in software is normal — TDD in hardware is rare
- How we wrote 250+ C# tests BEFORE writing any Verilog
- The golden vector approach: cocotb tests vs C# simulator
- Why this matters: confidence that the RTL matches the spec
- The Fibonacci(20) = 6,765 end-to-end test

## Article #4 — Outline

**Title:** Hardware-Level Security Without Mitigations: Why Spectre Can't Touch This

- The Spectre/Meltdown family: 7+ years of patches, 5-30% performance loss
- Why mitigations are a losing game
- CLI-CPU's approach: eliminate the attack surface, don't patch it
- No speculative execution, no branch predictor, no shared cache
- The Secure Core: dedicated trust anchor for code verification
- ROP/JOP impossible by ISA design
- Formal verification: why a small ISA matters

## Article #5 — Outline

**Title:** The Neuron OS Vision: Why Linux's 1970s Architecture Needs a Successor

- Linux inherited 1970s Unix decisions: shared memory, fork/exec, POSIX
- Why these don't scale to 1000+ cores
- The Erlang/OTP model: 40 years of proof that actors work
- Neuron OS: everything is an actor, hardware-enforced isolation
- Let it crash + supervision: fault tolerance from architecture
- Hot code loading: zero-downtime updates

## Article #6 — Outline

**Title:** 8 Million .NET Developers, One Hardware Platform

- CIL is an international standard (ECMA-335, ISO/IEC)
- Every .NET language compiles to CIL: C#, F#, VB.NET
- F# as the "perfect CLI-CPU language" (immutable, pattern matching, actors)
- Why RISC-V + .NET AOT isn't the same thing
- The vision: native silicon for the .NET ecosystem

## Medium Tags

Use these tags for all articles:
- `dotnet`
- `cpu-architecture`
- `open-source`
- `fpga`
- `hardware-security`
