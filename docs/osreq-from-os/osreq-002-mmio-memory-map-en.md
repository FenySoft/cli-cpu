# OSREQ-002: MMIO memory map — OS↔HW register interface

> **Source:** [FenySoft/Symphact — osreq-002](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-002-mmio-memory-map-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F4, F5, F6

## OS-side requirement

The Symphact boot sequence defines concrete MMIO registers for the HW↔SW interface. These are the foundation for boot, core discovery, mailbox management, and interrupt control.

## Proposed MMIO map summary

```
0xF0000100  Core discovery           (6 reg: Nano/Rich count, cluster info, chip ID)
0xF0000200  Mailbox base address     (1 reg)
0xF0000300  Per-core mailbox enable  (N reg, core_id×4 offset)
0xF0000400  Per-core status          (N reg: Sleeping/Running/Error/Reset)
0xF0000600  Interrupt controller     (3 vectors: mailbox, watchdog, trap)
0xF0000800  Mailbox address table    (N reg: core_id → FIFO physical address)
0xF0001000  QSPI/OPI Flash ctrl      (4 reg: config, addr, size, data)
0xF0002000  Seal Core interface      (5 reg: eFuse hash, status, signal, QRAM base/size)
```

## Impact on architecture docs

The current architecture doc describes the memory map at a high level. This OSREQ defines **concrete addresses and semantics** — these need to be implemented in RTL, or an alternative layout proposed.

## Open questions for HW designers

1. Is the `0xF0000000–0xF000FFFF` range acceptable for MMIO?
2. Register width: 32-bit everywhere, or is 8/16 bit sufficient in some cases?
3. `SEAL_CORE_SIGNAL` — read via polling or interrupt?
4. Max core count: scalability of the `core_id×4` offset (10k cores → ~40 KB MMIO space)
5. QSPI vs OPI: F6 switches to OPI — do the registers need modification?

The detailed register specification is in the [Symphact source](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-002-mmio-memory-map-en.md).
