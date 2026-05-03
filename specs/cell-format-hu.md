# CFPU NoC Cella Formátum

> English version: [cell-format-en.md](cell-format-en.md)

> Version: 2.3

> Forrás: `docs/interconnect-hu.md` v3.1 (2026-04-28)

Ez a specifikáció a CFPU NoC hálózatán utazó **cella** (üzenetcsomag) pontos bináris formátumát definiálja.

## Cella struktúra

ATM-inspirált fix buffer, változó link foglalás: **16 byte header + 1–128 byte payload** (v3.1 default; `BUS_WIDTH` paraméterrel skálázható, lásd `decision-bus-rollback-hu.md`).

A router buffer-ek fix méretűek (144 byte slot). A linken csak a header + tényleges payload utazik.

```
Cella = Header (16 byte) + Payload (1-128 byte)

Buffer:  mindig 144 byte slot (fix, determinisztikus SRAM kezelés)
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
| `len` | 39..32 | 8 bit | Küldő | — | Payload méret: `len + 1` byte. v3.1: max 128 byte (`len ≤ 127`); a felső 128 érték a jövőbeli `BUS_WIDTH` upscale-re fenntartva. 0 byte-os payload → `flags.zero_len` |
| `reserved` | 31..24 | 8 bit | — | — | Jövőbeli bővítés (QoS, stb.) |
| `CRC-16` | 23..8 | 16 bit | HW | — | Payload integritás ellenőrzés — a payload fölött számolva |
| `CRC-8` | 7..0 | 8 bit | HW | — | Header integritás ellenőrzés — a header bit 127..8 fölött számolva (beleértve CRC-16-ot) |

### flags mező részletezés

| Bit | Név | Ki írhatja? | Jelentés |
|-----|-----|-------------|---------|
| 7 | `vn` | Küldő SW | 0 = VN1 (actor üzenet), 1 = VN0 (control: supervisor, trap, heartbeat) |
| 6 | `relay` | NoC HW | 1 = relay üzenet (L3 fault tolerance, lásd interconnect spec) |
| 5..4 | `pri` | Küldő SW | Prioritás (00 = normál, 01–11 = jövőbeli QoS szintek) |
| 3 | `zero_len` | Küldő SW | 1 = nincs payload (0 byte), a `len` mező nem értelmezett |
| 2 | `ddr5_cap` | **CSAK core HW** | 1 = a payload első 8 byte-ja HW-attached DDR5 capability slot. A SW `send` opkódjában ez a bit maszkolva van 0-ra (HW filter). Részletek: [`ddr5-architecture-hu.md`](../docs/ddr5-architecture-hu.md) v1.3 |
| 1..0 | reserved | — | Jövőbeli használat |

## Payload (1–128 byte)

Az alkalmazásadat. A `len` mező (`len + 1`) határozza meg a tényleges méretet. Ha `flags.zero_len = 1`, nincs payload. A router a payload tartalmát **nem vizsgálja** — az kizárólag a fogadó core dolga.

Az Actor ID korábban (interconnect v1.8) a payload első byte-jaiban volt (szoftveres dispatch). A v2.4-től a `src_actor` és `dst_actor` a header-ben van — a payload **teljes egészében alkalmazásadat**.

## Változó link foglalás

A router buffer fix (144 byte slot), de a linken **csak a tényleges adat utazik**.

### 128 bites L0 adatút (v3.1 default)

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
| 48 (tipikus actor) | 3 | 4 | 64 |
| 64 | 4 | 5 | 80 |
| 96 | 6 | 7 | 112 |
| 128 (max v3.1) | 8 | 9 | 144 |

A skálázási elv: a **header pontosan 1 flit** a 128-bit linken (16 byte = 128 bit), a max payload **8 flit** (128 byte / 16 byte/flit). Header overhead konstans 11%.

### Jövőbeli upscale (256 / 512 / 1024-bit `BUS_WIDTH`)

A `BUS_WIDTH` RTL paraméter felfelé skálázásakor a header-méret és a max payload arányosan nő, hogy a `header = 1 flit, payload = 8 flit` szabály érvényben maradjon:

| `BUS_WIDTH` | Header | Max payload | Cella | Cella flit | **@ 50 MHz** | **@ 500 MHz** | **@ 1 GHz** |
|---|---|---|---|---|---|---|---|
| **128 (v3.1)** | **16 byte** | **128 byte** | **144 byte** | **9 flit** | **0,8 GB/s** | **8 GB/s** | **16 GB/s** |
| 256 (jövőbeli) | 32 byte | 256 byte | 288 byte | 9 flit | 1,6 GB/s | 16 GB/s | 32 GB/s |
| 512 (jövőbeli) | 64 byte | 512 byte | 576 byte | 9 flit | 3,2 GB/s | 32 GB/s | 64 GB/s |
| 1024 (jövőbeli) | 128 byte | 1024 byte | 1152 byte | 9 flit | 6,4 GB/s | 64 GB/s | 128 GB/s |

> **Sávszélesség képlet:** `BUS_WIDTH / 8 × f` — egy flit per ciklus, raw link kapacitás (header + payload együtt, SI: 1 GB/s = 10⁹ byte/s).
>
> **Frekvencia oszlopok indoklása:**
> - **50 MHz** — F3 Tiny Tapeout / Sky130 I/O target (lásd [`docs/architecture-hu.md`](../docs/architecture-hu.md) § OPI Octal SPI)
> - **500 MHz** — CFPU referencia core órajel (lásd [`docs/architecture-hu.md`](../docs/architecture-hu.md) § OPI PSRAM átviteli sebességek, "core ciklus @ 500 MHz")
> - **1 GHz** — aspirációs F6+ silicon target
>
> **Effektív payload sávszélesség:** worst-case 9 flit cella (1 header + 8 payload) esetén ~**88,9% × raw** (konstans 11% header overhead). Tipikus 48 byte aktor üzenet (1 header + 3 payload flit) esetén ~75% × raw — a változó link foglalás miatt a többi időt más cellák használhatják.

Részletek: [`docs/decision-bus-rollback-hu.md`](../docs/decision-bus-rollback-hu.md).

**HW költség (v3.1):** Visszaszámláló per router port + jobb-shift. Nincs LUT, nincs tail bit, nincs link-szélességi overhead.

## Split SRAM design

A header és a payload **külön SRAM-ban** tárolódik a routerben:

```
Header SRAM:   slot × 16 byte    (shift-es címzés)
Payload SRAM:  slot × 128 byte   (shift-es címzés, 2-hatvány) — v3.1 default
```

A scheduler a headert olvassa a routing döntéshez, miközben a payload még érkezik — **1 ciklus latencia-megtakarítás**. Nincs port-verseny a scheduler és a crossbar között.

## DDR5 burst illeszkedés

A 128 byte-os payload (v3.1 default) **DDR5 BL32** (Burst Length 32 × 4 byte) natív burst egységének felel meg, vagy 2× DDR5 BL16 (64 byte) burst:

| DDR5 burst szám | Payload méret | Cella szám |
|-----------------|---------------|------------|
| 1× BL16 (64 byte) | 64 | 1 |
| 2× BL16 (128 byte) | 128 | 1 |
| 1× **BL32** (128 byte) | 128 | 1 |
| 3× BL16 (192 byte) | 128 + 64 | 2 |
| 4× BL16 (256 byte) | 128 + 128 | 2 |

A jövőbeli `BUS_WIDTH=256` upscale-nél a 256B payload egyetlen cellában fog 4× BL16 (vagy 1× BL64) burst-öt kezelni — pontosan úgy, ahogy a v3.0 tervezte.

## RTL paraméterek

| Paraméter | Alapértelmezett | Tartomány | Hatás |
|-----------|----------------|-----------|-------|
| `BUS_WIDTH` | 128 | 128 / 256 / 512 / 1024 | L0 link szélesség (bit). A header és payload mérete arányosan skálázódik. |
| `CELL_SIZE` | 128 | 8 × `BUS_WIDTH/8` | Payload max méret (byte). Buffer slot = 16 (header) + CELL_SIZE (payload) — `BUS_WIDTH=128`-nál 144 byte slot. |

## Döntési napló

### 1. döntés: Miért fix buffer, változó link?

**Elvetett:** Teljesen fix cella (mindig teljes méret a linken). Az actor üzenetek ~80%-a ≤48 byte — a fix foglalás a link kapacitás nagy részét pazarolja.

**Elvetett:** Változó méretű buffer. Fragmentáció, bonyolult SRAM kezelés, nem-determinisztikus időzítés.

**Végső döntés:** Fix buffer + változó link. A buffer determinisztikus (ATM elv), a link hatékony. HW költség: 5 bites számláló per port.

### 2. döntés: Miért 128 byte payload (v3.1 rollback)?

**Korábbi döntések:**
- **2026-04-20:** 64 byte volt az alapértelmezett, mert fix link foglalásnál a nagyobb cella lassabb worst-case latenciát adott.
- **2026-04-22 (v1.0 ennek a spec-nek):** 256 byte az alapértelmezett — a változó link foglalással a nagy cella mellékhatásai eltűntek.
- **2026-04-28 (v2.0):** 256 byte a 256-bit-es L0 busz mellett.

**Felülvizsgálat (2026-04-28, v2.1):** A v3.1 interconnect rollback (256→128 bit L0 busz) miatt a payload max mérete is arányosan csökkent. A **skálázási elv** szerint:
- header = 1 flit = `BUS_WIDTH/8` byte
- payload = 8 flit = 8 × header byte
- cella = 9 flit, header overhead konstans 11%

**Indoklás a 128 byte mellett (v3.1):**
- **Header pontosan 1 flit** a 128-bit L0 buszon — a v3.0 256-bit busznál a header fél flit volt (50% padding waste).
- **DDR5 BL32** (128 byte) natív burst illeszkedés.
- **F2.7 FPGA-barát** wire-budget — 128-bit párhuzamos link Vivado/OpenXC7-ben triviális.
- **Felfelé skálázás** a `BUS_WIDTH` paraméterrel megmarad — ha az F4+ tapasztalat indokolja, 256-bit-re upscale-elhetők.

**Végső döntés (v2.1, 2026-04-28):** 128 byte az alapértelmezett (`CELL_SIZE = 128`, `BUS_WIDTH = 128`). Részletes indoklás: [`docs/decision-bus-rollback-hu.md`](../docs/decision-bus-rollback-hu.md).

### 3. döntés: Miért `src_actor` / `dst_actor` a header-ben?

**Elvetett (v1.8):** Actor ID a payload-ban, szoftveres dispatch. Az N:M actor-to-core mapping miatt a DDR5 Controller és a crash recovery nem tudta megkülönböztetni az aktorokat core szinten.

**v2.4 döntés:** Actor ID-k a header-be kerültek.

**v2.0 felülvizsgálat (2026-04-28):** 16 bit → 8 bit actor ID, mert:
- 256 aktor/core elegendő: a CST (Context Switch Table) HW-managed — az aktív actor context regiszter hardveresen tölti a `src_actor` mezőt, **nem hamisítható** (a core szoftvere nem írhatja felül)
- A felszabadult 2 × 8 bit (összesen 16 bit) a `seq` mezőt 8 → 16 bitre bővíti, ami nagyobb fragmentált üzeneteket tesz lehetővé
- DDR5 capability slot aktor-szintű ACL továbbra is működik (`src[24] + src_actor[8]` defence-in-depth a controller-en, lásd `ddr5-architecture-hu.md` v1.3)
- Crash recovery: csak az adott aktor capability-jét törli
- Router dispatch: header-ből olvasható, nem kell payload-ba nyúlni

**Végső döntés (v2.0):** 8 bit src_actor + 8 bit dst_actor a header-ben. A `src_actor`-t a core HW tölti ki (CST aktív context regiszter), a router a `src`-t tölti ki — mindkettő nem hamisítható.

### 4. döntés: Miért `len[8]` (len+1 kódolás)?

**Elvetett (v1.0):** `len[9]` (max 511). Lefedi a 256 byte-ot, de 1 bit pazarlás — a 257–511 tartomány soha nem használt.

**Elvetett:** `len[16]` (max 65 535). Túlméretezett — a felszabadult bitek hasznosabbak máshol.

**Elvetett:** `len[8]` direkt kódolás (max 255). Nem fedi le a 256 byte-os payload-ot a v3.0-ban.

**Végső döntés (v2.0/v2.1):** `len[8]` + 1 kódolás: a tárolt érték 0–255, a tényleges payload méret `len + 1` byte. A 0 byte-os (csak header) üzeneteket a `flags.zero_len` bit jelzi. v3.1-ben a max payload 128 byte (`len ≤ 127`); a felső 128 érték (`len = 128..255`) a jövőbeli `BUS_WIDTH=256` upscale-re fenntartva. Előnyök:
- 8 bit: szó-határ illeszkedés (32 bit szó részeként)
- Teljes 1–256 tartomány lefedése veszteség nélkül (jövőbeli upscale-hez forward kompatibilis)
- A felszabadult 1 bit (len[9] → len[8]) + a korábbi reserved-ből összesen a CRC-16-nak adott helyet

### 5. döntés: Miért CRC-16 a payload-hoz?

**v1.0-ban:** Csak CRC-8 a header fölött. A payload integritását nem ellenőriztük hardveresen.

**Végső döntés (v2.0):** CRC-16 (16 bit) a payload fölött számolva, a header Szó 3-ban tárolva. A CRC-8 (8 bit) ezután a teljes header (bit 127..8) fölött számolódik, **beleértve a CRC-16 értékét**. Így a header integritás a payload CRC-t is védi — egyetlen bit-flip sem marad észrevétlen.

## Changelog

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 2.3 | 2026-05-03 | **Sávszélesség táblázat-bővítés** a "Jövőbeli upscale" szekcióban — minden `BUS_WIDTH` értékhez (128/256/512/1024 bit) raw link sávszélesség 50 MHz / 500 MHz / 1 GHz órajeleken. Frekvencia oszlopok indoklása: 50 MHz Sky130 I/O target, 500 MHz CFPU referencia core órajel, 1 GHz aspirációs F6+. Effektív payload sávszélesség (~88,9% raw worst-case) megjegyzésben rögzítve. Tartalmi változás csak additív; a formátum spec változatlan. |
| 2.2 | 2026-04-28 | **`flags.ddr5_cap` HW-only bit allokálva.** A korábbi `reserved[3]` bit-ből egyet (bit 2) elneveztük `ddr5_cap`-nek, jelentés: a payload első 8 byte-ja egy HW-attached DDR5 capability slot. A bitet **CSAK a core HW request assembler-e állíthatja be**; az aktor SW `send` opkódja maszkolva 0-ra. A flags tábla "Ki írhatja?" oszloppal bővült. Részletek: [`docs/ddr5-architecture-hu.md`](../docs/ddr5-architecture-hu.md) v1.3 |
| 2.1 | 2026-04-28 | **v3.1 interconnect rollback szinkronizáció:** L0 busz 256→128 bit, max payload 256→128 byte (`CELL_SIZE = 128`), buffer slot 272→144 byte. Header layout **változatlan** (16 byte, 4×32 bit). `len[8]` szemantika változatlan (`len+1`), de v3.1-ben max 128 (`len ≤ 127`); a felső 128 érték a jövőbeli `BUS_WIDTH` upscale-re fenntartva. `BUS_WIDTH` RTL paraméter bevezetve (default 128, jövőbeli 256/512/1024). DDR5 burst illeszkedés frissítve (BL32 = 128 byte natív). Indoklás: [`docs/decision-bus-rollback-hu.md`](../docs/decision-bus-rollback-hu.md) |
| 2.0 | 2026-04-28 | Header átszervezés: 4 × 32 bit szó layout; src_actor/dst_actor 16→8 bit (HW-managed CST); seq 8→16 bit; len[9]→len[8] (len+1 kódolás); CRC-16 hozzáadva (payload integritás); flags bővítés (pri, zero_len); 256-bit link flit táblázat; döntési napló frissítés (3–5. döntés) |
| 1.0 | 2026-04-22 | Első verzió — 256 byte payload, len[9], header bitmezők, változó link foglalás, DDR5 burst illeszkedés, döntési napló |
