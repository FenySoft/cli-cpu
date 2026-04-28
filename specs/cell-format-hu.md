# CFPU NoC Cella Formátum

> English version: [cell-format-en.md](cell-format-en.md)

> Version: 2.0

> Forrás: `docs/interconnect-hu.md` v2.4 (2026-04-22)

Ez a specifikáció a CFPU NoC hálózatán utazó **cella** (üzenetcsomag) pontos bináris formátumát definiálja.

## Cella struktúra

ATM-inspirált fix buffer, változó link foglalás: **16 byte header + 1–256 byte payload**.

A router buffer-ek fix méretűek (272 byte slot). A linken csak a header + tényleges payload utazik.

```
Cella = Header (16 byte) + Payload (1-256 byte)

Buffer:  mindig 272 byte slot (fix, determinisztikus SRAM kezelés)
Linken:  16 + payload byte (változó, hatékony link kihasználás)
```

> **Megjegyzés:** 0 byte-os payload (csak header) a `flags.zero_len` bittel jelölhető — ilyenkor a `len` mező nem értelmezett.

## Header (16 byte = 128 bit)

4 × 32 bit szó:

```
Szó 0: dst[24] + dst_actor[8]                    = 32 bit  — cél
Szó 1: src[24] + src_actor[8]                     = 32 bit  — forrás
Szó 2: seq[16] + flags[8] + len[8]                = 32 bit  — control
Szó 3: reserved[8] + CRC-16[16] + CRC-8[8]        = 32 bit  — integrity
```

```
┌──────────────────────────────────────────────────────┐
│  Bit 127..104: dst[24]          — cél HW cím         │
│  Bit 103..96:  dst_actor[8]     — cél aktor          │
│  Bit 95..72:   src[24]          — forrás HW cím      │
│  Bit 71..64:   src_actor[8]     — küldő aktor        │
│  Bit 63..48:   seq[16]          — sorszám            │
│  Bit 47..40:   flags[8]         — vezérlőbitek       │
│  Bit 39..32:   len[8]           — payload méret      │
│  Bit 31..24:   reserved[8]      — jövőbeli           │
│  Bit 23..8:    CRC-16[16]       — payload integritás │
│  Bit 7..0:     CRC-8[8]         — header integritás  │
└──────────────────────────────────────────────────────┘
```

### Mezők

| Mező | Bitek | Méret | Ki írja | Hamisítható? | Leírás |
|------|-------|-------|---------|-------------|--------|
| `dst` | 127..104 | 24 bit | Küldő core | — | Cél hierarchikus HW cím (region.tile.cluster.core) |
| `dst_actor` | 103..96 | 8 bit | Küldő aktor | — | Cél aktor azonosítója (0–255) |
| `src` | 95..72 | 24 bit | **NoC router HW** | **Nem** | Forrás HW cím — a router hardveresen tölti ki a küldő core fizikai pozíciója alapján |
| `src_actor` | 71..64 | 8 bit | **Core HW** | **Nem** | Küldő aktor azonosítója (0–255) — az aktív actor context regiszterből, HW-managed, nem hamisítható |
| `seq` | 63..48 | 16 bit | Küldő | — | Sorszám fragmentált üzenetek sorrendjéhez |
| `flags` | 47..40 | 8 bit | Küldő | — | Vezérlőbitek (lásd alább) |
| `len` | 39..32 | 8 bit | Küldő | — | Payload méret: `len + 1` = 1–256 byte. 0 byte-os payload → `flags.zero_len` |
| `reserved` | 31..24 | 8 bit | — | — | Jövőbeli bővítés (QoS, stb.) |
| `CRC-16` | 23..8 | 16 bit | HW | — | Payload integritás ellenőrzés — a payload fölött számolva |
| `CRC-8` | 7..0 | 8 bit | HW | — | Header integritás ellenőrzés — a header bit 127..8 fölött számolva (beleértve CRC-16-ot) |

### flags mező részletezés

| Bit | Név | Jelentés |
|-----|-----|---------|
| 7 | `vn` | 0 = VN1 (actor üzenet), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 6 | `relay` | 1 = relay üzenet (L3 fault tolerance, lásd interconnect spec) |
| 5..4 | `pri` | Prioritás (00 = normál, 01–11 = jövőbeli QoS szintek) |
| 3 | `zero_len` | 1 = nincs payload (0 byte), a `len` mező nem értelmezett |
| 2..0 | reserved | Jövőbeli használat |

## Payload (1–256 byte)

Az alkalmazásadat. A `len` mező (`len + 1`) határozza meg a tényleges méretet. Ha `flags.zero_len = 1`, nincs payload. A router a payload tartalmát **nem vizsgálja** — az kizárólag a fogadó core dolga.

Az Actor ID korábban (interconnect v1.8) a payload első byte-jaiban volt (szoftveres dispatch). A v2.4-től a `src_actor` és `dst_actor` a header-ben van — a payload **teljes egészében alkalmazásadat**.

## Változó link foglalás

A router buffer fix (272 byte slot), de a linken **csak a tényleges adat utazik**.

### 128 bites belső adatút

```
payload_flits = ceil(len_bytes / 16)    ← 4 bites jobb-shift + carry
total_flits = 1 (header) + payload_flits
```

