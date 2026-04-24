# CLI-CPU — Tool openness and the "libre silicon" strategy

> Magyar verzió: [tool-openness-hu.md](tool-openness-hu.md)
>
> Version: 1.0

This document records the **licensing status** of tools used in CLI-CPU development and the project's **openness strategy**. The NLnet NGI Zero Commons Fund application explicitly mentions "libre silicon" as a funding criterion, making it important that the project's philosophy here is transparent and consistent.

## Core principle — two separated layers

CLI-CPU distinguishes between two independent openness dimensions:

1. **Output openness** — what the project **produces** (RTL, silicon GDSII, documentation, software, Neuron OS): **fully open source**.
2. **Process openness** — what the project **uses** during development (dev tools, CAD, simulator): **pragmatic mix**.

**The output is 100% libre; in the process, every tool is open where a realistic alternative exists, and we use closed tools only where the hardware or shuttle platform mandates it.**

This strategy matches industry practice: **SpinalHDL, NaxRiscv, LibreCores**, and nearly every NLnet-funded libre silicon project follows the same model.

## Outputs — fully open source

| Output | License | Location |
|--------|---------|----------|
| CLI-CPU ISA specification | CC-BY-SA 4.0 | `docs/ISA-CIL-T0-en.md` |
| C# reference simulator | MIT | `src/CilCpu.Sim/` |
| C# linker and runner | MIT | `src/CilCpu.Linker/`, `src/CilCpu.Sim.Runner/` |
| xUnit tests (259+) | MIT | `src/CilCpu.Sim.Tests/` |
| Verilog RTL (ALU, decoder, microcode) | Apache 2.0 | `rtl/src/` |
| cocotb testbench | Apache 2.0 | `rtl/tb/` |
| FPGA bring-up smoke test | Apache 2.0 | `rtl/fpga/smoke_test/` |
| Roadmap, architecture, security model | CC-BY-SA 4.0 | `docs/` |
| Neuron OS vision and SDK (F7) | MIT + Apache 2.0 | `NeuronOS/` |
| Silicon GDSII (F3, F6-Silicon) | Apache 2.0 | `tt/`, `mpw/` |

**All of these are in the project's public GitHub repository, open for pull requests and community contributions.**

## The process — phase-by-phase tool matrix

The table below lists tools used in each development phase with their licensing status.

### F0 — Specification

| Tool | Role | License | Open? |
|------|------|---------|-------|
| Markdown, Git | Document management | Public / GPL-2.0 | ✅ |
| GitHub | Hosting, issue tracker, PRs | Closed platform | ⚠️ (but GitLab mirror possible) |

### F1 — C# reference simulator (DONE)

| Tool | Role | License | Open? |
|------|------|---------|-------|
| .NET 10 SDK | Platform | MIT | ✅ |
| Roslyn C# compiler | Compilation | Apache 2.0 | ✅ |
| xUnit 2.9.3 | Test framework | Apache 2.0 | ✅ |
| Microsoft.CodeAnalysis.CSharp | Linker support | Apache 2.0 | ✅ |

**Fully open source.**

### F1.5 — Linker, Runner, Samples (DONE)

Same as F1 — `System.Reflection.Metadata` (built into .NET, MIT) added.

**Fully open source.**

### F2 — RTL (in progress)

| Tool | Role | License | Open? |
|------|------|---------|-------|
| Verilog (language) | RTL description | Standard (IEEE 1364) | ✅ |
| Verilator | Simulation | LGPL-3 | ✅ |
| cocotb | Python test framework | BSD-3 | ✅ |
| Yosys | Synthesis (Sky130 target, F2.6) | ISC | ✅ |
| GTKWave | Waveform viewer (debug) | GPL-2 | ✅ |

**Fully open source.**

### F2.7 — FPGA validation (current, 2026-04-24)

| Tool | Role | License | Open? |
|------|------|---------|-------|
| **Vivado ML Standard 2024.2** | FPGA synthesis + bitstream | AMD EULA (gratis, closed) | ❌ **closed** |
| A7-Lite 200T board | Physical hardware | MicroPhase (closed HW design) | ❌ **closed** |

**This is where closed tools appear.** **This is the only phase in the entire project where development requires a closed tool.**

### F3 — Tiny Tapeout (silicon)

| Tool | Role | License | Open? |
|------|------|---------|-------|
| OpenLane2 | Silicon P&R automation | Apache 2.0 | ✅ |
| Magic | Layout editor | BSD-style | ✅ |
| KLayout | GDSII viewer | GPL-3 | ✅ |
| Netgen | LVS (Layout vs Schematic) | GPL-2 | ✅ |
| Sky130 PDK | Open PDK (SkyWater/Google) | Apache 2.0 | ✅ |
| Yosys | Synthesis | ISC | ✅ |
| OpenROAD | Placement + Routing | BSD-3 | ✅ |
| Tiny Tapeout harness | Ready shuttle environment | Apache 2.0 | ✅ |

