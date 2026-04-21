# CFPU Interconnect Architektúra

> English version: [interconnect-en.md](interconnect-en.md)

> Version: 2.3

Ez a dokumentum a Cognitive Fabric Processing Unit (CFPU) **on-chip interconnect hálózatát** specifikálja: a topológiát, a switching modellt, a router belső felépítését, a fizikai elrendezést, a core családot és a node-skálázási stratégiát.

## Core család

A CFPU négy programozható core típust definiál (Nano, Actor, Rich, Seal) és hat termékvariánst (CFPU-N/A/R/ML/H/X). Az ML inference-hez MAC Slice-okat (FSM-vezérelt, nem programozható) használ. A részletekért — ISA különbségek, terület-hatás, SRAM méretezés, power domain-ek, piaci pozíció — lásd [`core-types-hu.md`](core-types-hu.md), a MAC Slice specifikációhoz: [`cfpu-ml-max-hu.md`](cfpu-ml-max-hu.md).

## Tervezési alapelvek (prioritás sorrendben)

1. **Biztonság nem kompromisszum** — shared-nothing kötelező, semmi közös memória vagy cell pool. A magok másolással küldenek üzenetet, nem pointer-átadással.
2. **Core szám = számítási teljesítmény** — minden gate amit a routerre költünk, az egy core-ból hiányzik. A router terület minimalizálandó. Három router variáns (Turbo, Compact, Systolic) 4–29% overhead-et tart core típustól függően (lásd L0 Router variánsok).
3. **Üzenet sebesség = rendszer sebesség** — de egyszerű és kicsi routerrel, nem okossal és naggyal. Csak olyan technikát használunk, ami effektív core-számot növel.

## 4-szintű hierarchia

A CFPU on-chip hálózata **4 szintű hierarchia**, ahol az alsó szint mesh, a felsőbb szintek crossbar:

```
L3: Chip ── N₃ régió, csillag topológia
            Seal Core + crossbar a chip geometriai közepén
 └── L2: Régió ── N₂ tile, crossbar a régió közepén, soros link
      └── L1: Tile ── N₁ cluster, crossbar a tile közepén
           └── L0: Cluster ── 16 core (Nano/Actor/Rich), 4×4 mesh (fix)
```

### Miért mesh alul, crossbar felül?

| Szempont | Mesh | Crossbar |
|----------|------|----------|
| Sok port (64+) | Hatékony: rövid vezetékek, alacsony gate | Drága: N² skálázás |
| Kevés port (8-16) | Pazarló: sok hop, változó latencia | **Hatékony: 1 hop, fix, determinisztikus** |
| Fizikai szomszédság | **Természetes**: 2D chip = 2D mesh | Közepén kell elhelyezni |
| Routing döntés | Szükséges minden hop-nál | **Nincs**: crossbar = direkt kapcsolás |

A mesh ott van, ahol fizikailag indokolt (core-ok között, ~300 μm). A crossbar ott van, ahol logikailag indokolt (gateway-ek között, 8-18 port).

### Referencia konfiguráció (5nm, 800 mm²)

```
L0: 16 core × L1: 8 cluster × L2: 8 tile × L3: 10 régió = 10 240 core
```

### Paraméterezhető konfiguráció

| Paraméter | Fix/Változó | Tartomány | Meghatározó |
|-----------|-------------|-----------|-------------|
| `CORES_PER_CLUSTER` | **Fix** | 16 (4×4) | Fizikai optimum: ~1.1 mm, 2 ciklusos wormhole pipeline/hop |
| `CLUSTERS_PER_TILE` | Változó | 4-12 | Node, chipméret |
| `TILES_PER_REGION` | Változó | 4-12 | Node, chipméret |
| `REGIONS` | Változó | 4-24 | Chipméret |
| `SRAM_KB_PER_CORE` | Változó | 16-1024 | Node |
| `CELL_SIZE` | Változó | 64/128 | Cella méret variáns |
| `CORE_TYPE` | Változó | NANO/ACTOR/RICH/MATRIX | Alkalmazásfüggő (heterogénnél vegyes) |
| `ROUTER_VARIANT` | Változó | TURBO/COMPACT/SYSTOLIC | Core típustól függő (klaszter-szintű) |
| `SERDES_RATIO` | Változó | 4–12 | Core órajeltől függő (lásd SerDes skálázás) |
| `SERIAL_WIRES` | Változó | 8–16 | Chipméret, vezeték-büdzsé |

## Switching modell

### ATM-inspirált fix cella

Minden üzenet **fix cellákra** darabolva halad a hálózaton: **16 byte header + 64 byte payload = 80 byte**.

```
Cella = Header (16 byte) + Payload (64 byte) = 80 byte

Header (16 byte = 128 bit) — Header SRAM-ban tárolva:
┌──────────────────────────────────────────────────────┐
│  dst[24] + src[24] + seq[8] + flags[8]                │
│  + len[16] + reserved[40] + CRC-8[8]                  │
└──────────────────────────────────────────────────────┘

Payload (64 byte) — Payload SRAM-ban tárolva:
┌──────────────────────────────────────────────────────┐
│  64 byte alkalmazás-adat                              │
└──────────────────────────────────────────────────────┘
```

**Split SRAM design:** a header és a payload **külön SRAM-ban** tárolódik a routerben. Ez természetes, mert funkcionálisan különböznek: a scheduler a headert olvassa a routing döntéshez, miközben a payload még érkezik — **1 ciklus latencia-megtakarítás**. Nincs port-verseny a scheduler és a crossbar között. Mindkét SRAM 2-hatvány igazított: header = slot × 16, payload = slot × 64 — egyszerű shift-es címzés, nincs szükség szorzóra.

**Miért 16 byte-os header?** A logikai mezők (dst, src, seq, flags, len, CRC) 88 bitet igényelnek. A 16 byte (128 bit) a természetes 2-hatvány határ, 40 bit reserved-del jövőbeli bővítésekre (QoS osztály, üzenet típus, fragmentációs info), header-formátum változtatás nélkül. A 64 byte-os payload szintén természetes 2-hatvány határ a szoftver számára.

**Miért fix cella?** A fix méret determinisztikus időzítést, egyszerű buffer-kezelést és egyszerűbb crossbar hardvert eredményez. Az ATM hálózatok (1985) alapelve, szilíciumra adaptálva.

### Miért 64 byte payload — Rich Core-oknál is?

Az eredeti 128 byte-os payload a Matrix Core 4×4 tile-jához volt túlméretezett, de a kérdés jogos: a Rich Core aktor-üzenetei nem igényelnek-e nagyobb cellát?

**Az elemzés azt mutatja, hogy a 64 byte-os payload a Rich Core-nak is előnyös:**

| Szempont | 64B payload (80B cella) | 128B payload (144B cella) |
|----------|------------------------|--------------------------|
| Header overhead | 20% | 11% |
| Flit szám (42-bit L0 link) | 16 flit | 28 flit |
| Szomszéd latencia | 2H + 15 = 17 cc | 2H + 27 = 29 cc |
| Cross-régió latencia | ~139 cc | ~229 cc |
| Router VOQ SRAM | kisebb | ~1,6× nagyobb |
| Router terület (Turbo) | 0,006 mm² | ~0,008 mm² |

**Döntő érv: a latencia.** A 80 byte-os cella **40%-kal gyorsabb** cross-régió latenciát ad (139 vs 229 cc). Ez **minden üzenetre** hat — parancsokra, eseményekre, válaszokra —, míg a 128B payload header-overhead előnye (11% vs 20%) **csak a ritka, nagy üzeneteknél** (state migráció, bulk transfer) számít.

