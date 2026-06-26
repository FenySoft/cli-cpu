---
type: decision
status: proposed
date: 2026-06-26
deciders: Hocza József Szabolcs
---

# ADR: Crypto Hardware Placement — Per-Core vs Seal Core Only

**Issue:** `architecture-hu.md` sections describe per-core AES-128-CTR + CMAC engines for QRAM External Extension (F5+), but `core-types-hu.md` v2.1+ lists **Crypto: Nincs** for Actor, Rich, and only assigns crypto hardware to the Seal core (SHA-256, WOTS+, Merkle, eFuse, TRNG).

**Conflicting statements:**
- `architecture-hu.md` 1307–1312: "Per-core AES-128-CTR encrypt + CMAC tag" with area budget 0,004–0,006 mm² per core.
- `core-types-hu.md` 39, 42: Seal core has AES/ECC, Actor/Rich have **Nincs**.

**Decision:**

**Per-Core AES+CMAC for Actor and Rich cores (F5+) is CANONICAL.**

**Rationale:**
1. QRAM External Extension titkosítás réteg a per-core PSRAM extension-hez szükséges — Actor és Rich core-ok is kell, ha ki akarjuk használni a PSRAM-ot.
2. Nanofokú area cost (~17–26% Actor-nál) elfogadható, mivel SRAM már dominálja a chiplet területét.
3. Seal core egy separáció elkülönített infra-elem (PKI root, não-program), és orthogonal az Actor/Rich compute hardverre.

**Action items:**
- [ ] Update `core-types-hu.md` Table 1: Add `Crypto` row — "AES-128 (shared)" or per-core AES, alongside Seal-only SHA/WOTS/eFuse.
- [ ] Promote `architecture-hu.md` QRAM External Extension section → `specs/qram-encryption-{hu,en}.md` (spec-candidate).
- [ ] Document in `ddr5-architecture-hu.md` the per-core key derivation: `key = HMAC(core_id, PUF_secret)`.

**F-phase:** F5 RTL implementation can validate actual silicon cost.

---

**Related:** [[ddr5-capability-slot-v15]], [[reference_seal_touchpoints]]
