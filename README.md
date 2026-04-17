# CLI-CPU

> **Trustworthy Cognitive Fabric -- memory safety baked into silicon + many small CIL-native cores on a single chip, communicating via mailbox messages, operating in an event-driven fashion.**
> No JIT. No AOT. No interpreter. CIL bytes go straight into the hardware -- **and hardware-enforced security cannot be bypassed.**

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 1.0

[clicpu.org](https://clicpu.org) *(coming soon)*

## Quick Start

```bash
git clone https://github.com/FenySoft/cli-cpu.git
cd cli-cpu
dotnet build CLI-CPU.sln -c Debug
dotnet test

# The CIL opcodes in the .dll are the SAME ones the CPU executes natively.
# The linker only repackages them from the PE/COFF container (.dll) into
# a flat binary (.t0) that the hardware can boot from — no translation.
# (The Rich core in F5+ will load .dll files directly via metadata walker,
#  after mandatory PQC signature verification.)

dotnet run --project src/CilCpu.Sim.Runner -- link samples/PureMath/bin/Release/net10.0/PureMath.dll --class Math --method Fibonacci -o fibonacci.t0
dotnet run --project src/CilCpu.Sim.Runner -- run fibonacci.t0 --args 20
```

## What is this?

The **Cognitive Fabric Processing Unit (CFPU)** is a new category of processing unit: **many small, independent CIL-native cores on a single chip**, communicating exclusively through **hardware mailbox FIFOs** in a shared-nothing model. Alongside the *CPU / GPU / TPU / NPU* family, the **CFPU** is the first **MIMD actor-native** processing unit — where each core runs arbitrary CIL programs with hardware-enforced isolation.

**CLI-CPU** is the **reference implementation of the CFPU** — the open-source project that realises the CFPU architecture in a C# simulator, then in RTL, then in silicon. CLI-CPU **executes .NET CIL bytecode natively in hardware**, without any compilation step. Each core runs a complete CIL program with its own local state -- no shared memory, no cache coherence, no lock contention.

Depending on the program, the same hardware can serve as:

- **A native Akka.NET / Orleans actor cluster** -- in hardware, with zero overhead
- **A programmable spiking neural network** -- each core running a LIF / Izhikevich / custom neuron model
- **A multi-agent simulation** -- swarm intelligence, cellular automata, complex systems
- **An event-driven dataflow pipeline** -- DSP, stream processing
- **An IoT edge gateway** -- many sensors, parallel processing, ultra-low power consumption
- **An embedded web server** -- one core per request

**One piece of hardware, many paradigms.** This is a position that no existing system occupies: there is no chip that is simultaneously **hardware-based + fully programmable nodes + open source + .NET native**. Existing neuromorphic chips (Intel Loihi, IBM TrueNorth, BrainChip Akida) all use **fixed neuron models**; software-based actor systems (Akka.NET, Erlang) are flexible but compete on the host CPU against scheduler, GC, and lock overhead.

## Why not the classic "bytecode CPU" approach

Sun's **picoJava** (1997) and ARM's **Jazelle** (2001) attempted exactly what CLI-CPU might naively try: a conventional, single-core bytecode-native processor as an alternative to software JIT. **Both failed**, because software JIT on general-purpose CPUs became cheaper and faster than dedicated hardware within a few years.

**CLI-CPU does not repeat this mistake.** It does not try to compete with modern OoO CPUs on single-core speed -- that is impossible. Instead, it positions itself in a **different dimension**: many small independent cores, event-driven operation, shared-nothing isolation, and a programming model that **naturally fits modern .NET applications** (Task, async/await, Akka.NET, Orleans, Channel). CLI-CPU **does not run C# -- it runs CIL**: every .NET language (C#, F#, VB.NET, IronPython, PowerShell) runs natively on the hardware, tapping into the existing codebase of ~8 million developers. This is the **first hardware platform that provides native silicon for an entire software ecosystem**.

Details in the **"Strategic Positioning: Cognitive Fabric"** section of `docs/architecture.md`.

## Four trump cards

1. **Silicon-grade security** -- memory safety, type safety, and control flow integrity are **physical properties of the silicon**, not software abstractions. Immune to Spectre/Meltdown-class microarchitectural attacks (no speculative execution), ROP/JOP attacks (hardware CFI), buffer overflows (hardware bounds checking), and JIT spraying (no JIT). **Formally verifiable** ISA, building on lessons from CompCert/seL4. Details: [`docs/security-en.md`](docs/security-en.md).
2. **Code density** -- CIL bytecode is 30-50% more compact than RISC-V RV32I or ARM Thumb-2 for equivalent functionality -- less flash, lower power, **more neurons fit on a single chip**.
3. **Shared-nothing scalability** -- since there is no shared memory between cores, performance **scales linearly** with core count. No MESI, no cache coherency overhead, no lock contention, no cross-core side channels.
4. **Event-driven power profile** -- cores are in sleep mode by default and only wake when a mailbox message arrives. **Ultra-low baseline power consumption**, which is critical for IoT, critical infrastructure, and neuromorphic workloads.

## Three-track positioning -- long-term successor to Linux

CLI-CPU + [**Neuron OS**](https://neuron-os.org) pursues **three parallel market narratives** built on the same hardware foundation, all serving a **single shared historical goal**: **replacing the 1970s Unix foundations inherited by Linux** with a modern, secure, scalable, actor-based architecture.

> **Companion project:** [**neuron-os.org**](https://neuron-os.org) ([source on GitHub](https://github.com/FenySoft/NeuronOS)) — the capability-based actor runtime co-designed with the CFPU. Runs on any .NET host today; targets CFPU silicon tomorrow. Apache-2.0.

**Track 1 -- "Cognitive Fabric"**: a programmable cognitive substrate for AI researchers, Akka.NET / Orleans actor systems, spiking neural network simulation, multi-agent simulation, and IoT edge gateways. **Long-term vision.**

**Track 2 -- "Trustworthy Silicon"**: a formally verifiable, certifiable processor for regulated industries -- automotive (ISO 26262 ASIL-B/C/D), aviation (DO-178C), medical (IEC 62304), critical infrastructure (IEC 61508 SIL-3/4), AI safety watchdog, and confidential computing. **Short-to-medium-term revenue opportunity.**

**Track 3 -- "Secure Edition"**: transforming the JavaCard / TEE / Secure Element market -- a parallel tape-out alongside the main F6, adding Crypto Actor + TRNG + PUF + tamper detection + DPA countermeasures. **First products: open banking card, open eSIM, open eID, open FIDO2 authenticator, open TPM, open hardware wallet, open V2X secure element, open medical SE.** Key differentiator: **multiple independent hardware security domains on a single chip**, which existing open alternatives (TROPIC01, OpenTitan) **do not offer**. Details: [`docs/secure-element-en.md`](docs/secure-element-en.md).

Same chip family, three different market segments -- **but the same historical goal**: just as x86 replaced the mainframe, mobile replaced the desktop, and the cloud replaced the on-prem data center, **the Cognitive Fabric + Neuron OS will be the next replacement cycle**, delivering the OS for the modern, AI-driven, safety-critical, massively distributed era. Details in the "The inherited problems of Linux and Neuron OS's answer" section of [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md).

## Heterogeneous multi-core: CFPU Nano + CFPU Rich

Starting from phase F5, the CFPU employs a **heterogeneous multi-core** architecture, analogous to ARM big.LITTLE, Apple P-core + E-core, and Intel Alder Lake -- but applied to the .NET world:

| | **CFPU Nano** | **CFPU Rich** |
|-|---------------|---------------|
| ISA | CIL-T0 (48 opcodes, integer-only) | Full ECMA-335 CIL (~220 opcodes) |
| Size | ~10k std cells | ~80k std cells |
| Features | Integer, stack cache, mailbox | Nano + object model + GC + FPU + exceptions + generics |
| Role | Worker / neuron / filter / simple actor | Supervisor / orchestrator / complex domain logic |
| Typical count on F6 | **16** (workers) | **6** (supervisors) + **1 Secure Core** |

C# programs use **`[RunsOn(CoreType.Nano)]`** or **`[RunsOn(CoreType.Rich)]`** attributes to indicate which class targets which core type. A Roslyn source generator verifies at build time that Nano-targeted code uses **only** CIL-T0 opcodes.

## Status

**F1.5 -- DONE.** The C# reference simulator (48/48 CIL-T0 opcodes, 250+ green tests), the Roslyn-to-CIL-T0 linker, the CLI runner (`run` / `link` commands), and the PureMath sample program are all complete. The next step is **F2 -- RTL** (Verilog/Amaranth HDL).

See [docs/roadmap-en.md](docs/roadmap-en.md) for the full phase breakdown.

## Blog

- [Why I'm Building a CPU That Runs .NET Natively](https://medium.com/@hj_84657/why-im-building-a-cpu-that-runs-net-natively-5242e4b9da1f) -- also on [clicpu.org](https://clicpu.org/en/blog/why-cli-cpu.html)

## Documents

- [docs/roadmap-en.md](docs/roadmap-en.md) -- Seven-phase roadmap from F0 to F7, with the Cognitive Fabric pivot at F4 and the F6.5 Secure Edition variant
- [docs/architecture-en.md](docs/architecture-en.md) -- CLI-CPU microarchitecture, Cognitive Fabric positioning, prior art analysis (picoJava, Jazelle, Transmeta, Loihi, SpiNNaker), heterogeneous Nano + Rich multi-core
- [docs/ISA-CIL-T0-en.md](docs/ISA-CIL-T0-en.md) -- CIL-T0 subset specification (48 opcodes), mailbox MMIO interface
- [docs/security-en.md](docs/security-en.md) -- Threat model, architectural security guarantees, attack immunity table, formal verification plan, certification paths (IEC 61508, ISO 26262, DO-178C, IEC 62304)
- [Neuron OS vision](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md) -- an actor-based operating system for the CFPU, "Erlang in silicon". **Implementation:** [github.com/FenySoft/NeuronOS](https://github.com/FenySoft/NeuronOS) (the vision document also lives there; local redirect stub: [`docs/neuron-os-en.md`](docs/neuron-os-en.md))
- [docs/secure-element-en.md](docs/secure-element-en.md) -- Secure Edition: JavaCard / TEE / Secure Element market, detailed TROPIC01 analysis, multi-SE hardware isolation, F6.5 parallel tape-out plan
- [docs/faq-en.md](docs/faq-en.md) -- FAQ: conceptual anchors for new readers (CLI vs CIL, CPU comparison, scheduling costs)
- [docs/vision-en.md](docs/vision-en.md) -- The shared-nothing future: OS, GUI, database, networking, and programming model reimagined

## Manufacturing path

| Phase | Goal | Platform |
|-------|------|----------|
| F0 | Spec documents | -- |
| F1 | C# reference simulator (TDD) | .NET |
| F2 | RTL (Verilog/Amaranth) + cocotb, single Nano core | simulation |
| F3 | **Tiny Tapeout submission** -- 1x Nano core + mailbox MMIO, first network-ready node | Sky130, ~$150 |
| F4 | **Cognitive Fabric pivot** -- 4x Nano core FPGA, shared-nothing, event-driven | A7-Lite 200T, ~$320 |
| F5 | **Rich core introduction** -- 2x Rich + 8x Nano (full CIL) FPGA, first heterogeneous system | same FPGA |
| **F6-FPGA** | **FPGA-verified distributed Cognitive Fabric** -- 3x A7-Lite 200T multi-board Ethernet mesh, 2R + ~26N, location transparency | 3x A7-Lite 200T, ~$960 |
| F6-Silicon | **Cognitive Fabric in real silicon** *(only after F6-FPGA verification)* -- the FPGA-verified design on real silicon | Sky130 ChipIgnite or IHP MPW, ~$10k |
| F7 | Demonstration platform + Neuron OS seeds | PCB + software |

## License

[CERN Open Hardware Licence Version 2 — Strongly Reciprocal (CERN-OHL-S v2)](LICENSE)

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
