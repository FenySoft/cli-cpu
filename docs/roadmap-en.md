# CLI-CPU — Roadmap

> Magyar verzió: [roadmap-hu.md](roadmap-hu.md)

> Version: 1.1

The CLI-CPU project is built in **seven phases**, from the specification document to the first working, hand-held silicon and beyond, to a full ECMA-335 CIL implementation.

## Guiding Principles

1. **Spec first, code second.** Every phase starts with a document or a precise requirements list. No "we'll figure it out along the way."
2. **TDD for every software layer.** Both the simulator and RTL are tested — tests are derived from spec requirements, not retrofitted to the implementation.
3. **One golden reference.** The F1 C# simulator **is the golden reference** — every subsequent RTL (F2, F4, F5) reproduces this behavior, verified via cocotb/golden-vector comparison.
4. **Expand from the bottom up.** F0–F3 cover the "clean, narrow" CIL-T0 subset. F4–F6 only proceed once the foundation is solid.
5. **Real silicon early.** F3 (Tiny Tapeout) is the project's first "tangible" milestone — feature coverage may be incomplete, but it **exists physically**.

## Phases

### F0 — Specification

**Goal:** Documents from which the entire project can be built without making design decisions on the fly.

**Output:**
- `docs/roadmap.md` — this document
- `docs/architecture.md` — CLI-CPU architecture: stack machine, pipeline, memory model, prior art
- `docs/ISA-CIL-T0.md` — full CIL-T0 subset specification (~40 opcodes)

**Done criteria:** After reading the three documents, an outside engineer can tell *exactly* what each CIL opcode does on the CLI-CPU and how it fits into the microarchitecture.

---

### F1 — C# Reference Simulator — **DONE**

**Goal:** A bit-accurate, TDD-developed software CLI-CPU simulator with a dedicated xUnit test for every CIL-T0 opcode.

**Platform:** .NET 10, C# 13, xUnit.

**Output:**
- `src/CilCpu.Sim/` — simulator library (fetch, decode, execute) — **done**
- `src/CilCpu.Sim.Tests/` — xUnit test project — **done, 218 green tests**

**Done criteria — met:**
- 100% opcode coverage with tests — all 48 CIL-T0 opcodes have dedicated tests
- A Fibonacci(20) CIL-T0 binary compiled from C# runs correctly on the simulator — `Fibonacci(20) = 6765` green
- The simulator **traps on everything** the spec prescribes (stack overflow, invalid branch target, invalid memory access, call depth exceeded, etc.)
- Developed via TDD across 4 iterations (constants, stack/local/arg, arith/branch/cmp, call/ret/mem/break)
- Devil's Advocate review after every iteration, finalized with a QR pass

**Dependency:** F0 done.

---

### F1.5 — Linker, Runner, Samples — **DONE**

**Goal:** A toolchain built around the F1 simulator that enables the full developer workflow: native C# source -> Roslyn -> .dll -> CIL-T0 linking -> simulator execution. Completion of deliverables deferred from F1.

**Platform:** .NET 10, C# 13, xUnit.

**Output:**
- `src/CilCpu.Linker/` — Roslyn .dll -> CIL-T0 binary linker (transitive call-target discovery, token-to-RVA resolution, opcode compatibility checking) — **done**
- `src/CilCpu.Sim.Runner/` — CLI runner tool (`run` and `link` commands, trap handling, TRunResult) — **done**
- `samples/PureMath/` — C# sample program (Add, Fibonacci, Factorial, GCD, IsPrime, etc.) — **done**
- `src/CilCpu.Sim.Tests/` — extended with linker + runner tests — **done, 259 green tests**

**CLI usage:**
```bash
# Run a .t0 binary
dotnet run --project src/CilCpu.Sim.Runner -- run program.t0 --args 2,3

# Link a .dll to .t0
dotnet run --project src/CilCpu.Sim.Runner -- link assembly.dll --class Pure --method Add -o output.t0
```