Az Akka/actor stílusú rendszerekben az üzenetek nagy többsége kicsi (parancsok, események, rövid válaszok: 16–64 byte), amelyek egyetlen 64B cellába elférnek. A nagy üzeneteknél (4–16 KB state migráció) a dupla celladarab overhead elhanyagolható a teljes transzfer idejéhez képest.

A `CELL_SIZE` RTL paraméter biztonsági háló: ha egy specifikus CFPU-R konfiguráció workload-ja megköveteli, 128B-re állítható gyártáskor.

**Végleges döntés (2026-04-20):** a 64B payload marad a fő mesh-re.

#### Miért nem 128B? — Részletes elemzés

**1. Az ML-Max nem indokolja a cella növelést.**
Az eredeti 128→64 csökkentés egyik indoka az volt, hogy a Matrix Core 4×4 tile-hoz a 128B túlméretezett. Azóta a CFPU-ML-Max saját 128-bit systolic routert használ (cluster-en belüli on-die link) — a tenzor-adatforgalom **nem a fő mesh-en** halad. Tehát sem a 128B melletti, sem az ellene szóló eredeti ML-érv nem releváns már.

**2. Aggregált throughput elemzés — a mátrix átbocsátó képessége.**

Egyetlen link throughput (42-bit L0 @ 500 MHz):

| Cella | Flit szám | Payload throughput | Link hatásfok |
|-------|-----------|-------------------|---------------|
| 80B (64B payload) | 16 flit | 64B / 16 cc = 4.00 B/cc | 80% |
| 144B (128B payload) | 28 flit | 128B / 28 cc = 4.57 B/cc | 89% |

**Egyetlen linken a 128B cella 14%-kal jobb.** De ez félrevezető — a rendszer-szintű throughput-ot a **tényleges hasznos adat / link-foglalási idő** határozza meg:

Tipikus actor workload üzenetméret-eloszlás:
- ~80% üzenet ≤ 48 byte payload (parancs, válasz, esemény, heartbeat)
- ~15% üzenet 49–64 byte (közepes payload)
- ~5% üzenet > 64 byte (code-load, state migration — multi-cell)

Egy 32 byte-os actor üzenet szállítási költsége:

| Cella | Flit | Hasznos adat | Hatásfok (B/flit) |
|-------|------|-------------|-------------------|
| 80B (64B payload) | 16 | 32B | 2.00 B/flit |
| 144B (128B payload) | 28 | 32B | 1.14 B/flit ← **43% pazarlás** |

A 128B cella **28 ciklusig foglalja a linket** egy 32 byte-os üzenettel — a 64B cella ugyanezt **16 ciklus** alatt szállítja. A hasznos adat azonos, de a link-foglalás 75%-kal hosszabb.

Súlyozott aggregált hatásfok (B/flit, workload mixszel):

```
64B cella:  0.80×(32/16) + 0.15×(56/16) + 0.05×(64/16) = 2.33 B/flit
128B cella: 0.80×(32/28) + 0.15×(56/28) + 0.05×(128/28) = 1.44 B/flit
```

**A 64B cella ~38%-kal nagyobb aggregált throughput-ot ad** a 10 000 core-os mesh-ben a tipikus actor workload mellett.

**3. Wormhole routing és HOL blocking.**

Wormhole routing-ban a cella **lefoglalja a köztes linkeket** amíg áthalad. Nagyobb cella = hosszabb foglalás = több torlódás:

```
H=50 átlagos hop (100×100 grid):
  64B cella:  link foglalás = 2H + 15 = 115 cc
  128B cella: link foglalás = 2H + 27 = 127 cc (+10%)
```

A 10%-kal hosszabb link-foglalás exponenciálisan növeli a Head-of-Line blocking valószínűségét magas terhelés mellett. A VOQ csökkenti, de nem szünteti meg. Az eredmény: a 128B cella hamarabb telíti a hálózatot.

**4. Code-load throughput — multi-cell streaming-gel megoldott.**

A Seal Core code-load a teljes chip forgalmának <5%-a. A throughput kérdése nem cella-méret növeléssel, hanem pipeline-olt multi-cell streaming-gel megoldott:
- 16 KB metódus = 256 cella (64B payload), pipeline-olva
- L0 throughput @ 500 MHz: ~2.6 GB/s
- Worst-case kézbesítés: ~8 μs @ 500 MHz

**5. Memória és tárhardverek natív burst mérete — a 64B természetes egység.**

| Memória típus | Natív burst méret | Illeszkedés |
|---------------|-------------------|-------------|
| DDR4 | 64 byte (BL8 × 8B) | **= 64B payload** |
| DDR5 | 64 byte (BL16 × 4B, dual sub-channel) | **= 64B payload** |
| LPDDR5 | 32–64 byte (BL16 × 2B vagy BL32 × 2B) | ≤ 64B payload |
| HBM2e/HBM3 | 32–256 byte (pseudo-channel, BL4 × 32B tipikus) | 64B és 128B is natív |
| QSPI Flash | 64–256 byte (page: 256B, de 64B burst optimális) | **= 64B payload** |
| On-chip SRAM | Cache line: 64 byte (iparági standard) | **= 64B payload** |
| NOR Flash | 64–128 byte burst | ≤ 64B illeszkedik |

A 64 byte-os payload **pontosan egy DDR4/DDR5 burst-nek, egy cache line-nak, és egy QSPI burst-nek felel meg**. Ez nem véletlen: az iparági memória-hierarchia a 64B-t választotta alapegységnek (Intel/AMD L1 cache line = 64B, ARM = 64B). A CFPU cella payload ennek tökéletesen illeszkedik — egy cella payload = egy memória-tranzakció, nincs töredék, nincs padding.

A 128B payload a HBM-nél illeszkedne jobban, de a HBM 64B-s sub-burst-öt is támogat, míg a DDR4/DDR5 és QSPI **nem** támogat 128B-t natívan (két tranzakcióra bontaná).

**Összefoglalás:** a 64B payload az actor-mesh optimális mérete. A 128B csak akkor lenne előnyös, ha a forgalom >50%-a 65–128 byte közötti — ez a CFPU-ban nem áll fenn. A 64B emellett az iparági memória-hardverek natív burst egysége.

### Címzés: 24 bit hierarchikus

```
HW cím: [régió:4-6].[tile:3-4].[cluster:3-4].[core:4] = 18 bit (a 24-ből)
Actor ID: szoftveres dispatch (payload bájtok, nem része a HW címnek)
```

