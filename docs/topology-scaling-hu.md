---
status: vision
---

# NoC Topológia Skálázás — általános elemzés

> English version: [topology-scaling-en.md](topology-scaling-en.md)

> Version: 1.2

> **⚠️ Vízió-szintű háttérdokumentum.** Az itt szereplő area-, BW- és latencia-becslések irodalmi adatokból (akadémiai NoC mérések, ARM CoreLink CMN, Synopsys/Cadence NoC IP, Adapteva Epiphany, Tenstorrent Tensix) extrapolált munkahipotézisek 5 nm node-ra. Általános háttéranyag a CFPU-tól elvonatkoztatva — a tényleges CFPU paraméterezést lásd [`interconnect-hu.md`](interconnect-hu.md) és [`internal-bus-hu.md`](internal-bus-hu.md).

## Cél

Ez a dokumentum azt vizsgálja, hogy egy on-chip hálózat **különböző topológiái** hogyan skálázódnak a core-szám (N) függvényében, ha az **üzenet egység fix 144 byte** (16 byte header + 128 byte payload). Három fő mérőszámot nézünk:

1. **Elfoglalt szilícium terület** (router logika + buffer SRAM + vezeték)
2. **Átbocsátóképesség** (per-core BW, aggregát BW, bisection BW)
3. **Latencia** (átmérő, átlagos hop, üzenet-szállítási idő)

A célszám: **konstans per-core BW lineáris area-költséggel**. Az alábbi táblázatok megmutatják, hogy ez melyik topológiával érhető el — és mikor.

## Üzenetegység és link feltevések

| Paraméter | Érték |
|-----------|-------|
| Üzenet méret | M = 144 byte = 1 152 bit |
| Header | 16 byte = 128 bit (1 flit a 128-bit linken) |
| Payload | 1–128 byte (max 8 flit) |
| Link szélesség (alapeset) | w = 128 bit |
| Link frekvencia | f = 1 GHz (5 nm jellemző) |
| Egy link BW | B = w · f = 128 Gb/s = **16 GB/s** |
| Üzenet hossza | F = ⌈M / (w/8)⌉ = **9 flit** (128-bit linken) |
| Wormhole router pipeline | 2 ciklus / hop |
| Üzenet/sec/link maximum | B / M = ~111 M msg/s |

A 128-bit link iparilag standard kis-közepes chipekhez (lásd `internal-bus-hu.md` v1.3 iparági referenciák).

## Topológia katalógus

### 1. Shared bus

```
[C0]──┬──[C1]──┬──[C2]──┬──[C3]──...──[Cn]
      │        │        │
   közös vezeték minden core között
```

Minden core egyetlen közös buszra csatlakozik. Csak egy üzenet utazik egyszerre. Bus arbiter dönti el, ki kap hozzáférést.

### 2. Ring (bidirekcionális)

```
   [C0]───[C1]───[C2]
    │              │
   [C7]          [C3]
    │              │
   [C6]───[C5]───[C4]
```

A core-ok körbe kapcsolódnak két irányban (CW és CCW). Egy core csak a két szomszédjával beszél közvetlenül; távoli core-okhoz hop-ok kellenek.

### 3. 2D Mesh (√N × √N)

```
   [C0]──[C1]──[C2]──[C3]
    │     │     │     │
   [C4]──[C5]──[C6]──[C7]
    │     │     │     │
   [C8]──[C9]──[CA]──[CB]
    │     │     │     │
   [CC]──[CD]──[CE]──[CF]
```

Négyzet rács, minden router 5-portos (4 szomszéd + 1 lokális). XY routing aciklikus, deadlock-mentes.

### 4. 2D Torus

Mint a mesh, de a szélső core-ok wraparound linkkel kapcsolódnak (toroid felület). Felére csökkenti a max hop számot, de a wraparound vezetékek hosszúak.

### 5. Crossbar (N×N)

```
       C0  C1  C2  C3  ...  Cn
       │   │   │   │
   C0──┼───┼───┼───┼─── ...
       ×   ×   ×   ×
   C1──┼───┼───┼───┼─── ...
       ×   ×   ×   ×
   ...
```

Minden core minden core-ral közvetlen kapcsolatban (1 hop). N² crosspoint switch.

### 6. Fat-tree (k-ary)

```
              [Root]
             /  |  \
        [Sw1]  [Sw2]  [Sw3]
         /\     /\     /\
       C0 C1  C2 C3  C4 C5
```

