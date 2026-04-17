# CLI-CPU Secure Edition — Open Secure Element / TEE / JavaCard Successor

> **Strategic positioning document.** This is the third market track alongside Cognitive Fabric and Trustworthy Silicon. It describes a separate chip family built on the same base architecture, augmented with Secure Element-specific hardware components, targeting the JavaCard / TEE / Secure Element market.

> Magyar verzio: [secure-element-hu.md](secure-element-hu.md)

> Version: 1.0

## Table of Contents

1. [Why a Third Track](#why-a-third-track)
2. [The Secure Element Market Overview](#the-secure-element-market-overview)
3. [Competitor Map — Closed Vendors and Open Projects](#competitor-map)
4. [TROPIC01 — In-Depth Analysis of the First Open Secure Element](#tropic01-in-depth)
5. [CLI-CPU Secure Edition — Positioning and Differentiation](#positioning)
6. [Architectural Fit — What We Have and What Is Missing](#architectural-fit)
7. [Required Additions](#required-additions)
8. [Certification Path](#certification-path)
9. [Product Family and Use Cases](#product-family)
10. [New Phase: F6.5 — Secure Edition Parallel Tape-Out](#f6-5-phase)
11. [Partnerships and Community](#partnerships)
12. [Realistic Timeline](#timeline)
13. [Next Steps](#next-steps)

## Why a Third Track <a name="why-a-third-track"></a>

The existing `docs/architecture-en.md`, `docs/security-en.md`, and [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md) documents established **two market tracks**:

1. **Cognitive Fabric** — programmable cognitive substrate, AI/SNN/actor cluster (long-term vision)
2. **Trustworthy Silicon** — regulated industries (automotive, aviation, medical, critical infra), short-to-medium-term revenue

This document introduces a **third track**: the **Secure Element / TEE / JavaCard** market. Three reasons justify a separate strategic-level document:

1. **Massive market.** ~$25-40B globally, growing fast, and **ten times larger** than what we have positioned so far
2. **Perfect architectural fit.** The core properties of CLI-CPU (memory safety, shared-nothing, formally verifiable ISA, small die size, low power, determinism) are **exactly** what the Secure Element market demands
3. **Distinctive positioning is possible.** Current open SE projects (TROPIC01, OpenTitan) **all** use single-core, traditional models. The CLI-CPU multi-core, shared-nothing, actor-based approach could **create a new category**: multiple independent Secure Elements on a single chip, with hardware isolation

The goal is **not** to replace Cognitive Fabric or Trustworthy Silicon, but to add a **complementary** market area on the same base hardware. Alongside F6 (eFabless ChipIgnite tape-out), an **F6.5 Secure Edition** variant can be produced, adding Secure Element-specific components (crypto accelerators, TRNG, PUF, tamper detection, side-channel countermeasures) -- with **minimal redesign**.

## The Secure Element Market Overview <a name="the-secure-element-market-overview"></a>

### What Is a Secure Element

A **Secure Element (SE)** is a dedicated chip or chip region that stores and processes sensitive data (keys, banking data, biometric data, device identity) in isolation from the main computing environment. Its fundamental properties are:

- **Tamper resistance** -- protection against physical attacks (decapsulation, probing, laser injection, voltage glitching)
- **Memory isolation** -- the main CPU cannot directly read or write the SE's memory
- **Cryptographic co-processor** -- AES, SHA, RSA/ECC, post-quantum accelerators
- **True Random Number Generator (TRNG)** -- entropy source for key generation
- **Secure storage** -- one-time programmable memory (OTP/eFuse) for root keys
- **Secure boot + attestation** -- a measurement chain through which the chip proves to the host system that only authorized firmware is running
- **Certification** -- Common Criteria EAL-5+ or EAL-6+ level (following the most rigorous physical security evaluation)

### The JavaCard Legacy

**JavaCard** (Oracle, originally Sun Microsystems, released in 1996) is the world's most widely deployed smart card software platform. An estimated **~30 billion cards** run it worldwide: SIMs, banking cards, national eID, transit tickets, eSIMs, FIDO authenticators. JavaCard does **exactly** what CLI-CPU also aims to do -- **native bytecode execution** on isolated security hardware -- except:

- **Java 1.5 level** (2004), lacking any modern developer experience
- **Closed ecosystem**, Oracle license, high barrier to entry
- **Software interpreter** on an 8-bit or 16-bit (rarely 32-bit) MCU
- **Software-based application isolation** -- the JavaCard runtime "isolates" different applets using a software verifier
- **Fixed crypto algorithms** -- adding new (e.g. post-quantum) algorithms is difficult
- **Limited multi-threading** -- only one applet is active at a time per card

**JavaCard is an aging architecture** that has received no substantive refresh in 30 years. There is **almost no competition** in the market -- Oracle, a handful of hardware vendors (Gemalto/Thales, Idemia, G+D), and the JavaCard 3.2 specification cover the entire landscape. It is an **ideal replacement target** for a more modern, open, genuinely isolated, actor-based platform.

### TEE (Trusted Execution Environment)

A TEE is an isolated computing environment that runs alongside the main OS. Current commercial TEEs all suffer from **known vulnerabilities**:

| TEE | Vendor | Known Vulnerabilities |
|-----|--------|-----------------------|
| **Intel SGX** | Intel | Foreshadow, L1TF, Plundervolt, SGAxe, AEPIC Leak, hundreds of INTEL-SA advisories |
| **AMD SEV / SEV-SNP** | AMD | SEVered, Cipherleaks, Undeserved, vulnerabilities |
| **ARM TrustZone** | ARM | CacheOut, numerous implementation bugs |
| **Apple Secure Enclave** | Apple | Closed, non-auditable; SEP keys leaked up to A11 |
| **Google Titan M2** | Google | Closed, though several bugs found in Titan M already |
| **RISC-V Keystone** | Academic | Experimental status |

The common problem: TEEs are **retrofitted onto** a shared-memory, speculative-execution CPU. CLI-CPU, by contrast, is **shared-nothing by design**, so there is **no isolation layer to add after the fact** -- it is the foundation of the system.

### Market Size

The annual global market for Secure Element / TEE / SE-based products:

| Segment | Annual Market | Typical Product |
|---------|---------------|-----------------|
| **Smart card chips (JavaCard)** | ~$12-15B | SIM, banking card, eID, transit |
| **eSIM / iSIM** | ~$8-12B | embedded SIM in mobile, IoT |
| **TEE / Secure Enclave** | ~$5-10B | Intel SGX, Apple Secure Enclave, ARM TrustZone |
| **HSM (Hardware Security Module)** | ~$2B | datacenter key management |
| **FIDO2 / Passkey authenticator** | ~$1B | YubiKey, hardware token |
| **TPM (Trusted Platform Module)** | ~$2B | Windows PC, server, IoT RoT |
| **Automotive secure element** | ~$1B | V2X, digital key, OTA update |
| **Total** | **~$30-42B** | -- |

This is **ten times larger** than the initial Cognitive Fabric positioning, and **growing fast** -- driven by post-quantum migration, zero-trust architecture, and mass FIDO2 adoption, the market could reach **~$60-80B** by 2030.

## Competitor Map <a name="competitor-map"></a>

### Closed Vendors -- The Main Market Targets

| Vendor | Products | Annual Revenue (Group) | Openness |
|--------|----------|------------------------|----------|
| **Thales** (ex-Gemalto) | SIM, banking, eID, eSIM | ~EUR15B | closed |
| **Idemia** (ex-Oberthur) | banking, biometric ID | ~EUR2.5B | closed |
| **Giesecke+Devrient** | SIM, banking, eGovernment | ~EUR3B | closed |
| **Infineon** | SLE/SLS Secure Elements | ~EUR15B | closed |
| **NXP** | SmartMX, A71CH, EdgeLock | ~EUR13B | closed |
| **STMicroelectronics** | ST33, ST54 | ~EUR17B | closed |
| **Samsung Semiconductor** | embedded Secure Element | -- | closed |

**All closed, all expensive, all built on legacy architectures.** The barrier to entry is high (Common Criteria certification, partner relationships, decades of IP portfolios), but **open alternatives are now emerging**, and the market is **receptive** to them -- especially in the EU, where sovereignty and auditability are increasingly important.

### Big Tech In-House SEs

| Company | Chip | Scope |
|---------|------|-------|
| **Apple** | Secure Enclave (A/M series) | iPhone/Mac/iPad, Face ID, Touch ID, Apple Pay |
| **Google** | Titan M2 (Pixel), Titan (server) | Android secure boot, confidential computing |
| **Samsung** | Knox Vault | Galaxy secure element |
| **Microsoft** | Pluton (AMD, Intel, Qualcomm) | Windows device RoT |

These are **all closed** and designed exclusively for their respective platforms. External developers cannot access, audit, or replace them.

### Open Projects

#### OpenTitan (Google + lowRISC + Partners, 2019-)

The **first open-source silicon Root of Trust project**, initiated by Google. Uses an **Ibex RISC-V** core (the same as TROPIC01). Coordinated by the lowRISC foundation (Cambridge, UK).

- **Focus**: datacenter Root of Trust (in Google servers)
- **Status**: first earlgrey chip taped out in 2024, orderable
- **Backers**: Google, Nuvoton, Winbond, Western Digital, lowRISC
- **License**: Apache 2.0

#### TROPIC01 (Tropic Square, Prague, 2019-)

The **first genuinely commercial open secure element**, backed by SatoshiLabs (the parent company of the Trezor hardware wallet). Covered in detail in the next section.

## TROPIC01 -- In-Depth Analysis of the First Open Secure Element <a name="tropic01-in-depth"></a>

TROPIC01 is **not just a concept or prototype** -- it is in **full production as of 2026 Q1**, already orderable, and the first partner products (the next-generation Trezor hardware wallet, MikroE Secure Tropic Click) are already available. This is the **first** real-world example of what the CLI-CPU Secure Edition also targets: an **open-architecture, auditable secure element**.

### Architecture

| Component | Details |
|-----------|---------|
| **Main CPU** | **Ibex RISC-V**, dual lock-step configuration (ISO 26262-friendly, automotive-compatible pattern) |
| **Cryptographic co-processor** | **SPECT** -- a dedicated unit with its own ISA, where cryptographic operations run. Not on the RISC-V core! |
| **Package** | QFN32, ~4x4 mm |
| **Host interface** | SPI, **encrypted channel with forward secrecy** |
| **Memory** | OTP (x.509 and root keys) + Flash (general data, PIN) + NVM on-the-fly encryption + ECC protection + memory address scrambling |

The **SPECT co-processor** is a particularly interesting design pattern: the cryptographic workload runs **not** on the main RISC-V core, but on a dedicated unit with its own ISA. This provides **three advantages**:
1. **Security** -- the main OS never sees a raw key
2. **Speed** -- SPECT is optimized for the specific algorithms
3. **Side-channel resistance** -- SPECT operates in constant time with constant power consumption

### Cryptography (SPECT Accelerators)

| Category | Algorithms |
|----------|-----------|
| **Asymmetric** | **Ed25519** EdDSA, **P-256** ECDSA, **X25519** Diffie-Hellman |
| **Hash** | SHA-256, SHA-512, **Keccak** (SHA-3) |
| **Symmetric** | **AES-256-GCM** |
| **Lightweight AEAD** | **ISAP** (NIST LWC finalist) |

**Notable omission:** TROPIC01 **does not support RSA**. This is a **deliberate decision**: Ed25519 and ECDSA are more modern, use smaller keys, and are less susceptible to timing attacks. **No legacy.**

### Physical Security (Full Package)

| Component | Function |
|-----------|---------|
| **Electromagnetic pulse detector** | EM glitch injection protection |
| **Voltage glitch detector** | supply voltage manipulation protection |
| **Temperature sensor** | freeze and heat-based attack protection |
| **Laser detector** | optical fault injection protection |
| **Active shield** | metal mesh over the die; breakage triggers key zeroization |
| **PUF** (Physically Unclonable Function) | chip-unique physical identity |
| **TRNG** | entropy source for key generation |

These components **typically** require years of engineering work, and closed vendors **guard** these designs closely. Tropic Square has **published every detail**, which is a **tremendous** contribution to the open hardware community.

### Openness -- This Is the Key

The openness of TROPIC01 is **not marketing** -- it is **real and verifiable**:

| Component | Status | GitHub Repository |
|-----------|--------|-------------------|
| **Main documentation** | public | `tropicsquare/tropic01` |
| **RTL (SystemVerilog)** | **public** | `tropicsquare/tropic01-rtl` |
| **Application firmware (C)** | **public** | `tropicsquare/ts-tr01-app` |
| **SPECT compiler** | **public** | separate repo |
| **SPECT firmware** | **public** | separate repo |
| **SDK and host libraries** | public | Tropic Square GitHub |
| **Development board** | MikroE Secure Tropic Click | mikroe.com |

This is **the first Secure Element** where the owner can **genuinely verify** what is on the chip -- not just the binary, but the **source RTL** as well. This is **revolutionary**.

### Maturity

- **Founded**: 2019
- **First tape-out**: ~2023-2024
- **General availability (GA)**: 2025 Q1
- **Full production**: 2026 Q1
- **Embedded World 2026** -- public demonstration and partner announcements
- **Reference products**: next-generation Trezor hardware wallet, MikroE Secure Tropic Click

**Development time**: **~6 years** from founding to full production. This is an important benchmark for our own plans.

### What We Learn from TROPIC01

1. **The open SE market exists and is supported.** Not a research fantasy, but a real market with real customers and real partners.
2. **The SPECT pattern is valuable.** A dedicated crypto co-processor with its own ISA is faster, more secure, and more side-channel resistant than crypto running on the main core.
3. **Tamper detection is complex but can be shared openly.** The TROPIC01 RTL provides a **learning resource** for how to design these components.
4. **The Ibex dual lock-step approach is ISO 26262-friendly.** A deliberate choice for anyone targeting the automotive market.
5. **The MikroE partnership model is worth adopting.** A hobbyist expansion board **dramatically** increases the developer community's reach.
6. **Modern crypto only** -- RSA omitted, only Ed25519 / ECDSA / X25519 / AES-GCM / Keccak. This yields a **cleaner** codebase and a **smaller** attack surface.
7. **Development timeframe**: ~6 years from founding to production. A realistic target for the CLI-CPU Secure Edition as well.
8. **SatoshiLabs partnership**: the Bitcoin/crypto community is **willing to fund** open hardware when the narrative is right.

## CLI-CPU Secure Edition -- Positioning and Differentiation <a name="positioning"></a>

### Not a Competitor, but the Next Generation

TROPIC01 is an **excellent first-generation open secure element**, and OpenTitan is strong in its own datacenter RoT segment. These projects **pave the way** for CLI-CPU Secure Edition -- they prove that the market exists, is mature, and funds open alternatives.

**CLI-CPU Secure Edition does not compete against them.** It offers a **next-generation** approach based on a **different architecture**, addressing problems that the market **has not yet solved**:

| Aspect | TROPIC01 | OpenTitan | CLI-CPU Secure Edition |
|--------|----------|-----------|------------------------|
| **ISA** | Ibex RISC-V + SPECT | Ibex RISC-V | **CIL (ECMA-335)** |
| **Core count** | 1 + lock-step + SPECT | 1 + a few crypto modules | **4-16 Nano + 1-4 Rich + Crypto Actor** |
| **Isolation model** | One security domain, software applet isolation | One security domain | **N independent security domains, hardware shared-nothing** |
| **Programming language** | C (embedded) | C (embedded) | **C# (modern, type-safe)** |
| **Actor model** | no | no | **native** |
| **Capability-based security** | Limited | Limited | **Native** |
| **Multi-application support** | Sequential, software-based | Sequential | **Parallel, hardware-based** |
| **Post-quantum ready** | Planned | Research | **Native (programmable)** |
| **Developer ecosystem** | Embedded C community | Embedded C community | **~400,000 NuGet packages from .NET** |
| **Primary target market** | Hardware wallet, single-use SE | Datacenter RoT | **Multi-use, converged SE platform** |
| **Maturity** | **Production 2026 Q1** | **Production 2024** | **F0 spec 2026, expected production 2031-2032** |

### The Differentiating Argument

**On today's Secure Element market, one chip equals one security domain.** If a smartwatch needs a banking SE, an eSIM, an eID, FIDO2, a crypto wallet, and a TPM simultaneously, it requires **six separate chips**. This is **physically expensive, power-hungry, and complex**.

The CLI-CPU Secure Edition offers **multiple independent Secure Elements on a single chip**, with **hardware shared-nothing** isolation. Each Nano core is **an independent secure applet** that is **mathematically provably** unable to communicate with the others except through defined mailbox interfaces.

**This is a new category** that neither TROPIC01 (one security domain), nor OpenTitan (one security domain), nor the classic closed SEs (sequential applet model) offer.

### Concrete Example: Smartphone Multi-SE

A modern smartphone requires:
- Banking SE (Apple Pay / Google Pay)
- eSIM (cellular network identity)
- Passport / eID (national ID, mDL)
- FIDO2 / Passkey (web authentication)
- Crypto wallet (Bitcoin/Ethereum on-device)
- TPM (Windows/Android secure boot)
- Device identity (remote attestation)

**Today:** 7 Secure Element chips, or software-isolated applets on a single chip (using a software verifier, **vulnerably**).

**With TROPIC01:** one chip, one security domain, **software** applet isolation -- gains **auditability** but not **physical isolation**.

**With CLI-CPU Secure Edition:** one chip, **7 separate Nano cores**, each a full actor-based Secure Element, coordinated by a **Rich core** supervisor. If the banking core were ever compromised, the others are **architecturally unaffected** -- a physical, hardware guarantee, not a software hope.

**This is a real, unsolved market problem** that CLI-CPU Secure Edition **can solve**.

## Architectural Fit -- What We Have and What Is Missing <a name="architectural-fit"></a>

### What the Current CLI-CPU Design **Already Provides**

The `docs/architecture-hu.md`, `docs/security-hu.md`, and `docs/ISA-CIL-T0-hu.md` documents already supply the foundations on which the Secure Edition can build, with **minimal redesign**:

| Secure Element Requirement | CLI-CPU Status | Phase |
|---------------------------|----------------|-------|
| **Hardware memory safety** | included | F3 (Nano core) |
| **Type safety (isinst/castclass)** | included | F5 (Rich core) |
| **Control flow integrity** | included (stack-machine model) | F3 |
| **Shared-nothing isolation** | **included (multi-core)** | **F4** |
| **Non-speculative execution** | included | F3 |
| **Determinism** | included | F3 |
| **Small die size** | included (~8700 std cell / Nano core) | F3 |
| **Low power (event-driven)** | included | F3 |
| **Formally verifiable ISA** | included (48 opcodes) | F5 |
| **Auditable (open HDL)** | included | F3 |
| **Multi-application isolation** | **included (hardware)** | **F4** |
| **Immunity to Spectre/Meltdown/ROP/JOP** | included | F3-F5 |
| **Capability-based security (actor ref)** | included | F5 (Neuron OS) |
| **Supervision hierarchy (fault tolerance)** | included | F5 (Neuron OS) |

This is a **very strong starting point**. The current F0-F6 plan covers **~80%** of Secure Element requirements **without even explicitly targeting them**.

### What **Needs** to Be Added

The missing ~20% requires specific **Secure Element-specific** hardware components that the current plan does not call for, but which are **mandatory** for the Secure Edition.

## Required Additions <a name="required-additions"></a>

### 1. Crypto Actor -- a SPECT-Inspired Cryptographic Co-Processor

Following the TROPIC01 SPECT pattern, the CLI-CPU Secure Edition will include a **dedicated Crypto Actor**. This is a separate Nano core-like unit, **but with its own microcoded instructions** optimized for cryptographic workloads.

**Operating pattern:**

```
Main actor -> send({encrypt: plaintext, with: key_id}) -> Crypto Actor
Crypto Actor -> (runs SPECT-like microprogram)
Crypto Actor -> reply({ciphertext: ..., tag: ...})
```

**Supported algorithms (F6.5 plan):**

| Category | Algorithms | Estimate (Sky130 std cell) |
|----------|-----------|----------------------------|
| Asymmetric | Ed25519, X25519, P-256 ECDSA, P-384 ECDSA | ~15k |
| Hash | SHA-256, SHA-512, SHA-3 (Keccak) | ~4k |
| Symmetric | AES-128/256 (ECB, CBC, CTR, GCM, CCM) | ~3k |
| Lightweight AEAD | ChaCha20-Poly1305, ISAP | ~3k |
| Post-Quantum | **Kyber** (KEM), **Dilithium** (signing), **Falcon** (signing) | **~20k** |
| RSA | **NO** (deliberate decision, following the TROPIC01 pattern) | -- |
| **Total** | -- | **~45k std cell** |

**Built-in post-quantum algorithms** would be among the first on the market -- a concrete competitive advantage as mass deployment of NIST-standardized PQC algorithms (Kyber, Dilithium, Falcon, SPHINCS+) begins in 2026-2030.

### 2. True Random Number Generator (TRNG)

An entropy source for key generation. Mandatory for every SE certification.

**Design options:**
- **Ring oscillator jitter-based** -- simple, proven, but with documented attack surfaces
- **Metastable flip-flop based** -- more complex, but statically analyzable
- **Diode shot noise** -- analog, separate IP block

**Size**: ~1-2k std cell + SHA-based whitening

**Certification**: NIST SP 800-90A/B/C compliance, AIS 31 (BSI) PTG.2 or PTG.3 class.

**Lesson from TROPIC01**: the PUF + TRNG combination is powerful. Their RTL provides a concrete reference implementation.

### 3. PUF (Physically Unclonable Function)

A chip-unique physical "fingerprint" generated from manufacturing tolerances. No two chips will **ever** produce the same PUF value, even from the same wafer.

**Uses:**
- **Device identity** -- the chip's unique identifier
- **Root key derivation** -- the PUF output serves as the master key
- **Anti-cloning** -- an attacker cannot manufacture an identical chip
- **Key wrapping** -- stored keys are encrypted with the PUF-derived key

**Design options:**
- **SRAM PUF** -- the random power-on state of SRAM cells provides the PUF
- **Arbiter PUF** -- delay-chain comparison
- **Ring oscillator PUF** -- frequency difference

**Size**: ~500-1000 std cell + error correction (BCH or Reed-Solomon)

### 4. Write-Once Key Storage (OTP / eFuse)

**eFuse** or **antifuse** cells that can be written **once** and then only read. The root key and device identity are programmed here during manufacturing.

**Typical size in an SE**: 4-16 Kbit OTP

**Important**: OTP is **physically separated** from CPU memory, and only a dedicated **OTP reader port** can access it. The software layer **cannot** modify it, only read it (and even that is restricted).

### 5. Secure Boot + Remote Attestation

**Boot chain:**

```
1. Boot ROM (not flash, immutable) -- the very first code to run
2. Verifies the Rich core firmware signature
3. If OK, loads and launches it
4. If NOT OK, enters error state + zeroization
```

**Remote attestation:**
The chip can **send a message** to an external server (attestation server) that **proves**:
1. The chip is genuine (PUF-based chip identity)
2. The firmware hash matches expectations
3. The boot process completed correctly
4. The current SE configuration

This enables **remote trust establishment**: a cloud server can **confirm** that the communicating device is **genuinely** an authentic, audited CLI-CPU Secure Edition.

### 6. Tamper Detection

Learning from TROPIC01, the CLI-CPU Secure Edition **must include the same package**:

| Component | Function | Size |
|-----------|---------|------|
| **Electromagnetic pulse detector** | EM glitch protection | ~300 cell |
| **Voltage glitch detector** | supply voltage manipulation | ~400 cell |
| **Temperature sensor** | thermal attack protection | ~200 cell |
| **Laser detector** | optical fault injection | ~500 cell |
| **Active shield** | metal mesh, break detection | layout work |
| **Frequency monitor** | clock glitch detection | ~200 cell |
| **Total** | -- | **~1.6k std cell + layout** |

**Important**: the active shield is **layout-level** work, not RTL. This can only be **designed in practice at F6.5**; it cannot be imported as an "IP core."

When any detector fires, it triggers **immediate key zeroization**: all sensitive state, keys, and caches are **overwritten with zeros**, and the chip enters an **irreversible** error state. The tamper event is recorded in OTP, and the chip never boots normally again.

### 7. Side-Channel Countermeasures (DPA Protection)

**Differential Power Analysis (DPA)** attacks measure the chip's power consumption during cryptographic operations and use statistical methods to **extract the key**. This is **one of the hardest attacks to defend against**, and **every serious SE** addresses it.

**Countermeasures:**

1. **Masking** -- operations are performed on sensitive values XORed with a random mask, then unmasked at the end. The attacker sees "key + mask," not the key.
2. **Hiding** -- algorithms that run in constant time with constant power consumption. Every conditional branch is padded with dummy operations.
3. **Noise injection** -- random dummy cycles and dummy power consumption.
4. **Constant-time code** -- cryptographic primitives do not branch based on sensitive data.

**Impact**: ~15-30% slower crypto, ~10-20% larger area. **Essential** for EAL-5+ certification.

### Combined Hardware Budget for the Secure Edition

| Component | Std cell |
|-----------|----------|
| Base CLI-CPU (Nano + Rich, F6 plan) | ~200k |
| **Crypto Actor** (AES, SHA, ECC, PQC, SPECT-inspired) | ~45k |
| **TRNG** | ~2k |
| **PUF** + error correction | ~1.5k |
| **OTP / eFuse** storage | ~3k (plus memory cells) |
| **Secure boot ROM** + attestation | ~3k |
| **Tamper detection** (6 components) | ~1.6k |
| **DPA countermeasures** (overhead on crypto) | ~8k |
| **Total for the Secure Edition** | **~264k std cell** |

This is **~32% larger** than the standard F6 Cognitive Fabric chip (~200k). It **fits** within a ChipIgnite OpenFrame MPW (~15 mm2 user area), or an IHP SG13G2 MPW (~15 mm2).

## Certification Path <a name="certification-path"></a>

### Common Criteria (ISO/IEC 15408)

**Common Criteria** is the international standard for certifying IT security products. There are seven EAL (Evaluation Assurance Level) levels: EAL-1 (lowest) through EAL-7 (highest). Secure Elements typically receive **EAL-5+** or **EAL-6+** certification.

| EAL Level | Evaluation Intensity | Typical Use |
|-----------|---------------------|-------------|
| EAL-1 | Functional testing | Basic products |
| EAL-2 | Structural testing | Commercial software |
| EAL-3 | Methodical testing + documented dev | Commercial hardware |
| EAL-4 | Documented dev process + code review | Server software |
| **EAL-4+** | Extended vulnerability analysis | **eSIM, FIDO** |
| **EAL-5+** | Semi-formal design + verification | **Banking card, eID, TPM** |
| **EAL-6+** | Semi-formal verified design | **High-security government, military** |
| EAL-7 | Formally verified design | **Critical weapons systems** |

**The CLI-CPU Secure Edition realistically targets EAL-5+**, and **EAL-6+** is achievable thanks to the formally verifiable ISA and simple microarchitecture.

### Certification Time and Cost

Common Criteria certification is **neither cheap nor fast**:

| Phase | Time | Cost |
|-------|------|------|
| Scheme selection (BSI/ANSSI/CCRA) | 1-2 months | $10-20k |
| Protection Profile selection / development | 3-6 months | $30-50k |
| Evaluation lab selection and contract | 1-2 months | $10-20k |
| Design and development to the EAL level | 12-24 months | **part of the project** |
| Evaluation (at the lab) | 6-12 months | **$300-800k** |
| Certification body review | 2-4 months | $20-40k |
| **Total** | **24-48 months** | **$400k-1M** |

This is **not a starter project budget**. EAL-5+ certification for the CLI-CPU Secure Edition should be initiated **after F6.5** (i.e. around 2031-2032), when real silicon and hands-on experience are available.

### Accredited Labs

- **BSI** (Germany) -- the most important European certification body
- **ANSSI** (France) -- the second most important
- **NIAP** (USA) -- tied to the US NSA
- **CCRA** -- mutual recognition arrangement

Tropic Square is currently moving toward **BSI** and **ANSSI**. The CLI-CPU Secure Edition can follow the same path, **learning from TROPIC01's experience**.

### Alternative / Complementary Certifications

| Certification | Focus | Relevant Market |
|---------------|-------|-----------------|
| **FIPS 140-3** | Cryptographic module | US government, IoT, finance |
| **EMVCo** | Banking card | Payment industry (Visa, Mastercard) |
| **GlobalPlatform** | Secure Element interoperability | SIM, eSIM, mobile payment |
| **GSMA eUICC** | eSIM standard | Mobile network industry |
| **FIDO Certified** | FIDO2 / Passkey authenticator | Web authentication |
| **TCG TPM 2.0** | Trusted Computing | Windows, server, IoT |

The CLI-CPU Secure Edition is **a product family** that will **obtain multiple certifications** for its various target markets.

## Product Family and Use Cases <a name="product-family"></a>

The CLI-CPU Secure Edition is **not a single chip** but **a platform** on which **multiple concrete products** can be built, each targeting a specific market segment. The **hardware base is shared**, but the **firmware and certifications** differ.

### 1. CLI-CPU Open Banking Card (EMV-Compatible)

**Goal**: the first open-source, EMV-compatible banking card platform.
**Certification**: EMVCo + EAL-5+
**Differentiator**: the user can **see** what runs on their card. A revolution in banking security.
**Competitors**: Thales, Idemia, Infineon banking chips (all closed).

### 2. CLI-CPU Open eSIM / iSIM

**Goal**: an open SIM/eSIM platform that the user can **flash themselves** onto their phone, independently choosing a carrier.
**Certification**: GSMA eUICC + EAL-4+
**Differentiator**: user sovereignty over mobile network identity.
**Competitors**: Thales eSIM (closed).

### 3. CLI-CPU Open eID / Passport

**Goal**: a national electronic identity card where citizens can **audit** the firmware.
**Certification**: ICAO 9303 + EAL-5+
**Differentiator**: **privacy-respecting eGovernment**. Particularly attractive in the EU, aligned with the EU Digital Identity Wallet initiative.
**Competitors**: Idemia, G+D eID chips.

### 4. CLI-CPU Open FIDO2 / Passkey Authenticator

**Goal**: a YubiKey alternative with auditable hardware token.
**Certification**: FIDO Certified Level 2 or 3 + EAL-4+
**Differentiator**: an **open, auditable, formally verifiable** FIDO authenticator. For the privacy-aware community.
**Competitors**: Yubico (closed), SoloKeys (partially open, but not SE-based).

### 5. CLI-CPU Open TPM 2.0

**Goal**: a Trusted Platform Module alternative for Windows/Linux/server/IoT systems.
**Certification**: TCG TPM 2.0 + EAL-4+
**Differentiator**: **replaces Intel PTT and AMD fTPM** for those who value auditability. A **Microsoft Pluton** alternative.
**Competitors**: Infineon SLB (TPM 2.0, closed), Nuvoton NPCT.

### 6. CLI-CPU Open Automotive V2X Secure Element

**Goal**: vehicle-to-everything communication + digital key + OTA update + remote attestation.
**Certification**: ISO 21434 + EAL-5+ + ASIL-D
**Differentiator**: a **formally verified, open-source** automotive SE. Particularly attractive to the EU automotive industry (CHIPS Act context).
**Competitors**: Infineon AURIX Secure Element, NXP A71.

### 7. CLI-CPU Open Medical Secure Element

**Goal**: secure element for implantable and wearable medical devices (pacemaker, insulin pump, CGM, neural implant).
**Certification**: IEC 62304 Class C + HIPAA + EAL-4+
**Differentiator**: **privacy-preserving medical AI inference, certifiable device identity, post-quantum ready crypto**. Today, most medical devices use **obsolete 8-bit MCUs** because new CPUs cannot be certified. CLI-CPU is modern and certifiable.
**Competitors**: Microchip, Infineon medical.

### 8. CLI-CPU Open Hardware Wallet

**Goal**: a Ledger and Trezor alternative, **from open source**.
**Certification**: EAL-5+ (optional)
**Differentiator**: TROPIC01 provides **one** security domain; CLI-CPU Secure Edition supports **multiple** cryptocurrencies simultaneously (Bitcoin + Ethereum + Solana + Monero + ...), each in a separate hardware security domain. **Multi-chain multi-wallet on a single chip**, securely.
**Competitors**: Trezor (on TROPIC01), Ledger (closed), GridPlus.

### 9. CLI-CPU Open Validator Node

**Goal**: blockchain validator (Ethereum PoS, Cardano, Solana, Cosmos) in a **deterministic, audited** manner.
**Certification**: EAL-5+ (optional)
**Differentiator**: **deterministic execution**, **formally verified consensus logic**, **shared-nothing** between every validator instance. Validator maintenance becomes drastically simpler.
**Competitors**: x86 servers + software validator nodes (highly vulnerable).

### 10. CLI-CPU Open AI Safety Watchdog

**Goal**: a small, formally verified CLI-CPU Secure Edition that **monitors** the decisions of a large AI model (LLM, agent) and performs an emergency shutdown if it detects anomalies.
**Certification**: IEC 61508 SIL-3/4 + EAL-5+
**Differentiator**: thanks to **formal verification**, the watchdog is **mathematically proven** to never fail. Serves as an AI safety layer for autonomous systems.
**Competitors**: none directly -- a new category.

## New Phase: F6.5 -- Secure Edition Parallel Tape-Out <a name="f6-5-phase"></a>

### Goal

The Secure Edition is **not a standalone project** but a **parallel tape-out variant** alongside the F6 eFabless ChipIgnite / IHP MPW submission. Same architecture (Nano + Rich core), **plus** the Secure Element-specific components.

### Timing

| Event | Estimated Date |
|-------|---------------|
| F6 Cognitive Fabric tape-out | 2029-2030 |
| F6.5 Secure Edition tape-out | **~6 months after F6** |
| F6.5 bring-up, testing | 2030 Q2 - Q4 |
| F6.5 Common Criteria evaluation start | 2030 Q4 |
| **EAL-5+ certification** | **2032-2033** |
| First commercial products | **2033-2034** |

This is **realistic** based on Tropic Square's ~6-year development timeframe (2019 to 2025 GA).

### New Design Work for F6.5 (Alongside Existing F5 and F6)

| Component | Engineering Estimate |
|-----------|---------------------|
| Crypto Actor (SPECT-inspired) | 6-12 engineer-months |
| TRNG (RO jitter + whitening) | 2-3 engineer-months |
| PUF (SRAM PUF + BCH error correction) | 2-4 engineer-months |
| OTP / eFuse interface | 1-2 engineer-months |
| Secure boot + attestation | 2-3 engineer-months |
| Tamper detection (6 components) | 4-6 engineer-months |
| Active shield layout | 2-3 engineer-months |
| DPA countermeasures | 3-5 engineer-months |
| Integration + verification | 4-6 engineer-months |
| **Total** | **~30-50 engineer-months** |

For a **3-5 person team**, this represents **~1-1.5 years of additional work** on top of F6. Not trivial, but **realistic**, especially if public IP from TROPIC01 and OpenTitan is reused.

### Costs

| Item | Estimated Cost |
|------|---------------|
| Additional engineering salaries (4 people x 1.5 years) | $0.5-1.2M |
| MPW tape-out (Sky130 ChipIgnite or IHP) | $10-50k |
| Evaluation lab contract (EAL-5+ target) | $400k-1M |
| Bring-up board (second variant) | $50-100k |
| **Total for F6.5** | **$1-2.5M** |

This is **significant**, but the Trustworthy Silicon track (even without Cognitive Fabric) **generates revenue on its own** if it finds a market.

## Partnerships and Community <a name="partnerships"></a>

### Potential Partners

#### Tropic Square (Not Now -- Best to Reach Out Around F5/F6)

**Collaboration opportunities:**
- **Shared IP library**: crypto accelerators, TRNG, tamper detection -- both projects benefit
- **Shared certification experience**: BSI, ANSSI processes -- they have already been through it
- **Joint EU lobbying**: Chips Act, Horizon Europe, EU sovereignty
- **Technical conferences**: joint talks at 35C3/FOSDEM/TROOPERS
- **Hardware partnership**: a TROPIC01 could even **serve alongside** a CLI-CPU chip as a root of trust

**Not now**, because:
- CLI-CPU is at the F0 spec stage; we are not yet at hardware
- We first need to demonstrate our own contribution (F1 simulator, F3 Tiny Tapeout)
- **Around F5** is the right time to initiate contact, when we have something demonstrable

#### OpenTitan Consortium

The OpenTitan consortium coordinated by lowRISC (Google, Nuvoton, Winbond, WD, etc.) is a **mature organization** working in a similar direction. **Partnership is possible**, especially around crypto IP and the certification process.

#### SatoshiLabs / Trezor

SatoshiLabs funds Tropic Square. If CLI-CPU Secure Edition offers a **multi-chain hardware wallet** variant (product type #10), then the **Trezor ecosystem** is a natural partner.

#### Academic Partners

| Institution | Relevant Research Group | Role |
|-------------|------------------------|------|
| **Cambridge (UK)** | CHERI, lowRISC | Capability security, open silicon |
| **ETH Zurich** | SafeBoard, ERIS lab | Secure systems, RISC-V |
| **KU Leuven (BE)** | COSIC | Crypto design, side-channel |
| **TU Graz (AT)** | IAIK | Crypto, hardware security |
| **CTU Prague (CZ)** | -- | Tropic Square connection |
| **BME / SZTAKI (HU)** | -- | Hungarian academic backing |

**Involving an academic partner** around F1-F4, in **formal verification** and **cryptographic accelerator design**, could **dramatically accelerate** the project's maturity.

### Community Building

The Secure Element community **differs** from the Cognitive Fabric / AI community:

- **Embedded security** professionals (BSI, ANSSI, Common Criteria experience)
- **Cryptography** researchers (IACR, post-quantum community)
- **Privacy activists** (EFF, Privacy International, Tor, Signal)
- **Crypto/Bitcoin community** (hardware wallet users)
- **Regulatory professionals** (EU Cybersecurity Act, eIDAS, NIS2)

**Conferences** worth attending:
- **35C3** (Chaos Communication Congress, Leipzig) -- privacy + hardware hacking
- **FOSDEM** (Brussels) -- open source foundation
- **TROOPERS** (Heidelberg) -- enterprise security
- **RSA Conference** (San Francisco) -- commercial SE market
- **Embedded World** (Nuremberg) -- where Tropic Square also presents

## Realistic Timeline <a name="timeline"></a>

The CLI-CPU Secure Edition is **not a quick project**. The Tropic Square lesson: **~6 years** from founding to full production, and **2-3 years** for Common Criteria certification.

| Year | Phase | Event |
|------|-------|-------|
| **2026** | F0 | Spec documents (including this one) |
| **2026-2027** | F1 | C# reference simulator |
| **2027** | F2 | RTL, single-core Nano core |
| **2027-2028** | F3 | Tiny Tapeout (Nano core + mailbox) -- first silicon |
| **2028** | F4 | FPGA 4x Nano multi-core (A7-Lite 200T) |
| **2028-2029** | F5 | Rich core + heterogeneous FPGA (A7-Lite 200T) |
| **2029-2030** | F6-FPGA | Heterogeneous Cognitive Fabric FPGA verification (3x A7-Lite 200T multi-board) |
| **2030** | F6-Silicon | ChipIgnite tape-out (only after F6-FPGA verification) |
| **2030-2031** | **F6.5** | **Secure Edition parallel tape-out** |
| **2030-2031** | -- | Bring-up, internal testing |
| **2031** | -- | Common Criteria evaluation begins |
| **2032-2033** | -- | **EAL-5+ certification obtained** |
| **2033** | -- | **First commercial Secure Edition products** |
| **2034-2035** | -- | Banking / eSIM / FIDO / TPM products on the market |
| **2035-2040** | -- | Market share acquisition, multi-use SE ecosystem |

This is **9-10 years** from the first spec to commercial Secure Edition products. **Not short-term**, but this is the **reality** for a Common Criteria-certified open chip, and it is realistic based on the Tropic Square example.

## Next Steps <a name="next-steps"></a>

The Secure Edition **does not rush** anything in the F1-F4 phases, because the Cognitive Fabric + Trustworthy Silicon tracks **naturally** carry the foundations. What needs to happen now:

### Short Term (Alongside the F1 Simulator, 2026-2027)

1. **Do not modify the existing F1-F4 plans** -- Cognitive Fabric and Trustworthy Silicon are **progressing naturally**
2. **Initiate contact** with a crypto research group (KU Leuven COSIC, TU Graz IAIK, or a Hungarian academic institution) so that we have an **academic sponsor** for the Secure Edition plan
3. **Monitor Tropic Square's progress** -- especially their BSI/ANSSI certification experiences and public IP library

### Medium Term (After F4 Multi-Core, 2028-2029)

4. **First formal Crypto Actor design** -- tied to F5, but already with the Secure Edition in mind
5. **Post-quantum crypto integration** -- Kyber/Dilithium/Falcon implementations are worth investigating now
6. **Reach out to Tropic Square** -- formal collaboration proposal around F5
7. **EU funding** (Horizon Europe, EU Chips Act) -- as part of the Trustworthy Silicon track, augmented with the Secure Edition

### Long Term (After F6, 2030+)

8. **F6.5 tape-out** -- 6 months after the Cognitive Fabric tape-out, in parallel
9. **Common Criteria evaluation** -- at a BSI or ANSSI accredited lab
10. **First products** -- likely a hardware wallet (Trezor-like) or FIDO2 authenticator (YubiKey-like), as these have the lowest barriers to entry

## Relationship to Other Documents

- [`docs/security-en.md`](security-en.md) -- Hardware security properties are documented here; the Secure Edition builds on them.
- [`docs/architecture-en.md`](architecture-en.md) -- The heterogeneous Nano + Rich multi-core architecture is also the foundation of the Secure Edition.
- [`docs/roadmap-en.md`](roadmap-en.md) -- The F6.5 phase will be recorded here.
- [`NeuronOS/docs/vision-en.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-en.md) -- The Neuron OS actor-based model **naturally** supports the multi-SE hardware isolation.

## Closing Thought

The Secure Element market is **enormous** (~$30-40B), **mature**, and **now opening** to open-source alternatives (TROPIC01 and OpenTitan prove it). The CLI-CPU Secure Edition **naturally** fits this space, because the base architecture (stack machine, shared-nothing, formally verifiable ISA, small die size, low power) is **exactly** what the SE market demands.

Our **differentiating position** is not that we are "yet another open SE" -- but that we offer **multi-core, actor-based, multiple independent security domains on a single chip**. This is a **new category** that neither TROPIC01, nor OpenTitan, nor the closed vendors offer. The future Secure Element will **require multiple security domains** (smartwatch/smartphone banking + eSIM + eID + FIDO + wallet + TPM), and the CLI-CPU Secure Edition is **ready** for this.

**Tropic Square has shown that the market is real and reachable.** The CLI-CPU Secure Edition **takes the next step**: the same auditability and openness, **on a generation-better architecture**.

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-14 | Initial versioned release |
