# CFPU Core Család

> English version: [core-types-en.md](core-types-en.md)

> Version: 2.0

Ez a dokumentum a Cognitive Fabric Processing Unit (CFPU) **négy core típusát** specifikálja: az ISA különbségeket, a terület-hatást, az SRAM méretezést, a power domain-eket, a termékcsalád variánsokat és a piaci pozíciót. Az ML inference-re optimalizált MAC Slice (nem programozható compute egység) specifikációja a [CFPU-ML-Max](cfpu-ml-max-hu.md) dokumentumban található.

## Kettős specializáció

A CFPU core család **nem lineáris hierarchia** — két különböző irányba specializálódik a Nano alapból:

```
                Nano (CIL-T0)
               /             \
      Actor (+GC+Obj)    Seal (+Crypto)
         |
      Rich (+FPU)
```

**Balra:** az általános célú programozás irány — objektumok, GC, kivételkezelés, majd FPU.
**Jobbra:** a biztonsági irány — kriptográfiai primitívek (SHA-256, WOTS+, Merkle), kódhitelesítés, eFuse kezelés.

Ez a kettős specializáció a CFPU egyedi vonása: egyetlen más processzor-család sem kínálja mindkét irányt azonos interconnecten, azonos üzenetformátummal, azonos RTL-ből paraméterezve.

> Az ML inference-hez a CFPU-ML chip **MAC Slice**-okat használ — ezek nem programozható core-ok, hanem FSM-vezérelt compute egységek. Specifikáció: [CFPU-ML-Max](cfpu-ml-max-hu.md).

## A négy core típus

| Tulajdonság | **Nano** | **Actor** | **Rich** | **Seal** |
|------------|---------|----------|---------|---------|
| **ISA** | CIL-T0 (48 opkód, int32) | Teljes CIL (obj, GC, generikusok) | Teljes CIL + FPU opkódok | CIL-Seal (CIL-T0 subset + crypto) |
| **FPU** | Nincs | Nincs | IEEE-754 R4+R8, power-gated | Crypto HW (AES, ECC) |
| **GC + Objektum modell** | Nincs | **Van** (bump alloc, mark-sweep) | **Van** | Nincs |
| **Kivételkezelés** | Trap only | Teljes (throw/catch/finally) | Teljes | Trap only |
| **Crypto** | Nincs | Nincs | Nincs | **SHA-256, WOTS+, Merkle, eFuse, TRNG** |
| **Logika (7nm)** | 0,009 mm² | 0,018 mm² | 0,022 mm² | ~0,2 mm² |
| **SRAM tartomány** | 4–64 KB | 64–256 KB | 128–512 KB | ~32 KB (kulcs + hash) |
| **Power gating** | Per-core clock gating | Per-core clock gating | FPU külön domain | Wake-on-demand |
| **Darabszám/chip** | 100–32 000 | 10–17 000 | 10–8 250 | 1+ (átbocsátás, redundancia) |
| **Cél** | Spike, szenzor, egyszerű worker | Általános aktor, supervisor, ML koordinátor | FP-igényes számítás, .NET | Kódhitelesítés, boot, audit |

### Nano Core

A legkisebb végrehajtó egység — 48 CIL-T0 opkód, integer-only. Minimális méret → maximális core szám.

**Mikor:** SNN spike-ok, IoT szenzor aktorok, nagyszámú egyszerű worker pipeline.

### Actor Core

A „standard" CFPU mag — teljes CIL, GC, objektumok, kivételek, **FPU nélkül**. A CFPU-ML chipben az Actor Core végzi a nem-MAC műveleteket (LayerNorm, Softmax, Residual).

**Mikor:** Actor cluster, stream processing, supervisor, edge gateway, ML koordinátor.

### Rich Core

Actor Core + **IEEE-754 FPU** (power-gated). Ha a kód nem használ FP-t, az FPU alszik.

**Mikor:** Tudományos számítás, pénzügyi modell, általános .NET `float`/`double` alkalmazás.

### Seal Core

A chip **hitelesítő kapuőre** — nem számítási egység. Minden kód (boot, hot loading, migráció) AuthCode verifikáción megy át. Az L3 crossbar közepén helyezkedik el. A CFPU-ML chipben az IOD-n van.

**Mikor:** Minden CFPU chipben. A darabszám az átbocsátási igénytől és a redundancia követelményektől függ.

Skálázhatóság: ~30 000 core-ig szaturáció nélkül (boot 8K core: ~256 ms, runtime: <0,1%).

## Terület összehasonlítás

### Core méretek (7nm)

