# NLnet NGI Zero Commons Fund — Application Draft

> **Deadline:** June 1, 2026, 12:00 CEST
> **Form:** https://nlnet.nl/propose/
> **Call:** NGI Zero Commons Fund (13th call)
> **Status:** SUBMITTED (v1.1 as filed). Documentation updated post-submission to introduce CFPU naming — see Changelog.

> Magyar verzió: [nlnet-application-draft-hu.md](nlnet-application-draft-hu.md)

> Version: 1.2

---

## Thematic Call

NGI Zero Commons Fund

## Proposal Name

**CLI-CPU: Open Source Cognitive Fabric Processing Unit (CFPU) — Native CIL Execution on Libre Silicon**

## Website / Wiki

https://github.com/FenySoft/cli-cpu

## Abstract

The project has already completed its reference implementation phase (F1.5): a fully tested C# simulator covering all 48 CIL-T0 opcodes (250+ passing xUnit tests), a Roslyn-based CIL-T0 linker, and a CLI runner — all developed with strict TDD methodology. **This grant funds the transition from proven software simulation to physical hardware:** RTL, first silicon (Tiny Tapeout), and multi-core FPGA verification.

CLI-CPU is the open-source reference implementation of the **Cognitive Fabric Processing Unit (CFPU)** — a new category of processing unit that executes .NET Common Intermediate Language (CIL) bytecode natively in hardware, without JIT compilation, AOT translation, or interpreter layers. Alongside the familiar *CPU / GPU / TPU / NPU* family, the CFPU is the first **MIMD actor-native** processing unit: many small, independent CIL-native cores on a single chip, communicating exclusively through hardware mailbox FIFOs in a shared-nothing model. Instead of competing on single-core speed (a battle lost by picoJava and Jazelle decades ago), the CFPU architecture eliminates cache coherency overhead entirely, enabling linear scaling with core count.

**The project targets three outcomes within this grant:**

1. **RTL implementation (F2):** Translate the existing, fully tested C# reference simulator (48 CIL opcodes, 250+ green tests) into synthesizable Verilog/Amaranth HDL, verified against the simulator using cocotb golden-vector testing.

2. **First silicon (F3):** Tape out a single Nano core + hardware mailbox on a Tiny Tapeout Sky130 shuttle — the project's first physical chip, running Fibonacci(20) and an "echo neuron" demo via UART.

3. **Multi-core FPGA verification (F4):** Demonstrate 4 Nano cores on a MicroPhase A7-Lite XC7A200T FPGA board, communicating via hardware mailboxes in a shared-nothing event-driven fabric — the first proof that the Cognitive Fabric scales.

**Why this matters for the NGI ecosystem:**

