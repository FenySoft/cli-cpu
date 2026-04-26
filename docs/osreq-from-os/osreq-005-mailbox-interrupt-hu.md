# OSREQ-005: Mailbox interrupt vs polling — core értesítési mechanizmus

> **Forrás:** [FenySoft/Symphact — osreq-005](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-005-mailbox-interrupt-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F4, F5, F6

## OS-oldali igény

A Symphact scheduler-nek tudnia kell, hogyan értesül egy core az új mailbox üzenetről. Ez az event-driven modell alapja.

## Javasolt megoldás

- **Nano core-ok:** tiszta HW interrupt (inbox not-empty → IRQ → wake)
- **Rich Core:** hybrid (interrupt coalescing — N üzenet vagy T ciklus → IRQ)

**Energiafogyasztási hatás:** 10k Nano core, 1% aktív → interrupt: ~20 mW vs polling: ~1 W (**50× különbség**).

## Nyitott kérdések a HW tervezőknek

1. IRQ vonal: per-core dedikált vagy cluster-szintű multiplexált?
2. Nested IRQ (mailbox IRQ handler alatt újabb üzenet)?
3. Wake latencia: target ≤5 ciklus (sleep → running)
4. IRQ prioritás: mailbox vs watchdog vs trap — fix vagy programozható?
5. Power domain: clock-gated, power-gated, vagy mindkettő?

A részletes specifikáció (energiaszámítással) a [Symphact forrásban](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-005-mailbox-interrupt-hu.md).
