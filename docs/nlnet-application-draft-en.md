# NLnet NGI Zero Commons Fund — Application Draft

> **Deadline:** June 1, 2026, 12:00 CEST
> **Form:** https://nlnet.nl/propose/
> **Call:** NGI Zero Commons Fund (13th call)
> **Status:** DRAFT — awaiting review

> Magyar verzió: [nlnet-application-draft-hu.md](nlnet-application-draft-hu.md)

> Version: 1.0

---

## Thematic Call

NGI Zero Commons Fund

## Proposal Name

**CLI-CPU: Open Source Cognitive Fabric Processor — Native CIL Execution on Libre Silicon**

## Website / Wiki

https://github.com/FenySoft/cli-cpu

## Abstract

The project has already completed its reference implementation phase (F1.5): a fully tested C# simulator covering all 48 CIL-T0 opcodes (267 passing xUnit tests), a Roslyn-based CIL-T0 linker, and a CLI runner — all developed with strict TDD methodology. **This grant funds the transition from proven software simulation to physical hardware:** RTL, first silicon (Tiny Tapeout), and multi-core FPGA verification.

CLI-CPU is an open-source processor architecture that executes .NET Common Intermediate Language (CIL) bytecode natively in hardware — without JIT compilation, AOT translation, or interpreter layers. Instead of competing on single-core speed (a battle lost by picoJava and Jazelle decades ago), CLI-CPU places many small, independent CIL-native cores on a single chip, communicating exclusively through hardware mailbox FIFOs in a shared-nothing model. This "Cognitive Fabric" architecture eliminates cache coherency overhead entirely, enabling linear scaling with core count.

**The project targets three outcomes within this grant:**

1. **RTL implementation (F2):** Translate the existing, fully tested C# reference simulator (48 CIL opcodes, 267 green tests) into synthesizable Verilog/Amaranth HDL, verified against the simulator using cocotb golden-vector testing.

2. **First silicon (F3):** Tape out a single Nano core + hardware mailbox on a Tiny Tapeout Sky130 shuttle — the project's first physical chip, running Fibonacci(20) and an "echo neuron" demo via UART.

3. **Multi-core FPGA verification (F4):** Demonstrate 4 Nano cores on a MicroPhase A7-Lite XC7A200T FPGA board, communicating via hardware mailboxes in a shared-nothing event-driven fabric — the first proof that the Cognitive Fabric scales.

**Why this matters for the NGI ecosystem:**

- **Libre silicon end-to-end:** Sky130 PDK + OpenLane2 (ASIC) and OpenXC7/Yosys (FPGA) — fully reproducible, auditable, open toolchain.
- **8 million developers' code runs natively:** Every .NET language (C#, F#, VB.NET) compiles to CIL. CLI-CPU is the first hardware that executes this ecosystem's bytecode directly — no runtime overhead, no proprietary toolchain dependency.
- **Actor-native security:** Per-core memory isolation is a physical property of the silicon (private SRAM, no shared memory), not a software abstraction. Immune to Spectre/Meltdown class attacks by architecture, not by mitigation. Deterministic execution enables formal verification of the ISA.
- **European sovereignty:** A fully open processor design that any European entity can manufacture, audit, and certify — independent of US/Asian IP licensing (unlike ARM, RISC-V commercial cores, or x86).

## Have you been involved with projects or organisations relevant to this topic before?

The applicant has extensive experience in:

- **.NET ecosystem:** 20+ years of professional C#/.NET development, including Akka.NET actor systems, Avalonia UI cross-platform applications, and Android/iOS deployment.
- **QuantumAE/JokerQ:** A production Akka.NET actor-based system (55+ actors, NAV-I tax authority integration, NFC smart card communication, offline-first persistence) — this system serves as the real-world validation target for CLI-CPU's actor-native architecture.
- **Hardware-adjacent:** Familiarity with FPGA development workflows, open-source EDA tools, and the Sky130/IHP open silicon ecosystem.

The CLI-CPU project itself has produced 7 architecture documents (~4000+ lines), a fully tested reference simulator, a CIL-T0 linker, and a CLI runner — all developed with strict TDD methodology.

## Requested Amount

**€35,000**

## Explain what the requested budget will be used for

| Milestone | Description | Budget | Timeline |
|-----------|-------------|--------|----------|
| **M1: RTL (F2)** | Verilog/Amaranth HDL implementation of single Nano core. Verilator + cocotb testbench matching all 267 C# simulator tests. Yosys synthesis for Sky130. | €8,000 | Month 1-4 |
| **M2: Tiny Tapeout (F3)** | 16-tile Tiny Tapeout submission: Nano core + mailbox + UART. Bring-up PCB design (KiCad). Post-silicon verification. | €7,000 | Month 4-7 |
| **M3: FPGA multi-core (F4)** | 3× MicroPhase A7-Lite XC7A200T boards (~€960). 4-core Cognitive Fabric on FPGA: shared-nothing, mailbox mesh, sleep/wake, event-driven. Ping-pong and echo-chain demos. | €8,000 | Month 6-10 |
| **M4: Rich core RTL (F5 start)** | Rich core (full CIL) RTL design start: object model, GC assist, exception handling, FPU. Heterogeneous Nano+Rich FPGA demo. | €7,000 | Month 8-12 |
| **M5: Documentation & community** | Architecture documentation in English, contribution guide, CI/CD pipeline, community outreach (blog posts, conference lightning talk). | €5,000 | Ongoing |
| **Total** | | **€35,000** | 12 months |