Hierarchikus fa, ahol felfelé haladva a sávszélesség nem csökken (ezért "fat"). Bisection = N · B.

### 7. Hierarchikus (k-mesh + crossbar fa)

```
[16-core mesh] [16-core mesh] [16-core mesh] ...
       \           |           /
        \          |          /
         [Tile crossbar (8 port)]
                   |
         [Régió crossbar (8 port)]
                   |
              [Chip root]
```

Az alsó szint mesh (fizikai szomszédság), a felsőbb szintek crossbar (logikai központ). 4-szintű (chip → régió → tile → cluster) hierarchia.

## Skálázási képletek

### Vezeték / link szám (~ area költség)

| Topológia | Linkek száma | Area |
|---|---|---|
| Shared bus | O(1) | de N driver kapacitás → repeater O(N) |
| Ring | 2N | O(N) |
| 2D Mesh √N×√N | 2N − 2√N ≈ **2N** | O(N) |
| 2D Torus | 2N | O(N) |
| Fat-tree (k-ary) | O(N · log_k N) | O(N log N) |
| Crossbar N×N | **N²** crosspoint | **O(N²)** |
| Hierarchikus (k-mesh + crossbar fa) | O(N) + O((N/k)² / level) | **O(N)** + alacsonyabb rendű |

### Diameter (max hop)

| Topológia | Diameter |
|---|---|
| Shared bus, Crossbar | 1 |
| Ring | N/2 |
| 2D Mesh √N×√N | 2(√N − 1) |
| 2D Torus | √N |
| Fat-tree (k-ary) | 2 · log_k N |
| Hierarchikus (4 szint) | √16 + 3 · log_k(N/16) |

### Bisection bandwidth (a hálózat felénél átvágó BW)

A bisection BW a **legfontosabb skálázási mérőszám**, mert ez korlátozza az aggregát forgalmat amikor a forgalom nem lokális.

| Topológia | Bisection BW |
|---|---|
| Shared bus | B (egyetlen vezeték) |
| Ring | 2B (bidirekciós) |
| 2D Mesh √N×√N | 2√N · B |
| 2D Torus | 4√N · B |
| Fat-tree | N · B |
| Crossbar | N · B |
| Hierarchikus | N · B (lépcsőzött) |

### Per-core BW (uniform random forgalom)

| Topológia | BW/core | Skálázás |
|---|---|---|
| Shared bus | B / N | **1/N** — összeomlik |
| Ring | ~ 4B / N | **1/N** |
| 2D Mesh | ~ (3/2) · B / √N | **1/√N** |
| 2D Torus | ~ 2B / √N | **1/√N** (~30% jobb mint mesh) |
| Fat-tree | B | **konstans** |
| Crossbar | B | **konstans** |
| Hierarchikus | B (cluster-en belül) | **konstans** |

## Konkrét számok 128-bit linkkel, 1 GHz-en, 144 byte üzenettel

### Per-core BW (uniform-random, GB/s)

| N | Bus | Ring | 2D Mesh | Torus | Crossbar | Hierarch. (16-mesh + xbar fa) |
|---|---|---|---|---|---|---|
| **16** (4×4) | 1,0 | 4,0 | **6,0** | 8,0 | 16,0 | 16,0 |
| **64** (8×8) | 0,25 | 1,0 | 3,0 | 4,0 | 16,0 | ~12 |
| **256** (16×16) | 0,06 | 0,25 | 1,5 | 2,0 | 16,0 | ~10 |
| **1 024** (32×32) | 0,015 | 0,06 | 0,75 | 1,0 | 16,0 | ~8 |
| **10 240** | 0,0015 | 0,006 | 0,24 | 0,32 | 16,0 | ~5 |

### Crosspoint / vezeték igény

| N | Bus linkek | Mesh linkek | Crossbar crosspoint | Hierarchikus crosspoint |
|---|---|---|---|---|
| 16 | 1 | 24 | 256 | 24 + 1 |
| 64 | 1 | 112 | 4 096 | 96 + 16 |
| 256 | 1 | 480 | **65 536** | 384 + 256 |
| 1 024 | 1 | 1 984 | **>1 M** ❌ | 1 536 + 4 096 |
| 10 240 | 1 | ~20 480 | **>100 M** ❌ | ~15 360 + ~6 400 |

A crossbar **N = 256-tól nem szintetizálható** észszerű chipméretben.

## Forgalom-mintázat — aggregát vs per-core BW

