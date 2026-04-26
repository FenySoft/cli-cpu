# CFPU Belső Busz Méretezés

> English version: [internal-bus-en.md](internal-bus-en.md)

> Version: 1.0

> **⚠️ Vízió-szintű dokumentum.** Az itt szereplő busz-szélesség, area- és power-becslések irodalmi adatokból (TSMC 5nm SRAM macro datasheet, AMD Zen, Apple M, NVIDIA H100 publikus paraméterek) extrapolált munkahipotézisek. A pontos értékek csak F2.7 FPGA bring-up és F6 szilícium után validálhatók. A dokumentum célja a tervezési irányt és a döntés-trail-t rögzíteni, nem a végleges paramétereket.

## Miért fontos a belső busz szélessége

A CFPU magokon belüli két leglassabb adatmozgás:

1. **Stack/lokál ↔ reg file** (egy mag pipeline-ján belül) — egy `add` művelet ehhez 3 reg-port hozzáférést kíván egy ciklusban
2. **Aktor-context ↔ SRAM** (warm-context cache spill/fill) — egy aktorváltáskor a teljes register-frame mozgatása

A `microarch-philosophy-hu.md` döntés szerint a CFPU minden core in-order, statikus ILP-vel. Ebben a modellben a **busz-szélesség közvetlenül határozza meg**, hány ciklus alatt cserél a mag aktort, és milyen multi-issue ráta megengedhető — mert OoO és scoreboard nem segít a port-bottleneck-en.

## Az alap dilemma — port-szám, nem latency

Egyciklusú on-chip SRAM latency-je 1–2 ciklus, ami **közel regiszter-szintű**. A probléma nem a sebesség, hanem a port-szám:

| Tárolási forma | Port konfiguráció | `add` művelet 1 ciklus alatt |
|---|---|---|
| Egy-portos SRAM (1R1W) | 1 read + 1 write/cycle | **NEM** — 2 read + 1 write kell |
| Két-portos SRAM (2R1W) | 2 read + 1 write/cycle | Igen |
| Multi-portos reg file (3R2W) | 3 read + 2 write/cycle | Igen, sőt 2-issue is fér |

Multi-portos SRAM ára:
- 1R1W → 2R1W: ~1,8× area
- 2R1W → 3R1W: további ~1,7× area (összesen ~3×)
- 3R1W → 3R2W: további ~1,3× (összesen ~4×)

Egy 32 KB Rich core SRAM macro 5nm-en ~0,005 mm² 1R1W-vel; 3R2W-vel ~0,02 mm². A reg file (32×32-bit = 128 byte) viszont 3R2W-ben triviális (~0,001 mm²).

**Konzekvencia**: a hot path tartalmát (TOS, lokálok) reg file-ban kell tartani; SRAM csak a passzív kontextusoknak.

## Egy aktor-context mérete

A `core-types-hu.md` szerint a Rich core teljes CIL-t futtat (objektumok, GC, kivételek). A „context" itt a végrehajtó-állapot, nem a teljes heap:

| Komponens | Méret |
|---|---|
| Register stack (max stack + lokálok) | 16–32 × 32-bit = 512–1024 bit |
| PC, SP, flags | ~64–96 bit |
| Aktor-state (mailbox-pointer, prioritás, supervisor link) | ~96–128 bit |
| **Összesen** | **~672–1248 bit, kerekítve 1024 bit** |

Egy aktor-context tehát **kb. 1 Kb** — ezt kell mozgatni egy warm-context cache miss-nél.

## Cycle-szám busz-szélesség függvényében

Egy 1024-bit-es context move teljes ciklusszáma a belső busz szélességének függvényében:

| Belső busz | Context move | Spill+fill párhuzamosan |
|---|---|---|
| 32-bit | 32 ciklus | 64 ciklus |
| 64-bit | 16 ciklus | 32 ciklus |
| 128-bit | 8 ciklus | 16 ciklus |
| **256-bit** | **4 ciklus** | **8 ciklus** (jó kompromisszum kis core-ra) |
| **512-bit** | **2 ciklus** | **4 ciklus** (jó kompromisszum Rich-re) |
| **1024-bit** | **1 ciklus** | **2 ciklus** (csak ML core-ra szükséges) |

A **64-cycle stall** (amit a korábbi elemzések feltételeztek 32-bites busszal) **256+ bittel néhány ciklusra zsugorodik**. A warm-context cache koncepció ettől válik életképessé: a háttér prefetch hint-tel a stall **0 cycle-re** is csökkenthető a hot path-on.

## HW költés — area és power

Becslések 5nm node-on, 1 mm-es busz-hossz:

| Réteg | 32-bit | 256-bit | 512-bit | 1024-bit |
|---|---|---|---|---|
| Wire trace | ~32 | 256 | 512 | 1024 |
| Metal layer felhasználás | M3–M4 | M3–M5 | M4–M6 | M4–M7 + tile-routing |
| Repeater cell-ek (500 µm-enként) | ~64/mm | ~512/mm | ~1K/mm | ~2K/mm |
| SRAM macro port szélesség | 32-bit | 256-bit (8 bank × 32) | 512-bit (8 bank × 64) | 1024-bit (16 bank × 64) |
| Dinamikus power (1 GHz, 50% activity) | ~0,3 mW | ~2,5 mW | ~5 mW | ~10 mW |
| Reg file area-növekmény (relatív) | 1× | ~1,3× | ~1,8× | ~2,8× |

**Kritikus küszöbök:**

- **256-bit** beleilleszthető egy egyszerű tile-routing-ba 5nm node-on, ~5–7% area-overhead a tile szintjén
- **512-bit** erőltetett tile-en belül, ideális egy Rich core back-end buszának
- **1024-bit** tile-en belül drága; itt érdemes 4-bank × 256-bit lokális + 1024-bit logikai látvánnyal megoldani (HBM-stílus)