**Fully open source silicon pipeline.**

### F4–F5, F6-FPGA — Multi-core and heterogeneous FPGA

Same as F2.7 — **Vivado** for FPGA, everything else (simulation, RTL, verification, tests) is **open source**.

### F6-Silicon — "Cognitive Fabric Zero / One" (silicon)

| Tool | Role | License | Open? |
|------|------|---------|-------|
| OpenLane2 / Caravel / OpenFrame harness | ChipIgnite (Sky130) | Apache 2.0 | ✅ |
| IHP Open PDK | IHP SG13G2 (alternative) | Apache 2.0 | ✅ |
| All F3 tools | Same | | ✅ |

**Fully open source silicon pipeline.**

### F7 — Neuron OS SDK

| Tool | Role | License | Open? |
|------|------|---------|-------|
| .NET 10 + Roslyn | Platform | MIT / Apache 2.0 | ✅ |
| NuGet | Package manager | Apache 2.0 | ✅ |
| Visual Studio Code | Developer IDE | MIT (code), closed (Microsoft.Code build) | ⚠️ VSCodium open build available |

**Almost entirely open source** — only the optional telemetry-containing VSCode build is closed.

## Why Vivado — and why not OpenXC7 yet?

In F2.7 and F4–F5, Vivado is the only closed tool. Three concrete reasons:

**1. The hardware dictates.** MicroPhase A7-Lite uses a **Xilinx Artix-7** chip. Its bitstream format is **closed**, and natively **only Xilinx/AMD Vivado** can generate it. Not a chosen constraint, but a physical one.

**2. An open alternative exists: OpenXC7 — and it's more mature than commonly assumed.** **OpenXC7** (Yosys + Nextpnr + Project X-Ray) is an **actively maintained** project (last `prjxray-db` commit 2026-04-24 — within days, `nextpnr-xilinx` 2026-04-18). It supports the entire Xilinx 7-series family, including Artix-7.

**What works as of April 2026 for our A7-Lite 200T:**
- **`xc7a200tfbg484`** (exactly our chip) **is present in prjxray-db** across all 4 speed grades (1, 2, 2L, 3)
- **Rich primitive support:** `MMCME2_ADV/BASIC`, `PLLE2_ADV/BASIC`, `OSERDESE2`, `ISERDESE2`, `IDDR`, `ODDR`, `IDELAYE2`, `ODELAYE2`, `IDELAYCTRL`, `BUFG`, `BUFGCTRL`, `BUFH`, `BUFHCE`, `DSP48E1`, `GTPE2_COMMON`, `GTPE2_CHANNEL`
- **DDR3 demo exists** for Arty S7 (Spartan-7) board with similar primitive family — Artix-7 DDR3 MIG is likely close to stable
- ✅ **LED blink smoke test RAN on A7-Lite 200T** (2026-04-24): full pipeline Yosys 0.38 → nextpnr-xilinx 0.8.2 → fasm2frames → xc7frames2bit. Bitstream: 9.3 MB uncompressed, chipdb: 331 MB (generated once). See `rtl/fpga/smoke_test/OpenXC7/` for the reproducible build.
- ✅ **Board programmed with openFPGALoader v1.1.1, bypassing Vivado entirely** (2026-04-24): WSL2 + usbipd-win USB-passthrough → `openFPGALoader --cable ft232 --fpga-part xc7a200tfbg484 --bitstream led_blink.bit` → `isc_done 1 init 1 done 1` → LEDs blink. **The entire F2.7 development loop (synth + P&R + bitstream + programming) runs on a 100% open source toolchain**.

**What we DON'T know for certain:**
- No specific **XC7A200T demo in the `demo-projects` repo** (largest validated Artix-7 demo is 100T)
- **No Gigabit Ethernet demo anywhere** in the repo family — critical for F6 multi-board bridge
- **No published Vivado vs OpenXC7 QoR benchmarks** — the ~20–30% expected QoR gap is estimated, not measured
- **DDR3 MIG calibration stability on our A7-Lite** is undocumented

**Realistic migration timeline:** **within 6–18 months** (late 2026 to mid-2027) OpenXC7 can likely be added as a parallel CI for CLI-CPU — especially because F2.7 LED blink and F4 Nano core don't really use DDR3 or Ethernet, only basic MMCM and UART. F5 (DDR3 for GC heap) and F6 (Ethernet bridge) depend on OpenXC7 only if someone validates them on A7-Lite by then.

**3. Vivado ML Standard is FREE.** The WebPACK license (`Vivado ML Standard Edition`) is **at no cost**, and supports all Artix-7 chips up to XC7A200T. No financial or legal restrictions for research, hobby, or even commercial use. This is "gratis" (free of charge), though not "libre" (open-source).