> **Fontos:** A fenti "Per-core BW" tábla **uniform random forgalmat** feltételez (minden core minden core-ral azonos valószínűséggel kommunikál) — ez **worst case**. Lokális forgalommal és párhuzamosítással a tényleges per-core BW nagyságrendekkel jobb.

### Aggregát BW — minden link egyszerre dolgozik

Egy mesh-ben (vagy hierarchikusban) **minden link párhuzamosan** képes egyszerre üzenetet hordozni — a teljes hálózat aggregát maximuma a linkek kapacitásainak összege:

| Topológia | Aggregát BW képlet | Indoklás |
|---|---|---|
| Shared bus | B | Egyetlen vezeték, szerializált |
| Ring | 2N · B | 2N link, mindegyik B |
| 2D Mesh √N×√N | **2N · B** (~ 2(N − √N) · B pontosan) | Minden link párhuzamosan |
| 2D Torus | 2N · B | Mint mesh + wraparound |
| Crossbar | N · B | N output port × B (1 hop, de szegmentálatlan) |
| Hierarchikus | ≥ N · B (cluster-lokálisan) + felső szintek | Cluster-lokális forgalomra ~teljes link kapacitás |

### Konkrét aggregát számok (B = 16 GB/s)

| N | Bus aggregát | **Mesh aggregát** | Crossbar aggregát | Hierarchikus (cluster-lokális) |
|---|---|---|---|---|
| **16** | 16 GB/s | **384 GB/s** | 256 GB/s | 384 GB/s |
| **64** | 16 GB/s | **1,8 TB/s** | 1,0 TB/s | ~1,5 TB/s |
| **256** | 16 GB/s | **7,7 TB/s** | 4,1 TB/s | ~6 TB/s |
| **1 024** | 16 GB/s | **31,7 TB/s** | 16,4 TB/s | ~25 TB/s |
| **10 240** | 16 GB/s | **~324 TB/s** | nem építhető | ~250 TB/s |

**Érdekes észrevétel:** a mesh aggregát BW > crossbar aggregát BW azonos N-re. A crossbar 1 hop-pal kapcsolja össze bármely két core-t, miközben a mesh-ben **több link párhuzamosan dolgozik** (több hop, de szegmentálható — minden link saját üzenetet tud vinni egyszerre).

### Forgalom-lokalitás faktor

A tényleges per-core BW erősen függ a forgalom-mintázattól. Példa **1024-core mesh**-re:

| Forgalom-mintázat | Bisection terhelés | Per-core BW | Skálázás |
|---|---|---|---|
| Csak szomszéd-kommunikáció (90%+ lokális) | minimális | **~16 GB/s** = B | konstans |
| Cluster-lokális (4×4 belül) | minimális | ~12 GB/s | konstans |
| Tile-lokális (~64 core) | mérsékelt | ~5 GB/s | lassú csökkenés |
| Régió-lokális (~256 core) | jelentős | ~2 GB/s | √N csökkenés |
| Uniform random | telített | **~0,75 GB/s** ← korábbi tábla | 1/√N |
| Adversariális (anti-pattern) | kritikus | ~0,4 GB/s | 1/√N + congestion |

**A különbség 40× a két szélső eset között.** Egy lokalitás-tudatos aktor-placement (pl. szorosan kommunikáló aktorok ugyanabba a clusterbe) **közel B** per-core BW-t tart fenn, miközben a worst-case forgalom 1/√N skálázással gyengít.

### Mikor érvényes a "Per-core BW" tábla 1/√N skálázása?

A korábbi 1/√N skálázás **csak akkor** korlátoz, ha a bisection BW a szűk keresztmetszet — vagyis amikor a forgalom **átlag minden iránya egyenletes**. A három tipikus eset:

1. **Lokális kommunikáció dominál** (>80% szomszéd vagy cluster-lokális) → per-core BW ≈ B (konstans)
2. **Vegyes forgalom** (~50% lokális, 50% távoli) → per-core BW ≈ B/√(N/k) ahol k a lokális tartomány mérete
3. **Tisztán uniform random** → per-core BW = (3/2)B/√N (a tábla képlete)

A CFPU aktor-modellje az 1. esetre tervez: a HW címek hierarchikusak, a NoC router topológia szomszéd-tudatos, az aktor-placement OS-szintű feladata a lokalitás biztosítása.

### Crossbar vs mesh — más megvilágításban

A crossbar nem a "tökéletes" megoldás minden szempontból:

