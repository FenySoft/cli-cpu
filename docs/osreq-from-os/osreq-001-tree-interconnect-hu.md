# OSREQ-001: Fa topológiájú interconnect a core-ok között

> **Forrás:** [FenySoft/Symphact — osreq-001](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-001-tree-interconnect-hu.md)
>
> **Állapot:** Draft — hardveres visszajelzésre vár
>
> **Érintett CFPU fázis:** F4 (multi-core FPGA), F5 (heterogén), F6 (silicon)

## OS-oldali igény

A Symphact három alapvető struktúrája **fa hierachiát** feltételez:

1. **Supervisor tree** — az actor-ok szülő-gyerek hierarchiája (hibakezelés, lifecycle)
2. **Capability delegation** — a jogok a root supervisor-tól delegálódnak lefelé
3. **Memória modell** — nincs shared memory, minden core privát SRAM → a „megosztás" mailbox üzenetek, amelyek a fában felfelé-lefelé haladnak

Az interconnect topológiának ezt kell tükröznie.

## Jelenlegi állapot az architecture-hu.md-ben

Az `architecture-hu.md` jelenleg ezt írja:

> *"F4 szinten 4-portú keresztkötés, ami még nem „crossbar", csak egy egyszerű mux-köteg"*
>
> *"16 core felett a bus topológiát át kell nevezni mesh-re (2D grid)"*

A **mesh (2D grid)** javaslat nem illeszkedik a Symphact igényeihez. Az OS supervisor tree **fa**, nem grid. A mesh uniform routing-ot feltételez, de a CFPU kommunikációja **lokális és hierarchikus** (szomszédos core-ok, parent-child supervisor, cluster-en belüli spike-ok).

## Javasolt topológia: Hierarchikus fa (fat tree)

```
                         Chip
                          │
                   ┌──────┴──────┐
              Seal Core     Rich Core(s)        Level 0: privileged
                              │
               ┌──────────────┼──────────────┐
           Cluster 0      Cluster 1      Cluster K    Level 1: Nano cluster-ek
            /  |  \        /  |  \        /  |  \
          N0  N1  N2     N3  N4  N5     N6  N7  N8   Level 2: Nano core-ok
          │   │   │      │   │   │      │   │   │
         4KB 4KB 4KB    4KB 4KB 4KB    4KB 4KB 4KB   Level 3: privát SRAM
```

### Routing szintek

| Szint | Útvonal | Hop | Becsült latencia |
|-------|---------|-----|-----------------|
| Intra-cluster | N→N azonos cluster-ben | 1 | ~2-4 ciklus |
| Inter-cluster | N→N más cluster-ben | 2 | ~6-10 ciklus |
| N↔Rich | Supervisor kommunikáció | 1-2 | ~4-8 ciklus |
| Inter-chip | Chip→Chip | 3+ | ~50-200 ciklus |

### Hierarchikus címzés

```
Cél cím: [chip-id].[cluster-id].[core-offset]

Routing döntés (O(1), nem O(N)):
  if chip-id ≠ saját → inter-chip bridge
  if cluster-id ≠ saját → chip router → cél cluster router
  if cluster-id = saját → cluster router (lokális delivery)
```

### Javasolt MMIO regiszterek

| Cím | Név | R/W | Leírás |
|-----|-----|-----|--------|
| `0xF0000108` | `CLUSTER_COUNT` | R/O | Cluster-ek száma |
| `0xF000010C` | `CORES_PER_CLUSTER` | R/O | Core-ok száma cluster-enként |
| `0xF0000110` | `CLUSTER_ID` | R/O | Az adott core melyik cluster-ben van |
| `0xF0000114` | `CHIP_ID` | R/O | Multi-chip: melyik chip |

## Miért fa és miért nem mesh?

| Szempont | Mesh (2D grid) | Fa (fat tree) |
|----------|----------------|---------------|
| **SW illeszkedés** | Nem illeszkedik supervisor tree-hez | Természetesen illeszkedik |
| **Vezetékszám** | O(N) per core (4 szomszéd) | O(log N) aggregált |
| **Routing döntés** | XY routing, O(1) de uniform | Hierarchikus, O(1) és lokalitás-tudatos |
| **Kommunikációs minta** | Uniform — nem igaz a CFPU-ra | Lokális + hierarchikus — pont amit a supervisor tree csinál |
| **Skálázás 10k+ core-ra** | Lehetséges, de pazarló | Természetes — cluster hozzáadás O(1) |
| **Broadcast (supervisor restart)** | Flood-based, lassú | Fa-broadcast, hatékony |

## Nyitott kérdések a HW tervezőknek

1. **Cluster méret** — hány Nano core / cluster? (4? 8? 16?) Nagyobb cluster = több lokális kommunikáció, de drágább cluster router
2. **Fat tree szélesség** — a chip router felé milyen széles busz? Hány párhuzamos üzenet?
3. **Rich Core pozíciója** — fa gyökerénél (minden üzenet átmegy rajta?) vagy mellette (dedikált uplink)?
4. **Inter-chip link** — SPI? LVDS? Pin count? Max message size?
5. **Cluster router** — programozható vagy fix logikájú?
6. **Broadcast/multicast** — HW multicast support supervisor restart-hoz?

## Hatás az architecture-hu.md-re

Az „F6-ra skálázódás" szekció frissítendő: a **mesh** helyett **fat tree** topológia kell. Ez nem változtatja meg az egyes core-ok belső működését (pipeline, dekóder, SRAM), csak az interconnect struktúráját.

## Kereszthivatkozások

- Symphact forrás: [osreq-001-tree-interconnect-hu.md](https://github.com/FenySoft/Symphact/blob/main/docs/osreq-to-cfpu/osreq-001-tree-interconnect-hu.md)
- CLI-CPU architecture: `docs/architecture-hu.md` — „Skálázódás F6-ra" szekció
- Symphact boot sequence: `docs/boot-sequence-hu.md` — 8. lépés (Nano Core Wake)
- Symphact roadmap: M2.3 (Router), M2.4 (Memory Manager)
