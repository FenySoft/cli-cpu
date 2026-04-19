# OSREQ-005: Mailbox interrupt vs polling — core notification mechanism

> **Source:** [FenySoft/NeuronOS — osreq-005](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-005-mailbox-interrupt-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F4, F5, F6

## OS-side requirement

The Neuron OS scheduler needs to know how a core is notified of a new mailbox message. This is the foundation of the event-driven model.

## Proposed solution

- **Nano cores:** pure HW interrupt (inbox not-empty → IRQ → wake)
- **Rich Core:** hybrid (interrupt coalescing — N messages or T cycles → IRQ)

**Power consumption impact:** 10k Nano cores, 1% active → interrupt: ~20 mW vs polling: ~1 W (**50x difference**).

## Open questions for HW designers

1. IRQ line: per-core dedicated or cluster-level multiplexed?
2. Nested IRQ (another message arrives during mailbox IRQ handler)?
3. Wake latency: target ≤5 cycles (sleep → running)
4. IRQ priority: mailbox vs watchdog vs trap — fixed or programmable?
5. Power domain: clock-gated, power-gated, or both?

The detailed specification (with power calculations) is in the [NeuronOS source](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-005-mailbox-interrupt-en.md).
