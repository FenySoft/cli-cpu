# Seal Core — A CFPU hitelesítési gatekeeper magja

> English version: [sealcore-en.md](sealcore-en.md)

> Version: 1.0

Ez a dokumentum a **Seal Core** komponenst írja le: egy dedikált, egyszerű, hardware-burned firmware-rel működő core-t, ami a CFPU chipen a **kódbetöltés hitelességét** biztosítja. A Seal Core két különböző mechanizmussal működik a CFPU fejlesztési fázisától függően — **pre-QRAM érában** (F3-F5) fizikai WE-pin routing révén, **QRAM érában** (F5+) AuthCode verifikációs gatekeeper szerepben. Ez a két megközelítés **külön mechanizmus**, amelyeket ez a doksi tudatosan szétválasztva tárgyal.

> **Vízió-szintű dokumentum.** A Seal Core F3-tól jelen van a CFPU-ban, és végig megmarad a chip-generációkon. Szerepe azonban **fundamentálisan másként áll** pre-QRAM vs. post-QRAM kontextusban, ezért a doksi két külön szekcióban tárgyalja a kettőt, explicit átmeneti pont-megjelöléssel.

## Tartalom

1. [Motiváció](#motivacio)
2. [Mi a Seal Core](#mi-a-sealcore)
3. [Kapcsolódás a CFPU brand-családfához](#brand)
4. [Általános architektúra](#architektura)
5. [Seal Core a pre-QRAM érában (F3-F5)](#preqram)
6. [Seal Core a QRAM érában (F5+)](#qram)
7. [Az átmeneti pont](#atmenet)
8. [Boot és firmware immutability](#boot)
9. [Többszörözés és graceful degradation](#redundancia)
10. [Gyorsító funkciók](#gyorsitok)
11. [Biztonsági garanciák](#biztonsag)
12. [Nyitott kérdések](#nyitott)
13. [F-fázis bevezetés](#fazisok)
14. [Referenciák](#referenciak)
15. [Changelog](#changelog)

## Motiváció <a name="motivacio"></a>

A CFPU biztonsági modellje (`docs/security-hu.md`, `docs/authcode-hu.md`) egyetlen kritikus állítást tesz:

> Csak hitelesített, ellenőrzött CIL kód kerülhet végrehajtásra.

Ez a garancia **egy hardveres kaput** feltételez, amelyen minden belépő kód átmegy. A kapu:
- **Megbízható**: saját firmware-e hardveres szinten rögzített (mask ROM vagy eFuse), nem tamperelhető
- **Izolált**: a kapu saját kódja és működése nem elérhető más core-ok számára
- **Dedicált**: kizárólag a hitelesítés és a kódbetöltés vezérlése a feladata, nem futtat alkalmazás-aktorokat

Ez a komponens a **Seal Core**. Egy minimális, egyszerű, audit-barát core, ami a CFPU-ra érkező bytecode-ok hitelességét kikényszeríti.

## Mi a Seal Core <a name="mi-a-sealcore"></a>

A Seal Core egy **harmadik core-kategória** a CFPU-ban, a Nano és Rich core-ok mellett:

| Attribútum | Nano Core | Rich Core | **Seal Core** |
|-----------|-----------|-----------|----------------|
| CIL futtatás | subset CIL-T0 | teljes CIL + GC + FP | kizárólag belső firmware |
| Megjelenési fázis | F3+ | F6+ | **F3+** (legkorábbi) |
| Programozható alkalmazás-kóddal | igen | igen | **nem** (kódja hardveresen rögzített) |
| SRAM | 16 KB | 256 KB | 64 KB (trusted zóna) |
| SHA-256 + WOTS+ acceleratorok | nem | nem | **igen** (dedikált HW) |
| Több példány a chipen | 10-100 | 1-16 | **1 vagy több** (redundancia) |
| Boot | aláírt CIL betöltés | aláírt CIL betöltés | **immutable mask ROM / eFuse** |

A Seal Core **nem fut alkalmazás-kódot**. A saját firmware-e hardveresen beégetett (mask ROM vagy nagy megbízhatóságú eFuse tömb), és **kizárólag** a következő funkciókat látja el:

- **Boot-idő self-test** (induláskor ellenőrzi saját integritását)
- **AuthCode verifikáció** — bejövő `.acode` konténerek aláírás-ellenőrzése (lásd `docs/authcode-hu.md`)
- **Code-loader feladatok** — ellenőrzött bytecode beírása a CODE régióba
- **Heartbeat jel** egy központi health monitor-nak (redundancia-célra)

## Kapcsolódás a CFPU brand-családfához <a name="brand"></a>

A Seal Core beilleszkedik a CFPU komplementer biztonsági mechanizmusok családjába:

```
               ┌───────────────────────────────────────────┐
               │              CFPU biztonsági család       │
               └───────────────────────────────────────────┘
                                    │
       ┌────────────────┬───────────┼───────────┬───────────────┐
       │                │           │           │               │
  [Quench-RAM]    [AuthCode]   [CodeLock]   [Seal Core]   [Symphact
   memóriacella   kód-aláírás   runtime W⊕X   gatekeeper    HSM Card]
                                              core          crypto + signing
```

A Seal Core az a **fizikai komponens**, amelyik a többi mechanizmust **gyakorlatilag aktiválja**:
- Az **AuthCode** verifikációs flow itt fut
- A **CodeLock** W⊕X kényszerítés (pre-QRAM érában) itt származik a WE-pin routing-ból
- A **Quench-RAM** CODE régió SEAL HW-triggerét itt indítják

## Általános architektúra <a name="architektura"></a>

A Seal Core belső komponensei (bármelyik fázisban azonos):

```
┌──────────────────────────────────────────────────────────┐
│                       Seal Core                          │
│                                                          │
│  ┌────────────────┐    ┌────────────────────────────┐    │
│  │  Boot firmware │    │  SRAM (64 KB trusted zone) │    │
│  │  mask ROM /    │    │  - AuthCode verify stack   │    │
│  │  immutable     │    │  - Session state           │    │
│  │  eFuse         │    │  - Revocation list cache   │    │
│  └────────┬───────┘    └────────────────┬───────────┘    │
│           │                             │                │
│           ▼                             ▼                │
│  ┌──────────────────────────────────────────────────┐    │
│  │    Simple CPU core (CIL-Seal ISA — F5)           │    │
│  │    - 5-stage in-order pipeline                   │    │
│  │    - 16 register file                            │    │
│  └────────────┬─────────────────────────────────────┘    │
│               │                                          │
│   ┌───────────┼───────────┬────────────────┐             │
│   ▼           ▼           ▼                ▼             │
│ [SHA-256  ][WOTS+    ][Merkle path  ][Heartbeat          │
│  HW unit ][ verifier][  verifier   ][  output pin]       │
│                                                          │
│   ┌───────────────────┐                                  │
│   │ Output interface  │ ─── különböző érában különböző   │
│   │ (CODE RAM access) │    (lásd lent)                   │
│   └───────────────────┘                                  │
└──────────────────────────────────────────────────────────┘
```

Az **"Output interface"** az egyetlen rész, ami fázisonként **érdemben változik** — a többi (firmware, SRAM, SHA-256 HW, verifier-ek) minden érában azonos.

## Seal Core a pre-QRAM érában (F3-F5) <a name="preqram"></a>

A pre-QRAM éra az F3 Tiny Tapeout-tól az F5 RTL prototípusig tart. Ebben a fázisban a CODE RAM **külső kereskedelmi SRAM chip**, aminek egyetlen WE pinje van. A védelem **a fizikai pin-routing-ból** származik.

### Az alapelv — defense by topology

> **A CODE RAM chip WE pinje csak a Seal Core-ig van huzalozva a CFPU chipen belül. Más core-nak (Nano, Rich) nincs vezetéke a WE-hez.**

Ez **nem konfigurálható**, nem bypass-olható szoftveresen. Megkerülni csak FIB-attack-kel lehet (szilícium átrajzolása), ami a threat model-en kívül esik.

### A fizikai topológia

```
        ┌────────────────────────────────────────────────┐
        │                  CFPU CHIP                     │
        │                                                │
        │  [Seal Core]   [Nano][Nano]...[Rich][Rich]     │
        │      │              │   │        │   │         │
        │      │              └───┴────────┴───┘         │
        │      │                    │                    │
        │      │              CODE read bus              │
        │      │              (megosztott, csak OE)      │
        │      │                    │                    │
        │      │                    │                    │
        │      │  CODE write bus (saját)                 │
        │      └───────────────────┐│                    │
        │                          ││                    │
        │                CODE RAM pins (WE + OE + adat)  │
        └──────────────────────────┬┬────────────────────┘
                                   ││
                          ┌────────┴┴────────┐
                          │  CODE RAM chip   │  (külső commercial SRAM)
                          └──────────────────┘
                                   
                                   
        ┌────────────────────────────────────────────────┐
        │                  CFPU CHIP                     │
        │                                                │
        │  DATA bus (minden core, WE is bárki)           │
        │                          │                     │
        │                DATA RAM pins (WE, OE, ...)     │
        └──────────────────────────┬─────────────────────┘
                                   │
                          ┌────────┴────────┐
                          │  DATA RAM chip  │  (külön chip)
                          └─────────────────┘
```

**Kritikus:** a CODE és DATA külön fizikai chipen van. Ez elkerülhetetlen a pre-QRAM érában, mert egy kereskedelmi RAM chipnek **egy WE pinje** van — és ezt vagy teljesen Seal-restricted, vagy nem.

### Egy WE pin → több CODE RAM chip (fan-out)

**Kulcs észrevétel:** egy Seal Core **egyetlen WE kimenete** standard bus-fan-out technikával **tetszőleges számú CODE RAM chip WE-jére** csatlakozhat. A címzés (memory map) dönti el, melyik RAM chip reagál az adott írási ciklusra — pontosan úgy, ahogy minden hagyományos embedded rendszerben működik.

Például egy 4-RAM-chipes konfigurációban:

| RAM chip | Címtartomány |
|----------|---------------|
| CODE RAM 1 | 0x0000 – 0x1FFF |
| CODE RAM 2 | 0x2000 – 0x3FFF |
| CODE RAM 3 | 0x4000 – 0x5FFF |
| CODE RAM 4 | 0x6000 – 0x7FFF |

A Seal Core egyetlen WE pinje mind a négy RAM WE-jére rákapcsol (párhuzamosan), a CS (Chip Select) jelek pedig standard címdekódolásból származnak. Amikor a Seal Core a 0x2500 címre ír, csak a CODE RAM 2 CS-je aktív → csak az ír. A többi RAM WE-jelét fogadja, de CS nélkül figyelmen kívül hagyja.

```
           CFPU CHIP                                   külső RAM chipek
┌──────────────────────────────┐
│  [Seal Core] ─WE ─┐          │                ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│                   ├── fan-out ──── WE bus ──> │ WE  │ │ WE  │ │ WE  │ │ WE  │
│  [Nano][Rich]...  │          │                │     │ │     │ │     │ │     │
│  (Nano/Rich: no   │ ADDR bus ──────────────>  │ RAM │ │ RAM │ │ RAM │ │ RAM │
│   WE vezeték)     │ DATA bus ──────────────>  │  1  │ │  2  │ │  3  │ │  4  │
│                   │          │                │0x000│ │0x200│ │0x400│ │0x600│
│                   │ CS decode ─────────────>  │ CS  │ │ CS  │ │ CS  │ │ CS  │
│                   │          │                └─────┘ └─────┘ └─────┘ └─────┘
└──────────────────────────────┘
```

A Nano/Rich core-ok WE-vezetékei **fizikailag nincsenek** bekötve egyetlen RAM chiphez sem — csak a Seal Core WE-je. Tehát **olvasni tudnak** (cím + OE jelek elérhetők nekik), **írni nem**.

### Redundancia több Seal Core-ral — ugyanolyan egyszerű

Több Seal Core esetén mindegyik WE kimenete a **közös WE bus-ra** kapcsolódik. Kis on-chip arbiter logika kezeli, hogy egy órajel-ciklusban csak egy Seal Core hajtsa a bust (tri-state vagy MUX):

```
[Seal Core 1] ─WE─┐
[Seal Core 2] ─WE─┤
[Seal Core 3] ─WE─┼──> arbiter ──> közös WE bus ──> minden CODE RAM
[Seal Core 4] ─WE─┘    (Seal Core-ok között)
```

A memory map szoftveresen (a Seal Core firmware-ben) osztja fel, melyik Seal Core melyik címtartomány felé dolgozik. Nem kell **semmilyen** extra hardver a RAM chipeken — azok standard commodity SRAM-ok maradnak, nincs "WE-kapcsoló" bennük.

Ha egy Seal Core meghal, a szomszéd egyszerűen átveszi a címtartományát — a WE-je amúgy is rá volt kötve az egész bus-ra. A takeover hardveresen **triviális**.

### Korlátok a pre-QRAM érában

A korlát **nem a WE-pin vagy a board-komplexitás**, mert a WE fan-outolható és a címzés a standard memory decode:

- **Címtér-méret:** a CFPU CODE címtere véges, ezen belül fér el a RAM chipek összessége
- **Külső RAM chipek darabszáma:** PCB és board-tervezés szerinti gyakorlati határok (de nem WE-pinek miatt)
- **Seal Core mint egység költsége:** minden Seal Core saját SHA-256 + WOTS+ HW-vel jár — a gyártási költség határozza meg a reális darabszámot

### Gyakorlati konfigurációk

| Fázis | Seal Core szám | CODE RAM chipek | Redundancia |
|-------|----------------|------------------|-------------|
| F3 Tiny Tapeout | 1 | 1 | nincs |
| F5 RTL prototípus | 1-2 | 1-2 | minimális |
| F6 ChipIgnite (pre-QRAM) | 2-4 | 1-4 | WE-bus + arbiter, szabad title takeover |

A több-Seal-Core redundancia pre-QRAM érában **ugyanolyan olcsó**, mint QRAM érában lesz — a standard bus-tervezés miatt.

## Seal Core a QRAM érában (F5+) <a name="qram"></a>

A QRAM éra az F5 RTL prototípus késői fázisában kezdődik, és a F6 ChipIgnite-tól teljes. Ebben a fázisban a CODE **on-chip Quench-RAM tömb**, aminek a védelmét a **per-block status-bit** biztosítja (SEAL/RELEASE hardveres állapotgép-műveletek, lásd `docs/quench-ram-hu.md`).

### Az alapelv — gatekeeper a verifikációra

> **A Seal Core itt NEM fizikai pin-routing-ot véd.** A CODE védelmet a Quench-RAM status-bit adja. A Seal Core szerepe kizárólag az **AuthCode verifikáció** futtatása — ő dönti el, hogy egy bejövő `.acode` konténer hiteles-e, és ő triggereli a Quench-RAM SEAL HW-állapotgépét a CODE régió lezárására.

Ez egy **fundamentálisan más szerep**, mint a pre-QRAM érában. A védelem forrása más mechanizmus, a Seal Core csak a verifikációs pipeline-t hajtja.

### A flow

```
1. .acode konténer érkezik (hálózat, USB, hot-update)
2. router → Seal Core (dedikált inbox)
3. Seal Core firmware futtatja az AuthCode verify flow-t:
      - SHA-256(bytecode) == cert.PkHash ?
      - BitIceCertificateV1.Verify(cert, eFuse.CaRootHash) ?
      - cert.SubjectId ∉ revocation_list ?
4. Ha mind OK:
      - Seal Core normál write-op-okkal beírja a bytecode-ot
        egy mutable (status=0) Quench-RAM régióba
      - Seal Core hívja a SEAL hardveres állapotgép-műveletet a régió lezárására
      - Quench-RAM HW: status=1, a bytecode innentől immutable
5. Seal Core értesíti a Symphact scheduler-t: "új aktor betöltve, indulhat"
```

A **4. lépésben** a Seal Core nem használ speciális WE-pint. Egyszerű memória-írást végez a Quench-RAM mutable régiójára (amit a capability rendszer neki biztosít), majd SEAL-lel lezárja. A védelem attól jön, hogy **csak a Seal Core firmware-e képes a `SEAL` hardveres állapotgép-műveletet triggerelni az AuthCode verify kontextusában** — a SEAL triggerek listája zárt: CODE régió (Seal Core boot / hot_code_loader), SEND (payload kilép a Core-ból), swap-out (DMA evict külső QRAM-ba).

### Redundancia — verifikációs throughput szempontjából

Több Seal Core QRAM érában **nem a memóriaírás védelméért** van, hanem:

| Szempont | Magyarázat |
|----------|------------|
| **Verifikációs throughput** | 4 Seal Core párhuzamosan 4× gyorsabb code-load |
| **Verifikációs redundancia** | Egyik Seal Core meghibásodik → a másik átveszi a szerepét |
| **Failure isolation** | Egy Seal Core lassulása / zavara nem akasztja meg a többit |

A ring/mesh topológia a **hot_code_loader aktor host-váltáshoz** kell (ha a S2 Seal Core elhal, a S1 indítja el a loader aktort magán), nem a memóriavédelemhez.

### A Seal Core QRAM-ban — összefoglalva

- **Nem** fizikai gatekeeper a WE-pin felett (nincs külön CODE chip sem)
- **IGEN** logikai gatekeeper az AuthCode flow-n
- **IGEN** SEAL HW-trigger forrás
- Több Seal Core = **párhuzamos verify + redundancia**
- A CODE memória védelme **teljes mértékben** a Quench-RAM status-bit mechanizmusa

## Az átmeneti pont <a name="atmenet"></a>

A két éra **közötti átmenet** egy konkrét CFPU chip-generációhoz kötött:

| Fázis | Memória | Seal Core fő szerep | Védelem forrása |
|-------|---------|-----------------------|------------------|
| F3 Tiny Tapeout | külső SRAM | fizikai WE-routing | topológia |
| F5 early | külső SRAM | fizikai WE-routing | topológia |
| F5 late (QRAM prototype) | on-chip QRAM | AuthCode verify + SEAL-trigger | status-bit |
| F6 ChipIgnite | on-chip QRAM | AuthCode verify + SEAL-trigger | status-bit |
| F7+ | on-chip QRAM | AuthCode verify + SEAL-trigger | status-bit |

Az F5 késői szakaszában a QRAM prototípus megjelenésével a Seal Core szerepe **változik**. A két mechanizmus **nem konkurens** egymással — időben váltják egymást, nem egyidejűleg léteznek.

Egyetlen rövid átmeneti fázis (F5 késő → F6 korai) elképzelhető, ahol **mindkét mechanizmus él** (külső CODE RAM + on-chip QRAM zóna), de ez is **tiszta szeparációval**: a külső RAM zóna WE-routing-ot használ, az on-chip QRAM zóna status-bit-et, és **egy bytecode vagy az egyikben vagy a másikban él** — sosem kevert.

## Boot és firmware immutability <a name="boot"></a>

A Seal Core saját kódja **nem tölthető be aláírt bináris formájában** — paradoxon volna (ki hitelesíti a hitelesítőt?). Három lehetséges forrás a Seal Core firmware-ének:

### Opció 1 — Mask ROM (chip-gyártáskor beégetett)

- Maszk-szinten a szilíciumba égetett áramkör
- **Soha nem módosítható** a chip élettartama alatt
- Nagyon biztonságos, de update-elhetetlen → bug-fix új chip-tape-out-ot igényel

### Opció 2 — OTP eFuse tömb

- Egyszer programozható eFuse cellák
- Gyártáskor vagy első bekapcsoláskor írható
- Első írás után **soha nem módosítható**
- Rugalmasabb, mint a mask ROM (gyártás-futamban frissíthető)

### Opció 3 — Flash + boot-time integrity check

- Flash-ben tárolt kód, SHA-256 hash eFuse-ban
- Boot-kor verify
- Update-elhető (új flash + új hash írás), de biztonsági kockázat nagyobb

**A v1.0 modellben Opció 1 vagy 2 a baseline.** A konkrét választás **F5 RTL döntés**, a gyártási reality-től függ.

### A boot flow

```
1. Chip power-on
2. Seal Core firmware fut mask ROM / eFuse-ból
3. Self-test:
      - SHA-256 unit működik?
      - WOTS+ unit működik?
      - SRAM tiszta (minden 0)?
      - eFuse CA Root Hash olvasható?
4. Health monitor check: más Seal Core-ok heartbeat-eznek?
5. Ready state: Seal Core fogadásra kész .acode konténereket
6. Parent supervisor értesítés: "Seal Core aktív"
```

## Többszörözés és graceful degradation <a name="redundancia"></a>

A CFPU chip típusától és méretétől függően **1-64+ Seal Core** lehet jelen. A többszörözés célja:

### Célok

- **Redundancia** — egy Seal Core HW-hiba (SEU, wear-out) esetén a többi tovább működik
- **Throughput** — párhuzamos AuthCode verify nagy code-load sebességhez
- **Load balancing** — code-load kérések elosztása

### Health monitor és heartbeat

Minden Seal Core **heartbeat pulzust** ad egy központi health monitor logikának:

```
health monitor (központi, on-chip FSM):
  - minden Seal Core → heartbeat jel (ciklikus pulzus)
  - elvárás: pulzus N órajel-cikluson belül
  - ha N×10 cikluson át nincs pulzus → dead[i] ← 1
  - dead[i] flip-flop: HW-set only, chip reset-tel clear
  - dead[i] olvasható a többi core számára, de NEM írható
```

Ez **~50-100 tranzisztor** a health monitor-ra, lokális és autonóm. **Nem szoftveresen vezérelt** — egy rosszindulatú aktor nem tudja "halottnak megjátszani" a szomszédot.

### Topológia

**Pre-QRAM éra (F3-F5):**
- Ring-neighbor: N Seal Core, külön CODE RAM chipekkel, szomszéd-takeover
- Korlát: maximum 4-8 Seal Core gyakorlatilag (pin-budget miatt)

**QRAM éra (F5+):**
- Ring vagy 2D mesh, a chip méretétől függően
- A takeover itt **a hot_code_loader aktor-host szerepet jelenti**, nem WE-routing-ot
- Skálázódás: 4-64+ Seal Core lehetséges

### Fix prioritás takeover

A kiszámíthatóság kedvéért minden Seal Core-hoz **fix prioritásos lista** tartozik a szomszédoktól, amely jelzi, ki veszi át a hiba esetén:

```
Ring topológia (N Seal Core):
  Seal[i] dead → Seal[i-1 mod N] takes over

2D mesh topológia (4-neighbor):
  Seal[i] dead → priority N > W > E > S
  if mind halott → dead Cluster, graceful degradation
```

### Graceful degradation

Ha egy Seal Core cluster teljesen elhal (pl. power-domén kiesés):

- A code-load throughput csökken (kevesebb parallel verifier)
- A hozzájuk tartozó CODE RAM régiók (pre-QRAM) / verifikációs feladatok (QRAM) más Seal Core-okra kerülnek
- **A rendszer folytatja a működését** — csak lassabban indít új aktorokat
- A már betöltött aktorok **teljesen érintetlenek** (a kódjuk már SEAL-elt)

## Gyorsító funkciók <a name="gyorsitok"></a>

Minden Seal Core dedikált hardveres gyorsítókat tartalmaz a kriptografikus műveletekhez. Ezek közvetlenül a Seal Core firmware-éből elérhetők:

### SHA-256 HW unit

- ~5K gate
- ~80 ciklus/blokk (512-bit input)
- Pipeline-olható egy input-stream-re

### WOTS+ verifier

- ~3K gate
- SHA-256 chain rekonstrukció (67 chain × ~7.5 átlagos hash)
- ~500 SHA-256 hívás egy teljes WOTS+ verify-hoz

### Merkle path verifier

- ~2K gate
- h=10 iteráció = 10 SHA-256 hash egy verify-hoz

### Teljes verify-ciklus

Egy teljes BitIce cert-verify (TBS hash + WOTS+ recompute + leaf hash + Merkle path):

- ~512 SHA-256 ops total
- ~41K ciklus 1 GHz-en = **~41 µs**

### Optional: BLAKE3 unit (jövőbeli)

Ha a jövőben egy másik hash-funkció kell (pl. a BitIce egy új verziójához), egy további ~5K gate BLAKE3 unit hozzáadható a Seal Core-hoz.

## Biztonsági garanciák <a name="biztonsag"></a>

A Seal Core mint komponens **egyedi hozzájárulása** a CFPU biztonsági modelljéhez:

| Támadás-osztály | Hagyományos rendszer | Seal Core-os CFPU |
|----------------|----------------------|-------------------|
| Memory controller write-path bypass | szoftveres check kerülhető | **Kizárva** (pre-QRAM: fizikai WE-routing; QRAM: SEAL HW FSM-trigger csak Seal Core firmware-ből) |
| Hot code loader tamper | kernel-szintű támadás | **Kizárva** (Seal Core firmware immutable, mask ROM / eFuse) |
| Unsigned code introduction | ring-0 exploit | **Kizárva** (minden code-load Seal Core-on megy át) |
| DoS a hitelesítőn | egyetlen signing service | **Redundáns** (több Seal Core, graceful degradation) |
| HW-fault on signing path | Az egyetlen service leáll | **Tolerált** (ring/mesh takeover) |

## Nyitott kérdések <a name="nyitott"></a>

Ez a v1.0 doksi a vízió-szintű architektúrát rögzíti. A részletek a megfelelő F-fázisokban pontosítandók:

### F4-F5 (szim + RTL)

1. **Seal Core CPU-architektúra** — CIL-Seal ISA: mely CIL-T0 opkódok maradnak, milyen crypto opkódok jönnek hozzá?
2. **Firmware tároló** — mask ROM vs. eFuse vs. flash+integrity check
3. **Heartbeat frekvencia és timeout** — mekkora N, mennyi az "elfogadható válaszidő"

### F5-F6 (első hardware)

4. **Pre-QRAM CODE RAM chip méret és pin-layout** — milyen kereskedelmi SRAM chipet támogat
5. **QRAM átmeneti pont** — mikor kerül be on-chip CODE memória
6. **Seal Core szám F6-ban** — 2, 4, vagy több?

### F7+ (skálázódás)

7. **Mesh topológia** — 4-neighbor vs. 8-neighbor (diagonálokkal)
8. **Power-domén határok** — hány Seal Core oszt egy power-domént
9. **Inter-chip multi-CFPU kontextus** — minden CFPU chipben külön Seal Core-készlet (explicit: igen)
10. **Hot-plug Seal Core quadrant** — nagyon nagy chipeken (F8+)

## F-fázis bevezetés <a name="fazisok"></a>

| Fázis | Seal Core szerepe |
|-------|---------------------|
| F0–F2 (szimulátor) | Szoftveres emuláció, AuthCode verify mock a `TCpu`-ban |
| F3 Tiny Tapeout | Egyszerű 1-magos Seal Core, WE-pin routing, 1 külső CODE RAM |
| F4 multi-core szim | 2-4 Seal Core szimulációban, ring-neighbor failover, WE-routing emuláció |
| **F5 RTL prototípus** | Első **valódi** Seal Core RTL-ben; SHA-256 + WOTS+ HW unit; pre-QRAM külső RAM-mal |
| **F5 késői (QRAM prototype)** | **Átmenet**: on-chip QRAM tömb megjelenik; Seal Core szerepe **vált** AuthCode-gatekeeper-ré |
| F6 ChipIgnite | Teljes on-chip QRAM, 2-4 Seal Core ring, production AuthCode flow |
| F6.5 Secure Edition | 4 Seal Core kötelező, extra gyorsítókkal (opcionális BLAKE3) |
| F7 Cognitive Fabric | 8-16 Seal Core 2D mesh, nagy-chip skála |
| F8+ server-class | 64-256 Seal Core 2D mesh, power-domén boundary, hot-plug cluster |

## Referenciák <a name="referenciak"></a>

### Belső dokumentumok

- `docs/authcode-hu.md` — az AuthCode mechanizmus, amit a Seal Core futtat
- `docs/quench-ram-hu.md` — a QRAM memóriacella, ami QRAM érában a CODE védelmét adja
- `docs/security-hu.md` — a CFPU biztonsági modell
- `docs/architecture-hu.md` — a CFPU mikroarchitektúra, ahova a Seal Core mint harmadik core-kategória beilleszkedik
- [`Symphact/docs/vision-hu.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-hu.md) — a `hot_code_loader` aktor, amit a Seal Core hosteol

### Külső referenciák

- BitIce projekt: `github.com/BitIce.io/BitIce` (a kriptografikus primitiv-ek forrása)
- NIST SP 800-208: Stateful Hash-Based Signature Schemes
- NIST FIPS 180-4: SHA-256 specifikáció

## Changelog <a name="changelog"></a>

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-16 | Kezdeti vízió-szintű kiadás. A Seal Core két különálló mechanizmusként: (1) pre-QRAM érában fizikai WE-pin routing a CODE RAM chipre; (2) QRAM érában AuthCode verifikációs gatekeeper a SEAL HW-trigger forrással. Explicit szeparáció a két érá között, nincs cross-contamination. Ring és 2D mesh failover topológiák, graceful degradation. Firmware immutability mask ROM / eFuse alapon. |
