# Symphact

> **📦 The Symphact vision document has moved to its own repository.**
>
> **New location:** [`FenySoft/Symphact/docs/vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md)

> Magyar verzió: [symphact-hu.md](symphact-hu.md)

> Version: 2.0 (2026-04-17 — stub, redirect only)

## What is this?

**Symphact** is the actor-based operating system for the **Cognitive Fabric Processing Unit (CFPU)**. Previously the entire vision document (~1000 lines) lived in this repository as `docs/symphact-en.md`, but the Symphact implementation has moved to its own repo ([`FenySoft/Symphact`](https://github.com/FenySoft/Symphact)) — and the **vision has moved along with it**.

This file remains only so old internal and external links don't break.

## Where is the content now?

| Former reference | New location |
|------------------|--------------|
| Full vision, philosophy, design principles | [`vision-en.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md) |
| Capability-based security (lines 377-413) | [`vision-en.md#capability-based-security`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#capability-based-security) |
| The concept of a capability (lines 388-398) | [`vision-en.md#the-concept-of-a-capability`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#the-concept-of-a-capability) |
| Per-core private GC (lines 366-369) | [`vision-en.md#per-core-private-gc`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#per-core-private-gc) |
| Kernel actors (line 244, `hot_code_loader`) | [`vision-en.md#kernel-actors-root-level`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#kernel-actors-root-level) |
| Actor `Start` (line 278, cooperative multitasking) | [`vision-en.md#2-start`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#2-start) |
| Starting a new actor dynamically (line 434) | [`vision-en.md#starting-a-new-actor-dynamically`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#starting-a-new-actor-dynamically) |
| F4 multi-core scheduler + router (lines 617-624) | [`vision-en.md#f4----multi-core-scheduler--router`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#f4----multi-core-scheduler--router) |
| "Not a monolithic kernel" decision (line 731) | [`vision-en.md#2-not-a-monolithic-kernel----instead-an-actor-hierarchy`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-en.md#2-not-a-monolithic-kernel----instead-an-actor-hierarchy) |

## Why a separate repo?

Three reasons:

1. **Different developer audience** — a .NET developer shouldn't need to read Verilog, cocotb or Yosys scripts to contribute to an actor runtime.
2. **Independent lifecycle** — Symphact runs on any CIL host today; it is not blocked on silicon.
3. **Clean licenses** — Apache-2.0 (Symphact) fits the .NET ecosystem; CERN-OHL-S (CLI-CPU) fits hardware designs.

## OS → HW feedback loop

If an OS requirement surfaces during Symphact development (`osreq`), it is tracked at [`FenySoft/Symphact/docs/osreq-to-cfpu/`](https://github.com/FenySoft/Symphact/tree/main/docs/osreq-to-cfpu), and mirrored on the CLI-CPU side as issues labeled `osreq-from-os`.
