---
status: living
---

# Dokumentumok státusz-indexe

> English version: [STATUS-en.md](STATUS-en.md)

Ez a fájl rögzíti minden `docs/` alatti dokumentum **státuszát**. Egyetlen forrás (single source of truth) a státuszra; a fájlokba beillesztett `status:` frontmatter mező ezzel a táblázattal egyezik.

> **Cél:** elkerülni, hogy egy vízió-szintű javaslat (pl. AI által generált koncepció) később ténynek tűnjön, csak mert markdown táblázatban szerepel. Minden olvasónak (ember vagy AI) **látnia kell** a tartalom státuszát, mielőtt rá hivatkozik.

## Státusz-rubrika

| Státusz | Mit jelent | Hivatkozási súly |
|---|---|---|
| **`vision`** | Kreatív tervezés. Számok munkahipotézisek; F4–F6 RTL/szilícium után validálhatók. | Inspiráció. **Ne** hivatkozz precíz számra ilyen doksira ütközés-ellenőrzés nélkül. |
| **`draft`** | Részletes javaslat, ADR vagy döntés nélkül. | Kiindulás. Promote → `decision` vagy `specs/` szükséges, mielőtt tényként kezelhető. |
| **`decision`** | Formális Architecture Decision Record (ADR). | **Kötelező.** Ütközés esetén felülírja a `vision` / `draft` doksit. |
| **`spec-candidate`** | Implementált és tesztelt; érdemes `specs/`-be promote-olni. | Megbízható. Promote után `specs/`-ben lakik, itt csak referencia. |
| **`policy`** | Projekt-stratégiai irány (brand, openness, kommunikáció). | Kötelező a vonatkozó területen, de nem műszaki spec. |
| **`living`** | Folyamatosan változó tervező dokumentum (pl. roadmap). | Aktuális; minden hivatkozásnál nézd meg a dátumot. |
| **`archived`** | Történelmi pillanatkép. | **Nem** hivatkozási alap; csak a múlt rögzítése. |
| **`reference`** | Külső dokumentáció (datasheet, board referencia). | Kötelező a vonatkozó hardverre. |
| **`mirror`** | Másik repóból (pl. `FenySoft/Symphact`) tükrözött doksi. Eredeti hely a `> Forrás:` mezőben. | Az eredeti repó az autoritatív. |

## Hozzáadási szabály

**Új doksi a `docs/` alá CSAK** a STATUS.md táblába vett bejegyzéssel kerülhet. Új koncepció a meglévő doksiba CSAK `decision`-ba promote-olással léphet ki a `vision`/`draft` státuszból.

## Promote útvonal

```
vision → draft → decision → spec-candidate → specs/<fájl>.md (verziózott, autoritatív)
```

Egy ugrást átugrani lehet (pl. `draft → spec-candidate`), de visszafelé nem.

## Aktuális státusz-tábla

Utolsó audit: **2026-05-03**

### `vision` (38 fájl, 19 pár)

> F4 RTL és F6 szilícium után validálandó. Számok munkahipotézisek.

| Fájl pár | Megjegyzés |
|---|---|
| `architecture-{hu,en}.md` | 1432 sor; **AI-generált rétegek halmozva** (Actor Scheduling Pipeline, QRAM Ext, AES/CMAC F5+). Tisztításra szorul. |
| `authcode-{hu,en}.md` | F5 RTL-ben validálandó. |
| `cfpu-ml-max-{hu,en}.md` | "v2.0-draft", de tartalom F6+ ML chip vízió. |
| `chiplet-packaging-{hu,en}.md` | F6 silicon utáni packaging. |
| `core-types-{hu,en}.md` | F4 RTL után validálható. **Ütközik** `architecture-hu.md` AES/CMAC engine számolásával. |
| `ddr5-architecture-{hu,en}.md` | F5+ DDR5 capability slot. |
| `faq-{hu,en}.md` | Vegyes (policy + vízió-számok). |
| `hw-attack-immunity-{hu,en}.md` | Friss (2026-05-02), de immunitás-tábla még vízió. |
| `hw-boot-{hu,en}.md` | F5+ HW boot szekvencia. |
| `interconnect-{hu,en}.md` | A cell-format része **promote-olva** → `specs/cell-format-{hu,en}.md`. Maradék: vízió. |
| `internal-bus-{hu,en}.md` | Busz-szélesség becslések. |
| `microarch-philosophy-{hu,en}.md` | F1.5 referenciák. |
| `perf-vs-riscv-{hu,en}.md` | Irodalmi precedensek alapján. |
| `quench-ram-{hu,en}.md` | F5 RTL-ben kezdhet megjelenni. |
| `sealcore-{hu,en}.md` | F5 RTL-ben validálható. |
| `secure-element-{hu,en}.md` | F6+ secure element vízió. |
| `security-{hu,en}.md` | Threat model + immunitás vízió. |
| `use-case-video-{hu,en}.md` | Core-szám becslés irodalmi adatokból. |
| `vision-{hu,en}.md` | A magas-szintű vízió. |