A hardveres cím a cellákat egy **core-hoz** irányítja, nem egy egyedi actorhoz. Az actor dispatch-et szoftveresen kezeli a célcore lokális schedulere — az actor ID a cella payload-jában utazik. Ez a megoldás lehetővé teszi, hogy az actorok száma core-onként változzon core típus, SRAM méret és workload szerint, fix hardveres korlát nélkül. A maradék 6 bit (24 − 18) jövőbeli címzési bővítésekre fenntartva. Részletek: [Architektúra — Actor Scheduling Pipeline](architecture-hu.md#actor-scheduling-pipeline).

A routing döntés O(1): a cím prefix-éből azonnal eldönthető, melyik szintű crossbar/mesh felé kell irányítani.

### Hibrid switching: Wormhole (L0) + Virtual Cut-Through (L1–L3)

A CFPU két switching módot használ, hierarchia-szinthez igazítva:

**L0 (mesh) — Wormhole routing:** a header flit (42 bit, a célcímet tartalmazza) azonnal továbbítódik a route döntés után; a body flitek pipeline-ban követik, ciklusonként egy. Egy 80 byte-os cella = 16 flit a 42 bites linken. H hop esetén a header 2H ciklus alatt halad át a mesh-en (2 ciklusos router pipeline: route + switch), az utolsó body flit 15 ciklussal később érkezik. **Összesen: 2H + 15 ciklus.**

**L1–L3 (crossbar-ok) — Virtual Cut-Through (VCT):** a cella teljesen beérkezik a crossbar input bufferbe a switching előtt. Az iSLIP scheduler a headert már fogadás közben olvassa (1 ciklus overlap), majd a cella 1 crossbar ciklussal továbbítódik. A VCT megőrzi a store-and-forward deadlock-mentességét (nincs láncos buffer-foglalás), miközben lehetővé teszi a pipelined header vizsgálatot.

### Virtual Output Queuing (VOQ)

Minden input port külön sort tart **minden kimenő port felé**. Ha az A port felé blokkolva vagyunk, a B port felé menő csomagok zavartalanul haladnak. Throughput: ~58% (egyszerű FIFO) → **~99% (VOQ)**.

**Költség-haszon:** a VOQ ~900 core-ba kerül (extra gate), de ~3 800 effektív core-t nyer (a throughput javulás miatt). Egyértelmű győzelem.

### iSLIP scheduler

Nick McKeown (Stanford, 1999) algoritmusa: maximális számú párhuzamos átvitelt ütemez round-robin fairness-szel, **1 órajelciklus** alatt. ~3 000 gate — elenyésző költség.

### Credit-based flow control

Minden link előre megmondja, hány cellát tud fogadni (4 credit/csatorna). A küldő csak credit-tel küld — a torlódás nem terjed szét a hálózatban.

### Deadlock-mentesség

**Wormhole (L0) + VCT (L1–L3) + VOQ + credit-based flow control = deadlock-mentes by construction.**

- **L0 mesh:** Az XY dimension-ordered routing teljes rendezést hoz létre a csatornákon — ciklikus függőség nem alakulhat ki (Dally & Seitz, 1987). A wormhole itt pont azért biztonságos, mert a routing függvény aciklikus.
- **L1–L3 crossbar-ok:** A VCT azt jelenti, hogy a cella teljes egészében pufferelve van a switching előtt — nincs láncos buffer-foglalás a hop-ok között. A VOQ megakadályozza a HOL-blocking szétterjedését. A credit-based flow control megakadályozza a buffer túlcsordulást.

Ez a kombináció minden szinten eliminálja a deadlockot, Virtual Channel-ek vagy az L0-s XY rendezésen túli extra routing korlátok nélkül.

## Szintenkénti részletek

### L0: Cluster (4×4 mesh, 16 core)

| Paraméter | Érték |
|-----------|-------|
| Topológia | 4×4 mesh, XY routing |
| Core-ok | 16 core (klaszterenként egy típus) |
| Fizikai méret | ~1.1 mm × 1.1 mm (5nm) |
| Link típus | Párhuzamos, 42 bit, 1× core clock |
| Vezeték hossz | ~330 μm (szomszéd core) |
| Max hop | 6 |
| Router terület / core | 0,001–0,006 mm² (lásd L0 Router variánsok) |
| Gateway | A sarok core router-jébe integrált uplink port |

#### L0 Router variánsok

Az L0 router a legnagyobb per-core overhead a CFPU-ban. Az eredeti 5-portos baseline router (~44 300 GE ≈ 0,011 mm²) Rich Core klaszterre volt méretezve. Kisebb core típusoknál (Nano, Actor, Matrix) ez a router nagyobb területet foglalna, mint maga a core. Ezért a CFPU két router variánst definiál, klaszterenként a `ROUTER_VARIANT` RTL paraméterrel választva.

**Baseline router felbontás (5-portos, Rich Core):**

| Komponens | GE | Funkció |
|-----------|---:|---------|
| Crossbar (5×5, 80 B) | 2 950 | Input→output adatkapcsolás |
| VOQ logika (5×5×4 = 100 slot) | 5 000 | Enqueue/dequeue, pointerek, flag-ek |
| VOQ SRAM (100 × 80 B = 8 KB) | 14 700 | Cella-tárolás |
| iSLIP ütemező (5×5) | 3 000 | Round-robin fair scheduling |
| XY routing | 1 000 | Cím → irány dekódolás |
| Credit flow control (5 × 4 credit) | 2 000 | Túlcsordulás megelőzés |
| 2 VN demux | 2 000 | Control / Actor forgalom szétválasztás |
| Cell assembly + CRC-8 | 1 670 | Cella-keretezés, integritás |
| Egyéb vezérlés | 12 000 | FSM, reset, power-gate interfész |
| **Összesen** | **~44 300** | **≈ 0,011 mm²** |

> **Terület-konvenció:** A GE→terület konverzió ~0,21 µm²/GE-t feltételez 5nm-en (logika + routing overhead), az SRAM dense 6T cellákat használ (~0,021 µm²/bit). Ezek szintézis előtti becslések; a végleges területet az RTL szintézis határozza meg (F4+). A baseline router 80B cellákra van méretezve.

**Variáns A: Turbo — Sebesség > Terület**

Maximális átvitel és latencia optimalizálás. Terület csökkentés a sebesség feláldozása nélkül.

| Változtatás | Indoklás | Sebesség hatás |
|-------------|----------|----------------|
| Heterogén portszám (sarok=3, él=4, belső=5) | Nem minden mesh csomópontnak kell 5 port. Átlag: 4,0 port. | Nincs |
| VOQ mélység 3 (4 helyett) | 25% kevesebb buffer SRAM | Throughput: 99% → 98% |
| iSLIP marad | 3 000 GE közel optimális throughput-ért | Nincs |
| 2 VN marad | Control plane izoláció kritikus | Nincs |
| Credit: 3 (4 helyett) | 1-gyel kevesebb regiszter/port | Elhanyagolható |

**Eredmény: ~26 000 GE ≈ 0,006 mm²** (−41% GE, −36% terület a baseline-hoz képest)

**Variáns B: Compact — Terület > Sebesség**

Agresszív router terület minimalizálás. Mérsékelt throughput csökkenés elfogadásával.

| Változtatás | Indoklás | Sebesség hatás |
|-------------|----------|----------------|
| Heterogén portszám | Ugyanaz mint Turbo. Átlag: 4,0 port. | Nincs |
| VOQ → 2 queue/input (priority + normal) | A full VOQ a legnagyobb területköltség. A priority queue a VN0 megfelelője. | Throughput: 99% → ~75%, mérsékelt HOL blocking |
| iSLIP → fix prioritásos round-robin | 1 arbiter/output az N×N iSLIP mátrix helyett | Burst alatt enyhén kevésbé fair |
| 1 VN + priority bit (2 VN helyett) | Priority bit a headerben; a priority cellák előre ugranak | Control plane ~95% izolált |
| Credit: 2 (4 helyett) | Burst alatt több stall | Kisebb hatás |
| Queue mélység: 2 (4 helyett) | Minimális bufferelés | Burst alatt több stall |

**Eredmény: ~14 500 GE ≈ 0,003 mm²** (−67% GE, −64% terület a baseline-hoz képest)

**Variáns C: Systolic — ML/SNN > Általános**

Dedikált ML/SNN pipeline router. Két 128-bites egyirányú link (W→E aktiváció, N→S súly betöltés), XY routing, VOQ és iSLIP nélkül. A felszabadult vezeték-büdzsét szélesebb (128-bit) forward linkekre fordítjuk, hogy a MAC array-t teljes sebességgel tápláljuk.

| Változtatás | Indoklás | Sebesség hatás |
|-------------|----------|----------------|
| 2 irány (W→E, N→S), 128-bit | Systolic pipeline fix adatfolyam | **3× sávszélesség** (128 vs 42 bit/cc) |
| VOQ eltávolítva | Nincs routing conflict systolic-ban | Nincs negatív hatás |
| iSLIP eltávolítva | Nincs arbitráció, fix irányok | Nincs negatív hatás |
| XY routing eltávolítva | Fix irányok, nincs routing döntés | Nincs negatív hatás |
| 2 VN → control uplink only | Adat a systolic linken, control a thin uplinken | Control ~95% izolált |
| Credit: 4 | Backpressure a 128-bit linken | Nincs |

**Eredmény: ~5 000 GE ≈ 0,001 mm²** (−81% a Turbo-hoz, −93% a baseline-hoz képest)

**Router felépítés (~5 000 GE):**

| Komponens | GE | Funkció |
|-----------|---:|---------|
| Data path MUX (2 × 128-bit) | 1 000 | Lokális ↔ átmenő kapcsolás |
| FIFO (2 irány × 2 slot × 80B) | 600 | Minimális pufferelés |
| Credit flow control (2 × 4 credit) | 400 | Backpressure |
| Control uplink (vékony, VN0 only) | 1 500 | Kód betöltés, supervisor |
| Cell assembly + CRC-8 | 500 | Cella integritás |
| Egyéb vezérlés | 1 000 | FSM, reset |
| **Összesen** | **~5 000** | **≈ 0,001 mm²** |

**Link struktúra (~274 vezeték/core):**

```
W → [128 bit aktiváció] → E     128 vezeték + 4 credit = 132
N → [128 bit súly load] → S     128 vezeték + 4 credit = 132
Control uplink                   ~10 vezeték
───────────────────────────────────────
Összesen:                        ~274 vezeték/core
```

Ez **kevesebb** mint a Turbo (~340 vez/core), de **3×** a sávszélesség (128 vs 42 bit/cc).

**Cella szerializáció Systolic Wide linken:** 80 byte = 640 bit → ⌈640/128⌉ = 5 flit. Szomszéd latencia: ~7 cc (2 hop pipeline + 5 body drain). Modell: 2H + 5.

A Systolic variáns **nem általános célú** — kizárólag ML/SNN workload-okhoz, ahol az adatfolyam iránya compile-time ismert. Általános actor workload-hoz a Turbo vagy Compact variáns szükséges.

**Miben különbözik a többi variánstól:**
- Nincs XY routing (fix irányok: W→E, N→S)
- Nincs VOQ (systolic pipeline szinkron, nincs conflict)
- Nincs iSLIP (nincs arbitráció, fix adatfolyam)
- Nincs 2 VN (csak control uplink)
- 128-bit data path (vs 42-bit Turbo/Compact)
- 2 irány (vs 4-5 Turbo/Compact)

**Sebesség összehasonlítás:**

| Metrika | Turbo | Compact | **Systolic** |
|---------|:-----:|:-------:|:------------:|
| Sávszélesség / link | 42 bit/cc | 42 bit/cc | **128 bit/cc** |
| Sustained throughput | ~98% | ~75% | **~95% (systolic)** |
| Szomszéd latencia | ~17 cc | ~19–21 cc | **~7 cc** |
| Worst-case klaszteren belül | ~27 cc | ~30–34 cc | **~7 cc (1 hop)** |
| MAC kihasználtság (ws) | ~15% | ~12% | **~100%** |
| Kommunikáció | Any-to-any | Any-to-any | **W→E, N→S only** |
| Control plane izoláció | Teljes (VN0) | Priority bit (~95%) | Control uplink (~95%) |

*(ws = weight-stationary)*

**Ajánlott variáns core típusonként:**

| Core típus | Variáns | Router terület | Router / core | Indoklás |
|------------|:-------:|---------------:|--------------:|----------|
| **Nano** | Compact | 0,003 mm² | 38% | A core apró (0,008 mm²); egyszerű aktorok ritkán szaturálják a 75% throughput-ot |
| **Actor** | Compact | 0,003 mm² | 13% | Üzenet-feldolgozási idő >> hálózati tranzit; 75% throughput ritkán szűk keresztmetszet |
| **Matrix (actor)** | Turbo | 0,006 mm² | 43% | Általános actor workload Matrix core-on |
| **Matrix (ML/SNN)** | **Systolic** | **0,001 mm²** | **7%** | Systolic pipeline: 128-bit link → MAC ~100% kihasználtság |
| **Rich** | Turbo | 0,006 mm² | 10% | A core elég nagy (0,059 mm²), a Turbo overhead elfogadható |

**Korrigált core-számok (5nm, 800 mm²):**

Az eredeti core-számok a [`core-types-hu.md`](core-types-hu.md)-ban `chipterület / (core + SRAM)` alapon számolódtak, fix hatékonysági faktorral, a per-core router terület explicit figyelembevétele nélkül. A korrigált számok tartalmazzák az ajánlott router variánst és az L1–L3 infrastruktúra per-core részét (~0,006 mm²):

| Core típus | Core+SRAM | Router | Infra | **Node** | **Szám** | Δ vs Turbo |
|------------|----------:|-------:|------:|---------:|---------:|--:|
| Nano (4 KB) | 0,008 | 0,003 | 0,006 | 0,017 | **~47 000** | — |
| Actor (64 KB) | 0,023 | 0,003 | 0,006 | 0,032 | **~25 000** | — |
| Matrix Turbo (8 KB) | 0,014 | 0,006 | 0,006 | 0,026 | **~30 800** | — |
| **Matrix Systolic (8 KB)** | **0,014** | **0,001** | **0,006** | **0,021** | **~38 100** | **+24%** |
| Rich (256 KB) | 0,059 | 0,006 | 0,006 | 0,071 | **~11 300** | — |

> **Megjegyzés:** A Systolic variáns +24%-kal több Matrix core-t tesz lehetővé a Turbo-hoz képest, a router 83%-os méretcsökkentésének köszönhetően. Minden szám szintézis előtti becslés.

### L1: Tile (crossbar, 8 cluster)

| Paraméter | Érték |
|-----------|-------|
| Topológia | 8×8 crossbar (VOQ + iSLIP) |
| Elhelyezés | A tile geometriai közepén |
| Fizikai méret | ~3.2 mm × 3.2 mm (5nm) |
| Link típus | Párhuzamos, 84 bit |
| Max távolság (GW → crossbar) | ~1.6 mm |
| Hop szám | Mindig 1 (determinisztikus) |
| Gate szám | ~16 000 |
| VOQ buffer | ~30 KB SRAM |

### L2: Régió (crossbar, 8 tile)

| Paraméter | Érték |
|-----------|-------|
| Topológia | 8×8 crossbar (VOQ + iSLIP) |
| Elhelyezés | A régió geometriai közepén |
| Fizikai méret | ~9 mm × 9 mm (5nm) |
| Link típus | Soros `SERDES_RATIO`×, `SERIAL_WIRES` vezeték + clock |
| Max távolság (tile GW → crossbar) | ~4.5 mm |
| Hop szám | Mindig 1 (determinisztikus) |
| Gate szám | ~16 000 |
| VOQ buffer | ~30 KB SRAM |

### L3: Chip (csillag, Seal Core + crossbar)

| Paraméter | Érték |
|-----------|-------|
| Topológia | Csillag — minden régió közvetlenül a központhoz |
| Elhelyezés | A chip geometriai közepén, a Seal Core-ral egyben |
| Fizikai méret | ~28 mm × 28 mm (5nm, 800 mm²) |
| Link típus | Soros `SERDES_RATIO`×, `SERIAL_WIRES` vezeték + clock |
| Max távolság (régió GW → közép) | ~14 mm |
| Hop szám | Mindig 2 (régió → közép → régió) |
| Gate szám | ~42 000 (crossbar) + ~200 000 (Seal Core) |
| VOQ buffer | ~77 KB SRAM |

## Seal Core elhelyezés

A Seal Core az L3 crossbar-ral együtt a chip **geometriai közepén** helyezkedik el. Ez az elhelyezés a **hálózati topológiából** következik, nem fizikai tamper-védelemből:

- **Minimális vezetékhossz:** a csillag topológia közepe minimalizálja a maximális távolságot bármelyik régió gateway-től (~14 mm 5nm-en), determinisztikus latenciát biztosítva.
- **Cross-régió ellenőrzési pont:** minden cross-régió forgalom áthalad az L3 crossbar-on, így a Seal Core biztonsági ellenőrzést végezhet (AuthCode verifikáció, forgalom-monitorozás) extra routing nélkül.
- **Egyetlen RTL példányosítás:** a Seal Core + L3 crossbar egyetlen paraméterezhető blokkot alkot a chip közepén — nincs szükség speciális elhelyezési logikára.

Az L3 crossbar-ral egyesítve minden cross-régió forgalom áthalad a Seal Core-on — biztonsági ellenőrzés lehetősége.

> **Megjegyzés a fizikai tamper-védelemről:** A középponti elhelyezés **nem** jelent fizikai védelmet mikroszondás, FIB, lézer fault injection vagy EM side-channel támadások ellen. A modern fizikai támadások (pl. backside FIB a szilícium szubsztráton át) a die bármely pontját elérhetik. A fizikai tamper-védelem dedikált ellenintézkedéseket igényel (aktív mesh shielding, feszültség/fény/frekvencia szenzorok, titkosított buszok) — ez egy külön tervezési réteg, jelenleg out-of-scope (lásd `docs/security-hu.md`, „Amit NEM védünk").

## Power domain-ek

Minden hierarchia-szinten önálló power domain — az alvó egységek fogyasztása ~0:

| Egység | Power state | Mikor alszik? | Wake trigger |
|--------|-----------|--------------|-------------|
| Core (Nano/Actor/Rich) | Per-core clock gating | Üres mailbox | Mailbox interrupt (cella érkezés) |
| Rich Core FPU | Külön power domain | Nincs FP művelet | FP opkód detektálása |
| Cluster (16 core) | Per-cluster power gating | Mind a 16 core alszik | Bármely core-nak érkező cella |
| Tile (L1 crossbar + clusterek) | Per-tile power gating | Mind a 8 cluster alszik | Bármely cluster-nek szóló cella |
| Régió (L2 crossbar + tile-ok) | Per-régió power gating | Mind a 8 tile alszik | Bármely tile-nak szóló cella |
| **L3 crossbar** | **Power-gated** | Nincs cross-régió forgalom | Bármely régió GW cross-régió cellát küld |
| **Seal Core** | **Power-gated** | Nincs kód betöltés | Kód-betöltési kérés (boot, hot code, migráció) |

A chip közepén **minden alhat** — az L3 crossbar és a Seal Core is power-gated, wake-on-demand. A crossbar ~40k gate statikus árama elenyésző, de ha nincs cross-régió forgalom, az is kikapcsolható.

## Seal Core kapacitás

A Seal Core két funkciót lát el: **kód hitelesítés** (ritka, de nehéz) és **L3 crossbar routing** (az L3 crossbar önállóan végzi, a Seal Core crypto engine-je nem dolgozik rajta).

### Kód hitelesítés terhelés

| Művelet | Mikor | Seal Core terhelés |
|---------|-------|--------------------|
| Boot (összes core kódja) | Egyszer, induláskor | ~128 MB hash = ~256 ms @ 500 MHz |
| Hot code loading | ~10/sec chip-szinten | ~160 KB/s = **<0.1%** kihasználtság |
| Aktor migráció | ~1-100/sec | Elhanyagolható |

### L3 crossbar skálázási korlát

| Core szám | Cross-régió forgalom | L3 crossbar kihasználtság | Bottleneck? |
|-----------|---------------------|--------------------------|-------------|
| 2 000 | ~2.5 GB/s | ~6% | Nem |
| 8 192 | ~10 GB/s | ~25% | Nem |
| 18 432 | ~23 GB/s | ~58% | Még nem |
A core szám növekedésével a cross-régió forgalom arányosan nő. 8 192 core-nál az L3 crossbar ~25%-os kihasználtsággal üzemel — jelentős headroom marad. Nagyobb chipeken (F6+) **2–64 Seal Core** lehet jelen redundancia és párhuzamos AuthCode verifikáció céljából (lásd [Seal Core](sealcore-hu.md)).

### L3 Crosspoint hibatűrés

Az L3 crossbar egy N×N iSLIP kapcsoló (N = `REGIONS`, jellemzően 8). Belül N² crosspoint-ból áll — minden crosspoint egyetlen bemenet→kimenet kapcsolat. Ha egy crosspoint meghibásodik, a kieső útvonal **egyetlen irányú kapcsolat** két régió között (pl. R2→R4), miközben az összes többi régiópár zavartalanul működik.

#### Hibamodell

```
        Kimenet (cél régió)
        R0  R1  R2  R3  R4  R5  R6  R7
Bemenet ┌───┬───┬───┬───┬───┬───┬───┬───┐
  R0    │ — │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │
  R1    │ ✓ │ — │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │ ✓ │
  R2    │ ✓ │ ✓ │ — │ ✓ │ ✗ │ ✓ │ ✓ │ ✓ │  ← R2→R4 crosspoint halott
  R3    │ ✓ │ ✓ │ ✓ │ — │ ✓ │ ✓ │ ✓ │ ✓ │
  ...
```

- **R2→R4** forgalom nem tud átmenni (halott crosspoint)
- **R4→R2** még működik (külön crosspoint)
- **Minden más régiópár** érintetlen
- Mitigáció nélkül: az R4-nek szánt cellák R2 VOQ-jában gyűlnek → backpressure → R2-ben lévő, R4-et célzó core-ok megakadnak

#### Mitigáció: relay szomszéd régión keresztül

Az iSLIP scheduler egy **fault bitmap**-et tart karban — crosspoint-onként 1 bit (N² = 64 bit 8 régió esetén). A bitmap induláskor BIST-tel (Built-In Self-Test) töltődik, vagy futás közben frissül, ha egy crosspoint nem válaszol a timeout-ablakon belül.

Ha a scheduler észleli, hogy a közvetlen crosspoint hibásnak van jelölve, **relay**-t hajt végre:

```
R2 ─╳→ R4           (közvetlen útvonal — halott crosspoint)
R2 → R3 → L3 → R4   (relay: R3 köztes hop-ként működik)
```

**Relay mechanizmus:**

1. A scheduler egy **alternatív kimeneti portot** (a relay régiót) választ egy előre számított relay-táblából
2. A cellát a relay régió GW-jéhez továbbítja, a header reserved bitjeiben beállított **relay flag**-gel
3. A relay régió GW visszainjektálja a cellát az L3 crossbar-ba az eredeti cél felé
4. A cél régió normálisan fogadja a cellát — a relay a core-ok számára transzparens

**Relay régió kiválasztás:** A scheduler azt a relay régiót választja, amelynek működik a crosspoint-ja a forrásból ÉS a célba. 8 régió és 1 halott crosspoint esetén mindig 6 érvényes relay-jelölt van.

#### Költségelemzés

| Komponens | Gate költség | SRAM költség | Megjegyzés |
|-----------|-------------|--------------|------------|
| Fault bitmap regiszter | ~130 gate | — | 64 FF + olvasó logika |
| Relay tábla (előre számított) | ~200 gate | — | 8×3 bites best-relay LUT |
| Scheduler módosítás | ~300 gate | — | Bitmap ellenőrzés + relay útvonal kiválasztás |
| Header relay flag | 0 | 0 | 1 reserved bitet használ (40 elérhető) |
| **Összesen** | **~630 gate** | **0** | **< 1.5% az L3 crossbar-ból** |

#### Teljesítmény hatás

| Szcenárió | Latency | Throughput |
|-----------|---------|------------|
| Nincs hiba | 2 hop (változatlan) | 100% |
| 1 crosspoint hiba, relay-zve | 4 hop (forrás→relay→közép→cél) | ~50% az érintett párra, 100% az összes többire |
| Több hiba | Graceful degradation — minden hibás pár relay-t használ | Throughput csökkenés a relay forgalommal arányos |

A relay 2 extra crossbar-áthaladást ad az érintett régiópárnak. Tipikus cross-régió terhelésnél (~25% kihasználtság) még több relay-zett pár sem telíti a crossbar-t.

#### Detekció: crosspoint állapotfigyelés

- **Boot-time BIST:** minden crosspoint-ot ismert mintával tesztel; a hibák a fault bitmap-be kerülnek a normál működés megkezdése előtt
- **Runtime watchdog:** ha egy crosspoint-nak kiosztott cella 4 cikluson belül nem produkál kimenet-oldali nyugtát, a crosspoint hibásnak jelölődik és a jövőbeli cellák relay-ződnek
- **Seal Core értesítés:** crosspoint hibákat diagnosztikai eseményként jelenti a Seal Core-nak (naplózva, opcionálisan chip-en kívülre továbbítva management interfészen)

## Kód betöltés a hálózaton

A kommunikációs hálózat nem csak aktor-üzeneteket visz — a **program kód** is ezen az úton jut el a core SRAM-ba. Három szcenárió:

| Szcenárió | Méret | Mikor | Útvonal |
|-----------|-------|-------|---------|
| **Boot** | Teljes program, KB-MB | Rendszerindítás | Flash → Seal Core (AuthCode verify) → L3 → L2 → L1 → broadcast minden core-ra |
| **Hot code loading** | 1 metódus, 256B-16KB | Futás közben | Flash/Rich Core → Seal Core (re-auth) → célzott core |
| **Aktor migráció** | Aktor state + kód, KB | Futás közben | Forrás core → Seal Core (re-auth) → cél core |

**Minden kód a Seal Core-on megy át** — nem hitelesített kód nem juthat core-ra. A csillag topológia ezt ingyen biztosítja: a Seal Core az L3 crossbar közepe, minden cross-régió forgalom áthalad rajta.

A kód betöltés normál 80 byte-os cellás forgalom a VN0 (control) csatornán. Egy 16 KB-os metódus = ~256 cella (64 byte payload cellánként); a pipeline throughput-ot a legszűkebb link korlátozza (L0, 42 bit @ 500 MHz = ~2.6 GB/s). Worst-case kézbesítés: ~8 µs @ 500 MHz.

## Quench-RAM integráció a hálózattal

A [Quench-RAM](quench-ram-hu.md) memória-biztonsági réteg és a packet-switched hálózat **egymást erősítik**. A shared-nothing modell miatt a QRAM invariánsát nem kell a hálózaton keresztül szinkronizálni — minden core a saját QRAM-ját kezeli lokálisan.

### Üzenetküldés (SEND) — QRAM szemantikával

```
SEND(dst_actor, payload_block):
  1. SEAL(payload_block)            ← payload immutable lesz (forrás core QRAM)
  2. Másolás → 80B cella(k)         ← a hálózatra kerül (wormhole L0-n, VCT crossbar-okon)
  3. Cellák → router → ... → cél core SRAM
  4. Cél core: blokk allokáció      ← QRAM: guaranteed zero-init (RELEASE invariáns)
  5. Cella tartalom → új blokk      ← cél core QRAM-ban
  6. Forrás: GC_SWEEP → RELEASE     ← atomi wipe, régi adat fizikailag megsemmisül
```

| Fázis | Forrás core QRAM | Hálózat | Cél core QRAM |
|-------|-----------------|---------|---------------|
| Küldés előtt | Mutable (aktor írja) | — | — |
| SEAL trigger | **Immutable** → nem változhat küldés közben | — | — |
| Hálózaton | — | Wormhole (L0) / VCT (crossbar) cellák, másolat | — |
| Megérkezés | — | — | Allokáció: **guaranteed zero** (RELEASE invariáns) |
| Feldolgozás | — | — | **SEAL** (capability tag tamper-proof) |
| GC | **RELEASE** → atomi wipe | — | — |

### Kód betöltés — QRAM szemantikával

```
Flash → Seal Core (AuthCode verify) → hálózat → cél core CODE régió → SEAL

CODE régió SEAL után IMMUTABLE:
  → self-modifying code fizikailag lehetetlen
  → hot_code_loader: RELEASE (atomi wipe) → új kód betöltés → SEAL
```

### Miért erősítik egymást?

- **Forrás oldal:** SEAL garantálja, hogy a küldött adat nem változik a másolás közben
- **Cél oldal:** RELEASE invariáns garantálja a zero-init-et — nincs information leak az előző használatból
- **Hálózat:** csak cellák, nincs pointer, nincs shared state → a QRAM invariáns **nem sérülhet** a transzfer során
- **Kód:** SEAL-elt CODE régió immutable → a futó kód nem módosítható, hot code loading RELEASE-szel atomi csere

A shared-nothing hálózati modell és a Quench-RAM **szimbiózisban** vannak: pont azért működik a QRAM lokálisan (per-core), mert a hálózat másolatot visz, nem pointert.

## Virtual Network (VN)

2 VN a forgalom izolálására:

| VN | Név | Forgalom | Prioritás |
|----|-----|----------|-----------|
| **VN0** | Control | Supervisor restart, trap signal, heartbeat, rendszer broadcast | Legmagasabb — preemptív |
| **VN1** | Actor | Normál aktor üzenetváltás, adatforgalom | Normál |

A VN0 garantálja, hogy a supervisor üzenetek **soha nem várnak** normál forgalom mögött.

## Multicast

HW multicast **csak a cluster gateway-ekben** (L1 crossbar-ban, nem minden L0 routerben). Supervisor restart és SNN fan-out hatékony: 1 multicast csomag = 1 cluster összes core-ja értesítve, ~5 ciklus (vs N×unicast = ~192 ciklus).

**Költség:** +2 500 gate × (CLUSTERS_PER_TILE × TILES_PER_REGION × REGIONS) gateway = elhanyagolható chip-szinten.

## Link típusok

| Szint | Típus | Vezetékek | Órajel | Sávszélesség |
|-------|-------|-----------|--------|-------------|
| L0 Turbo/Compact | Párhuzamos | 42 bit (egyirányú) | 1× core | ~2,6 GB/s |
| **L0 Systolic** | **Párhuzamos** | **128 bit (egyirányú, 2 irány)** | **1× core** | **~8 GB/s** |
| L1 (cluster → tile xbar) | Párhuzamos | 84 bit (kétirányú) | 1× core | ~5,2 GB/s |
| L2 (tile → régió xbar) | Soros | `SERIAL_WIRES` vez. + clock | `SERDES_RATIO`× core | lásd SerDes skálázás |
| L3 (régió → chip xbar) | Soros | `SERIAL_WIRES` vez. + clock | `SERDES_RATIO`× core | lásd SerDes skálázás |

## SerDes skálázás

Az L2/L3 soros linkek on-chip SerDes-t használnak konfigurálható szorzóval (`SERDES_RATIO`). A maximális megvalósítható szorzó a core órajeltől függ — magasabb órajel alacsonyabb szorzót igényel, hogy a SerDes frekvencia a szilícium korlátain belül maradjon.

**Korlát:** az on-chip SerDes IP 5nm-en jellemzően ~25–32 Gbps/lane-ig támogat. A SerDes frekvencia = core_clock × `SERDES_RATIO` e határ alatt kell maradjon.

| Core órajel | Max `SERDES_RATIO` | Ajánlott konfig | Effektív L2/L3 link szélesség | L2/L3 szerializáció |
|------------|-------------------|-----------------|-------------------------------|---------------------|
| 500 MHz | 12 | 10×, 8 vez. | 80 bit/cc | 8 cc |
| 1 GHz | 10 | 8×, 8 vez. | 64 bit/cc | 10 cc |
| 2 GHz | 8 | 6×, 8 vez. | 48 bit/cc | 14 cc |
| 3 GHz | 6 | 4×, 12 vez. | 48 bit/cc | 14 cc |
| 5 GHz | 4 | 4×, 16 vez. | 64 bit/cc | 10 cc |

**Kompenzációs stratégia:** magasabb core órajelnél csökkentjük a `SERDES_RATIO`-t és növeljük a `SERIAL_WIRES`-t az effektív link sávszélesség megtartásához. A `SERDES_RATIO × SERIAL_WIRES` szorzat határozza meg az effektív bit/core-ciklus értéket; a referencia cél **80 bit/cc**.

### `SERIAL_WIRES` skálázás területi hatása

A `SERIAL_WIRES` növelése 8-ról 16-ra nem ingyenes — mérhető terület- és routing-következményekkel jár:

| Komponens | 8 vez. (ref) | 12 vez. | 16 vez. | Megjegyzés |
|-----------|-------------|---------|---------|-----------|
| SerDes transceiver (link végpontonként) | ~3 000 GE | ~4 500 GE | ~6 000 GE | PLL közös, de CDR/EQ/driver lane-enként |
| L2 crossbar I/O mux | ~15 000 GE | ~18 000 GE | ~21 000 GE | Szélesebb input/output portok |
| L3 crossbar I/O mux | ~40 000 GE | ~48 000 GE | ~56 000 GE | Azonos skálázás |
| Fizikai vezetékek (L3, ~14 mm) | 8 × 2 = 16 vez. | 12 × 2 = 24 | 16 × 2 = 32 | Kétirányú; fémréteg routing nyomás |
| Fizikai vezetékek (L2, ~4.5 mm) | 16 vez. | 24 | 32 | Rövidebb, kevésbé kritikus |

**Chip-szintű hatás 16 vezetéknél (`SERIAL_WIRES`=16):**
- L2 crossbar terület: +~40% (+6 000 GE × 8 tile/régió)
- L3 crossbar terület: +~40% (+16 000 GE, egyetlen példány)
- Vezeték routing: az L3 linkek 32 vezetéket visznek ~14 mm-en — 5nm-en megvalósítható (fém pitch ~20 nm, teljes vezetékköteg ~0,64 µm széles), de regionálisan 1–2 dedikált fémréteget foglal
- **Teljes chip terület-növekedés: <1%** — a crossbar infrastruktúra eleve a die terület kis hányada (~2–3%)

A területi költség pont azért elfogadható, mert az L2/L3 crossbar infrastruktúra több ezer core-ra amortizálódik. A domináns terület továbbra is a core SRAM.

> **L3 vezetékhossz korlát:** az L3 link akár ~14 mm (5nm). 50 GHz-en (5 GHz × 10×) a vezeték terjedési késleltetés önmagában ~2–3 ns ≈ 100–150 bit-idő, ami többlépcsős retiming-et igényel. A SerDes frekvencia ≤ 20 GHz tartása elkerüli ezt a komplexitást.

## Hop-szám és latencia összefoglaló

A latenciák a **referencia konfigurációra** vonatkoznak (500 MHz, `SERDES_RATIO`=10, `SERIAL_WIRES`=8, effektív L2/L3 = 80 bit/cc), teljes 80 byte-os cellára, nulla torlódás mellett. Magasabb core órajel az illesztett SerDes paraméterekkel hasonló ciklusszámot eredményez (lásd SerDes skálázás).

**L0 wormhole modell:** 2 ciklus/hop router pipeline + 15 body flit drain = 2H + 15 ciklus H hop esetén.
**Crossbar VCT modell:** link szerializáció (⌈640 bit / link_szélesség⌉ ciklus) + 1 ciklus iSLIP crossbar-onként. A kimenő szerializáció átfed a következő szint bemenetével.

| Útvonal | Hop | Latencia | @500 MHz |
|---------|-----|---------|----------|
| Szomszéd core (L0) | 1 | ~17 ciklus | 34 ns |
| Cross cluster, azonos tile (L0+L1+L0) | 6+1+6 = 13 | ~63 ciklus | 126 ns |
| Cross tile, azonos régió (L0+L1+L2+L1+L0) | 6+1+1+1+6 = 15 | ~99 ciklus | 198 ns |
| Cross régió (L0+L1+L2+L3+L2+L1+L0) | 6+1+1+2+1+1+6 = 18 | ~139 ciklus | 278 ns |

> **Kontextus:** a worst-case ~280 ns on-chip versenyképes a hagyományos CPU-kon futó szoftver aktor üzenetküldéssel (Erlang/BEAM: ~0.5–2 µs), miközben a CFPU-ban több ezer független hardver core dolgozik párhuzamosan.

<details>
<summary>Cross-régió latencia részletezés (18 hop)</summary>

| Szegmens | Link szélesség | Ciklus | Megjegyzés |
|----------|---------------|--------|-----------|
| Forrás L0 wormhole (6 hop) | 42 bit | 27 | 2×6 + 15 body drain |
| L1 link (GW → xbar) | 84 bit | 8 | ⌈640/84⌉ |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link (xbar → tile GW) | 84 bit | 8 | |
| L2 link (tile GW → xbar) | 80 bit | 8 | ⌈640/80⌉ |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link (xbar → régió GW) | 80 bit | 8 | |
| L3 link (régió GW → xbar) | 80 bit | 8 | |
| L3 crossbar (iSLIP) | — | 1 | |
| L3 link (xbar → cél régió GW) | 80 bit | 8 | |
| L2 link → xbar | 80 bit | 8 | |
| L2 crossbar (iSLIP) | — | 1 | |
| L2 link → cél tile GW | 80 bit | 8 | |
| L1 link → xbar | 84 bit | 8 | |
| L1 crossbar (iSLIP) | — | 1 | |
| L1 link → cél cluster GW | 84 bit | 8 | |
| Cél L0 wormhole (6 hop) | 42 bit | 27 | 2×6 + 15 body drain |
| **Összesen** | | **139** | |

</details>

## Node-skálázás

Az RTL paraméterezhető — a chipméret és a gyártási technológia határozza meg a core számot:

**A) Növekvő SRAM (gazdagabb aktorok, kevesebb core):**

| Node | Core méret | SRAM/core | 800 mm² | 1 400 mm² | Szintek |
|------|-----------|-----------|---------|----------|---------|
| 130nm | 1.06 mm² | 16 KB | 588 | 1 030 | 2 |
| 28nm | 0.18 mm² | 64 KB | 3 467 | 6 067 | 3 |
| 7nm | 0.083 mm² | 256 KB | 7 518 | 13 157 | 4 |
| **5nm (ref)** | **0.103 mm²** | **512 KB** | **6 058** | **10 602** | **4** |

**B) Fix 256 KB SRAM (maximális párhuzamosság):**

