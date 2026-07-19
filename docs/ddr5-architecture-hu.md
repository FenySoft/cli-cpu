---
status: vision
---

# CFPU DDR5 Memória Architektúra — Hardveres Tervezési Döntések

> English version: [ddr5-architecture-en.md](ddr5-architecture-en.md)

> Version: 1.6

Ez a dokumentum a CFPU és a külső DDR5 memória közötti interfész **hardveres architektúráját** rögzíti. Nem csak a végeredményt, hanem az **érvelési utat** is dokumentálja: milyen alternatívákat vizsgáltunk, miért vetettük el őket, és milyen trade-off-ok vezettek a végső döntésekhez.

> **Célközönség:** HW fejlesztők, RTL tervezők, FPGA implementátorok. Az OS-oldali (Symphact) nézőpontot a [Symphact docs/ddr5-memory-model-hu.md](https://github.com/FenySoft/Symphact/blob/main/docs/ddr5-memory-model-hu.md) tartalmazza.

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
- A HW capability ellenőrzés (lásd alább) nulla ciklus többletköltséggel működik

### A DDR5 Controller felépítése (v1.3)

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
|  +-----------+  +------------+  +--------+ |
|  | DDR5_CAP  |  | Bank-aware |  | PHY    | |
|  | check     |->| Scheduler  |->| Iface  |->--> DDR5
|  | (~100 GE) |  | (HW FSM)   |  +--------+ |
|  +-----------+  +------------+              |
|       ^                                     |
|       | flag és range/perms ellenőrzés      |
|       | (token a payload-ban, már HW által  |
|       |  attached a forrás core-ban)        |
|                                             |
| Config port <-- Seal Core / root_supervisor |
| (hardwired, kulcs nélküli, csak engedély)   |
+---------------------------------------------+
```

**A capability adatok NEM a DDR5 Controllerben élnek.** A Controller csak a beérkező cella `flags.DDR5_CAP` bitjét és a payload-ban érkező region/offset/perms tripletet ellenőrzi. A capability **a forrás core QRAM-jában van**, és a forrás core HW request assembler-e attach-olja a kéréshez.

---

## 2. döntés: Hogyan akadályozzuk meg, hogy egy core más core adatait olvassa/írja?

Ez a shared-nothing modell kritikus kérdése. Ha bármelyik core tetszőleges DDR5 címet olvashat, az izoláció **illúzió**.

### 2.a) A küldő azonosítása — NoC header src + src_actor

A NoC router **hardveresen tölti ki** a flit header `src` (24 bit) és `src_actor` (8 bit) mezőit a küldő core fizikai azonosítójával és aktív aktor context regiszteréből. Ezt a küldő core szoftvere **nem tudja felülírni** (lásd `interconnect-hu.md` v3.2 + `cell-format-hu.md` v2.4).

```
NoC cella --> DDR5 Controller port
+---------------------------------+
| src[24]:        14 bit  <-- HW   |
| src_actor[8]:   8 bit   <-- HW   |
| dst:            DDR5 ctrl        |
| flags.DDR5_CAP: 1       <-- HW   |
| payload[0..15]: capability bytes |
| payload[16..]: offset, op, data  |
+---------------------------------+
```

**Analógia:** Mint a hálózatban a fizikai MAC cím — a switch tudja, melyik portról jött a keret, nem a keret tartalma mondja meg.

### 2.b) Jogosultság-ellenőrzés — HW Capability Slot (QRAM)

A v1.2-ben ezt egy nagy CAM tábla végezte a DDR5 Controllerben. A **CAM méret skálázási problémát mutatott** (lásd 5.b és 5.d alternatívák). A v1.3-ban a kapacitásokat **a forrás core QRAM-jában tároljuk**, és a HW request assembler attach-olja a kéréshez. A DDR5 Controller csak a határokat ellenőrzi — **nincs központi tábla, nincs HMAC**.

#### Capability Slot formátum (8 byte = 64 bit)

```
+---------------------------------------------------+
| Bit 63..32:  region_base[32]   4 KB-igazított      |
|                                lap-szám → 16 TB    |
| Bit 31..24:  reserved[8]       base 40-bitre bőv.  |
| Bit 23..8:   region_size[16]   4 KB-lapokban       |
|                                → max 256 MB        |
| Bit 7:       valid                                |
| Bit 6..4:    perms[3]          R / W / X (X: lásd) |
| Bit 3..0:    reserved (4 bit)                     |
+---------------------------------------------------+
```

A controller a tényleges byte-címet `(region_base << 12) + offset` formában rekonstruálja, a határt `offset < (region_size << 12)` szerint ellenőrzi — a slot **teljesen page-granuláris** (4 KB), a `valid`/`perms` bitek kivételével.

**Teljes page-granularitás — miért?** Mivel **két aktor sosem oszt meg egy lapot**, az izoláció eleve page-szintű, ezért a `region_base` ÉS a `region_size` is 4 KB-os lapokban értendő. Nincs sub-page megosztás → byte-pontos határra nincs szükség (a saját utolsó lapja slack-jébe olvasás nem cross-actor szivárgás, csak intra-actor).

Döntés-trail:

| Mező | Alternatíva | Választott |
|------|-------------|-----------|
| `region_base` | byte-36 (64 GB, alul) / byte-40 (1 TB, +slot) | **page-32 → 16 TB** (a 8-byte slotban) |
| `region_size` | byte-24 (16 MB, granularitás-eltérés) / byte-16 (64 KB) | **page-16 → 256 MB** (konzisztens, no page-share) |

A `reserved[8]` a base mellett a jövőbeli **40-bit page → 4 PB** bővítést tartja fenn. A core ISA **változatlanul 32-bit** — a `region_base` descriptor (adat), nem a mag által dereferált pointer (lásd lent).

**A `perms` X (execute) bit:** kizárólag **Seal-verifikált kódra** (pl. a lassú flash gyorsítására DRAM-ba cache-elt, már hitelesített kód). **Runtime-generált / nem-verifikált kód futtatása TILOS** — nincs aláírás → nincs bizalom. ⚠️ Ennek viszonya a [6. döntéshez](#kod-adat-szetvalasztas) (»DDR5 elsődlegesen adat«) és a cache-elt kód integritás-mechanizmusa (módosítás-védelem post-verifikáció) **NYITOTT kérdés** — külön döntést igényel.

**Tárolás:** **per core, QRAM-ban (Quench-RAM)**, SEAL invariáns alatt.

| Paraméter        | Érték                               |
| ---------------- | ----------------------------------- |
| Slot per actor   | 256 (`slot_id[8]`)                  |
| Aktor per core   | 256 (lásd v3.0 header)              |
| Slot mérete      | 8 byte                              |
| Slot tábla / core | 256 × 256 × 8 byte = **512 KB**? — TÚL SOK |
| **Reális allokáció** | **per aktor 4 slot** = 256 × 4 × 8 byte = **8 KB / core** |

A reális modellben minden aktor **legfeljebb 4 DDR5 capability slot**-ot kap (4 párhuzamos region — typikus workload bőven elég). Ha egy aktor többet igényel, dinamikusan újrarendelheti a slot-jait a `kernel_io_sup`-on keresztül.

**Tárolt adat:**
```
slot_table[actor_id][slot_id] = {region_base, region_size, perms, valid}
                                                        ^
                                                Quench-RAM SEAL alatt:
                                                  - Csak Seal Core írhat (RELEASE+újra-SEAL)
                                                  - Aktor SW olvasni nem tud közvetlenül
                                                  - HW request assembler olvashat (read-only path)
```

#### A kérés flow

```
Aktor CIL-T0 kód:
   ddr5_load  slot_id=N, offset=0x100, dest=R5

HW utasítás-dekóder (a forrás core-on):
1. QRAM olvasás:  slot[active_actor][N] = (region_base, size, perms, valid)
2. Valid check:   valid == 1?         (1 ciklus)
3. Offset check:  offset < size?      (1 ciklus, kombinációs)
4. Perms check:   op megengedett?     (1 ciklus, kombinációs)
5. Cella összerakás (HW, NEM software):
     header.flags.DDR5_CAP = 1   <-- HW-only writable bit
     payload[0..7]   = (region_base, size, perms)
     payload[8..11]  = offset_in_region
     payload[12..]   = op + data
6. NoC cella --> DDR5 Controller
```

#### DDR5 Controller validáció

A controller a beérkező cellán a következőket ellenőrzi:

```
1. flags.DDR5_CAP == 1?
   - NEM → trap (régi software-as-DMA, már elvetett modell)
   - IGEN → 2.

2. (region_base + offset) < region_base + region_size? (sanity check)
   (a forrás core már ellenőrizte, de a controller újraellenőrzi defense-in-depth)

3. op megengedett? (perms ellenőrzés)

4. PASS  → DDR5 PHY-hoz (Bank-aware Scheduler-en keresztül)
   FAIL → trap flit a küldőnek (InvalidMemoryAccess)
```

**Miért nincs HMAC?** A capability bytes **soha nem ér software-et**. A QRAM SEAL alatt él, a HW request assembler olvassa, és a `flags.DDR5_CAP` bit garantálja, hogy a payload első 8 byte-ja **HW-attached** (nem SW-által írt). Ha az aktor szoftvere megpróbálja kézzel összeállítani a cellát a `DDR5_CAP` bittel, a NoC router a forrás core-ban **filterezi** ezt a bitet — csak a HW assembler állíthatja be (lásd 2.c).

### 2.c) HW gate-keep — `DDR5_CAP` flag bit

A cella header `flags` mező egyik bitje (`flags.DDR5_CAP`) **csak a forrás core HW request assembler-e által írható**:

| Komponens                          | DDR5_CAP-ot ír? |
| ---------------------------------- | --------------- |
| Aktor CIL-T0 SW (`send` opkód)     | ❌ filterezett (HW maszkolja 0-ra) |
| HW request assembler (`ddr5_load`) | ✓ beállíthatja  |
| NoC router (továbbítás)            | ✓ továbbítja, nem módosítja |
| DDR5 Controller (validáció)        | csak olvas, nem ír |

A HW filter ~10 gate / core (egyszerű AND-mask az aktor `send` cella-összeállítójában).

### 2.d) Revocation — Quench-RAM RELEASE

A capability visszavonása a Quench-RAM SEAL/RELEASE mintára épül:

```
Seal Core: RELEASE(slot[actor_id][N])
   → atomi wipe: a slot fizikailag 0-ra állítódik (1 ciklus)
   → invariáns: ettől a pillanattól a HW assembler NEM tud kérést összerakni
                a slot-tal (valid==0, fail-stop)
```

**Sebesség:** 1 ciklus (slot zero-write). Nincs epoch, nincs window, nincs broadcast — a Quench-RAM atomi.

**In-flight kérések:** Ha a slot RELEASE pillanatában már van NoC-on lévő DDR5 kérés, az áthalad (a controller már megkapta a payload-ot). Ez **elfogadható**: az aktor logikailag azt látja, mintha a RELEASE picit később történt volna. A revocation **feasibility** garantált, **strict atomicity** nem (mint a TLB shootdown-nál a hagyományos OS-ekben).

### 2.e) Ki konfigurálja a slot-okat?

A capability slot-okat **kizárólag a Seal Core** írhatja, a `kernel_io_sup` aktor kérésére. A flow:

```
1. Aktor    → kernel_io_sup: MsgGrantRequest(region, size, perms)
2. kernel_io_sup: policy check, kontingens, isolation
3. kernel_io_sup → Seal Core: dedikált hardwired config porton
                              "írd be slot[actor][N] = (region, size, perms)"
4. Seal Core: a célcore QRAM-jában:
              RELEASE(slot[actor][N])    ← atomi wipe
              SEAL(slot[actor][N] = új capability)
5. kernel_io_sup → Aktor: MsgGranted(slot_id=N)
6. Aktor: ddr5_load slot=N, offset=..., dest=...
```

**Miért nem a NoC-on?** Ha a config parancsok a NoC-on mennének, bármely kompromittált core küldhetne hamis config üzenetet. A dedikált fizikai vezeték a Seal Core-tól minden core QRAM-jához garantálja, hogy **csak a Seal Core** írhat slot-okat.

---

## 3. döntés: Hogyan kap hozzáférést egy aktor a DDR5-höz?

### 3.a) Elvetett megoldás: központi közvetítő minden kéréshez

Az első ötlet az volt, hogy egy Memory Service aktor közvetít minden DDR5 olvasás/írás kérést. Az aktor üzenetben kéri az adatot, a Memory Service elvégzi a DDR5 műveletet, és visszaküldi az eredményt.

**Miért vetettük el:** Minden egyes DDR5 hozzáférés **három üzenetet** igényelt volna (kérés → service → DDR5, DDR5 → service → válasz). Ez a latenciát megháromszorozza, a throughput-ot lefelezi.

### 3.b) Elvetett megoldás: a root_supervisor dönt minden betöltésről

A következő ötlet: a `root_supervisor` (OS) ütemezi, mikor és mit tölt be a core SRAM-jába — DMA-szerűen, stream módban.

**Miért vetettük el:** A `root_supervisor` nem tudhatja, mikor és milyen adatra van szüksége az aktornak. Csak az aktor maga tudja, hogy éppen milyen objektumot akar feldolgozni.

### 3.c) Végső döntés: capability slot — egyszeri engedély, szabad használat

Az aktor **egyszer kér slot-ot** a `kernel_io_sup` aktortól. Ha megkapja, **szabadon, közvetlenül** olvassa/írja a DDR5 tartományt a `ddr5_load`/`ddr5_store` opkódokkal, további engedélykérés nélkül:

```
1. Aktor             → kernel_io_sup: MsgGrantRequest(ObjectId, Access: RW)
2. kernel_io_sup ellenőriz, majd:
   kernel_io_sup     → Seal Core (config port): írj slot-ot a célcore QRAM-jába
   Seal Core         → célcore QRAM: SEAL(slot[actor][N] = (region, size, perms))
3. kernel_io_sup     → Aktor: MsgGranted(slot_id=N)
4. Aktor: szabadon olvas/ír (ddr5_load/store --> NoC --> DDR5 Controller --> DDR5)
   ... ahányszor akarja, további engedély nélkül
5. Aktor             → kernel_io_sup: MsgReleaseRegion(slot_id=N)
6. kernel_io_sup     → Seal Core: RELEASE(slot[actor][N])
   Seal Core         → célcore QRAM: atomi wipe
```

**Egyetlen tulajdonos** — egy tartományra egy időben egy actor-nak lehet joga. Amíg Actor 7 nem adta vissza, más actor nem kaphat hozzáférést ugyanarra a tartományra. (Rust ownership analógia.)

**Döntési érvek:**
- Az aktor maga dönti el, mikor kell az adat — nem a kernel ütemezi
- A jogosultságkérés egyszeri költség (üzenet oda-vissza) — utána nulla overhead
- A capability visszavonható: ha az aktor befejezte vagy crash-el, a `kernel_io_sup` RELEASE-eli a slot-ot

---

## 4. döntés: Stream mode vs. Request mode

A DDR5 Controller két üzemmódot támogat, mert két gyökeresen eltérő használati minta van:

### Request mode — aktor aktívan dolgozik egy DDR5 tartománnyal

Az aktor a slot megkapása után `ddr5_load`/`ddr5_store` opkódokkal közvetlenül olvas/ír. Tetszőleges sorrendben, tetszőlegesen sokszor.

**Mikor:** Aktív feldolgozás közben — az aktor tudja, mit akar olvasni/írni.

### Stream mode — bulk DMA transfer

A DDR5 Controller szekvenciálisan olvas/ír nagy blokkokat, és a NoC-on **push-olja** a core-ok felé. A stream parancs is capability-alapú: a `kernel_io_sup` egy speciális stream-slot-ot ad, ami egy nagy, szekvenciális tartományra jogosít.

**Mikor:**
- Induló adat betöltése SRAM DATA-ba
- Eredmény visszaírása DDR5-be

> **Megjegyzés:** A kód betöltés **nem** a DDR5-ből történik. A hitelesített kódot a **SealFlash** (non-volatile) és **SealRAM** (volatile cache) tárolja — lásd a [Kód- és adattárolás szétválasztása](#kod-adat-szetvalasztas) szekciót.

**Miért kell mindkettő?** A stream mode maximálisan kihasználja a DDR5 burst-öt (szekvenciális olvasás), de az aktor nem mindig szekvenciálisan dolgozik. A request mode rugalmas, de a DDR5 burst-kihasználás gyengébb. A kettő kombinációja fedi le a valós munkafolyamatot: stream-mel betölt, request-tel dolgozik, stream-mel visszaír.

---

## Címzési modell: capability-szegmentálás és a >4 GB adat

> **Státusz:** a capability slot szélesítése (2.b) és a low-level primitívek (`ddr5_load`/stream) rögzítettek; a magas szintű programozói lowering (streaming-absztrakció → chunk-stream) **tervezési szándék** (CFPU toolchain, F2/F3), nem kész funkció.

### A mechanizmus: capability-alapú szegmentálás

A `slot_id + offset` címzés strukturálisan a **szegmentálás** (DS/CS) leszármazottja: a slot egy bázist (`region_base`) ad, az offset hozzáadódik. A választás indoka **nem a programozói kényelem** — egy managed runtime (.NET) **bármely** memória-modellt elrejt, laposat és szegmentáltat egyaránt (a .NET tiltja a nyers cross-object pointer-aritmetikát, ami felfedné). A valódi indok kettő:

1. **HW-kényszerített izoláció.** A capability nem puszta bázis, hanem `base + size + perms + valid`, QRAM-védett, HW-attached, nem hamisítható → ez az aktorok közti hardveres elszigetelés alapja, amit a runtime önmagában egy kompromittált aktor ellen nem garantálna.
2. **Terület.** A védelemnek laknia kell valahol: az x86-nak volt szegmentálása ÉS paging-je — a paging-et tartotta meg (lapos + per-lap) és a szegmentálást eldobta. A CFPU fordítva: **eldobja az MMU/paging-et** (egy teljes MMU + TLB + page-walk × több ezer mag = túl sok terület), és **capability-szegmentálással** ad izolációt — ez olcsóbb magonként → több mag fér el (lásd [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md): TLP > ILP).

### A >4 GB adat: descriptor, nem pointer

A core ISA **32-bit marad**. A >4 GB adatot nem flat pointerrel éri el senki:

- A széles fizikai cím (`region_base`) egy **descriptor (adat)**, amit a szoftver kiszámol és továbbad — nem pointer, amit dereferál. Egy 32-bites mag tud 40-bites descriptorral számolni (multi-word), mert sosem dereferálja; a tényleges hozzáférést a **controller** végzi.
- Az **OS/runtime** (`kernel_io_sup`) ismeri a teljes dataset helyét/méretét (TB-skála), és **chunkokra bontva** stream-eli/particionálja. Így TB-t menedzsel 32-bites magokon.
- Az **aktor** csak a saját ≤256 MB ablakát látja (`region_size[16]`, 4 KB-lapokban), 32-bites korlátos offsettel, ~256 KB-onként a lokális SRAM-ban.

### Programozói modell (tervezési szándék)

A programozó **streaming/ablakos absztrakciót** ír (idiomatikus .NET — `foreach`, `Span`, LINQ), a chunk-váltást (új grant, `region_base` léptetés) a toolchain/runtime generálja — nem a forráskód juggle-öli a „szegmenst". Ez a különbség a DOS-kori `far`-pointer modelltől, ahol a szegmens-kezelés a forrásba szivárgott. (A managed runtime amúgy a klasszikus DS/CS-t is elrejtené — a megkülönböztetés tehát nem ergonómiai, lásd fent.)

### Az irreducibilis korlát

Egy esetet **semmilyen runtime nem rejt el**: random hozzáférés egyetlen >4 GB lapos struktúrán (pl. 10 GB hash-tábla szétszórt eléréssel). Itt a flat-64 HW valódian nyer; a capability/streaming modell chunk-váltásonként grant-fordulót fizet. A CFPU ezt a workload-osztályt **tudatosan elengedi** — a particionálható/streamelhető terhelésre optimalizál (rendszer-throughput a mérce, nem single-thread random latency).

---

## 5. döntés: Hol éljen a capability tábla?

Ez a v1.3 fő architektúrális kérdése. Öt alternatívát értékeltünk:

### 5.a) Elvetett: szoftveres capability service (Memory Service aktor)

Lásd 3.a). Throughput-bottleneck, latency 3×.

### 5.b) Elvetett: központi CAM tábla a DDR5 Controllerben (v1.0–v1.2 modell)

Minden capability bejegyzés egy nagy CAM-ban, port-onként ellenőrzve.

**Számítás:**
- Max bejegyzés: 10 240 core × 256 actor × 1 grant = **2,6 millió**
- Realisztikus (10–50%): 260K–1,3M bejegyzés
- Per bejegyzés: ~21 byte (key + region + perms)
- Total CAM: **~21 MB** at 1M entry
- Per port × 10 port: **~210 MB CAM** (replikált) vagy megosztott (latency contention)

**Iparági referenciák:** Cisco router TCAM-ek tíz MB-os tartományban, **dedikált ASIC chipekben**. On-chip CPU CAM-ok 1K–16K entry. 1M+ entry on-chip CAM **a chip 10–20%-át foglalná** 5nm-en.

**Miért vetettük el:** irreálisan nagy. A v1.0–v1.2 modell skálázási hibája.

### 5.c) Elvetett: capability token + HMAC (CHERI/seL4 minta)

Az aktor 16-byte tokent kap a grant pillanatában (region + perms + epoch + HMAC). A tokent a saját SRAM-jában tárolja, és minden DDR5 kéréshez csatolja. A controller HMAC-cal validál.

**Miért vetettük el:** A HMAC akkor szükséges, ha a token **szoftverre kerül** (mert az aktor SW módosíthatja). A CFPU-ban viszont van Quench-RAM SEAL — a slot-okat HW-managed QRAM-ban tarthatjuk, ahol az aktor SW **nem írhat** (5.d). A HMAC ekkor redundáns kripto-overhead, a HW garanciák önmagukban elegendők.

**HW költség (ami megspórolódik):** ~3 250 gate / port × 10 port = ~32 500 gate (SipHash-128 engine + epoch logika). Kis méret, de felesleges.

### 5.d) Elvetett: per-core CAM, központi DDR5 controller-ben

10 240 core × 1 entry/core × 21 byte = ~215 KB CAM. Kezelhető méretben, de:
- Csak core-szintű ACL, **nincs aktor-szintű izoláció**
- Egy core többi aktora is hozzáfér, ha valamelyik aktornak van grant-je

**Miért vetettük el:** sérti az aktor-szintű izoláció elvét (`interconnect-hu.md` v3.0 CST modell aktor-szintű, ezt kell megőrizni).

### 5.e) **Végső döntés: HW Capability Slot a forrás core QRAM-jában**

A capability tábla **nem** a DDR5 Controllerben van, hanem **per core, QRAM-ban**, SEAL invariáns alatt. A HW request assembler olvassa, és a `flags.DDR5_CAP` bit garantálja a HW-attachment-et.

**Költség:**
- Per core: ~8 KB QRAM (256 actor × 4 slot × 8 byte) — `core-types-hu.md` szerinti SRAM-on belül allokálva
- Per core: ~500 gate (HW request assembler + filter)
- Per DDR5 controller port: ~100 gate (range + perms check)
- × 10 port: ~1 000 gate
- × 10 240 core: ~5,1 M gate (assembler) + ~84 MB QRAM összesen — de **per-core, lokálisan**, nem központosítva → **nem skálázási probléma**

**Miért ez a választás:**
- **Skálázódik:** a slot tárolás per-core, egy chip nem tud elromlani csak a slot mennyiségtől
- **Aktor-szintű izoláció:** a slot tábla actor_id-vel indexelt
- **Nincs kripto:** Quench-RAM SEAL elég
- **Atomi revocation:** Quench-RAM RELEASE
- **Konzisztens a v3.0 CST modellel:** azonos filozófia (HW-managed capability), külön implementáció

**A biztonság végső soron a Seal Core integritásán áll.** Ezt a Seal Core HW FSM (nem microcode, nem programozható) garantálja: aláírás-ellenőrzéssel védi a boot folyamatot, és watchdog-gal felügyeli a `root_supervisor` és a `kernel_io_sup` működését.

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
| DDR5 (2ch) | ~76 GB/s | **HW Controller, multi-port, RTL + capability slot** | Core nem tudja kiszolgálni |
| NVMe (x4) | ~8 GB/s | HW Controller, 1-2 port + capability slot | Core határ közelében |
| 10G Ethernet | ~1.25 GB/s | Gateway core (szoftveres) | Belefér egy core-ba |
| USB / SPI / I2C | ~MB/s | Gateway core (szoftveres) | Bőven belefér |

Alacsony sávszélességű perifériáknál a gateway core **fizikailag rá van kötve** a PHY-ra (MMIO, hardwired). Más core nem éri el — nincs fizikai útvonal.

Minden esetben ugyanaz a biztonsági modell:
- **src + src_actor** hardveresen azonosított a NoC-ban
- **HW capability slot** (nagy sávszélességnél) vagy **gateway aktor jogosultság-ellenőrzése** (kis sávszélességnél)
- **Slot konfiguráció** kizárólag a Seal Core-on keresztül (`kernel_io_sup` policy alapján)

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

**A DDR5-ben alapesetben nem tárolódik kód.** Ezzel a DDR5 kompromittálása kizárólag adatot érinthet, kódot nem — a támadási felület architektúrálisan csökkent.

> ⚠️ **Nyitott kérdés (v1.5):** a capability slot `perms` X bitje fenntart egy jövőbeli esetet, amikor **Seal-verifikált kód DRAM-ba cache-elhető** (a lassú flash gyorsítására). Ez feszül a fenti „alapesetben nem kód" elvvel. A reconciliation — és a cache-elt kód **integritás-mechanizmusa** (módosítás-védelem post-verifikáció, pl. W⊕X) — még **nincs eldöntve**. Amíg nincs, a DDR5 **csak adatot** tárol; a runtime-generált / nem-verifikált kód futtatása **minden esetben TILOS**.

### Három memória típus összefoglalása

| | SealRAM / SealFlash | QRAM (Quench-RAM) | DDR5 |
|---|---|---|---|
| **Tartalom** | Hitelesített kód | Per-core adat (objektumok, **DDR5 capability slotok**) | Munkaadatok, nagy adatkészletek |
| **Ki írhatja** | Kizárólag Seal Core (HW) | SEAL/RELEASE HW FSM trigger | Aktor, capability slot-tal |
| **Védelem típusa** | Fizikai WE vonal | Per-blokk státuszbit | **HW capability slot** (per core QRAM-ban, SEAL alatt) + `flags.DDR5_CAP` HW-only bit |
| **Trust root** | Seal Core (HW FSM) | Seal Core + HW FSM | **Seal Core (capability slot kezeli)** + `kernel_io_sup` (policy) |
| **Spec** | Ez a dokumentum | `docs/quench-ram-hu.md` | Ez a dokumentum |

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.6 | 2026-07-17 | **Elavult cell-format hivatkozás frissítve:** `cell-format-hu.md` v2.1 → **v2.4** (kaszkád a hatályos spec-ből). |
| 1.5 | 2026-06-02 | **Capability slot teljes page-granularitás + perms X pontosítás.** A `region_size` is **bájt → 4 KB page-granuláris** (most 16-bit → 256 MB max régió), a base mellett **`reserved[8]`** a jövőbeli 40-bit page (4 PB) bővítéshez. Indok: mivel **két aktor sosem oszt meg lapot** (felhasználói döntés), az izoláció page-szintű → a byte-pontos size felesleges (intra-actor bug-fogó lett volna, nem izoláció). Új layout: `region_base[32] + reserved[8] + region_size[16] + valid[1] + perms[3] + reserved[4]`. **`perms` X bit:** kizárólag **Seal-verifikált kódra** (DRAM-mint-flash-cache); **runtime-generált kód TILOS** (nem hitelesíthető). ⚠️ Az X viszonya a 6. döntéshez (»DDR5 = adat«) + a cache-elt kód integritás-mechanizmusa **NYITOTT**. Bit-formátum csak ebben + quench-ram-hu.md-ben él (sweep igazolva). |
| 1.4 | 2026-06-01 | **Capability slot: `region_base` 36-bit byte-cím → 32-bit page-aligned (4 KB) → 16 TB.** A korábbi 36-bit (64 GB) alulméretezett a mai kapacitásokhoz (128 GB fogyasztói RAM, 1+ TB szerver/akcelerátor horizont). A page-igazítás 16 TB-ot ad ugyanabban a 8-byte slotban (32+24+1+3=60 bit). Döntés-trail: byte-36 (alul) / byte-40 (nagyobb slot) / **page-32 (választott)**. **Új „Címzési modell" szakasz:** (1) a `slot_id + offset` capability-alapú **szegmentálás** — a valódi indok HW-izoláció + terület (NEM ergonómia, mert a managed runtime bármely modellt elrejt, a klasszikus DS/CS-t is); (2) a >4 GB adat **descriptor (adat), nem pointer** — a core ISA 32-bit marad, a széles cím a controllerben/capability-ben él, az OS chunkolva stream-eli; (3) programozói modell = streaming-lowering (**tervezési szándék**, F2/F3); (4) irreducibilis korlát: random hozzáférés >4 GB lapos struktúrán — itt flat-64 nyer, a CFPU tudatosan elengedi. Core ISA változatlanul 32-bit. |
| 1.3 | 2026-04-28 | **CAM tábla → HW Capability Slot (QRAM-ban).** Az 5.b-ben elvetett 21 MB-os központi CAM helyett: minden core QRAM-jában 8 KB capability slot tábla (256 actor × 4 slot × 8 byte), Seal Core SEAL/RELEASE-szel kezelve. Új `flags.DDR5_CAP` HW-only header bit a cellán (csak a forrás core HW request assembler állíthatja, az aktor SW nem). Az 5.c capability token + HMAC alternatíva is elvetve (a HMAC redundáns, ha a Quench-RAM SEAL gate-keep elegendő). Új döntés-trail: 5.a–5.e (szoftveres / CAM / HMAC token / per-core CAM / **HW Capability Slot**). Revocation = QRAM RELEASE (atomi, 1 ciklus). Memória összefoglaló tábla DDR5 sora frissítve. **Indoklás:** central CAM nem skálázódik on-chip, a Quench-RAM és a v3.0 CST modell mintát ad egy stateless, HW-only capability mechanizmushoz |
| 1.2 | 2026-04-24 | src_actor mező 16→8 bitre szűkítve (max 256 actor/core), összhangban a CST modellel és az interconnect spec-kel. |
| 1.1 | 2026-04-22 | SealRAM / SealFlash bevezetése kód-tárolásra, DDR5 = csak adat. Három memória típus összefoglaló tábla. |
| 1.0 | 2026-04-22 | Első verzió — DDR5 Controller döntési folyamat, biztonsági modell, capability grant, perifériakezelés |
