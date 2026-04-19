# OSREQ-002: MMIO memória térkép — OS↔HW regiszter interfész

> **Forrás:** [FenySoft/NeuronOS — osreq-002](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-002-mmio-memory-map-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F4, F5, F6

## OS-oldali igény

A Neuron OS boot szekvenciája konkrét MMIO regisztereket definiál a HW↔SW interfészhez. Ezek a boot, a core felderítés, a mailbox kezelés és az interrupt vezérlés alapjai.

## Javasolt MMIO térkép összefoglaló

```
0xF0000100  Core felderítés         (6 reg: Nano/Rich count, cluster info, chip ID)
0xF0000200  Mailbox base address    (1 reg)
0xF0000300  Per-core mailbox enable (N reg, core_id×4 offset)
0xF0000400  Per-core status         (N reg: Sleeping/Running/Error/Reset)
0xF0000600  Interrupt controller    (3 vektor: mailbox, watchdog, trap)
0xF0000800  Mailbox address table   (N reg: core_id → FIFO fizikai cím)
0xF0001000  QSPI/OPI Flash ctrl     (4 reg: config, addr, size, data)
0xF0002000  Seal Core interfész     (5 reg: eFuse hash, status, signal, QRAM base/size)
```

## Hatás az architecture-hu.md-re

A jelenlegi architecture doc a memória térképet magas szinten írja le. Ez az OSREQ **konkrét címeket és szemantikákat** definiál — ezeket az RTL-ben implementálni kell, vagy alternatív elrendezést javasolni.

## Nyitott kérdések a HW tervezőknek

1. A `0xF0000000–0xF000FFFF` tartomány elfogadható-e MMIO-nak?
2. Regiszter szélesség: mindenhol 32-bit, vagy van ahol 8/16 bit elegendő?
3. `SEAL_CORE_SIGNAL` polling-gal vagy interrupt-tal olvasandó?
4. Max core szám: a `core_id×4` offset skálázhatósága (10k core → ~40 KB MMIO tér)
5. QSPI vs OPI: az F6 OPI-ra vált — a regiszterek módosítandók?

A részletes regiszter-specifikáció a [NeuronOS forrásban](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-002-mmio-memory-map-hu.md).
