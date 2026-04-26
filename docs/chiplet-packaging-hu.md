# CFPU Chiplet Packaging Architektúra

> English version: [chiplet-packaging-en.md](chiplet-packaging-en.md)

> Version: 1.0

Ez a dokumentum a Cognitive Fabric Processing Unit (CFPU) **chiplet packaging architektúráját** specifikálja: a chiplet típusokat, a multi-chiplet elrendezéseket, a technológiai skálázást és a Symphact-re gyakorolt hatást.

## Tervezési alapelvek

1. **Két chiplet típus** — egy központi (C) és egy compute (R) chiplet, azonos gyártósorról
2. **2-hatvány core számok** — minden szinten 2ⁿ (cluster, chiplet, package)
3. **Technológia-független skálázás** — a Symphact ugyanazt a kódot futtatja 4k és 32k core-on
4. **Yield optimalizálás** — chiplet méret a 90%+ yield tartományban

## Chiplet típusok

### R chiplet (Compute)

A compute chiplet kizárólag core-okat és a mesh hálózatot tartalmazza. Minden I/O a központi chiplet-en keresztül érhető el.

| Elem | Terület (5nm) |
|------|---------------|
| Rich Core node (core + SRAM + router + infra) | 2 048 × 0,071 mm² = 145,4 mm² |
| UCIe PHY (chiplet linkek) | ~10 mm² |
| ESD + I/O ring | ~10 mm² |
| PLL | ~0,5 mm² |
| **R chiplet összesen** | **~166 mm²** |
| Tartalék (SRAM növelésre / debug) | ~34 mm² |
| **Yield (~0,09 defect/cm²)** | **~93%** |

> A node méret a [core-types-hu.md](core-types-hu.md) Rich Core specifikációjából származik: 0,012 mm² logika + 0,042 mm² SRAM (256 KB) + 0,006 mm² Turbo router + ~0,011 mm² L1–L3 infra = 0,071 mm².

**Ami nincs az R chipletben:** Seal Core, DDR5 PHY, PCIe/CXL — ezek mind a C chipletben vannak.

### C chiplet (Központi)

A központi chiplet a chip „I/O hubja" — egyetlen példányban van jelen, és minden külső interfész rajta keresztül érhető el.

| Elem | Terület (5nm) | Miért itt |
|------|---------------|-----------|
| Seal Core (1–2 db) | ~0,25 mm² | Minden kódbetöltés átmegy rajta — központból 1 hoppal elér mindent |
| DDR5 PHY (2 csatorna) | ~16 mm² | Egyszer kell, nem chipletenkét |
| PCIe/CXL (host csatlakozás) | ~5 mm² | Egyetlen csatlakozás a host felé |
| UCIe (max 8 link) | ~20 mm² | Mind a 8 R chiplethez |
| DMA vezérlő | ~2 mm² | DDR5 ↔ chiplet SRAM adatmozgatás |
| ESD + I/O ring | ~15 mm² | Fizikai védelem |
| PLL-ek | ~0,5 mm² | Órajelek |
| Rich Core (maradék terület) | ami elfér | Compute kapacitás |
| **C chiplet összesen** | **~200 mm²** | |

## Multi-chiplet elrendezések

### Topológia: kombinált mesh + csillag

A chiplet-ek 3×3 rácsban helyezkednek el. A szomszédos chiplet-ek mesh linkkel, az átlós chiplet-ek a központi C chiplet-en keresztül kapcsolódnak. Ez **kombinált mesh + csillag** topológia:

```
  ┌───┐ ┌───┐ ┌───┐
  │ R │─│ R │─│ R │
  │   │ │   │ │   │
  └─┬─┘╲└─┬─┘╱└─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ C │─│ R │      C = központi chiplet
  │   │ │   │ │   │      R = compute chiplet
  └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐╱┌─┴─┐╲┌─┴─┐
  │ R │─│ R │─│ R │
  │   │ │   │ │   │
  └───┘ └───┘ └───┘

  ─ │ = mesh linkek (szomszédos chiplet-ek közt)
  ╲ ╱ = csillag linkek (C ↔ átlós chiplet-ek)
```

**Előnyök:**
- Bármely két chiplet közt **max 2 hop** (mesh + C-n át)
- Szomszédos chiplet-ek **1 hop** (direkt mesh link)
- Ha a C meghibásodik, a mesh linkek továbbra is működnek (degradált mód)

### Termékváltozatok

| Termék | Chiplet konfiguráció | Rich Core | Chip SRAM (256 KB/core) |
|--------|---------------------|-----------|------------------------|
| **CFPU-R1** | 1C + 1R | 2 048 | 512 MB |
| **CFPU-R2** | 1C + 2R | 4 096 | 1 GB |
| **CFPU-R4** | 1C + 4R | 8 192 | 2 GB |
| **CFPU-R8** | 1C + 8R | 16 384 | 4 GB |

