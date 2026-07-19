---
status: decision
---

# Döntés: L0 busz visszaléptetés 256→128 bit (v3.1)

> English version: [decision-bus-rollback-en.md](decision-bus-rollback-en.md)

> Version: 1.2

> Státusz: Architektúra döntés, hatályos 2026-04-28-tól. Érinti az `interconnect-hu.md` v3.1-et, a `specs/cell-format-hu.md` v2.1-et és az `internal-bus-hu.md` v1.1-et.

## Összefoglaló

A v3.0 (`interconnect-hu.md`) bevezette a 256-bit-es L0 cluster mesh linket és a 16 byte header + max 256 byte payload cella formátumot. A v3.1-ben **az L0 busz szélességét visszaléptetjük 128-bitre, a max payload-ot 128 byte-ra**. A header layout változatlan marad (16 byte). A skálázási elv (lásd lent) megőrizve, hogy a felfelé skálázás (256/512/1024 bit) később egyszerűen elvégezhető legyen.

## A skálázási elv

A v3.1 a következő tervezési szabályt rögzíti az L0 busz és a cella méretezésére:

```
header_size_byte = bus_width_bit / 8       (= 1 flit)
payload_size_byte = 8 × header_size_byte    (= 8 flit)
cell_size_byte = 9 × header_size_byte       (= 9 flit, header overhead 11%)
```

Ez biztosítja, hogy:

1. A header **mindig pontosan 1 flit** — nincs fél-flit pazarlás.
2. A payload **mindig egész flit-szám** — nincs sub-flit padding.
3. A header overhead **konstans 11%** minden bus-szélességen.

| Bus szélesség | Header | Max payload | Max cella | Cella flit | Header overhead |
|---|---|---|---|---|---|
| **128-bit (v3.1, jelenlegi)** | **16 byte** | **128 byte** | **144 byte** | **9 flit** | **11%** |
| 256-bit (v3.0, elvetett) | 16 byte | 256 byte | 272 byte | 9 flit + 0,5 pad | 50% pad a header flit-ben |
| 256-bit (jövőbeli upscale) | 32 byte | 256 byte | 288 byte | 9 flit | 11% |
| 512-bit (jövőbeli) | 64 byte | 512 byte | 576 byte | 9 flit | 11% |

A v3.0 hibája, hogy a 16 byte header-t **megtartotta** a v2.4-es 42-bit busznál örökölt méreten, miközben a buszt 256-bitre szélesítette — ezzel a header **fél flit-et foglalt**, 16 byte padding minden cellán.

## Miért éppen 128 bit?

### Konzervativitás az F2.7 FPGA bring-up-hoz

A jelenlegi roadmap fázis (F2.7) **A7-Lite 200T FPGA**-ra céloz. Egy 256-bit-es párhuzamos NoC link a Vivado/OpenXC7 routing számára nehezen kezelhető (sok globális vezeték, magas LUT-foglalás a router crossbar-ban). A 128-bit-es link **fele wire-budget**, és minden iparági FPGA NoC példa ezen a tartományon belül van (Tilera Tile, AsAP, ZedBoard NoC referencia-implementációk).

### A 16 byte header pontosan 1 flit

A header layout v3.0-ban már 128 bit (4 × 32 bit word, lásd `interconnect-hu.md` v3.0). Ezt változatlanul tartva a 128-bit-es busznál a header **pontosan 1 flit** — nincs spec-újraírás, nincs új mezőelhelyezés, csak a `len` szemantika korlátozódik 1-128-ra (a 8 bit-es mező továbbra is `len+1`, csak a felső 128 érték nem használt; jövőbeli upscale-nél automatikusan elérhető).

### A tipikus actor üzenet még mindig kicsi

**Tervezési feltételezés (nem mért):** az actor üzenetek becsült ~80%-a ≤48 byte payload, ~15% 49-64 byte, ~5% nagyobb — Akka.NET/Erlang-stílusú workloadok jellemzően kis üzenetei alapján; valódi eloszlás-mérés későbbi fázisra ütemezve. E feltételezés szerint a 128 byte max payload **lefedné a forgalom ~95-100%-át** egyetlen cellában — a state migráció és code-load chunk-ok 2× több cellára darabolódnak (~10% header overhead a ritka nagy üzeneteknél), de ez nem dominálja a rendszert.

### DDR5 burst alignment

