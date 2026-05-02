# Seal Core — A CFPU hitelesítési gatekeeper magja

> English version: [sealcore-en.md](sealcore-en.md)

> Version: 1.5

Ez a dokumentum a **Seal Core** komponenst írja le: egy dedikált, egyszerű, hardware-burned firmware-rel működő core-t, ami a CFPU chipen a **kódbetöltés hitelességét** biztosítja. A Seal Core két különböző mechanizmussal működik a CFPU fejlesztési fázisától függően — **pre-QRAM érában** (F3-F5) fizikai WE-pin routing révén, **QRAM érában** (F5+) AuthCode verifikációs gatekeeper szerepben. Ez a két megközelítés **külön mechanizmus**, amelyeket ez a doksi tudatosan szétválasztva tárgyal.

> **Vízió-szintű dokumentum.** A Seal Core F3-tól jelen van a CFPU-ban, és végig megmarad a chip-generációkon. Szerepe azonban **fundamentálisan másként áll** pre-QRAM vs. post-QRAM kontextusban, ezért a doksi két külön szekcióban tárgyalja a kettőt, explicit átmeneti pont-megjelöléssel.

## Tartalom

1. [Motiváció](#motivacio)
2. [Mi a Seal Core](#mi-a-sealcore)
3. [Kapcsolódás a CFPU brand-családfához](#brand)
4. [Általános architektúra](#architektura)
5. [A három SEAL érintési pont](#seal-points)
6. [Seal Core a pre-QRAM érában (F3-F5)](#preqram)
7. [Seal Core a QRAM érában (F5+)](#qram)
8. [Az átmeneti pont](#atmenet)
9. [Boot és firmware immutability](#boot)
10. [Authority delegáció — runtime CST policy](#authority)
11. [Többszörözés és graceful degradation](#redundancia)
12. [Gyorsító funkciók](#gyorsitok)
13. [Biztonsági garanciák](#biztonsag)
14. [Nyitott kérdések](#nyitott)
15. [F-fázis bevezetés](#fazisok)
16. [Referenciák](#referenciak)
17. [Changelog](#changelog)

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
- **DDR5 capability slot kezelés** — `kernel_io_sup` policy alapján SEAL/RELEASE-eli a per-core capability slot-okat NoC mailbox üzenettel a célcore **QGate**-jén keresztül (lásd `ddr5-architecture-hu.md` v1.3, "5.e) HW Capability Slot")
- **CST (Capability Slot Table) kezelés** — a NoC aktor-aktor capability tábla SEAL/RELEASE-e szintén NoC mailbox üzenettel a célcore **QGate**-jén keresztül (lásd `interconnect-hu.md` v3.0, `quench-ram-hu.md`)
- **Single-instance peripheria config** — a DDR5 Controller, QSPI Controller stb. **egész peripheria** konfigurációja **dedikált hardwired config porton** (1 cél, lásd `ddr5-architecture-hu.md` v1.3 line 85-86) — itt **nem** QGate, mert a peripheria nem core
- **Authority delegation gatekeeper** — boot-időben az OS root aktornak GRANT_ALL CST entry-t ír; runtime alatt az OS root aktor (vagy delegáltjai) felől érkező spawn / revoke / delegate kérelmeket ellenőrzi a supervisor link és a kérelmező saját CST capability-je alapján, majd a célcore **QGate**-jének NoC mailbox üzenetet küld. Részletek: ["Authority delegáció — runtime CST policy"](#authority) és ["A három SEAL érintési pont"](#seal-points).

## Kapcsolódás a CFPU brand-családfához <a name="brand"></a>

A Seal Core beilleszkedik a CFPU komplementer biztonsági mechanizmusok családjába:

```
               ┌───────────────────────────────────────────┐
               │              CFPU biztonsági család       │
               └───────────────────────────────────────────┘
                                    │
   ┌──────────────┬──────────┬──────────┬──────────────┬──────────┬──────────────┐
   │              │          │          │              │          │              │
[Quench-RAM] [AuthCode] [CodeLock] [Seal Core]    [QGate]   [Symphact
 memória-     kód-       runtime    globális       per-core    HSM Card]
 cella        aláírás    W⊕X        gatekeeper     Quench-RAM  crypto +
                                    core           kapuőr      signing
```

| Komponens | Hatókör | Szerep |
|-----------|---------|--------|
| **Quench-RAM** | per-bit | Memóriacella, status-bit alapú immutability |
| **AuthCode** | per-bináris | CIL kód aláírás-verifikáció (LMS+WOTS+) |
| **CodeLock** | per-régió | Runtime W⊕X (pre-QRAM: WE-pin routing) |
| **Seal Core** | chip-szintű | Globális gatekeeper, AuthCode flow, capability authority root |
| **QGate** | **per-core** | **Lokális Quench-RAM kapuőr — az egyetlen írási út a core CST QSRAM-hoz / DDR5 cap-slot QRAM-hoz; NoC mailbox SEAL/RELEASE üzenetekre aktiválódik** |
| **Symphact HSM Card** | rendszer-szintű | Külső kulcs-management, signing |

A Seal Core az a **fizikai komponens**, amelyik a többi mechanizmust **gyakorlatilag aktiválja**:
- Az **AuthCode** verifikációs flow itt fut
- A **CodeLock** W⊕X kényszerítés (pre-QRAM érában) itt származik a WE-pin routing-ból
- A **Quench-RAM** CODE régió SEAL HW-triggerét itt indítják
- A per-core **QGate**-eket NoC mailbox üzenetekkel vezérli (CST/cap-slot SEAL/RELEASE)

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

## A három SEAL érintési pont <a name="seal-points"></a>

A Seal Core **három különböző SEAL/RELEASE eseménytípust** vezérel, és ezek **három különböző csatornán és három különböző végrehajtón** futnak. Ezek explicit szétválasztása fontos, mert korábbi doc-verziók (sealcore-hu v1.1–v1.2) keverték a "hardwired config port" megfogalmazást — az csak az 1. és 3. eseményre igaz, a 2.-ra **nem**.

> **Brand-név bevezetés (v1.4):** a 2. eseménytípus végrehajtóját — a per-core lokális SEAL/RELEASE FSM-et — innentől **QGate**-nek nevezzük (Quench-RAM Gate). Ez a CFPU biztonsági brand-családjának új eleme; lásd ["Kapcsolódás a CFPU brand-családfához"](#brand) szekció új sora.

| # | Esemény | Authority | Csatorna | Végrehajtó | Sebesség |
|---|---------|-----------|----------|------------|----------|
| 1. | **CODE régió SEAL** (boot / hot-load) | Seal Core | Lokális (Seal Core saját címterében — write-port + SEAL trigger) | Seal Core HW FSM | Slow path (kódbetöltésenként egyszer) |
| 2. | **Capability slot SEAL/RELEASE** (per-core CST, per-core DDR5 cap slot) | Seal Core / supervisor aktor | **NoC mailbox** üzenet a célcore felé | **QGate** (per-core lokális Quench-RAM kapuőr FSM) | Fast path (gyakori, runtime) |
| 3. | **Single-instance peripheria config** (DDR5 Controller, QSPI Controller stb.) | Seal Core / `root_supervisor` | **Hardwired config port** (1 küldő → 1 cél, kulcs nélküli, csak engedély) | Periféria HW | Slow path (config-only, ritka) |

### Miért nem hardwired config port a CST/capability slot íráshoz?

A per-core CST és a per-core DDR5 capability slot tábla **fizikailag a célcore QSRAM-jában él** (lásd `ddr5-architecture-hu.md` v1.3 §2.b, "Tárolás: per core, QRAM-ban"). Nincs központi capability tábla. Ha ezt egy globális hardwired config bus-szal írnánk, akkor:

- ~10 000 core × n_slots × m_bit-es vezeték = **fizikailag kivitelezhetetlen** routing
- Minden core-nak külön config-port-ja lenne a Seal Core felé → óriási area + power
- A shared-nothing chip elv sérülne (központi adatút)

Ehelyett a per-core SEAL/RELEASE **NoC mailbox üzenet**-ként utazik: a küldő (Seal Core vagy supervisor aktor) `dst=(target_core, 0)` címre küld egy SEAL parancsot, és a célcore **QGate**-je írja a saját QSRAM-jába. Ez:

- **Skálázódik** a meglévő NoC-on, nem igényel új vezetékeket
- **HW-attested** — a QGate ellenőrzi, hogy a `(src, src_actor)` páros a Seal Core hardwired címe vagy egy felhatalmazott supervisor (lásd `interconnect-hu.md` v3.0, header v3.1)
- **Lokális végrehajtás** — a QGate kizárólagos hozzáféréssel ír a saját CST/cap-slot QSRAM-jába; más core-nak nincs vezetéke az adott QSRAM-hoz

### A QGate komponens

A **QGate** (Quench-RAM Gate) egy **per-core HW állapotgép**, amely egyetlen funkciót lát el: CRC-gate-eli a write-portot a core saját Quench-RAM-alapú capability tábláihoz (CST QSRAM, DDR5 cap-slot QRAM). A QGate brand-családi pozícióját lásd a 3. szekcióban ["Kapcsolódás a CFPU brand-családfához"](#brand).

```
┌──────────────────────────── core_i ───────────────────────────┐
│                                                                │
│   NoC inbox ──► [QGate] ──► CST QSRAM (per-actor capability)  │
│                  │     └──► DDR5 cap-slot QRAM (per-actor)    │
│                  │                                             │
│                  ├─ CRC-8 header check                         │
│                  ├─ CRC-16 payload check                       │
│                  └─ op decode (SEAL_INSTALL / UPDATE / RELEASE)│
│                  │                                             │
│                  └─ ha CRC fail → silent drop                  │
│                                                                │
│   core SW ────────X─► (NINCS út a QSRAM íráshoz)              │
└────────────────────────────────────────────────────────────────┘
```

| Tulajdonság | Érték |
|-------------|-------|
| Példányszám | **1 / core** (Nano, Actor, Rich-en mind van) |
| Tárolt belső állapot | minimális (FSM állapot + CRC checker shift-regiszter) |
| Bemenet | NoC inbox dedikált port (csak SEAL/RELEASE üzenet típusok) |
| Kimenet | CST QSRAM write-port, DDR5 cap-slot QRAM write-port |
| Validáció | **kizárólag CRC-8 (header) + CRC-16 (payload)** — logikai validáció nincs |
| Drop-feltétel | CRC mismatch → silent drop, counter inkrement |
| Becsült terület (5nm) | **~600–800 gate / core** (CRC-8 ~200 + CRC-16 ~400 + write-mux + FSM ~150) |

### Miért nincs logikai validáció — CFPU single-layer trust elv

A QGate **nem ellenőriz** semmit a következő dimenziókban:

- ❌ `src` mező authority komparátor (eFuse cím vs. supervisor capability)
- ❌ Payload range check (`target_actor` ∈ [0..255], `perms` értelmes maszk)
- ❌ Op-validitás (érvényes opcode-érték)
- ❌ Supervisor link well-formedness

**Ez tudatos tervezés, nem hiányosság.** A CFPU single-layer trust elve szerint:

> Bízz az immutable + HW-managed forrásban; csak a fizikai hibákra védj.

A QGate-hez érkező üzenetek mindig a Seal Core firmware-éből (vagy felhatalmazott supervisor aktortól) származnak — más aktor nem tud küldeni, mert a CST router-szintű filter szűri (a saját CST entry-jében nincs capability a QGate-célhoz). Tehát:

- A küldő **definíció szerint authority** (mert a CST garantálja)
- A Seal Core firmware **immutable** (mask ROM / eFuse) → nem küld rosszul formált payload-ot
- Az egyetlen reális hibalehetőség: **fizikai bit-flip a NoC tranzit során** (SEU, kozmikus sugárzás)
- Erre a CRC-8 (header) és CRC-16 (payload) **elegendő védelem**

A logikai validáció hozzáadása **defense-in-depth retorika** lenne — az ellentéte annak az elvnek, ami miatt:
- A header v3.0-ból a HMAC mezőt **töröltük** (`interconnect-hu.md` v3.0): "a CST HW-managed, a szoftver nem manipulálhatja"
- A küldő core HW-ja oldja fel a CST indexet → nem aktor SW

Ugyanez itt: ha logikai bug van a Seal Core firmware-ben (rossz `target_actor`-t küld), az **threat model-en kívül** van. Nincs olyan threat model, amiben az immutable mask ROM hibás kódot futtat — ha az lenne, sokkal súlyosabb gondunk volna.

**Konzekvencia:** a QGate gyakorlatilag egy **CRC-gate-elt write-port**, semmi több. Ez a minimális HW, ami a Quench-RAM SEAL/RELEASE szemantikát garantálja a NoC-mailbox csatornán.

### Miért hardwired config port a single-instance peripheriához?

A DDR5 Controller, QSPI Controller stb. **egyetlen példányos** komponens a chip-en — a config információ (PHY paraméterek, bank policy stb.) szintén egyetlen helyen él. Itt:

- A "1 küldő → 1 cél" topológia triviális (egy darab vezeték a Seal Core-tól)
- Boot-időben kell konfigurálni, runtime alatt csak ritka módosítás
- A NoC mailbox over-kill volna egy ilyen alacsony frekvenciájú config-csatornához

Ezért a single-instance peripheria config **hardwired, kulcs nélküli, csak engedély** porton fut a Seal Core-tól (lásd `ddr5-architecture-hu.md` v1.3 line 85-86). Ez **nem** ugyanaz a mechanizmus, mint a per-core CST/cap slot SEAL/RELEASE.

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

## Authority delegáció — runtime CST policy <a name="authority"></a>

Ez a szekció rögzíti, **hogyan oszlik meg a felelősség** a Seal Core (HW mechanizmus) és az OS root aktor (runtime policy) között a CST tábla írásakor és az aktor-szintű capability delegálás során. A modell a [`feedback_mechanism_separation`](../docs/architecture-hu.md) elvet követi: **a Seal Core firmware-e nem érti az OS struktúráját** — a Seal Core csak ellenőrző és író mechanizmus, a tényleges policy az OS root aktor kezében van.

### Alapelv

> A per-core CST-be **kizárólag** az adott core **QGate**-je írhat, és a QGate-hez csak authority forrásból érkezhet üzenet — ezt a CST router-szintű filter garantálja: a QGate-célhoz capability-t csak Seal Core / felhatalmazott supervisor adhat, így nem-authority aktor a saját core HW-jénél küldéskor elakad. A QGate maga **csak CRC-t ellenőriz** (single-layer trust elv, lásd ["A QGate komponens"](#seal-points) szekció v1.5). Más core-nak **nincs vezetéke** a célcore CST QSRAM-jához. Ez fizikailag érvényesített, nem szoftveresen konfigurálható. Lásd: ["A három SEAL érintési pont"](#seal-points) — a per-core CST a 2. eseménytípus (NoC mailbox + QGate), nem a 3. (hardwired config port).

A Seal Core firmware-e azonban **nem dönti el saját maga**, kit milyen capability illet. A boot utáni runtime CST-változtatásokat **az OS root aktor** kéri üzenetekkel — a Seal Core firmware policy-ja csak a kérelem **hitelességét** és **konzisztenciáját** ellenőrzi. Ez egy klasszikus mechanizmus / policy szétválasztás (microkernel filozófia).

### Boot-idő delegáció — kezdeti GRANT_ALL

A `hw-boot-hu.md` 2. lépés végén, mielőtt a Rich core reset elengedődik:

```
1. Seal Core verifikálja az OS root binárist (LMS+WOTS+ aláírás)
2. Seal Core NoC mailbox üzenetet küld a Rich core QGate-jének:
     dst   = (Rich_core, 0)    ← Rich core QGate mailbox címe
     src   = (Seal_core, 0)    ← Seal Core hardwired HW címe (HW-attested)
     op    = SEAL_CST_INSTALL
     entry = (target_actor=1, perms=GRANT_ALL, supervisor=(Seal_core, 0))
3. Rich core QGate ellenőrzi CRC-8 + CRC-16, és (ha OK) beírja a saját CST QSRAM-jába:
     CST[1] = (perms=GRANT_ALL, supervisor=(Seal_core, 0))
4. Seal Core jelzi a Rich core-nak: 0xF0002024 ← 1 (verified + go)
5. Rich core indul, az OS root aktor (actor_id=1) felveszi a runtime authority szerepét
```

A QGate **nem ellenőrzi** a `src` mezőt — ezt a CST router-szintű filter már megtette küldéskor (a Seal Core hardwired címére minden core-nak van capability-je, mások meg nem küldhetnek a QGate-célre). A QGate csak CRC-8 + CRC-16 ellenőrzést végez, és ha OK, beírja a CST-t. Lásd: ["A QGate komponens"](#seal-points) "Miért nincs logikai validáció" alszekció.

A boot utáni CST tábla tehát **egyetlen** entry-vel indul: az OS root aktor mindent lát és mindent delegálhat. Innentől a CFPU runtime policy-ja **az OS root aktor felelőssége**, nem a Seal Core firmware-éé.

### Runtime delegáció — üzenet-API

> **Pontosítás — NoC-attested, nem kriptografikusan aláírt:** a CFPU üzenet-szinten **nem használ HMAC-et vagy digitális aláírást** (lásd `interconnect-hu.md` v3.0: a HMAC mező a header v3.0-ban TÖRÖLVE lett). Az authority command hitelességét **kizárólag a HW által attribuált eredet** adja: a header `src_actor[8]` mezőjét a küldő core HW context regisztere tölti (nem hamisítható), a `src[24]` mezőt pedig a NoC router HW tölti a küldő fizikai pozíciója alapján. A CRC-16 / CRC-8 mezők **csak integritás-ellenőrzésre** szolgálnak, **nem auth-ra**. Tehát az alábbi műveletek **NoC-attested authority command**-ok, nem aláírt üzenetek.

Az OS root aktor (vagy egy delegáltja, akinek megfelelő capability-je van) üzenetet küld a Seal Core-nak (`(Seal_core, 0)` címre), hogy CST-műveletet kérjen. Az üzenet típusok funkcionálisan:

| Művelet | Kérelem tartalma | Seal Core ellenőrzése |
|---------|------------------|------------------------|
| **Spawn** — új aktor létrehozása | `target_core, code_hash, parent, perms` | (a) `parent == src_actor` (a kérelmező a leendő szülő), (b) `perms ⊆ kérelmező CST entry-je`, (c) `code_hash` AuthCode-verifikált |
| **Delegate** — meglévő aktornak capability adás | `target_actor, perms_subset` | (a) `target_actor` parentje a kérelmező (supervisor link), (b) `perms_subset ⊆ kérelmező delegate-jogai` |
| **Revoke** — capability visszavonás | `target_actor` | (a) `target_actor` parentje a kérelmező, vagy a kérelmező az OS root aktor |

A konkrét üzenet-opcode-ok és payload-formátumok **F4-F5 RTL döntés** — ezt a `CIL-Seal ISA` definiálja majd (lásd [Nyitott kérdések](#nyitott) #1).

A kérelmező identitása **nem hamisítható**: a `src_actor` mező a header v3.1-ben a core HW context regiszteréből származik (lásd `specs/cell-format-hu.md` v2.2, "3. döntés"), a `src` mezőt pedig a NoC router HW tölti a fizikai eredet alapján. A Seal Core firmware ezt a (HW-attested) `(src, src_actor)` párost veti össze a kérelem `parent` / `target_actor` mezőivel — **nincs kripto, csak HW-attribuált eredet**.

### Validációs algoritmus (Seal Core firmware)

```
on_request(MsgCstOp from src):
    1. lookup CST[src_core, src_actor] → caller_perms, caller_supervisor
       (ha nincs entry → REJECT, src nem aktív aktor)

    2. switch(op):
         case Spawn:
             if request.parent != src                    → REJECT
             if request.perms ⊄ caller_perms             → REJECT
             if AuthCodeVerify(request.code_hash) fails  → REJECT
             allocate target_actor on target_core
             send NoC mailbox: SEAL_CST_INSTALL →
                  dst=(target_core, 0),
                  payload=(target_actor, request.perms, supervisor=src)
             # célcore QGate:
             #   CRC-8 + CRC-16 ellenőrzés
             #   beírja: CST[target_actor] = (perms, supervisor=src)

         case Delegate:
             if supervisor_link[request.target] != src   → REJECT
             if request.perms_subset ⊄ caller_perms      → REJECT
             send NoC mailbox: SEAL_CST_UPDATE →
                  dst=(target.core, 0),
                  payload=(target.actor, perms_or=request.perms_subset)

         case Revoke:
             if supervisor_link[request.target] != src
                AND src != OS_root_actor                 → REJECT
             send NoC mailbox: RELEASE_CST_ENTRY →
                  dst=(target.core, 0),
                  payload=(target.actor)
             cascade revoke children (supervision tree-walk + RELEASE üzenetek)

    3. reply MsgCstOpResult(success / error_code)
```

A **cascade revoke** szemantika a klasszikus actor supervision tree-t követi: ha egy parent-et revoke-olunk, a children CST-jét is törölni kell. A Seal Core firmware végigjárja a supervision tree-t, és minden érintett célcore-nak külön RELEASE_CST_ENTRY üzenetet küld — minden egyes érintett core **QGate**-je hajtja végre a saját QSRAM-jában. A sweep maga firmware-vezérelt (nem egyetlen HW broadcast), de a végrehajtás a célcore-okban kizárólag HW (QGate).

### Miért nem a Seal Core firmware tartalmazza a policy-t

A Seal Core firmware **mask ROM-ban / eFuse-ban** él, és nem frissíthető a chip élete során. Ha a delegation policy itt lenne:

- Az OS struktúra változásai (új aktor-típusok, új capability-osztályok) **chip re-tape-out** árán lennének követhetők
- A microkernel filozófia sérülne: a Seal Core "értené" a magas-szintű OS fogalmakat, nem csak a HW mechanizmust
- Egy bug a policy-ban nem javítható szoftveres update-tel

Ezért a Seal Core firmware-e **csak a mechanizmust** implementálja (CST írás, kérelem-validáció ellenőrzött szabályok szerint), és a magas-szintű döntéseket (ki kapjon mit, mikor, miért) az OS root aktor hozza meg. Az OS root aktor **frissíthető** (új AuthCode-verifikált bináris egy új OS verzióhoz), így a policy evolúciója sosem igényel új szilíciumot.

### Threat model — mit zár ki

| Támadás | Védelem |
|---------|---------|
| Rosszindulatú aktor próbál közvetlenül a saját core CST QSRAM-jába írni | A CST QSRAM-ot csak a core **QGate**-je írhatja (write-port szigorúan FSM-vezérelt). Az aktor SW-jének nincs címterhez illeszkedő utasítása a CST QSRAM-ra. |
| Rosszindulatú aktor a célcore-nak hamis `SEAL_CST_INSTALL` üzenetet próbál küldeni | **Fizikailag nem lehetséges.** A küldéshez szükség van CST entry-re a `(target_core, 0)` célhoz, és a QGate-célt csak Seal Core / authority delegate adhat capability-ként. A nem-authority aktornak nincs CST entry-je → a saját core HW-ja küldéskor elutasítja. A QGate-hez csak authority-tól érkezhet üzenet. |
| Aktor hamis `src_actor` mezővel kér capability-t | A küldő core HW tölti a `src_actor` mezőt context regiszterből, nem hamisítható (lásd `cell-format-hu.md` v2.2 3. döntés). |
| Bit-flip / SEU a NoC tranzit során | CRC-8 (header) és CRC-16 (payload) — a QGate silent drop-pal kezeli. |
| Rosszindulatú aktor szülőként ad capability-t nem-gyermeknek | A Seal Core firmware ellenőrzi a `supervisor_link[target] == src` invariánst minden delegálásnál (a saját firmware-belső supervisor tree alapján). |
| Aktor próbál önmagának capability-t adni | Az aktor saját `src_actor`-ja nem lehet egyidejűleg a kérelem `parent` mezője és a `target` is — a Seal Core firmware kizárja. |
| Az OS root aktor kompromittálódik | Threat model-en kívül: az OS root aktor AuthCode-verifikált, és a Seal Core mechanizmusként továbbra is érvényesíti a strukturális invariánsokat. A teljes rendszer-takeover egy AuthCode-verified rosszindulatú OS-t igényelne. |

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

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.5 | 2026-05-02 | **QGate single-layer trust elv — drasztikus egyszerűsítés.** A v1.4-es QGate spec redundáns logikai validációt tartalmazott (`src` authority komparátor, payload range check, op-validitás, trap-flit) — ezek **CFPU single-layer trust elv** szerint feleslegesek: a CST router-szintű filter már garantálja, hogy csak authority küldhet a QGate-nek, és a Seal Core firmware immutable (mask ROM), ezért definíció szerint korrekt. A QGate v1.5-ben **kizárólag CRC-8 + CRC-16 ellenőrzést végez**; CRC mismatch → silent drop. Becsült terület 500–2000 gate → **600–800 gate**. Új alszekció: "Miért nincs logikai validáció — CFPU single-layer trust elv". Threat model frissítve: a "rosszindulatú aktor hamis SEAL_CST_INSTALL üzenete" sor **nem reális fenyegetés** (CST router-szinten kizárt), helyette "bit-flip / SEU NoC tranzit" sor (CRC fogja). Konzisztens a header v3.0 HMAC-törlés indoklásával. |
| 1.4 | 2026-05-02 | **QGate brand-név bevezetve** a per-core lokális Quench-RAM kapuőr FSM-re. Korábban "lokális SEAL FSM" / "célcore lokális SEAL FSM" / "MailBox SEAL trigger" néven futott — ezek mind ugyanazt a komponenst jelölik, és most egységesen **QGate**. A brand-családi diagram (3. szekció) bővült új sorral, az új ["A QGate komponens"](#seal-points) alszekció a komponens tulajdonságait rögzíti (1 / core, ~500–2000 gate, NoC inbox bemenet, CST QSRAM + DDR5 cap-slot QRAM kimenet). A QGate brand-pozíciója: per-core kapuőr a **Quench-RAM** alapú capability tábláknál, szemben a Seal Core globális AuthCode-gatekeeper szerepével. Hivatkozások végig átvezetve. |
| 1.3 | 2026-05-02 | **"A három SEAL érintési pont" szekció hozzáadva** (1. CODE régió SEAL — lokális Seal Core HW; 2. per-core CST/cap slot SEAL/RELEASE — NoC mailbox + célcore lokális SEAL FSM; 3. single-instance peripheria config — hardwired config port). **Korrigálva a v1.1–v1.2 hibás megfogalmazás:** korábban a per-core CST írást "dedikált hardwired config porton"-ként írtuk le; ez **HIBÁS**, mert a CST QSRAM per core él, és NoC mailbox üzenettel + célcore lokális SEAL FSM-mel íródik. A hardwired config port csak a single-instance peripheriához (DDR5 Controller stb.) tartozik. Boot 2e. lépés és validációs algoritmus átírva NoC mailbox-os szemantikára (`SEAL_CST_INSTALL`, `SEAL_CST_UPDATE`, `RELEASE_CST_ENTRY` üzenetek). Threat model frissítve: a védelem a célcore lokális SEAL FSM `src` mező ellenőrzéséből jön, nem hardwired vezeték hiányából. |
| 1.2 | 2026-05-02 | **"Authority delegáció — runtime CST policy" szekció hozzáadva.** A Seal Core mint mechanizmus (HW config port írás + kérelem-validáció) és az OS root aktor mint runtime policy szétválasztva. Boot-időben a Seal Core egyetlen GRANT_ALL CST entry-t ír az OS root aktornak; a runtime CST-műveleteket (spawn / delegate / revoke) az OS root aktor (vagy delegáltja) üzenetekkel kéri, a Seal Core firmware a supervisor link és a kérelmező saját CST capability-je alapján validálja. A konkrét üzenet-opcode-ok F4-F5 RTL döntésnek hagyva (CIL-Seal ISA). |
| 1.1 | 2026-04-28 | **DDR5 capability slot kezelés és CST írás hozzáadva** a Seal Core feladataihoz. A `ddr5-architecture-hu.md` v1.3 HW Capability Slot modellje szerint a Seal Core dedikált hardwired config porton SEAL/RELEASE-eli a per-core 8 KB capability slot táblát (256 actor × 4 slot × 8 byte). A NoC oldali CST (Capability Slot Table, `interconnect-hu.md` v3.0) is hasonlóan hardwired porton íródik. |
| 1.0 | 2026-04-16 | Kezdeti vízió-szintű kiadás. A Seal Core két különálló mechanizmusként: (1) pre-QRAM érában fizikai WE-pin routing a CODE RAM chipre; (2) QRAM érában AuthCode verifikációs gatekeeper a SEAL HW-trigger forrással. Explicit szeparáció a két érá között, nincs cross-contamination. Ring és 2D mesh failover topológiák, graceful degradation. Firmware immutability mask ROM / eFuse alapon. |