| Mérőszám | Crossbar (N=1024) | Mesh (N=1024) |
|---|---|---|
| Aggregát BW | 16 TB/s | **31,7 TB/s** (2×) |
| Per-core BW (uniform) | **16 GB/s** | 0,75 GB/s |
| Per-core BW (lokális) | 16 GB/s | **~16 GB/s** (egyenlő) |
| Latencia | **11 ns** | 51 ns |
| Area | 25-35 mm² ❌ | **3,2 mm²** |

A crossbar a **latencia és uniform-random per-core BW** szempontjából nyer; a mesh az **aggregát BW és area** szempontjából. **Lokális forgalom esetén a két topológia per-core BW-je gyakorlatilag azonos**, miközben a mesh-é töredék area-n.

## Elfoglalt szilícium terület (5 nm)

### Egységnyi költségek

| Komponens | Tipikus méret 5 nm-en |
|---|---|
| 1 GE (NAND2 ekv.) | ~0,16 µm² |
| 1 SRAM bit cell (HD) | ~0,021 µm² |
| 1 flit slot (144 byte = 1 152 bit) buffer | ~25–30 µm² |
| 1 crossbar crosspoint | ~10 µm² (~50 GE switch) |
| 5-port mesh router (Compact, 2 VC × 4 slot) | ~14,5k GE ≈ **0,003 mm²** |
| 5-port mesh router (Turbo, full VOQ × 4 VC) | ~40k GE ≈ **0,008 mm²** |
| 1 mm vezeték (128-bit, M3-M4 metal) | ~256 repeater + tracks |

### Router buffer méretezése a 144 byte cellából

Egy 5-portos mesh router buffer költsége (a router area >50%-a kis N-en):

```
Slot méret    : 144 byte = 1 152 bit
Slot/port/VC  : 4 (jellemző wormhole pipeline)
VC/port       : 2 (priority + normal)
Port          : 5 (N, S, E, W, local)
Összes slot   : 5 × 2 × 4 = 40 slot
Buffer SRAM   : 40 × 144 byte = 5,76 kB / router
Area (5 nm)   : ~0,002 mm² SRAM + ~0,001 mm² logika
Total/router  : ~0,003 mm² (Compact variáns)
```

→ **1024-core mesh teljes buffer SRAM = ~5,9 MB**, ami a teljes mesh terület ~10–15%-a.

Ha az üzenetegységet **288 byte-ra** növelnénk (2× cella):
- Buffer area 2× → ~0,006 mm²/router
- 1024-core mesh: 6,4 mm² (2× annyi)

A mesh router area cella mérettre **közel lineárisan érzékeny**.

### Teljes NoC area mm²-ben

| N | Bus | Ring | 2D Mesh | Torus | Crossbar | Fat-tree (k=8) | Hierarch. |
|---|---|---|---|---|---|---|---|
| **16** | ~0,01 ⚠️ | 0,03 | 0,05 | 0,06 | 0,18 | – | 0,05 |
| **64** | ❌ | 0,1 | 0,2 | 0,22 | **1,0** | 0,5 | 0,25 |
| **256** | ❌ | 0,4 | 0,8 | 0,9 | **5–7** | 2,0 | 1,0 |
| **1 024** | ❌ | 1,5 | 3,2 | 3,5 | **25–35** | 10 | 4 |
| **10 240** | ❌ | 15 | 32 | 35 | **>1 000** ❌ | ~120 | 40 |

A **bus** N ≥ 8-tól nem életképes (kapacitás → driver + repeater → frekvencia összeomlik).
A **crossbar** N ≥ 256-tól már több területet eszik mint maguk a magok.

### Komponensbontás (1024-core eset)

| Topológia | Router/Logika | Buffer SRAM | Vezeték | **Összesen** |
|---|---|---|---|---|
| 2D Mesh 32×32 | 1024 × 0,003 = 3,1 mm² | ~0,15 mm² (router-be integrálva) | bele | **~3,2 mm²** |
| Torus 32×32 | ugyanaz | ugyanaz | +10% wraparound | **~3,5 mm²** |
| Crossbar 1024² | 0,5 mm² (arbiter) | ~12 mm² (1024 input × 9 kB) | ~10 mm² (N² xpoint) | **~25 mm²** |
| Fat-tree k=8 | 512 router × 0,02 = 10 mm² | bele | bele | **~10 mm²** |
| Hierarch. (64×16+fa) | 1024 × 0,003 + ~0,5 | ~0,2 mm² | bele | **~4 mm²** |

