---
type: decision
status: proposed
date: 2026-06-26
deciders: Hocza József Szabolcs
---

# ADR: PUF (Physically Unclonable Function) Timeline — F5+ vs F6.5+

**Issue:** `architecture-hu.md` contains two conflicting statements:
- **Line 1309:** "Per-core kulcs (core ID + **PUF-ból származtatva**)" — implies PUF available **F5+**.
- **Line 388:** "F6.5 **Teljes Crypto Actor**" — lists PUF as part of F6.5 Secure Core deliverable.

**Decision:**

**PUF is infrastructure for CFPU Secure Boot + Key Derivation; available starting F5.** Not F6.5.

**Rationale:**
1. Per-core AES+CMAC (F5) for external PSRAM encryption requires per-core key derivation — PUF is the **entropy source**.
2. Seal core (F6.5) *uses* PUF outputs but doesn't introduce PUF silicon — PUF is a shared infrastructure (like clock, reset).
3. PUF silicon itself (ring oscillators, SRAM decay measurement, or poly-to-well variation) is modest (~0.0005–0.001 mm²), best co-integrated with early logic.

**Timeline:**
- **F5 RTL:** PUF simulation model (entropy generator mock).
- **F6 Silicon (IHP + Cerebras shuttle):** Real PUF silicon measured; key derivation validated.
- **F6.5+:** Seal core operations depend on proven PUF entropy.

**Action items:**
- [ ] Update `architecture-hu.md` 388: Clarify "F6.5 uses PUF, F5 integrates PUF infrastructure."
- [ ] Create `docs/puf-strategy-{hu,en}.md`: PUF design, entropy validation, per-core key derivation formula.
- [ ] Specs: `specs/puf-entropy-{hu,en}.md` after F6 silicon results.

---

**Related:** [[crypto-hardware-placement]], [[reference_seal_touchpoints]]
