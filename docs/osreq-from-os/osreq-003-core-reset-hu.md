# OSREQ-003: Core reset mechanizmus — supervisor restart támogatás

> **Forrás:** [FenySoft/Symphact — osreq-003](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-003-core-reset-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F4, F5, F6

## OS-oldali igény

A Symphact „let it crash" supervision modellje **gyakori core restart-ot** feltételez. Amikor egy actor hibát dob, a supervisor (Rich Core) újraindítja a hibás Nano core-t. Ehhez:

1. **Atomi SRAM clear** — a teljes core SRAM nullázása (stack + heap + locals)
2. **Mailbox FIFO flush** — pending üzenetek eldobása
3. **Core halt** — a core megáll, a scheduler dönt az újraindításról

## Miért kell HW support?

- A Rich Core **nem látja** a Nano core SRAM-ját (shared-nothing!) → SW-only reset lehetetlen
- Ha a core crash-elt, **nem bízhatunk meg benne** → self-reset nem opció
- A restart **gyakori, normális művelet** → ~100 ciklus target (nem ~2000)

## Javasolt megoldás

`CORE_RESET[n]` write-only regiszter (`0xF0000500 + core_id×4`): a Rich Core `1`-et ír → HW atomilag reseteli a target core-t.

## Nyitott kérdések a HW tervezőknek

1. Partial reset (csak heap) kell-e, vagy mindig full wipe?
2. Mailbox drain (supervisor kiolvashatja) vs flush (eldobás)?
3. Determinisztikus-e a reset idő? (real-time use case)
4. Cascade reset: cluster supervisor reset → egész cluster?
5. Kell-e `CORE_RESET_REASON` regiszter (trap code, watchdog, explicit)?

A részletes specifikáció a [Symphact forrásban](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-003-core-reset-hu.md).
