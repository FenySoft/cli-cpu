# OSREQ-006: Inter-chip link protocol — distributed fabric communication

> **Source:** [FenySoft/Symphact — osreq-006](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-006-interchip-link-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F6, F7

## OS-side requirement

Symphact location transparency requires that `TActorRef` **does not reveal** whether the target actor is local or on another chip. The `Send(ref, msg)` call must work transparently across chip boundaries.

## Proposed solution

Hierarchical routing (OSREQ-001 tree topology extended to multi-chip level):

```
Send(ref, msg):
  if ref.ChipId = own → intra-chip routing
  if ref.ChipId ≠ own → inter-chip bridge → serialize → link → target chip deserialize → dst mailbox
```

Message format: `[src_chip:8][dst_chip:8][dst_cluster:8][dst_core:16][msg_len:16][payload][CRC-16]`

## Open questions for HW designers

1. Link type: SPI, LVDS, custom? (architecture doc: "Mailbox bridge, 4 pin")
2. Max message size: fixed (64 byte) or variable? Fragmentation?
3. Multi-chip topology: daisy chain, star, tree?
4. Link speed: target Mbps? Latency target (<10 us)?
5. Hot plug: runtime chip addition/removal?
6. Encryption: are inter-chip messages encrypted?

The detailed specification is in the [Symphact source](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-006-interchip-link-en.md).
