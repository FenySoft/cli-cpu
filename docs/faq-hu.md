# CLI-CPU — Gyakori Kérdések (FAQ)

> English version: [faq-en.md](faq-en.md)

> Version: 1.0

Ez a dokumentum olyan koncepcionális kérdéseket gyűjt, amelyek a projekt megértéséhez szükségesek, de nem férnek bele a részletes spec dokumentumokba (`architecture-hu.md`, `ISA-CIL-T0-hu.md`, `security-hu.md`, `neuron-os-hu.md`, `secure-element-hu.md`).

A FAQ célja, hogy egy **új olvasó** (akár mérnök, akár befektető, akár érdeklődő) gyorsan elhelyezze magában a projekt pozícióját anélkül, hogy a teljes ~3500+ soros dokumentáción végig kellene rágnia magát.

## Tartalom

- [1. CLI vagy CIL — mi a helyes szóhasználat?](#1-cli-vagy-cil--mi-a-helyes-szóhasználat)
- [2. A CLI-t meg lehet valósítani hardveren?](#2-a-cli-t-meg-lehet-valósítani-hardveren)
- [3. Egy fizikai core több logikai aktort kiszolgálhat?](#3-egy-fizikai-core-több-logikai-aktort-kiszolgálhat)
- [4. Miért kötelező az F6-FPGA verifikáció a silicon tape-out előtt?](#4-miért-kötelező-az-f6-fpga-verifikáció-a-silicon-tape-out-előtt)
- [5. Hogyan érik el a modern CPU-k a magas teljesítményt?](#5-hogyan-érik-el-a-modern-cpu-k-a-magas-teljesítményt)
- [6. Mi a különbség a RISC-V, ARM, x86/x64 és CLI-CPU között?](#6-mi-a-különbség-a-risc-v-arm-x86x64-és-cli-cpu-között)
- [7. Hogyan alakulnak a feladat-ütemezési költségek?](#7-hogyan-alakulnak-a-feladat-ütemezési-költségek)
- [8. Hány CLI-CPU core fér egy AMD Zen 4 chip területére?](#8-hány-cli-cpu-core-fér-egy-amd-zen-4-chip-területére)
- [9. Mennyivel kevesebbet fogyaszt a CLI-CPU?](#9-mennyivel-kevesebbet-fogyaszt-a-cli-cpu)
- [10. Miért nem emeljük az órajelet magasabbra?](#10-miért-nem-emeljük-az-órajelet-magasabbra)

---

## 1. CLI vagy CIL — mi a helyes szóhasználat?

**Mindkettő helyes, de más dolgot jelentenek.** A két rövidítés testvér, nem szinonima.

### Definíciók (ECMA-335 szabvány szerint)

| Rövidítés | Teljes név | Jelentés |
|-----------|-----------|----------|
| **CLI** | **Common Language Infrastructure** | Az **egész futtatókörnyezeti szabvány** — típusrendszer (CTS), metaadat formátum, fájlformátum (PE/COFF assembly), verifikáció, GC modell, kivételkezelés, **és** a bájtkód nyelv. Ez a „minden, ami a .NET-et .NET-té teszi". |
| **CIL** | **Common Intermediate Language** | **Maga a bájtkód**, amire a C#/F#/VB.NET fordít. ~220 opkód, stack-alapú. Ez a CLI **egyik komponense**. Régi nevén MSIL (Microsoft IL). |

**Analógia:**
- **CLI** ≈ „a JVM" (az egész Java platform: runtime + classfile format + GC + bájtkód nyelv)
- **CIL** ≈ „a Java bytecode" (kizárólag a bájtkód nyelv a `.class` fájlokban)

### Hogyan használjuk a projektben

A `docs/` dokumentumok **következetesen** ezt a mintát követik:

**✅ `CLI` — amikor a teljes szabványra, a platformra vagy a projektre utalunk:**
- **`CLI-CPU`** (projekt név) — mert a processzor a **CLI egészét** implementálja (bájtkód + metaadat + típusrendszer + verifikáció)
- **„teljes CLI core"** — mert a Rich core az ECMA-335 **minden** aspektusát támogatja
- **„CLI szabvány"**, **„ECMA-335 CLI"** — a referencia szabvány neve

**✅ `CIL` — amikor konkrétan a bájtkódra vagy az opkódokra utalunk:**
- **`CIL-T0`** (az ISA neve) — mert ez a **CIL opkódok** egy 48 elemű subset-je
- **„CIL bájtkód"**, **„CIL opkódok"** — a végrehajtott utasítások
- **„CIL bájtok közvetlenül a hardverbe"** — maga a bájtkód folyam

### Miért nem lehet felcserélni

Ezek **nem szinonimák**. Ha felcseréljük őket, a szöveg értelme megváltozik, vagy félrevezetővé válik:

- ❌ `"CIL-CPU"` — rossz, mert a processzor nem csak a bájtkódot, hanem a teljes CLI infrastruktúrát implementálja (pl. metaadat token feloldás, verifikáció, GC támogatás)
- ❌ `"CLI-T0 ISA"` — rossz, mert az ISA az **opkódok** halmaza, ezek CIL-ek, nem CLI-k
- ❌ `"CLI bájtkód"` — félreérthető, mert a CLI **nem** bájtkód, hanem az egész szabvány
- ❌ `"CIL szabvány"` — a szabvány (ECMA-335) a **CLI**-t definiálja, amiben benne van a CIL mint egyik komponens

### Rövid szabály

> **CLI = a platform / szabvány / projekt**  
> **CIL = a bájtkód / opkódok / ISA**
>
> Ha bájtokról, utasításokról, vagy ISA-ról beszélünk → **CIL**  
> Ha a teljes futtatókörnyezetről, szabványról, vagy magáról a processzorról → **CLI**

---

## 2. A CLI-t meg lehet valósítani hardveren?

**Rövid válasz:** a CLI **~95%-a hardverre + mikrokódra képezhető**. A maradék 5% (dynamic codegen, P/Invoke, reflection.emit) **szándékosan kimarad**, és ez a kimaradás **erény, nem hiány** — formális verifikálhatóságot, silicon-grade security-t, és ultra-alacsony fogyasztást ad cserébe.

Ez nem új kérdés: már kipróbálták (picoJava, Jazelle, Azul Vega). A CLI-CPU az ő tanulságaikra épít, és egy **konkrét, átgondolt választ ad** rá.

### A CLI komponensenként — mi mehet hardverbe?

Az ECMA-335 CLI szabvány hét fő réteget definiál. Nézzük egyenként a hardveres nehézséget és a projekt válaszát:

| CLI komponens | Hardveres nehézség | A CLI-CPU válasza |
|---------------|-------------------|-------------------|
| **CIL bájtkód** (~220 opkód) | 🟢 Könnyű | ~75% hardwired (1 ciklus), ~25% mikrokódolt — lásd `architecture-hu.md` „Hardwired vs mikrokódolt osztályozás" |
| **Stack VM** modell | 🟢 Nagyon könnyű | Stack cache (TOS regiszterekben), natív stack gép |
| **Integer aritmetika** | 🟢 Könnyű | Hardwired ALU |
| **Floating point** (R4/R8) | 🟡 Közepes | FPU **csak** a Rich core-on (F5-től) |
| **Memória biztonság** (bounds check, null check) | 🟢 Könnyű | Hardveres mellékhatás — minden load/store ellenőrzi |
| **Control Flow Integrity** | 🟢 Könnyű | Branch target validation hardveresen |
| **Objektum modell** (`newobj`, `ldfld`, `stfld`) | 🟡 Közepes | Rich core-on; Nano core-on nincs |
| **Virtuális hívás** (`callvirt`) | 🟡 Közepes | **vtable inline cache** (Rich core) |
| **Metaadat token feloldás** (`ldtoken`, stb.) | 🔴 Nehéz | **Metadata Walker koprocesszor** |
| **Garbage collection** | 🔴 Nagyon nehéz | **Bump allocator hardver** + **per-core privát heap** + **mikrokód GC szubrutin** |
| **Kivételkezelés** (try/catch/finally) | 🟡 Közepes | **Shadow register file** + mikrokód unwind |
| **Generikusok** (runtime type params) | 🔴 Nehéz | Rich core-on, metadata walker + per-típus specializáció |
| **String kezelés** | 🟡 Közepes | Rich core-on standard objektumként |
| **Dinamikus kódbetöltés** | ❌ Kizárva | Statikus `.t0` / `.tr` binárisok, build-time linkelés |
| **Reflection.Emit** (futásidejű kódgen) | ❌ Kizárva | Helyette **Roslyn source generator** build-time |
| **P/Invoke** (natív interop) | ❌ Kizárva | **Nincs natív világ** — minden CIL, nincs mihez invokálni |

### A hat kulcs-döntés, amik lehetővé teszik

A `docs/architecture-hu.md` hat konkrét architekturális döntést tartalmaz, amelyek együtt lehetővé teszik a CLI hardveres implementációját:

#### 1. Hibrid dekódolás (75/25 arány)

A gyakori, egyszerű opkódokat (`ldc.i4`, `add`, `ldloc`, `stloc`, `br`) **közvetlen hardver** végzi 1 ciklus alatt. A ritka, komplex opkódokat (`newobj`, `castclass`, `isinst`, `callvirt`) **mikrokód ROM-ból** trap-eli a dekóder, és egy mikrokód szekvencia futtatja le őket.

**Ez a picoJava tanulsága:** nem éri meg minden 220 opkódot szilíciumba önteni. A forró 48-ra optimalizálj, a maradékot mikrokóddal.

#### 2. Shared-nothing modell → nincs globális GC

A CLI klasszikus implementációjának legnagyobb fejfájása a **stop-the-world GC** egy megosztott heap-en. A CLI-CPU ezt **teljesen kikerüli**:

> „Minden core-nak saját 16 KB SRAM-ja van... (F5-től) saját objektum heap-je" (`architecture-hu.md`)

Ez azt jelenti:
- **Nincs globális GC koordináció** → nincs stop-the-world
- **Nincs MESI / cache coherency** → nincs cross-core szinkronizáció
- **Minden GC egy-core lokális** → egyszerű mark/sweep mikrokódban
- **Nincs lock contention** a heap-en

**Ez a CLI-CPU egyik legerősebb innovációja a „CLI hardveren" kérdésben.** A hagyományos .NET-ben ez óriási komplexitás; itt egyszerűen nem létezik a probléma.

#### 3. Bump allocator hardveresen + write barrier hardveresen

A `newobj` leglényege ~5-8 ciklusban lezajlik:

```
TOS_SIZE  ← objektum_méret
NEW_ADDR  ← HEAP_TOP
HEAP_TOP  ← HEAP_TOP + TOS_SIZE
if HEAP_TOP > HEAP_LIMIT → TRAP #GC
```

A write barrier (`stfld`/`stelem.ref` reference típusra) a **kártyatáblát** frissíti, szintén hardveresen. A tényleges GC (mark/sweep) **csak trap esetén** fut mikrokódban.

Ez **Azul Vega-szerű** megközelítés, csak nyílt forrású.

#### 4. Metadata Walker koprocesszor

A CIL a legtöbb összetett opkódnál **metaadat tokeneket** használ (pl. `newobj 0x06000042`). Ezeket szoftveres JIT szokta feloldani táblakeresés alapján. A CLI-CPU-ban a Metadata Walker egy **dedikált koprocesszor**, ami:
- Párhuzamosan fut a fő pipeline-nal
- Külön power domain-ben él (alszik, ha nincs feloldás)
- A PE/COFF metaadat táblákat közvetlenül olvassa

Ez egy **tipikus hardveres assist pattern** — nem a fő pipeline, hanem egy külön egység végzi a nehéz melót.

#### 5. Shadow register file a kivételekhez

A CLI kivételkezelés (`try`/`catch`/`finally`) a hagyományos processzorokon **stack unwind tábla stepping**-gel történik, lassan. A CLI-CPU:

- `try` belépéskor a mikrokód **egy ciklus alatt** átmásolja a TOS cache-t + SP + BP + PC-t egy **shadow register file-ba**
- `throw` esetén a mikrokód a shadow file-ból helyreállítja az állapotot, és a metódus kivétel-tábláját átfutva megkeresi a handler-t

**Drámaian gyorsabb**, és hardveresen megvalósítható, mert a shadow file egy egyszerű SRAM.

#### 6. Writable microcode (F6-tól)

Az F6 tape-outban lesz egy **írható mikrokód SRAM** (`roadmap-hu.md`):

> „Writable microcode SRAM — firmware-ből frissíthető opkód viselkedés"

Ez azt jelenti, hogy ha később kiderül egy ECMA-335 sarok-eset, amit rosszul implementáltunk, **nem kell új chipet gyártani** — csak egy firmware frissítést töltünk a mikrokód SRAM-ba. **Ez a Transmeta-inspiráció** (Crusoe/Efficeon) az egyik legfontosabb mintája.

### Mit NEM tesz a CLI-CPU (és miért jó, hogy nem teszi)

Ezek a CLI funkciók **szándékosan kimaradnak**, és ez **erény**, nem hiány:

#### ❌ Reflection.Emit (dinamikus kódgenerálás)

A hagyományos .NET-ben `Reflection.Emit`-tel futásidőben **új IL-t generálhatunk és futtathatunk**. Ez:
- Szükséges a szoftveres JIT-hez (`System.Linq.Expressions`, `ExpressionTree.Compile()`)
- Egy **óriási biztonsági lyuk** (JIT spraying támadások)
- Hardveresen **gyakorlatilag megvalósíthatatlan** (önmódosító kód, D-cache ↔ I-cache koherencia)

A projekt helyette **Roslyn source generator**-t használ build-time. Ez illik a nyílt forrás filozófiához (a kód **publikált**, nem runtime generált), és **immunis a JIT spraying-re**.

#### ❌ P/Invoke (natív interop)

A .NET-ben a `DllImport`-tal C vagy Win32 kódot hívhatunk. A CLI-CPU-n **nincs natív kód** — **minden CIL**. Nincs mihez invokálni.

**Ez nem hiány:** egy Secure Element / safety-critical környezetben a P/Invoke pontosan az a **támadási felület**, amit **nem akarunk** engedni. Ha minden csak CIL, akkor minden **verifikálható** és **type-safe**.

#### ❌ AppDomains (runtime isolation)

A .NET-ben az AppDomain szoftveres izolációt ad. A CLI-CPU-n **nincs** — helyette **fizikai core isolation**. Minden aktor egy saját core-on fut, saját privát SRAM-mal. Ez **hardveres silicon-grade isolation**, sokkal erősebb, mint szoftveres sandbox.

#### Dynamic assembly loading — fázisonként eltérő

A .NET-ben futásidőben betölthetünk új DLL-eket. A CLI-CPU-n ez **core típusonként különbözik**:

- **Nano core (CIL-T0):** **Nem** — a binárisok **statikusan linkelt** `.t0` fájlok, a boot-loader tölti be egyszer. **Ez a formális verifikáció előfeltétele**: ha egyszer ellenőriztük a statikus képet, senki nem tudja futásidőben módosítani.
- **Rich core (F5+):** **Igen** — writable microcode SRAM és a Neuron OS hot code loading funkciója lehetővé teszi aktor szintű kódcserét futás közben, **leállás nélkül** (Erlang OTP-inspiráció). Minden dinamikusan betöltött kódnak át kell mennie **kötelező PQC aláírás-ellenőrzésen** a végrehajtás előtt. Felhasználási esetek: firmware frissítés, plugin betöltés, aktor migráció Nano → Rich, biztonsági patch zero downtime-mal.

#### ❌ Thread, async/await runtime

A C# `async/await` kulcsszavak **build-time állapotgép kompilációra** fordulnak (a Roslyn csinálja). Nincs „async runtime" a CLI-CPU-n — csak **egy aktor üzenet a mailbox-on**. Az async/await és a Task minta **természetesen leképződik** a mailbox-alapú üzenetre (részletek: `neuron-os-hu.md`).

### Történelmi tanulságok — mit csinál másképp a CLI-CPU

Négy komoly kísérlet volt már „bytecode CPU hardveren":

| Projekt | Év | Mit csinált | Miért bukott / sikerült |
|---------|-----|-------------|-------------------------|
| **Sun picoJava** | 1997 | Teljes JVM bájtkód hardveren | ❌ Egymagos sebességen próbált versenyezni a szoftveres JIT-tel. Elvesztette a Moore-törvény + JIT fejlődés miatt |
| **ARM Jazelle** | 2001 | Hardveres JVM mód az ARM-on | ❌ Trap-elt a komplex opkódoknál, hibrid volt, de a szoftveres JIT rá is elhúzott. 2011-ben eltávolították |
| **Azul Vega / Vega2** | 2005 | Custom Java processzor hardveres GC assist-tel | ✅ Siker — de drága, szűk piaci szegmens, csak high-frequency trading-nek |
| **JOP** (kutatási) | 2002– | Valós idejű Java FPGA-n | ✅ Akadémiai siker, korlátozott produkció |

**A CLI-CPU a Vega modelljét viszi tovább**, de **nyílt forrással** és **shared-nothing multi-core-ral**:

> „A CLI-CPU nem ismétli ezt a hibát. Nem egymagos sebességben akar versenyezni a modern OoO CPU-kkal — az lehetetlen. Ehelyett más dimenzióban pozicionál." (`README.md`)

A `docs/architecture-hu.md` „Stratégiai pozicionálás: Cognitive Fabric" szekciója szerint a CLI-CPU **nem a hagyományos 1 mag = 1 szál versenyt játssza**, hanem **sok kis core + event-driven + shared-nothing** terepet. Ezen a terepen a hardveres CIL-implementáció **értelmes**, mert:

1. **A GC probléma eltűnik** (per-core heap)
2. **A szinkronizáció probléma eltűnik** (mailbox only)
3. **Az egymagos sebesség nem számít** (sok core párhuzamosan)
4. **Az egymag-per-feladat idle-ben van** (alacsony fogyasztás)
5. **A formális verifikáció lehetségessé válik** (nincs dinamikus kódgen)

### A legfontosabb mondat

> **A CLI NEM 100%-ban hardverre képezhető**, mert bizonyos funkciói (dynamic loading, reflection.emit, appdomain) inherenter futásidejűek.
>
> **A CLI ~95%-a viszont hardverre + mikrokódra képezhető**, ha:
> 1. Nem 1 mag = 1 szál modellt használunk (shared-nothing)
> 2. Megosztott heap helyett per-core privát heap-et (nincs globális GC)
> 3. Hibrid dekódolást (hardwired + microcode) használunk
> 4. Elfogadjuk, hogy a fennmaradó 5% (dynamic codegen, P/Invoke, reflection) **kimarad**
> 5. Cserébe **formális verifikáció**, **silicon-grade security**, és **ultra-alacsony fogyasztás** a jutalom

**A CLI-CPU pontosan ez az útvonal.** A `docs/architecture-hu.md` ezt világosan megfogalmazza, és a hét fázis (F0–F7) ennek a victory path-nak a lépéseit járja be:

- **F3 Tiny Tapeout:** a CIL-T0 48 opkód hardverben → bizonyíték, hogy működik
- **F4 Multi-core FPGA:** a shared-nothing modell → bizonyíték, hogy skálázódik
- **F5 Rich core:** a teljes CLI → bizonyíték, hogy kivitelezhető
- **F6-FPGA:** FPGA-verifikált elosztott heterogén fabric (3× A7-Lite 200T) → bizonyíték, hogy production-ready
- **F6-Silicon:** (csak FPGA-verifikáció után) valós szilícium → a kereskedelmi bizonyíték

---

## 3. Egy fizikai core több logikai aktort kiszolgálhat?

**Rövid válasz: igen, és ez nem opcionális optimalizáció, hanem a Neuron OS vízió alapvető része.** A fizikai core egy hardver erőforrás, a logikai aktor egy futtatási egység — a kettő aránya **dizájn-döntés**, nem fix 1:1 leképzés.

### A projekt saját dokumentációja explicit támogatja

A `docs/neuron-os-hu.md` négy különböző helyen is rögzíti a „több aktor egy core-on" modellt:

**Location transparency** (107. sor):
> „Egy aktor referencia **nem árulja el**, hogy a target **lokális (ugyanezen a core-on)**, másik core-on, vagy másik chipen van."

Ha az architektúra „1 core = 1 aktor" lenne, a lokális eset nem létezne.

**Zero-copy ugyanazon a core-on** (365. sor):
> „Ha egy aktor üzenetet küld egy másik aktoron belül **ugyanazon a core-on**, a runtime zero-copy módon továbbítja."

A runtime aktívan **észleli és optimalizálja** az eset, amikor két aktor ugyanazon a core-on él.

**Lokális üzenet mint latencia-kategória** (314. sor):
> „Lokális (ugyanazon a core-on, ugyanazon az aktoron belüli belső üzenetek) — ~1–3 ciklus, zero copy"

Ez egy konkrét performance-kategória a projekt üzenet-latencia modelljében.

**Aktor-migráció** (110. sor):
> „Az aktorok **futás közben áthelyezhetők** core-ok között (load balancing)"

Ez implikálja, hogy a core kapacitása elég több aktor hordozására — különben nem lenne mit áthelyezni.

### A kulcs: fizikai core ≠ logikai aktor

Ezt tisztán kell tartani, mert könnyű összekeverni:

| Fogalom | Mi az | Hány lehet |
|---------|-------|------------|
| **Fizikai core** | Hardveres végrehajtó egység (Nano vagy Rich) | F6-FPGA: ~26 Nano + 2 Rich (3× A7-200T) |
| **Logikai aktor** | Állapot + mailbox + viselkedés (CIL kód) | **Ezer vagy több** összesen |

A **fizikai core** egy **hardver erőforrás**. A **logikai aktor** egy **futtatási egység**, amit a runtime a core-ra ütemez.

### Hogyan működik a gyakorlatban

Egy fizikai core `privát SRAM`-jában **runtime + több aktor állapota** fér el:

```
┌────────────────────────────────┐
│      Physical Nano Core        │
│                                │
│  ┌──────────────────────────┐  │
│  │  Pipeline + stack cache  │  │
│  └──────────────────────────┘  │
│                                │
│  ┌──────────────────────────┐  │
│  │  Privát SRAM: 4 KB       │  │
│  │  ┌──────────────────┐    │  │
│  │  │ Aktor runtime    │    │  │
│  │  ├──────────────────┤    │  │
│  │  │ Aktor A állapot  │    │  │
│  │  │ Aktor B állapot  │    │  │
│  │  │ Aktor C állapot  │    │  │
│  │  │ ... (N aktor)    │    │  │
│  │  └──────────────────┘    │  │
│  └──────────────────────────┘  │
│                                │
│  ┌──────────────────────────┐  │
│  │  Hardver mailbox FIFO    │  │
│  │  (8 mély inbox/outbox)   │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

Az üzenet-feldolgozás lépései:

1. **Hardver** → a mailbox FIFO-ba betölt egy üzenetet
2. **Runtime** → kiolvassa, megnézi a címzett aktor ID-ját
3. **Runtime** → megkeresi a helyi aktor táblában (privát SRAM-ban)
4. **Runtime** → átkapcsol annak az aktornak az állapotára, végrehajtja az üzenet-kezelőt
5. **Aktor** → visszatér, a runtime várja a következő üzenetet (akár másik aktornak)

Ez pont olyan, mint az **Akka.NET / Erlang runtime**, csak **hardveres mailbox és privát SRAM** támogatással — **kooperatív multitasking**, ahol a scheduler nem szakítja félbe az üzenet-feldolgozást (`neuron-os-hu.md` 278. sor).

### Hány aktor fér egy core-on?

A kemény korlát a privát SRAM mérete. A runtime maga ~2–3 KB (Nano) vagy ~10–20 KB (Rich), a maradék aktoroknak jut:

**Nano core (4 KB privát SRAM):**
- Nagyon kis aktor (~50–100 byte) → **~10–20 aktor**
- Átlagos aktor (~500 byte) → **~2–3 aktor**
- Nagy állapotú aktor (~2 KB) → **~1 aktor**

**Rich core (64–256 KB privát SRAM + heap):**
- Egyszerű aktor (~200–500 byte) → **~100–500 aktor**
- Komplex aktor objektumokkal (~5–10 KB) → **~10–50 aktor**

**F6-FPGA teljes kapacitás (~26 Nano + 2 Rich, 3× A7-200T multi-board):**
- Átlagos workload: **~1200–4000 logikai aktor** egyidejűleg
- Kis aktorokra optimalizálva: **akár 8000+**

**F6-Silicon (opcionális felskálázás 32 Nano + 2 Rich):**
- Átlagos workload: **~1500–5000 logikai aktor** egyidejűleg
- Kis aktorokra optimalizálva: **akár 10 000+**

### Mikor érdemes „1 core = 1 aktor" modellt használni?

Van amikor szándékosan dedikált core-t kap egy aktor:

- **Kritikus timing** — real-time vezérlés, forró hálózati útvonal, audio pipeline
- **Isolation** — biztonsági domain (pl. kripto kulcs kezelés a Secure Element-ben)
- **Performance worker** — SNN neuron, ahol a deterministikus time-step számít
- **Fault isolation** — egy supervisor-fa levele, amelyet lehet restart-olni a többi befolyásolása nélkül

### Mikor érdemes „1 core = sok aktor" modellt használni?

- **Nagy aktor populáció** — ezer vagy több aktor (pl. webszerver: 1 kérés = 1 aktor, `neuron-os-hu.md` 434. sor)
- **Hot/cold workload** — sok aktor, de csak kevés aktív egyidejűleg (pl. session handler)
- **Supervisor fa belső csomópontjai** — ritkán dolgoznak, dedikált core pazarló lenne
- **Kernel aktorok együtt** — `root_supervisor` + `scheduler` + `router` osztoznak egy Rich core-on

### A teljes kép — heterogén leképzés

A Neuron OS **rugalmas N:M aktor-core leképzést** használ:

```
┌─── Rich core 0 ──────────────────┐
│ • root_supervisor                │  ← több "kernel aktor"
│ • scheduler                      │    egy core-on
│ • router                         │
└──────────────────────────────────┘

┌─── Rich core 1 ──────────────────┐
│ • http_server                    │  ← sok kis aktor
│ • 1000 × session aktor           │    egy core-on
└──────────────────────────────────┘

┌─── Nano core 5 ──────────────────┐
│ • network_packet_filter          │  ← egyetlen dedikált aktor
└──────────────────────────────────┘    egy core-on (forró út)

┌─── Nano core 12–43 ──────────────┐
│ • neuron_0 ... neuron_31         │  ← egy-aktor-per-core
└──────────────────────────────────┘    (SNN worker)
```

Ugyanaz a chip, különböző aktor/core arányok az igényeknek megfelelően.

### F3 Tiny Tapeout — egy speciális eset

Vigyázz egy potenciális ellentmondással: a `docs/roadmap-hu.md` **F3 Tiny Tapeout** verziója egyetlen core-on **egyetlen CIL program**ot futtat. Ez **nem** azt jelenti, hogy a core csak 1 aktort tud hordozni — F3-ban egyszerűen a Tiny Tapeout tile SRAM annyira kicsi, hogy nem érdemes runtime-ot tenni rá.

**A multi-aktor runtime F4-től jön be** (`neuron-os-hu.md` 617–624. sor), amikor már a `scheduler` + `router` valódi szerepet játszik, és F5-től természetes a több aktor egy core-on.

### A megkülönböztető pont más neuromorphic chipekkel szemben

Ez pont az, ami **megkülönbözteti a CLI-CPU-t** a hagyományos neuromorphic chipektől (Intel Loihi, IBM TrueNorth, BrainChip Akida): **nem rögzített 1 neuron = 1 compute unit** topológia, hanem **rugalmas N aktor × M core** leképzés egy runtime-on keresztül. A hardver biztosítja az izoláció és üzenet-továbbítás alapjait, a runtime pedig a logikai aktorok flexibilis elhelyezését.

---

## 4. Miért kötelező az F6-FPGA verifikáció a silicon tape-out előtt?

**Rövid válasz:** mert **nincs silicon tape-out olyan design-nal, ami nem futott FPGA-n**. 3 darab MicroPhase A7-Lite XC7A200T (134K LUT/db, Gigabit Ethernet hálóban, ~€960 összesen) elegendő a heterogén Cognitive Fabric (2 Rich + 26 Nano elosztva) teljes verifikálásához — és **reálisabb teszt**, mert a valódi Cognitive Fabric is multi-chip. Az F6-FPGA **kötelező előfeltétele** az F6-Silicon-nak.

### Miért ez a sorrend

Egy silicon tape-out ~$10k és 4–6 hónap. Ha a design-ban bug van, az pénz és idő kidobva. Az FPGA-verifikáció **ugyanazt az RTL-t** futtatja valós hardveren, de:

| Szempont | F6-Silicon | **F6-FPGA (kötelező előtte)** |
|----------|-----------|-------------------------------|
| **Költség** | ~$10 000 | **~€960 (3 board)** |
| **Build idő** | 4–6 hónap | **órák** (rebuild) |
| **Hibák költsége** | Egy bug → ~$10k + 6 hó | Egy bug → **azonnal javítható** |
| **Iterálhatóság** | Egyszeri tape-out | **Korlátlan** módosítás |
| **Reprodukálhatóság** | Egyedi MPW chip | **Bárki** újragyárthat ugyanazzal a hardverrel |
| **Sweet spot keresés** | Csak egyszer kipróbálható | **Többféle (Rich, Nano) konfiguráció** szisztematikusan |
| **Toolchain** | OpenLane2 (nyílt, érett) | OpenXC7 (nyílt, érett 7-series-en) |

### A platform: 3 × A7-Lite 200T multi-board háló

A fejlesztés **3 × MicroPhase A7-Lite XC7A200T** board-okkal történik (134K LUT/db, 512 MB DDR3, Gigabit Ethernet, ~€320/db). Vivado ML Standard (WebPACK) **ingyenesen** támogatja az Artix-7 családot (XC7A200T-ig).

**Egyetlen board** (134K LUT, cél ≤85%):

| (Rich, Nano) | Becsült LUT | Kihasználás | Cél |
|--------------|-------------|-------------|-----|
| (0, 20) | ~115K | 86% | Tiszta Nano fabric (SNN max) |
| (1, 14) | ~105K | 78% | „1 supervisor + sok worker" |
| **(2, 8)** | **~105K** | **78%** | **Heterogén sweet spot** |
| (2, 10) | ~115K | 86% | Heterogén max |

**3 board Ethernet hálóban** (3 × 134K = 402K LUT aggregált):

| Konfiguráció | Összesen | Cél |
|-------------|---------|-----|
| (2,6) + (0,10) + (0,10) | **2R + 26N** | **F6 elosztott Cognitive Fabric** |
| (1,8) + (1,8) + (0,10) | 2R + 26N | Szimmetrikus supervisor |

A multi-board konfiguráció **reálisabb teszt**, mert a valódi Cognitive Fabric is multi-chip — a location transparency és az inter-chip mailbox bridge **csak így tesztelhető**. Opcionálisan Kintex-7 K325T, ha megfelelő board elérhetővé válik.

### A hardver konkrétan

- **F4–F6 platform:** 3 × MicroPhase A7-Lite XC7A200T (~€320/db) — Gigabit Ethernet hálóban
- **Összesen: ~€960** (~$1030) a teljes F4–F6 FPGA hardver — az F4–F5 board-ok újrahasznosítva

### Mit nem ad az FPGA

- **Power efficiency mérés** — az FPGA fogyasztása ~10–20× rosszabb, mint Sky130 silicon. Az event-driven energia-spórolás csak silicon-on bizonyítható valós számokkal.
- **Órajel maximum** — FPGA-n ~100–200 MHz, silicon-on ~300–600 MHz lehetséges ugyanarra az RTL-re.
- **F6.5 Secure Edition** — a Crypto Actor, TRNG, PUF, tamper detection silicon-specifikus hardvert igényel, ezért az F6.5 az **F6-Silicon**-ra épít.

### Az F6-Silicon — csak FPGA-verifikáció után

Az F6-Silicon **kizárólag akkor indulhat**, ha az F6-FPGA **minden kész kritériuma teljesül**, és legalább egy a következőkből igaz:

1. A projekt **finanszírozást vagy ipari partnert** kapott a tape-out fedezésére
2. A **kereskedelmi termék útvonal** (F6.5 Secure Edition, F7 demo hardver) **silicon-előfeltétel**
3. A **valós energia hatékonyság** és **>500 MHz órajel** mérése **kritikus** a következő mérföldkőhöz

A silicon target az FPGA multi-board hálón verifikált konfigurációra épül (2R + 26N elosztva 3 chipen → egyetlen silicon chipre). Az ASIC-on a core-ok kisebbek (std cell vs FPGA LUT), így a multi-board-on verifikált konfiguráció **egyetlen chipre elfér**, és opcionálisan felskálázható — de csak a verifikált router topológia egyenes kiterjesztéseként.

**Részletek:** [`docs/roadmap-hu.md`](roadmap-hu.md) F6 szekció és „Három kulcs pivot" szakasz.

---

## 5. Hogyan érik el a modern CPU-k a magas teljesítményt?

**Rövid válasz:** Három egymásra épülő technikával: **pipeline** (átlapolás), **szuperszkaláris végrehajtás** (több pipeline párhuzamosan), és **out-of-order végrehajtás** (sorrenden kívüli feldolgozás). A CLI-CPU tudatosan egyiket sem használja — más úton keres teljesítményt.

### 5.1 Pipeline — az alap (1985, MIPS R2000)

Egyetlen utasítás végrehajtása 5 lépésből áll. A trükk: **nem egy utasítást gyorsítunk**, hanem **5 utasítást lapolunk át**:

```
Órajel:    1     2     3     4     5     6     7     8
         ┌─────┬─────┬─────┬─────┬─────┐
Instr 1: │ IF  │ ID  │ EX  │ MEM │ WB  │
         └─────┼─────┼─────┼─────┼─────┼─────┐
Instr 2:       │ IF  │ ID  │ EX  │ MEM │ WB  │
               └─────┼─────┼─────┼─────┼─────┼─────┐
Instr 3:             │ IF  │ ID  │ EX  │ MEM │ WB  │
                     └─────┴─────┴─────┴─────┴─────┘
```

| Fokozat | Mit csinál |
|---------|-----------|
| **IF** (Fetch) | Utasítás betöltése a memóriából |
| **ID** (Decode) | Dekódolás + regiszter olvasás |
| **EX** (Execute) | ALU művelet vagy cím számítás |
| **MEM** (Memory) | Load/store memória hozzáférés |
| **WB** (Write Back) | Eredmény visszaírása regiszterbe |

Egy utasítás **5 ciklust** vesz igénybe, de mivel 5 van egyszerre a csőben, a **throughput** mégis 1 utasítás/órajel.

**Miért működik ez RISC-nél?**
1. **Fix hosszúságú utasítás** (32 bit) → az IF pontosan tudja, hol a következő
2. **Load/Store architektúra** → csak `ld`/`st` nyúl memóriához, aritmetika regiszter-regiszter
3. **Egyszerű címzési módok** → nincs komplex `[base + index*scale + disp]`
4. **Sok regiszter** (32 db) → kevesebb memory spill

**Pipeline hazard-ok** (amikor nem 1 utasítás/órajel):
- **Data hazard** — egy utasítás a korábbi eredményére vár → **forwarding** (EX kimenet visszavezetése)
- **Control hazard** — branch utasítás: nem tudjuk hová ugrik → **branch prediction** (99%+ pontosság)
- **Structural hazard** — két fokozat ugyanazt az erőforrást akarja → **Harvard architektúra** (külön I/D memória)

### 5.2 Szuperszkaláris — több pipeline (1993, Pentium)

Miért csak 1 pipeline? Tegyünk be többet, és **egyszerre több utasítást** hajtsunk végre:

```
1-wide (klasszikus RISC, 1985):    1 utasítás / órajel

  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══

4-wide (szuperszkaláris, 2006):    4 utasítás / órajel

  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══
  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══
  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══
  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══

8-wide (Apple M4 P-core, 2024):   8 utasítás / órajel

  ═══[IF]═══[ID]═══[EX]═══[MEM]═══[WB]═══  × 8 + OoO
```

### 5.3 Out-of-Order (OoO) — sorrend felrúgása (1995, Pentium Pro)

A CPU **nem sorban** hajtja végre az utasításokat, hanem **amint az operandusok készen állnak**:

```asm
LDR  x1, [x0]        ; lassú memória olvasás (~100 clk)
ADD  x2, x3, x4      ; x1-re NEM vár → ALU-n MOST futhat!
MUL  x5, x1, x2      ; x1-re VÁR, de x2 már kész
SUB  x6, x7, x8      ; független → megelőzheti a MUL-t
```

A **Reorder Buffer (ROB)** biztosítja, hogy az eredmények mégis **program-sorrendben** legyenek commit-olva (architektúrális konzisztencia).

### 5.4 A három technika együtt — modern CPU profil

| | Klasszikus RISC (1985) | Apple M4 P-core (2024) | CLI-CPU Nano |
|---|---|---|---|
| Pipeline | 5-stage, in-order | 14+ stage, OoO | **3-stage, in-order** |
| Decode szélesség | 1-wide | 8-10-wide | **1-wide** |
| ROB | — | ~700+ entry | **—** |
| Végrehajtó egységek | 1 | ~15 | **1** |
| IPC (elmélet) | 1 | 8-10 | **~0.3-0.5** |
| IPC (valós) | ~0.8 | ~5-6 | **~0.3-0.5** |
| Tranzisztor / core | ~25K | ~300M | **~20-50K** |

**A CLI-CPU miért nem használja ezeket?**
1. **Terület** — OoO és szuperszkaláris ~1000× több tranzisztort igényel. Abból inkább ~1000 Nano core-t csinálunk.
2. **Determinizmus** — OoO és spekuláció Spectre-szerű oldalcsatornákat nyit. Event-driven és security workload-oknak determinisztikus végrehajtás kell.
3. **Energia** — OoO ROB és rename logika a fogyasztás ~30-40%-a. Alvó core-ok 0W-ot fogyasztanak.
4. **Filozófia** — a CLI-CPU nem az egymagos IPC-ben versenyez, hanem a **sok egyszerű mag közötti üzenetküldésben**.

### 5.5 Az x86/x64 speciális helyzete — CISC kívül, RISC belül

Az x86 egy 1978-as (8086) örökség: változó hosszúságú utasítások (1-15 byte), komplex címzési módok. A modern x86 CPU-k **belül RISC-re fordítják** az utasításokat:

```
┌─────────────────────────────────────────────────────────┐
│                    x86 FRONTEND                         │
│                                                         │
│  Fetch → Pre-decode → Decode → µop fordítás → µop Queue │
│          (hossz         (x86 utasítást RISC-szerű       │
│          megállapítás)   µop-okra bontja)               │
│                                                         │
│  ADD [RBX+RCX*4+0x10], RAX                              │
│    → µop₁: LEA  tmp, [addr]      (cím számítás)         │
│    → µop₂: LOAD tmp2, [tmp]      (memória olvasás)      │
│    → µop₃: ADD  tmp2, RAX        (összeadás)            │
│    → µop₄: STORE [tmp], tmp2     (memória visszaírás)   │
└─────────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    RISC BACKEND                         │
│  (pont ugyanaz, mint az ARM: OoO, szuperszkaláris)      │
│  Rename → ROB → Scheduler → Execute → Retire            │
└─────────────────────────────────────────────────────────┘
```

Az x86 lényegében egy **hardveres fordító** (frontend) + egy **RISC végrehajtó** (backend).

A **változó utasításhossz** drága: a pre-decode-nak ki kell találnia, hol kezdődik a következő utasítás, mielőtt dekódolná. Megoldás: **µop cache** (~4000-6000 entry) — forró ciklusokon a frontend költsége eltűnik.

| | ARM (AArch64) | x86/x64 |
|---|---|---|
| Utasítás hossz | Fix 4 byte | Változó 1-15 byte |
| Pre-decode | Nem kell (mindig PC+4) | Szükséges (drága!) |
| Decode | ARM → belső op (~1:1) | x86 → µop fordítás (komplex) |
| µop cache | Nem kell | ~4000-6000 entry |
| Backend | RISC OoO | RISC OoO (lényegében ugyanaz) |
| Frontend ára | Alacsony | ~15-20% extra tranzisztor és energia |

**Az x86 teljesítménye megközelíti az ARM-ot** (IPC ~5-6 mindkettőnél), de **magasabb órajelen és fogyasztáson** éri el. Az extra tranzisztorokat és energiát a frontend fordító eszi meg.

---

## 6. Mi a különbség a RISC-V, ARM, x86/x64 és CLI-CPU között?

**Rövid válasz:** Mindegyik más problémát old meg, és más kompromisszumot köt. Az x86 a kompatibilitásért, az ARM az energia-hatékonyságért, a RISC-V a nyíltságért, a CLI-CPU a **sok mag közötti üzenetküldés hatékonyságáért** optimalizál.

### Architekturális profil

| | x86/x64 | ARM (AArch64) | RISC-V | CLI-CPU Nano | CLI-CPU Rich |
|---|---|---|---|---|---|
| **Születés** | 1978 (8086) | 1985 (ARM1) | 2010 (Berkeley) | 2025 | 2025 (F5 cél) |
| **Filozófia** | CISC → belül RISC | RISC, pragmatikus | RISC, minimalista | Stack gép, actor fabric | Stack gép, teljes CIL |
| **Licenc** | Intel/AMD zárt | ARM Ltd. ~$1-5M | Nyílt (BSD) | Nyílt (MIT/Apache) | Nyílt (MIT/Apache) |
| **Utasítás hossz** | 1-15 byte | Fix 4 byte | 2 vagy 4 byte | 1-5 byte | 1-5 byte |
| **Regiszterek** | 16 GP + 32 SIMD | 31 GP + 32 NEON | 31 GP + 32 FP | **0** (stack) | **0** (stack + TOS cache) |
| **Operandus** | Regiszter + memória | Regiszter-regiszter | Regiszter-regiszter | **Stack (implicit)** | **Stack (implicit)** |
| **Pipeline** | 19+ stage, OoO | 11-14+ stage, OoO | 5-8 stage, in-order/OoO | **3 stage, in-order** | **5 stage, in-order** |
| **Std cell / core** | ~500M tr. | ~50-300M tr. | ~1-2M tr. | **~10K** | **~80K** |

### Ugyanaz a művelet (`c = a + b`) — négy ISA-n

```asm
x86/x64:                      ARM (AArch64):
  MOV  EAX, [a]                 LDR  W0, [X1]
  ADD  EAX, [b]   ← memóriából LDR  W2, [X3]    ← CSAK load/store
  MOV  [c], EAX     is tud!    ADD  W4, W0, W2     nyúl memóriához
                               STR  W4, [X5]

RISC-V:                        CLI-CPU (CIL-T0):
  LW   a0, 0(a1)                ldind.i4        ← stack[TOS] címről olvas
  LW   a2, 0(a3)                ldind.i4
  ADD  a4, a0, a2               add             ← pop 2, push(a+b)
  SW   a4, 0(a5)                stind.i4
```

**Regiszter gép** (x86, ARM, RISC-V): az utasítás **megmondja** melyik regisztert használja → hosszabb utasítások, de a fordító optimalizálhat.

**Stack gép** (CLI-CPU): az utasítás **mindig a stack tetejéről** dolgozik → rövidebb utasítások (1 byte!), de több utasítás kell.

### Utasítás kódolás összehasonlítás

```
x86/x64 — változó, komplex (történelmi rétegek):
┌────────┬────────┬────────┬─────────┬────────┬──────────┐
│ Prefix │  REX   │ Opcode │ ModR/M  │  SIB   │ Imm/Disp │
│ 0-4 B  │ 0-1 B  │ 1-3 B  │ 0-1 B   │ 0-1 B  │ 0-8 B    │  1-15 byte
└────────┴────────┴────────┴─────────┴────────┴──────────┘

ARM — fix, szabályos:
┌──────────┬───────┬───────┬───────┬───────────┐
│  Opcode  │  Rd   │  Rn   │  Rm   │  Imm      │  mindig 4 byte
└──────────┴───────┴───────┴───────┴───────────┘

RISC-V — fix, minimális:
┌──────────┬───────┬───────┬───────┬───────────┐
│  Opcode  │  rd   │  rs1  │  rs2  │  funct    │  4 byte (vagy 2B C ext.)
└──────────┴───────┴───────┴───────┴───────────┘

CLI-CPU — változó, de egyszerű:
┌──────────┬──────────────┐
│  Opcode  │  Operand     │
│  1-2 B   │  0-4 B       │  1-5 byte — nincs regiszter mező!
└──────────┴──────────────┘
```

### Kódsűrűség — Fibonacci(n)

| ISA | Utasítás szám | Kód méret (byte) |
|-----|--------------|-------------------|
| x86/x64 | ~12 | ~35 |
| ARM AArch64 | ~14 | 56 (fix 4B) |
| RISC-V (RV32I) | ~14 | 56 (fix 4B) |
| RISC-V (RV32IC) | ~14 | ~32 (compressed) |
| CIL-T0 | ~18 | ~22 |

A CIL-T0 **több utasítást** igényel, de **kevesebb byte-ot** — mert nincs regiszter mező az utasításokban.

### Multi-core modell — az igazi különbség

| | x86/ARM/RISC-V | CLI-CPU |
|---|---|---|
| **Kommunikáció** | Shared memory + cache koherencia | **Mailbox FIFO (shared-nothing)** |
| **Koherencia protokoll** | MOESI/MESIF (komplex, drága) | **Nincs (nem kell!)** |
| **Szinkronizáció** | Mutex, atomic CAS, memory barrier | **Üzenet küldés (lock-free)** |
| **Skálázás korlátja** | ~8-16 core után romlik (contention) | **1000+ core lineáris** |
| **Heterogén** | P+E core (Apple, Intel, ARM) | **Nano + Rich core** |

```
Hagyományos shared-memory:         CLI-CPU shared-nothing:

┌──────┬──────┬──────┬────┐       ┌────┐ ┌────┐ ┌────┐ ┌────┐
│Core 0│Core 1│Core 2│Core│       │Nano│→│Nano│→│Nano│→│Nano│
│ L1/L2│ L1/L2│ L1/L2│L1/2│       └──┬─┘ └──┬─┘ └──┬─┘ └──┬─┘
├──────┴──────┴──────┴────┤          │      │      │      │
│    Shared L3 Cache      │       ┌──┴──────┴──────┴──────┴──┐
│  (koherencia protokoll) │       │     Mailbox Router       │
└─────────────────────────┘       │  (nincs shared state!)   │
                                  └──────────────────────────┘
Bármelyik core bármelyik         Minden core CSAK üzenetet
memóriát látja → koherencia       küld → nincs koherencia
protokoll kell → DRÁGA            → OLCSÓ, lineárisan skálázik
```

### Mire jó melyik?

| Felhasználás | Legjobb | Miért |
|---|---|---|
| Desktop / laptop | x86, Apple M-series ARM | Magas IPC, ökoszisztéma |
| Szerver (felhő) | x86, ARM (Graviton) | Virtualizáció, kompatibilitás |
| Mobil | ARM | Energia-hatékonyság |
| Beágyazott (MCU) | RISC-V, ARM Cortex-M | Kis terület, olcsó |
| **Event-driven (IoT, routing)** | **CLI-CPU Nano** | Mailbox, sleep/wake, 0 overhead |
| **Actor rendszerek (Akka, Erlang)** | **CLI-CPU** | Hardveres natív üzenetküldés |
| **Spiking neural network** | **CLI-CPU Nano** | 1 core = 1 neuron |
| **Heterogén C# workload** | **CLI-CPU Rich + Nano** | Supervisor (Rich) + workerek (Nano) |

### Egy mondatban

- **x86** — 45 év kompatibilitás: mindent tud, de drágán (CISC kívül, RISC belül)
- **ARM** — pragmatikus RISC: jó IPC/watt, de licensz kell
- **RISC-V** — nyílt RISC: minimalista, ingyenes, de fiatal ökoszisztéma
- **CLI-CPU** — más dimenzió: nem egymagos sebességben versenyez, hanem a **sok egyszerű mag közötti üzenetküldésben**

---

## 7. Hogyan alakulnak a feladat-ütemezési költségek?

**Rövid válasz:** A kontextusváltás a CLI-CPU-n **3-4 nagyságrenddel** (1,000-20,000×) kevesebb órajelciklust igényel, mint a hagyományos architektúrákon — és ez **az architektúra tulajdonsága**, nem a gyártási technológiáé. Az összehasonlítás órajelciklusban történik, hogy a technológia-különbség ne torzítson.

### Fontos: a CLI-CPU-n VAN kontextusváltás

Az előző FAQ-kérdés (3. kérdés) rögzíti: a CLI-CPU **N:M aktor-core leképzést** használ, nem fix 1:1-et. Amikor több aktor osztozik egy core-on, kooperatív aktor-váltás történik üzenet-feldolgozási határokon. Három üzemód létezik:

| Mód | Mikor | Kontextusváltás költsége |
|---|---|---|
| **1:1** (dedikált) | SNN neuronok, real-time, latency-kritikus | 0 ciklus (nincs váltás) |
| **N:M** (kooperatív) | Webszerver, sok session, kernel aktorok | ~10-60 ciklus |
| **Migráció** (core→core) | Load balancing, Nano→Rich upgrade | ~100-500 ciklus |

### Kontextusváltás költsége — órajelciklusban (technológia-független)

| Költség-komponens | x86/x64 | Apple M4 P | Apple M4 E | ARM A720 | RISC-V U74 | CLI-CPU Nano | CLI-CPU Rich |
|---|---|---|---|---|---|---|---|
| Regiszter mentés/töltés | ~300-500 | ~150-250 | ~100-170 | ~100-200 | ~30-60 | **~1-2** | **~5-10** |
| TLB flush + refill | ~20K-180K | ~7K-55K | ~3K-22K | ~7K-40K | ~5K-15K | **0** | **~4-8** |
| Cache kihűlés | ~10K-110K | ~5K-70K | ~1.5K-14K | ~7K-50K | ~1.5K-15K | **0** | **0** |
| Pipeline refill | ~19-25 | ~14-18 | ~8-12 | ~11-15 | ~8-10 | **~3** | **~5** |
| Scheduler döntés | ~3K-11K | ~1.5K-5K | ~1K-3K | ~2K-7K | ~300-750 | **~2-5** | **~2-5** |
| **ÖSSZESEN** | **~33K-300K** | **~14K-130K** | **~5.5K-39K** | **~16K-97K** | **~7K-31K** | **~10-15** | **~30-60** |

### Miért ekkora a különbség?

A hagyományos architektúrák **általános célú** tervezése megköveteli az alábbi infrastruktúrát, amelyek mindegyike kontextusváltásnál büntetést jelent:

| Infrastruktúra | Hagyományos | CLI-CPU | Hatás |
|---|---|---|---|
| **Regiszter file** (16-31 × 64 bit + SIMD) | Menteni/tölteni kell | **Nincs** (stack gép) | ~300 clk megtakarítás |
| **Virtuális memória** (TLB + MMU) | TLB flush + page walk | **Nincs MMU**, fizikai cím | ~20K-180K clk megtakarítás |
| **Shared cache** (L1/L2/L3 hierarchia) | Cache kihűlés | **Privát SRAM**, soha nem hűl ki | ~10K-110K clk megtakarítás |
| **OS kernel scheduler** | Komplex algoritmus (CFS/XNU) | **HW FIFO poll** (~2-5 clk) | ~3K-11K clk megtakarítás |
| **Mély pipeline** (14-19+ stage) | Teljes pipeline flush | **3-5 stage** flush | ~15 clk megtakarítás |

A CLI-CPU ezeket az infrastruktúrákat **nem építi be**, mert a shared-nothing actor modell nem igényli. Ez nem hiányosság, hanem **tudatos design döntés**: az általános célú flexibilitást elcseréli az ütemezési hatékonyságra.

### Mi történik kontextusváltásnál — lépésről lépésre

**x86/x64 (OS scheduler, preemptív):**
```
1. Timer interrupt → kernel mode switch            ~5-10 clk
2. Scheduler döntés (CFS red-black tree walk)      ~3K-11K clk
3. XSAVE: 16 GP + 32 ZMM regiszter mentés → RAM   ~300-500 clk
4. CR3 write (page table váltás)                   ~20-30 clk
5. TLB flush (PCID partial flush)                  ~10-20 clk
   └→ Utána: ~200-800 TLB miss × ~100-200 clk     ~20K-160K clk
6. XRSTOR: új task regiszterei visszatöltés        ~300-500 clk
7. Pipeline refill (19+ stage)                     ~19-25 clk
8. L1/L2 cache kihűlés (cold miss-ek)             ~10K-100K clk
────────────────────────────────────────
ÖSSZESEN:                                          ~33K-300K clk
```

**Apple M4 P-core (OS scheduler, preemptív):**
```
1. Timer interrupt → EL1 switch                    ~3-5 clk
2. Scheduler döntés (XNU)                          ~1.5K-5K clk
3. 31 GP + 32 NEON regiszter mentés                ~150-250 clk
4. TTBR0 write (page table váltás)                 ~10-15 clk
5. TLB: ASID-alapú szelektív flush                 ~5-10 clk
   └→ Utána: ~100-400 TLB miss × ~60-130 clk      ~6K-52K clk
6. Regiszterek visszatöltés                        ~150-250 clk
7. Pipeline refill (14+ stage)                     ~14-18 clk
8. L1 cache kihűlés (128 KB L1D)                   ~5K-70K clk
────────────────────────────────────────
ÖSSZESEN:                                          ~14K-130K clk
```

**CLI-CPU Nano (kooperatív aktor váltás):**
```
1. Aktor A: ret (üzenet feldolgozás kész)          ~1 clk
2. Scheduler: inbox FIFO poll (hardveres)          ~2-5 clk
3. PC + SP mentés → SRAM (8 byte)                  ~1-2 clk
4. Új aktor PC + SP töltés ← SRAM                  ~1-2 clk
5. Pipeline refill (3 stage)                       ~3 clk
6. TLB flush: nincs MMU                            ~0
7. Cache kihűlés: nincs (privát SRAM)              ~0
────────────────────────────────────────
ÖSSZESEN:                                          ~10-15 clk
```

**CLI-CPU Rich (kooperatív aktor váltás):**
```
1. Aktor A: ret (üzenet feldolgozás kész)          ~1 clk
2. Scheduler: inbox FIFO poll (hardveres)          ~2-5 clk
3. PC + SP + TOS cache (8×32b) mentés              ~5-10 clk
4. Shadow register file mentés                     ~2-4 clk
5. GC state pointer váltás                         ~1 clk
6. Metadata TLB flush (vtable cache)               ~4-8 clk
7. Új aktor state töltés                           ~5-10 clk
8. Pipeline refill (5 stage)                       ~5 clk
9. Metadata TLB warmup (első callvirt)             ~10-20 clk
────────────────────────────────────────
ÖSSZESEN:                                          ~30-60 clk
```

### Multi-core szinkronizáció (ciklusban)

| Művelet | x86/x64 | M4 P | M4 E | ARM A720 | RISC-V | Nano | Rich |
|---|---|---|---|---|---|---|---|
| Mutex lock/unlock | ~200-1000 | ~100-500 | ~60-300 | ~150-700 | ~50-250 | **N/A** | **N/A** |
| Atomic CAS | ~50-300 | ~40-150 | ~25-100 | ~50-200 | ~20-70 | **N/A** | **N/A** |
| Cache line bounce | ~200-500 | ~100-250 | ~60-150 | ~150-300 | ~50-100 | **N/A** | **N/A** |
| **Üzenet küldés** | ~1K-3K (SW) | ~700-2K | ~500-1.5K | ~700-2K | ~200-500 | **~2-10** | **~2-10** |
| Lock contention (8+ core) | ~5K-60K | ~2K-25K | ~2K-15K | ~4K-40K | ~1K-10K | **0** | **0** |

A CLI-CPU-n **nincs mutex, nincs atomic, nincs cache bounce** — az üzenetküldés a hardveres mailbox FIFO-n keresztül megy, ~2-10 ciklus.

### Igazságos összehasonlítás: azonos gyártási technológián

Az eddigi összehasonlítás ciklusokban volt, ami technológia-független. De mi történne, ha a CLI-CPU-t **ugyanarra a csomópontra** vinnénk, mint a mai csúcs CPU-kat?

| Technológia | x86 órajel | M4 P órajel | Nano órajel (becsült) | Rich órajel (becsült) |
|---|---|---|---|---|
| Sky130 (130 nm) — F3 cél | — | — | 50-200 MHz | 50-150 MHz |
| TSMC 28nm | ~2-3 GHz | — | 500-1,000 MHz | 400-800 MHz |
| TSMC 7nm | ~4-5 GHz | — | 1.0-2.0 GHz | 0.8-1.5 GHz |
| **TSMC 3nm** | **5.7 GHz** | **4.5 GHz** | **2.0-4.0 GHz** | **1.5-3.0 GHz** |

A Nano core (3-stage in-order, ~10K std cell) **jól skálázik** órajelben, mert egyszerű. Egy komplex OoO core (19-stage, ~500M tranzisztor) nehezebben emeli a frekvenciát.

### Területre normalizált összehasonlítás — TSMC 3nm, azonos 12 mm²

| Core típus | Terület (3nm, becsült) | Hány fér 12 mm²-be |
|---|---|---|
| x86 Zen 5 core | ~8-12 mm² | ~1 |
| Apple M4 P-core | ~12 mm² | 1 (referencia) |
| Apple M4 E-core | ~2-3 mm² | ~4-6 |
| ARM Cortex-A720 | ~3-5 mm² | ~2-4 |
| RISC-V U74 | ~0.5-1 mm² | ~12-24 |
| **CLI-CPU Rich** | **~0.02-0.08 mm²** | **~150-600** |
| **CLI-CPU Nano** | **~0.002-0.01 mm²** | **~1,200-6,000** |

### Aggregált throughput — actor workload, azonos terület és technológia

10,000 független actor feladat: üzenet fogadás → ~100 utasítás feldolgozás → válasz.

| Architektúra | Core szám (12 mm²) | Órajel (3nm) | Ctx switch (clk) | **Throughput** |
|---|---|---|---|---|
| x86 Zen 5 | 1 | 5.7 GHz | ~166K | ~34K msg/s |
| M4 P-core | 1 | 4.5 GHz | ~72K | ~62K msg/s |
| M4 E-core | 5 | 2.8 GHz | ~22K | ~632K msg/s |
| ARM A720 | 3 | 3.3 GHz | ~56K | ~177K msg/s |
| RISC-V U74 | 18 | 1.5 GHz | ~19K | ~1.4M msg/s |
| **CLI-CPU Rich** | **300** | **2.0 GHz** | **~45** | **~41M msg/s** |
| **CLI-CPU Nano** | **3,000** | **3.0 GHz** | **~12** | **~80M msg/s** |

```
Aggregált actor throughput — log skála (azonos 12 mm², TSMC 3nm):

                   10K      100K       1M        10M       100M
                    │         │         │          │          │
  x86 (1 core):    ███                                          34K
  M4 P (1 core):   ████                                        62K
  ARM A720 (3):    ██████                                      177K
  M4 E (5 core):   █████████                                   632K
  RISC-V (18):     ███████████▌                                1.4M
  Rich (300):      ██████████████████████████████▌               41M
  Nano (3,000):    ████████████████████████████████▌             80M
                    │         │         │          │          │
                   10K      100K       1M        10M       100M

  Log skála: minden █ ≈ 2× szorzó. A Nano ~2,350× az x86 felett.
```

A CLI-CPU **~1,000-2,000× magasabb throughput-ot** ad azonos szilícium területen, actor workload-on.

### Energia-hatékonyság

| | Fogyasztás/core (3nm) | Msg throughput/watt |
|---|---|---|
| x86 Zen 5 | ~10-15 W | ~3K msg/s/W |
| M4 P-core | ~5-8 W | ~8K msg/s/W |
| M4 E-core | ~0.5-1 W | ~130K msg/s/W |
| RISC-V U74 | ~0.1-0.3 W | ~500K msg/s/W |
| **CLI-CPU Rich** | **~0.01-0.05 W** | **~2-8M msg/s/W** |
| **CLI-CPU Nano** | **~0.001-0.005 W** | **~5-20M msg/s/W** |

A sleep/wake modell miatt az idle Nano core **~0 W** — hagyományos CPU-n az idle core is fogyaszt (leakage, clock distribution).

### Single-thread: ahol a CLI-CPU veszít

| | Single-thread IPC × GHz (3nm) |
|---|---|
| x86 Zen 5 | 5.5 × 5.7 = **31.4 GIPS** |
| M4 P-core | 5.5 × 4.5 = **24.8 GIPS** |
| M4 E-core | 2.5 × 2.8 = **7.0 GIPS** |
| ARM A720 | 4.0 × 3.3 = **13.2 GIPS** |
| RISC-V U74 | 2.0 × 1.5 = **3.0 GIPS** |
| **CLI-CPU Rich** | 0.7 × 2.0 = **1.4 GIPS** |
| **CLI-CPU Nano** | 0.4 × 3.0 = **1.2 GIPS** |

Single-thread-ben a CLI-CPU **~20× lassabb** — de ez nem a versenyterep, amire tervezték.

### Összefoglalás — igazságos összevetés

| Metrika | Hagyományos nyerő | CLI-CPU nyerő | Arány |
|---|---|---|---|
| Single-thread sebesség | M4 P / x86 | — | ~20× hagyományos előny |
| Ctx switch (ciklusban) | — | Nano / Rich | **~1,000-20,000×** CLI-CPU |
| Throughput / mm² (actor) | — | Nano | **~1,000-2,000×** CLI-CPU |
| Throughput / watt (actor) | — | Nano | **~1,000-4,000×** CLI-CPU |
| Skálázhatóság | ~8-16 core-ig lineáris | 1,000+ core lineáris | CLI-CPU nem romlik |
| Determinizmus | Nincs (OoO, spekuláció) | Teljes (in-order) | CLI-CPU garantált |

**A lényeg:** nem az órajel a fontos, hanem hogy mit csinálsz vele. Egy 3 GHz-es Nano core actor workload-on **~12 ciklust** igényel egy aktorváltásnál, amihez egy 5.7 GHz-es Zen 5-nek **~166,000 ciklus** kell. Az órajel-hátrány (~2×) eltörpül az architekturális előny (~10,000×) mellett.

---

## 8. Hány CLI-CPU core fér egy AMD Zen 4 chip területére?

**Rövid válasz:** Egy 32-core-os AMD EPYC chip ~288 mm² számítási területén **~2,225 CLI-CPU Fat Rich core** fér el — **~70× több**, azonos funkcionalitással (teljes CIL, FPU, GC, kivételkezelés). Az aggregált throughput párhuzamos workload-on **~8-11× magasabb**.

### Az AMD Zen 4 chip felépítése

Egy AMD Zen 4 core (~9 mm²) területe meglepően oszlik el:

| Komponens | Terület | Arány | Mit csinál |
|---|---|---|---|
| **L2 cache (1 MB)** | ~3.5 mm² | **39%** | Adat gyorsítás |
| **OoO engine** (ROB, scheduler, rename) | ~2.0 mm² | **22%** | Utasítás átrendezés |
| **Frontend** (x86 decode, branch pred, µop cache) | ~1.5 mm² | **17%** | x86→µop fordítás |
| **Execute** (4× ALU, 2× FPU, 3× AGU) | ~1.0 mm² | **11%** | Tényleges számítás |
| **L1 cache** (I+D, 64 KB) | ~0.5 mm² | **6%** | Közvetlen adat |
| Egyéb (clock, power) | ~0.5 mm² | **5%** | Infrastruktúra |

A tényleges számítás (ALU+FPU) a core területének **mindössze ~11%-a**. A többi 89% cache, sorrendezés, dekódolás és infrastruktúra — olyan feladatok, amelyeket a CLI-CPU shared-nothing modellje **nem igényel**.

### CLI-CPU Fat Rich core — azonos funkcionalitás, ~82× kisebb

A „Fat Rich" core a Rich core bővített változata: 2-wide decode, branch predictor, dual ALU — funkcionálisan azonos szintű, mint az AMD core (teljes ISA, FPU, GC, kivételek).

| Komponens | AMD Zen 4 | CLI-CPU Fat Rich | Miért kisebb |
|---|---|---|---|
| Dekóder | ~1.5 mm² | ~0.010 mm² | 220 CIL opkód vs ~1500 x86, nincs µop fordítás |
| OoO engine | ~2.0 mm² | 0 mm² | In-order — nincs ROB/rename |
| Branch predictor | ~0.3 mm² | ~0.005 mm² | Egyszerű BHT vs komplex TAGE |
| Execute (ALU+FPU) | ~1.0 mm² | ~0.010 mm² | 2 ALU + 1 FPU, 32-bit fő, nincs AGU |
| L1+L2 cache | ~4.0 mm² | 0 mm² | Privát SRAM kiváltja |
| SRAM (256 KB) | — | ~0.060 mm² | Stack + heap + aktor state |
| GC + metadata + mailbox | — | ~0.015 mm² | Hardveres GC, vtable, üzenetküldés |
| Egyéb | ~0.5 mm² | ~0.010 mm² | Kisebb die = egyszerűbb |
| **Összesen** | **~9.0 mm²** | **~0.110 mm²** | **~82× kisebb** |

### Hány core fér el?

288 mm² (32 AMD core területe), TSMC 5nm:

| Architektúra | Core szám | Single-thread | Aggregált throughput |
|---|---|---|---|
| AMD Zen 4 | 32 | 28.6 GIPS | 915 GIPS |
| **CLI-CPU Fat Rich** | **~2,225** | 3.25 GIPS | **~7,231 GIPS** |

A CLI-CPU single-thread-ben ~8.8× lassabb — de azonos területen **~8× magasabb aggregált throughput-ot** ad.

### Heterogén konfigurációk — a workload határozza meg

| Workload | Rich core | Nano core | Összesen | Core szám |
|---|---|---|---|---|
| C# üzleti app (string, objektum, kivétel) | ~96% | ~4% | 288 mm² | ~5,200 |
| IoT edge (szenzor + HTTP API) | ~3% | ~97% | 288 mm² | ~16,500 |
| SNN neurális háló (integer neuronok) | ~0.1% | ~99.9% | 288 mm² | ~24,000 |

Ugyanaz a chip, **a workload-hoz igazított arányban**.

---

## 9. Mennyivel kevesebbet fogyaszt a CLI-CPU?

**Rövid válasz:** Csúcsterhelésen **~2× kevesebbet**, szerver workload-on (ahol a core-ok többsége I/O-ra vár) **~8-15× kevesebbet**. A megtakarítás fő forrása nem a tranzisztor szám (az **közel azonos** azonos chipterületen), hanem az **alacsonyabb activity factor** és a **hardveres sleep/wake**.

### Miért NEM a tranzisztor számból jön a megtakarítás?

Azonos chipterületen (288 mm², TSMC 5nm) a tranzisztor szám **közel azonos**:

| | AMD Zen 4 (32 core) | CLI-CPU Fat Rich (2,225 core) |
|---|---|---|
| Terület | 288 mm² | 288 mm² |
| Tranzisztor / core | ~820M | ~10M |
| Core szám | 32 | 2,225 |
| **Összes tranzisztor** | **~26,240M** | **~22,250M** |

A chip területe **azonos**, tehát a tranzisztor mennyiség is hasonló. A fogyasztáskülönbség máshonnan jön.

### A három fő megtakarítási forrás

**1. Activity factor — az OoO és spekuláció felesleges kapcsolásai:**

| | AMD Zen 4 | CLI-CPU |
|---|---|---|
| OoO engine (ROB, rename, scheduler) | Állandóan kapcsol | **Nincs** |
| Spekulatív végrehajtás | ~30% felesleges munka | **Nincs** |
| Cache koherencia (snoop, invalidate) | Állandóan fut | **Nincs** |
| Branch predictor tábla frissítés | Minden branch-nél | Egyszerű BHT |
| **Átlagos activity factor** | **~0.4** | **~0.25** |

Megtakarítás: **~1.6×**

**2. Feszültség/órajel — alacsonyabb f → alacsonyabb V → V² hatás:**

| | AMD Zen 4 | CLI-CPU (5-stage) |
|---|---|---|
| Órajel | 5.2 GHz | 2.5 GHz |
| Feszültség | ~1.0V | ~0.65V |
| **V² × f** | **5.2** | **1.06** |

Megtakarítás: **~5×** (de a CLI-CPU-nak ~70× több core-ja van, ami visszaeszi)

**3. Hardveres sleep/wake — a szerver workload trükkje:**

```
AMD (szerver, 99% I/O wait):
  4 core aktívan számol              ~32W
  28 core idle, DE clock forog       ~56W  ← EZ a pazarlás!
  Uncore (memória controller)        ~30W
  Összesen:                         ~118W

CLI-CPU (szerver, 99% I/O wait):
  100 core aktívan számol            ~1W
  2,125 core ALSZIK (clock gated)    ~0.01W  ← NULLA!
  SRAM leakage (power gated)         ~1-2W
  Router + I/O                       ~1W
  Összesen:                         ~3-5W
```

### Összesített fogyasztás becslés

| Állapot | AMD Zen 4 | CLI-CPU | Arány | Fő ok |
|---|---|---|---|---|
| **Csúcsterhelés** | ~200W | **~100-125W** | **~1.6-2×** | Activity factor |
| **Szerver workload** | ~118W | **~8-15W** | **~8-15×** | Sleep/wake |
| **Idle** | ~30-50W | **~1-2W** | **~20-30×** | Power gating |

### Őszinte fenntartások

| Bizonytalanság | Hatás |
|---|---|
| SRAM leakage 2,225 core-nál | Lehet nagyobb mint becsülve |
| Router mesh fogyasztás | Nem becsült pontosan |
| Valós V/f operating point | Szilícium mérés nélkül ismeretlen |
| **Nincs mérésünk** | **Az AMD számok mértek, a CLI-CPU számok becslések** |

**Ami biztosan állítható:** szerver workload-on ~8-15× kevesebb fogyasztás, mert a sleep/wake hardveres és a shared-nothing modell nem igényel cache koherenciát.

---

## 10. Miért nem emeljük az órajelet magasabbra?

**Rövid válasz:** Mert **két core fele órajellel hatékonyabb**, mint egy core dupla órajellel. Az órajel duplázása a fogyasztást ~4×-esére emeli (V² hatás), míg a core szám duplázása **lineárisan** skálázik. A CLI-CPU filozófiája: ne egy core-t gyorsíts, hanem **rakj be többet**.

### Az órajel és a fogyasztás kapcsolata

```
Fogyasztás = C × V² × f

Az órajel (f) emeléséhez a feszültséget (V) is emelni kell:

  2.5 GHz @ 0.65V:  P = C × 0.42 × 2.5 = 1.06 × C
  5.0 GHz @ 0.95V:  P = C × 0.90 × 5.0 = 4.51 × C

  2× órajel → ~4.25× fogyasztás
```

### 1 core 2× órajellel vs 2 core 1× órajellel

| | 1 core @ 5.0 GHz | 2 core @ 2.5 GHz |
|---|---|---|
| Órajel | 5.0 GHz | 2.5 GHz |
| Feszültség | ~0.95V | ~0.65V |
| IPC / core | 1.2 (mélyebb pipeline kell) | 1.3 |
| **Aggregált sebesség** | **6.0 GIPS** | **6.5 GIPS** |
| **Fogyasztás (relatív)** | **4.51** | **2.11** |
| **GIPS / watt** | **1.33** | **3.08** |

Két core fele órajellel: **+8% sebesség, -53% fogyasztás, 2.3× jobb hatékonyság**.

### Miért csökken az IPC az órajel emelésével?

Az órajel emeléshez a pipeline-t **mélyíteni** kell — több fokozatra darabolni a logikát. De a mélyebb pipeline **branch penalty**-t okoz: ha egy elágazásnál a CPU rossz irányt tippel, az addig fetch-elt utasításokat **ki kell dobni**.

```
Branch penalty = a pipeline mélysége - 1

  5-stage:   4 ciklus elveszett (kicsi → nem kell predictor)
  12-stage: 11 ciklus elveszett (nagy → predictor KÖTELEZŐ)
  19-stage: 18 ciklus elveszett (hatalmas → komplex TAGE predictor)
```

### A sebesség csúcspontja — túl mély pipeline-nál VISSZAESIK

```
Sebesség (GIPS)
     ▲
 7.0 │                          ●──── 16-stage (csúcs!)
     │                      ╱      ╲
 6.0 │                ● ──╱          ╲── 20-stage (VISSZAESIK!)
     │             ╱  12-stage
 5.0 │          ╱
     │       ╱
 4.0 │   ● 8-stage
     │  ╱
 3.0 │● 5-stage (jelenlegi terv)
     └──────────────────────────────────────► Órajel (GHz)
       2.5    3.8    4.8    5.5    5.8
```

~16 stage felett az órajel alig nő (fizikai határ), de az IPC sokat esik → a sebesség **csökken**.

### A CLI-CPU sweet spot: 5-stage, branch predictor nélkül

| Konfiguráció | Órajel | IPC | GIPS | Core szám (288 mm²) | Aggregált | GIPS/watt |
|---|---|---|---|---|---|---|
| **5-stage** (jelenlegi) | 2.5 GHz | 1.3 | 3.25 | 2,225 | **7,231** | **~289** |
| 12-stage + BP | 4.8 GHz | 1.25 | 6.0 | 1,700 | 10,200 | ~128 |

A 12-stage +41% aggregált sebességet ad, de **-56% GIPS/watt** hatékonysággal. A CLI-CPU nem az órajelben versenyez, hanem a **core szám × hatékonyság** szorzatban.

### Ez nem új felismerés

| Példa | Stratégia |
|---|---|
| ARM big.LITTLE (2011) | Sok kis E-core, kevés nagy P-core |
| Apple M-sorozat E-core | Alacsony órajel, magas hatékonyság |
| Google TPU | Sok egyszerű MAC egység, nem nagy órajel |
| **CLI-CPU** | **Sok kis core, alacsony órajel, shared-nothing** |

Az ipar trendje: **ne egy core-t gyorsíts, hanem rakj be többet**. A CLI-CPU ezt viszi a végletekig.

---

## A FAQ bővítése

Ez a dokumentum **élő**. Amikor a projekt során új, visszatérő koncepcionális kérdés merül fel (akár belső fejlesztői vitából, akár külső olvasótól), érdemes ide felvenni.

**Formátum új bejegyzéshez:**

1. Új H2 szekció a következő sorszámmal
2. Első bekezdésben **rövid válasz** (1-3 mondat)
3. Utána részletes indoklás, szükség esetén táblázatokkal, kódrészletekkel
4. Hivatkozások a releváns `docs/` fájlokra, ahol a mélyebb részletek vannak
5. A tartalomjegyzék frissítése a dokumentum tetején

**Amit NEM érdemes FAQ-ba tenni:**

- Részletes specifikációk (→ `ISA-CIL-T0-hu.md`, `architecture-hu.md`)
- Fejlesztői útmutatók (→ majd `CONTRIBUTING.md`)
- Build és telepítési instrukciók (→ majd `README.md` vagy `BUILDING.md`)
- Egyszer-feltett, nem ismétlődő kérdések (→ GitHub Issues)

A FAQ **konceptuális horgonyokat** ad, nem dokumentáció-duplikációt.

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
| 1.1 | 2026-04-15 | FAQ 8-10: AMD összehasonlítás, fogyasztás, órajel stratégia |
