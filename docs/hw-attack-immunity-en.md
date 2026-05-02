# CFPU — HW Attack Immunity Reference

> Magyar verzió: [hw-attack-immunity-hu.md](hw-attack-immunity-hu.md)

> Version: 1.0

This is a **compact reference table** of CFPU hardware attack immunity: attack class → mitigating mechanism → source document. Full threat model, formal verification, and certification pathways: [`security-en.md`](security-en.md).

> The table covers **HW-level mitigation only**. Software bugs, social engineering, physical destruction (FIB, probing, fault injection) are **out of scope** for this document.

## The four pillars of mitigation

CFPU attack immunity rests on **four architectural decisions** — every tabulated mitigation traces back to these:

| Pillar | Mechanism | What it eliminates |
|--------|-----------|--------------------|
| **1. In-order, no OoO, no speculation** | Deterministic pipeline, static branch hints | Spectre family, transient execution |
| **2. Shared-nothing fabric** | Per-core SRAM, mailbox NoC, no cache coherence | Cache side-channel, cross-core leak |
| **3. HW-managed capability (CST + Quench-RAM SEAL)** | Capability Slot Table in QSRAM, SEAL/RELEASE HW FSM | Memory safety, capability forge, DMA bypass |
| **4. Trust by construction (AuthCode + LMS/WOTS+)** | Hash-based PQC signature at code load, runtime W⊕X | Code injection, supply chain, JIT spray |

## Per-message authenticity — the HMAC-free design

> **Important**: CFPU **does NOT use HMAC** at message level. Header v3.0 (interconnect-en.md) explicitly removed it.

Sender-actor identity is established without HMAC:

| Component | Mechanism | Source of unforgeability |
|-----------|-----------|-------------------------|
| **`src_actor[8]`** in header | Core HW writes it directly from the **active actor context register** | Software cannot access the HW context register |
| **`src[24]`** (source core ID) | NoC router physically arrives from source port | Routing-level locality |
| **CST index → address resolution** | CST (Capability Slot Table) lives in QSRAM, **under Quench-RAM SEAL** | Software cannot write QSRAM, only the Seal Core SEAL/RELEASE FSM can |
| **Capability `perms`** | Does NOT travel in header — checked by HW at send time against CST | Stateless sender check, locally |
| **CRC-16** (payload) + **CRC-8** (header) | Integrity, NOT authentication | Bit-flip detection on the NoC |

**Trust by construction** — the CIL binary is **once** subject to LMS-signature verification (AuthCode at code load), and from there every capability is hardware-bound. No per-message HMAC is needed because:

1. Sender actor identity is **HW-written** (cannot be spoofed)
2. Capability content lives **under QSRAM SEAL** (cannot be manipulated)
3. Running code is **AuthCode-verified** and runs under **CodeLock W⊕X** (cannot be injected)

## Attack immunity reference

### Transient execution / speculation attacks

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Spectre v1/v2/v4 | CWE-1037 | No speculation | [`microarch-philosophy-en.md`](microarch-philosophy-en.md) |
| Meltdown | CWE-1037 | No OoO + no speculation | [`microarch-philosophy-en.md`](microarch-philosophy-en.md) |
| Foreshadow / L1TF | CWE-1037 | Per-core SRAM scratchpad, no L1 cache | [`core-types-en.md`](core-types-en.md) |
| MDS (RIDL/Fallout/ZombieLoad) | CWE-1037 | No SMT, no internal buffer sharing | [`microarch-philosophy-en.md`](microarch-philosophy-en.md) |
| Retbleed / BHI | CWE-1037 | No branch predictor (static hints) | [`microarch-philosophy-en.md`](microarch-philosophy-en.md) |
| Inception / SQUIP | CWE-1037 | No SMT, no scheduler resource sharing | [`core-types-en.md`](core-types-en.md) |

### Cache side-channel

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Flush+Reload | CWE-208 | No shared cache | [`core-types-en.md`](core-types-en.md) |
| Prime+Probe | CWE-208 | No cache eviction policy (scratchpad) | [`core-types-en.md`](core-types-en.md) |
| Evict+Reload | CWE-208 | Per-core SRAM, deterministic latency | [`core-types-en.md`](core-types-en.md) |
| MESI protocol leak | — | Shared-nothing, no coherence protocol | [`interconnect-en.md`](interconnect-en.md) |
| CacheBleed | CWE-208 | No cache port serialization | [`core-types-en.md`](core-types-en.md) |
| Cross-core MDS | CWE-1037 | Shared-nothing fabric | [`interconnect-en.md`](interconnect-en.md) |

