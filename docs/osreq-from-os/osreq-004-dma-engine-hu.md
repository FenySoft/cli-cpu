# OSREQ-004: DMA engine — nem-blokkoló persistence támogatás

> **Forrás:** [FenySoft/Symphact — osreq-004](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-004-dma-engine-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F5, F6

## OS-oldali igény

A Symphact persistence modellje (Event Sourcing) megköveteli, hogy actor állapotot **aszinkron, nem-blokkoló** módon lehessen kiírni külső tárolóra (FRAM/PSRAM). A core SRAM volatile → journal/snapshot kiíráshoz **DMA engine** kell.

## Javasolt megoldás

**Per-cluster DMA** — illeszkedik az OSREQ-001 fa topológiához:
- Cluster-enként egy DMA csatorna (`0xF0000900 + cluster_id×16`)
- SRC (SRAM) → DST (FRAM/PSRAM) aszinkron átvitel
- Interrupt on complete → core nem blokkolódik

## Nyitott kérdések a HW tervezőknek

1. Per-core vs per-cluster vs központi DMA — terület-budget?
2. DMA és mailbox azonos buszon → prioritás?
3. Scatter-gather (nem-összefüggő SRAM régiók)?
4. Max átvitel méret (Nano: 4 KB, Rich: 256 KB)?
5. Double buffering (ping-pong journal buffer)?

A részletes specifikáció a [Symphact forrásban](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-004-dma-engine-hu.md).