A 128 byte payload **DDR5 BL32** (Burst Length 32, ×4 byte = 128 byte) natív burst egységének felel meg. A 64 byte (BL16) is támogatott. A `ddr5-architecture-hu.md` HW Capability Slot modellje változatlan, csak a fragment méret változik.

### Wire-budget a hop-on belül

L0 cluster mesh hop távolság: ~330 µm (4×4 mesh, ~1,1 mm cluster). Wire pitch 5nm-en: ~0,5 µm. 128-bit link wire bundle: 64 µm — kényelmesen elfér a 330 µm hop-on belül, repeater-célletekkel együtt is. 256-bit-en a bundle 128 µm volt, még mindig fért, de a routing-mező sűrűsége magasabb.

## Mit veszítünk

| Metrika | v3.0 (256-bit) | **v3.1 (128-bit)** | Változás |
|---|---|---|---|
| L0 throughput @ 500 MHz | 16 GB/s | **8 GB/s** | −50% |
| Max cella payload | 256 byte | 128 byte | −50% |
| Tipikus 48B üzenet flit szám | 2 flit | 4 flit (header + 3 × 16B payload) | +2 flit |
| Tipikus 48B üzenet hop latencia | 2H + 1 cc | 2H + 3 cc | +2 cc |
| Worst case cella flit | 9 flit | 9 flit | 0 (változatlan!) |
| Worst case cella latency | 2H + 8 cc | 2H + 8 cc | 0 (változatlan!) |

A worst case latency **nem változik** (9 flit drain), mert a flit darabszám ugyanaz — csak a flit kisebb. A tipikus actor üzenet 2 cc lassabb hopanként; cross-régió 18 hop-on ez 36 cc extra (~72 ns @ 500 MHz). A rendszer-szintű hatás kicsi, a mailbox-késleltetés tipikusan ~100-300 ns.

## Mit nyerünk

1. **Tiszta flit-illesztés** — header pontosan 1 flit, nincs padding waste.
2. **FPGA-barát routing** — fele wire-budget, A7-Lite 200T-n könnyen routol.
3. **Iparági standard tartomány** — 128-bit on-chip mesh link megegyezik a Tilera Tile-Gx, Adapteva Epiphany és STMicro PNoC referenciákkal.
4. **DDR5 BL32 alignment** — 128 byte = 1 DDR5 burst (BL32 × 4 byte) natív méret.
5. **Egyszerű felfelé skálázás** — ha a tapasztalat azt mutatja, hogy 8 GB/s nem elég, a `BUS_WIDTH` RTL paramétert 256-bitre állítva (és ezzel együtt a header-t 32 byte-ra, payload-ot 256 byte-ra) a teljes architektúra arányosan skálázódik.

## Felfelé skálázás kritériuma

A v3.1 jövőbeli felülvizsgálatát a következő tapasztalati metrikák indokolhatják:

1. **L0 link kihasználtság > 60% sustained** — a 8 GB/s telített, és a workload bandwidth-bound (nem latency-bound).
2. **State migráció gyakori** — ha a fragment overhead (10-20% nagy üzeneteknél) szignifikáns rendszer-throughput költséget okoz.
3. **DDR5 prefetch streaming** — ha a 128 byte burst-méret nem optimális egy konkrét workload memóriahozzáférés-mintázatára (HBM-átállás, vagy DDR5 BL64-féle bővítmény).

Ha **két** kritérium teljesül, a v3.2 felülvizsgálat mérlegelhető. Az F4 multi-core RTL és F2.7 FPGA bring-up tényleges mérései adják az adatot.

## Alternatívák — döntés-trail

### A) Megtartani a v3.0 256-bit / 16B header / 256B payload kombinációt

- **Pro:** Magasabb L0 throughput (16 GB/s), nagyobb max cella (256B payload).
- **Contra:** Header fél flit-et foglal (16B / 32B = 0,5 flit), 50% pad a header flit-ben minden cellán. F2.7 FPGA routing nehéz a 256-bit párhuzamos linkkel.
- **Elvetve:** A wire-pazarlás és FPGA-barátság elsőbbsége.

### B) v3.0 256-bit + header 32 byte-ra bővítés (1 flit alignment)

