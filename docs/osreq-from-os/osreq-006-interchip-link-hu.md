# OSREQ-006: Inter-chip link protokoll — elosztott fabric kommunikáció

> **Forrás:** [FenySoft/NeuronOS — osreq-006](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-006-interchip-link-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F6, F7

## OS-oldali igény

A Neuron OS location transparency megköveteli, hogy `TActorRef` **ne árulja el**, hogy a cél actor lokális vagy más chip-en van. A `Send(ref, msg)` hívásnak transzparensen kell működnie chip-határokon át.

## Javasolt megoldás

Hierarchikus routing (OSREQ-001 fa topológia kiterjesztése multi-chip szintre):

```
Send(ref, msg):
  if ref.ChipId = saját → intra-chip routing
  if ref.ChipId ≠ saját → inter-chip bridge → serialize → link → célchip deserialize → dst mailbox
```

Üzenet formátum: `[src_chip:8][dst_chip:8][dst_cluster:8][dst_core:16][msg_len:16][payload][CRC-16]`

## Nyitott kérdések a HW tervezőknek

1. Link típus: SPI, LVDS, custom? (architecture doc: „Mailbox bridge, 4 pin")
2. Max message méret: fix (64 byte) vagy változó? Fragmentáció?
3. Multi-chip topológia: daisy chain, csillag, fa?
4. Link sebesség: target Mbps? Latencia target (<10 µs)?
5. Hot plug: runtime chip hozzáadás/eltávolítás?
6. Encryption: inter-chip üzenetek titkosítottak?

A részletes specifikáció a [NeuronOS forrásban](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-006-interchip-link-hu.md).