### `draft` (4 fájl, 2 pár)

| Fájl pár | Megjegyzés |
|---|---|
| `ISA-CIL-Seal-{hu,en}.md` | Önmagát "v0.1 (draft)"-nak jelöli. F5+ ISA. |
| `certification/CFPU-SEC-v1-{hu,en}.md` | Tanúsítási keret. "v1" név spec-szerűséget sugall, de F5+ tartalom. |

### `decision` (8 fájl, 4 pár) — formális ADR

| Fájl pár | Megjegyzés |
|---|---|
| `decision-bus-rollback-{hu,en}.md` | L0 256→128 bit visszaléptetés. **Mintaként megőrzendő.** |
| `2026-06-26-crypto-hardware-placement.md` | Per-core AES+CMAC (Actor/Rich) vs Seal core crypto; **proposed**, ütközés feloldás. |
| `2026-06-26-puf-timeline.md` | PUF F5+ infra vs F6.5+ Secure Core use; **proposed**. |
| `2026-06-26-sleeping-actor-inbox-buffering.md` | Multi-cell mailbox FIFO spec; **proposed**. |

### `spec-candidate` (2 fájl, 1 pár) — promote-olandó

| Fájl pár | Megjegyzés |
|---|---|
| `ISA-CIL-T0-{hu,en}.md` | A 64 opkód a szimulátorban implementált, 187 teszt. **Promote ide:** `specs/isa-cil-t0-{hu,en}.md`, `Version: 1.0`. |

### `policy` (6 fájl, 3 pár)

| Fájl pár | Megjegyzés |
|---|---|
| `brand-{hu,en}.md` | Brand- és elnevezési útmutató (CLI-CPU vs CFPU). |
| `tool-openness-{hu,en}.md` | Open-source toolchain stratégia. |
| `blog/series-plan-{hu,en}.md` | Blog kommunikációs terv. |

### `living` (4 fájl, 2 pár)

| Fájl pár | Megjegyzés |
|---|---|
| `roadmap-{hu,en}.md` | F0–F7 fázisok, folyamatos frissítés. |
| `STATUS-{hu,en}.md` | Maga ez az index. |

### `archived` (10 fájl, 5 pár)

| Fájl pár | Megjegyzés |
|---|---|
| `nlnet-application-draft-{hu,en}.md` | NLnet pályázati anyag. |
| `nlnet-corrections-{hu,en}.md` | Beadás utáni korrekciók. |
| `symphact-{hu,en}.md` | Átköltözött `FenySoft/Symphact` repóba. |

### `reference` (2 fájl, 1 pár)

| Fájl pár | Megjegyzés |
|---|---|
| `A7-Lite/A7-Lite-{hu,en}.md` | MicroPhase A7-Lite XC7A200T FPGA board referencia. |

### `mirror` (12 fájl, 6 pár)

> Eredeti hely: `FenySoft/Symphact` repó.

| Fájl pár | Megjegyzés |
|---|---|
| `osreq-from-os/osreq-001-tree-interconnect-{hu,en}.md` | Fa topológiájú interconnect követelmény. |
| `osreq-from-os/osreq-002-mmio-memory-map-{hu,en}.md` | MMIO memory map. |
| `osreq-from-os/osreq-003-core-reset-{hu,en}.md` | Core reset mechanizmus. |
| `osreq-from-os/osreq-004-dma-engine-{hu,en}.md` | DMA engine követelmény. |
| `osreq-from-os/osreq-005-mailbox-interrupt-{hu,en}.md` | Mailbox interrupt vs polling. |
| `osreq-from-os/osreq-006-interchip-link-{hu,en}.md` | Inter-chip link protokoll. |

## Ismert ütközések — ADR megoldás alatt (2026-06-26)

A 2026-05-03 audit során feltárt belső inkonzisztenciák — feloldásuk ADR vagy promote útján:

| Ütközés | Érintett doksik | ADR / Megoldás | Státusz |
|---|---|---|---|
| **AES/CMAC engine van/nincs Actor és Rich core-on** | `architecture-{hu,en}.md` (per-core AES F5+) ⚡ `core-types-{hu,en}.md` (Crypto: Nincs) | [[2026-06-26-crypto-hardware-placement]] | **proposed** |
| **Actor/Rich core terület (7nm → 5nm számok)** | `core-types-{hu,en}.md` (5nm) ⚡ `architecture-{hu,en}.md` 1312. sor (régi 7nm) | Szoftver-fix: 0,036→0,023 (Actor), 0,083→0,059 (Rich), 0,014→0,008 (Nano) | **kész** |
| **PUF elérhetősége F5+ vagy F6.5+** | `architecture-{hu,en}.md` 1309 (F5+), 388 (F6.5+) | [[2026-06-26-puf-timeline]] | **proposed** |
| **Multi-cell üzenet bufferelése alvó aktor inbox-ában** | `architecture-{hu,en}.md` Actor Scheduling Pipeline (csak egycellás) | [[2026-06-26-sleeping-actor-inbox-buffering]] | **proposed** |
