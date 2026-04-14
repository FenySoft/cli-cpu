# CLI-CPU — Security Model and Threat Analysis

> English version: not yet available

> Version: 1.0

Ez a dokumentum a CLI-CPU **biztonsági modelljét** írja le: mit véd hardveresen, mit nem, milyen támadás-osztályokra immunis, milyen formális verifikáció lehetséges, és milyen tanúsítási útvonalakat céloz meg hosszú távon.

## Miért fontos most

Az AI korszakban a biztonság tájképe **gyökeresen** átalakult, és a hagyományos CPU-architektúrák (x86, ARM, RISC-V) **nincsenek felkészülve** rá:

1. **AI-generated kód mindenhol.** A Copilot, ChatGPT, Claude és a hasonló eszközök naponta milliárd sor kódot generálnak, aminek jelentős része sebezhető. A „trust the developer" modell megszűnt.
2. **Supply chain támadások.** Az `npm`, `PyPI`, `NuGet`, `crates.io` csomagok kompromittálva. A SolarWinds, log4j, xz-utils incidensek mutatták, hogy a szoftveres védelem nem elegendő.
3. **Autonomous AI agents.** Egy LLM-alapú agent önállóan hozhat döntéseket és hajthat végre műveleteket. Prompt injection-nel manipulálva valós kárt okozhat.
4. **Mikroarchitektúra-sebezhetőségek.** Spectre, Meltdown, L1TF, Rowhammer, Retbleed, Inception — a modern OoO CPU-k architekturális bugokkal tele vannak, amiket nem lehet szoftveresen javítani teljesítményvesztés nélkül.
5. **Post-quantum fenyegetés közelít.** 2030-ra új kriptográfiai algoritmusok kellenek, és hozzá új hardveres primitívek.

Ebben a környezetben a „biztonság = szoftveres absztrakció" paradigma megbukott. A CLI-CPU válasza: **biztonság = fizikai tulajdonság a szilíciumban**, amit sem szoftveres, sem firmware-szintű támadás nem tud megkerülni.

## Threat Model

### Amit védünk (in-scope)

- **Adatintegritás** — az egyik program nem írhat egy másik program memóriájába
- **Vezérlési folyamat integritása** — a program nem ugorhat tetszőleges címre (ROP/JOP védelem)
- **Típus-biztonság** — egy objektum nem értelmezhető újra más típusként
- **Metódus-kontraktok** — egy metódus csak a deklarált paraméterekkel hívható
- **Memóriakezelés helyessége** — nincs use-after-free, nincs double-free, nincs buffer overflow
- **Stack-biztonság** — stack overflow és underflow hardveresen ellenőrzött
- **Cross-core isolation** — egy core sérülése nem terjed a többire
- **Kód-integritás** — a futó kód nem módosítható futás közben (R/O CODE régió)

### Amit NEM védünk (out-of-scope — őszinte figyelmeztetés)

- **Fizikai támadás** — ha valaki hozzáfér a chiphez és dekapszulálja, a tartalom láthatóvá válik (FIB, probing támadások). Ez a „tamper resistance" feladata, ami egy külön tervezési réteg (pl. SEAL, mesh shielding), és a jelenlegi terv **nem** tartalmazza.
- **Oldalcsatornás támadások teljes körű védelme** — a power analysis, EM emission, thermal side-channel nem tárgya a mostani tervnek. A CLI-CPU egyszerűbb pipeline-ja ezeket **nehezebbé teszi**, de nem lehetetlenné.
- **Fault injection** — laser/glitch támadások ellen a tamper-resistance tervezési réteg szükséges.
- **Denial of Service** — egy rosszindulatú core telesprayelheti a mailboxokat, ami a rendszert lelassítja. A rate limiting a szoftveres runtime (Neuron OS) feladata.
- **Üzleti logika hibák** — ha a C# kód maga rosszul ellenőrzi az engedélyeket, azt a hardver nem tudja javítani. A „secure by design" szoftverfejlesztés felelőssége marad.
- **Kvantum-támadások** — a jelenlegi terv nem tartalmaz post-quantum crypto primitíveket; ez F7 utáni kiegészítés.

### A támadó feltételezett képességei

