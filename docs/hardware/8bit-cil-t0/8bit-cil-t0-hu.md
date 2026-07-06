---
status: educational
---

# OctaCIL — 8-bit CIL-T0 diszkrét processzor-kit

> English version: [8bit-cil-t0-en.md](8bit-cil-t0-en.md)

> **⚠️ Oktatási / demonstrációs dokumentum.** Ez egy **breadboard-szintű, diszkrét 74HC logikai chipekből** felépíthető 8-bites CIL-T0 processzor terve — lépésről lépésre felépíthető "építsd meg magad" projekt. NEM a CFPU szilícium-roadmap része; célja az ISA megértetése, oktatás és közösségépítés. A fő szimulátor és FPGA-implementáció (F1.5–F2.8) a 32-bites CIL-T0-t valósítja meg; ez a 8-bites változat egy didaktikus leszármazott.

Ez a dokumentum összefoglalja, hogyan építhető meg a CIL-T0 ISA egy **8-bites, diszkrét alkatrészes** változata kézzelfogható hardverben, és hogyan programozható. A kész kit és a köré épülő oktatótartalom **OctaCIL** néven jelenik meg.

## Motiváció

A CLI-CPU projektben hiányzik egy közérthető, fizikailag megfogható belépő. A magyar YouTube-on nincs alkatrész-szintű, a nulláról építő CPU-tartalom (lásd a kutatást a [Háttér](#háttér) szakaszban). Egy diszkrét 8-bites CIL-T0:

- **Megfogható**: az adatbusz LED-eken látszik, az órajel léptethető
- **Oktató**: a stack-alapú végrehajtás minden lépése követhető
- **Közösségépítő**: **OctaCIL** kit-ként értékesíthető az érdeklődőknek
- **Hiteles**: a CLI-CPU "build journey" credibility-first stratégia része

## Miért alkalmas a stack-alapú ISA diszkrét építésre?

A CIL-T0 **stack-alapú** — ez konkrét hardveres előny breadboard szinten a regiszter-alapú ISA-khoz (6502, RISC-V) képest:

| Szempont | Regiszter-alapú | Stack-alapú (CIL-T0) |
|---|---|---|
| Regiszterfile | Sok flip-flop chip | ❌ Nincs — csak TOS/TOS1 cache |
| Forwarding logika | Bonyolult | ❌ Nincs |
| Busz vezérlés | Összetett | Egyszerűbb (push/pop) |
| Utasítás-kódolás | Regiszter-mezők | Implicit (rövidebb dekóder) |

A nevesített regiszterek hiánya miatt nincs "regiszter-méret" probléma sem: a stack értékei egységesen 8 bitesek ebben a változatban.

## Blokk-vázlat

```
        ┌─────────────┐      ┌──────────────┐
        │  Program    │      │  Mikrokód    │
        │  EEPROM     │      │  ROM (3×)    │
        │  AT28C64    │      │  AT28C64     │
        └──────┬──────┘      └──────┬───────┘
               │ utasítás           │ vezérlőjelek
               ▼                    ▼
        ┌─────────────────────────────────────┐
        │            VEZÉRLŐ + DEKÓDER        │
        │         (74HC138 chip-select)       │
        └─────────────────┬───────────────────┘
                          │
   ┌──────────┬───────────┼───────────┬──────────┐
   ▼          ▼           ▼           ▼          ▼
┌──────┐  ┌──────┐   ┌────────┐  ┌────────┐  ┌──────┐
│  PC  │  │  SP  │   │  ALU   │  │  TOS   │  │ Stack│
│HC191 │  │HC191 │   │ HC283  │  │ cache  │  │ SRAM │
│      │  │      │   │ +86/08 │  │ HC374  │  │62256 │
│      │  │      │   │ /32/04 │  │        │  │      │
└──────┘  └──────┘   └────────┘  └────────┘  └──────┘
   │          │           │           │          │
   └──────────┴───────────┴─────8-bit BUSZ───────┘
                  (74HC245 puffer ×5)
                          │
                    ┌─────┴───────┐
                    │ LED kijelző │
                    │ 8 piros +   │
                    │ 8 sárga     │
                    └─────────────┘
```

## Funkcionális egységek

| Egység | Chip | Szerep |
|---|---|---|
| **ALU** | 2× 74LS181 (+1× 74HCT245 illesztő) | komplett 8-bit ALU, 32 művelet (ADD/SUB/AND/OR/XOR/NOT...) |
| **Regiszterek** | 74HC374 ×6 | TOS, TOS-1, IR, vezérlőszó-latch, MAR×2 (16-bit) |
| **Program counter** | 74HC191 ×4 + 74HC245 ×2 | 16-bit utasítás-cím, fel/le + jump load |
| **Stack pointer** | 74HC191 ×4 + 74HC245 ×2 | 16-bit stack-cím, push/pop |
| **Mikrolépés-számláló** | 74HC191 ×1 | mikrokód fázis (opkód → vezérlőszó) |
| **Busz puffer** | 74HC245 ×6 össz. | 8-bit sín + 16-bit cím-puffer |
| **Dekóder** | 74HC138 ×2 | memory map / chip-select |
| **Stack memória** | 62256 SRAM | 32 KB — teljes 32K használt (16-bit cím) |
| **Program tár** | AT28C64 | 8 KB EEPROM |
| **Mikrokód ROM** | AT28C64 ×3 | vezérlőjelek opkódonként |
| **Órajel** | 3× NE555 + 1 MΩ potméter | astabil (run) + monostabil (step) + bistabil (debounce) |

A teljes chip-szám **~37 IC** — 16-bit címzéssel (teljes 32K memória) és a **2× 74LS181** ALU-val. A 74LS181 a diszkrét ALU-t (~15 chip) 2 chipre csökkenti.

## A mikrokód a kulcs

A 48 opkód diszkrét vezérlőlogikával kezelhetetlen lenne. A megoldás **mikrokód ROM**: az opkód + állapotgép-fázis adja a ROM-cím bemenetet, a kimenet vezérli az összes chip `enable`/`direction` vonalát. Ez a bevett mikrokódos megközelítés. 3× AT28C64 tárolja a teljes vezérlőjel-térképet.

## Programozás és tápellátás

Az AT28C64 EEPROM-ok (program + mikrokód) tartalmát **dedikált EEPROM programozóval** írjuk meg — a chipet ZIF-foglalatba helyezve, USB-n a PC-hez csatlakoztatva.

- **Programozó**: TL866II+ vagy XGecu T48 (széles AT28Cxxx támogatás, `minipro` / `Xgpro` szoftver)
- **Tápellátás (futtatáshoz)**: 5V USB-C vagy Raspberry Pi 5V GPIO → breadboard tápsín (~270 mA fogyasztás)
- **Mikrokód generálás**: a vezérlőjel-térképet szkript állítja elő bináris image-ként, a programozó szoftvere írja a chipre

> A programozó **egyszeri eszköz-beruházás**, nem része a kit-enkénti alkatrészlistának.

## Alkatrészlista (BOM)

A teljes, Hestore cikkszámokkal ellátott rendelési lista (tab-separated, kosárba másolható) külön fájlban, a repón kívül:

➡️ `~/Work/CFPU/8bit-cil-t0/8bit-cil-t0-bom.txt`

Minden chip **DIP/THT tokozásban, Hestore-ról** rendelhető. Egyetlen figyelmeztetés: a **74HC283 limitált készletű** — érdemes először azt ellenőrizni; ha kifogy, AliExpress-ről pótolható (~3–5 hét).

> A **breadboard és a memória adja az anyagköltség nagy részét** (4 db AT28C64/kit). A részletes árazás és a mennyiségi (1/5/10/15/20 kit) kalkuláció a BOM-fájl mellett, a `~/Work/CFPU/8bit-cil-t0/` munkamappában él — szándékosan a publikus dokumentumon kívül.

## OctaCIL termékszintek

Az OctaCIL három szinten lesz elérhető — a tiszta digitálistól a teljes fizikai csomagig. A részletes árazás szándékosan a publikus dokumentumon kívül él (lásd az [Alkatrészlista](#alkatrészlista-bom) megjegyzését).

| Szint | Mit tartalmaz | Kinek |
|---|---|---|
| **Digital** | Breadboard-térkép + BOM-lista (Hestore/AliExpress cikkszámokkal) + építési útmutató + videósorozat | Aki maga szerzi be az alkatrészeket, vagy csak tanulni szeretne |
| **Core** | Digital + **előprogramozott EEPROM-ok** (program + mikrokód) | Aki nem akar EEPROM-programozót beszerezni, de szívesen vásárol alkatrészt |
| **Full** | Core + **breadboard + összes alkatrész** egy csomagban | Aki egyetlen csomagot szeretne, és nulláról építene |

A **Digital** szint a belépő (maximális elérés, oktatás); a **Core** és **Full** szint kézzelfogható kit-ként szállítható.

## Kapcsolat a CLI-CPU projekttel

| | 8-bit diszkrét (ez) | 32-bit szimulátor/FPGA (fő projekt) |
|---|---|---|
| Cél | Oktatás, demó, közösség | Referencia + szilícium-út |
| Szélesség | 8-bit | 32-bit |
| Megvalósítás | 74HC breadboard | C# sim + Verilog FPGA |
| ISA | CIL-T0 részhalmaz | Teljes CIL-T0 (48 opkód) |
| Fázis | Önálló didaktikus ág | F1.5 KÉSZ → F2.8 |

A 8-bites változat ugyanazt az **ISA-filozófiát** (stack-alapú, int-only, objektum nélküli) demonstrálja kézzelfogható hardverben, amit a 32-bites referencia-szimulátor és az FPGA-implementáció teljes mélységében megvalósít.

## Háttér

A magyar YouTube-on jelenleg **nincs** alkatrész-szintű, a nulláról építő CPU-építő csatorna. A meglévő magyar tech-csatornák (Kernel Pánik, Neonity, TECHWorldhu) hardver-teszt és IT-hír fókuszúak, nem mélyarchitekturális oktatás. Az OctaCIL kit + dokumentáció pontosan ezt a betöltetlen rést célozza meg.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-06-08 | Kezdeti verzió — 8-bites diszkrét CIL-T0 építés (blokk-vázlat, funkcionális egységek ~37 IC, mikrokód ROM, programozás, BOM, kapcsolat a fő projekthez) |
| 1.1 | 2026-06-09 | OctaCIL brand bevezetése (cím + bevezető + motiváció) és termékszintek (Digital / Core / Full) szekció |
| 1.2 | 2026-06-10 | AT28C256 → AT28C64 (8 KB elég a program + mikrokódhoz); az „EEPROM dominálja a költséget" állítás javítva (a breadboard + memória dominál) |
| 1.3 | 2026-06-25 | Külső személynév-hivatkozások eltávolítása — a leírás generikus, eszközfüggetlen megfogalmazásra váltva („lépésről lépésre felépíthető", „a nulláról építő", „bevett mikrokódos megközelítés") |