| Payload (byte) | Payload flitek | Összes flit | Byte a linken |
|---------------|---------------|------------|---------------|
| 0 (zero_len) | 0 | 1 | 16 |
| 1 | 1 | 2 | 32 |
| 8 | 1 | 2 | 32 |
| 16 | 1 | 2 | 32 |
| 32 | 2 | 3 | 48 |
| 64 | 4 | 5 | 80 |
| 128 | 8 | 9 | 144 |
| 192 | 12 | 13 | 208 |
| 256 | 16 | 17 | 272 |

### 256 bites belső adatút

```
payload_flits = ceil(len_bytes / 32)    ← 5 bites jobb-shift + carry
total_flits = 1 (header) + payload_flits
```

> **Megjegyzés:** A 128 bites header egyetlen 256 bites flit alsó felébe kerül (felső 128 bit = 0 vagy első 16 byte payload). Az implementáció dönthet a header+payload összevonásról az első flitben.

| Payload (byte) | Payload flitek | Összes flit | Byte a linken |
|---------------|---------------|------------|---------------|
| 0 (zero_len) | 0 | 1 | 32 |
| 1 | 1 | 2 | 64 |
| 16 | 1 | 2 | 64 |
| 32 | 1 | 2 | 64 |
| 64 | 2 | 3 | 96 |
| 128 | 4 | 5 | 160 |
| 192 | 6 | 7 | 224 |
| 256 | 8 | 9 | 288 |

**HW költség:** Visszaszámláló per router port + jobb-shift. Nincs LUT, nincs tail bit, nincs link-szélességi overhead.

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
- **`len[8]`** + 1 kódolással 1–256 byte lefedhető; 0 byte-os payload külön flag-gel jelölve

**Végső döntés (2026-04-22):** 256 byte az alapértelmezett (`CELL_SIZE = 256`). Kisebb értékek (64, 128) RTL paraméterként elérhetők.

### 3. döntés: Miért `src_actor` / `dst_actor` a header-ben?

**Elvetett (v1.8):** Actor ID a payload-ban, szoftveres dispatch. Az N:M actor-to-core mapping miatt a DDR5 Controller és a crash recovery nem tudta megkülönböztetni az aktorokat core szinten.

**v2.4 döntés:** Actor ID-k a header-be kerültek.

**v2.0 felülvizsgálat (2026-04-28):** 16 bit → 8 bit actor ID, mert:
- 256 aktor/core elegendő: a CST (Context Switch Table) HW-managed — az aktív actor context regiszter hardveresen tölti a `src_actor` mezőt, **nem hamisítható** (a core szoftvere nem írhatja felül)
- A felszabadult 2 × 8 bit (összesen 16 bit) a `seq` mezőt 8 → 16 bitre bővíti, ami nagyobb fragmentált üzeneteket tesz lehetővé
- DDR5 CAM tábla aktor-szintű ACL továbbra is működik (`src[24] + src_actor[8]`)
- Crash recovery: csak az adott aktor capability-jét törli
- Router dispatch: header-ből olvasható, nem kell payload-ba nyúlni

**Végső döntés (v2.0):** 8 bit src_actor + 8 bit dst_actor a header-ben. A `src_actor`-t a core HW tölti ki (CST aktív context regiszter), a router a `src`-t tölti ki — mindkettő nem hamisítható.

### 4. döntés: Miért `len[8]` (len+1 kódolás)?

**Elvetett (v1.0):** `len[9]` (max 511). Lefedi a 256 byte-ot, de 1 bit pazarlás — a 257–511 tartomány soha nem használt.

**Elvetett:** `len[16]` (max 65 535). Túlméretezett — a felszabadult bitek hasznosabbak máshol.

**Elvetett:** `len[8]` direkt kódolás (max 255). Nem fedi le a 256 byte-os payload-ot.

**Végső döntés (v2.0):** `len[8]` + 1 kódolás: a tárolt érték 0–255, a tényleges payload méret `len + 1` = 1–256 byte. A 0 byte-os (csak header) üzeneteket a `flags.zero_len` bit jelzi. Előnyök:
- 8 bit: szó-határ illeszkedés (32 bit szó részeként)
- Teljes 1–256 tartomány lefedése veszteség nélkül
- A felszabadult 1 bit (len[9] → len[8]) + a korábbi reserved-ből összesen a CRC-16-nak adott helyet

### 5. döntés: Miért CRC-16 a payload-hoz?

**v1.0-ban:** Csak CRC-8 a header fölött. A payload integritását nem ellenőriztük hardveresen.

**Végső döntés (v2.0):** CRC-16 (16 bit) a payload fölött számolva, a header Szó 3-ban tárolva. A CRC-8 (8 bit) ezután a teljes header (bit 127..8) fölött számolódik, **beleértve a CRC-16 értékét**. Így a header integritás a payload CRC-t is védi — egyetlen bit-flip sem marad észrevétlen.

## Changelog

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 2.0 | 2026-04-28 | Header átszervezés: 4 × 32 bit szó layout; src_actor/dst_actor 16→8 bit (HW-managed CST); seq 8→16 bit; len[9]→len[8] (len+1 kódolás); CRC-16 hozzáadva (payload integritás); flags bővítés (pri, zero_len); 256-bit link flit táblázat; döntési napló frissítés (3–5. döntés) |
| 1.0 | 2026-04-22 | Első verzió — 256 byte payload, len[9], header bitmezők, változó link foglalás, DDR5 burst illeszkedés, döntési napló |