**Done criteria — met:**
- The linker transitively discovers called methods and resolves call tokens
- CIL-T0 incompatible opcodes (ldsfld, ldstr, newarr, etc.) produce link-time errors
- The Runner reads and executes `.t0` files, handles traps
- The Runner links `.dll` files to `.t0` via the CLI
- The full pipeline (C# -> Roslyn -> linker -> simulator) is end-to-end tested
- Fibonacci(20) = 6765 through the full Roslyn-native pipeline
- Developed via TDD, Devil's Advocate review after every iteration

**Dependency:** F1 done.

---

### F2 — RTL (Register Transfer Level)

**Goal:** A synthesizable RTL description of the CLI-CPU that behaves bit-for-bit identically to the F1 simulator.

**Platform:**
- **Language:** Verilog (TT mainstream) or Amaranth HDL (Python, more modern) — final decision at F2 start
- **Simulation:** Verilator + cocotb
- **Golden reference:** F1 C# simulator — every CIL-T0 test runs on both RTL and simulator simultaneously, with result comparison

**Output:**
- `rtl/` — RTL sources
- `rtl/tb/` — cocotb testbench
- `rtl/scripts/` — synthesis and simulation scripts (OpenLane2 compatible)

**Subsections:**
- F2.1 ALU — 32-bit integer ALU (Verilog + cocotb) — **DONE**
- F2.2a Decoder — length decoder + opcode decode (current sprint)
- F2.2b Decoder — microcode ROM for complex opcodes (next sprint)
- F2.3 Stack cache — 4×32-bit TOS + spill logic
- F2.4 QSPI controller — code + data fetch
- F2.5 Golden vector harness — cocotb vs C# simulator
- F2.6 Yosys synthesis — Sky130 PDK, area estimate
- F2.7 FPGA validation — single Nano core on real hardware (A7-Lite)

**Done criteria:**
- Verilator simulation passes on all F1 tests
- Yosys synthesis to Sky130 PDK succeeds
- Timing analysis: min. 30 MHz @ Sky130, target 50 MHz
- Area estimate fits the Tiny Tapeout multi-tile budget (12–16 tiles, ~12K–16K gates)

**Dependency:** F1 done, all tests green.

---

### F2.7 — Single-core FPGA Validation

**Goal:** Validate the F2 RTL **on real FPGA hardware** before the Tiny Tapeout submission (F3). This ensures the design works on physical hardware, not just in simulation — reducing F3 tape-out risk.

**Platform:** MicroPhase A7-Lite XC7A200T (the first of the 3 boards). Vivado WebPACK (free for Artix-7).

**Output:**
- `rtl/fpga/` — FPGA-specific top-level wrapper (clock, I/O pin assignment)
- Single Nano core + UART running on the FPGA board
- Fibonacci(20) = 6765 demo over UART on real hardware

**Done criteria:**
- Nano core RTL synthesized and running on A7-Lite 200T
- Fibonacci(20) runs correctly with UART output
- Timing closed (min. 50 MHz on FPGA)
- Cocotb golden-vector test results match FPGA output

**Dependency:** F2 done (RTL + cocotb simulation green).

**Cost:** ~€0 (the FPGA board is also needed for F4, already ordered).

**Why this matters:** *"No silicon tape-out with a design that hasn't run on FPGA."* F2.7 is this principle in practice — cheap, fast, and bugs are found on FPGA, not on the Tiny Tapeout chip.

---

### F3 — Tiny Tapeout Submission (single-core CIL-T0 + Mailbox)

**Goal:** The first real CLI-CPU silicon. On Sky130 PDK, via Tiny Tapeout shuttle, single-core CIL-T0 subset + **hardware mailbox interface**, enabling the first "networkable node" demo.

**Platform:** Tiny Tapeout (TTSKY26a or a later shuttle, whichever is available in time), Sky130 PDK, OpenLane2. One tile is ~160x100 um, ~1K logic gate capacity. The Nano core + Mailbox + UART **requires 12–16 tiles** (~12K–16K gates, including routing overhead). 24 GPIO (8 in + 8 out + 8 bidi), min. 50 MHz clock.

**Output:**
- `tt/` — Tiny Tapeout submission directory (`info.yaml`, `src/`, `docs/`, etc.)
- `tt/test/` — post-silicon bring-up tests
- `hw/bringup/` — bring-up board designs (KiCad): QSPI flash socket, QSPI PSRAM socket, FTDI USB-UART (for the mailbox external bridge), power, debug LEDs, PMOD connectors

**New F3 component per spec:**
- **Mailbox MMIO block** — 8-deep inbox + outbox FIFO at address `0xF000_0100`, details in `docs/ISA-CIL-T0.md`. Allows a host computer to send messages to the chip over UART, which the chip processes with a CIL program and responds back.

**Done criteria:**
- GDS accepted by the Tiny Tapeout shuttle
- Gate-level simulation green
- Bring-up board manufactured (JLCPCB), wired up
- **Physically running `Fibonacci(10)` on your own chip**, output over UART
- **First "echo neuron" demo:** the host sends a message through the mailbox, the chip's CIL program processes it and sends it back — the first silicon-level proof of the cognitive fabric concept

**Dependency:** F2 done.

**Cost estimate:** ~$900–$1,300 (12–16 tile TT submission, base + extra tiles ~$50/tile) + ~$80 (bring-up PCB + components). The 1-tile early bird price (~$150) is not enough for the Nano core — the ~10K std cell core + mailbox + UART requires at least 8 tiles, 12–16 tiles recommended for routing margin.

---

### F4 — Multi-core Cognitive Fabric on FPGA

**Goal:** **The strategic pivot moment.** The CLI-CPU becomes a real network for the first time — 4 single-core CIL-T0 cores working together on a single FPGA chip, in a **shared-nothing model**, communicating exclusively via mailbox messages, with event-driven operation.

**Why the main pivot is here:** This phase distinguishes the CLI-CPU from the historical Jazelle/picoJava "bytecode CPU" failures. The `docs/architecture.md` "Strategic Positioning: Cognitive Fabric" section argues in detail why the project's real value lies here, and why it is not about the single-core speed race.

**New features:**
- **4 CIL-T0 cores** on a single FPGA (the F3 RTL instantiated 4 times)
- **Mailbox router** — targeted forwarding of inter-core messages (4-port mux bank, not crossbar)
- **Per-core private SRAM** (16 KB/core), shared-nothing model
- **Sleep/Wake logic** — the core sleeps on an empty inbox, wakes on a new message (wake-from-sleep interrupt)
- **Global time base** — a single synchronized clock counter readable by every core (for neuron model time dependencies)
- **Shared slow bus** — only for QSPI flash, UART, timer access, not for critical inter-core communication

**New microarchitecture elements:**
- Router FSM (~1000 std cells)
- Per-core mailbox FIFO (already present in F3, here it just connects to the router)
- Wake-from-sleep interrupt line
- Global clock broadcast network

**Platform:** MicroPhase A7-Lite XC7A200T (~EUR320) — **primary reference platform for F4–F5**. Pure Artix-7 FPGA, 215K logic cells, 134K LUTs, 740 DSPs, 13.1 Mbit Block RAM, **512 MB DDR3**, Gigabit Ethernet, HDMI, built-in USB-JTAG, 2x50-pin GPIO header, 80x56 mm compact form factor. Vivado ML Standard (WebPACK) supports it **for free**. Alternatives: Digilent Arty A7-100T (~$332, 101K logic cells, no DDR3) or Lattice ECP5 (OrangeCrab, ~$130, smaller capacity). Still 100% feasible on FPGA.

**Done criteria:**
- 4 cores simultaneously run different CIL programs, communicating via messages
- **Ping-pong demo:** Core 0 sends a message to Core 1, Core 1 responds — minimal actor pattern
- **Echo chain demo:** 4 cores pass a message in a chain, the first sends it off, the fourth outputs it over UART
- **Spiking neural network demo:** all 4 cores run a LIF neuron CIL program with configurable topology — the cognitive fabric's first real neuromorphic use case
- Event-driven mode: idle power measured, sleep state benefit demonstrated

**Dependency:** F3 done, post-silicon lessons ported back to RTL.

---

### F5 — Rich core (full CIL) on FPGA, first heterogeneous system

**Goal:** **The birth of the Rich core.** This is the phase where, alongside the narrow CIL-T0 subset, the **"big sibling" is born** — a full ECMA-335 CIL core with object model, GC, virtual calls, exceptions, FPU, 64-bit integers, and generics. By the end of this phase, **we run a heterogeneous multi-core system for the first time**: 4 Nano cores (from F4) **alongside** 1 Rich core, on a shared mailbox network.

**Why "Rich core" and not just "full CIL"?** The `docs/architecture.md` **"Heterogeneous multi-core: Nano + Rich"** section explains: the CLI-CPU will use a heterogeneous (big.LITTLE-style) architecture from F6 onwards, **with two core types**. The Nano (CIL-T0) was born in F3, the Rich (full CIL) here in F5. This terminology unification is just a rename — the technical content is what was previously called "full CIL" in the roadmap.

**New opcodes on the Rich core (in addition to the Nano's 48 opcodes):**
- Object model: `newobj`, `newarr`, `ldfld`, `stfld`, `ldelem.*`, `stelem.*`, `ldlen`, `initobj`
- Virtual calls and metadata: `callvirt`, `ldtoken`, `ldftn`, `ldvirtftn`
- Type checking: `isinst`, `castclass`, `box`, `unbox`
- String: `ldstr`
- Exception handling: `throw`, `rethrow`, `leave`, `endfinally`, `endfilter`
- 64-bit integer: all arithmetic `.i8` variants
- Floating point: `ldc.r4`, `ldc.r8`, `add` (FP), `mul` (FP), `div` (FP), `conv.*`
- Generics: runtime type parameter resolution

**New microarchitecture for the Rich core:**
- **Metadata TLB + token resolver** — traverses PE/COFF tables
- **vtable inline cache** — virtual call acceleration
- **Per-core GC assist unit** — bump allocator on the private heap. **No global GC**, because there is no shared heap — this is the **great simplification** of the shared-nothing model: GC does not need to stop-the-world globally
- **Shadow register file + exception unwinder** (Transmeta-inspired)
- **uop cache** (Transmeta-style, energy savings on hot loops)
- **FPU** (IEEE-754 R4, R8)

**New software work:**
- **Roslyn source generator** for `[RunsOn(CoreType.Nano)]` / `[RunsOn(CoreType.Rich)]` attributes
- The generator verifies at build-time that Nano-designated methods use only CIL-T0 opcodes (verification)
- Two separate binary outputs: `.t0` (Nano) and `.tr` (Rich)

**Platform:** Same A7-Lite XC7A200T as F4. The 134K LUTs and 13.1 Mbit Block RAM comfortably accommodate 1 Rich + 4 Nano cores (~60K LUTs, ~45%), and even **2 Rich + 8 Nano** (~105K LUTs, ~78%) is feasible. The 512 MB DDR3 is a critical advantage over boards without DDR3 for the Rich core's GC/heap. Alternative: Arty A7-100T (63K LUTs — 1 Rich + 4 Nano fits tightly, but 2 Rich does not).

**Done criteria:**
- Every ECMA-335 opcode has a test on the C# reference simulator and on RTL
- A C# program with classes, virtual methods, arrays, strings, exceptions **runs on the Rich core**
- A C# program where **some classes are `[RunsOn(CoreType.Nano)]`, others `[RunsOn(CoreType.Rich)]`** — runs in a heterogeneous system
- **Multi-core Akka.NET demo:** supervisor on the Rich core, workers on the Nano cores, messages via mailbox
- **Multi-core SNN demo:** Izhikevich or Hodgkin-Huxley model on all 4 Nano cores, one Rich core coordinating

**Dependency:** F4 done.

---

### F6 — Cognitive Fabric FPGA-Verified Demonstration (heterogeneous Nano + Rich)

**Goal:** **Full, FPGA-verified demonstration** of the Cognitive Fabric architecture. **No silicon tape-out with a design that hasn't run on FPGA.** F6-FPGA is the primary and mandatory milestone; F6-Silicon may only proceed once F6-FPGA passes all tests.

**Architecture:** Heterogeneous Rich + Nano multi-core fabric. On a single A7-Lite 200T board, **2 Rich + 8–10 Nano** (~105–115K / 134K LUTs). Multiple boards connected via Ethernet demonstrate the Cognitive Fabric's **distributed multi-chip** variant — the first real test of Neuron OS location transparency.

#### F6-FPGA — Heterogeneous demonstration on A7-Lite 200T multi-board mesh (primary, mandatory)

**Goal:** **Verification** of the Cognitive Fabric architecture on MicroPhase A7-Lite XC7A200T boards, **both on a single chip and in a multi-chip Ethernet mesh**. F6-FPGA **proves the architecture works** before anyone risks ~$10k on an MPW shuttle.

**Strategic rationale:** The **MicroPhase A7-Lite XC7A200T** (134K LUTs, 512 MB DDR3, Gigabit Ethernet, ~EUR320) is the F4–F5 reference platform, and **3 boards connected in an Ethernet mesh** provide 3 x 134K = **402K aggregate LUT capacity** — **twice as much as a Kintex-7 K325T** (204K LUTs). Moreover, the multi-board configuration is a **more realistic test**, because the real Cognitive Fabric will also be multi-chip. Vivado ML Standard (WebPACK) supports the Artix-7 family (up to XC7A200T) **for free**. Alternatively, the **OpenXC7** open toolchain can be used.

**Why not Kintex-7 K325T?** No suitably configured K7-325T development board is currently available. If one becomes available in the future, the F6 configuration sweep can be extended to it — but F6 **does not depend on it**.

**New work beyond F4+F5:**
- **Adaptive top-level instantiation** — parameterizable (`#NUM_RICH`, `#NUM_NANO`) on the same RTL
- **Mesh router** scalability — 2D grid topology for systems larger than 4 cores (~1 engineer-month)
- **Inter-chip Ethernet bridge** — cross-board mailbox messages over Gigabit Ethernet, the real test of Neuron OS location transparency (~1 engineer-month)
- **Heterogeneous verification** and multi-configuration test harness (~1 engineer-month)
- **Configuration sweep script** — automated synthesis and P&R for multiple (Rich, Nano) pairs, LUT/timing/throughput report
- **Total: ~3-4 engineer-months**

**Platform:** **3 x MicroPhase A7-Lite XC7A200T** (~EUR320/board) — per board: 134K LUTs, 740 DSPs, 13.1 Mbit Block RAM, 512 MB DDR3, Gigabit Ethernet, HDMI, built-in USB-JTAG, 2x50-pin GPIO header. Vivado ML Standard (WebPACK) supports it **for free**. Optionally **Kintex-7 XC7K325T** (204K LUTs), if a suitably configured board becomes available.

**Board roles:**

| Board | Role | Configuration |
|-------|------|---------------|
| **#1** | Development, F4–F5, primary single-chip test | 2 Rich + 8–10 Nano |
| **#2** | Inter-chip test, distributed fabric | 0–2 Rich + 8–10 Nano |
| **#3** | 3-node mesh, spare | 0–2 Rich + 8–10 Nano |

**Multi-board example configuration (3 boards in Ethernet mesh):**
- Board A: 2 Rich (supervisor) + 6 Nano — the "control node"
- Board B: 0 Rich + 10 Nano — worker farm
- Board C: 0 Rich + 10 Nano — worker farm
- **Total: 2 Rich + 26 Nano**, distributed across 3 physical chips, connected via Ethernet bridge

**Output:**
- `rtl/top_f6_fpga/` — parameterizable top-level (Nano and Rich core count as configuration parameters)
- `rtl/eth_bridge/` — inter-chip Ethernet mailbox bridge
- `rtl/test_harness/` — single-chip and multi-chip stress test scenarios
- `bring-up/f6_fpga_results.md` — multi-configuration report (LUT, timing, throughput, power estimate)
- `bring-up/f6_fpga_sweet_spot.md` — recommendation for the F6-Silicon (Rich, Nano) configuration

**Configuration sweep — A7-200T combinations (134K LUTs per board, target <=85% utilization):**

*Single-board:*

| (Rich, Nano) | Estimated LUT | Utilization | Goal |
|--------------|---------------|-------------|------|
| (0, 20) | ~115K | 86% | Pure Nano fabric (SNN max) |
| (1, 14) | ~105K | 78% | "1 supervisor + many workers" |
| (2, 8) | ~105K | 78% | **Heterogeneous sweet spot** |
| (2, 10) | ~115K | 86% | Heterogeneous max |

*Multi-board (2–3 boards, in Ethernet mesh):*

| Configuration | Total | Goal |
|---------------|-------|------|
| 2 boards: (2,6) + (0,10) | 2R + 16N | F5+ heterogeneous distributed |
| 3 boards: (2,6) + (0,10) + (0,10) | **2R + 26N** | **F6 distributed Cognitive Fabric** |
| 3 boards: (1,8) + (1,8) + (0,10) | 2R + 26N | Symmetric supervisor |

**Done criteria:**
- **At least 4 different (Rich, Nano) configurations** synthesized and run on single-board
- **The 2 Rich + 8 Nano configuration** runs stably on single-board, all tests green
- **Multi-board Ethernet bridge** works: messages traverse between boards, latency measured
- **Distributed demo:** 2–3 boards in a mesh, actors communicate cross-chip, the sender does not know the target is on a different chip (location transparency)
- **The four F4 demos** (ping-pong, echo-chain, ping-network, SNN) **run on both single-board and multi-board**
- **Rich core demo:** C# code runs on the Rich core (arrays, strings, exceptions)
- **Heterogeneous demo:** Rich core supervisor coordinates a neural network running on Nano cores
- **SNN demo:** LIF/Izhikevich network distributed across 16+ Nano cores, with 1-2 Rich coordinators
- **Akka.NET cluster demo:** an actor system compiled from real C# code running in hardware, across multiple chips
- **Aggregate throughput** measurement (messages/sec — single-chip and cross-chip separately)
- **Power estimate** (FPGA consumption x empirical FPGA-to-silicon conversion factor)
- **Multi-configuration report** published (LUT, timing, throughput comparison)

**Dependency:** F5 done, FPGA stable (with both Nano and Rich cores), all tests green.

**Cost estimate:** 3 x ~EUR320 = **~EUR960** (~$1030) — F4–F5 boards reused in F6. **Vivado ML Standard (WebPACK): $0**. **Engineering effort:** 3-4 engineer-months.

#### F6-Silicon Zero — "Cognitive Fabric Zero" (IHP 3 mm², first heterogeneous silicon)

**Goal:** The first **heterogeneous Cognitive Fabric silicon** — **1 Rich + 8 Nano cores, 48 KB on-chip SRAM, 3 mm² IHP SG13G2**. This is the stepping stone between the F3 single-core Tiny Tapeout and the full "Cognitive Fabric One" (15 mm²). **Potentially achievable at EUR0 cost** via the IHP FMD-QNC free research MPW program.

**Why a standalone milestone:**
- **F3** (TT, 1 Nano) proves the core works in silicon
- **Cognitive Fabric Zero** (IHP, 1R+8N) proves that **heterogeneous multi-core works in silicon** — supervisor + worker, mailbox mesh, sleep/wake, Neuron OS foundations
- **Cognitive Fabric One** (ChipIgnite, 6R+16N+1S) proves at full scale — with benchmarks and publication

**Configuration (3 mm² IHP SG13G2):**

| Element | Count | Per-core SRAM | Area |
|---------|-------|---------------|------|
| Rich core + mailbox | 1 | 16 KB | 0.75 mm² |
| Nano core + mailbox | 8 | 4 KB | 8 x 0.18 = 1.44 mm² |
| Mesh router (8-port) | 1 | — | 0.01 mm² |
| Peripherals (QSPI, UART) | — | — | 0.05 mm² |
| Routing overhead (~25%) | — | — | 0.56 mm² |
| **Total** | **9 cores** | **48 KB** | **~2.81 mm²** |

**Done criteria:**
- 9-core heterogeneous die manufactured and in your hands
- Rich core supervisor + 8 Nano workers running, mailbox communication working
- Ping-pong and echo-chain demo on silicon
- SNN demo: 8 LIF neurons, 1 Rich coordinator
- Comparison with the F3 single-core TT chip — scaling is tangible

**Dependency:** F5 done (Rich core RTL tested on FPGA), F6-FPGA at least single-board verification done.

**Cost:** **EUR0** (IHP FMD-QNC free research MPW) or ~EUR4,500 (IHP standard price, 3 mm²). **Schedule:** IHP shuttles 2026: March, October, November.

**Note:** Cognitive Fabric Zero **does not replace** Cognitive Fabric One — it complements it. Zero is the "it works in silicon" proof, One is the "it outperforms traditional approaches" proof with benchmarks.

---

#### F6-Silicon One — "Cognitive Fabric One" MPW tape-out (the full demonstration)

**Goal:** The **"Cognitive Fabric One"** — the heterogeneous design verified in F6-FPGA (on A7-Lite 200T multi-board mesh) and optimized to the sweet spot, **on real silicon**: **6 Rich + 16 Nano + 1 Secure core, 160 KB on-chip SRAM, 15 mm² Sky130 (OpenFrame)**. This chip proves that on the same silicon, the Cognitive Fabric paradigm **performs 5–22x more useful work** on actor-based workloads than a traditional multi-core CPU — while being deterministic, hardware-isolated, and linearly scalable. Detailed chip vision and benchmark comparison: [`docs/architecture-en.md`](architecture-en.md) "Cognitive Fabric One" section. **Prerequisite: all F6-FPGA done criteria are met** — silicon tape-out cannot begin without FPGA verification.

**When it starts:** **Only after all F6-FPGA done criteria are met**, and only when at least one of the following is true:
- The project has **secured funding or an industry partner** to cover the tape-out
- A **commercial product roadmap** ([F6.5 Secure Edition](#f65--secure-edition-parallel-tape-out-optional), F7 demo hardware) has a **silicon prerequisite**
- Measuring **real power efficiency** and **>500 MHz clock** is **critical** for the next milestone

**The silicon target builds on the FPGA-verified configuration:** the (Rich, Nano) sweet spot selected from the F6-FPGA multi-board sweep — expected to be **6 Rich + 16 Nano + 1 Secure** (as verified in the multi-board mesh) — goes to tape-out on a single chip. **On ASIC, cores are smaller** (std cell vs FPGA LUT), so the configuration verified across multiple boards **fits on a single silicon chip**, and can optionally **scale up**, but only as a straightforward extension of the verified router and mesh topology.

**Platform decision (before F6-Silicon starts):**
- **Sky130 @ eFabless ChipIgnite** — the **Caravel** harness offers 10 mm² user area, 38 GPIO; the **OpenFrame** harness offers **15 mm²**, 44 GPIO. ~$14,950 (2026 price), 100 QFN chips + eval board, ~5-month turnaround. **The reference configuration (6R+16N+1S) targets OpenFrame.**
- **IHP SG13G2 MPW** — European, ~EUR1,500/mm² (standard) or **EUR0** (FMD-QNC free research program, for open-source designs). EUR4,500 for 3 mm²; schedule: 2026 March, October, November.
- **Google Open MPW** — free shuttle (when available), Sky130, Caravel harness. Not regular, but CLI-CPU's open-source status makes it a strong candidate.
- **Funding:** NLnet NGI Zero Commons Fund (EUR5K–EUR50K, next deadline: June 1, 2026), community crowdfunding, industry partner.

**New features beyond F6-FPGA (silicon-specific):**
- **Floorplan optimization** — Rich cores placed centrally, Nano cores grouped around them
- **Writable microcode** SRAM — firmware-updatable opcode behavior (simulated with BRAM on FPGA, dedicated SRAM on silicon)
- **Gated store buffer** (GC write barrier batch, Transmeta-inspired)
- **Aggressive power-gating** — unused cores in fully cold state (not realistic on FPGA)
- **Cross-core-type bridge** — Nano to Rich messages and state migration with hardware optimization
- **Optional scale-up** — if silicon budget permits, scaling the FPGA-verified 2R+16N to 2R+32N (linear extension of router topology, not a new design)

**New design work for F6-Silicon (beyond F6-FPGA):**
- Floorplan: **~2–4 engineer-weeks**
- Power gating and clock tree CTS: **~1 engineer-month**
- DFT scan chain insertion: **~2 engineer-weeks**
- Tape-out checklist and sign-off: **~1 engineer-month**
- **Total: ~2-3 engineer-months of additional work**

**Output:**
- `mpw/` — eFabless/IHP submission directory
- `mpw/firmware/` — bootloader, microcode image, Nano/Rich code loader
- `hw/chipignite-board/` — ChipIgnite (or IHP) bring-up board

**Done criteria:**
- "Cognitive Fabric One" heterogeneous die manufactured and in your hands
- **All demos verified on F6-FPGA** reproduced on real silicon
- **Actor throughput benchmark** — messages/sec measurement, compared against an equivalent-area RISC-V multi-core reference
- **SNN benchmark** — LIF/Izhikevich network, linear scaling demonstrated
- **Power/performance measurement** — on event-driven workloads, idle power measurement (sleeping cores), compared against ARM Cortex-M4 / RISC-V RV32
- **Fault tolerance demo** — worker crash -> supervisor restart, the system does not halt
- **Publication material** — benchmark report, the "Cognitive Fabric One" narrative: *"5–22x more useful work on the same silicon for actor-based workloads"*

**Dependency:** **F6-FPGA done** (all done criteria met), sweet spot selected, multi-configuration report available.

**Cost estimate:** ~$14,950 (eFabless ChipIgnite OpenFrame, 15 mm², 100 QFN chips + eval board), or ~EUR4,500 (IHP SG13G2 3 mm², smaller configuration: 1R+8N), or **EUR0** (IHP free research MPW / Google Open MPW, if available). **NLnet NGI Zero Commons Fund** grant could cover the entire F6-Silicon (EUR5K–EUR50K).

---

### F6.5 — Secure Edition parallel tape-out (optional)

**Goal:** The CLI-CPU Secure Edition parallel tape-out variant, targeting the Secure Element / TEE / JavaCard market. Same base architecture (Nano + Rich core), **plus** Secure Element-specific hardware components: Crypto Actor (SPECT-inspired), TRNG, PUF, secure boot + attestation, tamper detection, DPA countermeasures, OTP key storage.

**Detailed document:** [`docs/secure-element-en.md`](secure-element-en.md) — this captures the full Secure Element positioning, a detailed analysis of TROPIC01 (Tropic Square's first open commercial SE), the differentiating architectural advantages (multi-core, multiple independent security domains on a single chip), the certification roadmap (EAL-5+), and the specific product family (open banking card, open eSIM, open eID, open FIDO2 authenticator, open TPM, open hardware wallet, open V2X, open medical SE).

**Why "F6.5" and not "F6"?** Because this is **a parallel tape-out variant**, not a standalone phase. Same F5 RTL base, just augmented with Secure Element hardware components. It can be ready **~6 months after** the F6-Silicon Cognitive Fabric tape-out — Secure Edition has a silicon prerequisite, so F6.5 builds on the F6-Silicon variant, **not** on F6-FPGA.

**New features beyond F6:**
- **Crypto Actor** — SPECT-inspired dedicated cryptographic unit (AES, SHA, ECC, post-quantum: Kyber/Dilithium/Falcon)
- **TRNG** — true random number generator (ring oscillator jitter + whitening)
- **PUF** — Physically Unclonable Function (SRAM PUF + error correction)
- **OTP / eFuse storage** — write-once root key storage
- **Secure boot + remote attestation** — measurement chain and chip identity
- **Tamper detection** — 6 components (EM pulse, voltage glitch, temperature, laser, active shield, frequency monitor)
- **DPA countermeasures** — masking, hiding, constant-time, noise injection

**Estimated additional design effort:** ~30-50 engineer-months (relative to F6), for a 3-5 person team ~1-1.5 years.

**Estimated additional area:** ~64k std cells on Sky130 (~32% increase over F6's ~200k). **Fits** in a ChipIgnite OpenFrame MPW (~15 mm²) or an IHP SG13G2 MPW (~15 mm²).

**Done criteria:**
- F6.5 tape-out successfully completed
- First bring-up board manufactured
- Crypto Actor correctly implements the target algorithms
- Tamper detection triggers on tested attacks (voltage glitch, EM, laser)
- TRNG meets NIST SP 800-90B entropy requirements
- First **Common Criteria pre-evaluation** initiated

**Dependency:** F6-Silicon Cognitive Fabric tape-out done (F6-FPGA alone is not sufficient, because the Secure Element components — Crypto Actor, TRNG, PUF, tamper detection — require silicon-specific hardware).

**Cost estimate:** ~$10-50k (MPW tape-out) + ~$0.5-1.2M (additional engineering salaries) + ~$400k-1M (later Common Criteria evaluation).

**Certification target (post-F7):** **Common Criteria EAL-5+** at a BSI (Germany) or ANSSI (France) accredited lab. **Timeline**: 2-3 years for evaluation. **Expected first commercial products**: 2033-2034.

---

### F7 — Demonstration Platform + Neuron OS Developer SDK

**Goal:** The Cognitive Fabric + Neuron OS combination as a **demonstrable, developable platform** for multiple real use cases. The `Neuron OS` graduates from research status to a real developer platform here.

**The full Neuron OS vision is in a separate document**: [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md). In brief: an actor-based operating system that realizes the Erlang OTP vision with hardware support (Erlang in silicon). Everything is an actor, shared-nothing, let it crash, supervision hierarchy, capability-based security, hot code loading, location transparency.

**Output:**
- **Reference PCBs** for multiple use cases:
  - IoT sensor node (QSPI flash, PSRAM, LoRa/WiFi, a few sensors)
  - Akka.NET cluster demo dev kit (multiple chips networked)
  - SNN inference board (for MNIST/CIFAR-level tasks)
- **Neuron OS Developer SDK**:
  - `NeuronOS.Core` — actor base library (Actor<T>, Supervisor, Spawn, Send, Receive)
  - `NeuronOS.Devices` — device actor library (UART, GPIO, QSPI, timer)
  - `NeuronOS.Distributed` — inter-chip actor protocol
  - `dotnet publish` target for Neuron OS
  - VSCode / VS extension debugger with actor message replay
  - NuGet packages on public feed
- **Reference C# demo applications:**
  - Akka.NET-style actor cluster (supervisor hierarchy, hot code loading)
  - LIF spiking neural network on 16+ Nano cores
  - IoT edge gateway (sensor handlers + LoRa protocol)
  - Multi-agent simulation (Boids, extension of Conway's Game of Life)
- **Publication material:** paper, talk, demo video — a narrative presenting the entire project, Linux Foundation project status request

**Dependency:** F6 done, chip in hand, Neuron OS alpha (since F5) stable.

**Note on Neuron OS phasing:** The Neuron OS is **not a standalone phase**, but **builds organically** along the F1-F7 phases:
- **F1**: minimal `NeuronOS.Core` library in the C# simulator (Actor<T>, in-memory mailbox)
- **F3**: single-actor bootloader on the Tiny Tapeout chip (echo neuron demo)
- **F4**: 4-actor system with initial scheduler + router implementation
- **F5**: full supervision tree, per-core GC, capability-based isolation, Roslyn source generator for the `[RunsOn]` attribute
- **F6**: hot code loading, writable microcode, distributed actors across multiple chips
- **F7**: developer SDK, VSCode integration, NuGet publishing, real application demos

Details and developer API examples: [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md).

---

## Estimated Work Hours Summary

Estimates assume **AI-assisted development** (Claude Code pair programming), which based on actual F0–F2.2b effort provides ~30–40% productivity gain in code generation, test writing, and documentation. Physical work (PCB, bring-up, FPGA) benefits less from AI assistance.

| Phase | Description | Est. Hours | Eng. Months* | Status |
|-------|-------------|-----------|-------------|--------|
| **F0** | Specification (3 documents, ~3500+ lines) | ~60 | ~0.4 | ✅ DONE |
| **F1** | C# reference simulator (48 opcodes, 218 tests, 4 TDD iterations) | ~120 | ~0.8 | ✅ DONE |
| **F1.5** | Linker, Runner, Samples (259 tests) | ~80 | ~0.5 | ✅ DONE |
| **F2** | RTL (Verilog + cocotb, 7 subsections) | ~350 | ~2.2 | 🔧 In Progress |
| — F2.1 | ALU (32-bit integer) | ~30 | | ✅ DONE |
| — F2.2a | Decoder (length + opcode) | ~40 | | ✅ DONE |
| — F2.2b | Decoder (microcode ROM) | ~50 | | ✅ DONE |
| — F2.3 | Stack cache (4×32-bit TOS + spill) | ~50 | | ⬜ Planned |
| — F2.4 | QSPI controller | ~70 | | ⬜ Planned |
| — F2.5 | Golden vector harness | ~35 | | ⬜ Planned |
| — F2.6 | Yosys synthesis (Sky130) | ~30 | | ⬜ Planned |
| — F2.7 | FPGA validation (A7-Lite) | ~45 | | ⬜ Planned |
| **F3** | Tiny Tapeout submission (1 Nano + Mailbox, bring-up board) | ~220 | ~1.4 | ⬜ Planned |
| **F4** | Multi-core Cognitive Fabric on FPGA (4× Nano, router, sleep/wake) | ~360 | ~2.3 | ⬜ Planned |
| **F5** | Rich core + heterogeneous system (full CIL, GC, FPU, source gen.) | ~720 | ~4.5 | ⬜ Planned |
| **F6-FPGA** | Heterogeneous demonstration (3× A7-Lite, mesh, Ethernet bridge) | ~480 | ~3 | ⬜ Planned |
| **F6-Si Zero** | IHP 3 mm² (1R+8N, tape-out + bring-up) | ~360 | ~2.3 | ⬜ Planned |
| **F6-Si One** | ChipIgnite 15 mm² (6R+16N+1S, tape-out + bring-up) | ~360 | ~2.3 | ⬜ Planned |
| **F6.5** | Secure Edition (Crypto Actor, TRNG, PUF, tamper, DPA) | ~5,600 | ~35 | ⬜ Optional |
| **F7** | Neuron OS SDK + demo platform (PCBs, SDK, applications) | ~520 | ~3.3 | ⬜ Planned |
| | **Total (without F6.5)** | **~3,630** | **~23** | |
| | **Total (with F6.5)** | **~9,230** | **~58** | |

\* 1 engineer-month ≈ 160 hours (4 weeks × 40 hours). F6.5 requires a separate team (3–5 people), the rest is estimated for a single AI-assisted developer.

**Notes:**
- DONE phases (F0, F1, F1.5, F2.1–F2.2b) estimates reflect actual effort — these are **already AI-assisted** values
- The F4 estimate is lower than core count might suggest because Nano core RTL is **reused** from F2/F3 — the substantive new work is the router, sleep/wake, and demos
- F6-Silicon Zero and One **can run in parallel** after F6-FPGA, or sequentially — the table shows pure engineering effort, not manufacturing wait times
- F6.5 (Secure Edition) requires a **separate team**, and Common Criteria certification adds ~2–3 years
- Estimates cover **pure engineering time** only — manufacturing lead times (TT ~5 months, ChipIgnite ~5 months, IHP ~4 months), shipping, and bring-up waiting are not included

### NLnet NGI Zero Commons Fund Alignment

The [NLnet application](nlnet-application-draft-en.md) (v1.1, submitted 2026-04-14) requested **€35,000** for **18 months**, assuming ~900 hours of part-time work (~€36/h, of which ~€2,440 is hardware).

**Milestone mapping:**

| NLnet Milestone | Roadmap Phase | Grant Budget | Grant Hours† | Roadmap Est. | Coverage |
|-----------------|---------------|-------------|-------------|-------------|----------|
| **M1:** RTL | F2 | €8,000 | ~222 h | ~350 h | full |
| **M2:** Tiny Tapeout | F3 | €7,000 | ~159 h | ~220 h | full |
| **M3:** FPGA multi-core | F4 | €8,000 | ~190 h | ~360 h | full |
| **M4:** Rich core RTL start | F5 (start) | €7,000 | ~194 h | ~200 h (of 720) | ~28% |
| **M5:** Docs & community | (built-in) | €5,000 | ~139 h | ~100 h | full |
| **Total** | F2–F5 start | **€35,000** | **~904 h** | **~1,230 h** | |

† Personnel hours = (budget − hardware cost) ÷ €36/h

**Gap explanation:** The roadmap's full estimate (~1,230 h for the NLnet scope) **exceeds the grant's ~900 hours by ~330 h**. This is normal for open-source grant projects — the grant covers **costs**, not 100% of effort. The difference (~27%) represents the developer's **unfunded own contribution** to the project, which is the standard open-source development model.

**The grant commitments are achievable**, because:
1. Actual pace on F0–F2.2b (~260 h / ~2 weeks of intensive sprints) **exceeds** the grant's timeline
2. AI-assisted development (Claude Code) delivers a proven ~30–40% speedup on code generation, testing, and documentation as demonstrated in DONE phases
3. F2 RTL foundations (ALU, decoder, microcode ROM) are **already complete** — before the grant period starts
4. F4 core instantiation directly reuses F2/F3 RTL — the substantive new work (router, sleep/wake) is well-scoped

---

## Dependency Graph

```
                          ┌── Nano core path ─┐        ┌── Rich core path ──┐
                          │                   │        │                    │
F0 ──► F1 ──► F2 ──► F3 ──┘──► F4 ──►─────────┘─► F5 ──┴──► F6-FPGA ──► F7
  spec   sim    RTL    TT       multi-         heterogeneous  verified    demo
              │         1×      Nano          (Rich+Nano)  demonstration + Neuron
              │         +        4×            FPGA       (3× A7-Lite     OS SDK
              │        mbox     FPGA         (A7-Lite     200T multi-     ▲
              │              ▲                200T)       board mesh)     │
              └──── FPGA ────┘                                 │          │
                 (optional                                     │          │
                  early after F2)                              │          │
                                                               ▼          │
                                                        F6-Silicon Zero ──┤
                                                        "Cognitive        │
                                                         Fabric Zero"     │
                                                        (IHP 3mm²,        │
                                                         1R+8N, €0?)      │
                                                               │          │
                                                               ▼          │
                                                        F6-Silicon One ───┘
                                                        "Cognitive
                                                         Fabric One"
                                                        (ChipIgnite 10mm²,
                                                         6R+16N+1S, ~$15K)
                                                               │
                                                               ▼
                                                          F6.5 ──► Secure Edition
                                                           parallel tape-out
                                                           (Crypto Actor + TRNG +
                                                           PUF + tamper + DPA)
                                                               │
                                                               ▼
                                                      Common Criteria EAL-5+
                                                      evaluation (~2-3 years)
                                                                 │
                                                                 v
                                                      Commercial SE products
                                                      (open wallet, eSIM, eID,
                                                       FIDO, TPM, V2X, medical)
```

After F2, the CIL-T0 subset can optionally be run on FPGA, even before F3 (Tiny Tapeout) — this helps with bring-up board design.

## Three Key Pivots in the Roadmap's History

**1st pivot — F4: Cognitive Fabric direction (shared-nothing multi-core)**

The **previous** F4 was "CIL object model + GC on FPGA"; the **current** F4 is "4-core multi-core FPGA Cognitive Fabric". The object model + GC moved to F5. The **hardware base (stack machine core) does not change** — it carries over from F3 to F4, just in 4 instances. This means the pivot is **achievable with minimal code changes**, preserving all F0-F3 work to date. This step distinguishes the CLI-CPU from the historical picoJava/Jazelle failures.

**2nd pivot — F5: Heterogeneous Nano + Rich terminology**

The former "F5 — CIL Object Model + GC single-core extension" title was renamed to **"F5 — Rich core (full CIL) on FPGA, first heterogeneous system"**. Technically the content is nearly the same (full CIL extension), but we now explicitly frame it as: this is where **the Rich core is born** as the Nano core's "big sibling". From F6 onwards, the system is a **heterogeneous Nano+Rich multi-core chip**, analogous to ARM big.LITTLE, Apple P/E-core, and Intel Alder Lake models. See `docs/architecture.md` "Heterogeneous multi-core: Nano + Rich" section.

**3rd pivot — F6: Mandatory FPGA verification before silicon, A7-Lite 200T multi-board**

The **previous** F6 targeted a single large FPGA (K7-480T, then K7-325T). The **current** F6 builds on the **realistically available and in-hand platform**: **3 x MicroPhase A7-Lite XC7A200T** (3 x 134K = 402K aggregate LUT capacity, in a Gigabit Ethernet mesh). This is a **more realistic test**, because the real Cognitive Fabric will also be multi-chip — location transparency and the inter-chip mailbox bridge **can only be tested on multi-board**. The Kintex-7 K325T is an optional addition if a suitably configured board becomes available. **F6-Silicon may only start after full F6-FPGA verification** — no silicon tape-out with a design that hasn't run on FPGA.

## Current Status

**F0 is conceptually complete.** Seven documents under `docs/` and `README.md` together amount to ~3500+ lines, forming an internally consistent project plan with the **three-track positioning** (Cognitive Fabric + Trustworthy Silicon + Secure Edition), the heterogeneous Nano+Rich multi-core model, silicon-grade security positioning, the Neuron OS vision, and the Secure Element strategic plan (F6.5 parallel tape-out).

**F1 — C# reference simulator closed.** The `src/CilCpu.Sim` and `src/CilCpu.Sim.Tests` projects implement all **48 opcodes** specified by the CIL-T0 spec, with every hardware trap tested. The **F1 golden reference**: `Fibonacci(20) = 6765` green. Development took place across **4 iterations** with strict TDD, each iteration followed by a Devil's Advocate review.

**F1.5 — Linker, Runner, Samples closed.** The `CilCpu.Linker` Roslyn .dll -> CIL-T0 pipeline, the `CilCpu.Sim.Runner` CLI runner tool (`run` / `link` commands), and the `samples/PureMath` sample program are done. **259 green xUnit tests**, **0 warnings, 0 errors**. The full pipeline (C# -> Roslyn -> linker -> simulator) is end-to-end tested, developed via TDD, with Devil's Advocate review.

**Next substantive step:** **F2 — RTL** kickoff (Verilog or Amaranth HDL decision, cocotb testbench infrastructure).

## Funding Action Plan

The CLI-CPU silicon milestones (F3 Tiny Tapeout, F6-Silicon Zero/One) require external funding. The following action plan prioritizes realistically available sources.

### Grant Opportunities

| Source | Amount | Deadline | Fit | Priority |
|--------|--------|----------|-----|----------|
| **NLnet NGI Zero Commons Fund** | EUR5K–EUR50K | **June 1, 2026** (round 13) | Explicitly mentions "libre silicon", open-source project | **#1 — submit immediately** |
| **IHP FMD-QNC free MPW** | EUR0 (research) | 2026: Oct, Nov; 2027: Mar | Open-source, non-commercial design | **#2 — register** |
| **Google Open MPW** | $0 (sponsored) | Not regular, monitor | Sky130, Caravel harness, open design | **#3 — monitor** |
| **EU CHIPS Act** grants | Varies | Ongoing | European open hardware | Long-term |

### Community Funding

| Platform | Goal | When |
|----------|------|------|
| **GitHub Sponsors** | Continuous small amounts, visibility | Set up immediately |
| **Open Collective** | Transparent finance, community decision-making | Before F3 |
| **Crowd Supply** | Hardware campaign (bring-up board, chip) | As F3 tape-out approaches |

### Budget Scenarios

| Scenario | Amount | Covers |
|----------|--------|--------|
| **A: Out of pocket** | ~EUR2,400 | 3x A7-Lite 200T (F4–F6 FPGA) + 1x TT 16 tiles (F3) + bring-up |
| **B: NLnet EUR15K** | ~EUR15K | Scenario A + IHP "Cognitive Fabric Zero" (1R+8N, 3 mm²) + engineering tools |
| **C: NLnet EUR30K** | ~EUR30K | Scenario B + ChipIgnite "Cognitive Fabric One" (6R+16N+1S, 15 mm²) |
| **D: NLnet EUR50K** | ~EUR50K | Scenario C + 2nd tape-out iteration + conference/publication + subcontracted engineering work |

### Schedule

```
2026 Apr     --- NLnet grant preparation (47 days!)
2026 Jun 1   --- NLnet NGI Zero Commons Fund deadline
2026 Jun-Sep --- F2 RTL development + FPGA bring-up
2026 Oct     --- IHP free MPW registration deadline
2026 Nov     --- IHP shuttle (if accepted)
2027 Q1      --- F3 Tiny Tapeout submission (TTSKY26a or later)
2027 Q2-Q3   --- F4-F5 FPGA development (3x A7-Lite 200T)
2027 Q4      --- F6-FPGA verification done
2028 Q1      --- F6-Silicon Zero (IHP) / One (ChipIgnite) submission
2028 Q3      --- First silicon in hand
```

**The most important immediate action:** NLnet NGI Zero Commons Fund grant preparation — **47 days until the June 1, 2026 deadline**. The CLI-CPU project profile (open-source libre silicon, novel Cognitive Fabric architecture, actor-native processor, Neuron OS vision) **makes it a particularly strong candidate**.

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.1 | 2026-04-17 | Added estimated work hours summary + NLnet grant alignment section. AI-assisted development estimates. |
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
