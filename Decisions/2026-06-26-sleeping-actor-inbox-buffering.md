---
type: decision
status: proposed
date: 2026-06-26
deciders: Hocza József Szabolcs
---

# ADR: Sleeping Actor Inbox Multi-Cell Message Buffering

**Issue:** `architecture-hu.md` Actor Scheduling Pipeline section describes **single-cell message handling only** — a sleeping actor's inbox behavior when multiple cells are enqueued (pre-wake, during wake, or post-timeout) is **unspecified**.

Concrete gaps:
1. **Multi-cell arrival during sleep:** Does a cell arriving to a sleeping actor trigger immediate wake, or batch-wait until a timeout?
2. **Inbox capacity:** Is the per-core mailbox FIFO single-entry, or N-entry depth?
3. **Stale-wake mitigation:** What prevents a wake interrupt from re-triggering if the CPU core ignores it?

**Decision:**

**Per-core mailbox FIFO = 4-entry depth (dual-ported SRAM); sleeping actor wakes on first cell arrival; subsequent cells queue.**

**Rationale:**
1. **Fairness:** A single-entry mailbox starves fast producers — F4 multi-core demos require buffering.
2. **Neuromorphic precedent:** Spiking neural networks (F4 LIF neuron demo) emit bursts of spikes; a 1-entry FIFO causes artificial stalling.
3. **Area:** 4×144-bit FIFO ≈ 0.0002 mm² (negligible vs core size).
4. **Timeout:** Edge-triggered wake (on *new* mail arrival) prevents edge-stalling; hardware-driven vs interrupt-driven is orthogonal.

**Specifics:**
- Mailbox FIFO: 4 entries × 144 bits (current cell format).
- Wake interrupt: Edge-triggered (asserted on non-empty transition).
- Sleeping actor CSR: `r_mailbox_empty` read-only, cleared on dequeue.
- Scheduler: On wake, actor resumes at inbox-check instruction (no context loss).

**Action items:**
- [ ] Extend `architecture-hu.md` Actor Scheduling Pipeline: Add FIFO depth, stale-wake prevention, timeout interaction.
- [ ] Mailbox RTL spec: Update `hw/rtl/cilcpu_mailbox.v` with 4-entry FIFO (currently single-entry placeholder).
- [ ] F4 test: Ping-pong and burst-message scenarios to validate buffering.

**F-phase:** F3 UART-only (no inter-core); F4 first validação with multi-core mailbox.

---

**Related:** [[project_interconnect_decision]], [[reference_onchip_interconnect]]