### NoC overhead arány

Feltéve **0,5 mm²/core** átlag:

| N | Chip core area | Mesh NoC | Crossbar NoC | Hierarch. NoC |
|---|---|---|---|---|
| 16 | 8 mm² | **0,6%** | 2,3% | 0,6% |
| 64 | 32 mm² | **0,6%** | 3,1% | 0,8% |
| 256 | 128 mm² | **0,6%** | 4,7% | 0,8% |
| 1 024 | 512 mm² | **0,6%** | 5,3% | 0,8% |
| 10 240 | 5 120 mm² | **0,6%** | nem építhető | 0,8% |

A **mesh és hierarchikus megoldás konstans ~0,6–0,8% area overhead** marad, függetlenül N-től. A **crossbar overhead lineárisan nő N-nel** (mert N² area / N · core = N).

## Latencia (wormhole, 2 ciklus/router)

Latency ≈ F + 2 · hop_count ciklus = 9 + 2 · hop ciklus (128-bit linken)

| Topológia | Átlag hop | Latency 1 GHz-en |
|---|---|---|
| Crossbar | 1 | 11 ns |
| Bus (egy üzenet) | 1 | 11 ns (de szerializált!) |
| 16-core mesh | ~2,7 | 14 ns |
| 64-core mesh | ~5,3 | 20 ns |
| 256-core mesh | ~10,7 | 30 ns |
| 1024-core mesh | ~21,3 | 51 ns |
| Hierarchikus 1024 (4 szint, ~6 hop + 3 xbar hop) | ~9 | ~21 ns |

A bus latencia félrevezető — 1 üzenet 11 ns alatt halad át, de **N-re szerializálódik**, így a tényleges effektív latency N · 11 ns nagyforgalom alatt.

## Topológia választás algoritmus

```
HA N ≤ 8 ÉS forgalom ritka:
    Shared bus elegendő
ELSE HA N ≤ 32 ÉS BW kritikus, area nem:
    Crossbar a tisztább megoldás
ELSE HA 16 ≤ N ≤ 64 ÉS uniform szomszédság:
    2D Mesh / Torus optimum
ELSE HA N ≥ 64:
    Hierarchikus (cluster mesh + crossbar fa)
        — egyetlen életképes választás
        — konstans per-core BW
        — lineáris area
```

A döntési határok empirikusak; a pontos érték a node, frekvencia és üzenet-méret függvényében változik (a 144 byte cellára a fenti táblák érvényesek).

## A "miért hierarchikus" matematikai indoklása

A hierarchikus megoldás (16-core cluster mesh + crossbar fa) azért nyer N ≥ 64-től:

```
N = 1024 core példa:

  Tiszta crossbar:    1024² = 1 048 576 crosspoint  ❌
                      ~25-35 mm² area

  Tiszta 2D mesh:     1 984 link, de 51 ns latency
                      0,75 GB/s/core (csökken N-nel)
                      ~3,2 mm² area

  Hierarchikus:       64 × (16-core mesh) + 64-port crossbar tree
                    = 64 × 24 + 64² = 1 536 + 4 096 = 5 632 crosspoint
                      21 ns latency
                      ~8 GB/s/core (10× jobb mint tiszta mesh)
                      ~4 mm² area
```

Tehát N = 1024 core-nál a hierarchikus:
- **~186× kevesebb crosspoint** mint a crossbar (5,6k vs 1M)
- **10× jobb per-core BW** mint a tiszta mesh
- **csak 2× rosszabb per-core BW** mint a (megépíthetetlen) crossbar
- **~25%-kal több area** mint a tiszta mesh (4 vs 3,2 mm²) — több router miatt, de a 10× jobb per-core BW és 2,4× jobb latencia bőven kompenzálja
- **2,4× jobb latencia** mint a tiszta mesh (21 vs 51 ns)

A hierarchikus topológia ezért a **CFPU választása** is (lásd `interconnect-hu.md` 4-szintű hierarchia).

## Fő összefüggések

**1. Bisection BW dönti el a skálázódást, nem a link szélesség.**
- 2D mesh: bisection ∝ √N → per-core BW ∝ 1/√N
- Torus / fat-tree / hierarchikus: bisection ∝ N → per-core BW konstans

**2. Crossbar a "tökéletes" megoldás N²-tel fizetve.**
- N = 16: 256 crosspoint, kezelhető
- N = 64: 4 096 crosspoint, határeset
- N ≥ 256: nem szintetizálható (>65k crosspoint)