- **Pro:** Nincs header pad, +128 bit szabad mező a header-ben (Fragment ID, AuthCode hash, Trace ID, QoS extended).
- **Contra:** Header layout breaking change. F2.7 FPGA routing a 256-bit párhuzamos linkkel nehéz marad.
- **Elvetve első körben:** Túl korai a header bővítése konkrét felhasználási tapasztalat nélkül. Ha az F4+ fázisban felmerül igény (pl. inline tracing), a v3.2 ezt a változatot újratárgyalja.

### C) **128-bit bus / 16B header / 128B payload (választott v3.1)**

- **Pro:** Tiszta flit-illesztés (header = 1 flit). FPGA-barát. Header layout változatlan. Iparági standard tartomány. Egyszerű felfelé skálázás `BUS_WIDTH` paraméterrel.
- **Contra:** 8 GB/s L0 throughput (vs 16 GB/s a v3.0-ban). Max payload 128 byte (vs 256 byte).
- **Választott:** A konzervatív path az F2.7-hez, megőrizve az upscale opciót.

### D) Bus szélesség = teljes cella (272 byte = 2176-bit), 1 cc/hop

- **Pro:** Logikailag tiszta, 1 cc/hop fix latencia, nincs flit pipeline, nincs body drain, nincs wormhole.
- **Contra:** Wire bundle ~1,1 mm szélesség (a 0,33 mm hop távolságnál szélesebb → fizikailag nem fér). L1/L2/L3 chip-szintű crossbar-ban (cm-skálán) kizárt. Wire-budget ~8,5× a 256-bit-hez képest. Tipikus 48B üzenet 6× over-provisioning.
- **Elvetve:** Fizikai layout korlát.

## Implementációs hatás

A v3.1 a következő dokumentumokat érinti:

- `docs/interconnect-hu.md` v3.0 → **v3.1** — L0 link 256→128 bit, payload 256→128 byte, cella 272→144 byte, throughput, latency táblák, link típusok
- `docs/interconnect-en.md` — angol mirror
- `specs/cell-format-hu.md` v2.0 → **v2.1** — payload 256→128 byte, len semantics
- `specs/cell-format-en.md` — angol mirror
- `docs/internal-bus-hu.md` v1.0 → **v1.1** — "Tile-szintű NoC: 256→128 bit", terminológia tisztázás (cluster = 16 core), L1/L2/L3 link típusok pontosítás, v3.1 hivatkozás
- `docs/internal-bus-en.md` — angol mirror
- `docs/ddr5-architecture-hu.md` — DDR5 burst alignment ellenőrzés (128B = BL32 × 4B kompatibilis)
- `web/{en,hu}/blog/internet-on-chip.html`, `scaling-cores.html` — hivatkozások frissítése

Az RTL paraméterezés (jövőbeli F4 fázis) bevezeti a `BUS_WIDTH` RTL paramétert, alapérték 128, választható 256/512/1024 (felfelé skálázás).

## Kapcsolódó dokumentumok

- [`interconnect-hu.md`](interconnect-hu.md) — L0 cluster mesh, hierarchia, switching modell
- [`internal-bus-hu.md`](internal-bus-hu.md) — core-on belüli busz méretezés (Nano/Actor 256, Rich 512, ML 1024, Seal 64 — független a NoC busztól)
- [`specs/cell-format-hu.md`](../specs/cell-format-hu.md) — header és payload bit-szintű elrendezés
- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — TLP > ILP filozófia, statikus ILP, in-order pipeline
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — DDR5 controller, HW Capability Slot

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-28 | Kezdeti verzió — L0 busz visszaléptetés 256→128 bit indoklása, skálázási elv (header = 1 flit, payload = 8 flit), alternatívák A/B/C/D, felfelé skálázás kritériumai |
| 1.1 | 2026-06-01 | **A „~80% ≤48 byte" eloszlás hamis forrás-attribúciója javítva.** A v1.0 egy nemlétező „interconnect-hu.md v2.4 elemzésre" hivatkozott; valójában ez sosem volt mérés. A szám most explicit **tervezési feltételezésként (nem mért)** szerepel, Akka/Erlang-workload alapú indoklással. A tartalmi döntés (256→128 bit rollback) változatlan. |
| 1.2 | 2026-07-17 | **DDR5-modell terminológia frissítve:** az elavult „capability grant + CAM ACL" hivatkozás a hatályos **HW Capability Slot** modellre (ddr5-architecture v1.3 óta: központi CAM → per-core QRAM capability slot). A cell-format v2.0→v2.1 történeti hivatkozások (a döntés hatálya) változatlanok. |
