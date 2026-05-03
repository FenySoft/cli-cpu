---
status: draft
---

# CFPU-SEC-v1 -- Mandatory Security Elements Specification

> Version: 1.0 | Date: 2026-04-17

> Magyar verzió: [CFPU-SEC-v1-hu.md](CFPU-SEC-v1-hu.md)

This document forms the technical basis for the **CFPU Certified** certification mark. It defines the **mandatory security elements** whose compliance is verified and certified by the CFPU Foundation. The document also contains a draft of the **Regulations of Use** required for the EUIPO certification mark application.

## Table of Contents

1. [Purpose and Scope](#purpose)
2. [Referenced Documents](#references)
3. [Mandatory Security Elements (S1-S12)](#elements)
4. [Certification Levels](#levels)
5. [Conformance Test Outline](#tests)
6. [Certificate Format and Registry](#certificate)
7. [Regulations of Use (EUIPO Certification Mark)](#regulations)
8. [Lifecycle and Versioning](#lifecycle)
9. [Changelog](#changelog)

## Purpose and Scope <a name="purpose"></a>

### What the CFPU Certified Mark Certifies

The **CFPU Certified** certification mark (EU certification mark, Nice classes: 9 + 42) certifies that a CFPU-architecture chip or module **complies** with the mandatory security elements described in this specification. The mark does **not** identify the manufacturer, but **certifies a technical property** of the product.

### Who It Applies To

- Any legal or natural person who manufactures, distributes a CFPU-architecture chip, or licenses CFPU-compatible IP blocks
- Certification is **non-discriminatory** -- available to anyone who passes the conformance test and pays the registration fee

### What It Does NOT Apply To

- Software compatibility (CIL toolchain, Symphact applications) -- this is a separate certification program
- Physical tamper-resistance (decapsulation, FIB attacks) -- this falls outside the threat model
- Performance or energy efficiency -- CFPU-SEC exclusively examines security properties

## Referenced Documents <a name="references"></a>

| Document | Location | Relevance |
|----------|----------|-----------|
| Seal Core Architecture | [`docs/sealcore-en.md`](../sealcore-en.md) | S1, S2, S3 elements: the authentication gatekeeper core |
| AuthCode + CodeLock | [`docs/authcode-en.md`](../authcode-en.md) | S3, S4, S11, S12 elements: code signing and W-xor-X mechanism |
| Quench-RAM Memory Cell | [`docs/quench-ram-en.md`](../quench-ram-en.md) | S5, S6, S7 elements: per-block status bit and atomic wipe |
| Security Model | [`docs/security-en.md`](../security-en.md) | S8, S9, S10 elements: isolation, CFI, stack protection |
| ISA Specification | [`docs/ISA-CIL-T0-en.md`](../ISA-CIL-T0-en.md) | S9, S10 elements: opcode-level bounds check |
| Architecture | [`docs/architecture-en.md`](../architecture-en.md) | S4, S8 elements: Harvard architecture, shared-nothing |

## Mandatory Security Elements (S1--S12) <a name="elements"></a>

Each element is a **verifiable property**: a hardware guarantee whose compliance can be checked with automated tests. The elements are **not implementation details** -- they do not prescribe gate counts, pipeline depths, or chip technology. They only specify the **observable behavior**.

---

### S1 -- Seal Core Presence and Activity

> **Source:** [`sealcore-en.md`](../sealcore-en.md) SS what-is-sealcore

**Requirement:** The chip contains at least one (1) Seal Core that is active after boot and provides a heartbeat signal.

**Verification:**
- After boot sequence, the health monitor `alive[i]` flag is active for at least one Seal Core
- The Seal Core responds to self-test queries (firmware hash report)

**Rationale:** The Seal Core is the trust anchor in the CFPU security model -- without it, there is no AuthCode verify, no SEAL trigger source, and code loading authenticity cannot be guaranteed.

---

### S2 -- Seal Core Firmware Immutability

> **Source:** [`sealcore-en.md`](../sealcore-en.md) SS boot

**Requirement:** The Seal Core firmware is **not modifiable** during the chip's lifetime. Firmware storage method: mask ROM, OTP eFuse, or flash + eFuse-integrity-check. The firmware hash is fixed in the eFuse.

**Verification:**
- `SHA-256(firmware_readback) == eFuse.SealCoreFirmwareHash`
- Write attempts to firmware storage result in a trap or no-op

**Rationale:** If the Seal Core firmware could be tampered with, the entire trust chain collapses (the authenticator itself becomes untrustworthy).

---

### S3 -- AuthCode Verify Gate

> **Source:** [`authcode-en.md`](../authcode-en.md) SS authcode, [`sealcore-en.md`](../sealcore-en.md) SS qram

**Requirement:** All CIL bytecode entering the chip's CODE region must **mandatorily** pass AuthCode verification. The AuthCode verify flow contains three steps:
1. `SHA-256(bytecode) == cert.PkHash`
2. `BitIceCertificateV1.Verify(cert, eFuse.CaRootHash)`
3. `cert.SubjectId notIn revocation_list`

If any step fails, the bytecode is **not loaded** and a trap is generated.

**Verification:**
- Loading an unsigned `.acode` container -> `INVALID_SIGNATURE` trap, CODE region unchanged
- Tampered bytecode (1 bit flip) -> `CODE_HASH_MISMATCH` trap
- Valid `.acode` -> successful loading, actor can be started

**Rationale:** AuthCode implements the "single gate" principle -- only signed, verified code can run on the chip.

---

### S4 -- CodeLock W-xor-X Hardware Separation

> **Source:** [`authcode-en.md`](../authcode-en.md) SS codelock

**Requirement:** The chip hardware **physically** enforces W-xor-X (Write XOR Execute) separation:
- Write-to-CODE trap: any core attempting to write to the CODE region -> `WRITE_TO_CODE_DENIED`
- Execute-from-DATA trap: the PC (program counter) points to a DATA/STACK address -> `EXECUTE_FROM_DATA`
- PC range check: every instruction fetch verifies that the PC is in a valid CODE region

**Verification:**
- Memory write to a CODE region address -> `WRITE_TO_CODE_DENIED` trap
- Setting PC to a DATA region address (branch/call) -> `EXECUTE_FROM_DATA` trap
- ROP/JOP gadget step: "return address" written to stack points to DATA -> trap

**Rationale:** CodeLock ensures that loaded code remains bit-identical (integrity), and data is never interpreted as code (shellcode injection prevention).

---

### S5 -- Quench-RAM SEAL/RELEASE State Machine Invariant

> **Source:** [`quench-ram-en.md`](../quench-ram-en.md) SS state-machine

**Requirement:** Every Quench-RAM block has **a status bit** (0 = mutable, 1 = sealed/immutable). The following invariant holds **after every cycle**:

> `status = 0` implies `data = 0...0` (every allocatable block is zero-initialized)

This means two transition operations:
- `SEAL`: 0 -> 1 (data unchanged, block becomes immutable)
- `RELEASE`: 1 -> 0 **and** `data <- 0^N` (atomic, 1 cycle)

No other state transition **exists**.

**Verification:**
- After RELEASE, every bit of the block is 0 (readback verify)
- Write attempt to a sealed block -> trap or no-op
- Freshly allocated block (status=0) content is 0 (zero-init guarantee)

**Rationale:** The Quench-RAM invariant physically prevents use-after-free, information leak, and cold boot key recovery attacks.

---

### S6 -- Quench-RAM Atomic Wipe

> **Source:** [`quench-ram-en.md`](../quench-ram-en.md) SS isa-primitives

**Requirement:** The `RELEASE` operation executes the status bit reset (1 -> 0) and zeroing of all data bits **in a single clock cycle**. The two events are **atomic** -- there is no intermediate state where the block is "released-but-dirty".

**Verification:**
- Timing measurement: RELEASE -> in the next cycle the block has status=0 and data=0
- No intermediate state can be read (broadcast-clear acts simultaneously across the full width of the SRAM row)

**Rationale:** A non-atomic wipe would open a window for timing-based attacks (data could be read between release and erase).

---

### S7 -- Trust Boundary: SEAL/RELEASE Not Callable from CIL

> **Source:** [`quench-ram-en.md`](../quench-ram-en.md) SS trust-boundary

**Requirement:** `SEAL` and `RELEASE` are **hardware state machine operations (HW FSM)** that can **only** be invoked by well-defined trigger events:

| Primitive | Allowed Triggers |
|-----------|-----------------|
| `SEAL` | CODE region (Seal Core boot / `hot_code_loader`), `SEND` (payload leaves the Core), Swap-out (DMA evict to external QRAM) |
| `RELEASE` | `GC_SWEEP` (only on the calling actor's own heap), `hot_code_loader` unload, Swap-in (reload from external QRAM) |

From the CIL application level, **there is no way** to access either SEAL or RELEASE.

**Verification:**
- SEAL/RELEASE activates exclusively on HW FSM trigger events, not accessible from CIL
- An actor's `GC_SWEEP` acts **only** on its own heap, does not affect other actors' blocks

**Rationale:** If a malicious actor could arbitrarily SEAL or RELEASE blocks, the Quench-RAM security guarantees would be invalidated.

---

### S8 -- Per-Actor Heap Isolation (Shared-Nothing)

> **Source:** [`security-en.md`](../security-en.md) SS 4, [`architecture-en.md`](../architecture-en.md)

**Requirement:** Every actor operates on its **own, private SRAM heap**. The memory regions of two different actors have **no** physical overlap. Cross-core memory writes are **physically impossible** (bus routing does not allow it).

**Verification:**
- Actor A attempts to write to Actor B's heap address -> `INVALID_MEMORY_ACCESS` trap
- Actor A attempts to read from Actor B's heap address -> `INVALID_MEMORY_ACCESS` trap
- Mailbox SEND/RECEIVE is the only cross-actor communication path

**Rationale:** Shared-nothing isolation is the foundation for physically preventing cross-core side-channel attacks (Foreshadow, L1TF, false sharing).

---

### S9 -- Control Flow Integrity (CFI)

> **Source:** [`security-en.md`](../security-en.md) SS 3

**Requirement:** The chip **hardware** enforces control flow integrity:

| Check | Requirement |
|-------|-------------|
| Call target | Every `call`/`callvirt` target is a **method entry point according to CIL metadata** |
| Return target | `ret` takes the return address from the **hardware frame pointer**, not from the user stack |
| Branch target | Every `br*` target is **within the current method's code region** |

**Verification:**
- `call` pointing to an arbitrary address -> `INVALID_CALL_TARGET` trap
- Return address falsified via stack manipulation -> `INVALID_BRANCH_TARGET` trap
- Branch beyond method boundary -> `INVALID_BRANCH_TARGET` trap

**Rationale:** CFI physically prevents ROP and JOP attacks -- this alone covers approximately 30-40% of published kernel exploits.

---

### S10 -- Stack Bounds Check

> **Source:** [`security-en.md`](../security-en.md) SS 1, [`ISA-CIL-T0-en.md`](../ISA-CIL-T0-en.md)

**Requirement:** Every stack operation (push, pop, ldloc, stloc, ldarg, starg) is **hardware-checked**:
- Stack overflow -> `STACK_OVERFLOW` trap
- Stack underflow -> `STACK_UNDERFLOW` trap
- Local variable index >= local count -> `INVALID_LOCAL` trap
- Argument index >= arg count -> `INVALID_ARG` trap

**Verification:**
- Recursive calls exceeding the stack size -> `STACK_OVERFLOW` trap (no unbounded stack growth)
- Pop from empty stack -> `STACK_UNDERFLOW` trap
- `ldloc 99` when only 3 locals exist -> `INVALID_LOCAL` trap

**Rationale:** Stack bounds checking is the hardware prevention of buffer overflow and stack smashing attacks.

---

### S11 -- eFuse CA Root Hash Presence

> **Source:** [`authcode-en.md`](../authcode-en.md) SS trustchain

**Requirement:** A **32-byte CA Root Hash** is fixed in the chip's eFuse, which is the root of the BitIce trust chain. The eFuse contents:
- Writable at manufacturing or first boot (OTP -- one-time programmable)
- **Never modifiable** after writing
- Readable by the Seal Core firmware at boot

**Verification:**
- eFuse readback: not all-zeros (programmed)
- The eFuse content matches the Foundation CA Root public hash
- Write attempts to the eFuse -> no-op or trap (OTP nature)

**Rationale:** The eFuse CA Root Hash is the physical root of the trust chain. Without it, AuthCode verify has nothing to compare against -- any cert could become acceptable.

---

### S12 -- Revocation List Support

> **Source:** [`authcode-en.md`](../authcode-en.md) SS revocation, [`sealcore-en.md`](../sealcore-en.md)

**Requirement:** The Seal Core firmware is capable of storing a **revocation list** and using it during cert verification. Loading an `.acode` container signed with a revoked `SubjectId` -> `CERT_REVOKED` trap.

**Verification:**
- After revocation list update, loading an `.acode` signed with the affected SubjectId -> `CERT_REVOKED` trap
- Non-revoked cert -> still loads successfully
- Revocation list storage capacity: at least 64 revoked entries (v1.0 minimum)

**Rationale:** In a system without revocation, a compromised developer card issues certs that are **forever** valid. The revocation list ensures the Foundation can revoke compromised certs.

---

## Certification Levels <a name="levels"></a>

CFPU-SEC-v1 defines **three levels** that align with the chip's maturity and intended use context:

### CFPU-SEC-v1-Basic

**Phase:** F3--F5 (pre-QRAM era, external CODE RAM)

**Mandatory elements:**

| Element | Requirement | Mechanism |
|---------|-------------|-----------|
| S1 | Seal Core presence | at least 1 active |
| S2 | Firmware immutability | mask ROM / eFuse |
| S3 | AuthCode verify gate | all code-load through Seal Core |
| S4 | CodeLock W-xor-X | physical WE-pin routing (pre-QRAM) |
| S8 | Shared-nothing isolation | per-core SRAM, no shared bus |
| S9 | CFI | call/ret/branch target verify |
| S10 | Stack bounds check | overflow/underflow trap |

**Not mandatory (not relevant in pre-QRAM era):** S5, S6, S7 (Quench-RAM), S11, S12 (eFuse + revocation)

**Rationale:** In the pre-QRAM era, CODE protection is based on physical WE-pin routing, not Quench-RAM status bits. The Basic level applies to early silicon (Tiny Tapeout, FPGA) where Quench-RAM is not yet available.

---

### CFPU-SEC-v1-Full

**Phase:** F5+ (QRAM era, on-chip Quench-RAM)

**Mandatory elements:** **All S1--S12.**

| Element | Requirement |
|---------|-------------|
| S1 | Seal Core presence (at least 1) |
| S2 | Firmware immutability |
| S3 | AuthCode verify gate |
| S4 | CodeLock W-xor-X (Quench-RAM status-bit based) |
| S5 | Quench-RAM SEAL/RELEASE invariant |
| S6 | Quench-RAM atomic wipe |
| S7 | Trust boundary (SEAL/RELEASE not callable from CIL) |
| S8 | Shared-nothing isolation |
| S9 | CFI |
| S10 | Stack bounds check |
| S11 | eFuse CA Root Hash |
| S12 | Revocation list support |

**Rationale:** In the F5+ era, Quench-RAM is available and the complete security model (AuthCode + CodeLock + Quench-RAM + Seal Core) works together. This is the target level for industrial applications.

---

### CFPU-SEC-v1-Redundant

**Phase:** F6+ (production silicon)

**Mandatory elements:** **All S1--S12**, plus:

| Element | Requirement |
|---------|-------------|
| S1+ | At least **2** active Seal Cores |
| S1++ | Health monitor heartbeat (HW FSM, not software-controlled) |
| S1+++ | Graceful degradation: the system continues operating if 1 Seal Core fails |

**Rationale:** The Redundant level is intended for safety-critical applications (IEC 61508 SIL-3+, ISO 26262 ASIL-B+) where a single HW failure must not cause complete system shutdown.

---

### Certification Levels Summary Table

| Level | Phase | Mandatory Elements | Seal Core Min. | Quench-RAM | Revocation |
|-------|-------|--------------------|----------------|------------|------------|
| **Basic** | F3--F5 | S1-S4, S8-S10 | 1 | no | no |
| **Full** | F5+ | S1--S12 | 1 | yes | yes |
| **Redundant** | F6+ | S1--S12 + redundancy | 2+ | yes | yes |

## Conformance Test Outline <a name="tests"></a>

The conformance test suite consists of **automated, reproducible** tests. Each test references an S-element and produces a **PASS/FAIL** result. The test suite is open source (part of the CLI-CPU repo) and can run both on a simulator (`TCpu`) and physical silicon.

### Test Sets

#### TH-1: Seal Core Boot and Heartbeat (S1, S2)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-1.1 | Health monitor query after boot | at least 1 Seal Core `alive` |
| TH-1.2 | Seal Core firmware hash readback | `SHA-256(fw) == eFuse.SealCoreFwHash` |
| TH-1.3 | Write attempt to firmware storage | trap or no-op, firmware unchanged |

#### TH-2: AuthCode Verify (S3, S11, S12)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-2.1 | Valid `.acode` loading | success, actor can be started |
| TH-2.2 | Unsigned `.acode` loading | `INVALID_SIGNATURE` trap |
| TH-2.3 | Tampered bytecode (1 bit flip) | `CODE_HASH_MISMATCH` trap |
| TH-2.4 | Valid cert, but revoked SubjectId | `CERT_REVOKED` trap |
| TH-2.5 | Valid cert, but eFuse CA Root Hash mismatch | `INVALID_SIGNATURE` trap |
| TH-2.6 | eFuse CA Root Hash readback | not all-zeros |

#### TH-3: CodeLock W-xor-X (S4)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-3.1 | Write to CODE region address | `WRITE_TO_CODE_DENIED` trap |
| TH-3.2 | PC -> DATA region (branch) | `EXECUTE_FROM_DATA` trap |
| TH-3.3 | PC -> STACK region (ROP-like) | `EXECUTE_FROM_DATA` trap |
| TH-3.4 | Fetch from valid CODE | success, no trap |

#### TH-4: Quench-RAM Invariants (S5, S6, S7) -- Full/Redundant only

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-4.1 | Block readback after RELEASE | all bits = 0 |
| TH-4.2 | Write attempt to sealed block | trap or no-op |
| TH-4.3 | Freshly allocated block content | all bits = 0 |
| TH-4.4 | RELEASE atomicity (timing) | 1 cycle, no intermediate state |
| TH-4.5 | SEAL/RELEASE activates only on HW FSM triggers | not accessible from CIL, no such opcode |
| TH-4.6 | GC_SWEEP on another actor's heap | `INVALID_MEMORY_ACCESS` trap |

#### TH-5: Isolation and CFI (S8, S9, S10)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-5.1 | Cross-core memory write | `INVALID_MEMORY_ACCESS` trap |
| TH-5.2 | Cross-core memory read | `INVALID_MEMORY_ACCESS` trap |
| TH-5.3 | `call` to invalid target address | `INVALID_CALL_TARGET` trap |
| TH-5.4 | `ret` with falsified return address | `INVALID_BRANCH_TARGET` trap |
| TH-5.5 | Branch beyond method boundary | `INVALID_BRANCH_TARGET` trap |
| TH-5.6 | Stack overflow (deeply recursive) | `STACK_OVERFLOW` trap |
| TH-5.7 | Stack underflow (pop from empty stack) | `STACK_UNDERFLOW` trap |
| TH-5.8 | `ldloc` with invalid index | `INVALID_LOCAL` trap |

#### TH-6: Redundancy (Redundant level only)

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| TH-6.1 | 2+ Seal Core alive after boot | health monitor: alive count >= 2 |
| TH-6.2 | 1 Seal Core simulated failure | the other takes over, code-load continues |
| TH-6.3 | Heartbeat timeout detection | dead[i] flag set in health monitor |

### Conformance Test Result Format

```json
{
  "schemaVersion": "CFPU-SEC-v1",
  "chipId": "CFPU-2026-XXXX",
  "testSuiteVersion": "1.0.0",
  "level": "Full",
  "timestamp": "2026-04-17T12:00:00Z",
  "results": {
    "TH-1.1": "PASS",
    "TH-1.2": "PASS",
    "TH-2.1": "PASS",
    "...": "..."
  },
  "summary": {
    "total": 27,
    "passed": 27,
    "failed": 0,
    "verdict": "PASS"
  }
}
```

The `verdict` value:
- **PASS** -- all tests in all test sets PASS -> certificate can be issued
- **FAIL** -- any test FAIL -> certificate **cannot** be issued

Partial compliance **does not exist**. Within a level, all elements are mandatory.

## Certificate Format and Registry <a name="certificate"></a>

### Electronic Certificate

The CFPU Foundation issues an **electronic certificate** in W3C Verifiable Credential format, signed with the Foundation's Ed25519 (or PQC) eSeal. Every issued certificate contains:

| Field | Description |
|-------|-------------|
| `id` | Unique URI: `https://cfpu.org/registry/CFPU-YYYY-NNNN` |
| `issuer` | `did:web:cfpu.org` (CFPU Foundation) |
| `issuanceDate` | Date of issue |
| `expirationDate` | Expiration date (default: 2 years) |
| `credentialSubject.sku` | Chip SKU / product identifier |
| `credentialSubject.manufacturer` | Manufacturer name |
| `credentialSubject.conformanceLevel` | `Basic` / `Full` / `Redundant` |
| `credentialSubject.testSuiteVersion` | Test suite version used |
| `credentialSubject.mandatoryElements` | S1--S12 PASS/N-A statuses |
| `proof` | Ed25519Signature2020 or WOTS+ signature |

### Public Registry

The Foundation maintains a **public, queryable, auditable registry** at `https://cfpu.org/registry/`:

- **Search:** by manufacturer, SKU, level, date
- **API:** `GET /registry/{id}` -> JSON-LD Verifiable Credential
- **Status:** `GET /registry/{id}/status` -> `valid` | `revoked` | `expired`
- **CRL:** `GET /registry/crl.json` -> list of revoked certificates
- **Transparency log:** append-only Merkle tree (optional, sigstore/rekor compatible)

### Certificate Revocation

The Foundation may revoke a certificate if:
- A security flaw is subsequently discovered in the certified chip
- The manufacturer provided misleading data
- The chip was modified after certification (new revision without certification)

A revoked certificate gets `revoked` status in the CRL and registry. The certificate holder may appeal within 30 days.

## Regulations of Use -- EUIPO Certification Mark Rules (Draft) <a name="regulations"></a>

This section contains the draft of the **Regulations of Use** required for the EU certification mark application, pursuant to Article 83 of EUIPO Regulation 2017/1001.

---

### Article 1 -- The Mark and Its Owner

**The mark:** CFPU Certified (word mark) + logo (figurative mark)

**Owner:** CFPU Foundation [legal entity to be determined: Hungarian association, EU nonprofit, or Swiss Stiftung]

**Nice classes:** 9 (computer hardware, processors, semiconductors, software), 42 (technical design, R&D services)

### Article 2 -- What the Mark Certifies

The CFPU Certified mark certifies that the designated goods or services **comply** with the mandatory security elements described in the CFPU-SEC-v1 specification (this document), at one of the levels defined therein (Basic, Full, Redundant).

### Article 3 -- Who May Use It

Use of the mark is **available to anyone** who:
1. Submits their product for conformance testing
2. The test result is **PASS** at the requested level
3. Pays the annual registration fee (the CFPU Foundation publicly discloses the fee schedule)
4. Complies with the terms of use (Article 4)

The Foundation **may not refuse** use of the mark based on conditions unrelated to the certified properties. Certification is non-discriminatory -- it cannot be restricted based on geography, ownership, or business model.

### Article 4 -- Terms of Use

When using the mark, the licensee must:
1. Clearly display the **level** (e.g., "CFPU Certified Full")
2. Include the certificate's **unique identifier** (CFPU-YYYY-NNNN) in product documentation
3. Make the **cfpu.org/registry** URL accessible to users
4. Not **modify** the product since certification in ways that affect the certified properties without recertification
5. Comply with the Foundation's logo usage guidelines (sizing, color, context)

### Article 5 -- Testing Procedure

1. The applicant submits the chip/module (physical sample or RTL + simulation capability)
2. The Foundation (or a laboratory accredited by it) runs the CFPU-SEC-v1 conformance test suite
3. The result is PASS/FAIL. In case of FAIL, the Foundation sends a detailed report on failed tests.
4. In case of PASS, the Foundation issues the certificate **within 30 days** and adds it to the registry.
5. The applicant may **appeal** a FAIL decision within 30 days.

### Article 6 -- Fee Schedule

The Foundation publicly discloses the fee schedule. Fees cover:
- Conformance testing costs
- Certificate issuance and registration
- Annual renewal fee (for registry maintenance)

Fees **must not be discriminatory** -- the same fee must be charged for the same level of testing.

### Article 7 -- Revocation

The Foundation may revoke the right to use the mark if:
1. The certified product **does not comply** with the specification (based on subsequent audit)
2. The licensee uses the mark in a **misleading manner**
3. The licensee **fails to pay** the annual fee for more than 90 days
4. The licensee **modified** the product without recertification

Revocation occurs **in writing**, with a 30-day appeal period.

### Article 8 -- Auditing

The Foundation is entitled to:
- Conduct **annual random audits** on a sample of certified products
- Initiate **complaint-based investigations** upon third-party reports
- Audit costs are borne by the Foundation (except in cases of proven deception)

### Article 9 -- Amendments

These Regulations may be amended by the Foundation Steering Committee. Amendments take effect with a **6-month transition period**. The Foundation **directly notifies** existing licensees.

---

## Lifecycle and Versioning <a name="lifecycle"></a>

### CFPU-SEC Specification Versioning

| Field | Meaning |
|-------|---------|
| **Major version** (v1, v2, ...) | Addition of new mandatory elements or deletion of existing ones -> recertification required |
| **Minor version** (v1.1, v1.2, ...) | Clarifications, test additions, textual corrections -> compatible with existing certificates |

### Backward Compatibility

- A **CFPU-SEC-v1-Full** certificate is **valid** for the entire lifetime of v1
- If v2 is released, v1 certificates are **automatically extended by 2 years** (sunset period)
- The Foundation **may not revoke** a certificate solely because a new version was released

### Relationship to Chip Generations

| Chip Generation | Available Level |
|-----------------|----------------|
| F3 Tiny Tapeout | Basic |
| F5 RTL prototype | Basic or Full (depends on QRAM presence) |
| F6 ChipIgnite | Full or Redundant |
| F7+ production | Redundant (recommended for safety-critical applications) |

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-17 | Initial release. 12 mandatory security elements (S1--S12), three certification levels (Basic/Full/Redundant), conformance test suite outline (27 tests), electronic certificate (W3C Verifiable Credential), public registry, EUIPO Regulations of Use draft. |
