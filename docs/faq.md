# CLI-CPU — Gyakori Kérdések (FAQ)

Ez a dokumentum olyan koncepcionális kérdéseket gyűjt, amelyek a projekt megértéséhez szükségesek, de nem férnek bele a részletes spec dokumentumokba (`architecture.md`, `ISA-CIL-T0.md`, `security.md`, `neuron-os.md`, `secure-element.md`).

A FAQ célja, hogy egy **új olvasó** (akár mérnök, akár befektető, akár érdeklődő) gyorsan elhelyezze magában a projekt pozícióját anélkül, hogy a teljes ~3500+ soros dokumentáción végig kellene rágnia magát.

## Tartalom

- [1. CLI vagy CIL — mi a helyes szóhasználat?](#1-cli-vagy-cil--mi-a-helyes-szóhasználat)
- [2. A CLI-t meg lehet valósítani hardveren?](#2-a-cli-t-meg-lehet-valósítani-hardveren)

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
| **Azul Vega / Vega2** | 2005 | Custom Java processzor hardveres GC assist-tel | ✅ Siker — de drága, niche, csak high-frequency trading-nek |
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
