---
status: vision
---

# CFPU vs RISC-V — Single-thread Performance Analysis

> Magyar verzió: [perf-vs-riscv-hu.md](perf-vs-riscv-hu.md)

> Version: 1.2

> **⚠️ Vision-level document.** Numerical estimates are extrapolations from documented sources (picoJava-2 perf paper, Jazelle DBX measurements, Krall & Probst 1998, Azul Vega). **Not an RTL-level measurement, not a silicon measurement.** Precise ratios can only be validated after F1.5 dynamic instruction count baseline + F2.7 FPGA cycle-accurate prototype + F4 multi-core RTL + F6 silicon. The document records **methodology** and brings prior estimates onto a reproducible foundation, not declared final numbers.

## The question

For a given C# program (Roslyn → IL → CFPU CIL-T0 link → CFPU execution), how does the **single-thread wall-clock time** compare to the same program (Roslyn → IL → NativeAOT/Mono LLVM → RV32IM execution) on the same technology node and the same clock?

This is **not the CFPU's main argument** — the main argument is many-core throughput (`microarch-philosophy-en.md`). But **per-core perf is also relevant**, because most legacy C# code does not run as thousands of concurrent actors. The "is the Rich core fast enough as a sensible baseline" question deserves a defensible answer.

## What we compare against — reference is always in-order RV

Per [`microarch-philosophy-en.md`](microarch-philosophy-en.md), every CFPU core is in-order. Fair comparison can therefore be **only against in-order RV** — never against RV-OoO Cortex-A75 or Apple M class, since those represent a category outside the CFPU microarchitecture's design space.

| RV reference | CFPU reference | Reason |
|---|---|---|
| SiFive E31 (RV32IMC, in-order, 1-issue, 5-stage) | F4 Rich (in-order, 1-issue, reg stack, macro-op fusion) | Base baseline |
| SiFive U74 (RV32IMC, in-order, **2-issue**, 8-stage) | F5 Rich (in-order, **2-issue**, reg stack, fusion, static pair-bit) | Optimized |
| Spike emulator (RV32IMC, static IPC=1) | F1.5 reference simulator (static IPC=1) | Dynamic instruction count baseline |

**Forbidden references:** ARM Cortex-A55/A75, Apple M-series P-core, Intel Lakefield E-core, AMD Zen — all OoO/speculative, not relevant to the CFPU.

## Withdrawal of prior extrapolation

Earlier working estimates (analyses prior to fixing the microarchitecture philosophy) assumed an OoO option and used it in the perf model. This was wrong on two counts:

1. **Architectural**: OoO is not an option on the CFPU (see [`microarch-philosophy-en.md`](microarch-philosophy-en.md))
2. **Methodological**: numbers were extrapolation, not measurement — this document itself defines the reproducible measurement basis

The earlier "F5 Rich + OoO 2-issue ≈ RV-OoO 2-issue" argument is **withdrawn**. Realistic estimate:

| Configuration | RV reference | Estimated slowdown | Reason |
|---|---|---|---|
| F1.5 reference sim (3-stage, no cache) | RV32I in-order, no cache | ~3–5× | both are naïve, **not a meaningful measurement** |
| F4 Rich (5-stage in-order, 1-issue, reg stack, macro-op fusion) | RV32IM 5-stage in-order 1-issue (SiFive E31 class) | **~1.3–1.5×** | stack ISA + static pattern recognition |
| F5 Rich (5-stage in-order, 2-issue static pair-bit, reg stack, fusion, static branch hint) | RV32IMC 5-stage in-order 2-issue (SiFive U74 class) | **~1.1–1.3×** | EPIC-style static ILP |

The "matches RV-OoO 2-issue" argument is **deleted**. Realistic measure: in-order RV vs in-order CFPU, where **~1.2× on the hot path** is achievable — the targeted middle value after F5.

## Methodology — how to measure realistically

Claims of "X× slower" are only supportable by **one of the following methods**:

### Method 1: Dynamic instruction count ratio (available in F1.5)

```
RV_dyn_count(P) / CFPU_dyn_count(P) = instruction count ratio
```

On the CFPU side: `CilCpu.Sim.TCpu.Execute()` augmented with a counter, +1 per executed opcode.
On the RV side: Spike emulator with `--instructions=count` flag.

This is **not a perf ratio**, only an instruction-count ratio. It becomes a perf ratio when a CPI model is added:

```
Perf_ratio = (CFPU_dyn / RV_dyn) × (CFPU_CPI / RV_CPI)
```

CPI in the F1.5 phase is analytically modelable (5-stage in-order pipeline, static hazard list).

