# Brand and Naming Guide — Cognitive Fabric, CFPU, CLI-CPU

> Magyar verzió: [brand-hu.md](brand-hu.md)

> Version: 1.0

This document is the **canonical reference** for the three names that appear together throughout this project: **Cognitive Fabric**, **CFPU**, and **CLI-CPU**. They are not synonyms. Each refers to a different layer (architecture family, processor category, reference implementation), and the wrong choice in a sentence quietly distorts the meaning.

If you only have time to read one section, read [§ 4 — When to use which term](#4-when-to-use-which-term).

---

## 1. The three layers

```
Cognitive Fabric          ← architecture family / vision
  │
  └── CFPU                ← the processing-unit category
        │   (Cognitive Fabric Processing Unit — sibling of CPU/GPU/TPU/NPU)
        │
        ├── CFPU Nano     ← integer-only worker core         (product line)
        ├── CFPU Actor    ← actor-native event-driven core   (product line)
        ├── CFPU Rich     ← full CIL + GC + FPU + supervisor (product line)
        ├── CFPU Matrix   ← MAC-slice ML accelerator         (product line)
        └── CFPU Seal     ← secure boot / trust anchor       (product line)
        │
        └── CLI-CPU       ← the open-source reference implementation
              │             of the CFPU category — this project
              ├── repo:       github.com/FenySoft/CLI-CPU
              ├── simulator:  CilCpu.Sim
              ├── linker:     CilCpu.Linker
              ├── ISA spec:   CIL-T0 (and CIL-Seal for the Seal core)
              └── license:    CERN-OHL-S (hardware) + Apache-2.0 (software)
```

The pattern matches well-known industry split-ups:

| Vision / family | Category | Reference implementation |
|-----------------|----------|--------------------------|
| Unix-like OS    | OS kernel | **Linux** (Linus Torvalds, 1991) |
| Open browser    | Browser engine | **Chromium** (Google, 2008) |
| Open WebKit     | Browser engine | **WebKit** (Apple/KDE, 2001) |
| **Cognitive Fabric** | **CFPU** | **CLI-CPU** (FenySoft, 2026) |

Just as Linux is *one* implementation of the Unix-like-OS idea, **CLI-CPU is one implementation of the CFPU category**. Other CFPU implementations may follow — the category is open.

---

## 2. Definitions

### 2.1 Cognitive Fabric

**Definition:** the architecture *family* — the high-level vision and the marketing narrative.

A Cognitive Fabric is a chip (or many chips) made of **many small, independent, CIL-native cores** that communicate through **shared-nothing message passing**. There is no shared memory, no cache-coherence protocol, no lock contention. Each core runs a complete program with its own local state; cores wake on inbound messages.

This is the *vision* level. It does not commit to a specific number of cores, a specific ISA subset, a specific package format, or a specific manufacturing node. "Cognitive Fabric" is what we put on slides, in blog posts, in the elevator pitch.

**Sibling terms in industry:** *neuromorphic*, *dataflow*, *systolic*, *manycore* — but Cognitive Fabric is **MIMD actor-native** (every core runs a *different* program), which separates it from all four.

### 2.2 CFPU — Cognitive Fabric Processing Unit

**Definition:** the processing-unit *category* — sibling of CPU, GPU, TPU, NPU.

CFPU is *what kind of chip* this is. It is **not** a product name and **not** a project name. It is a category that future implementations (from FenySoft or others) can fall under, the same way "GPU" covers NVIDIA, AMD, and Intel parts.

| Category | Paradigm | Example workload |
|----------|----------|------------------|
| CPU      | SISD / MIMD (shared memory) | general purpose |
| GPU      | SIMD (data parallel) | matrix, shader |
| TPU      | Systolic array | neural inference (fixed) |
| NPU      | Fixed neuron model | neural inference (edge) |
| **CFPU** | **MIMD (shared-nothing, actor)** | **actor systems, SNN, multi-agent, IoT edge** |

Within CFPU we have **product lines** (core types), each addressable by a suffix:

| Product line | Suffix | Role |
|--------------|--------|------|
| CFPU Nano    | -N     | Integer-only worker, smallest area |
| CFPU Actor   | -A     | Event-driven actor core |
| CFPU Rich    | -R     | Full CIL with GC, FPU, supervisor |
| CFPU Matrix  | -ML    | MAC-slice ML accelerator |
| CFPU Seal    | -H     | Hardened secure-boot / trust anchor |

These are described in [docs/core-types-en.md](core-types-en.md).

**Why not "CFP":** the abbreviation **CFP** is heavily reserved in the hardware industry (*C Form-factor Pluggable* — 100G/400G optical-transceiver MSA). The trailing **\*PU** in **CFPU** is unambiguously a processing unit, with no industry collision.

### 2.3 CLI-CPU

**Definition:** the *project* — this open-source repository and everything it produces.

CLI-CPU is the **first** reference implementation of the CFPU category. It is the:

- **GitHub repo:** [github.com/FenySoft/CLI-CPU](https://github.com/FenySoft/CLI-CPU)
- **C# simulator** (`CilCpu.Sim`) — cycle-accurate reference model
- **Linker** (`CilCpu.Linker`) — Roslyn `.dll` → CIL-T0 binary
- **CLI runner** (`CilCpu.Sim.Runner`) — `run` and `link` commands
- **ISA spec** (`CIL-T0`) — the bytecode the silicon executes
- **RTL** (forthcoming, F4–F6) — the Verilog/Chisel that becomes the chip
- **NLnet grant** application and project plan

Anything that is a **build artefact**, a **commit**, a **test target**, a **roadmap milestone**, or a **license declaration** belongs to *CLI-CPU*. The name appears in `git log`, in the `.csproj` files, on the issue tracker, on the funding application.

CLI-CPU was the *first* name (chosen before "Cognitive Fabric" was coined), which is why the repo, the GitHub org, the simulator, and the ISA all carry it. The name is permanent for the project — but the chips that come out of it carry **CFPU** product names.

---

## 3. Why three names instead of one

The three-name split exists because each name does work the others cannot:

- A **product** (e.g. "CFPU-R Rich core") needs to be sellable, brand-able, and category-comparable to GPU/TPU/NPU. Calling it "CLI-CPU Rich" would make every product page look like it was named after a software project, not silicon.
- A **project** (e.g. "the CLI-CPU simulator") needs to be searchable, citeable, license-attachable, and have a stable GitHub URL. Calling it "the CFPU project" would conflate the open-source effort with future closed-source CFPU chips that may exist someday.
- A **vision** (e.g. "Cognitive Fabric is the substrate for Symphact") needs to be evocative, marketing-ready, and decoupled from any specific instruction set or core type. It is what goes on a one-line pitch deck slide.

If we collapse the three into one name, every public-facing surface — academic paper, product datasheet, grant application, README, blog post — leaks meaning into the wrong layer.

---

## 4. When to use which term

### 4.1 Use **CLI-CPU** when

- Talking about the **project**, the **repo**, the **codebase**, or **build artefacts**.
- Citing the simulator, the linker, the runner, or the ISA implementation.
- Referring to roadmap phases (F0–F7), test targets, NLnet grant, license.
- Anything that has a `git log` entry, a `.csproj`, or a GitHub issue.

**Examples:**

> *"The CLI-CPU project status is F1.5 DONE."*
>
> *"Clone: `git clone https://github.com/FenySoft/CLI-CPU`"*
>
> *"The CLI-CPU reference simulator has 250+ tests."*
>
> *"CLI-CPU is licensed under CERN-OHL-S (hardware) and Apache-2.0 (software)."*

### 4.2 Use **CFPU** when

- Talking about the **chip category** or the **architecture-level processor type**.
- Comparing against CPU / GPU / TPU / NPU.
- Naming **product lines** (CFPU Nano, CFPU Rich, CFPU-ML Matrix, CFPU-H Seal, etc.).
- Discussing **silicon-level features** (microarchitecture, mailbox, NoC, secure element).
- Writing chip datasheets, security models, threat analyses, certification documents.

**Examples:**

> *"The CFPU is a new category of processing unit."*
>
> *"CFPU-N Nano vs. CFPU-R Rich heterogeneous multi-core."*
>
> *"CFPU Security Model — threat surface and mitigations."*
>
> *"The CFPU mailbox is shared-nothing; coherence does not apply."*

### 4.3 Use **Cognitive Fabric** when

- Talking about the **architecture family**, **vision**, or **marketing narrative**.
- Naming **chips** (e.g. *Cognitive Fabric One* — the F6 reference silicon).
- Pitching the **idea** independently of any specific implementation.
- Connecting to **Symphact** as the runtime layer.

**Examples:**

> *"Cognitive Fabric is a substrate for actor-native, event-driven workloads."*
>
> *"Cognitive Fabric One — the F6-Silicon reference chip (6R+16N+1S, 15 mm²)."*
>
> *"Cognitive Fabric + Symphact is the successor to Linux on commodity CPUs."*

---

## 5. Do / Don't table

| Don't ❌ | Do ✅ | Reason |
|---------|------|--------|
| "the CLI-CPU Security Model" (in a chip-level threat doc) | "the CFPU Security Model" | Threat surface is silicon-level, not project-level |
| "CFPU repo" / "CFPU pull request" | "CLI-CPU repo" / "CLI-CPU pull request" | The repo is the project, not the category |
| "CFPU project plan" | "CLI-CPU project plan" | Project plans belong to projects |
| "CLI-CPU Nano" / "CLI-CPU Rich" | "CFPU Nano" / "CFPU Rich" | Product lines belong to the category |
| "the Cognitive Fabric repo" | "the CLI-CPU repo" | Vision is not a repo |
| "the CLI-CPU is a new category of processor" | "the CFPU is a new category of processor" | A project is not a category |
| "buy a CLI-CPU" | "buy a Cognitive Fabric One chip" / "buy a CFPU-R" | You buy chips, not projects |
| "CFPU under CERN-OHL-S" | "CLI-CPU under CERN-OHL-S" | The license attaches to the project |

---

## 6. Edge cases and overlaps

Some sentences legitimately span two layers. The rule of thumb is: **lead with the layer that owns the noun, mention the other layer parenthetically.**

- **Reference implementation:** lead with CFPU, name CLI-CPU as the implementation.
  > *"The CFPU category is open; the first reference implementation is the **CLI-CPU** project."*

- **Project status of a category:** lead with CLI-CPU, name CFPU as the category.
  > *"The **CLI-CPU** project is at F1.5; the **CFPU** silicon (Cognitive Fabric One) is targeted for F6."*

- **Marketing one-liner:** lead with Cognitive Fabric, name CFPU and CLI-CPU as the category and reference.
  > *"**Cognitive Fabric** is a new architecture family. Its processing-unit category is **CFPU**. Its open-source reference implementation is the **CLI-CPU** project."*

---

## 7. Style notes

- **Capitalisation:** all three names are capitalised in running text (`Cognitive Fabric`, `CFPU`, `CLI-CPU`). Do not write `cli-cpu` or `cfpu` in body text. In code identifiers (`CilCpu.Sim`, `CFPU_NANO`, etc.) follow the language's convention.
- **Hyphen:** `CLI-CPU` always has the hyphen. `CFPU` never has one (do not write `CF-PU`).
- **Plurals:** `CFPUs` (no apostrophe). `CLI-CPUs` is awkward — prefer "CLI-CPU instances" or "CLI-CPU implementations".
- **First mention in a doc:** spell out at least one of the abbreviations on first use. e.g. *"the **Cognitive Fabric Processing Unit (CFPU)** …"* or *"the **CLI-CPU** project (the open-source reference implementation of the CFPU category) …"*.

---

## 8. See also

- [docs/faq-en.md § 1](faq-en.md#1-what-is-the-cfpu-and-how-does-it-relate-to-cli-cpu) — the short version of this guide.
- [docs/architecture-en.md](architecture-en.md) — CFPU microarchitecture.
- [docs/core-types-en.md](core-types-en.md) — CFPU product lines (Nano / Actor / Rich / Matrix / Seal).
- [docs/security-en.md](security-en.md) — CFPU security model.
- [docs/roadmap-en.md](roadmap-en.md) — CLI-CPU project phases F0–F7.
