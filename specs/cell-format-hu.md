# CFPU NoC Cella Formátum

> English version: [cell-format-en.md](cell-format-en.md)

> Version: 1.0

> Forrás: `docs/interconnect-hu.md` v2.4 (2026-04-22)

Ez a specifikáció a CFPU NoC hálózatán utazó **cella** (üzenetcsomag) pontos bináris formátumát definiálja.

## Cella struktúra

ATM-inspirált fix buffer, változó link foglalás: **16 byte header + 0–256 byte payload**.

A router buffer-ek fix méretűek (272 byte slot). A linken csak a header + `len` byte payload utazik.

```
Cella = Header (16 byte) + Payload (0-256 byte)

Buffer:  mindig 272 byte slot (fix, determinisztikus SRAM kezelés)
Linken:  16 + len byte (változó, hatékony link kihasználás)
```

## Header (16 byte = 128 bit)

```
┌──────────────────────────────────────────────────────┐
│  Bit 127..104: dst[24]          — cél HW cím         │
│  Bit 103..80:  src[24]          — forrás HW cím      │
│  Bit 79..64:   src_actor[16]    — küldő aktor        │
│  Bit 63..48:   dst_actor[16]    — cél aktor          │
│  Bit 47..40:   seq[8]           — sorszám            │
│  Bit 39..32:   flags[8]         — vezérlőbitek       │
│  Bit 31..23:   len[9]           — payload méret      │
│  Bit 22..15:   CRC-8[8]         — header integritás  │
│  Bit 14..0:    reserved[15]     — jövőbeli           │
└──────────────────────────────────────────────────────┘
```

### Mezők

| Mező | Bitek | Méret | Ki írja | Hamisítható? | Leírás |
|------|-------|-------|---------|-------------|--------|
| `dst` | 127..104 | 24 bit | Küldő core | — | Cél hierarchikus HW cím (region.tile.cluster.core) |
| `src` | 103..80 | 24 bit | **NoC router HW** | **Nem** | Forrás HW cím — a router hardveresen tölti ki a küldő core fizikai pozíciója alapján |
| `src_actor` | 79..64 | 16 bit | Core scheduler | Core-on belül igen | Küldő aktor azonosítója (0–65 535) |
| `dst_actor` | 63..48 | 16 bit | Küldő aktor | — | Cél aktor azonosítója (0–65 535) |
| `seq` | 47..40 | 8 bit | Küldő | — | Sorszám fragmentált üzenetek sorrendjéhez |
| `flags` | 39..32 | 8 bit | Küldő | — | VN0/VN1 (bit 0), relay flag (bit 1), többi reserved |
| `len` | 31..23 | 9 bit | Küldő | — | Payload tényleges mérete byte-ban (0–256) |
| `CRC-8` | 22..15 | 8 bit | HW | — | Header integritás ellenőrzés |
| `reserved` | 14..0 | 15 bit | — | — | Jövőbeli bővítés (QoS, stb.) |

### flags mező részletezés

| Bit | Név | Jelentés |
|-----|-----|---------|
| 0 | `vn` | 0 = VN1 (actor üzenet), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 1 | `relay` | 1 = relay üzenet (L3 fault tolerance, lásd interconnect spec) |
| 2–7 | reserved | Jövőbeli használat |

## Payload (0–256 byte)

Az alkalmazásadat. A `len` mező határozza meg a tényleges méretet. A router a payload tartalmát **nem vizsgálja** — az kizárólag a fogadó core dolga.

Az Actor ID korábban (interconnect v1.8) a payload első byte-jaiban volt (szoftveres dispatch). A v2.4-től a `src_actor` és `dst_actor` a header-ben van — a payload **teljes egészében alkalmazásadat**.

## Változó link foglalás

A router buffer fix (272 byte slot), de a linken **csak a tényleges adat utazik**:

```
128 bites belső adatút:
  payload_flits = ceil(len / 16)    ← 5 bites jobb-shift + carry
  total_flits = 1 (header) + payload_flits
```

| len (byte) | Payload flitek | Összes flit | Byte a linken |
|-----------|---------------|------------|---------------|
| 0 | 0 | 1 | 16 |
| 8 | 1 | 2 | 32 |
| 16 | 1 | 2 | 32 |
| 32 | 2 | 3 | 48 |
| 64 | 4 | 5 | 80 |
| 128 | 8 | 9 | 144 |
| 192 | 12 | 13 | 208 |
| 256 | 16 | 17 | 272 |