**Hardware costs included in milestones:**
- 3× A7-Lite XC7A200T FPGA boards: ~€960
- 1× Tiny Tapeout 16-tile submission: ~€1,200
- Bring-up PCB + components: ~€80
- Shipping, cables, adapters: ~€200
- **Hardware subtotal: ~€2,440**

## Describe existing funding sources

The project is currently self-funded by the applicant. No external funding has been received. There are no pending applications to other funding bodies for the same work.

Future complementary funding (not overlapping with this proposal):
- **IHP SG13G2 free MPW:** Application planned for the October 2026 shuttle (F6 heterogeneous silicon — beyond this proposal's scope).
- **Community funding:** GitHub Sponsors / Open Collective will be set up during the project (for ongoing maintenance, not covered by this grant).

## Comparison with existing efforts

| Project | Approach | Limitation | CLI-CPU difference |
|---------|----------|------------|-------------------|
| **RISC-V** (SiFive, etc.) | Open ISA, register machine | Runs compiled C/Rust natively, but .NET requires heavy runtime (JIT/AOT/interpreter) | CLI-CPU runs CIL natively — no runtime layer |
| **ARM Jazelle** (2001) | Java bytecode in HW | Single-core, single-language, shared-memory — JIT became faster | Multi-core, multi-language (.NET), shared-nothing, actor-native |
| **Sun picoJava** (1997) | Java bytecode CPU | Same failure as Jazelle — single-core speed race | CLI-CPU doesn't compete on single-core; wins on parallelism |
| **Intel Loihi 2** | Neuromorphic | Fixed neuron model, not programmable | CLI-CPU cores run arbitrary CIL programs |
| **SpiNNaker 2** | Programmable neuromorphic (ARM cores) | C/C++ only, academic, not .NET native | CLI-CPU: full .NET ecosystem, open source |
| **OpenTitan** | Open source secure element | RISC-V based, single-core, no actor model | CLI-CPU: multi-core, actor-native, .NET programmable |

**No existing open-source project combines:** native CIL execution + multi-core shared-nothing + hardware mailbox + libre silicon + actor-native architecture. CLI-CPU is a new category.

## What are significant technical challenges you expect to solve during the project?

1. **CIL-to-RTL fidelity:** The reference C# simulator defines "golden" behavior for all 48 CIL-T0 opcodes. The RTL must match bit-for-bit. Challenge: the CIL stack machine semantics (variable-length instructions, implicit operand stack) require careful pipeline design. Mitigation: cocotb golden-vector testing against every existing simulator test.

2. **Tiny Tapeout area budget:** The Nano core (~9,100 std cells) + mailbox + UART must fit in 12-16 tiles (~12K-16K gates). Challenge: routing overhead on Sky130 can consume 30-40% of tile area. Mitigation: iterative synthesis with area optimization, starting from Yosys estimates before submission.

3. **Multi-core mailbox routing:** The 4-core FPGA fabric requires a fair, deadlock-free message router. Challenge: ensuring no starvation when multiple cores send simultaneously. Mitigation: round-robin arbiter with per-core FIFO buffers (well-understood design pattern).

4. **QSPI memory latency:** On-chip SRAM is limited (4-16 KB per core). Code and data must be fetched from QSPI flash/PSRAM with 10-50 cycle latency. Challenge: achieving acceptable IPC despite external memory. Mitigation: prefetch buffer for sequential code fetch, TOS (top-of-stack) cache for hot stack data.

5. **Rich core complexity (M4):** The full CIL instruction set (~220 opcodes) requires object model, GC, exceptions, FPU. Challenge: fitting into FPGA LUT budget alongside Nano cores. Mitigation: incremental approach — start with Rich core in isolation, then integrate with Nano fabric.

## Describe the ecosystem of the project

**Upstream dependencies (all open source):**
- Sky130 PDK (SkyWater/Google) — ASIC fabrication
- OpenLane2 (eFabless) — ASIC build flow
- Yosys + nextpnr / OpenXC7 — FPGA synthesis
- Verilator + cocotb — simulation and verification
- .NET SDK (Microsoft, MIT license) — C# simulator, linker, test framework

**Downstream users and stakeholders:**
- **.NET developer community (~8M developers):** Any C#/F# code compiled to CIL can potentially run on CLI-CPU hardware. The Akka.NET and Orleans actor framework communities are natural early adopters.
- **Neuromorphic research community:** CLI-CPU's programmable cores offer a flexible SNN simulation platform, unlike fixed-model chips (Loihi, TrueNorth).
- **IoT / embedded security:** The shared-nothing architecture provides hardware-level isolation without MMU/TrustZone complexity.
- **Open hardware community:** The project contributes a novel CIL-native core design to the libre silicon ecosystem, usable by anyone under CERN-OHL-S-2.0.
- **European digital sovereignty:** A fully open, auditable processor design that can be manufactured at European foundries (IHP SG13G2, GlobalFoundries Dresden) without non-EU IP dependencies.

**Community building plan:**
- GitHub repository with CI/CD (all tests green on every commit)
- English documentation and contribution guide
- Blog posts on technical milestones
- Lightning talk at FOSDEM / ORConf / Tiny Tapeout community meetup
- Monthly progress reports on the project website

---

## Attachments plan

PDF attachment:
1. Architecture overview (excerpt from architecture.md)
2. ISA-CIL-T0 specification summary
3. Roadmap visualization (F0-F7 diagram)
4. Cognitive Fabric One chip vision (benchmark comparison with RISC-V)
5. Current status: 267 tests, simulator, linker, runner screenshots

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
