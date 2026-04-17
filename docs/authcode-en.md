# AuthCode + CodeLock — Authenticated Code Loading and Hardware-Enforced W⊕X

> Magyar verzió: [authcode-hu.md](authcode-hu.md)

> Version: 1.0

This document describes the **CFPU code-loading security model**: how the hardware guarantees that **only authentic code** can execute, and that **data can never become code**. The mechanism consists of two complementary components: **AuthCode** (signature verification at code load) and **CodeLock** (runtime W⊕X separation). Together they form the foundation of the trust chain — from the CA root hash burned into the eFuse to the Neuron OS Card in the developer's hand.

> **Vision-level document.** The full model takes shape in F5 RTL and reaches silicon in F6. BitIce integration and the Neuron OS Card straddle software and hardware design; concrete parameters (AID, form factor, HSS depth, PIN policy) are open questions tied to specific F-phases.

## Table of Contents

1. [Motivation](#motivation)
2. [Core principle: Trust by Construction](#principle)
3. [Architecture overview](#architecture)
4. [AuthCode — signature verification at load](#authcode)
5. [CodeLock — hardware-enforced W⊕X separation](#codelock)
6. [BitIce certificate integration](#bitice)
7. [The trust chain](#trustchain)
8. [Neuron OS Card](#neuroncard)
9. [The `.acode` container format](#acode)
10. [Developer workflow](#workflow)
11. [Operational patterns](#operational)
12. [Revocation strategy](#revocation)
13. [Hardware requirements and performance](#hardware)
14. [Security guarantees](#security)
15. [Synergy with Quench-RAM and Neuron OS](#synergy)
16. [Open questions](#open)
17. [Phase introduction](#phases)
18. [References](#references)
19. [Changelog](#changelog)

## Motivation <a name="motivation"></a>

In the security models of modern operating systems, **code loading and code execution are weak points**:

- **Linux / Windows:** arbitrary executables may be loaded by any user with `execute` permission. Source verification is optional (code signing), and often bypassable in software.
- **iOS / Android:** code signing is mandatory but enforced in software (kernel-level checks). These systems can be jailbroken; signing bypass is a recurring CVE class.
- **JIT-based environments** (JVM, V8, .NET): new code is generated continuously at runtime — **fundamentally contradicting** strict code signing. Every JIT spray exploit targets this.

The CFPU starts from an **architecturally different** position:

> **No software runs on the chip until the hardware has verified that it originates from an authenticated publisher, and that the bytecode is bit-exact identical to what was signed.**

Two mechanisms enforce this together: **AuthCode** at load time (one-time verification), **CodeLock** at runtime (continuous hardware separation).

The model dramatically simplifies runtime security checks. If every running actor is **trustworthy by construction**, every message need not be cryptographically authenticated — capability-based isolation suffices.

## Core principle: Trust by Construction <a name="principle"></a>

The security model in one sentence:

> **Trust is established once (at code load), not hundreds of millions of times per second (at message send).**

This principle is **fundamentally different** from traditional per-message authentication models (Kerberos, TLS, etc.), and close to the **iOS App Store / Android Play** code-signing approach — but **hardware-enforced** rather than software-checked.

Three building blocks:

1. **A single gate at code loading** — every incoming bytecode is verified by the hardware against a hash-based PQC cert chain
2. **Immutable code region** — loaded code is Quench-RAM-sealed, not modifiable during execution
3. **Data can never execute** — the PC (program counter) physically cannot point into the DATA region

Together: **only and exclusively** CIL bytecode that a known publisher has signed, bit-exact to the signed form, can execute on the chip.

## Architecture overview <a name="architecture"></a>

```
┌─────────────────────────────────────────────────────────────────┐
│ OUTSIDE WORLD                                                   │
│                                                                 │
│  Developer          Neuron OS Card           CIL bytecode       │
│     │                     │                       │             │
│     └──── sign(hash) ─────┘                       │             │
│                     │                             │             │
│                     ▼                             │             │
│            BitIce cert + bytecode ────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                     │
                     │  .acode container
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ CFPU CHIP                                                       │
│                                                                 │
│  [hot_code_loader actor]                                        │
│         │                                                       │
│         ▼                                                       │
│  ┌─ AuthCode verify (BitIce trust chain) ───────────────────┐   │
│  │  1. SHA-256(bytecode) == cert.PkHash ?                   │   │
│  │  2. BitIce.Verify(cert, eFuse.CaRootHash) ?              │   │
│  │  3. cert.SubjectId ∉ revocation_list ?                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │ (all OK)                                              │
│         ▼                                                       │
│  [CODE region — Quench-RAM SEAL]                                │
│         │                                                       │
│  ┌─ CodeLock hardware enforcement ──────────────────────────┐   │
│  │  - PC range check on every fetch                         │   │
│  │  - Write-to-CODE forbidden (except hot_code_loader)      │   │
│  │  - Execute-from-DATA trap                                │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                                                       │
│         ▼                                                       │
│  [scheduler → actor execution]                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The left column is **software** (developer + card + CIL), the right column is **hardware** (on-chip enforcement). The `.acode` container crosses the boundary.

## AuthCode — signature verification at load <a name="authcode"></a>

AuthCode is the cryptographic verification flow of the **hot_code_loader kernel actor**. Every new CIL bytecode passes through it before reaching the Quench-RAM CODE region.

### The verification flow step by step

```
hot_code_loader.LoadActor(acodeContainer):
  // Container split
  bytecode ← acodeContainer.cilBytecode
  cert     ← acodeContainer.bitIceCertificate

  // 1. Code-hash check: does the cert authorize THIS code?
  binary_hash ← SHA-256(bytecode)
  if binary_hash ≠ cert.PkHash then
      trap(CODE_HASH_MISMATCH)
      return

  // 2. BitIce cert-chain verify: does the cert derive from the eFuse root?
  if not BitIceCertificateV1.Verify(cert, eFuse.CaRootHash) then
      trap(INVALID_SIGNATURE)
      return

  // 3. Revocation check: is the cert unrevoked?
  if cert.SubjectId ∈ revocation_list then
      trap(CERT_REVOKED)
      return

  // 4. Allocate and write
  code_region ← Quench-RAM.alloc_code_region(bytecode.length)
  Quench-RAM.write(code_region, bytecode)

  // 5. SEAL — code is now immutable
  Quench-RAM.seal(code_region)

  // 6. Registry entry
  LoadedCodeRegistry.insert(
      actor_id: newActorId,
      code_hash: binary_hash,
      issuer: cert.IssuerId,
      subject: cert.SubjectId,
      code_region: code_region
  )

  // 7. Scheduler may spawn the actor
  scheduler.allow_spawn(newActorId, code_region)
```

Failure of any step → `trap` and the actor **never starts**. No runtime attack surface, because bad code never reaches the chip.

### Why `cert.PkHash == SHA-256(bytecode)`

The BitIce cert format (see [BitIce integration](#bitice)) stores **the hash of the signed card's public key** in the `PkHash` field. Adapted to the CFPU, we use this for **the SHA-256 hash of the CIL bytecode**. This cryptographically binds the cert **to that specific bytecode** — the same cert cannot be used for different bytecode because step 1 would fail.

## CodeLock — hardware-enforced W⊕X separation <a name="codelock"></a>

CodeLock is the runtime mechanism that makes it **physically impossible** for:
- data to execute (execute-from-DATA),
- code to be modified (write-to-CODE),
- the program counter to point to an invalid address.

### Hardware checks

| Check | Where | Trap |
|-------|-------|------|
| PC range check | before every instruction fetch | `INVALID_PC` |
| Write-to-CODE region | every memory store | `WRITE_TO_CODE_DENIED` |
| Execute-from-DATA | every fetch from DATA | `EXECUTE_FROM_DATA` |
| CODE block status check | every fetch verifies Quench-RAM status | `CODE_NOT_SEALED` |

The architecture is already **Harvard-like** (per `docs/architecture-en.md` line 105 the CODE and DATA live in separate address spaces), but CodeLock **enforces this in hardware** — not an optional configuration, but part of the decoder.

### What it explicitly excludes

- **JIT compilation:** none. Any attempt by CIL code to write new bytecode into a new memory region and jump there results in a `WRITE_TO_CODE_DENIED` trap. **JIT cannot run on the CFPU** — a security advantage (no JIT spraying), and the .NET native CIL execution makes JIT unnecessary anyway.
- **Shellcode injection:** a buffer overflow cannot "drop" new code into DATA because DATA has no execute.
- **Self-modifying code:** Quench-RAM SEAL guarantees the loaded code stays bit-exact until the CODE region is released (which can only happen via GC).
- **Return-to-data gadgets:** PC range check fires on every fetch; a PC jump back to stack / heap / any DATA address traps.

### Why Quench-RAM "gives this for free"

The Quench-RAM cell described in `docs/quench-ram-en.md` uses **the same status-bit mechanism** for the CODE region as everywhere else:
- `hot_code_loader` writes bytecode (status=0, mutable)
- After writing, SEAL is triggered (status=1, immutable)
- During execution every fetch checks the status
- GC or unload calls RELEASE (status→0, data→0, region becomes re-allocatable)

CodeLock is not a separate hardware module — **it is a targeted application of Quench-RAM semantics** to the CODE region.

## BitIce certificate integration <a name="bitice"></a>

The CFPU uses **the BitIce library** (`github.com/BitIce.io/BitIce`) as its cryptographic foundation for signature verification. BitIce is a hash-based post-quantum PKI framework:

- **WOTS+** (Winternitz One-Time Signature Plus) — the signing primitive
- **LMS Merkle tree** — stateful tree-based signature structure
- **SHA-256** — the sole hash function
- **HSS** — Hierarchical Signature Scheme for larger signature counts
- **BitIceCertificateV1** — compact (71 byte) and full (2535 byte) certificate format

### `BitIceCertificateV1` fields in the CFPU context

```
BitIceCertificateV1 (compact 71 byte):
  Version       (1)   : 0x01
  Type          (1)   : 0x01 (Card / actor binary)
  H             (1)   : Merkle tree height (5-15, default 10)
  SubjectId    (16)   : signed entity ID (here: code / actor identifier)
  IssuerId     (16)   : issuing delegate ID (Neuron OS Vendor)
  PkHash       (32)   : SHA-256(CIL bytecode)   ◄── binds cert to code
  SignatureIndex(4)   : LMS leaf index (anti-replay)

BitIceCertificateV1 (full 2535 byte):
  [compact 71 byte]
  AuthPath   (320 byte)  : Merkle path (h=10 × 32 byte)
  WotsSig   (2144 byte)  : WOTS+ signature (67 × 32 byte)
```

### The `Verify` procedure (from the BitIce codebase)

```csharp
public bool Verify(ReadOnlySpan<byte> caRoot)
{
    // 1. TBS hash
    byte[] tbsHash = SHA256.HashData(tbs);
    // 2. WOTS+ pk reconstruction
    byte[] computedPk = WotsPlus.ComputePublicKeyFromSignature(wotsSignature, tbsHash);
    // 3. Leaf hash
    byte[] leafHash = SHA256.HashData(computedPk);
    // 4. Merkle root recomputation
    byte[] computedRoot = LmsMerkleTree.ComputeRoot(leafHash, sigIndex, authPath, TreeHeight);
    // 5. Compare to CA root
    return computedRoot.SequenceEqual(caRoot);
}
```

Five SHA-256-based steps. A hardware SHA-256 unit on the CFPU executes this directly — no ECC, no RSA, no other asymmetric primitive needed.

### Why hash-based, not ECDSA / Ed25519

| Aspect | ECDSA / Ed25519 | WOTS+ / LMS (BitIce) |
|--------|-----------------|-----------------------|
| Quantum resistance | ❌ (Shor's algorithm breaks it) | ✅ (hash-based, Grover only 2× speedup) |
| Hardware primitives | elliptic curve math + hash | **only SHA-256** |
| NIST-standardized | FIPS 186 | FIPS 205 (SLH-DSA) + NIST SP 800-208 (LMS/HSS) |
| Stateful? | No | **Yes** — single-use leaf enforcement required |
| Hardware state management | Unnecessary | **Mandatory** (NIST SP 800-208 SHALL) |

The stateful nature of hash-based schemes is a **positive property** in the CFPU context because the BitIce card physically enforces single-use (see [Neuron OS Card](#neuroncard)).

## The trust chain <a name="trustchain"></a>

The full authentication chain from the manufacturing-time hardware root to the developer's card:

```
[Chip eFuse: 32 byte CA Root Hash]                    ← burned at manufacture, immutable
        │ root-of-trust (hardware)
        ▼
[BitIce CFPU Foundation Root CA]                      ← HSM-held
        │ signs WOTS+ (HSS level 1)
        ▼
[Neuron OS Vendor Delegate Cert]                      ← vendor (e.g., FenySoft)
        │ signs WOTS+ (HSS level 2)
        ▼
[Neuron OS Card]                                      ◄── DEVELOPER CARD
   └─ BitIce Neuron OS Applet                         ← physical SE, single-use leaf
        │ signs WOTS+ (leaf in XMSS tree, h=10)
        ▼
[CIL Binary Cert]                                     ← specific bytecode signature
        │ verifies on
        ▼
[CFPU AuthCode loader]                                ← on-chip verify + load
```

### Every element is hardware-protected

| Element | Where | Protection |
|---------|-------|-----------|
| CA Root Hash | eFuse on chip | burned at manufacture, never modifiable |
| Foundation Root CA | dedicated HSM | FIPS 140-3 Level 3+ tamper-resistant |
| Vendor Delegate Cert | vendor HSM | same |
| Neuron OS Card | developer's hand | tamper-resistant smart card, single-use NVRAM counter |
| `.acode` file | developer's machine | needs no protection — the signature is self-authenticating |

**No point in the chain relies on software alone.** Trust always lives in a physical device.

## Neuron OS Card <a name="neuroncard"></a>

The Neuron OS Card is a dedicated, single-purpose BitIce smart card running a separate **BitIce Neuron OS Applet** on the **JavaCard runtime**. This card is **mandatory** for every developer deploying actors to the CFPU.

### Why hardware-enforced signing is mandatory

The WOTS+ signing primitive has **one critical property**: a leaf key may be used **exactly once**. Dual use lets an attacker **interpolate to forge arbitrary signatures** — security collapses totally.

A software signer can **never** reliably guarantee this:
- VM snapshot → state rollback → same leaf used twice
- Backup restore → state rollback
- Race condition between two concurrent signing operations
- Memory dump → private key theft

**NIST SP 800-208** (the LMS/HSS standard) therefore **explicitly forbids** software-only state tracking:

> *"State management for stateful hash-based signature schemes SHALL be performed by the cryptographic module that contains the private key, and SHALL NOT rely on external software or operating system support."*

The Neuron OS Card's tamper-resistant smart card hardware guarantees:

| Guarantee | Mechanism |
|-----------|-----------|
| Single-use leaf index | NVRAM counter, atomic write-before-sign |
| State non-clonable | Private key never leaves the card |
| State non-rollback-able | Tamper detection + secure element zone |
| No backup creatable | Private key export disabled |
| Side-channel resistant | Constant-time WOTS+ implementation |

### Why a separate card and separate applet

JavaCard 3.x+ runtime provides an **applet firewall** — one applet cannot access another's data. A dedicated **Neuron OS Applet** in the BitIce ecosystem offers:

| Advantage | Meaning |
|-----------|---------|
| Domain isolation | A bug in an identity / payment applet doesn't leak Neuron OS state |
| Independent leaf counter | The Neuron OS HSS space is consumed only by CIL signing |
| Independent cert chain | Different vendor delegate than for general BitIce uses |
| Independent PIN / policy | Stricter PIN / biometrics for code signing |
| Independent audit log | "Who and when signed CIL" — clean forensic trail |
| Independent lifetime | Card replaceable on the Neuron OS side without impacting other BitIce functions |

A **dedicated card** (not multi-applet) reinforces further:
- Physical separation — developer doesn't mix with banking / identity card
- Reduced attack surface — single applet = smaller JavaCard runtime surface
- Simpler audit — "CFPU code-signing card" is unambiguously identifiable

### Applet APDU interface (sketch)

```
SELECT_APPLET   <Neuron OS Applet AID>      → authenticate
SIGN_CIL_HASH   <SHA-256 hash>              → BitIceCertificateV1 (compact 71 byte)
GET_FULL_CERT                                → BitIceCertificateV1 (full 2535 byte)
GET_CERT_CHAIN                               → chain up to root
GET_REMAINING                                → remaining usable leaves
ROTATE_KEY                                   → new sub-tree (HSS deeper level)
```

The concrete APDU byte layout, AID, PIN policy, and form factor are **F-phase open questions** (see [Open questions](#open)).

## The `.acode` container format <a name="acode"></a>

The developer uses the `cli-cpu-link` tool to produce an **`.acode`** file wrapping CIL bytecode and the BitIce cert in one container:

```
.acode file layout (sketch):
  ┌────────────────────────────────────────────┐
  │ Magic:  "ACODE"                  5 bytes   │
  │ Version:                         1 byte    │
  │ Flags:                           2 bytes   │
  │ BitIce cert length:              4 bytes   │
  │ CIL bytecode length:             8 bytes   │
  │ BitIce certificate:     variable (2535)    │
  │ CIL bytecode:           variable           │
  │ CRC32 over all:                  4 bytes   │
  └────────────────────────────────────────────┘
```

The exact format is an **implementation question** to be finalized when `cli-cpu-link` introduces it. The key property: **self-contained** — `hot_code_loader` finds everything it needs for verification.

## Developer workflow <a name="workflow"></a>

```
1. Write C# code                           (developer)
2. dotnet build → CIL bytecode              (Roslyn)
3. cli-cpu-link:
     hash ← SHA-256(bytecode)
4. Neuron OS Card connected:
     SELECT_APPLET <Neuron OS Applet AID>
     PIN / biometric prompt
5. cli-cpu-link → card:
     SIGN_CIL_HASH(hash)
       → card NVRAM: leaf_index++ (atomic commit BEFORE return)
       → card: WOTS+ sign TBS (TBS contains the hash in PkHash)
       → return: BitIceCertificateV1 (full 2535 byte)
6. cli-cpu-link package:
     bytecode + cert → program.acode
7. Deploy:
     hot_code_loader accepts .acode
     AuthCode flow runs (see above)
     on success: Quench-RAM SEAL → scheduler may spawn
```

**Steps 4-5 are the only part** requiring a physical card. An h=10 XMSS tree provides 1024 signatures; at 1-3 builds per day this covers **1-3 years** of developer activity, after which key rotation (ROTATE_KEY) or a new card.

## Operational patterns <a name="operational"></a>

### CI/CD integration

In modern dev workflows, CI/CD pipelines auto-sign builds. This **requires a physical card** connected to the build server. Three viable patterns:

| Pattern | Meaning | Tradeoff |
|---------|---------|----------|
| **Dedicated CI/CD card** | Card server in a locked room → build server accesses over network | Standard, scalable, audit-friendly |
| **Developer-signs-only** | Every developer signs locally, CI only verifies | Manual, slower, but minimal attack surface |
| **Tiered**: dev / prod | Dev branch software signer (simulator only), prod uses hardware card | Hybrid, but "software signer" output is NOT executable on CFPU, only simulator |

**Dedicated CI/CD card** is the most common — analogous to AWS CloudHSM, Azure Key Vault HSM mode. BitIce must support a **server form factor** for this (PCIe or network appliance running JavaCard runtime) — a BitIce roadmap item.

### Emergency hotfix

For a 3am critical bug:
- On-call engineer **physically present** with their card
- Or: "emergency response" card in a safe with m-of-n access (e.g., two engineer PINs required)
- Every signature audited → forensic review after the fact

This **matches** traditional TLS cert HSM management practice.

### Open source contributor model

A GitHub contributor cannot sign CFPU-deployable code directly (no delegate cert). Two accepted patterns:

| Model | How it works |
|-------|--------------|
| **Maintainer-resigning** | Project maintainer reviews the PR and re-signs the merged bytecode with their own card |
| **Per-project sub-CA** | Project vendor delegate issues "contributor cards" to active contributors |

**Maintainer-resigning** is the safer default — reminiscent of the Debian package-signing model.

## Revocation strategy <a name="revocation"></a>

If a Neuron OS Card is lost, stolen, or its private key is otherwise compromised, associated certs **must be revoked**.

### Possible mechanisms (F-phase decision)

| Mode | How it works | Complexity |
|------|--------------|-----------|
| **Local revocation list** | Chip stores a revoked-list in Quench-RAM, updated via signed writes | Simple, local, but chip-memory hungry |
| **Cert validity period** | Every cert has a short lifetime, periodic re-issuance | Heavy infrastructure, but no revocation list |
| **OCSP-like query** | Every code load queries cert status online | Internet-dependent, fails offline |
| **Hybrid** | Local revocation list + optional online check | Flexible, but more code |

The exact decision is an **F5-F6 question**. The v1.0 model records that **local revocation list** is the baseline, extensible as needed.

## Hardware requirements and performance <a name="hardware"></a>

### Fixed hardware overhead

| Component | Size | Note |
|-----------|------|------|
| SHA-256 unit | ~5K gates | already needed for Quench-RAM payload_hash |
| WOTS+ verifier state machine | ~3K gates | just SHA-256 chaining |
| Merkle path verifier | ~2K gates | h=10 iteration |
| eFuse (CA Root Hash) | 256 bit + ECC | manufacture-time |
| PC range comparator | ~32 gates per core | part of CodeLock |
| Write-to-CODE enforcement | ~Quench-RAM existing | nothing new |

**Total new hardware:** ~10K gates + eFuse. **Two orders of magnitude smaller** than e.g. a per-message auth system would have been.

### Memory overhead

| Purpose | Size | Frequency |
|---------|------|-----------|
| Loaded Code Registry | ~256 bytes/actor | permanent while alive |
| Revocation list (optional) | ~16 bytes/entry × max 1024 | ~16 KB if used |
| Temporary: .acode buffer during load | bytecode size + 2535 byte cert | transient |

### Verification time

A typical cert-verify (h=10 XMSS):

| Step | SHA-256 ops | Cycles (1 GHz, HW) |
|------|-------------|---------------------|
| TBS hash | 1 | ~80 |
| WOTS+ recompute (67 × ~7.5 avg) | ~500 | ~40K |
| Leaf hash | 1 | ~80 |
| Merkle path (h=10) | 10 | ~800 |
| **Total** | **~512** | **~41K cycles ≈ 41 µs** |

Loading 100 KB CIL bytecode: ~100 µs (SHA-256 compute) + 41 µs (verify) + 10 µs (seal) = **~150 µs**. **One-time**, at actor spawn. **Zero overhead** during execution.

## Security guarantees <a name="security"></a>

AuthCode + CodeLock + Neuron OS Card together **eliminate eight** classic attack categories at hardware level:

| Attack class | CWE | Traditional CPU | CFPU (AuthCode+CodeLock) |
|-------------|-----|-----------------|---------------------------|
| Shellcode injection | CWE-94 | Vulnerable | **Eliminated** (CodeLock: W⊕X) |
| JIT spraying | — | Every JIT environment | **Eliminated** (no JIT) |
| Code reuse / gadgets | — | ROP/JOP possible | **Eliminated** (CodeLock + Quench-RAM SEAL) |
| Unsigned code execution | CWE-345 | OS-dependent, bypassable | **Eliminated** (AuthCode mandatory) |
| Tampered binary | CWE-345 | Software check, bypassable | **Eliminated** (SHA-256 hash ↔ PkHash binding) |
| Supply chain at code level | — | Unverifiable | **Verifiable** (BitIce trust chain) |
| Stateful sig key reuse | — | Easy with software signer | **Eliminated** (Neuron OS Card single-use NVRAM) |
| Quantum break of signature | — | Shor breaks ECDSA/Ed25519 | **Eliminated** (WOTS+/LMS hash-based PQC) |

## Synergy with Quench-RAM and Neuron OS <a name="synergy"></a>

### Quench-RAM

CodeLock is **not new hardware** — it is a targeted application of the Quench-RAM cell (`docs/quench-ram-en.md`) to the CODE region:

- `hot_code_loader` writes bytecode into status=0 Quench-RAM blocks
- After writing, the loader triggers SEAL
- During execution the hardware permits fetch based on the status bit
- On unload, GC or loader triggers RELEASE → region is re-allocatable

The Quench-RAM per-block status bit mechanism guarantees **exactly** what CodeLock needs: the CODE region may be written only once (during a load cycle), and loaded code stays immutable for its lifetime.

### Neuron OS hot code loader

[`NeuronOS/vision-en.md#kernel-actors-root-level`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md#kernel-actors-root-level) describes a `hot_code_loader` actor receiving new CIL code. AuthCode becomes its **security module**:

```
hot_code_loader (Neuron OS kernel actor):
  - receives .acode container as message
  - AuthCode flow (verify + load + seal)
  - on success: report_success(new_actor_id) → parent supervisor
  - on failure: report_failure(reason) → security_log actor
```

The `hot_code_loader` itself is **a signed actor** — part of the root supervisor tree, either vendor-delegated or directly root-CA-signed. This is the basis of recursive trust.

### Per-actor capability model

AuthCode verifies only **code loading** — interactions among running actors are still governed by the existing capability-based system ([`NeuronOS/vision-en.md#capability-based-security`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md#capability-based-security)). The two are orthogonal:

- **AuthCode:** "who may run on the chip at all"
- **Capability:** "what a running actor may do"

## Open questions <a name="open"></a>

v1.0 captures the vision-level architecture. The following details are to be resolved in **later F-phases**, aligned with the hardware and software state at that time.

### Around F4-F5 (sim + RTL prototype)

1. **CA Root Hash source in eFuse** — single global CA root, vendor-customized root, or multiple root slots?
2. **Revocation list size and update mechanism** — max revoked entries on-chip?
3. **HSS depth in the BitIce cert chain** — h=10 (1024), h=15 (32K), or deeper? Each level is one HSS tier.

### Around F5-F6 (first hardware)

4. **Neuron OS Card AID** — registered ISO/IEC AID under the BitIce RID (e.g. `<RID>+"NEURONOS"`).
5. **Form factor** — ISO 7816 ID-1 (card), USB token, NFC, or multiple variants in parallel.
6. **PIN / biometric policy** — single PIN, dual-PIN (m-of-n), on-card fingerprint, or opt-in combinations.
7. **Server-side BitIce HSM** — PCIe or network appliance for CI/CD pipelines.

### Around F6-F7 (production)

8. **Final revocation mechanism** — local list, OCSP-like query, or hybrid.
9. **Open source contributor infrastructure** — per-project sub-CA provisioning process.
10. **Emergency response protocol** — m-of-n quorum rules, audit logging requirements.

These questions **do not block** earlier phases — the v1.0 model allows consistent decisions on each dimension.

## Phase introduction <a name="phases"></a>

| Phase | Role of AuthCode + CodeLock + Neuron OS Card |
|-------|----------------------------------------------|
| F0–F2 (simulator) | Software emulation in `TCpu`: AuthCode verify mock, CodeLock as runtime check; `.acode` format can be finalized here |
| F3 (Tiny Tapeout) | No hardware AuthCode (area limit), but CIL-T0 ISA already specifies the `hot_code_loader` interface |
| F4 (multi-core sim) | Full software AuthCode flow, BitIce library integrated into the simulator; **simulated Neuron OS Card** for unit tests |
| **F5 (RTL prototype)** | First hardware SHA-256 + WOTS+ verifier; **real Neuron OS Card** prototype (dev kit); first version of the BitIce Neuron OS Applet |
| F6 (ChipIgnite tape-out) | Full hardware AuthCode + CodeLock + eFuse; production Neuron OS Card available to developers |
| F6.5 (Secure Edition) | Finer revocation mechanism, dual-cert support (e.g., for FIPS certification path) |
| F7 (silicon iter 2) | Emergency response protocol, global revocation grid |

## References <a name="references"></a>

### Internal documents

- `docs/quench-ram-en.md` — the Quench-RAM memory cell on which CodeLock is built
- `docs/security-en.md` — the CFPU security model that AuthCode extends
- [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md) — the `hot_code_loader` actor and the capability model
- `docs/architecture-en.md` — the CFPU Harvard architecture on which CodeLock builds
- `docs/secure-element-en.md` — the Secure Edition (F6.5) may use this mechanism for its TEE

### External references

- BitIce project: `github.com/BitIce.io/BitIce`
- NIST SP 800-208: Recommendation for Stateful Hash-Based Signature Schemes
- NIST FIPS 205: Stateless Hash-Based Digital Signature Standard (SLH-DSA)
- NIST FIPS 180-4: SHA-256 specification
- RFC 8554: Leighton-Micali Hash-Based Signatures (LMS)
- RFC 8391: XMSS: eXtended Merkle Signature Scheme

## Changelog <a name="changelog"></a>

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-16 | Initial vision-level release. AuthCode (load-time verify) + CodeLock (W⊕X hardware) + BitIce WOTS+/LMS integration + Neuron OS Card (dedicated JavaCard applet). Detailed parameters (AID, form factor, HSS depth, PIN policy, revocation, CI/CD HSM) are F-phase-dependent open questions. |