- **Libre silicon end-to-end:** Sky130 PDK + OpenLane2 (ASIC) and OpenXC7/Yosys (FPGA) — fully reproducible, auditable, open toolchain.
- **8 million .NET developers can target this hardware using familiar tools:** Every .NET language (C#, F#, VB.NET) compiles to CIL. The Nano core runs the CIL-T0 integer subset natively; the Rich core (F5+) will extend to full CIL with objects, GC, and FPU. No JIT, no interpreter, no runtime layer.
- **Actor-native security:** Per-core memory isolation is a physical property of the silicon (private SRAM, no shared memory), not a software abstraction. The shared-nothing architecture eliminates cross-core side-channel attack surface by design (no shared cache, no speculative execution, no branch predictor). Deterministic execution enables formal verification of the ISA.
- **European sovereignty:** A fully open processor design that any European entity can manufacture, audit, and certify — independent of US/Asian IP licensing (unlike ARM, RISC-V commercial cores, or x86).
- **Concrete use case:** Secure IoT edge node running Akka.NET actor workloads with per-core hardware isolation — eliminating traditional TEE/TrustZone complexity while providing stronger guarantees.

- **Growing relevance of hardware-level security:** As personal data breaches, infrastructure attacks, and AI-driven threats escalate, software-only security measures are increasingly insufficient. CLI-CPU's hardware-enforced memory safety, type safety, and control flow integrity cannot be bypassed by any software exploit — making it increasingly relevant for both current and future security challenges in personal devices, critical infrastructure, and IoT.

**Why now?** The convergence of open PDKs (Sky130, IHP SG13G2), mature actor-model frameworks (Akka.NET, Orleans), the end of Dennard scaling pushing towards many-core architectures, the democratization of silicon (Tiny Tapeout, eFabless), and the growing urgency of hardware-level security against escalating cyber threats makes a many-core bytecode-native approach viable and necessary in 2026 where single-core picoJava failed in 1997.

## Have you been involved with projects or organisations relevant to this topic before?

The applicant has 35+ years of professional software and hardware experience:

- **Hardware foundations (1980s):** Z80 computer design and assembly programming (hobby/college level), later 8086/80286 assembly + Pascal projects, then C/C++ on Windows. This early hardware experience directly informs the CLI-CPU microarchitecture design.
- **National-scale production systems (1990s–2026):** As part of a 3-person team, developed "Atlasz" — a railway dispatch control system for MÁV (Hungarian National Railways), used in **national traffic management until 2026**. Also developed Visual Restaurant, Visual Hotel & Restaurant (Delphi, later .NET) — a hospitality management suite distributed by Com-Passz Kft., widely used in the Hungarian restaurant and hotel industry — including a .NET-based mobile waiter terminal (embedded .NET + hardware integration).
- **.NET ecosystem (20+ years):** Professional C#/.NET development including mandatory government data reporting integrations (NAV tax authority, NTAK tourism), market API integrations (Wolt, Fooddora, falatozz.hu, D-EDGE, iBar), Akka.NET actor systems, Avalonia UI cross-platform applications, and Android/iOS deployment.
- **Hungarian Tax Control Unit:** Hardware development experience from the original Adóügyi Ellenőrző Egység (Tax Control Unit) project — **sole developer** of all software. The current **QCassa/JokerQ** is a modern, PQC-secured successor (55+ Akka.NET actors), also **developed solo** as a .NET software + hardware integration project under regulation 8/2025 NGM. This project provides deep hands-on experience with actor-model architecture and .NET hardware integration that directly informs CLI-CPU's design decisions.
- **CLI-CPU RTL:** Preliminary Verilog RTL development already underway — ALU module with full cocotb testbench (41/41 passing tests). Working knowledge of open-source EDA tools (Yosys, Verilator, cocotb) and the Sky130/IHP open silicon ecosystem.

The CLI-CPU project itself has produced 7 architecture documents (~4000+ lines), a fully tested reference simulator, a CIL-T0 linker, and a CLI runner — all developed with strict TDD methodology.

The project has been in focused development since early April 2026, building a solid technical foundation before public announcement. The NLnet grant would fund the first fully public phase, including community outreach and conference presentations.

## Requested Amount

**€35,000**

## Explain what the requested budget will be used for

| Milestone | Description | Budget | Timeline |
|-----------|-------------|--------|----------|
| **M1: RTL (F2)** | Verilog/Amaranth HDL implementation of single Nano core. Verilator + cocotb testbench matching all C# simulator tests (250+). Yosys synthesis for Sky130. | €8,000 | Month 1-6 |
| **M2: Tiny Tapeout (F3)** | 16-tile Tiny Tapeout submission: Nano core + mailbox + UART. Bring-up PCB design (KiCad). Post-silicon verification. | €7,000 | Month 5-10 |
| **M3: FPGA multi-core (F4)** | 3× MicroPhase A7-Lite XC7A200T boards (~€960). 4-core Cognitive Fabric on FPGA: shared-nothing, mailbox mesh, sleep/wake, event-driven. Ping-pong and echo-chain demos. | €8,000 | Month 8-14 |
| **M4: Rich core RTL (F5 start)** | Rich core (full CIL) RTL design start: object model, GC assist, exception handling, FPU. Heterogeneous Nano+Rich FPGA demo. | €7,000 | Month 12-18 |
| **M5: Documentation & community** | Architecture documentation in English, contribution guide, CI/CD pipeline, community outreach (blog posts, conference lightning talk). | €5,000 | Ongoing |
| **Total** | | **€35,000** | 18 months |

**Hardware costs included in milestones:**
- 3× A7-Lite XC7A200T FPGA boards: ~€960
- 1× Tiny Tapeout 16-tile submission: ~€1,200
- Bring-up PCB + components: ~€80
- Shipping, cables, adapters: ~€200
- **Hardware subtotal: ~€2,440**

Personnel: ~18 months part-time (~900 hours), €32,560 / 900h ≈ €36/hour. Hardware: €2,440.

## Describe existing funding sources

The project is currently self-funded by the applicant. No external funding has been received. There are no pending applications to other funding bodies for the same work.

Future complementary funding (not overlapping with this proposal):
- **IHP SG13G2 free MPW:** Application planned for the October 2026 shuttle (F6 heterogeneous silicon — beyond this proposal's scope).
- **Community funding:** GitHub Sponsors / Open Collective will be set up during the project (for ongoing maintenance, not covered by this grant).

**Sustainability plan:** (1) Follow-up NLnet proposal for F5-F6 (Rich core + silicon tape-out). (2) IHP SG13G2 free MPW application for research-grade silicon. (3) Long-term: dual licensing model (CERN-OHL-S for open version, commercial license for certified products). (4) GitHub Sponsors / Open Collective for ongoing community maintenance.

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

2. **Tiny Tapeout area budget:** The Nano core (~9,100 std cells) + mailbox + UART must fit in 12-16 tiles (~12K-16K gates). Challenge: routing overhead on Sky130 can consume 30-40% of tile area. Mitigation: iterative synthesis with area optimization, starting from Yosys estimates before submission. Plan B: If the design does not fit in 16 tiles after routing, we will reduce to Nano core + UART only (without mailbox), verifying the mailbox on FPGA (M3) instead.

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
- Visual Studio Code / Code - OSS (MIT license) — primary development environment, extensible with C#, Verilog, and cocotb tooling

**Downstream users and stakeholders:**
- **.NET developer community (~8M developers):** Any C#/F# code compiled to CIL can potentially run on CLI-CPU hardware. The Akka.NET and Orleans actor framework communities are natural early adopters.
- **Neuromorphic research community:** CLI-CPU's programmable cores offer a flexible SNN simulation platform, unlike fixed-model chips (Loihi, TrueNorth).
- **IoT / embedded security:** The shared-nothing architecture provides hardware-level isolation without MMU/TrustZone complexity.
- **Open hardware community:** The project contributes a novel CIL-native core design to the libre silicon ecosystem, usable by anyone under CERN-OHL-S-2.0.
- **European digital sovereignty:** A fully open, auditable processor design that can be manufactured at European foundries (IHP SG13G2, GlobalFoundries Dresden) without non-EU IP dependencies.

**Note on .NET independence:** The CIL specification (ECMA-335) is an international standard ratified by ISO/IEC, not proprietary to Microsoft. CLI-CPU targets the bytecode format, not the Microsoft runtime. Alternative CIL producers exist (Mono, various Roslyn-independent front-ends). The hardware design operates at the ISA level and is independent of any upstream runtime changes.

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
5. Current status: 250+ tests, simulator, linker, runner screenshots

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.2 | 2026-04-16 | **Post-submission doc update only** — introduced "Cognitive Fabric Processing Unit (CFPU)" naming in title and abstract. The submitted application (v1.1) did not use the CFPU abbreviation. Technical content, budget, milestones unchanged. |
| 1.1 | 2026-04-14 | **SUBMITTED version.** Timeline 18 months, €35K with all 5 milestones, hourly rate, test count 250+, RTL experience, sustainability plan, Why now, ECMA-335 independence, concrete use case, Plan B for TT |
| 1.0 | 2026-04-14 | Initial version |