> A termékváltozatok **ugyanabból a két chiplet designból** épülnek — a kombináció adja a termékcsaládot. A yield binning és a chiplet tesztelés (KGD — Known Good Die) biztosítja, hogy csak jó chiplet-ek kerüljenek a package-be.

### Interposer és package méret

| Konfiguráció | Interposer terület | Package típus |
|--------------|-------------------|---------------|
| 1C + 1R | ~400 mm² | Kis package |
| 1C + 2R | ~600 mm² | Közepes |
| 1C + 4R | ~1 000 mm² | CoWoS |
| 1C + 8R | ~2 000 mm² | CoWoS-L |

## DDR5 és külső memória

A core-ok SRAM-ja (128–512 KB / core) elegendő az aktorok kódjának és lokális állapotának. Nagy adathalmazokhoz (adatbázis, ML inference input) a C chipletben lévő DDR5 szolgál.

| DDR5 konfiguráció | Sávszélesség | Kapacitás |
|-------------------|-------------|-----------|
| 2 csatorna (alap) | ~100 GB/s | 16–64 GB |
| 4 csatorna (opcionális) | ~200 GB/s | 32–128 GB |

### Használati modell

A core nem lát DDR5-öt közvetlenül — a shared-nothing elv megmarad. Egy **DMA actor** a C chipletben kezeli a DDR5 hozzáférést, és mailbox üzeneteken keresztül szolgálja ki a core-ok kéréseit:

```
Core (R chiplet)                C chiplet
┌──────┐  mailbox kérés        ┌─────────┐        ┌──────┐
│ Core │──────────────────────►│ DMA     │◄──────►│ DDR5 │
│      │◄──────────────────────│ Actor   │        │      │
└──────┘  mailbox válasz       └─────────┘        └──────┘
```

## Linkek és sávszélesség

### Chipen belüli linkek (CMesh 16:1)

A cluster-en belül 16 core osztozik egy routeren. A routerek közti mesh link **256 bit széles, 500 MHz**:

| Paraméter | Érték |
|-----------|-------|
| Link szélesség | 256 bit |
| Órajel | 500 MHz |
| Egy link sávszélesség | 16 GB/s |
| Hop latencia (128B cella max) | ~4 ns |

> Az 500 MHz-es NoC órajel a fogyasztás-optimalizálás eredménye: ~1 GHz-hez képest ~68%-kal alacsonyabb dinamikus fogyasztás (f × V² skálázás), miközben a szélesebb link kompenzálja a sávszélességet.

### Chiplet határon (UCIe / CoWoS)

| Paraméter | Érték |
|-----------|-------|
| Sávszélesség | 200–500 GB/s |
| Latencia | ~2–5 ns |
| Távolság | ~1–5 mm (interposeren) |

### Multi-package (2D torus)

Több CFPU package egy rendszerben **2D torus** topológiával kapcsolható össze:

```
     ┌──────┐     ┌──────┐     ┌──────┐
 ◄══►│ CFPU │◄═══►│ CFPU │◄═══►│ CFPU │◄══►  (wrap)
     └──┬───┘     └──┬───┘     └──┬───┘
        │             │             │
     ┌──┴───┐     ┌──┴───┐     ┌──┴───┐
 ◄══►│ CFPU │◄═══►│ CFPU │◄═══►│ CFPU │◄══►  (wrap)
     └──────┘     └──────┘     └──────┘

  4 link / package (±X, ±Y), szélek körbeérnek
```

| Paraméter | Érték |
|-----------|-------|
| Sávszélesség | 25–100 GB/s |
| Latencia | ~50–100 ns |
| Médium | PCB trace / kábel |

### Sávszélesség összesítés

| Szint | Egy link | Latencia |
|-------|----------|----------|
| Chipen belül (mesh, 256-bit, 500 MHz) | 16 GB/s | ~4 ns/hop |
| Chiplet határ (UCIe) | 200–500 GB/s | ~2–5 ns |
| Package közt (±X/±Y, PCB) | 25–100 GB/s | ~50–100 ns |

## Technológiai skálázás

### SRAM fal

Az SRAM nem skálázódik a logikával azonos ütemben, mert a 6 tranzisztoros SRAM cella stabilitási korlátba ütközik kisebb technológiai node-okon:

| Node | Logika sűrűség (vs 5nm) | SRAM sűrűség (vs 5nm) |
|------|------------------------|----------------------|
| 5nm | 1× | 1× |
| 3nm | 1,7× | **1,1×** |
| 2nm (GAA) | 2,5× | **1,2×** |
| 1,4nm | 3,5× | **1,3×** |
| 1nm | 5× | **1,5×** (3D SRAM-mal) |

### Chiplet méret növekedés

A defect density csökken generációnként, ami nagyobb chiplet-eket tesz lehetővé 90%+ yield mellett:

| Időszak | Defect density | 90%+ yield chiplet méret |
|---------|---------------|-------------------------|
| 2025 (5nm) | ~0,09 /cm² | ~200 mm² |
| 2028 (3nm érett) | ~0,06 /cm² | ~300 mm² |
| 2030+ (2nm érett) | ~0,04 /cm² | ~400 mm² |
| 2033+ | ~0,02 /cm² | ~600 mm² |