**Gratis ≠ libre, but in practice the difference matters only if:**
- The project **cannot reproduce** its results without the closed tool — **CLI-CPU can**, because the silicon pipeline (F3, F6-Silicon) is fully open
- The closed tool **forces missing functionality** — Vivado doesn't dictate design constraints
- Tool discontinuation **would block development** — Vivado has been available for 20+ years, AMD is expected to maintain it

## Path toward greater openness

Three concrete steps the CLI-CPU project can take to proactively reduce Vivado dependence:

### 1. OpenXC7 parallel CI flow (around F4, late 2026)

Based on the updated estimate, parallel CI can be introduced as early as **F4** (4-core Cognitive Fabric FPGA, requires only MMCM + UART, no DDR3 or Ethernet):
- Every RTL PR runs **Vivado** synthesis (for the official bitstream)
- **And** runs **OpenXC7** synthesis (as a verification that no Vivado-specific code has leaked in)

This **doesn't increase** dependence — it **decreases** it — by guaranteeing that no Vivado-only constructs creep into the codebase. Already at **F2.7 LED blink** it's worth running an experimental OpenXC7 build to learn the toolchain's strengths and weak spots on our own project.

**Migrating F5+ (DDR3) and F6 (Ethernet) to OpenXC7** depends on:
- Whether A7-Lite DDR3 MIG calibration is stable under OpenXC7 (likely to be validated during 2026, either by the community or by us)
- Whether Gigabit Ethernet RGMII works reliably

If these are validated by mid-2027, a **fully Vivado-free FPGA pipeline** may be reachable before F6-Silicon tape-out.

### 2. Yosys Sky130 synthesis now (F2.6)

The **F2.6** phase's output is **Yosys** synthesis against the **Sky130 PDK**. This works **without Vivado** and is the path used for F3 Tiny Tapeout submission. Vivado **doesn't even enter the picture** in this phase — the silicon manufacturing path is 100% open.

So the **"official" silicon bitstream** (for the Tiny Tapeout chip) is produced entirely by **open source toolchain** — Vivado only appears in the **intermediate FPGA verification** phase.

### 3. Long-term goal — full OpenXC7 migration

The project's documented intent is that **as soon as OpenXC7 maturity allows** (expected mid-2027 for the F2–F4 scope, late 2027 or early 2028 for the F5–F6 DDR3/Ethernet scope), the entire FPGA flow will be moved to the open toolchain. This **is only a question of time** — no new design is needed, the existing Verilog RTL runs on both.

## Comparison to other libre silicon projects

| Project | Silicon toolchain | FPGA dev tool | Policy |
|---------|-------------------|---------------|--------|
| **CLI-CPU (this)** | OpenLane2 / Sky130 (open) | Vivado (closed) | Silicon open, FPGA pragmatic |
| **NaxRiscv** (SpinalHDL) | OpenLane / Sky130 (open) | Vivado (Kintex-7) | Same |
| **OpenPiton** | Multi-fab (partially open) | Vivado / Quartus | Same |
| **PicoRV32** | Yosys + OpenLane (open) | Vivado / iCE40 open | Where possible, open |
| **CVA6 (Ariane)** | PULP flow + OpenLane | Vivado (Genesys-2) | Same |

**This is industry-standard for libre silicon projects.** NLnet evaluators and the community alike know and accept this model — as long as the **output** and the **silicon pipeline** are open, the closed FPGA dev tool is a **pragmatic necessity**, not an ideological compromise.

## Summary — "What is CLI-CPU's libre silicon status?"

- **All project outputs (RTL, ISA, specs, software, silicon) are open source.** ✅
- **The silicon manufacturing pipeline (F3, F6-Silicon) is fully open source.** ✅
- **In FPGA development phases (F2.7, F4–F5, F6-FPGA) Vivado is closed but free (gratis).** ⚠️
- **The project proactively plans to migrate to an open FPGA toolchain (OpenXC7) once maturity allows.** ✅
- **This is the industry standard for libre silicon projects; NLnet accepts this model.** ✅

**CLI-CPU is unambiguously a libre silicon project** — the "libre" label applies to the project's outputs and silicon pipeline, not to every single dev tool. The **gratis but not libre** Vivado usage in FPGA dev phases is a pragmatic choice, not a compromise.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-24 | Initial version — written on the occasion of the first FPGA bring-up (F2.7 smoke test), when Vivado first entered the dev flow. OpenXC7 maturity assessment based on direct repo inspection (xc7a200tfbg484 in prjxray-db, MMCM/PLL/IDDR/ODDR/IDELAY/DSP48/SerDes/GTP primitives supported, active maintenance). |