| Node | Core méret | SRAM/core | 800 mm² | 1 400 mm² | Szintek |
|------|-----------|-----------|---------|----------|---------|
| 130nm | 2.93 mm² | 256 KB | 213 | 373 | 2 |
| 28nm | 0.37 mm² | 256 KB | 1 686 | 2 951 | 3 |
| 7nm | 0.083 mm² | 256 KB | 7 518 | 13 157 | 4 |
| **5nm (ref)** | **0.059 mm²** | **256 KB** | **10 576** | **18 508** | **4** |

A döntés a workload-tól függ — az RTL `SRAM_KB_PER_CORE` paramétere gyártáskor állítható.

A worst-case latencia ~100–139 ciklus tartományban marad (~200–278 ns @ 500 MHz) minden node-on — a kisebb cluster fizikai méret a fejlettebb node-okon részben kompenzálja a mélyebb hierarchiát.

## Kizárt alternatívák (és indoklás)

| Alternatíva | Miért kizárva |
|-------------|--------------|
| Shared memory / zero-copy cell pool | Biztonsági rés — pointer-manipuláció, side-channel, isolation sértés |
| Adaptív routing (2 VC) | ~800 core-ba kerül, a latencia javulás nem kompenzálja |
| In-network computation | 44% router terület, a core szám felére csökken |
| Fat tree (tiszta) | Bottleneck és SPOF a gyökéren; horizontális linkekkel konvergál a hierarchikus mesh-hez |
| Dragonfly | On-chip all-to-all vezetékigény ~12× a mesh-é — irreális |
| Flat mesh (10k node) | Max ~200 hop — elfogadhatatlan latencia |
| Teljes wormhole (minden szinten) | Láncos buffer-foglalás a crossbar szinteken; L0-n használjuk, ahol az XY routing aciklikus csatornákat garantál |
| 3+ VN | Extra buffer terület nem éri meg a marginal QoS javulást |

