# OSREQ-004: DMA engine — non-blocking persistence support

> **Source:** [FenySoft/NeuronOS — osreq-004](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-004-dma-engine-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F5, F6

## OS-side requirement

The Neuron OS persistence model (Event Sourcing) requires that actor state can be written to external storage (FRAM/PSRAM) in an **asynchronous, non-blocking** manner. Core SRAM is volatile → a **DMA engine** is needed for journal/snapshot writes.

## Proposed solution

**Per-cluster DMA** — aligned with the OSREQ-001 tree topology:
- One DMA channel per cluster (`0xF0000900 + cluster_id×16`)
- SRC (SRAM) → DST (FRAM/PSRAM) asynchronous transfer
- Interrupt on complete → core is not blocked

## Open questions for HW designers

1. Per-core vs per-cluster vs centralized DMA — area budget?
2. DMA and mailbox on the same bus → priority?
3. Scatter-gather (non-contiguous SRAM regions)?
4. Max transfer size (Nano: 4 KB, Rich: 256 KB)?
5. Double buffering (ping-pong journal buffer)?

The detailed specification is in the [NeuronOS source](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-004-dma-engine-en.md).