### Method 2: Cycle-accurate FPGA prototype (available in F2.7)

On A7-Lite 200T the Rich core RTL prototype runs benchmark code cycle-accurately. The RV reference runs on the same FPGA via VexRiscv or SERV.

Result: **actual measured wall-clock**, same clock, same FPGA.

### Method 3: Silicon measurement (available in F6)

The Cognitive Fabric One MPW (15 mm², 6R+16N+1S) is the final ground truth. A reference RV chip on the same node (e.g. SiFive U74 PMP).

> **Important caveat:** the Cognitive Fabric One MPW is **130nm** (Sky130). This is a "works in silicon" proof — **not** a realistic perf or energy baseline for the product vision (5nm): the 130nm clock ceiling is ~50–100 MHz and energy/op is orders of magnitude worse. The RV ratio measured at 130nm is **functionally** valid but does not settle the *dense-node* perf/energy question.

### Method 3.5: 22FDX silicon measurement (available in F6.7, optional)

The roadmap [F6.7 "Cognitive Fabric Dense"](roadmap-en.md#f67--cognitive-fabric-dense-node-shrink-gf-22fdx-dresden--optional-de-risk-step) optional de-risk step tapes out the design verified in F6-Si One on the GlobalFoundries **22FDX** (22nm FD-SOI, Dresden) process. This is the **first real, non-literature** perf/energy data point on a *dense* node — within the ~10× density gap between 130nm (Method 3) and the 5nm product vision.

| | Method 3 (130nm) | **Method 3.5 (22FDX)** | Product vision (5nm) |
|---|---|---|---|
| Clock | ~50–100 MHz | **>500 MHz (measured)** | extrapolation |
| Energy/op | poor (130nm) | **first real measured point** | extrapolation |
| RV ratio | functionally valid | **valid on a dense node** | extrapolation |

On 22FDX the reference comparison uses an RV core synthesized to the same node (VexRiscv/SERV ASIC flow), not FPGA emulation. This point also calibrates the `chiplet-packaging` scaling table (see the "22FDX Calibration Point" section there). **Optional** — only if F6.7 starts (funding or critical dense-node measurement).

## Reproducible baseline — what to do now (F1.5)

We propose this as **the next implementation step** in the `CilCpu.Sim` project:

1. **Instruction counter** in `TCpu`
   - +1 per `TExecutor` `Step()` invocation
   - Per-opcode breakdown (separate counter per opcode, 48 total)
   - Method header read, branch taken/not-taken breakdown
   - TDD: new `TCpuInstructionCountTests`, baseline values for each `samples/PureMath` benchmark

2. **Spike RV reference run**
   - Compile `samples/PureMath` project with NativeAOT to RV32IMC (`-r linux-riscv32` if available, or LLVM cross-compile)
   - Run on Spike with `--isa=RV32IMC --log-commits`
   - Extract instruction count

3. **Documented ratio table**
   - `docs/perf-baseline/{benchmark}.md` per case
   - With reproducible script (`scripts/perf-baseline.sh`)
   - Versioned — must be re-run at each roadmap phase

4. **CPI model integrated**
   - Simple analytical model: 5-stage in-order, hazard-stall rules
   - Until F2.7 model only, after F2.7 RTL replaces it

## What we gain from the baseline

- **Concrete, citable number** for each roadmap update
- **NLnet and blog post numbers** based on actual measurement
- **Regression detection** — if a new opcode implementation worsens the count, it shows
- **Linker optimization measurable** — before/after macro-op fusion on the same benchmark

## What we do not gain

Dynamic instruction count **does not say everything**:

- Cache miss rate, branch misprediction rate — these are RTL-level
- Memory bandwidth demand — also RTL/silicon measurements
- Power per benchmark — silicon measurement
- Multi-core scaling — measured in F4

The baseline **is therefore a single point** in the full validation chain, not a substitute for the other phases.

## In context — why per-core slowdown is not the main problem

As `microarch-philosophy-en.md` records: the CFPU's argument is not single-thread speed. The 4,300-thread iMac example shows that on conventional CPUs per-core performance is already absorbed by context switch overhead. A 1.2× single-thread slowdown on a CFPU core is **dwarfed** by the 7–15× aggregate throughput gain on multi-task workloads.

This perspective must be **explicitly maintained in every comparative communication** — per-core measurement matters not so we can compete with RV, but so the Rich core is not embarrassingly slow on the baseline and on legacy C# code.

## Security-adjusted comparison

The slowdown estimates above (F4 ~1.3–1.5×, F5 ~1.1–1.3×) measure **unguarded code against unguarded code**: the RV reference does not enforce CIL-T0's runtime safety guarantees. As soon as the workload requires the **same security guarantee**, the comparison shifts — because on the RV side that guarantee has to be *paid for out of something*.

**The principle: the CFPU trades silicon area for time.** It moves the security check out of the recurring, per-opcode *instruction cost* into parallel hardware — the HW core performs bounds/stack/trap checks alongside the datapath at ~0 marginal cycles, whereas a stock RV must inject guard instructions. This is the same time→silicon conversion as the [`microarch-philosophy-en.md`](microarch-philosophy-en.md) TLP>ILP thesis, on the security axis.

Three cases must be separated — the naïve "the CFPU is faster when security matters" would be an overclaim:

| Security property | Stock RV32 cost | CFPU cost | Verdict at equal guarantee |
|---|---|---|---|
| **Semantic safety** (bounds check on `ldind`/`stind`, stack-depth trap, `div`-by-zero + `INT_MIN/−1`) | software guard: +1–3 instructions per guarded op (RV `div` **does not trap** — divide-by-zero returns a defined value; bounds/stack likewise need software or a guard page) | HW parallel, ~0 marginal cycles | **CFPU faster** — the HW supplies the guarantee for free in time |
| **Coarse region isolation** (R/W/X at region granularity) | **PMP** (Physical Memory Protection): HW, ~0 cycles | HW, ~0 cycles | **tie** — the CFPU's edge here is finer granularity, NOT speed |
| **HW-rooted capability + code attestation** | software check = **bypassable** → weaker guarantee | HW-enforced, load-time verify, zero runtime overhead (see [`authcode-en.md`](authcode-en.md)) | **different league** — software cannot reach the level |

**Effect on the tables above.** The ~1.3–1.5× slowdown assumes *unguarded* execution. On safety-heavy code (heavy memory indexing, division, deep call chains) the RV reference must pay guard overhead, which **narrows the gap and can even reverse it on a safety-dominated hot path**. This does not mean the CFPU is "faster" — its own per-core overhead remains — but that **the raw-speed tables underrate the CFPU on every workload where security is not optional.**

Two caveats, so this is not an overclaim:

- **Not free, only free in time.** The "~0 cycles" holds for *throughput*; the comparators + trap FSM + Seal logic consume **area and energy**. The HW converts a recurring time cost into a one-time area cost.
- **Not everywhere.** For coarse isolation, PMP ties; for security-free general compute, the raw-speed tables (above) govern. The security-adjusted edge appears **only on security-critical + fine-grained + attested** execution.

**Measurement.** Like every number in this document, the +1–3 guard instructions/op is a **literature estimate, not an RTL measurement**. Validation: in Method 1, compile the Spike reference with guards emulating CIL-T0's trap semantics (not raw RV32) and record the dynamic-instruction-count ratio that way too — this yields the "security-adjusted" column in the baseline table.

## Related documents

- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — TLP > ILP, why single-thread perf is not the main argument
- [`internal-bus-en.md`](internal-bus-en.md) — port bottleneck is part of the CPI model
- [`core-types-en.md`](core-types-en.md) — Rich core spec
- [`ISA-CIL-T0-en.md`](ISA-CIL-T0-en.md) — instruction set, basis of the count
- [`roadmap-en.md`](roadmap-en.md) — F2.7 / F4 / F6 phases where validation happens
- [`authcode-en.md`](authcode-en.md) — HW-rooted code attestation, zero runtime overhead (case 3 of the security-adjusted comparison)

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.2 | 2026-07-06 | **Security-adjusted comparison** section added — the raw-speed tables measure unguarded code; at equal security guarantee the CFPU trades area for time (bounds/stack/trap in HW at ~0 cycles vs. software guards on RV). 3 cases: semantic safety → CFPU faster; coarse isolation → PMP tie; HW attestation → software cannot reach it. Cascade: cross-reference to `authcode` (reciprocal back-ref in `authcode` v1.1). |
| 1.1 | 2026-05-17 | **Method 3.5: 22FDX silicon measurement** added — the roadmap F6.7 optional de-risk step provides the first real (non-literature) dense-node perf/energy point in the ~10× gap between 130nm (Method 3) and the 5nm product vision. 130nm-caveat warning added to Method 3. Cascade: `roadmap` v1.8, `chiplet-packaging` v1.1. |
| 1.0 | 2026-04-25 | Initial version — methodology (dynamic instruction count, FPGA, silicon), in-order vs in-order comparison, OoO assumption withdrawn, F1.5 baseline measurement plan |