**HW költség:** 5 bites visszaszámláló per router port + jobb-shift. Nincs LUT, nincs tail bit, nincs link-szélességi overhead.

## Split SRAM design

A header és a payload **külön SRAM-ban** tárolódik a routerben:

```
Header SRAM:   slot × 16 byte    (shift-es címzés)
Payload SRAM:  slot × 256 byte   (shift-es címzés, 2-hatvány)
```

A scheduler a headert olvassa a routing döntéshez, miközben a payload még érkezik — **1 ciklus latencia-megtakarítás**. Nincs port-verseny a scheduler és a crossbar között.

## DDR5 burst illeszkedés

A 256 byte-os payload pontosan **4 × DDR5 burst** (64 byte/burst):

| DDR5 burst szám | Payload méret | Cella szám |
|-----------------|---------------|------------|
| 1× (64 byte) | 64 | 1 |
| 2× (128 byte) | 128 | 1 |
| 3× (192 byte) | 192 | 1 |
| 4× (256 byte) | 256 | 1 |
| 5× (320 byte) | 256 + 64 | 2 |

## RTL paraméterek

| Paraméter | Alapértelmezett | Tartomány | Hatás |
|-----------|----------------|-----------|-------|
| `CELL_SIZE` | 256 | 64 / 128 / 256 | Payload max méret. Buffer slot = 16 (header) + CELL_SIZE (payload) |

## Döntési napló

### 1. döntés: Miért fix buffer, változó link?

**Elvetett:** Teljesen fix cella (mindig teljes méret a linken). Az actor üzenetek ~80%-a ≤48 byte — a fix foglalás a link kapacitás nagy részét pazarolja.

**Elvetett:** Változó méretű buffer. Fragmentáció, bonyolult SRAM kezelés, nem-determinisztikus időzítés.

**Végső döntés:** Fix buffer + változó link. A buffer determinisztikus (ATM elv), a link hatékony. HW költség: 5 bites számláló per port.

### 2. döntés: Miért 256 byte payload?

**Korábbi döntés (2026-04-20):** 64 byte volt az alapértelmezett, mert fix link foglalásnál a nagyobb cella lassabb worst-case latenciát adott.

**Felülvizsgálat (2026-04-22):** A változó link foglalás bevezetésével a nagy payload hátrányai **megszűntek**:
- Rövid üzenetek (≤64 byte): **ugyanannyi flit** — nincs hátrány
- Hosszú üzenetek: **egy cella elég** — nincs darabolás, kevesebb header overhead

**Döntő érvek a 256 byte mellett:**
- **4 × DDR5 burst** (64 byte) elfér egyetlen cellában — a periféria-kezelés természetes egysége
- **2-hatvány** payload méret — egyszerű shift-es SRAM címzés
- **`len[9]`** (max 511) bőven lefedi — 1 bit-tel több mint `len[8]`, 15 bit reserved marad

**Végső döntés (2026-04-22):** 256 byte az alapértelmezett (`CELL_SIZE = 256`). Kisebb értékek (64, 128) RTL paraméterként elérhetők.

### 3. döntés: Miért `src_actor` / `dst_actor` a header-ben?

**Elvetett (v1.8):** Actor ID a payload-ban, szoftveres dispatch. Az N:M actor-to-core mapping miatt a DDR5 Controller és a crash recovery nem tudta megkülönböztetni az aktorokat core szinten.

**Végső döntés (v2.4):** 16 bit src_actor + 16 bit dst_actor a header-ben. Hardveres előnyök:
- DDR5 CAM tábla aktor-szintű ACL (`src[24] + src_actor[16]`)
- Crash recovery: csak az adott aktor capability-jét törli
- Router dispatch: header-ből olvasható, nem kell payload-ba nyúlni
- 16 bit: 65 536 aktor/core, lefedi az alvó aktorokat is

### 4. döntés: Miért `len[9]` és nem `len[8]` vagy `len[16]`?

**Elvetett:** `len[8]` (max 255). Nem fedi le a 256 byte-os payload-ot.

**Elvetett:** `len[16]` (max 65 535). Túlméretezett — a felszabadult bitek hasznosabbak actor ID-nak.

**Végső döntés:** `len[9]` (max 511). Pontosan lefedi a 256 byte-os payload-ot, és 15 bit reserved marad.

## Changelog

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 1.0 | 2026-04-22 | Első verzió — 256 byte payload, len[9], header bitmezők, változó link foglalás, DDR5 burst illeszkedés, döntési napló |