| Core típus | Logika | Optimális SRAM | **Core összesen** | Router variáns | Router terület | **Node összesen** | **Core szám (800 mm²)** |
|-----------|--------|---------------|------------------|:--------------:|---------------:|------------------:|------------------------:|
| Nano | 0,009 mm² | 4 KB | 0,014 mm² | Compact | 0,004 mm² | 0,025 mm² | **~32 000** |
| Actor | 0,018 mm² | 64 KB | 0,036 mm² | Compact | 0,004 mm² | 0,047 mm² | **~17 000** |
| Rich | 0,022 mm² | 256 KB | 0,083 mm² | Turbo | 0,007 mm² | 0,097 mm² | **~8 250** |
| Seal | 0,200 mm² | 32 KB | 0,210 mm² | — | — | 0,210 mm² | **1+** |

> A core-számok tartalmazzák az ajánlott L0 router variáns területét és az L1–L3 infrastruktúra per-core részét (~0,007 mm²). Az SRAM dominálja a core méretet, nem a logika.

## Power domain-ek

| Egység | Power state | Mikor alszik? | Wake trigger |
|--------|-----------|--------------|-------------|
| Bármely core | Per-core clock gating | Üres mailbox | Mailbox interrupt |
| Rich FPU | Külön power domain | Nincs FP művelet | FP opkód detektálása |
| Cluster (16 core) | Per-cluster power gating | Mind a 16 core alszik | Bármely core-nak érkező cella |
| Tile (L1 crossbar) | Per-tile power gating | Minden cluster alszik | Cella érkezés |
| Régió (L2 crossbar) | Per-régió power gating | Minden tile alszik | Cella érkezés |
| L3 crossbar | Power-gated | Nincs cross-régió forgalom | Cross-régió cella |
| Seal Core | Power-gated | Nincs kód betöltés | Kód-betöltési kérés |

## CFPU termékcsalád

| Variáns | Seal | Core-ok / egységek | Célpiac |
|---------|------|-------------------|---------|
| **CFPU-N** | Seal | Nano only | IoT, masszív SNN spike háló |
| **CFPU-A** | Seal | Actor only | Actor cluster, stream processing |
| **CFPU-R** | Seal | Rich only | Teljes .NET, FP-igényes |
| **CFPU-ML** | Seal | **MAC Slice + Actor** | ML inference — lásd [CFPU-ML-Max](cfpu-ml-max-hu.md) |
| **CFPU-H** | Seal | Actor + Nano | Heterogén supervisor+worker | 1S + 2 000A + ~24 000N |
| **CFPU-X** | Seal | Vegyes (bármely kombináció) | Alkalmazás-specifikus | Egyedi |

### CFPU-ML: az ML/SNN-re optimalizált chip

A CFPU-ML a legérdekesebb variáns ML/SNN szempontból:

A CFPU-ML chip nem programozható core-okból, hanem **MAC Slice**-okból (FSM-vezérelt compute egységek) + Actor Core-okból + Seal Core-ból áll. Részletes specifikáció: **[CFPU-ML-Max](cfpu-ml-max-hu.md)**.

## Tervezési megkülönböztetők

| Tulajdonság | Leírás |
|-------------|--------|
| Event-driven (0W idle) | A core-ok csak mailbox üzenetre ébrednek — nincs polling, nincs idle fogyasztás |
| .NET natív | C# / F# CIL-re fordítva, natívan végrehajtva — nincs driver stack, nincs CUDA |
| Nyílt forráskód | Teljes ISA, RTL (tervezett), toolchain és OS — auditálható, fork-olható |
| Seal Core | Hardveres kódhitelesítés — auditálható ML inference (orvosi, pénzügyi) |
| Csak on-chip SRAM | Nincs DRAM controller — determinisztikus latencia |

## Kapcsolódó dokumentumok

- [CFPU-ML-Max](cfpu-ml-max-hu.md) — ML inference accelerator: chiplet architektúra, MAC Slice, J/token összehasonlítás
- [Interconnect architektúra](interconnect-hu.md) — 4-szintű hierarchia, switching modell, router felépítés
- [Quench-RAM](quench-ram-hu.md) — per-blokk immutability, QRAM+hálózat szimbiózis
- [ISA-CIL-T0](ISA-CIL-T0-hu.md) — a Nano Core ISA alapja
- [Architektúra](architecture-hu.md) — a teljes CFPU áttekintés

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|------------|----------------------------------------------|
| 2.0 | 2026-04-20 | 4 core típus (Matrix Core → MAC Slice, külön dokumentumba: [CFPU-ML-Max](cfpu-ml-max-hu.md)). Kettős specializáció: Nano→Actor→Rich (programozás) + Nano→Seal (biztonság). Termékcsalád frissítve. |
| 1.0 | 2026-04-18 | Kezdeti verzió — 5 core típus, kettős specializáció, terület összehasonlítás, SRAM méretezés, power domain-ek, termékcsalád, piaci pozíció |