## OSREQ kereszthivatkozások

Ez a dokumentum az alábbi Neuron OS hardware requirement-ekre válaszol:

| OSREQ | Téma | Státusz |
|-------|------|---------|
| [OSREQ-001](osreq-from-os/osreq-001-tree-interconnect-hu.md) | Interconnect topológia | **Lezárva**: 4-szintű hierarchikus mesh + crossbar |
| [OSREQ-004](osreq-from-os/osreq-004-dma-engine-hu.md) | DMA engine | Kötelező F4-től (nagy üzenetek, actor state transfer) |
| [OSREQ-005](osreq-from-os/osreq-005-mailbox-interrupt-hu.md) | Mailbox interrupt | HW interrupt, a cella-érkezés triggereli |

## Kapcsolódó dokumentumok

- [Quench-RAM](quench-ram-hu.md) — per-blokk immutability, atomi wipe-on-release, QRAM+hálózat szimbiózis
- [AuthCode](authcode-hu.md) — kód-hitelesítés, a Seal Core ellenőrzi minden betöltött kód aláírását
- [Architektúra](architecture-hu.md) — a teljes CFPU mikroarchitektúra áttekintés
- [ISA-CIL-T0](ISA-CIL-T0-hu.md) — a CIL-T0 utasításkészlet specifikáció

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 2.3 | 2026-04-21 | L3 Crosspoint hibatűrés szekció: fault bitmap (64-bit), relay szomszéd régión keresztül (~630 gate, <1,5% overhead), BIST + runtime watchdog detekció, graceful degradation modell |
| 2.2 | 2026-04-21 | Referencia node 7nm→5nm váltás. Újraszámolva: router területek (Turbo 0,006, Compact 0,003), core+SRAM méretek, korrigált core-számok (Nano ~47k, Actor ~25k, Matrix Turbo ~30,8k, Matrix Systolic ~38,1k, Rich ~11,3k), fizikai méretek (L0 1,1mm, L1 3,2mm, L2 9mm, L3 28mm), Seal Core vezetékhossz 14mm. Referencia konfig: 16×8×8×10 = 10 240 core |
| 2.1 | 2026-04-19 | Systolic router variáns (Variáns C): 128-bites egyirányú linkek (W→E, N→S), ~5 000 GE ≈ 0,001 mm², ML/SNN dedikált. Sebesség tábla, ajánlott variáns tábla, korrigált core-számok és link típusok frissítve |
| 2.0 | 2026-04-19 | Cella payload 128→64 byte (cella méret 144→80 byte). 16 flit/cella, 2H+15 latencia modell, L1 8cc, L2/L3 8cc szerializáció, cross-régió 139 ciklus (278 ns). Router gate számok, VOQ SRAM, core-számok újraszámolva. CELL_SIZE tartomány: 64/128. Turbo: 0,007 mm², Compact: 0,004 mm² |
| 1.9 | 2026-04-19 | Cella header 8→16 byte (128-bit, 2-hatvány). Cella méret 136→144 byte. Összes származtatott érték újraszámolva: 28 flit/cella, 2H+27 latencia modell, L1 14cc, L2/L3 15cc szerializáció, cross-régió 229 ciklus (458 ns). VOQ SRAM és gate számok frissítve |
| 1.8 | 2026-04-19 | Címzés módosítva: actor mező eltávolítva a HW címből, szoftveres dispatch a payload-on keresztül. Kereszthivatkozás az Architektúra Actor Scheduling Pipeline szekcióra |
| 1.7 | 2026-04-19 | SerDes skálázás szekció: `SERDES_RATIO` + `SERIAL_WIRES` konfigurálható paraméterek, órajel-függő szorzó tábla (500 MHz–5 GHz), L3 vezetékhossz korlát, kompenzációs stratégia. L2/L3 link specifikációk paraméterezve |
| 1.6 | 2026-04-19 | L0 Router variánsok: Turbo (sebesség-első, 0,009 mm²) és Compact (terület-első, 0,005 mm²), core típusonkénti ajánlással. Korrigált core-számok router területtel. Frissített 2. tervezési alapelv és L0 Cluster paraméterek |
| 1.5 | 2026-04-19 | Switching modell korrigálva: hibrid wormhole (L0) + VCT (L1–L3) a tiszta store-and-forward helyett. Latencia tábla újraszámolva szerializációs matematikával (42 bit L0 = 28 flit/cella). Deadlock-mentesség érvelés frissítve (Dally & Seitz 1987, wormhole + XY). Cross-régió részletező tábla hozzáadva |
| 1.4 | 2026-04-18 | Matrix Core újradefiniálva: CIL-T0 + FP alapú (nem Rich/Actor), nincs GC, nincs objektummodell, nincs kivételkezelés, nincs virtuális dispatch. Core méretek frissítve (Matrix logic: 0.019 mm²), két Matrix sor (64KB/256KB), CFPU-ML termékváltozat hozzáadva, elágazási diagram |
| 1.3 | 2026-04-18 | Matrix Core hozzáadva (5. core típus: Nano + FPU + 4×4 MAC + SFU), CFPU-ML termékváltozat, CORE_TYPE=MATRIX |
| 1.2 | 2026-04-18 | Core család (Nano/Actor/Rich/Seal), termékcsalád (CFPU-N/A/R/H/X), power domain-ek, Seal Core kapacitás |
| 1.1 | 2026-04-18 | Kód betöltés és Quench-RAM integráció szekciók hozzáadva |
| 1.0 | 2026-04-18 | Kezdeti verzió — 4-szintű hierarchia, mesh+crossbar hibrid, Seal Core közép, node-skálázás |