A biztonsági modell feltételezi, hogy a támadó:
- **Képes rosszindulatú CIL kódot futtatni** a chipen (a felhasználó szintjén)
- **Képes tetszőleges bemeneti üzenetet** küldeni a mailboxra
- **NEM férkőzött** hozzá a chiphez fizikailag
- **NEM tudja** módosítani a firmware-t / mikrokódot (ezt a secure boot védi)
- **NEM tudja** módosítani a gyártási GDS-t (ez supply chain audit kérdés)

## Architekturális garanciák

### 1. Hardveres memória-biztonság (memory safety)

Minden memória-hozzáférés **hardveresen** ellenőrzött:

| Ellenőrzés | Hol történik | Trap |
|-----------|--------------|------|
| Stack overflow | Minden push | `STACK_OVERFLOW` |
| Stack underflow | Minden pop | `STACK_UNDERFLOW` |
| Lokális változó index ≥ count | `ldloc`, `stloc` | `INVALID_LOCAL` |
| Argumentum index ≥ count | `ldarg`, `starg` | `INVALID_ARG` |
| Branch target kódrégión kívül | `br*` | `INVALID_BRANCH_TARGET` |
| Call RVA kódrégión kívül | `call` | `INVALID_CALL_TARGET` |
| Div by zero | `div`, `rem` | `DIV_BY_ZERO` |
| Array bounds (F5+) | `ldelem`, `stelem` | `ARRAY_INDEX_OUT_OF_RANGE` |
| Null dereference (F5+) | `ldfld`, `stfld`, `callvirt` | `NULL_REFERENCE` |
| Type check failure (F5+) | `castclass`, `isinst` | `INVALID_CAST` |

**Következmény:** **a buffer overflow osztály támadásai (CWE-119, CWE-120, CWE-121, CWE-122) architektúra-szinten kizárva**. Nem szoftveres mitigation, hanem a hardver fizikailag nem tud nem-engedélyezett hozzáférést végrehajtani.

### 2. Típus-biztonság (type safety)

A CIL ECMA-335 megkövetel egy **verifiable code** fogalmat, ami type-safe. A CLI-CPU ezt a hardverben kényszeríti ki:

- Minden stack slot **implicit típusjelzést** hordoz (F5+)
- `castclass` és `isinst` a runtime metaadat alapján hardveresen jár végig a típus-hierarchián
- Egy `int32`-t **nem lehet** `object`-ként értelmezni, sem fordítva
- Nincs pointer-cast, nincs `reinterpret_cast<T*>`

**Következmény:** **a type confusion támadások** (CWE-843, amely az egyik leggyakoribb kritikus böngésző-sebezhetőség) **kizárva**.

### 3. Vezérlési folyamat integritása (Control Flow Integrity, CFI)

A hagyományos CPU-kon a CFI szoftveres védelem (Clang CFI, Intel CET, ARM PAC), ami **kiegészítő**, és **megkerülhető**. A CLI-CPU-n a CFI **nem opcionális**, hanem az ISA része:

- **Call target verification:** minden `call` és `callvirt` opkód olyan címet vesz, ami **a CIL metaadat szerint metódus-belépési pont**. Tetszőleges cím nem ugorható.
- **Return target verification:** a `ret` egy **frame pointer-szerkezetből** vett címre ugrik, amit hardveres frame setup tett oda. ROP gadget-láncolás nem lehetséges, mert a stack-en tárolt visszatérési cím **külön memóriaterületen** van, nem a user stack-en.
- **Branch target verification:** minden feltétlen és feltételes branch cél a **jelenlegi metódus kódtartományán belül** kell legyen. Metódusközi ugrás csak `call`/`ret` lehet.

**Következmény:** **ROP (Return-Oriented Programming) és JOP (Jump-Oriented Programming) támadások kizárva.** Nem nehezebbé téve — **fizikailag lehetetlen**. Ez önmagában ~30–40% a publikált kernel-exploiteknek.

### 4. Shared-nothing isolation

A multi-core CLI-CPU-n (F4+) **nincs megosztott memória** a core-ok között. Minden core saját privát SRAM-ban dolgozik, és a core-ok **kizárólag** a mailbox FIFO-kon keresztül kommunikálnak.

**Következmény:**
- **Cross-core side-channel** (mint a Foreshadow, L1TF, Fallout) **kizárva** — nincs shared cache, nincs shared TLB
- **False sharing covert channel kizárva** — nincs közös cache line
- **Rowhammer cross-process** — nehezebb, mert a core-ok SRAM-ja lokális, nem DRAM
- Egy kompromittált core **nem** tud memórián keresztül beszélni egy másik core-ral; csak a router által engedélyezett mailbox üzenetekkel, amiket naplózni lehet

