# NLnet Pályázat — Beadás utáni korrekciók

> **Cél:** Ez a dokumentum a CLI-CPU NLnet NGI Zero Commons Fund pályázat **beadása UTÁN** azonosított belső review korrekciókat rögzíti. A beadott fájl ([`nlnet-application-draft-hu.md`](nlnet-application-draft-hu.md) ill. `-en.md`) **változatlanul** megőrzi, mint az NLnet-hez beérkezett szöveg hiteles rekordját.
>
> **Hogyan használjuk:**
> - Ha az NLnet bírálók pontosítást kérnek, használd az alábbi finomított szövegeket a válaszhoz.
> - A follow-up pályázat (F5-F6) már ezeket a korrekciókat kezdetektől beépíti.
> - A párhuzamos Neuron OS pályázat ([`FenySoft/NeuronOS`](https://github.com/FenySoft/NeuronOS)) már tükrözi ezeket a tanulságokat.

> English version: [nlnet-corrections-en.md](nlnet-corrections-en.md)

> Version: 1.0 — 2026-04-23

---

## 1. korrekció — Tiny Tapeout költségvetés alulbecsült

**Beadott szöveg (M2 mérföldkő + hardver subtotal):**
> „1× Tiny Tapeout 16 tile-os submission: ~€1,200"
> „Hardver összesen: ~€2,440"

**Probléma:** A 2026-os TT shuttle árazás magasabb a €1,200-as becslésnél; a reális 16-tile ár €1,500–3,000.

**Finomított szöveg:**
> Tiny Tapeout submission (8-16 tile, a végleges shuttle árazástól függően beadáskor): **€1,500–3,000**. B terv: ha a 16-tile meghaladja a keretet, 8 tile-os submission (Nano core + UART, mailbox nélkül — a mailbox helyette FPGA-n M3-ban verifikálva).
> Hardver subtotal tartomány: **~€2,760–€4,360**. Ha a hardver költség meghaladja az allokációt, a személyi óra arányosan csökken, megőrizve mind az 5 mérföldkövet.

---

## 2. korrekció — EU szuverenitás állítás pontatlan volt

**Beadott szöveg:**
> „Európai szuverenitás: Teljesen nyílt processzor-design, amelyet bármely európai entitás gyárthat, auditálhat és tanúsíthat — függetlenül US/ázsiai IP licenszeléstől (ellentétben az ARM, RISC-V kereskedelmi core-ok vagy x86 esetével)."

**Probléma:** Az F3 első szilícium a Sky130-at (SkyWater, US-alapú PDK) célozza. A tiszta „európai szuverenitás" állítás csak a HDL/design rétegre igaz; az F3 gyártási útvonal US-ben van.

**Finomított szöveg:**
> **Európai szuverenitás (IHP SG13G2 útvonalon keresztül):** A teljes HDL/RTL stack licensz-mentes és portolható bármely nyílt PDK-ra. Az F3 első szilícium a Sky130-at (SkyWater, US) célozza a legalacsonyabb Tiny Tapeout belépési költség miatt — tudatos pragmatikus választás a kezdeti proof-of-silicon-hoz minimális költségen. Az F6+ szilícium **IHP SG13G2 (Németország)** célpontra tervezett — teljesen európai foundry útvonal US/ázsiai IP függőségek nélkül. A design konstrukciósan portolható; csak a gyártási helyszín változik fázisok között.

---

## 3. korrekció — M4 „Rich core RTL" scope túlvállalt volt

**Beadott szöveg (M4 mérföldkő):**
> „Rich core (teljes CIL) RTL tervezés kezdete: objektum modell, GC assist, kivételkezelés, FPU. Heterogén Nano+Rich FPGA demó."

**Probléma:** A teljes Rich core RTL (~220 opkód + GC + kivételek + FPU) nem megvalósítható 6 hónap alatt részmunkaidőben. A bíráló ezt irreálisnak jelölheti és megkérdőjelezheti a €7,000 allokációt.

**Finomított szöveg:**
> **M4: Rich core specifikáció + mikroarchitektúra (F5 kezdet).** Rich core **specifikáció és mikroarchitekturális tervezés** — nem teljes RTL: objektum modell, GC assist, kivételkezelés, FPU, mind RFC-stílusú specifikációkban dokumentálva ciklus-pontos mikroarchitekturális diagramokkal. Az első 30-40 opkód implementálva szintetizálható proof-of-concept blokként. A heterogén Nano+Rich FPGA demó **stretch cél**. A teljes Rich core RTL implementáció dedikált follow-up grantre van scope-olva (valódi F5).

---

## 4. korrekció — Duplikált bekezdés a hardver-szintű biztonságról

**Beadott szöveg:** A „Miért releváns az NGI ökoszisztéma számára" szekció tartalmaz egy önálló „Hardver-szintű biztonság növekvő relevanciája" bullet-et, ÉS a „Miért most?" bekezdés ugyanazt a témát ismétli.

**Probléma:** Tartalmi duplikáció. A bírálók észreveszik az ismétlést.

**Finomított szöveg:** Egyetlen „Miért most?" bekezdésbe olvasztva:
> **Miért most?** A nyílt PDK-k (Sky130, IHP SG13G2), az érett aktor-modell keretrendszerek (Akka.NET, Orleans), a Dennard skálázás végének sok-magos architektúrák felé tolása, a szilícium demokratizálódása (Tiny Tapeout, eFabless), és a hardver-szintű biztonság növekvő sürgőssége az eszkalálódó kiberfenyegetésekkel szemben — a kizárólag szoftveres megoldások egyre kevésbé elegendőek supply chain támadások (log4j, xz-utils), AI-generált exploitok és állami szintű fenyegetések ellen — együttesen teszik életképessé és szükségessé a sok-magos bytecode-natív megközelítést 2026-ban, ott, ahol az egymagos picoJava 1997-ben megbukott. A CLI-CPU hardveresen kikényszerített memória-biztonsága, típus-biztonsága és vezérlési folyamat integritása semmilyen szoftveres exploit-tal nem kerülhető meg.

---

## 5. korrekció — „8 millió .NET fejlesztő" pontosítást igényelt

**Beadott szöveg:**
> „8 millió .NET fejlesztő célozhatja meg ezt a hardvert ismerős eszközökkel"

**Probléma:** Kerek szám forrás nélkül marketing-szerűen hangzik. Technikai bírálók diszkontálhatják az állítást.

**Finomított szöveg:**
> **Jelentős létező .NET fejlesztői bázis** célozhatja meg ezt a hardvert ismerős eszközökkel. Minden .NET nyelv (C#, F#, VB.NET) CIL-re fordul. A Microsoft éves fejlesztői felmérései és az Akka.NET / Orleans éles telepítései bizonyítják a runtime beágyazott pozícióját enterprise szoftverben — különösen szabályozott iparágakban (pénzügyi szolgáltatások, kormányzat, egészségügy), ahol a CLI-CPU biztonsági modell a leginkább értékes.

---

## 6. korrekció — Párhuzamos Neuron OS pályázat bejelentése szükséges

**Beadott szöveg (meglévő finanszírozási források):**
> „Nincs más függőben lévő pályázat ugyanerre a munkára."

**Probléma:** A beadás óta párhuzamos NLnet pályázat készült a **Neuron OS**-re. Bár a két projekt scope-ban elhatárolt (hardver vs szoftver), átláthatóság szükséges.

**Finomított addendum:**
> Párhuzamos NLnet NGI Zero Commons Fund pályázat tervezett (2026 Q3 beadási ablak) a **Neuron OS** projektre ([`FenySoft/NeuronOS`](https://github.com/FenySoft/NeuronOS)) — a capability-alapú aktor runtime, amely közösen-tervezve, de scope-ban elhatárolva készül ettől a hardveres pályázattól.
>
> | Dimenzió | CLI-CPU / CFPU | Neuron OS |
> |----------|---------------|-----------|
> | Deliverable | Hardveres ISA, RTL, silicon tape-out, FPGA | Szoftveres runtime, OS szolgáltatások |
> | Cél | Verilog szintézis, Sky130 PDK | .NET 10 library (Windows/Linux/macOS) |
> | Licensz | CERN-OHL-S-2.0 | Apache-2.0 |
> | Repository | `FenySoft/CLI-CPU` | `FenySoft/NeuronOS` |
> | Mérföldkövek | F2 RTL, F3 Tiny Tapeout, F4 FPGA multi-core | M0.3-M3.2 aktor runtime + kernel aktorok |
>
> A két pályázat szándékosan nem átfedő scope-pal rendelkezik. A Neuron OS nem függ a CLI-CPU szilíciumtól (ma szimulátorokon fut); a CLI-CPU nem függ a Neuron OS-től (a hardvernek saját C# referencia szimulátora van).

---

## 7. korrekció — IHP MPW jogosultság pontosítás szükséges

**Beadott szöveg:**
> „IHP SG13G2 ingyenes MPW: A 2026 októberi shuttle-re tervezett pályázat."

**Probléma:** Az IHP ingyenes/kutatási MPW csatorna jellemzően akadémiai intézményi host-ot igényel. A FenySoft Kft. (kereskedelmi entitás) önmagában nem jogosult ingyenes MPW slot-okra — ezt nem ismertük el a beadott szövegben.

**Finomított szöveg:**
> **IHP SG13G2 MPW (F6+), 2027+:** Az IHP ingyenes/kutatási MPW csatorna jellemzően akadémiai intézményi host-ot igényel. A FenySoft Kft. önmagában nem jogosult ingyenes slot-okra. Az F6 szilíciumhoz három útvonal egyikét követjük:
> - (a) Magyar egyetemmel partnerkedés (BME Elektronikus Eszközök Tanszék vagy SZTAKI) mint társpályázó EUROPRACTICE kutatási credit eléréséhez.
> - (b) Pályázat külön kereskedelmi MPW grant-en keresztül (pl. Horizon Europe digitális szuverenitás hívás).
> - (c) Kereskedelmi IHP mini@shuttle (~€15-30K) finanszírozása follow-up grantekből.
>
> Ez az útvonal **nem része a jelenlegi pályázatnak**, és follow-up munkát képvisel.

---

## 8. korrekció — Fenntarthatósági terv konkrétabb csatornákat igényelt

**Beadott szöveg (fenntarthatósági terv):**
> „(1) Következő NLnet pályázat az F5-F6-ra (Rich core + silicon tape-out). (2) IHP SG13G2 ingyenes MPW pályázat kutatási szilíciumra. (3) Hosszú távon: dual licensing modell. (4) GitHub Sponsors / Open Collective a folyamatos közösségi karbantartásra."

**Probléma:** Négy pont, egyikük (IHP ingyenes MPW) fent korrigálva. A bíráló jellemzően 3 éven belüli önfenntarthatóságot vár.

**Finomított szöveg (6 csatorna):**
> 1. **Grant lánc:** Következő NLnet pályázat az F5-F6-ra (Rich core RTL + silicon tape-out), tervezett €50-150K. A párhuzamos Neuron OS grant keresztökoszisztémás legitimitást ad.
> 2. **Európai kutatási útvonalak:** Chips JU / TRISTAN konzorciumi részvétel nem-RISC-V hozzájárulóként (CIL ISA mint kiegészítő célpont); Horizon Europe digitális szuverenitás hívások; IHP SG13G2 kutatási szilícium akadémiai partnerségen keresztül.
> 3. **Dual licensing modell:** A core repo CERN-OHL-S-2.0 marad (erős reciprocal). Kereskedelmi licenszek elérhetők: (a) tanúsított termékekhez (IEC 61508, ISO 26262, IEC 62304) és (b) proprietary derivative RTL-hez — analóg a MariaDB / MongoDB üzleti modellel, szilíciumra alkalmazva.
> 4. **Tanácsadási / integrációs szolgáltatások (FenySoft Kft., meglévő entitás):** Egyedi CFPU integráció szabályozott iparágaknak (egészségügy, kritikus infrastruktúra) keresztfinanszírozást biztosít a nyílt-core karbantartáshoz.
> 5. **Online tanúsítás / képzés:** CFPU architektúra és secure-by-design hardver fejlesztési tanúsítási kurzusok (lásd `project_monetization_model` emlékeztető).
> 6. **Közösségi finanszírozási csatornák:** GitHub Sponsors / Open Collective elindítva a 6. hónapban. Cél: €500–1500/hónap stabil állapot a 2. év végére.
>
> **.NET Foundation tagsági pályázat** a 12. hónapban infrastruktúra támogatásért (code signing, CLA management, Azure hosting — nincs direkt finanszírozás, de közösségi legitimitás).
>
> A projektnek **dokumentált útvonala van az önfenntartáshoz 3 éven belül** folyamatos grant-függőség nélkül.

---

## 9. korrekció — Team kockázat (egyedüli pályázó) mitigációs nyelvezet

**Beadott szöveg:** Nincs explicit említés a hozzájárulói növekedési tervről.

**Probléma:** Az egyedüli-pályázó projektek dokumentált kockázati tényező az NLnet-nél. A beadott szöveg ezt nem kezelte.

**Finomított addendum (közösségépítési tervhez):**
> **Hozzájárulói növekedési kötelezettség:** `CONTRIBUTORS.md` fájl karbantartása a repóban, az összes technikai hozzájáruló (RTL szerzők, cocotb testbench szerzők, dokumentáció karbantartók) feltüntetésével — nem csak tipó-javító PR-ok. A cél egy dokumentált multi-contributor projekt a 18 hónapos grant időszak alatt (cél: 3+ érdemi külső hozzájáruló a 12. hónapra).
>
> **Supporting letterek:** A follow-up pályázathoz egy akadémiai levelet (BME Elektronikus Eszközök Tanszék vagy SZTAKI) és egy industry levelet (.NET Foundation tag, Akka.NET karbantartó, vagy Tiny Tapeout mentor) csatolunk az intézményi háttér dokumentálására.

---

## 10. korrekció — CFPU / CLI-CPU névegyeztetés (részben kezelve v1.2-ben)

**Státusz:** A beadás utáni v1.2 frissítés visszamenőlegesen bevezette a CFPU elnevezést. A README és a dokumentáció frissítve. Ha egy bíráló ma megnyitja a GitHub repót, prominens „CFPU"-t lát — ami eltér a beadott pályázat címétől („CLI-CPU").

**Javasolt README kiegészítés (fájl teteje):**
> **Elnevezés:** A CLI-CPU a **Cognitive Fabric Processing Unit (CFPU)** architektúra referencia implementációja. A projekt azonosítója (CLI-CPU) erre a konkrét nyílt forráskódú implementációra utal; a CFPU a szélesebb processzor-kategóriára utal. A két név együtt jelenik meg a dokumentáció egészében.

Ez explicitté teszi a kapcsolatot bármely bíráló számára, aki a pályázatból követi a README linket.

---

## B szekció — Ténylegesen a beadott szövegben lévő hibák

> Ezek **nem javaslatok a javításra** — hanem olyan hibák, amelyek bekerültek a NLnet-hez beadott szövegbe. A beadási visszaigazoló PDF átnézése során fedeztük fel. Proaktívan tisztázandók, ha a bírálók az érintett szekciókat érintik.

### 11. korrekció — Cím kihagyja a „Processing Unit (CFPU)" kibővítést

**Beadott cím:**
> „CLI-CPU: Open Source Cognitive Fabric **Processor** — Native CIL Execution on Libre Silicon"

**Szándékolt (draft v1.2) cím:**
> „CLI-CPU: Open Source Cognitive Fabric **Processing Unit (CFPU)** — Native CIL Execution on Libre Silicon"

**Hatás:** A CFPU akronim — ami prominensen jelenik meg a repó egészében — nem szerepel a beadott címben. Egy bíráló, aki megnyitja a GitHub linket, olyan „CFPU" terminológiát lát, ami hiányzik a beadványból. Mitigáció: válasz tisztázva, hogy a „CFPU" és a „Cognitive Fabric Processor" ugyanarra a koncepcióra utal; az előbbi a preferált, bővített forma.

### 12. korrekció — Technikai elírás: „OPI" helyett „QSPI"

**Beadott szöveg (challenges §4):**
> „**OPI** memory latency: On-chip SRAM limited (4-16 KB per core). Code and data fetched from **OPI** flash/PSRAM with 6-10 cycle latency."

**Szándékolt (draft):**
> „**QSPI** memory latency: ... from **QSPI** flash/PSRAM with **10-50** cycle latency."

**Hatás:** Technikai pontatlanság. Az OPI (Octal Peripheral Interface) egy másik protokoll. A referencia design QSPI (Quad SPI) külső memóriát céloz. A ciklus latency érték is hibás (6-10 → 10-50). Mitigáció: ha a bíráló a memória-architektúrát érinti, tisztázni transzkripciós hibaként és a helyes értékekre hivatkozni.

### 13. korrekció — Ökoszisztéma: európai foundry állítás aspiratív

**Beadott szöveg (ecosystem):**
> „European digital sovereignty: fully open, auditable processor manufactured at European foundries (IHP SG13G2, GlobalFoundries Dresden)."

**Probléma:** A beadott szöveg azt mondja, európai foundry-k „gyártják" a chipet — de az F3 első szilícium a Sky130-at célozza (SkyWater, US). Csak az F6+ megy hipotetikusan IHP SG13G2-re. Ez a megfogalmazás aspiratív, nem aktuális. Kombinálva a 2. korrekcióval — a szuverenitás narratívának szüksége van az F3/F6+ megkülönböztetésre, hogy őszinte legyen.

### 14. korrekció — Magyar ékezetek elvesztek tulajdonnevekben

**A beadott szöveg tartalmazza:**
- „Adougyi Ellenorzo Egyseg" — helyesen „**Adóügyi Ellenőrző Egység**"
- „MAV" — helyesen „**MÁV**"

**Hatás:** Kozmetikai, de elsietett beadásra utal. Valószínűleg form encoding vagy copy-paste probléma volt a beadási űrlap kitöltésekor. Mitigáció: nem szükséges, hacsak a bíráló nem kérdez a magyar Adóügyi Ellenőrző Egység kontextusáról — akkor helyesen írni a tulajdonneveket a válaszban.

---

## Mit tegyünk, ha az NLnet bírálók pontosítást kérnek

1. **Ismerjük el, hogy a beadott verzió a v1.2** (a filed szöveg), és ajánljuk fel ezt a korrekciós dokumentumot pontosításként.
2. **A leginkább lényegi korrekciókkal kezdjünk** (#1 TT árazás, #3 M4 scope, #8 fenntarthatóság) — ezek érintik a költségvetést és deliverable-öket.
3. **Proaktívan ajánljuk fel a PDF mellékleteket**, ha még nem lettek beadva (architektúra áttekintés, roadmap, teszt screenshotok, 1-oldalas executive summary).
4. **Említsük meg a párhuzamos Neuron OS pályázatot** (#6) elöl, hogy elkerüljük a kapcsolódó finanszírozási tervek elhallgatásának látszatát.

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.1 | 2026-04-23 | B szekció hozzáadva — négy tényleges hiba a beadott szövegben (§11-14), az NLnet visszaigazoló PDF átnézése során azonosítva: cím nem tartalmazza a CFPU akronimet, OPI/QSPI elírás + hibás ciklus szám, európai foundry-k aspiratív állítás, elvesztett magyar ékezetek. |
| 1.0 | 2026-04-23 | Kezdeti beadás utáni korrekciós dokumentum. 10 javítási javaslat katalogizálva belső review alapján (A szekció). A beadott draft fájl változatlanul megőrizve. |
