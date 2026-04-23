# NLnet Application — Post-Submission Corrections

> **Purpose:** This document records internal-review corrections identified AFTER the CLI-CPU NLnet NGI Zero Commons Fund application was submitted. The submitted file ([`nlnet-application-draft-en.md`](nlnet-application-draft-en.md)) is preserved unchanged as the authoritative record of what NLnet received.
>
> **How to use this document:**
> - If NLnet reviewers request clarification, respond using the refined text below.
> - The follow-up proposal (F5-F6) should incorporate these corrections from the start.
> - The parallel Neuron OS proposal ([`FenySoft/NeuronOS`](https://github.com/FenySoft/NeuronOS)) already reflects these lessons.

> Magyar verzió: [nlnet-corrections-hu.md](nlnet-corrections-hu.md)

> Version: 1.0 — 2026-04-23

---

## Correction 1 — Tiny Tapeout budget was underestimated

**Submitted text (M2 milestone + hardware subtotal):**
> "1× Tiny Tapeout 16-tile submission: ~€1,200"
> "Hardware subtotal: ~€2,440"

**Issue:** 2026 TT shuttle pricing trends higher than the €1,200 estimate; realistic 16-tile pricing is €1,500–3,000.

**Refined text:**
> Tiny Tapeout submission (8-16 tiles, depending on final shuttle pricing at submission time): **€1,500–3,000**. Plan B: if 16-tile exceeds budget, submit 8 tiles (Nano core + UART, no mailbox — mailbox verified on FPGA in M3 instead).
> Hardware subtotal range: **~€2,760–€4,360**. If hardware costs exceed the allocation, personnel hours are proportionally reduced while preserving all five milestones.

---

## Correction 2 — EU sovereignty claim needed precision

**Submitted text:**
> "European sovereignty: A fully open processor design that any European entity can manufacture, audit, and certify — independent of US/Asian IP licensing (unlike ARM, RISC-V commercial cores, or x86)."

**Issue:** F3 first silicon targets Sky130 (SkyWater, US-based PDK). Pure "European sovereignty" claim is only accurate for the HDL/design layer; fabrication path is US for F3.

**Refined text:**
> **European sovereignty (via IHP SG13G2 path):** The entire HDL/RTL stack is license-free and portable to any open PDK. F3 first silicon targets Sky130 (SkyWater, US) for the lowest-cost Tiny Tapeout entry — a deliberate pragmatic choice for initial proof-of-silicon at minimal cost. F6+ silicon is planned for **IHP SG13G2 (Germany)** — a fully European fab path with no US/Asian IP dependencies. The design is portable by construction; only the fabrication venue differs between phases.

---

## Correction 3 — M4 "Rich core RTL" scope was overstated

**Submitted text (M4 milestone):**
> "Rich core (full CIL) RTL design start: object model, GC assist, exception handling, FPU. Heterogeneous Nano+Rich FPGA demo."

**Issue:** Full Rich core RTL (~220 opcodes + GC + exceptions + FPU) is not feasible in 6 months part-time. Reviewer may flag this as unrealistic and question budget allocation of €7,000.

**Refined text:**
> **M4: Rich core specification + microarchitecture (F5 start).** Rich core **specification and microarchitectural design** — not full RTL: object model, GC assist, exception handling, FPU, all documented in RFC-style specs with cycle-accurate microarchitectural diagrams. First 30-40 opcodes implemented as a synthesizable proof-of-concept block. Heterogeneous Nano+Rich FPGA demo is a **stretch goal**. Full Rich core RTL implementation is scoped for a dedicated follow-up grant (F5 proper).

---

## Correction 4 — Duplicate paragraph on hardware-level security

**Submitted text:** The "Why this matters for the NGI ecosystem" section contains a standalone "Growing relevance of hardware-level security" bullet AND the "Why now?" paragraph repeats the same theme.

**Issue:** Content duplication. Reviewers notice repetition.

**Refined text:** Merge into a single "Why now?" paragraph:
> **Why now?** The convergence of open PDKs (Sky130, IHP SG13G2), mature actor-model frameworks (Akka.NET, Orleans), the end of Dennard scaling pushing toward many-core architectures, the democratization of silicon (Tiny Tapeout, eFabless), and the growing urgency of hardware-level security against escalating cyber threats — software-only measures are increasingly insufficient against supply chain attacks (log4j, xz-utils), AI-generated exploits, and state-level threats — makes a many-core bytecode-native approach viable and necessary in 2026 where single-core picoJava failed in 1997. CLI-CPU's hardware-enforced memory safety, type safety, and control flow integrity cannot be bypassed by any software exploit.

---

## Correction 5 — "8 million .NET developers" needed grounding

**Submitted text:**
> "8 million .NET developers can target this hardware using familiar tools"

**Issue:** Round number without citation reads as marketing. Technical reviewers may discount the claim.

**Refined text:**
> A **large existing .NET developer base** can target this hardware using familiar tools. Every .NET language (C#, F#, VB.NET) compiles to CIL. Microsoft's annual developer surveys and Akka.NET / Orleans production deployments demonstrate the runtime's entrenched position in enterprise software — particularly in regulated industries (financial services, government, healthcare) where the CLI-CPU security model is most valuable.

---

## Correction 6 — Parallel Neuron OS proposal needed disclosure

**Submitted text (funding sources):**
> "There are no pending applications to other funding bodies for the same work."

**Issue:** Since submission, a parallel NLnet proposal for **Neuron OS** has been drafted. While the two projects are scope-separated (hardware vs. software), transparency is required.

**Refined addendum:**
> A parallel NLnet NGI Zero Commons Fund application is planned (Q3 2026 submission window) for the **Neuron OS** project ([`FenySoft/NeuronOS`](https://github.com/FenySoft/NeuronOS)) — the capability-based actor runtime co-designed with, but scope-separated from, this hardware proposal.
>
> | Dimension | CLI-CPU / CFPU | Neuron OS |
> |-----------|---------------|-----------|
> | Deliverable | Hardware ISA, RTL, silicon tape-out, FPGA | Software runtime, OS services |
> | Target | Verilog synthesis, Sky130 PDK | .NET 10 library (runs on Windows/Linux/macOS) |
> | License | CERN-OHL-S-2.0 | Apache-2.0 |
> | Repository | `FenySoft/CLI-CPU` | `FenySoft/NeuronOS` |
> | Milestones | F2 RTL, F3 Tiny Tapeout, F4 FPGA multi-core | M0.3-M3.2 actor runtime + kernel actors |
>
> The two proposals are deliberately non-overlapping in scope. Neuron OS does not depend on CLI-CPU silicon (it runs on simulators today); CLI-CPU does not depend on Neuron OS (the hardware has its own reference C# simulator).

---

## Correction 7 — IHP MPW eligibility required clarification

**Submitted text:**
> "IHP SG13G2 free MPW: Application planned for the October 2026 shuttle."

**Issue:** The free/research IHP MPW channel typically requires an academic institutional host. FenySoft Kft. (commercial entity) alone is not eligible for free MPW slots — this was not acknowledged.

**Refined text:**
> **IHP SG13G2 MPW (F6+), 2027+:** The free/research IHP MPW channel typically requires an academic institutional host. FenySoft Kft. alone is not eligible for free slots. For F6 silicon we will pursue one of three paths:
> - (a) Partner with a Hungarian university (BME Department of Electron Devices or SZTAKI) as co-applicant to access EUROPRACTICE research credit.
> - (b) Apply through a separate commercial MPW grant (e.g., Horizon Europe digital sovereignty call).
> - (c) Fund a commercial IHP mini@shuttle (~€15-30K) from follow-up grants.
>
> This path is **not covered by the current proposal** and represents follow-up work.

---

## Correction 8 — Sustainability plan needed more concrete channels

**Submitted text (sustainability plan):**
> "(1) Follow-up NLnet proposal for F5-F6 (Rich core + silicon tape-out). (2) IHP SG13G2 free MPW application for research-grade silicon. (3) Long-term: dual licensing model (CERN-OHL-S for open version, commercial license for certified products). (4) GitHub Sponsors / Open Collective for ongoing community maintenance."

**Issue:** Four bullets, one of which (IHP free MPW) was corrected above. Reviewer typically wants to see a path to self-sustainability within 3 years.

**Refined text (6 channels):**
> 1. **Grant chain:** Follow-up NLnet proposal for F5-F6 (Rich core RTL + silicon tape-out), projected €50-150K. Parallel Neuron OS grant provides cross-ecosystem legitimacy.
> 2. **European research pathways:** Chips JU / TRISTAN consortium participation as a non-RISC-V contributor (CIL ISA as a complementary target); Horizon Europe digital sovereignty calls; IHP SG13G2 research-grade silicon via academic partnership.
> 3. **Dual licensing model:** Core repo stays CERN-OHL-S-2.0 (strong reciprocal). Commercial licenses available for (a) certified products (IEC 61508, ISO 26262, IEC 62304) and (b) proprietary derivative RTL — analogous to MariaDB / MongoDB business model applied to silicon.
> 4. **Consulting / integration services (FenySoft Kft., existing entity):** Custom CFPU integration for regulated industries (healthcare, critical infrastructure) provides cross-subsidy for open-core maintenance.
> 5. **Online certification / training:** CFPU architecture and secure-by-design hardware development certification courses (see `project_monetization_model` note).
> 6. **Community funding channels:** GitHub Sponsors / Open Collective launched at Month 6. Target: €500–1500/month steady state by end of Year 2.
>
> **.NET Foundation membership application** at Month 12 for infrastructure support (code signing, CLA management, Azure hosting — no direct funding but community legitimacy).
>
> The project has a **documented path to self-sustainability within 3 years** without continuous grant dependency.

---

## Correction 9 — Team risk (single applicant) needed mitigation language

**Submitted text:** No explicit mention of contributor growth plan.

**Issue:** Single-applicant projects are a documented risk factor for NLnet. The submitted text did not address this.

**Refined addendum (add to community building plan):**
> **Contributor growth commitment:** A `CONTRIBUTORS.md` file is maintained in the repository listing all technical contributors (RTL authors, cocotb testbench authors, documentation maintainers) — not merely typo-fix PRs. The goal is a documented multi-contributor project within the 18-month grant period (target: 3+ substantive external contributors by Month 12).
>
> **Supporting letters:** For the follow-up proposal, we will attach one academic letter (BME Department of Electron Devices or SZTAKI) and one industry letter (.NET Foundation member, Akka.NET maintainer, or Tiny Tapeout mentor) documenting institutional backing.

---

## Correction 10 — CFPU / CLI-CPU naming consistency (partially addressed in v1.2)

**Status:** The post-submission v1.2 update introduced the CFPU naming retroactively. The README and documentation were updated. If a reviewer opens the GitHub repo today, they see "CFPU" prominently — which differs from the submitted proposal title ("CLI-CPU").

**Recommended README addition (top of file):**
> **Naming:** CLI-CPU is the reference implementation of the **Cognitive Fabric Processing Unit (CFPU)** architecture. The project identifier (CLI-CPU) refers to this specific open-source implementation; CFPU refers to the broader processor category. The two names appear together throughout the documentation.

This makes the relationship explicit for any reviewer following the README link from the proposal.

---

## Section B — Errors present in the actually submitted text

> These are **not suggested improvements** — they are mistakes that made it into the text NLnet received. Discovered during post-submission review of the confirmation PDF. Should be clarified proactively if reviewers touch the affected sections.

### Correction 11 — Title missing "Processing Unit (CFPU)" expansion

**Submitted title:**
> "CLI-CPU: Open Source Cognitive Fabric **Processor** — Native CIL Execution on Libre Silicon"

**Intended (draft v1.2) title:**
> "CLI-CPU: Open Source Cognitive Fabric **Processing Unit (CFPU)** — Native CIL Execution on Libre Silicon"

**Impact:** The CFPU acronym — used prominently throughout the repository — does not appear in the submitted title. A reviewer opening the GitHub link will see "CFPU" terminology that is absent from the submission. Mitigation: reply clarifying that "CFPU" and "Cognitive Fabric Processor" refer to the same concept; the former is the preferred expanded form.

### Correction 12 — Technical typo: "OPI" should be "QSPI"

**Submitted text (challenges §4):**
> "**OPI** memory latency: On-chip SRAM limited (4-16 KB per core). Code and data fetched from **OPI** flash/PSRAM with 6-10 cycle latency."

**Intended (draft):**
> "**QSPI** memory latency: ... from **QSPI** flash/PSRAM with **10-50** cycle latency."

**Impact:** Technical inaccuracy. OPI (Octal Peripheral Interface) is a different protocol. The reference design targets QSPI (Quad SPI) external memory. The cycle latency figure is also wrong (6-10 → 10-50). Mitigation: if the reviewer raises memory architecture, clarify this as a transcription error and cite the correct values.

### Correction 13 — Ecosystem duplicated claim about European foundries

**Submitted text (ecosystem):**
> "European digital sovereignty: fully open, auditable processor manufactured at European foundries (IHP SG13G2, GlobalFoundries Dresden)."

**Issue:** The submitted draft says European foundries "manufacture" the chip — but F3 first silicon targets Sky130 (SkyWater, US). Only F6+ hypothetically moves to IHP SG13G2. This framing is aspirational, not current. Combined with Correction 2 — the sovereignty narrative needs the F3/F6+ distinction to be honest.

### Correction 14 — Hungarian diacritics lost in proper nouns

**Submitted text contains:**
- "Adougyi Ellenorzo Egyseg" — should be "**Adóügyi Ellenőrző Egység**"
- "MAV" — should be "**MÁV**"

**Impact:** Cosmetic, but suggests rushed submission. Likely due to form encoding or copy-paste issue when the submission form was completed. Mitigation: none needed unless reviewer asks about the Hungarian Tax Control Unit context — in which case, spell the proper nouns correctly in the reply.

---

## What to do if NLnet reviewers request clarification

1. **Acknowledge the submitted version is v1.2** (the filed text), and offer this corrections document as a clarification.
2. **Lead with the most material corrections** (#1 TT pricing, #3 M4 scope, #8 sustainability) — these affect budget and deliverables.
3. **Offer PDF attachments proactively** if not already submitted (architecture overview, roadmap, test screenshots, 1-page executive summary).
4. **Mention the parallel Neuron OS proposal** (#6) upfront to avoid the appearance of withholding related funding plans.

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.1 | 2026-04-23 | Added Section B — four actual errors in the submitted text (§11-14) identified by reviewing the NLnet confirmation PDF: title missing CFPU acronym, OPI/QSPI typo + wrong cycle count, European foundries aspirational claim, lost Hungarian diacritics. |
| 1.0 | 2026-04-23 | Initial post-submission corrections document. 10 suggested improvements cataloged based on internal review (Section A). Submitted draft file preserved unchanged. |
