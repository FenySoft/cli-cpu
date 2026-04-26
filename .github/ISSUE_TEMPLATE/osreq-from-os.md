---
name: "OS requirement from Symphact"
about: "An OS-level need surfaced by Symphact that should be considered in CFPU hardware design"
title: "[osreq] "
labels: ["osreq-from-os", "hw-codesign"]
assignees: []
---

## Summary

<!-- One sentence: what does Symphact need from the CFPU hardware? -->

## Source

<!-- Link the corresponding issue / document in FenySoft/Symphact. -->

- Symphact issue: #TODO
- Symphact osreq doc (if any): `docs/osreq-to-cfpu/...`

## Context

<!-- Where in Symphact did this requirement surface?
  - Which module/actor/test revealed it?
  - Was it a performance bottleneck, a correctness issue, or a design limitation? -->

## Current software workaround

<!-- How is Symphact handling this today without hardware support?
     Is the workaround acceptable, or is it blocking something? -->

## Proposed hardware behaviour

<!-- What should the CFPU provide?
  - New MMIO register?
  - Different mailbox depth?
  - Interrupt structure change?
  - New trap type?
  - New opcode?
  - Be concrete where possible. -->

## Measured impact (if applicable)

<!-- Numbers from the simulator:
  - Latency differences
  - Allocation patterns
  - Mailbox occupancy histograms
  - Context sizes -->

## Affected CFPU phase

<!-- Which phase would this land in?
  - [ ] F2 (RTL single Nano core)
  - [ ] F3 (Tiny Tapeout silicon)
  - [ ] F4 (multi-core FPGA)
  - [ ] F5 (Rich core + heterogeneous)
  - [ ] F6 (distributed multi-board / silicon)
  - [ ] Unclear -- needs discussion -->

## Design-phase risk

<!-- If we skip this requirement, what breaks later?
  - Silicon area cost?
  - ABI stability problem?
  - Perf cliff in Symphact workloads? -->

## Related CFPU docs

<!-- Link relevant CLI-CPU specs:
  - `docs/architecture-hu.md` / `-en.md`
  - `docs/ISA-CIL-T0-hu.md` / `-en.md`
  - `docs/security-hu.md` / `-en.md`
  - `docs/roadmap-hu.md` / `-en.md` -->