### Memory safety

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Buffer overflow | CWE-119/120 | HW bounds check on every memory opcode | [`security-en.md`](security-en.md) |
| Use-after-free | CWE-416 | Per-actor heap + capability lifecycle (SEAL/RELEASE) | [`quench-ram-en.md`](quench-ram-en.md) |
| Double-free | CWE-415 | Quench-RAM RELEASE atomic, status-bit | [`quench-ram-en.md`](quench-ram-en.md) |
| Type confusion | CWE-843 | CIL type system, ILC verification AOT | [`security-en.md`](security-en.md) |
| Pointer leak | CWE-200 | Capability index (32-bit), raw addresses can't leak | [`interconnect-en.md`](interconnect-en.md) §Capability v3.0 |
| Privilege escalation | CWE-269 | No "kernel mode" — capability cannot be elevated | [`sealcore-en.md`](sealcore-en.md) |
| Stack smashing | CWE-121 | HW stack bounds + frame pointer physically separated | [`security-en.md`](security-en.md) |
| Information leak in freed memory | CWE-244, CWE-226 | Quench-RAM RELEASE = atomic wipe | [`quench-ram-en.md`](quench-ram-en.md) |
| Uninitialized memory read | CWE-457 | Quench-RAM + ECMA-335 zero-init | [`quench-ram-en.md`](quench-ram-en.md) |

### Cross-actor / fabric attacks

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Inter-process info leak | CWE-200 | Shared-nothing — physically no shared memory | [`interconnect-en.md`](interconnect-en.md) |
| DMA bypass | CWE-1233 | DDR5 HW Capability Slot in QRAM + `flags.DDR5_CAP` HW-only bit | [`ddr5-architecture-en.md`](ddr5-architecture-en.md) |
| Confused deputy | CWE-441 | `src_actor` from HW context register, cannot be spoofed | [`interconnect-en.md`](interconnect-en.md) |
| Actor spoofing | — | `src_actor[8]` field written by core HW (not software) | [`interconnect-en.md`](interconnect-en.md) v3.0 |
| Capability forging | — | CST in QSRAM, under Quench-RAM SEAL — software cannot write | [`quench-ram-en.md`](quench-ram-en.md) v1.4 |
| Capability tag forging | — | Sealed region, physically unforgeable | [`quench-ram-en.md`](quench-ram-en.md) |
| Mailbox replay attack | — | `seq[16]` fragment counter + AuthCode-derived code integrity | [`interconnect-en.md`](interconnect-en.md) |

### Code integrity / supply chain

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Unsigned code execution | CWE-345 | AuthCode HW verify on every code load | [`authcode-en.md`](authcode-en.md) |
| Tampered binary execution | CWE-345 | LMS+WOTS+ signature, SHA-256(bytecode) ↔ cert.PkHash | [`authcode-en.md`](authcode-en.md) |
| Stateful signature key reuse | — | Symphact HSM Card single-use NVRAM | [`authcode-en.md`](authcode-en.md) |
| Quantum break of signature | — | LMS+WOTS+ hash-based PQC (FIPS 205, NIST SP 800-208) | [`authcode-en.md`](authcode-en.md) |
| Hot code loader tamper | — | Seal Core firmware mask ROM / eFuse immutable | [`sealcore-en.md`](sealcore-en.md) |
| Memory controller write-path bypass | — | Pre-QRAM WE-routing / QRAM SEAL HW-trigger | [`sealcore-en.md`](sealcore-en.md) |
| Shellcode injection | CWE-94 | CODE R/O in hardware, Quench-RAM SEAL | [`quench-ram-en.md`](quench-ram-en.md) |
| JIT spraying | — | **No JIT** — native CIL execution | [`microarch-philosophy-en.md`](microarch-philosophy-en.md) |
| Self-modifying code | CWE-94 | Quench-RAM SEAL — sealed region not writable | [`quench-ram-en.md`](quench-ram-en.md) |
| Supply chain at HW level | — | Open HDL (CERN-OHL-S), reproducible build | [`security-en.md`](security-en.md) |
| Supply chain at code level | — | AuthCode trust chain: eFuse → CA → vendor → card → binary | [`authcode-en.md`](authcode-en.md) |

