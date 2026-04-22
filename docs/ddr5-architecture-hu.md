# CFPU DDR5 Memória Architektúra — Hardveres Tervezési Döntések

> English version: [ddr5-architecture-en.md](ddr5-architecture-en.md)

> Version: 1.1

Ez a dokumentum a CFPU és a külső DDR5 memória közötti interfész **hardveres architektúráját** rögzíti. Nem csak a végeredményt, hanem az **érvelési utat** is dokumentálja: milyen alternatívákat vizsgáltunk, miért vetettük el őket, és milyen trade-off-ok vezettek a végső döntésekhez.

> **Célközönség:** HW fejlesztők, RTL tervezők, FPGA implementátorok. Az OS-oldali (Neuron OS) nézőpontot a [NeuronOS docs/ddr5-memory-model-hu.md](https://github.com/FenySoft/NeuronOS/blob/main/docs/ddr5-memory-model-hu.md) tartalmazza.

## Kiindulópont: milyen szerepet tölt be a DDR5 a CFPU-ban?

A CFPU **shared-nothing** architektúra: minden core saját SRAM-mal rendelkezik (CODE + DATA + STACK), nincs megosztott memória, nincs cache koherencia. Ez felveti a kérdést: **hogyan érnek el a core-ok nagy külső adathalmazokat** (adatbázis, kép, ML dataset)?

A DDR5 a CFPU-ban **nem munkamemória** (mint a hagyományos CPU-knál), hanem **tároló**, amiből a core-ok SRAM-jába töltődik a tartalom:

- **Kód betöltés** — aktor kódjának SRAM CODE-ba töltése
- **Adat betöltés** — objektumok, lookup táblák SRAM DATA-ba töltése
- **Eredmény visszaírás** — feldolgozott adat kiírása
- **Nagy adatkészletek** — scatter/gather, pipeline, chunked streaming mintákkal

---

## 1. döntés: Ki közvetít a core-ok és a DDR5 között?

### 1.a) Elvetett megoldás: szoftveres gateway core-ok

Az első ötlet az volt, hogy dedikált CFPU core-ok (gateway aktorok) közvetítenek a NoC és a DDR5 PHY között — ugyanúgy, ahogy bármely periféria-kezelő aktor teszi.

**Miért vetettük el:**

```
Egy core mailbox áteresztőképessége:  ~500 MB/s - 1 GB/s
  (128 bit flit × 500 MHz ÷ ~15 ciklus feldolgozás per kérés)

DDR5 2 csatornás sávszélesség:        ~76 GB/s

76 GB/s ÷ 0.5 GB/s = ~150 gateway core kellene
```

150 core a teljes sávszélesség kihasználásához — és még akkor is minden kérés **két extra NoC hop-ot** fizet (core → gateway → DDR5, DDR5 → gateway → core). Ez elfogadhatatlan.

### 1.b) Elvetett megoldás: egyetlen Arbiter Core

A következő ötlet: a gateway core-ok végzik a jogosultság-ellenőrzést, de egyetlen Arbiter Core kezeli a PHY-t.

**Miért vetettük el:** Az Arbiter Core maga is egy szoftveres core, ~500 MB/s – 1 GB/s áteresztőképességgel. A DDR5 sávszélesség ~1%-át használná ki. A szűk keresztmetszet csak áthelyeződött, nem szűnt meg.

### 1.c) Végső döntés: hardveres RTL DDR5 Controller

A DDR5 Controller **nem programozható core**, hanem **fix RTL blokk**, amely a NoC-ra csatlakozik mint végpont. 128 bites portjain közvetlenül fogadja a core-ok kéréseit.

**Döntési érvek:**
- A DDR5 ütemezés (row activation, bank interleaving, refresh timing) **időkritikus, fix logika** — nem való általános célú core-ra
- A 128 bites adatút natívan illeszkedik a NoC flit méretéhez
- Nincs szoftveres bottleneck az útvonalon
- A HW ACL (lásd alább) nulla ciklus többletköltséggel ellenőriz

### A DDR5 Controller felépítése

```
                     NoC (128 bit széles)
                      |
        +-------------+-------------+
        |             |             |
     port 0        port 1    ...  port 9
        |             |             |
+-------+-------------+-------------+-------+
| DDR5 Controller (RTL, nem programozható)   |
|                                            |
|  10 x 128 bit port @ 500 MHz               |
|  = 10 x 8 GB/s = 80 GB/s                   |
|  ~ DDR5 2ch teljes sávszélesség            |
|                                            |
|  +----------+  +------------+  +---------+ |
|  | HW ACL   |  | Bank-aware |  | PHY     | |
|  | (CAM)    |->| Scheduler  |->| Iface   |->--> DDR5
|  +----------+  | (HW FSM)   |  +---------+ |
|                +------------+              |
|                                            |
| Config port <-- root_supervisor (hardwired)|
+--------------------------------------------+
```

---

## 2. döntés: Hogyan akadályozzuk meg, hogy egy core más core adatait olvassa/írja?

Ez a shared-nothing modell kritikus kérdése. Ha bármelyik core tetszőleges DDR5 címet olvashat, az izoláció **illúzió**.

### 2.a) A küldő azonosítása — NoC header src_core

A NoC router **hardveresen tölti ki** a flit header `src_core` mezőjét a küldő core fizikai azonosítójával. Ezt a küldő core **nem tudja felülírni**, mert a NoC router a szilícium topológiája alapján tudja, melyik portjáról érkezett a flit.

```
NoC flit --> DDR5 Controller port
+-------------------------+
| src_core : 14 bit  <-- hardver irja, nem szoftver
| dst:       DDR5 ctrl    |
| address:   0x0050_1234  |
| op:        READ/WRITE   |
+-------------------------+
```

**Analógia:** Mint a hálózatban a fizikai MAC cím — a switch tudja, melyik portról jött a keret, nem a keret tartalma mondja meg.

### 2.b) Jogosultság-ellenőrzés — hardveres CAM tábla

A DDR5 Controller minden portján **1 ciklus alatt**, pipeline-oltan ellenőrzi a jogosultságot egy CAM (Content-Addressable Memory) táblával:

```
+----------+------------+------------------+------------------+-------+
| src[24]  | src_actor  | DDR5 Start       | DDR5 End         | Jog   |
|          | [16]       |                  |                  |       |
+----------+------------+------------------+------------------+-------+
| Core 42  | Actor 7    | 0x0050_0000      | 0x0050_FFFF      | RW    |
| Core 42  | Actor 12   | 0x0100_0000      | 0x0100_0FFF      | RW    |
| Core 99  | Actor 3    | 0x0060_0000      | 0x0060_FFFF      | RW    |
+----------+------------+------------------+------------------+-------+
```

A CAM tábla `src[24] + src_actor[16]` alapján ellenőriz — **aktor szintű**, nem core szintű jogosultság-kezelés. Ez az interconnect spec v2.4-ben bevezetett header `src_actor` mezőjére épül (lásd `docs/interconnect-hu.md`).

- **PASS** → kérés a Request Queue-ba
- **DENY** → trap flit vissza a küldőnek (`InvalidMemoryAccess`)

**Miért CAM és nem szoftveres ellenőrzés?** A CAM párhuzamosan keres minden szabályban — egyetlen órajel ciklus, nulla latencia többlet. Szoftveres ellenőrzés 3-5 ciklust venne el **minden egyes kérésnél**.

### 2.c) Ki konfigurálja a CAM táblát?

A CAM táblát **kizárólag a `root_supervisor`** (Neuron OS legfelső szintű aktora) módosíthatja, **dedikált, hardwired config porton** keresztül.

**Miért nem a NoC-on?** Ha a config parancsok a NoC-on mennének, bármely kompromittált core küldhetne hamis config üzenetet. A dedikált fizikai vezeték garantálja, hogy **csak a `root_supervisor` Rich Core-ja** éri el a config regisztereket.

---

## 3. döntés: Hogyan kap hozzáférést egy aktor a DDR5-höz?

### 3.a) Elvetett megoldás: központi közvetítő minden kéréshez

Az első ötlet az volt, hogy egy Memory Service aktor közvetít minden DDR5 olvasás/írás kérést. Az aktor üzenetben kéri az adatot, a Memory Service elvégzi a DDR5 műveletet, és visszaküldi az eredményt.

**Miért vetettük el:** Minden egyes DDR5 hozzáférés **három üzenetet** igényelt volna (kérés → service → DDR5, DDR5 → service → válasz). Ez a latenciát megháromszorozza, a throughput-ot lefelezi.

### 3.b) Elvetett megoldás: a root_supervisor dönt minden betöltésről

A következő ötlet: a `root_supervisor` (OS) ütemezi, mikor és mit tölt be a core SRAM-jába — DMA-szerűen, stream módban.

**Miért vetettük el:** A `root_supervisor` nem tudhatja, mikor és milyen adatra van szüksége az aktornak. Csak az aktor maga tudja, hogy éppen milyen objektumot akar feldolgozni.

### 3.c) Végső döntés: capability modell — egyszeri engedély, szabad használat

Az aktor **egyszer kér hozzáférést** a `kernel_io_sup` aktortól (a Neuron OS I/O supervisor-a). Ha megkapja, **szabadon, közvetlenül** olvassa/írja a DDR5 tartományt MMIO-n keresztül, további engedélykérés nélkül:

```
1. Aktor --> kernel_io_sup: MsgGrantRequest(ObjectId, Access: RW)
2. kernel_io_sup ellenőriz, majd:
   kernel_io_sup --> DDR5 Controller config: regisztrál Core 42 -> tartomány
3. kernel_io_sup --> Aktor: MsgGranted(Region)
4. Aktor szabadon olvas/ír (MMIO --> DDR5 Controller port --> DDR5)
   ... ahányszor akarja, további engedély nélkül
5. Aktor --> kernel_io_sup: MsgReleaseRegion
6. kernel_io_sup --> DDR5 Controller config: törli a jogot
```

**Egyetlen tulajdonos** — egy tartományra egy időben egy core-nak lehet joga. Amíg Core 42 nem adta vissza, más core nem kaphat hozzáférést ugyanarra a tartományra. (Rust ownership analógia.)

**Döntési érvek:**
- Az aktor maga dönti el, mikor kell az adat — nem a kernel ütemezi
- A jogosultságkérés egyszeri költség (üzenet oda-vissza) — utána nulla overhead
- A capability visszavonható: ha az aktor befejezte vagy crash-el, a `kernel_io_sup` törli a jogot

---

## 4. döntés: Stream mode vs. Request mode

A DDR5 Controller két üzemmódot támogat, mert két gyökeresen eltérő használati minta van:

### Request mode — aktor aktívan dolgozik egy DDR5 tartománnyal

Az aktor a capability megkapása után MMIO-n keresztül közvetlenül olvas/ír. Tetszőleges sorrendben, tetszőlegesen sokszor.

**Mikor:** Aktív feldolgozás közben — az aktor tudja, mit akar olvasni/írni.

### Stream mode — bulk DMA transfer

A DDR5 Controller szekvenciálisan olvas/ír nagy blokkokat, és a NoC-on **push-olja** a core-ok felé.

**Mikor:**
- Induló adat betöltése SRAM DATA-ba
- Eredmény visszaírása DDR5-be

> **Megjegyzés:** A kód betöltés **nem** a DDR5-ből történik. A hitelesített kódot a **SealFlash** (non-volatile) és **SealRAM** (volatile cache) tárolja — lásd a [Kód- és adattárolás szétválasztása](#kod-adat-szetvalasztas) szekciót.

**Miért kell mindkettő?** A stream mode maximálisan kihasználja a DDR5 burst-öt (szekvenciális olvasás), de az aktor nem mindig szekvenciálisan dolgozik. A request mode rugalmas, de a DDR5 burst-kihasználás gyengébb. A kettő kombinációja fedi le a valós munkafolyamatot: stream-mel betölt, request-tel dolgozik, stream-mel visszaír.

---

## 5. döntés: PHY hozzáférés védelme

### 5.a) Elvetett megoldás: fix bekötés (hardwired, soha nem változik)

Bizonyos core-ok **fizikailag rá vannak kötve** a DDR5 PHY-ra, más core-ok nem érik el.

**Miért vetettük el a DDR5-nél:** A DDR5 Controller RTL blokk, nem core — a portjai a NoC-ra csatlakoznak, nem core-okhoz. A kérdés nem az, hogy "melyik core éri el a PHY-t", hanem "melyik core küldhet kérést a DDR5 Controller-nek" — és erre a CAM tábla a válasz.

### 5.b) Elvetett megoldás: OTP fuse (egyszer programozható)

A chip gyártásakor fuse-okkal égetik be, melyik core-ok jogosultak.

**Miért vetettük el:** Nem ad extra biztonságot a CAM tábla fölé. Ha a `root_supervisor` kompromittálódik, a fuse sem véd (mert a `root_supervisor` a trust root). Ha a `root_supervisor` épségben van, a CAM tábla is megbízható. A fuse csak a rugalmasságot veszi el, biztonsági nyereség nélkül.

### 5.c) Végső döntés: a root_supervisor vezérli a DDR5 Controller CAM tábláját

A `root_supervisor` a **capability grant** folyamat részeként írja/törli a CAM bejegyzéseket a dedikált config porton. Ez a config port **hardwired** — csak a `root_supervisor` Rich Core-ja éri el fizikailag.

**A biztonság végső soron a `root_supervisor` integritásán áll.** Ezt a Seal Core garantálja: hardveres FSM (nem microcode, nem programozható), amely aláírás-ellenőrzéssel védi a boot folyamatot, és watchdog-gal felügyeli a `root_supervisor` működését.

---

## Kapacitás összefoglaló

```
10 port x 128 bit x 500 MHz = ~5 milliárd kérés/sec
DDR5 2ch sávszélesség:          ~76 GB/s = ~4.75 milliárd x 16 byte kérés/sec
```

| Hozzáférési gyakoriság / core | Kiszolgálható core-ok |
|-------------------------------|----------------------|
| Minden ciklus                 | ~10                  |
| Minden 100. ciklus            | ~1 000               |
| Minden 1000. ciklus           | ~10 000 (teljes chip)|

A CFPU core-ok SRAM-ból dolgoznak, jellemzően a "minden 1000. ciklus" kategóriába esnek — **a 10 portos DDR5 Controller az egész chipet ki tudja szolgálni**.

---

## Perifériakezelés általános mintája

A DDR5 Controller tervezési döntései **általános mintát** adnak a többi perifériához is:

**Szabály:** ha a periféria sávszélessége megközelíti egy core áteresztőképességét (~500 MB/s), **hardveres RTL controller** kell. Ha jóval alatta van, **szoftveres gateway aktor** megoldja.

| Periféria | Sávszélesség | Megoldás | Indoklás |
|-----------|-------------|----------|----------|
| DDR5 (2ch) | ~76 GB/s | **HW Controller, multi-port, RTL** | Core nem tudja kiszolgálni |
| NVMe (x4) | ~8 GB/s | HW Controller, 1-2 port | Core határ közelében |
| 10G Ethernet | ~1.25 GB/s | Gateway core (szoftveres) | Belefér egy core-ba |
| USB / SPI / I2C | ~MB/s | Gateway core (szoftveres) | Bőven belefér |

Alacsony sávszélességű perifériáknál a gateway core **fizikailag rá van kötve** a PHY-ra (MMIO, hardwired). Más core nem éri el — nincs fizikai útvonal.

Minden esetben ugyanaz a biztonsági modell:
- **src_core** hardveresen azonosított a NoC-ban
- **HW ACL** (nagy sávszélességnél) vagy **gateway aktor jogosultság-ellenőrzése** (kis sávszélességnél)
- **Config/hozzáférés** kizárólag a `root_supervisor`-on keresztül

## Kód- és adattárolás szétválasztása <a name="kod-adat-szetvalasztas"></a>

### 6. döntés: Hol tároljuk a hitelesített kódot?

#### 6.a) Elvetett megoldás: DDR5-ben kód és adat együtt

Az első ötlet az volt, hogy a DDR5 tárolja a kódot is (stream mode-ban töltve a core SRAM CODE régiójába).

**Miért vetettük el:** A DDR5 hozzáférést a `kernel_io_sup` kezeli — ez szoftveres aktor. Ha kompromittálódik, RW jogot adhat egy támadónak a kód-tartományra, aki felülírja a kódot. A DDR5-ben tárolt kód integritása szoftveres bizalomra épül, nem hardveres garanciára.

#### 6.b) Elvetett megoldás: QRAM (Quench-RAM) a kód tárolásához

A Quench-RAM per-blokk státuszbittel, SEAL/RELEASE szemantikával rendelkezik — kiváló per-core adatvédelemre (use-after-free kizárás, atomi wipe, zero-init garancia). De kód-tárolásra **túlméretezett**: a kód nem igényel per-blokk seal/release ciklust, csak egyszerű read-only védelmet.

#### 6.c) Végső döntés: SealRAM / SealFlash

Két új memória típus, amelyek **szabványos SRAM/Flash**, de a Write Enable (WE) vonaluk **fizikailag a Seal Core-hoz kötött**:

```
                     NoC (128 bit széles)
                      |
        Core-ok olvasási kérései (MsgCodeRead)
                      |
              +-------+--------+
              | SealRAM / SealFlash Controller (RTL) |
              |                                      |
              |  NoC port: CSAK OLVASÁS              |
              |    - fogad: MsgCodeRead(addr)         |
              |    - válaszol: NoC flit (kód adat)    |
              |    - írási kérés: ELUTASÍTVA (trap)   |
              |                                      |
              |  WE port: Seal Core (hardwired)       |
              |    - fizikai vezeték                  |
              |    - NoC-ról NEM elérhető             |
              +-------+--------+
                      |
                      | WE vonal (hardwired, nem NoC)
                      |
                +-----+-----+
                | Seal Core  |
                | (HW FSM)   |
                +------------+
```

A core-ok a **NoC-on üzenettel kérik** a kódot — nincs közvetlen busz. A Controller NoC végpont, amely:
- **Olvasási kérést** fogad bármelyik core-tól (nincs ACL, mert a kód hitelesített és közös)
- **Írási kérést a NoC-ról elutasít** — a controller egyszerűen nem implementálja
- **Írás kizárólag a WE vonalon** — fizikai vezeték a Seal Core-tól

| Típus | Memória | Volatilitás | Szerep |
|-------|---------|-------------|--------|
| **SealFlash** | Szabványos NOR Flash | Non-volatile (megmarad) | Hitelesített kód **tartós tárolása** |
| **SealRAM** | Szabványos SRAM | Volatile (elvész) | Gyors kód-cache (boot-kor SealFlash-ből töltődik) |

**Döntési érvek:**
- **Nulla egyedi IP szükséges** — szabványos memória, csak a WE bekötés speciális
- **Hardveres garancia** — nem szoftver dönt az írási jogról, hanem a szilícium topológiája
- **Nem hackelhető** — nincs szoftveres útvonal a WE vonalhoz, a Seal Core HW FSM (nem microcode)
- A `root_supervisor` kompromittálása sem segít — a Seal Core független, hardveres entitás

**A kód betöltés teljes útvonala:**

```
Frissítés:
  Aláírt kódcsomag --> Seal Core (HW aláírás-ellenőrzés) --> SealFlash írás

Boot:
  Seal Core --> SealFlash --> SealRAM (másolás, gyorsítótár)

Futás:
  Core SRAM CODE <-- SealRAM (NoC read, bárki olvashat)
```

**A DDR5-ben soha nem tárolódik kód.** Ezzel a DDR5 kompromittálása kizárólag adatot érinthet, kódot nem — a támadási felület architektúrálisan csökkent.

### Három memória típus összefoglalása

| | SealRAM / SealFlash | QRAM (Quench-RAM) | DDR5 |
|---|---|---|---|
| **Tartalom** | Hitelesített kód | Per-core adat (objektumok, capability) | Munkaadatok, nagy adatkészletek |
| **Ki írhatja** | Kizárólag Seal Core (HW) | SEAL/RELEASE microcode trigger | Aktor, capability-vel |
| **Védelem típusa** | Fizikai WE vonal | Per-blokk státuszbit | CAM tábla (HW ACL) |
| **Trust root** | Seal Core (HW FSM) | Seal Core + microcode | root_supervisor (szoftver) |
| **Spec** | Ez a dokumentum | `docs/quench-ram-hu.md` | Ez a dokumentum |

---

## Changelog

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 1.0 | 2026-04-22 | Első verzió — DDR5 Controller döntési folyamat, biztonsági modell, capability grant, perifériakezelés |
| 1.1 | 2026-04-22 | SealRAM / SealFlash bevezetése kód-tárolásra, DDR5 = csak adat. Három memória típus összefoglaló tábla. |