### 5. Kód-adat szeparáció (Harvard architecture)

A CODE régió a chipen **külön címtartományban** van, mint a DATA/STACK régiók, és fizikailag külön QSPI flash-en érhető el, ami **csak olvasható** hardveresen. A kódot futás közben **nem lehet módosítani**.

**Következmény:**
- **Nincs shellcode injection** — nem lehet bájtokat írni a CODE régióba
- **Nincs JIT spraying** — **mert nincs JIT**. A CLI-CPU egyik legerősebb biztonsági érve: a CIL natívan fut, nincs JIT compiler, ami sebezhető lenne (Firefox, Chrome, Safari JIT-jét évente kihasználják).
- **Nincs self-modifying code** — sem hibásan, sem szándékosan

### 6. Speculative execution hiánya

A CLI-CPU in-order, nem-speculative pipeline. **Nincs branch prediction bypass, nincs out-of-order execution** (legalábbis az F6-ig).

**Következmény:** **Spectre v1, v2, v4, Meltdown, L1TF, MDS, Inception — a teljes spekulatív támadás-család kizárva.** Ez azért nagy szám, mert a modern CPU-kon **minden évben** új variáns jön ki, és a javítás minden alkalommal 5–30% teljesítményvesztéssel jár.

## Támadás-immunitási táblázat

| Támadás-osztály | CWE | Hagyományos CPU | CLI-CPU |
|----------------|-----|-----------------|---------|
| Buffer overflow | CWE-119/120/121/122 | Sebezhető | **Kizárva** (hardveres bounds check) |
| Use-after-free | CWE-416 | Sebezhető | **Kizárva** (GC hardveresen) |
| Double-free | CWE-415 | Sebezhető | **Kizárva** (GC hardveresen) |
| Null dereference | CWE-476 | DoS potenciál | **Trap-el** (hardveres null check) |
| Type confusion | CWE-843 | Sebezhető | **Kizárva** (isinst/castclass hardveresen) |
| Integer overflow → buffer overflow | CWE-190 | Sebezhető | **Részben véd** (overflow trap opcionális) |
| Format string | CWE-134 | Sebezhető | **Kizárva** (nincs printf, nincs C string) |
| Stack overflow (nem-bounded recursion) | CWE-674 | Stack smashing | **Hardveres trap** |
| **ROP (return-oriented programming)** | CWE-121 | Fő támadási felület | **Kizárva** (CFI az ISA-ban) |
| **JOP (jump-oriented programming)** | — | Sebezhető | **Kizárva** (branch target verification) |
| Shellcode injection | CWE-94 | Sebezhető | **Kizárva** (CODE R/O hardveresen) |
| JIT spraying | — | Minden JIT-es runtime | **Kizárva** (nincs JIT) |
| **Spectre v1/v2/v4** | CWE-1037 | Sebezhető | **Kizárva** (nincs spekuláció) |
| **Meltdown** | CWE-1037 | Sebezhető | **Kizárva** (nincs spekuláció) |
| **Rowhammer** | CWE-1247 | Sebezhető | **Nehéz** (per-core SRAM, determinisztikus) |
| Cache timing side-channel | CWE-208 | Sebezhető | **Nehéz** (shared-nothing, kevesebb shared cache) |
| Branch predictor side-channel | CWE-1037 | Sebezhető | **Kizárva** (nincs branch predictor) |
| Foreshadow / L1TF | CWE-1037 | Sebezhető | **Kizárva** |
| Cross-core MDS | CWE-1037 | Sebezhető | **Kizárva** (shared-nothing) |
| Race condition a GC-ben | CWE-362 | Sebezhető | **Kizárva** (per-core privát heap, nincs globális GC) |
| Deadlock (lock contention) | CWE-833 | Sebezhető | **Kizárva** (nincs shared lock, csak mailbox) |
| False sharing covert channel | — | Sebezhető | **Kizárva** (nincs shared cache) |
| Supply chain at hardware level | — | Ellenőrizhetetlen | **Ellenőrizhető** (nyílt HDL, reprodukálható build) |

**Ezek után érthető, miért erősebb a CLI-CPU biztonsági profilja, mint bármely létező kereskedelmi CPU-é.** Nem néhány extra réteget adunk, hanem az architektúra alapja eleve **nem engedélyezi** ezeket a támadásokat.