## Iparági referenciák

| Chip / blokk | Belső busz | Megjegyzés |
|---|---|---|
| AMD Zen 4 — L1↔reg path | 512-bit | OoO mag, multi-issue háttér |
| Apple M4 P-core — L1↔reg | 256-bit | OoO mag |
| NVIDIA H100 SM — reg file BW | ~8 Kbit/cycle aggregate | sok-warp parallel |
| Cerebras WSE local fabric | 256-bit | sok kis core |
| Tenstorrent Tensix NoC | 1024-bit | tile-load alapelvárás |
| HBM3 die interface | 1024-bit | chiplet-skála |
| **CFPU Rich (cél)** | **512-bit** | sok mag, in-order |
| **CFPU Nano (cél)** | **256-bit** | minimum core, sok aktor |
| **CFPU ML/Matrix (cél)** | **1024-bit** | tile-load alapelvárás |

A 256–512 bit egy mai 5nm AI/many-core chip-en **ipari standard**, nem extravagáns.

## Választott méretezés — core típusonként

| Réteg | Busz szélesség | Indok |
|---|---|---|
| **Nano** belső reg ↔ SRAM | **256-bit** | 4–8 aktor warm-context, 4-cycle full move; minimális mag, sok aktor |
| **Actor core** | **256-bit** | Rich-hez közelít, ugyanaz az építőelem; kompatibilitás megtartva |
| **Rich core** belső back-end | **512-bit** | 32 reg + multi-issue + 64-bit ISA opcióhoz fejlécet ad |
| **ML/Matrix core (CFPU-ML MAC Slice)** | **1024-bit** | Tile-load alapelvárás, vektor-pipe (32 elem × 32-bit / cycle) |
| **Seal core** | **64-bit** | Auditálhatóság > sebesség, minimum logika |
| **Tile-szintű NoC** (4–8 mag között) | **256-bit** | Mailbox + context-spill osztott sávja |
| **Chip-szintű NoC** (tile ↔ tile) | **128-bit** | A `interconnect-hu.md` v2.4 jelenlegi értéke, marad |
| **DDR5 hub felé** | **128-bit** (2 channel × 64-bit) | DDR5 fizikai limit |

## Alternatívák — döntés-trail

### A) Egységes 32-bit belső busz mindenhol

- Egyszerű layout, kis area
- Context move 32 ciklus → warm-context cache koncepció elvérzik
- Multi-issue képtelenség (port-bottleneck)
- **Elvetve**: a sok-magos modell igazi nyeresége a context-cache-ben van, ezt megöli

### B) Egységes 256-bit mindenhol

- Mindenütt elég a Nano és Rich-hez
- ML core-on alulméretezett (4-cycle context vs 1-cycle ideál)
- Egyszerűbb tervezés
- **Részben átvéve**: ez a fallback, ha az ML-tile bus nem éri meg a 1024-bites bonyodalmat

### C) Heterogén busz (választott)

- Core-onkénti optimum
- Nano 256, Rich 512, ML 1024
- Bonyolultabb floorplan, de az architekturális heterogenitás (`core-types-hu.md`) amúgy is megköveteli
- **Választott**: konzisztens a core-család dizájnnal

### D) Egységes 1024-bit minden core-on

- Maximális teljesítmény
- Túlméretezett a Nano-ra (10× area-túllépés a kis magon)
- Power-budget kifeszítve idle ciklusokon
- **Elvetve**: pazarló, a Nano filozófia (kicsi és sok) ellen

## Trade-off — mit kell elfogadni

- **Power-hierarchy**: a wide bus toggle-power-e növekszik. Tile-szintű clock-gating kötelező, hogy az inaktív tile-ok ne fogyasszanak.
- **Layout-tightness**: 512+ bites busz a tile floorplan-ját kényszerpályára teszi. A core-okat „bus-spine-orientált" elrendezésben kell tervezni (Cerebras-stílus), nem szabadon.
- **DDR5-hub szűk keresztmetszet marad**: a 1024-bites tile-bus nem éri el a DDR-t. A memóriahozzáférés globális mintázata óvatos kell legyen — ezt a [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) capability grant + CAM ACL modell már kezeli.

## Validálási terv

1. **F1.5 (most)**: Csak elméleti döntés, busz szélesség az RTL paraméterezhető.
2. **F2.7 (FPGA, A7-Lite)**: A Rich core 1-magos prototípus 256-bit-es belső busszal megépíthető (FPGA BRAM erős). 512-bit FPGA-n nehéz, 1024-bit gyakorlatilag lehetetlen — itt simulation-ban validáljuk.
3. **F4 (multi-core RTL)**: cycle-accurate verifikáció Verilator-on, méretezett SRAM macro-kkal.
4. **F6 (silicon)**: tényleges layout, post-silicon power és perf validáció.

## Kapcsolódó dokumentumok

- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — TLP > ILP filozófia, ami a busz méretezés indoklása
- [`core-types-hu.md`](core-types-hu.md) — core típusok, ahol a busz méret core-onként eltér
- [`interconnect-hu.md`](interconnect-hu.md) — chip-szintű NoC busz (külön réteg)
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — memória hub szűk keresztmetszet
- [`cfpu-ml-max-hu.md`](cfpu-ml-max-hu.md) — ML core 1024-bit busz indoklása

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-25 | Kezdeti verzió — port-bottleneck elemzés, context move cycle-számolás 32–1024 bit között, választott méretezés core típusonként, döntés-trail (egységes 32 / egységes 256 / heterogén / egységes 1024) |