### Control flow integrity

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| ROP (Return-Oriented Programming) | CWE-121 | CFI in the ISA, return target HW-verified | [`security-en.md`](security-en.md) |
| JOP (Jump-Oriented Programming) | — | Branch target verification (only intra-method jumps) | [`security-en.md`](security-en.md) |
| Format string | CWE-134 | No printf, no C strings | [`security-en.md`](security-en.md) |
| Stack overflow (unbounded recursion) | CWE-674 | HW stack bounds trap | [`security-en.md`](security-en.md) |

### Concurrency

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Race condition in GC | CWE-362 | Per-core private heap, no global GC | [`core-types-en.md`](core-types-en.md) |
| Deadlock (lock contention) | CWE-833 | No shared locks, only mailbox | [`interconnect-en.md`](interconnect-en.md) |
| False sharing covert channel | — | No shared cache | [`interconnect-en.md`](interconnect-en.md) |
| TOCTOU (Time-Of-Check Time-Of-Use) | CWE-367 | Capability check atomic in sender HW | [`interconnect-en.md`](interconnect-en.md) |

### Cold boot / physical-adjacent

| Attack | CWE | CFPU mechanism | Source |
|--------|-----|---------------|--------|
| Cold boot key recovery | — | Quench-RAM: sealed key only released via wipe | [`quench-ram-en.md`](quench-ram-en.md) |
| Rowhammer (cross-row) | CWE-1247 | Per-core SRAM (not DRAM), DDR5 capability-bound | [`ddr5-architecture-en.md`](ddr5-architecture-en.md) |

## What is NOT mitigated in HW — honest scope

CFPU is a strong architecture, but **not omnipotent**. The following require **complementary mechanisms**:

| Attack | Why HW does not mitigate | What is needed alongside |
|--------|--------------------------|--------------------------|
| Power analysis (DPA/SPA) | Constant-time ALU is not default | Constant-time + masking in software, especially in Seal Core crypto |
| EM analysis | Physical leakage | Shielding, masked logic — Seal Core-level option |
| Fault injection (clock/volt glitch, laser) | Fault detection FSM is not default | Clock monitor, voltage monitor, redundancy — justified in Seal Core |
| Physical probing / FIB | Decapped chip is visible | Anti-tamper mesh, active shield — in Seal Core |
| Software bug in user code | HW cannot fix logic errors | "Secure by design" SDLC, code review |
| Social engineering / key compromise | Outside HW scope | Process controls, HSM policy |
| Denial of Service (mailbox spray) | Rate limiting not in HW | Symphact runtime responsibility |
| Business logic flaw (permission check) | If C# code calls capability incorrectly | Design responsibility |

## The four pillars summarized — for an auditor's one-liner

If an auditor or partner asks for a single sentence:

> **CFPU's four architectural decisions** (in-order pipeline, shared-nothing fabric, HW-managed capability under QRAM SEAL, trust-by-construction with LMS-signed code load) **physically eliminate the vast majority of published CWE classes** — not as software mitigation, but as a structural property that **cannot be patched in the wrong direction** and **cannot be turned off for performance**.

## Positioning message

| Layer | Traditional CPU | CFPU |
|-------|-----------------|------|
| **Mitigation level** | Software patch, firmware microcode | **HW design choice** |
| **Auditability** | List of patches, each with exploit-CVE | TLA+/SVA assertions, formally verifiable |
| **Bypass possibility** | "Fast mode" or disable flag (e.g., SMT-off for Spectre) | **None** — structural |
| **For new attack classes** | New patch, new performance loss | **Architectural immunity** |
| **Marketing** | "Secure with patches" | **"Secure by construction"** |

## Related documents

- [`security-en.md`](security-en.md) — comprehensive threat model, formal verification, certification pathways, market segments
- [`microarch-philosophy-en.md`](microarch-philosophy-en.md) — in-order, no OoO, TLP > ILP philosophy
- [`interconnect-en.md`](interconnect-en.md) — Header v3.0, CST, capability model
- [`quench-ram-en.md`](quench-ram-en.md) — Quench-RAM SEAL/RELEASE, atomic wipe
- [`authcode-en.md`](authcode-en.md) — AuthCode + CodeLock + LMS/WOTS+ trust chain
- [`sealcore-en.md`](sealcore-en.md) — Seal Core as trust anchor
- [`ddr5-architecture-en.md`](ddr5-architecture-en.md) — capability slot, HW request assembler

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-05-02 | Initial version. Compact mitigation table. Four pillars + per-message authenticity (HMAC-free, src_actor from HW context register + CST under QSRAM SEAL) + LMS/WOTS+ code signing. Scope: HW-level mitigation only; formal verification and certification: [`security-en.md`](security-en.md). |
