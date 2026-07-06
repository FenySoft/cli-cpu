---
status: vision
---

# CFPU 3D Stack Architektúra — memória-integráció és rétegződés

> English version: [3d-stack-architecture-en.md](3d-stack-architecture-en.md)

> Version: 1.0

> **⚠️ Vízió-szintű pozicionáló dokumentum.** A CFPU-oldali rétegződés vízió-szintű terv; a pontos paraméterek (rétegszám, TSV-sűrűség, per-csempe SRAM méret, memória-mesh szemcsézet) a részletes tervezési (RTL/implementációs) fázisokban rögzülnek. A valós-chip adatok (AMD MI300, Intel Ponte Vecchio, CEA-Leti IntAct, Cerebras WSE, Tenstorrent) nyilvános forrásokból származnak — lásd a [Külső források](#külső-források-valós-chipek) szekciót.

Ez a dokumentum a CFPU **3D vertikális rétegződési vízióját** specifikálja nagy (sok tízezer core-os) mesh-ekre: hogyan kapcsolható a memória **maximális sebességgel** egy many-core 2D mesh-hez, milyen a rétegzett stack (compute-mesh / per-csempe SRAM / memória-mesh / perem-DRAM), miért **két külön fizikai NoC-sík**, mi a termikus orientáció, és **hol kezdődik a CFPU-újdonság** a valós szilíciumhoz képest.

Ez a dokumentum a [`chiplet-packaging-hu.md`](chiplet-packaging-hu.md) **vertikális (3D) kiegészítője**: az utóbbi a 2.5D **vízszintes** chiplet-elrendezést tárgyalja (C/R chiplet, interposer, CoWoS), ez pedig a **függőleges** memória/mesh-stacket. A valóságban a kettő együtt ad „3.5D" csomagot (lásd MI300).

## A probléma: a lapos 2D mesh memória-fala nagy N-nél

Egy √N × √N 2D mesh-ben a **bisection sávszél ∝ √N**, miközben a core-szám **N** — így a kereszt-chip per-core sávszél **∝ 1/√N** (lásd [`topology-scaling-hu.md`](topology-scaling-hu.md)). Ha a memória **csak a 4 peremen** ül, a belső linkek a szélek felé **befulladnak**, mielőtt maga a memóriachip telítődne.

Konkrétan **256×256 = 65 536 core** esetén:

| Mérőszám | Érték |
|----------|-------|
| Perem-csomópont (potenciális memória-tap) | 4·256 − 4 = **1 020** |
| Egy tapre jutó core | 65 536 / 1 020 ≈ **64** |
| Átlagos távolság a legközelebbi szélig | több tíz hop; a közepén **~128 hop** |
| Bisection (középső vágás) | **256 link** → per-core kereszt-chip rész ≈ **1/256** |

> A **256 link** a középső vágást keresztező (egyirányú) fizikai linkek száma (√N); a [`topology-scaling-hu.md`](topology-scaling-hu.md) ugyanezt **kétirányú sávszélként** fejezi ki (2√N·B). A skálázás (∝ 1/√N) mindkét konvencióban azonos; csak a konstans faktor tér el 2×-szel.

**A gyilkos összefüggés:** a core-szám **négyzetesen** (N), a középső áteresztő csak **lineárisan** (√N) nő — tehát **több core = core-onként kevesebb** kereszt-chip sávszél. A 4 peremre rakott memória ezt **nem oldja meg**; a szűk keresztmetszet nem a szél, hanem a **belső mesh-linkek**. A megoldás nem a síkon van.

## Döntési nyom: hogyan kapcsoljuk a memóriát a mesh-hez

| Alternatíva | Lényeg | Verdikt |
|-------------|--------|---------|
| **A** — Memória csak a 4 peremen (2D) | mind a 4 él kihasználva, interleave-elt címtér | 4× perem-BW, de a belső link-funnel + 1/√N fal marad → **elégtelen** önmagában nagy N-nél |
| **B** — Diamond / belső tap-ek (2D, Abts 2009) | a memória-beszúrási pontok a fabric belsejébe is szétszórva | a **2D-optimum** (kiegyenlített hop + link-terhelés), de **még mindig a síkba** ütközik |
| **C** — 3D-stacked DRAM (HBM-on-logic) | DRAM közvetlenül a compute fölé/alá stackelve | nagy kapacitás, de **process-eltérés** (DRAM ≠ logika), lassabb, és a **hőérzékeny DRAM a forró compute mellett** rossz → **elvetve mint elsődleges** |
| **D — VÁLASZTOTT** — 3D-stacked SRAM + külön memória-mesh sík | per-csempe SRAM a compute-hoz stackelve; a hideg DRAM egy külön memória-mesh szélein | lásd alább |

**A D választás indokai:**

1. **Azonos gyártási process.** Az SRAM ugyanabban a logikai CMOS-folyamatban készül, mint a core-ok → a stackelés **könnyű** (hybrid bond), szemben a DRAM process-eltérésével. Ez nem elmélet: az **AMD 3D V-Cache** pontosan ezt csinálja tömeggyártásban.
2. **Sebesség + sávszél kapacitás helyett.** Az SRAM néhány ciklusos, óriási vertikális sávszéllel — a working setnek pont ez kell; a kapacitás-igényt a hideg DRAM-tier fedi.
3. **Az SRAM-area kiköltözik a logikából.** Lapos die-on minden KB scratchpad **elveszi a compute-területet**; 3D-ben az SRAM külön die-ra kerül → **több core/die + jobb yield** a logikán, az SRAM meg SRAM-ra optimalizált node-on. (Az SRAM amúgy is megállt zsugorodni az új node-okon — lásd [`chiplet-packaging-hu.md`](chiplet-packaging-hu.md) „SRAM fal".)
4. **A memória lekerül a mesh-ről.** A per-csempe SRAM **0 mesh-hoppal**, függőlegesen elérhető → a memóriaforgalom **nem terheli** a core-mesh-t, és a fenti 1/√N fal **eltűnik** a forró útból.

## A választott architektúra: a rétegzett stack

```
   [ hűtő ]
   ┌────────────────────────────────────────────┐
   │ CORE-mesh (2D mesh #1 — aktor-üzenetek)      │ ← FELÜL (termikus döntés)
   ├────────────────────────────────────────────┤
   │ per-csempe 3D SRAM (PRIVÁT scratchpad, 0-hop)│
   ├────────────────────────────────────────────┤
   │ MEMÓRIA-mesh (2D mesh #2)                     │      ┌─ DRAM/HBM
   │   aktív interposer + memóriavezérlők          │◄────►│  (a mesh SZÉLEIN)
   ├────────────────────────────────────────────┤
   │ interposer + hordozó                         │
   └────────────────────────────────────────────┘
```

| Réteg | Szerep |
|-------|--------|
| **Core-mesh** (felül) | a Cognitive Fabric üzenet-hálózata: sok kis, független core, aktor-üzenetküldés (shared-nothing) |
| **per-csempe 3D SRAM** | privát scratchpad minden core alatt/fölött, függőleges TSV, ~1–2 ciklus, **0 mesh-hop** |
| **Memória-mesh** (alul) | dedikált, sávszélre hangolt hálózat az SRAM↔DRAM (hideg) forgalomhoz; egyben **aktív interposer** (routing + memóriavezérlők) |
| **DRAM/HBM** | a kapacitás-tier a **memória-mesh szélein** (2.5D HBM-stack / off-package) — nem a forró compute alatt |

### Két fizikai NoC-sík (forgalmi osztály szerint)

A kulcs-döntés, hogy **két különböző forgalmat két külön hálózat** visz:

| | **Core-mesh** (felül) | **Memória-mesh** (alul) |
|---|---|---|
| Mit visz | inter-core aktor-üzenetek | SRAM↔DRAM (spill/fill, hideg tier) |
| Jellege | kicsi, latency-érzékeny | tömeges, sávszél-éhes |
| Optimalizálás | gyors, keskeny linkek | széles linkek, **durvább szemcsézet** (aggregáló) |

**Trade-off — fizikai sík vs virtuális hálózat (VN):** a CFPU eddig egy mesh-en, **virtuális hálózatokkal** (2VN, lásd [`interconnect-hu.md`](interconnect-hu.md)) választotta szét a forgalmi osztályokat közös vezetékeken. Itt a **memória-VN-t a saját fizikai síkjára emeljük**: drágább (extra réteg), de **tökéletes izoláció** (a tömeges memóriaforgalom soha nem fojtja a latency-kritikus üzenetküldést) és **külön optimalizálhatóság**. A két sík **két külön „4 szélet"** is ad: a core-mesh szélei → host-I/O + chip-chip link; a memória-mesh szélei → DRAM.

### Az SRAM mint sávszél-szűrő

A memória-mesh is 2D, tehát elvileg ugyanaz a 1/√N fal fenyegetné — **de az SRAM sávszél-szűrőként megmenti:**

- A forró working setet a **függőleges SRAM** szolgálja ki (0 hop). Csak a **miss** megy le a memória-mesh-re.
- Jó SRAM-találati aránynál a memória-mesh a teljes forgalom **töredékét** cipeli.
- Ha a working set elfér az SRAM-ban → a DRAM-forgalom **~0-ra** esik (Cerebras-elv).
- A CFPU aktor working setjei szerények (komfort ~100–300 KB/core, lásd [`core-types-hu.md`](core-types-hu.md)) → a per-csempe 3D SRAM ezt **reálisan eltarthatja**.

### Termikus orientáció: compute felül

**Al-döntés:** SRAM felül (logika alul) **vagy** compute felül (SRAM/memória alul)?

A forró compute a hűtőhöz közel kell legyen. Bizonyíték az **AMD 3D V-Cache** evolúciója:

| Generáció | Elrendezés | Következmény |
|-----------|-----------|--------------|
| Zen 3/4 (5800X3D, 7800X3D) | cache **felül**, structural silicon | hő-fojtás → **downclock** |
| Zen 5 (9800X3D) | cache a **CCD alatt** | **full clock**, ~46% jobb termikus ellenállás, overclock |

→ **CFPU: compute (core-mesh) felül.** Ára: a **tápot fel kell juttatni** a felső logikához — vagy táp-TSV-kkel a köztes rétegeken át, vagy elegánsabban **háttér-oldali tápellátással** (BSPDN — Intel PowerVia / TSMC backside), amely a tápot felülről adja (ugyanonnan, ahonnan a hő távozik), az alsó oldalt pedig felszabadítja az adat-TSV-knek.

## Valós-szilícium pozicionálás

**Minden egyes darabja** ennek az architektúrának **létezik valós, szállító szilíciumban** — a *pontos kombináció ebben a léptékben* viszont nem kész termék.

| A CFPU architektúra eleme | Valós chip, ami már csinálja | Státusz |
|---------------------------|------------------------------|---------|
| Sok kis core 2D mesh-ben (üzenet-NoC) | Tenstorrent (Tensix), Cerebras WSE, Tilera, Intel mesh | szállító |
| SRAM 3D-ben a compute-ra rétegezve | **AMD 3D V-Cache** (a compute-ra), Intel Ponte Vecchio RAMBO (a base tile-ra) | szállító |
| Logika felül / cache alul (termikus) | **AMD Zen 5 X3D (9800X3D)** | szállító |
| Külön memória-hálózat base die / aktív interposer rétegben | **AMD MI300 IOD/AID**, Intel PV Foveros base tile, **CEA-Leti IntAct** | szállító (MI300/PV) + kutatás (IntAct) |
| DRAM a széleken (2.5D HBM), nem a forró úton | AMD MI300, Intel Ponte Vecchio | szállító |
| SRAM-everywhere, DRAM nélkül a forró úton | **Cerebras WSE** | szállító |

**A legközelebbi egész rendszerek:**

- **AMD MI300 (legközelebbi kereskedelmi).** Compute-die-ok (XCD/CCD) **felülre 3D-stackelve** (SoIC, 9µm hybrid bond) ülnek az **IOD-eken** (AMD hivatalos neve; az elemzők **AID = Active Interposer Die** néven is hivatkoznak rá). Az IOD tartalmazza a **memória-hálózatot (Infinity Fabric AP) + memóriavezérlőket + 256 MB Infinity Cache-t** (megosztott LLC, 128 × 2 MB slice). A **8× HBM3** a **CoWoS-S interposeren, az IOD mellett** (2.5D). AMD ezt „**3.5D**"-nek hívja (SoIC 3D + CoWoS 2.5D).
- **Intel Ponte Vecchio.** 63 tile: 16 compute + **8 RAMBO SRAM-cache** (15 MB/tile, 3D-stackelve) + 2 **Foveros base tile** (memóriavezérlő + fabric + FIVR) + 8 HBM2E + Xe-Link + EMIB.
- **CEA-Leti IntAct (legközelebbi kutatás).** 96 core, 6 chiplet **3D-stackelve egy aktív interposeren**, és **a NoC magában az aktív interposerben él** (chiplet-chiplet hálózat + L1/L2/L3 + integrált tápellátás). Ez **szó szerint** a mi „memória-mesh egy réteggel lejjebb" koncepciónk demonstrátor-szinten.
- **Cerebras WSE / Tenstorrent (filozófiai rokonok).** Cerebras: ~850k csempe uniform 2D mesh-ben, 48 KB SRAM/csempe, **nulla külső DRAM** (de 2D, nem 3D). Tenstorrent: Tensix-mesh + NoC, ~1,5 MB SRAM/csempe, hibrid memória — a **CFPU legközelebbi kereskedelmi unokatestvére** üzenet-mesh filozófiában.

### MI300 réteg-összevetés

| Dimenzió | MI300 | CFPU (mi) | |
|----------|-------|-----------|:--:|
| Compute felül (termikus) | XCD/CCD felül, SoIC | core-mesh felül | ✅ egyezik |
| Base die = aktív interposer memória-hálózattal | IOD/AID: Infinity Fabric + MC + LLC | memória-mesh réteg | ✅ egyezik az elv |
| DRAM a széleken (2.5D) | 8× HBM3 CoWoS-on, IOD mellett | HBM a memória-mesh szélein | ✅ egyezik |
| 3D integráció (hybrid bond + TSV) | SoIC 9µm + CoWoS | TSV/hybrid bond | ✅ egyezik (tech) |
| **Szemcsézettség** | ~12–13 nagy chiplet (8 XCD × 38 CU) | ~65 000 apró, független core | ❌ eltér (durva vs finom) |
| **Hálózat** | **EGY** koherens fabric (Infinity Fabric AP), VC-kkel | **KÉT** külön fizikai mesh-sík, forgalmi osztály szerint | ❌ eltér |
| **SRAM/cache** | 256 MB **megosztott**, memória-oldali LLC az IOD-ben | per-csempe **privát** 3D scratchpad, 0-hop | ❌ eltér |
| **Memóriamodell** | cache-**KOHERENS**, egységes/megosztott (NUMA) | shared-**NOTHING**, üzenetküldés + capability | ❌ eltér (a legmélyebb) |
| **Végrehajtás / ISA** | GPU CU-k (CDNA3) | natív CIL bytecode, in-order actor-core | ❌ eltér |

> **Pontosítás:** az **MI300 nem rak külön SRAM-die-t a compute-ra** (az a V-Cache / a Ponte Vecchio RAMBO). Az MI300 cache-e a **base IOD-ben** ül, megosztott, memória-oldali LLC-ként. Tehát a mi **per-csempe 3D SRAM-rétegünkhöz nem az MI300** a párhuzam, hanem a V-Cache/RAMBO — az MI300 a **memória-hálózat-a-base-die-ban + perem-HBM + compute-felül** részt igazolja.

## Hol kezdődik a CFPU-újdonság

> **A CSOMAG (a fizikai „hogyan stackeljünk") bizonyított — az ÚJDONSÁG a rétegek TARTALMÁBAN és VISELKEDÉSÉBEN van.**

Az MI300 igazolja, hogy a stacked elrendezés (**compute felül + aktív-interposer memória-base + perem-HBM + hybrid bond**) **kereskedelmi, tömeggyártott valóság** → a CFPU **csomagolása alacsony kockázatú**. A CFPU nem a csomagban innovál, hanem abban, amit a rétegekbe tesz:

1. **Szemcsézettség** — 65k finom, független core (Cerebras-finomság) az MI300 tucatnyi nagy chipletje helyett; ezt a memória-base-zel **senki nem kombinálta**.
2. **Két fizikailag szétválasztott NoC-sík** (üzenet vs memória) az MI300 **egyetlen** koherens fabricje helyett.
3. **Shared-nothing üzenetküldés + capability-memória** az MI300 **cache-koherens megosztott** memóriája helyett — ez a legmélyebb eltérés, és egyben a CFPU skálázási + biztonsági **moatja**.
4. **Per-csempe privát 3D scratchpad (0-hop)** az MI300 megosztott, memória-oldali LLC-je helyett.
5. **Natív CIL végrehajtás + HW-capability/security + Symphact statikus co-design** — ortogonális szoftver/ISA-moat, amit egyik fenti chip sem ad.

**Összefoglalva:** az MI300 bizonyítja, hogy a stacked elrendezés **fizikailag gyártható és él**; a CFPU újdonsága ott kezdődik, hogy ebbe a bevált csomagba **finomszemcsés many-core mesh-t, két forgalmi-osztály-szerint szétválasztott hálózati síkot, shared-nothing capability-memóriát és natív CIL-végrehajtást** tesz, amit együtt még senki. A rizikó a fizikában alacsony; a differenciálás az **architektúrában, a biztonságban és a szoftverben** van.

## Nyitott kérdések / jövőbeli irányok

1. **TSV-granularitás** — per-csempe (legjobb lokalitás, 0 hop, max TSV) **vs** per-klaszter (kevesebb TSV/bond, de pár hop a klaszteren belül a SRAM-portig). Valódi trade-off: TSV-sűrűség ↔ in-plane hop.
2. **Termika 3 aktív réteggel** — a memória-mesh legalul, legtávolabb a hűtőtől; szerencsére kisebb power-density (vezeték + DRAM-PHY), de ez tervezési tengely.
3. **Kapacitás-tier** — a hideg DRAM megmarad a memória-mesh szélein; a **cache-elt kód integritása** (W⊕X?) és a capability-grant összefüggése nyitott (lásd [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md)).
4. **Tápellátás** — BSPDN vs táp-TSV az egész stacken (compute felül → a tápot fel kell juttatni).
5. **Szemcsézet-illesztés** — pl. 256×256 core-mesh fölött egy 16×16 memória-mesh; egy SRAM-miss útja lefelé a DRAM-ig.

## Kapcsolódó dokumentumok

- [`chiplet-packaging-hu.md`](chiplet-packaging-hu.md) — 2.5D **vízszintes** chiplet-elrendezés (ennek a doksinak a párja); már tartalmaz „3D SRAM" és „3D package" szekciót
- [`topology-scaling-hu.md`](topology-scaling-hu.md) — bisection matematika, 1/√N skálázás, mesh vs crossbar vs hierarchikus
- [`interconnect-hu.md`](interconnect-hu.md) — CFPU NoC, 2VN, XY routing, router variánsok
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — capability grant, hideg memória-tier, CAM ACL
- [`core-types-hu.md`](core-types-hu.md) — SRAM méretezés (per-core komfort 100–300 KB)
- [`architecture-hu.md`](architecture-hu.md) — teljes CFPU áttekintés

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-07-02 | Kezdeti verzió — a CFPU 3D vertikális rétegződési víziója nagy mesh-ekre: a lapos 2D mesh memória-fala (1/√N, 256×256 konkrét számok), döntési nyom (A peremvédelem / B diamond / C 3D-DRAM / **D 3D-SRAM + memória-mesh — választott**), a rétegzett stack (core-mesh / per-csempe SRAM / memória-mesh / perem-DRAM), két fizikai NoC-sík (vs 2VN), termikus orientáció (compute felül, V-Cache-bizonyíték), SRAM mint sávszél-szűrő. Valós-szilícium pozicionálás (MI300/PV/IntAct/Cerebras/Tenstorrent) + MI300 réteg-összevetés + „hol kezdődik a CFPU-újdonság". A [`chiplet-packaging`](chiplet-packaging-hu.md) vertikális kiegészítője. |

## Külső források (valós chipek)

- AMD MI300 3D csomagolás (TechInsights): https://www.techinsights.com/blog/amd-mi300-family-adopts-3d-packaging
- MI300 „3.5D", SoIC+CoWoS, IOD/AID (SemiAnalysis): https://newsletter.semianalysis.com/p/amd-mi300-taming-the-hype-ai-performance
- MI300A memória-alrendszer, Infinity Fabric/Coherent Master (Chips and Cheese): https://chipsandcheese.com/p/inside-the-amd-radeon-instinct-mi300as
- MI300 mikroarchitektúra, 256 MB Infinity Cache (ROCm): https://rocm.docs.amd.com/en/latest/conceptual/gpu-arch/mi300.html
- AMD 9800X3D — V-Cache a CCD alatt (TechPowerUp): https://www.techpowerup.com/328225/de-lidded-ryzen-7-9800x3d-pic-confirms-3d-v-cache-die-moved-below-the-ccd
- Intel Ponte Vecchio 3D csomagolás (ServeTheHome): https://www.servethehome.com/intel-xe-hpc-ponte-vecchio-shows-next-gen-packaging-direction/
- CEA-Leti IntAct aktív interposer (WikiChip Fuse): https://fuse.wikichip.org/news/3364/cea-leti-demos-a-6-chiplet-96-core-3d-stacked-mips-processor/
- Cerebras WSE áttekintés (WikiChip Fuse): https://fuse.wikichip.org/news/3010/a-look-at-cerebras-wafer-scale-engine-half-square-foot-silicon-chip/
- Tenstorrent Wormhole elemzés (SemiAnalysis): https://newsletter.semianalysis.com/p/tenstorrent-wormhole-analysis-a-scale
- D. Abts et al., „Achieving Predictable Performance through Better Memory Controller Placement in Many-Core CMPs", ISCA 2009 (diamond placement)