### 3D SRAM

Ha az SRAM réteget a logika fölé stackelik (TSMC 3D SRAM, SoIC technológia), a core alapterülete csökken, mert az SRAM nem foglalja a chiplet síkbeli területét:

```
  2D (mai):                    3D SRAM (jövő):
  ┌──────┬──────┐             ┌──────────────┐ ← SRAM réteg
  │ Core │ SRAM │             │    SRAM      │
  └──────┴──────┘             ├──────────────┤
                              │    Core      │ ← logika réteg
                              └──────────────┘
```

### Kombinált hatás: core szám / chiplet (Nano Core, 64 KB SRAM)

A sűrűség javulás és a chiplet méret növekedés együttes hatása:

| Időszak | Technológia | Chiplet méret | Node méret | **Core / chiplet** |
|---------|-------------|---------------|------------|--------------------|
| 2025 | 5nm, 2D | 200 mm² | 0,0255 mm² | **4 096** (2¹²) |
| 2028 | 3nm, 2D | 300 mm² | 0,0183 mm² | **8 192** (2¹³) |
| 2030 | 2nm, 3D SRAM | 400 mm² | 0,015 mm² | **16 384** (2¹⁴) |
| 2033+ | 1,4nm, 3D SRAM | 600 mm² | 0,012 mm² | **32 768** (2¹⁵) |

> A core szám generációnként ~2×-re nő, a két tényező (sűrűség + chiplet méret) együttes hatásából.

## Symphact hatás

### Ami fix marad generációk közt

| Elem | Érték | Miért fix |
|------|-------|-----------|
| Core / cluster (CMesh 16:1) | 16 | Router port szám — HW döntés |
| Mailbox üzenet méret | 32 bit | CIL ISA része |
| Cella méret | max 80 byte (16B header + 64B payload) | Hálózati protokoll |
| Chiplet típusok | C + R | Funkcionális szétválasztás |

### Ami változik

| Elem | Hogyan nő |
|------|-----------|
| Cluster / chiplet | ~2× generációnként |
| SRAM / core | Nő (3D SRAM), de a core szám nem csökken |
| Chiplet / package | Hűtés technológia függő |

### Scheduler skálázás

A Symphact scheduler egyetlen paramétere: **hány cluster van a chipletben**. A boot folyamat:

1. Chiplet jelenti: „N cluster vagyok"
2. OS felépíti a scheduler fát
3. Ugyanaz a kód fut 4k és 32k core-on

A 2-hatvány lépcsők (4k → 8k → 16k → 32k / chiplet) biztosítják, hogy a scheduler fa mindig kiegyensúlyozott marad.

## Jövőbeli bővítési irányok

### 3D package (3×3×2)

Ha a hűtés technológia megengedi, a chiplet-ek két rétegben stackelhetők SoIC-vel:

```
  Felső (z=1)              Alsó (z=0)
  ┌───┐ ┌───┐ ┌───┐       ┌───┐ ┌───┐ ┌───┐
  │ R │─│ R │─│ R │       │ R │─│ R │─│ R │
  └─┬─┘ └─┬─┘ └─┬─┘       └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐       ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ R │─│ R │       │ R │─│ C │─│ R │
  └─┬─┘ └─┬─┘ └─┬─┘       └─┬─┘ └─┬─┘ └─┬─┘
  ┌─┴─┐ ┌─┴─┐ ┌─┴─┐       ┌─┴─┐ ┌─┴─┐ ┌─┴─┐
  │ R │─│ R │─│ R │       │ R │─│ R │─│ R │
  └───┘ └───┘ └───┘       └───┘ └───┘ └───┘

  17R + 1C = 18 chiplet, ~34 816 Rich Core
```

> A felső réteg hűtése kritikus — a Symphact scheduler-nek réteg-tudatosnak kell lennie (z=1 core-okat kevésbé terhelni). A 3×3×3 (27 chiplet) a középső réteg hűtési problémája miatt jelenleg nem reális.

## Kapcsolódó dokumentumok

- [Core típusok](core-types-hu.md) — Nano/Actor/Rich/Seal specifikáció, SRAM méretezés
- [Interconnect](interconnect-hu.md) — 4-szintű on-chip hálózat, switching modell, router variánsok
- [DDR5 architektúra](ddr5-architecture-hu.md) — DDR5 controller, capability grant, CAM ACL
- [CFPU-ML-Max](cfpu-ml-max-hu.md) — ML inference chiplet architektúra
- [Architektúra](architecture-hu.md) — teljes CFPU áttekintés

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-23 | Kezdeti verzió — C/R chiplet típusok, 1+1..8 termékváltozatok, kombinált mesh+csillag topológia, 256-bit 500 MHz link, DDR5 a C chipletben, technológiai skálázás (SRAM fal, 3D SRAM, chiplet méret növekedés), Symphact scheduler hatás |
