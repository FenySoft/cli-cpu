# OSREQ-003: Core reset mechanism — supervisor restart support

> **Source:** [FenySoft/NeuronOS — osreq-003](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-003-core-reset-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F4, F5, F6

## OS-side requirement

The Neuron OS "let it crash" supervision model assumes **frequent core restarts**. When an actor throws an error, the supervisor (Rich Core) restarts the faulty Nano core. This requires:

1. **Atomic SRAM clear** — zeroing the entire core SRAM (stack + heap + locals)
2. **Mailbox FIFO flush** — discarding pending messages
3. **Core halt** — the core stops, the scheduler decides on restart

## Why is HW support needed?

- The Rich Core **cannot see** Nano core SRAM (shared-nothing!) → SW-only reset is impossible
- If the core has crashed, **it cannot be trusted** → self-reset is not an option
- Restart is a **frequent, normal operation** → ~100 cycle target (not ~2000)

## Proposed solution

`CORE_RESET[n]` write-only register (`0xF0000500 + core_id×4`): the Rich Core writes `1` → HW atomically resets the target core.

## Open questions for HW designers

1. Is partial reset (heap only) needed, or always full wipe?
2. Mailbox drain (supervisor can read out) vs flush (discard)?
3. Is the reset time deterministic? (real-time use case)
4. Cascade reset: cluster supervisor reset → entire cluster?
5. Is a `CORE_RESET_REASON` register needed (trap code, watchdog, explicit)?

The detailed specification is in the [NeuronOS source](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-003-core-reset-en.md).