## Formális verifikáció

### Mit jelent

A formális verifikáció **matematikai bizonyítása** annak, hogy egy rendszer megfelel a specifikációjának. Nem tesztelés (ami csak néhány esetet ellenőriz), hanem **minden lehetséges végrehajtás** bizonyítása.

### Miért lehetséges a CLI-CPU-n

A formális verifikáció **gyakorlatilag lehetetlen** a modern OoO x86/ARM magokon, mert:
- 15 000+ opkód variáns (x86)
- Több ezer mikroarchitektúra állapot
- Speculatív végrehajtás
- Változó cache állapotok

A **CLI-CPU Nano core** ezzel szemben:
- **48 opkód**
- **5-stage in-order pipeline**, egyszerű állapottal
- **Nincs spekuláció**
- **Stack-gép szemantika**, ami közvetlen matematikai modell
- **Shared-nothing** — a modellezés egyetlen core-ra szorítkozik

**Ez közvetlenül** a seL4 microkernel formális bizonyítás méretosztálya (~10 000 sor C kód), és **kisebb**, mint a CompCert formálisan bizonyított C fordító.

### Konkrét eszközök

| Eszköz | Használat | Példák |
|--------|-----------|--------|
| **Coq** | Interaktív tétel-bizonyító, mélység | seL4, CompCert, Certikos |
| **Isabelle/HOL** | Interaktív tétel-bizonyító | seL4 (másik fele) |
| **Lean 4** | Modern tétel-bizonyító, gyorsan növő közösség | Mathlib, terra-cotta projekt |
| **F\*** | Függő típusok + SMT, automatizáltabb | Project Everest (HTTPS stack) |
| **Dafny** | Microsoft, SMT-alapú | kisebb rendszerek |
| **TLA+** | Specifikáció + model checking | AWS, Azure kritikus rendszerek |
| **SMV / SPIN** | Model checking hardware-re | CPU verifikáció |

### A CLI-CPU formális verifikáció terve

**Három szinten** verifikálható:

1. **ISA specifikáció szintje (F3-ban kezdve)** — a 48 CIL-T0 opkód szemantikája formálisan leírva (pl. Lean 4-ben vagy Coq-ban). **Cél: minden opkódra precíz operacionális szemantika**, amit később a hardver és a szimulátor ellen ellenőrizhetünk.

2. **RTL szint (F5+ után)** — a hardveres implementáció (Verilog vagy Amaranth) **refinement bizonyítással** ellenőrzött az ISA spec ellen. **Cél: bizonyítani, hogy a hardver minden állapotban megfelel a specifikációnak.**

3. **C# szimulátor szint (F1-ben kezdve)** — a szimulátor **unit tesztekkel és QuickCheck-szerű property-based** teszteléssel ellenőrzött. **Nem formális bizonyítás**, de kiegészítő biztonság.

**Ütemterv:**

| Fázis | Formális verifikáció lépés |
|-------|----------------------------|
| F1 | C# szimulátor + property-based tesztek (FsCheck / xUnit.Theory) |
| F3 | **ISA specifikáció** formálisan leírva (Lean 4 vagy F\*), ~4–6 mérnökhónap |
| F5 | **Refinement bizonyítás** az RTL ellen az ISA-hoz képest — ez az **igazi** formális verifikáció, ~12–18 mérnökhónap |
| F6 | A bizonyítás **revíziója** a heterogén Nano+Rich architektúrára |
| F7 | **Külső audit** és publikáció, pre-assessment a tanúsításokhoz |

**Ez nem jelenti**, hogy F0-F4 alatt mindez készen van — csak hogy a lehetőség **nyitva marad**, és a tervezési döntések **nem zárják ki**.

## Tanúsítási útvonalak

A CLI-CPU biztonsági profilja **potenciálisan alkalmas** a következő ipari szabványokra, **ha** a formális verifikáció befejezett és a megfelelő szoftveres folyamatok (V-model, FMEDA, MTBF analízis) mellé állnak.

### IEC 61508 — Functional Safety

**Cél:** általános ipari funkcionális biztonság
**Szintek:** SIL-1 (legalacsonyabb) … SIL-4 (legmagasabb)
**Követelmények:**
- Determinisztikus végrehajtás ✓ (CLI-CPU az)
- Formal methods használata magasabb SIL-en ✓ (cél)
- FMEDA (Failure Mode Effects and Diagnostic Analysis) — szoftveres munka
- MTBF számítás — gyártási adatból
**Realisztikus cél:** SIL-3 F7 végén, SIL-4 egy későbbi iterációban