**3. A 144 byte üzenetegység három dolgot határoz meg:**
- **Üzenet hossza flit-ben:** 9 flit 128-bit linken (header overhead ~11%)
- **Forgalom granularitása:** túl kicsi üzenet → router overhead dominál; túl nagy → HOL blocking
- **Buffer méret:** minden router ~5,76 kB / VC × port-onként (mesh router fő area-költsége)

**4. NoC overhead lineárisan skálázódó topológiákban konstans.**
- Mesh, torus, hierarchikus: ~0,6–0,8% chip area, függetlenül N-től
- Crossbar: a chip arányosan egyre több területet vesz el N-nel (N=1024-nél 5%+)

## Iparági referenciák

| Rendszer | Topológia | N | Megjegyzés |
|---|---|---|---|
| Intel Xeon (Skylake-SP+) | 2D Mesh | 28+ | Server core, nem-hierarchikus |
| AMD EPYC (Zen 4) | Crossbar (CCD) + Infinity Fabric | 8/CCD | Hierarchikus, on-package |
| Apple M4 Max | Ring (P-cluster) + crossbar | 4-12 | Heterogén |
| ARM CoreLink CMN | Mesh (mesh-IP) | 1-128 | Konfigurálható mesh |
| Adapteva Epiphany | 2D Mesh (eMesh) | 16/64 | Many-core nano |
| Tenstorrent Tensix | 2D Torus (NoC) | 80-256 | ML-orientált |
| Cerebras WSE-3 | 2D Mesh (lokális) | 900 000 | Wafer-skála |
| **CFPU (terv)** | **Hierarchikus (mesh + crossbar fa)** | **16–10 240** | 4-szintű, lásd `interconnect-hu.md` |

## Kapcsolódó dokumentumok

- [`interconnect-hu.md`](interconnect-hu.md) — CFPU 4-szintű hierarchikus mesh + crossbar konkrét specifikáció
- [`internal-bus-hu.md`](internal-bus-hu.md) — busz szélesség választás (32–1024 bit) core típusonként
- [`decision-bus-rollback-hu.md`](decision-bus-rollback-hu.md) — L0 busz visszaléptetés indoklása (256→128 bit)
- [`architecture-hu.md`](architecture-hu.md) — F4 shared bus → F6 mesh átmenet (16 core határ)
- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — TLP > ILP filozófia (sok kis core a lineáris skálázódás miatt)
- [`osreq-from-os/osreq-001-tree-interconnect-hu.md`](osreq-from-os/osreq-001-tree-interconnect-hu.md) — Symphact OS hardware requirement a topológiára
- [`3d-stack-architecture-hu.md`](3d-stack-architecture-hu.md) — a bisection-fal 3D-feloldása: per-csempe SRAM + külön memória-mesh sík

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.2 | 2026-07-02 | Kereszthivatkozás hozzáadva a [`3d-stack-architecture-hu.md`](3d-stack-architecture-hu.md) dokumentumhoz — a bisection-fal 3D-feloldása (per-csempe SRAM + külön memória-mesh sík). |
| 1.1 | 2026-05-03 | **Új szekció: "Forgalom-mintázat — aggregát vs per-core BW"**. A v1.0 csak uniform random forgalmat mutatott (worst case); a v1.1 hozzáadja az aggregát BW képletet (mesh: 2N · B), konkrét aggregát számokat (16-core mesh 384 GB/s, 1024-core mesh 31,7 TB/s), forgalom-lokalitás faktor táblát (40× különbség szomszéd vs uniform), és a crossbar vs mesh közvetlen összehasonlítást azonos N-en. Kulcs konklúzió: lokális forgalom esetén a mesh per-core BW ≈ B (mint a crossbar), miközben a mesh aggregát > crossbar aggregát. A korábbi 1/√N skálázás csak a bisection-limited (uniform random) esetben érvényes |
| 1.0 | 2026-05-03 | Kezdeti verzió — általános NoC topológia skálázás CFPU-tól elvonatkoztatva. Bus/Ring/Mesh/Torus/Crossbar/Fat-tree/Hierarchikus összehasonlítás 144 byte üzenetegységgel. Per-core BW, bisection BW, area (5 nm), latencia képletek és konkrét számok N = 16, 64, 256, 1024, 10240 core-ra. Topológia választás algoritmus. A hierarchikus választás matematikai indoklása N ≥ 64-től |
