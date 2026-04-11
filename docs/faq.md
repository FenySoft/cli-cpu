# CLI-CPU — Gyakori Kérdések (FAQ)

Ez a dokumentum olyan koncepcionális kérdéseket gyűjt, amelyek a projekt megértéséhez szükségesek, de nem férnek bele a részletes spec dokumentumokba (`architecture.md`, `ISA-CIL-T0.md`, `security.md`, `neuron-os.md`, `secure-element.md`).

A FAQ célja, hogy egy **új olvasó** (akár mérnök, akár befektető, akár érdeklődő) gyorsan elhelyezze magában a projekt pozícióját anélkül, hogy a teljes ~3500+ soros dokumentáción végig kellene rágnia magát.

## Tartalom

- [1. CLI vagy CIL — mi a helyes szóhasználat?](#1-cli-vagy-cil--mi-a-helyes-szóhasználat)
- [2. A CLI-t meg lehet valósítani hardveren?](#2-a-cli-t-meg-lehet-valósítani-hardveren)
- [3. Egy fizikai core több logikai aktort kiszolgálhat?](#3-egy-fizikai-core-több-logikai-aktort-kiszolgálhat)
- [4. Miért fontosabb az F6-FPGA, mint az F6-Silicon?](#4-miért-fontosabb-az-f6-fpga-mint-az-f6-silicon)

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
| **CIL bájtkód** (~220 opkód) | 🟢 Könnyű | ~75% hardwired (1 ciklus), ~25% mikrokódolt — lásd `architecture.md` „Hardwired vs mikrokódolt osztályozás" |
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

A `docs/architecture.md` hat konkrét architekturális döntést tartalmaz, amelyek együtt lehetővé teszik a CLI hardveres implementációját:

#### 1. Hibrid dekódolás (75/25 arány)

A gyakori, egyszerű opkódokat (`ldc.i4`, `add`, `ldloc`, `stloc`, `br`) **közvetlen hardver** végzi 1 ciklus alatt. A ritka, komplex opkódokat (`newobj`, `castclass`, `isinst`, `callvirt`) **mikrokód ROM-ból** trap-eli a dekóder, és egy mikrokód szekvencia futtatja le őket.

**Ez a picoJava tanulsága:** nem éri meg minden 220 opkódot szilíciumba önteni. A forró 48-ra optimalizálj, a maradékot mikrokóddal.

#### 2. Shared-nothing modell → nincs globális GC

A CLI klasszikus implementációjának legnagyobb fejfájása a **stop-the-world GC** egy megosztott heap-en. A CLI-CPU ezt **teljesen kikerüli**:

> „Minden core-nak saját 16 KB SRAM-ja van... (F5-től) saját objektum heap-je" (`architecture.md`)

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

Az F6 tape-outban lesz egy **írható mikrokód SRAM** (`roadmap.md`):

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

#### ❌ Dynamic assembly loading

A .NET-ben futásidőben betölthetünk új DLL-eket. A CLI-CPU-n **nem** — a binárisok **statikusan linkelt** `.t0` vagy `.tr` fájlok, a boot-loader tölti be egyszer. **Ez a formális verifikáció előfeltétele**: ha egyszer ellenőriztük a statikus képet, senki nem tudja futásidőben módosítani.

#### ❌ Thread, async/await runtime

A C# `async/await` kulcsszavak **build-time állapotgép kompilációra** fordulnak (a Roslyn csinálja). Nincs „async runtime" a CLI-CPU-n — csak **egy aktor üzenet a mailbox-on**. Az async/await és a Task minta **természetesen leképződik** a mailbox-alapú üzenetre (részletek: `neuron-os.md`).

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

A `docs/architecture.md` „Stratégiai pozicionálás: Cognitive Fabric" szekciója szerint a CLI-CPU **nem a hagyományos 1 mag = 1 szál versenyt játssza**, hanem **sok kis core + event-driven + shared-nothing** terepet. Ezen a terepen a hardveres CIL-implementáció **értelmes**, mert:

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

**A CLI-CPU pontosan ez az útvonal.** A `docs/architecture.md` ezt világosan megfogalmazza, és a hét fázis (F0–F7) ennek a victory path-nak a lépéseit járja be:

- **F3 Tiny Tapeout:** a CIL-T0 48 opkód hardverben → bizonyíték, hogy működik
- **F4 Multi-core FPGA:** a shared-nothing modell → bizonyíték, hogy skálázódik
- **F5 Rich core:** a teljes CLI → bizonyíték, hogy kivitelezhető
- **F6 Tape-out:** a kereskedelmi bizonyíték

---

## 3. Egy fizikai core több logikai aktort kiszolgálhat?

**Rövid válasz: igen, és ez nem opcionális optimalizáció, hanem a Neuron OS vízió alapvető része.** A fizikai core egy hardver erőforrás, a logikai aktor egy futtatási egység — a kettő aránya **dizájn-döntés**, nem fix 1:1 leképzés.

### A projekt saját dokumentációja explicit támogatja

A `docs/neuron-os.md` négy különböző helyen is rögzíti a „több aktor egy core-on" modellt:

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
| **Fizikai core** | Hardveres végrehajtó egység (Nano vagy Rich) | F6-on: 32–48 Nano + 2–4 Rich |
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
│  │  Privát SRAM: 16 KB      │  │
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

Ez pont olyan, mint az **Akka.NET / Erlang runtime**, csak **hardveres mailbox és privát SRAM** támogatással — **kooperatív multitasking**, ahol a scheduler nem szakítja félbe az üzenet-feldolgozást (`neuron-os.md` 278. sor).

### Hány aktor fér egy core-on?

A kemény korlát a privát SRAM mérete. A runtime maga ~2–3 KB (Nano) vagy ~10–20 KB (Rich), a maradék aktoroknak jut:

**Nano core (16 KB privát SRAM):**
- Nagyon kis aktor (~50–100 byte) → **~100–200 aktor**
- Átlagos aktor (~500 byte) → **~25–30 aktor**
- Nagy állapotú aktor (~2 KB) → **~6–7 aktor**

**Rich core (64–256 KB privát SRAM + heap):**
- Egyszerű aktor (~200–500 byte) → **~100–500 aktor**
- Komplex aktor objektumokkal (~5–10 KB) → **~10–50 aktor**

**F6 szilícium teljes kapacitás (32 Nano + 4 Rich):**
- Átlagos workload: **~1500–5000 logikai aktor** egyidejűleg
- Kis aktorokra optimalizálva: **akár 10 000+**

### Mikor érdemes „1 core = 1 aktor" modellt használni?

Van amikor szándékosan dedikált core-t kap egy aktor:

- **Kritikus timing** — real-time vezérlés, forró hálózati útvonal, audio pipeline
- **Isolation** — biztonsági domain (pl. kripto kulcs kezelés a Secure Element-ben)
- **Performance worker** — SNN neuron, ahol a deterministikus time-step számít
- **Fault isolation** — egy supervisor-fa levele, amelyet lehet restart-olni a többi befolyásolása nélkül

### Mikor érdemes „1 core = sok aktor" modellt használni?

- **Nagy aktor populáció** — ezer vagy több aktor (pl. webszerver: 1 kérés = 1 aktor, `neuron-os.md` 434. sor)
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

Vigyázz egy potenciális ellentmondással: a `docs/roadmap.md` **F3 Tiny Tapeout** verziója egyetlen core-on **egyetlen CIL program**ot futtat. Ez **nem** azt jelenti, hogy a core csak 1 aktort tud hordozni — F3-ban egyszerűen a Tiny Tapeout tile SRAM annyira kicsi, hogy nem érdemes runtime-ot tenni rá.

**A multi-aktor runtime F4-től jön be** (`neuron-os.md` 617–624. sor), amikor már a `scheduler` + `router` valódi szerepet játszik, és F5-től természetes a több aktor egy core-on.

### A megkülönböztető pont más neuromorphic chipekkel szemben

Ez pont az, ami **megkülönbözteti a CLI-CPU-t** a hagyományos neuromorphic chipektől (Intel Loihi, IBM TrueNorth, BrainChip Akida): **nem rögzített 1 neuron = 1 compute unit** topológia, hanem **rugalmas N aktor × M core** leképzés egy runtime-on keresztül. A hardver biztosítja az izoláció és üzenet-továbbítás alapjait, a runtime pedig a logikai aktorok flexibilis elhelyezését.

---

## 4. Miért fontosabb az F6-FPGA, mint az F6-Silicon?

**Rövid válasz:** mert a **CLI-CPU nyílt forráskódú filozófiája** azt követeli, hogy a teljes architektúrát **először nyílt toolchain-en, reprodukálható módon bizonyítsuk**, és a **legnagyobb OpenXC7-támogatott Xilinx FPGA-k (Kintex-7 325T és 480T)** **pontosan elegendőek** a teljes Cognitive Fabric demonstrálására **silicon nélkül**, **30-100× olcsóbban**, **órás iterációs ciklussal**.

A `docs/roadmap.md` 2026 áprilisi pivot-ja kettébontotta az F6-ot **F6-FPGA** (elsődleges) és **F6-Silicon** (opcionális, halasztható) variánsra. Ez a kérdés ezt a döntést magyarázza el új olvasóknak.

### A pivot oka

Az **OpenXC7** (a Project X-Ray + Yosys + nextpnr-xilinx köré épült nyílt FPGA toolchain) **érett állapotban** támogatja a Xilinx **7-series** családot, beleértve a **Kintex-7 XC7K325T** (~204k LUT) és **XC7K480T** (~298k LUT) chipeket. **Ez a technikai határa** a 2026-os nyílt FPGA toolchain-eknek Xilinx hardveren — UltraScale+ még nem támogatott, és valószínűleg évekig nem lesz az.

A felismerés: **ez a határ pontosan elegendő** a CLI-CPU **teljes F6 heterogén Cognitive Fabric** (2–4 Rich + 32–48 Nano core) **demonstrálásához**. **Nem kell silicon ahhoz, hogy az architektúra bizonyítva legyen.**

### Mit nyer az F6-FPGA megközelítés

| Szempont | F6-Silicon (eredeti) | **F6-FPGA (új elsődleges)** |
|----------|---------------------|----------------------------|
| **Toolchain** | OpenLane2 (nyílt, érett) | OpenXC7 (nyílt, érett 7-series-en) |
| **Költség** | ~$10 000 | **~$200-400** |
| **Build idő** | 4–6 hónap | **órák** (rebuild) |
| **Iterálhatóság** | Egyszeri tape-out | **Korlátlan** módosítás |
| **Hibák költsége** | Egy bug → ~$10k + 6 hó | Egy bug → **azonnal javítható** |
| **Reprodukálhatóság** | Egyedi MPW chip | **Bárki** újragyárthat ugyanazzal a hardverrel |
| **Auditálhatóság** | OpenLane build chain | **OpenXC7 build chain** |
| **Sweet spot keresés** | Csak egyszer kipróbálható | **Tucatnyi (Rich, Nano) konfiguráció** szisztematikusan |
| **Filozófia-illeszkedés** | ⚠️ Vegyes (silicon = zárt foundry process) | ✅ **Tisztán nyílt end-to-end** |

### Mit veszít

- **Power efficiency mérés** — az FPGA fogyasztása ~10–20× rosszabb, mint Sky130 silicon. Az event-driven energia-spórolás csak silicon-on bizonyítható valós számokkal.
- **Órajel maximum** — FPGA-n ~100–200 MHz, silicon-on ~300–600 MHz lehetséges ugyanarra az RTL-re.
- **Fizikai chip** — „kézben tartható silicon" hatás. **De**: ez a roadmap szerint **F3 Tiny Tapeout-ban már megtörtént**, **nem F6 az első silicon**.
- **F6.5 Secure Edition pálya** — a Crypto Actor, TRNG, PUF, tamper detection silicon-specifikus hardvert igényel, ezért az F6.5 továbbra is az **F6-Silicon**-ra épít, **nem** az F6-FPGA-ra.

### Az F6-Silicon nem törlődik — csak halasztódik

Az F6-Silicon **akkor indul**, ha **legalább egy** a következőkből igaz:

1. A projekt **finanszírozást vagy ipari partnert** kapott a tape-out fedezésére
2. A **kereskedelmi termék útvonal** (F6.5 Secure Edition, F7 demo hardver) **silicon-előfeltétel**
3. A **valós energia hatékonyság** és **>500 MHz órajel** mérése **kritikus** a következő mérföldkőhöz
4. Az **F6.5 Secure Edition tape-out** közeledik, és a Cognitive Fabric base **szilíciumon** kell legyen először

**Addig** az F6-FPGA bőven elegendő ahhoz, hogy a projekt mérnökileg, demo szempontból, és publikációs szempontból **„kész"** legyen.

### A hardver konkrétan

- **Elsődleges F6-FPGA target:** **Kintex-7 XC7K480T** (pl. Inspur YPCB-00338-1P1, ex-data center, ~$60-200) — **298k LUT**, elég a 2 Rich + 32 Nano = 34 core F6 alsó silicon target FPGA megfelelőjéhez
- **Másodlagos F6-FPGA target:** **Kintex-7 XC7K325T** (pl. SITLINV CERN-OHL-P-2.0 nyílt hardver dev board ~$220-265) — **204k LUT**, kisebb konfigurációkra (1-2 Rich + 16-24 Nano)
- **Mindkettő:** OpenXC7 + yosys + nextpnr-xilinx, **Vivado licenc nem szükséges**

### A multi-konfiguráció sweet spot keresés

Az F6-FPGA fő hozzáadott értéke az **adatvezérelt sweet spot keresés**. A kész kritérium szerint **legalább 4 különböző (Rich, Nano) konfiguráció** szintetizálva és tesztelve:

| FPGA | (Rich, Nano) | Cél |
|------|--------------|-----|
| K7-325T | (0, 30) | Tiszta Nano fabric (SNN max) |
| K7-325T | (2, 16) | Heterogén közép |
| K7-480T | **(2, 32)** | **F6 alsó silicon target megfelelője** |
| K7-480T | (4, 12) | Apple-szerű big.LITTLE arány |

A tényleges F6-Silicon tape-out (ha valaha indul) **az F6-FPGA-ban kiválasztott sweet spot** alapján mehet, **adatvezérelt döntéssel**, nem előre fix becsléssel.

### Filozófiai következmény

Ez a pivot **mélyebb**, mint csupán hardver-választás. Ez kimondja: **a CLI-CPU értéke nem csak a fizikai chipben van, hanem a tervezési módszertanban is** — a teljesen nyílt, reprodukálható, audálható, iterálható build chain-ben. Az F6-FPGA **nem alacsonyabb rendű mérföldkő**, mint az F6-Silicon — **más kategóriájú**, és a projekt nyílt forráskódú víziójához **közelebb** áll.

**Részletek:** [`docs/roadmap.md`](roadmap.md) F6 szekció és „Három kulcs pivot" szakasz.

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

- Részletes specifikációk (→ `ISA-CIL-T0.md`, `architecture.md`)
- Fejlesztői útmutatók (→ majd `CONTRIBUTING.md`)
- Build és telepítési instrukciók (→ majd `README.md` vagy `BUILDING.md`)
- Egyszer-feltett, nem ismétlődő kérdések (→ GitHub Issues)

A FAQ **konceptuális horgonyokat** ad, nem dokumentáció-duplikációt.