### ISO 26262 — Automotive Safety

**Cél:** autóipari funkcionális biztonság
**Szintek:** ASIL-A … ASIL-D
**Követelmények (ASIL-D):**
- Hardveres redundancia vagy self-test ✓ (heterogén Nano+Rich redundancia, plus a watchdog lehetőség)
- Determinisztikus válaszidők ✓
- Formális bizonyítás ajánlott
**Realisztikus cél:** ASIL-B tanúsítható F7-ben, ASIL-D egy külön iterációban

### DO-178C — Aviation Software

**Cél:** repülőgép-szoftver
**Szintek:** DAL-A (legszigorúbb) … DAL-E
**Követelmények (DAL-A):**
- Formális módszerek **kötelezően** használhatók DO-333 kiegészítéssel
- Modell-ellenőrzés
- Minden kódsor bizonyítottan helyes
**Realisztikus cél:** DAL-C F7-ben, DAL-A hosszú távon

### IEC 62304 — Medical Device Software

**Cél:** orvosi eszköz szoftver
**Szintek:** Class A (nincs sérülés) … Class C (halálos kockázat)
**Követelmények:**
- Kockázatelemzés
- Forráskód-audit
- Szoftverfejlesztési folyamat dokumentálva
**Realisztikus cél:** Class C **elérhető** egy CLI-CPU-alapú orvostechnikai eszközhöz, ha a szoftveres fejlesztői folyamat a Microsoft/Amazon/Apple szintű.

### Kapcsolódó szabványok

- **Common Criteria (ISO/IEC 15408)** — információbiztonsági tanúsítás, EAL-1 … EAL-7
- **FIPS 140-3** — kriptográfiai modulok (USA kormányzati)
- **CC EAL-5+** — Apple Secure Enclave-szint, **cél** a CLI-CPU-ra

## Kapcsolódó projektek — tanulandó és lehetséges partnerek

### CHERI (Cambridge Hardware Enhanced RISC Instructions)

**Legközelebbi rokon.** Cambridge Egyetem projekt, ami **capability-based security-t** ad hardveres szinten. A memóriára mutató „pointer"-ek kapszulázva vannak, nem lehet őket növelni, csökkenteni, felülírni. A **Morello** prototípus ARM-alapú és már fut.

**Miért érdekes nekünk:**
- A CLI-CPU filozófiája **párhuzamos**, de más úton éri el ugyanazt (type-safe CIL helyett capability pointer)
- A Cambridge csapat **formális verifikációt** csinál a CHERI-re
- **Lehetséges akadémiai partner**

### seL4 Microkernel

A világ első **formálisan bizonyított** OS kernele (~10 000 sor C, Coq + Isabelle). A UNSW (Ausztrália) csapata 15+ év munka alatt bizonyította, hogy a kernel **nincs bug**, és minden működési garancia érvényes.

**Miért érdekes nekünk:**
- Pontos precedens arra, hogy **egy egyszerű rendszer formálisan bizonyítható**
- A Nano core ISA-ja **kisebb**, mint a seL4
- **Lehetséges technikai partner** a formális verifikációhoz

### CompCert

Formálisan bizonyított C fordító (Coq-ban). Ha egy szoftver CompCert-tel fordul, akkor **matematikailag** biztos, hogy a gépi kód megfelel a C forrásnak.

**Miért érdekes nekünk:**
- Analóg cél: egy formálisan bizonyított **CIL → CLI-CPU bináris** fordító
- A mostani `cli-cpu-link` tool **hosszú távú célja** egy CompCert-szerű bizonyított változat

### Project Everest (Microsoft Research)

Formálisan verifikált **HTTPS/TLS stack** F\*-ban. Bizonyítottan helyes kriptográfia, parser, state machine.

**Miért érdekes nekünk:**
- A Microsoft a .NET ökoszisztéma mögött áll
- **Potenciális támogató** egy formálisan bizonyított .NET runtime hardveres implementációjának
- A jelenlegi nanoFramework (amire építünk) **Microsoft-támogatott**

## Felelősségi modell

A CLI-CPU **nem** ad abszolút biztonsági garanciát. A modellt három rétegben érdemes tisztán elválasztani:

### Hardver réteg (amit a CLI-CPU garantál)

- Minden CIL opkód a specifikáció szerint viselkedik
- Memory safety hardveresen kikényszerítve
- Type safety hardveresen
- Control flow integrity hardveresen
- Shared-nothing isolation
- Nincs spekulatív végrehajtás

### Firmware / Neuron OS réteg (a projekt felelőssége)

- Secure boot (aláírt firmware ellenőrzés)
- Core allocation integritás
- Message routing integritás
- Supervisory logic (Rich core-okon)
- Logging, monitoring, telemetria

### Alkalmazás réteg (a fejlesztő felelőssége)

- Üzleti logika helyessége
- Permission modell
- Input validáció
- Adat- és hitelesítéskezelés
- Biztonságos kommunikáció

**A CLI-CPU **az első réteget** garantálja abszolút módon.** A második réteg **tervezési felelősségünk**, de csak F6-F7 után válik valós termékké. A harmadik réteg **mindig** a felhasználó felelőssége marad.

## Mit jelent ez a projekt gyakorlati célja szempontjából

A biztonsági dimenzió **új piacokat** nyit, amelyek a jelenlegi Cognitive Fabric narratíva mellett párhuzamosan érvényesek:

| Piaci szegmens | Piac mérete (globális, 2030 becslés) | CLI-CPU alkalmazhatóság |
|----------------|--------------------------------------|-------------------------|
| **AI safety / watchdog** | ~$5–15B | **Magas** — kis formálisan verifikált chip kritikus AI mellé |
| **Critical infrastructure** | ~$50–100B | **Magas** — SIL-3/4 tanúsítás |
| **Automotive (ISO 26262)** | ~$60B | **Közepes–magas** — ASIL-B/C/D |
| **Aviation (DO-178C)** | ~$20B | **Közepes** — hosszú tanúsítási ciklus |
| **Medical devices** | ~$30B (embedded processor része) | **Magas** — Class C tanúsítható |
| **Secure enclaves (TEE)** | ~$10B | **Magas** — CHERI-szerű előny |
| **Post-quantum crypto accelerator** | ~$5B (új piac) | **Közepes** — jövőbeni |
| **Confidential computing** | ~$10B | **Magas** — shared-nothing természetes |
| **Blockchain validator** | ~$5B | **Közepes** — deterministic execution |
| **Zero-trust endpoints** | ~$15B | **Közepes–magas** |
| **Összesen** | **~$200–300B** | — |

**Ez nagyságrendekkel nagyobb**, mint a „CIL-natív IoT CPU" eredeti pozicionálása. És ez egy **valós, meglévő piac** — nem jövőbeli vízió.

## Kétpályás stratégia

Ezek fényében a CLI-CPU projektet érdemes **két párhuzamos narratívával** kommunikálni:

### Pálya 1: „Cognitive Fabric"
- **Célközönség:** AI kutatók, akadémiai intézmények, neurális hálóalapú startupok
- **Érv:** programozható kognitív szubsztrátum, sok egyszerű core, event-driven, .NET natív
- **Időzítés:** F4-től élő narratíva

### Pálya 2: „Trustworthy Silicon"
- **Célközönség:** regulated industries (automotive, aviation, medical, critical infra), defense, privacy-focused tech
- **Érv:** szilíciumban élő memory safety, formálisan verifikálható, audithatóság, támadás-immunitás
- **Időzítés:** F5-től, amikor a formális verifikáció tervei nyilvánosak

**Ugyanaz a hardver**, **két különböző piaci szegmens**. A cognitive fabric a hosszú távú vízió, a trustworthy silicon a rövid távú bevételi lehetőség.

---

## Következő lépések

1. **F1 szimulátor**: a property-based tesztek (pl. FsCheck a C#-hoz) már most beépülnek
2. **F3 Tiny Tapeout**: a bounds check, branch target validation, call target validation **mind benne van** a jelenlegi ISA spec-ben
3. **F3 után**: első külső biztonsági audit (egy barátságos CHERI-szerű közösségből)
4. **F5 körül**: formális ISA specifikáció kezdete (Lean 4 vagy F\* alapon)
5. **F6 után**: tanúsítási pre-assessment az IEC 61508-ra
6. **F7 mellett**: a Trustworthy Silicon narratíva aktív kommunikációja, regulated industry partnerek keresése

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
