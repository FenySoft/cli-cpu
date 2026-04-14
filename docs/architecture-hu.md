# CLI-CPU — Architektúra Áttekintés

> English version: [architecture-en.md](architecture-en.md)

> Version: 1.0

Ez a dokumentum a CLI-CPU **mikroarchitektúráját** írja le magas szinten: a stack-gép modellt, a pipeline-t, a memória térképet, a dekódolási stratégiát, a GC és kivételkezelés hardveres támogatását, valamint az elődprojektek (picoJava, Jazelle, Transmeta) közül átvett technikákat.

> **Megjegyzés:** Ez az architektúra fokozatosan épül fel az F0–F7 fázisokban. Az itt leírt teljes funkciókészlet az **F6-Silicon „Cognitive Fabric One"** chipben készül el (ChipIgnite vagy IHP MPW, 6R+17N+1S, 10 mm²). A **Tiny Tapeout (F3)** csak az egymagos CIL-T0 subset-et valósítja meg, amit egy külön dokumentum (`ISA-CIL-T0-hu.md`) ír le. A „Cognitive Fabric One" szekció rögzíti a konkrét referencia chip víziót és az összehasonlítást a hagyományos multi-core CPU-kkal.

## Stratégiai pozicionálás: Cognitive Fabric

A CLI-CPU **nem klasszikus bytecode CPU-ként** pozicionálja magát, mint annak idején a Sun picoJava vagy az ARM Jazelle. Azt az utat **már megpróbálták, és megbukott**: a szoftveres JIT + hagyományos CPU olcsóbb és gyorsabb lett, mint a dedikált bytecode hardver. Ugyanezt az utat megismételni **nem lenne értelmes**.

Ehelyett a CLI-CPU egy **programozható kognitív szubsztrátum** — sok kis, független CIL-natív core, amelyek **üzenet-alapú kommunikációval** egy heterogén, eseményvezérelt hálózatot alkotnak. Minden core egy **teljes CIL programot** futtat saját lokális állapottal; a core-ok **mailbox FIFO-kon keresztül** beszélnek egymással, nincs megosztott memória, nincs cache koherencia protokoll, nincs lock contention. A használati mód a programtól függ: egy chip lehet **Akka.NET actor cluster**, **programozható spiking neural network**, **multi-agent szimuláció**, vagy **event-driven IoT edge**.

### Miért más ez, mint a létező megoldások

| Rendszer | Programozható? | Hardveres? | Nyílt? | .NET natív? | Event-driven? | Stack-kompakt ISA? |
|---------|---------------|------------|--------|-------------|--------------|-------------------|
| Intel Loihi 2 | ❌ rögzített LIF | ✓ | ❌ | ❌ | ✓ | ❌ |
| IBM TrueNorth | ❌ rögzített LIF | ✓ | ❌ | ❌ | ✓ | ❌ |
| BrainChip Akida | ❌ fix modell | ✓ | ❌ | ❌ | ✓ | ❌ |
| GrAI Matter Labs GrAI-1 | ❌ fix | ✓ | ❌ | ❌ | ✓ | ❌ |
| SpiNNaker 2 (Manchester) | ✓ C/C++ ARM | ✓ | részben | ❌ | ❌ (polling) | ❌ (ARM ISA) |
| Akka.NET / Orleans | ✓ teljes C#/F# | ❌ szoftveres | ✓ | ✓ | ❌ (OS scheduler) | ❌ (host CPU ISA) |
| Erlang BEAM | ✓ Erlang | ❌ szoftveres | ✓ | ❌ | ❌ (BEAM scheduler) | ❌ (host CPU ISA) |
| **CLI-CPU (Cognitive Fabric)** | **✓ teljes CIL** | **✓** | **✓** | **✓** | **✓** (hw mailbox wake) | **✓** (CIL stack-gép) |

A **neuromorphic versenytársak** (Loihi, TrueNorth, Akida, GrAI) mind **rögzített neuron-modellel** dolgoznak — nem lehet rajtuk tetszőleges algoritmust futtatni, csak a súlyokat és a topológiát beállítani. A **SpiNNaker** az egyetlen, amely programozható csomópontokat kínál, de **C/C++ ARM magokon**, sok mérnökmunkával, akadémiai keretek között. A **szoftveres actor rendszerek** (Akka.NET, Erlang) rugalmasak, de a host CPU-n versenyeznek a scheduler, GC, lock overhead-jével.

**A CLI-CPU az egyetlen pozíció**, ahol **mind a hat oszlop** teljesül: programozható csomópont + hardveres + nyílt + .NET natív + event-driven + stack-kompakt ISA. Ez nem csak „egy újabb bytecode CPU", hanem **egy új kategória**.

### Neuromorphic-ihletett, de nem neuromorphic

A CLI-CPU **átveszi** a neuromorphic architektúrák legértékesebb elveit:

- **Sok kis független egység** saját lokális állapottal
- **Üzenet-alapú kommunikáció** (nem shared memory)
- **Event-driven working mode** (a core alszik, amíg üzenet nem érkezik)
- **Ultra-alacsony alapfogyasztás**
- **Lineáris skálázódás** core-számmal

De **nem neuromorphic** a szigorú értelmben, mert:

- A csomópontok **nem 1-bit spike-okat** küldenek, hanem **32-bit üzeneteket** (ami elegendő pontosságot ad minden folytonos értéknek digitalizált formában)
- A csomópontok **tetszőleges CIL algoritmust** futtathatnak — egy LIF neuron, egy Izhikevich neuron, egy DSP filter, egy Akka actor, egy state machine, vagy bármi más
- **Digitális, determinisztikus** — nem analóg, nem sztochasztikus
- **Dinamikusan átprogramozható** futás közben — a core új CIL kódot tud betölteni

Ez azt jelenti, hogy egy **ugyanolyan hardveres chip** a program választásától függően lehet:

| Program | A chip mi lesz |
|---------|----------------|
| C# + Akka.NET actors | Natív hardveres actor cluster |
| Leaky Integrate-and-Fire neurons | Spiking Neural Network szimulátor |
| Izhikevich modell + STDP | Biologikusabb SNN kutatási platform |
| Conway's Game of Life + komplex szabályok | Cellular automata szubsztrátum |
| Dataflow pipeline (FIR, IIR, FFT) | DSP processing fabric |
| Multi-agent AI / játék szimuláció | Swarm intelligencia platform |
| Per-request web handler | Embedded web szerver |
| IoT edge szenzor-fúzió | Event-driven IoT gateway |

**Ez a „one hardware, many paradigms" megközelítés** az, ami a projekt történeti jelentőségét adhatja — ha sikerül.

### Többnyelvű platform — az egész .NET ökoszisztéma hardverben

A CLI-CPU **nem C#-t futtat — CIL-t futtat**. Az ECMA-335 Common Intermediate Language az a célformátum, amelyre **minden .NET nyelv** fordít. Ez azt jelenti, hogy a CLI-CPU natívan futtatja:

| Nyelv | Paradigma | CLI-CPU illeszkedés |
|-------|-----------|-------------------|
| **C#** | OOP + funkcionális | Akka.NET, legnagyobb közösség (~6M fejlesztő) |
| **F#** | Funkcionális-first | **Természetes illeszkedés** — immutable by default, pattern matching, algebraic types, actor-barát |
| **VB.NET** | OOP | Legacy kódbázisok portolása |
| **IronPython** | Dinamikus | Gyors prototípus, scripting a chipen |
| **PowerShell** | Shell/scripting | Device management, konfiguráció |

**Ez ~8 millió fejlesztő meglévő kódbázisa**, amely natívan futhat a CLI-CPU-n — fordítás, interpreter, vagy runtime overhead nélkül.

#### Miért más ez, mint a Jazelle?

Az ARM Jazelle (2001) és a Sun picoJava (1997) **megbuktak**, mert:
1. **Egynyelvű** — csak Java bytecode-ot céloztak, egyetlen ökoszisztéma
2. **Egymagos** — shared-memory CPU-n, a szoftveres JIT gyorsabb lett
3. **Nem actor-natív** — nincs hardveres üzenetküldés, nincs mailbox

A CLI-CPU fundamentálisan más:
1. **Többnyelvű** — minden .NET nyelv CIL-re fordul, a hardver CIL-t futtat
2. **Multi-core, shared-nothing** — a szoftveres JIT nem tud 18 core-on párhuzamosan futni cache coherency nélkül
3. **Actor-natív** — a mailbox hardverben van, a context switch 5-8 ciklus (nem 500-2000)

#### F# — a „tökéletes CLI-CPU nyelv"

Az F# különösen erős illeszkedés, mert a nyelvi paradigmája **azonos** a Cognitive Fabric architektúrájával:

- **Immutable by default** → shared-nothing modell természetesen adódik
- **Pattern matching** → actor message dispatch elegáns és biztonságos
- **Pipe operator (`|>`)** → actor pipeline lánc olvasható
- **Discriminated unions** → üzenet típusok fordítási időben ellenőrzöttek
- **Computation expressions** → async actor workflow natívan kifejezhető
- **Nincs null** → kevesebb TTrapReason, biztonságosabb kód

```fsharp
// F# aktor a CLI-CPU Nano core-on
[<RunsOn(CoreType.Nano)>]
let ledController = actor {
    let! msg = receive ()
    match msg with
    | SetLed (id, color) -> setGpio id color
    | BlinkLed (id, hz)  -> startBlink id hz
    | GetState            -> reply (currentState ())
}

// F# aktor a CLI-CPU Rich core-on
[<RunsOn(CoreType.Rich)>]
let navSupervisor = actor {
    let! msg = receive ()
    match msg with
    | SubmitDocument doc ->
        let! signed = ask cryptoActor (Sign doc)
        let! result = ask navClient (Send signed)
        reply result
    | ChildFailed (child, _) ->
        restart child    // let it crash + supervision
}
```

#### Összehasonlítás: RISC-V vs CLI-CPU .NET alkalmazásokon

Ugyanazon a ~10 mm² Sky130 szilíciumon:

| Metrika | CLI-CPU (10R+8N) | RISC-V 4-core + CIL interpreter | RISC-V 4-core + AOT |
|---------|------------------|--------------------------------|---------------------|
| **CIL végrehajtás** | Natív (1×) | 10–50× lassabb (sw interpret) | ~1× de 10-50× nagyobb bináris |
| **Core szám** (same die) | **18** | 4 | 4 |
| **.NET bináris méret** | ~1-2 MB (CIL compact) | +100KB interpreter | ~20-50 MB (AOT natív) |
| **Actor msg/sec** | **~5M** (hw mailbox) | ~25-100K (sw queue + lock) | ~100-250K (sw queue) |
| **Context switch** | 5-8 ciklus | 500-2000 ciklus | 500-2000 ciklus |
| **Cache coherency** | **0%** overhead | 10-20% overhead | 10-20% overhead |
| **GC** | Per-core, kis heap | Global stop-the-world | Global stop-the-world |
| **.NET nyelv kompatibilitás** | **Minden** (C#, F#, VB.NET, ...) | Interpreter: korlátozott | AOT: a legtöbb, de nagy bináris |

A RISC-V-nek **két rossz opciója** van .NET kódra: interpreter (10-50× lassabb) vagy AOT (10-50× nagyobb bináris, I-cache pressure). A CLI-CPU **natívan futtatja a CIL-t**, kompakt formában, hardveres actor támogatással.

**A narratíva:** A CLI-CPU **nem „még egy CPU"** — hanem **az első hardver platform, ami egy 8 milliós fejlesztői ökoszisztéma natív szilíciumát adja**. Minden C#, F#, VB.NET kód, ami CIL-re fordul, natívan fut a Cognitive Fabric-on — átírás, interpreter, vagy JIT nélkül.

## Tervezési alapelvek

1. **A CIL a natív ISA.** A CPU fetch egysége közvetlenül a Roslyn/ilasm által kibocsátott CIL bájtokat olvassa. Nincs JIT, nincs AOT, nincs interpreter réteg. A CIL bájtok a memóriában **változatlanok** maradnak.
2. **Stack-gép, Top-of-Stack Caching-gel.** Kifelé tiszta ECMA-335 evaluation stack; belül a stack felső 4–8 eleme fizikai regiszterekben él, a többi RAM-ba spillel. Ez a picoJava és a HotSpot tanulsága.
3. **Harvard modell külső memóriával.** Külön QSPI kód-flash és külön QSPI PSRAM adatnak. A chip-en belüli SRAM kizárólag gyorsítótár.
4. **Hibrid dekódolás.** Egyszerű opkódok (~75%) közvetlen hardverrel, 1 ciklus. Komplex opkódok (~25%) mikrokód ROM-on keresztül, több ciklus.
5. **Managed memory safety a szilíciumban.** A GC write barrier, a stack bounds check, a branch target validation, a type check — mind hardveres mellékhatás, nem szoftveres runtime feladat.
6. **Shared-nothing multi-core.** Az F4 fázistól kezdve több core működik együtt egyetlen chipen, **megosztott memória nélkül**. Minden core saját lokális SRAM-mal, és kizárólag **mailbox-alapú üzenetekkel** kommunikál. Ez automatikusan megszünteti a cache koherencia, lock contention, memory ordering problémákat.
7. **Event-driven, nem clock-driven.** A core alapértelmezésben alvó üzemmódban van, és **csak akkor ébred**, amikor mailbox üzenet érkezik (vagy timer kilő). Ez ultra-alacsony alapfogyasztást eredményez.
8. **Agresszív power-gating.** Minden fel nem használt egység hideg — FPU, GC koprocesszor, metaadat walker, mailbox router mind külön power domain.

## Multi-core blokk diagram (F4+ cognitive fabric)

Az F4 fázisban a CLI-CPU először válik **valódi hálózattá**. A 4 core egymástól függetlenül futtat saját CIL programot, mindegyik saját lokális SRAM-mal, és kizárólag a mailbox interfészeken keresztül kommunikál. Nincs megosztott heap, nincs cache koherencia:

```                                                                          
  ┌──────────────────────────────────────────────────────────────────────────┐           
  │                    CLI-CPU Cognitive Fabric (F4)                         │           
  │                                                                          │           
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
  │  │  Core 0      │  │  Core 1      │  │  Core 2      │  │  Core 3      │  │
  │  │              │  │              │  │              │  │              │  │
  │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │  │
  │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │  │
  │  │              │  │              │  │              │  │              │  │
  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │  │
  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │
  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │
  │  │  │ privát │  │  │  │ privát │  │  │  │ privát │  │  │  │ privát │  │  │
  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │  │
  │  │              │  │              │  │              │  │              │  │
  │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │  │
  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │  │
  │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │  │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
  │         │                 │                 │                 │          │
  │  ═══════╧═════════════════╧═════════════════╧═════════════════╧═══════   │
  │                         Shared Bus (4-port arbiter)                      │
  │                                   │                                      │
  │              ┌────────────────────┼────────────────────┐                 │
  │              ▼                    ▼                    ▼                 │
  │    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
  │    │ QSPI Flash ctrl │  │   UART / GPIO   │  │  Timer / IRQ    │         │
  │    │   (kód, R/O)    │  │   (I/O interf.) │  │  (global clock) │         │
  │    └─────────────────┘  └─────────────────┘  └─────────────────┘         │
  └──────────────────────────────────────────────────────────────────────────┘
```

**Kulcs megfigyelések:**

- **Minden core ugyanaz**, mint az F3 Tiny Tapeout egymagos CIL-T0. A pipeline, dekóder, mikrokód, stack cache — **változatlan**. Csak 4 példányban van.
- **Nincs megosztott adat SRAM.** Minden core-nak saját 16 KB SRAM-ja van, amelyben él a saját eval stack-je, lokális változói, frame-jei, és (F5-től) saját objektum heap-je.
- **A shared bus csak „lassú" erőforrásokra** — a QSPI flash (kód betöltés, ritka), az UART, a timer. Ezek a core-ok számára nem kritikus útvonalon vannak.
- **Az inter-core kommunikáció** a mailbox FIFO-kon keresztül megy, **a shared bus megkerülésével** — a router egy direkt kapcsolat a 4 core között (F4 szinten 4-portú keresztkötés, ami még nem „crossbar", csak egy egyszerű mux-köteg).
- **Sleep/Wake logika:** ha egy core-ban a CIL program egy `WAIT` mikrokódot futtat (vagy üres inbox-on polling-ba kerül), a core elalszik és csak akkor ébred, amikor mailbox üzenet érkezik. Ez az F4 fázis **event-driven** működésmódja.

### Skálázódás F6-ra (16–64 core)

Az F4 4-core design **lineárisan skálázható** 16 core-ig anélkül, hogy a shared bus torlódna — a CIL programok többsége amúgy is privát SRAM-ban dolgozik, a bus csak ritka (flash fetch, I/O) eseményekre kell. **16 core felett** a bus topológiát át kell nevezni **mesh-re** (2D grid), ahol minden core a szomszédaival és egy lokális I/O csatornával beszél. Ez az F6 ChipIgnite tape-out fizikai szerkezete.

## Heterogén multi-core: Nano + Rich

Az F5 fázistól a CLI-CPU **heterogén multi-core** architektúrára vált, három bevált ipari koncepciót egyesítve egyetlen chipben:

- **ARM big.LITTLE (2011):** Kétféle CPU core egy chipen — „big" (gyors, energiaéhes) és „LITTLE" (lassú, takarékos). A telefon a könnyű feladatokat a LITTLE-ön futtatja, a nehezeket a big-en. **Nálunk: Rich = big, Nano = LITTLE.**
- **Apple Secure Enclave (2013):** Külön, izolált chip-a-chipben az iPhone-ban, amelynek egyetlen feladata a biztonsági műveletek (Face ID, ujjlenyomat, fizetés). Még ha feltörik a telefont, a Secure Enclave-ben tárolt kulcsok biztonságban maradnak. **Nálunk: Secure Core = Secure Enclave.**
- **Intel Alder Lake (2021):** P-core (Performance) + E-core (Efficiency) heterogén keverék, az OS ütemezőre bízva a feladatkiosztást. **Nálunk: a Neuron OS supervisor osztja ki a feladatokat Rich és Nano core-ok között.**

Egyetlen chipen **háromféle elem** él együtt — kettő számítási, egy biztonsági:

| | **Nano core** | **Rich core** |
|-|---------------|---------------|
| **ISA** | CIL-T0 subset (~48 opkód, integer-only, static calls) | Teljes ECMA-335 CIL (~220 opkód) |
| **Méret** | ~10 000 std cell | ~80 000 std cell |
| **Funkciók** | Integer ALU, stack cache, mailbox, mikrokód (mul/div/call/ret) | Nano + objektum modell + GC + metadata walker + vtable cache + FPU (R4/R8) + 64-bit + kivételkezelés + generikusok |
| **Órajel** | ~50–200 MHz | ~50–150 MHz (több pipeline stage miatt kissé lassabb) |
| **Tipikus szerep** | Worker / neuron / filter / egyszerű actor / state machine | Supervisor / orchestrator / komplex domain logika / hibakezelő |
| **Per-core SRAM** | 16–64 KB | 64–256 KB (heap-pel együtt) |
| **Tranzisztor arány** | ~8× több fér el ugyanakkora területre | ~8× kevesebb |

### Miért működik ez — Apple big.LITTLE a CLI-re

A kereskedelmi heterogén multi-core CPU-k (ARM big.LITTLE 2011 óta, Apple M1+ 2020 óta, Intel Alder Lake 2021 óta, AMD Zen 5c 2024 óta) **mind sikeresek**, mert a valós workload-ok **nem homogének**. A legtöbb feladat egyszerű, kevés feladat komplex. **Egy teljes Rich core-t „pazarlás" lenne egy LIF neuronra, és egy Nano core kevés egy orchestrátor-nak.**

Egy valós alkalmazás munkamegosztása:

| Feladat típus | Példa | Core típus |
|--------------|-------|-----------|
| Szenzor-értelmezés | ADC sample → threshold | **Nano** |
| Neuron szimuláció (LIF, Izhikevich) | `potential += weight; if (potential>th) fire()` | **Nano** |
| DSP filter (FIR, IIR) | Simple integer pipeline | **Nano** |
| Filter-lánc | Stream processor egy core-on | **Nano** |
| Akka.NET worker actor | `Receive(msg) { state = f(state, msg); }` | **Nano** (ha integer) |
| Akka.NET supervisor | Exception handling, child restart | **Rich** |
| Complex domain logic | `Order.Validate()`, `User.Authorize()` | **Rich** |
| Orchestrator / coordinator | Több actor koordinálása, tranzakciós logika | **Rich** |
| Dinamikus CIL betöltés | Futásidejű új kód load | **Rich** |
| Hibakezelő / logger | Exception → log + alert | **Rich** |
| FP / tudományos számítás | NN forward pass double precíziósan | **Rich** |
| String / szövegfeldolgozás | `ldstr`, `string.Concat` | **Rich** |

A **Nano**-k többségben vannak (a valós munka ott történik), a **Rich**-ek kis számban felügyelnek.

### Tervezési ökonómia — miért nem költségvetés-növelés

Ez a legfontosabb rész: a heterogén modellhez **nincs új alapvető hardveres tervezési munka**. Mindkét core típus **már szerepel a roadmap-ben**, csak eddig külön fázisokban voltunk rájuk:

```
F3 (Tiny Tapeout)  ─►  Nano core 1×  ───┐
                                        │
F4 (FPGA multi-core) ─►  Nano core 4×  ─┤
                                        │
F5 (FPGA Rich)     ─►  Rich core 1×  ───┤
                                        │
                                        ▼
F6-FPGA (3×A7-200T) ─►  Heterogén: Rich 2× + Nano ~26× elosztva (multi-board)
F6-Silicon (MPW)    ─►  FPGA-verifikált design egyetlen chipre, opcionálisan felskálázva
```

Az **F6-hoz új tervezési munka ~1–2 mérnökhónap**: floorplan optimalizáció, a Roslyn source generator `[RunsOn]` attribútum támogatása, és az a néhány regiszter a message router-ben, ami a Nano/Rich közötti átjárást intézi. **Ez marginális** ahhoz képest, amit a Nano és a Rich core tervezése külön-külön igényel.

### Programozási modell — C# attribútumok

A .NET fordítói szint már most támogatja az ilyen jelölőket. A CLI-CPU-n egy **Roslyn source generator** figyeli a `[RunsOn]` attribútumot, és a metódust a megfelelő bináris fájlba fordítja (`.t0` Nano-ra, `.tr` Rich-re):

```csharp
[RunsOn(CoreType.Nano)]
public class LifNeuron : CoreProgram {
    int potential, threshold, lastTime;

    public void OnSpike(int weight) {
        potential += weight;
        if (potential >= threshold) {
            Fire();
            potential = 0;
        }
    }
}

[RunsOn(CoreType.Rich)]
public class NetworkSupervisor : Actor {
    Dictionary<int, NeuronRef> neurons = new();

    public void OnStartup() {
        try {
            LoadTopologyFromFlash();
            InitializeNeurons();
        } catch (Exception ex) {
            Log.Error(ex);
            Restart();
        }
    }
}
```

A fordító ellenőrzi, hogy a `[RunsOn(CoreType.Nano)]` kódban **csak a CIL-T0 opkódok** fordulnak elő — ha egy Nano metódus `newobj`-ot próbálna használni, a fordítás **compile-time hibát** ad. Ez a CIL ECMA-335 `verifiable code` fogalmának szigorúbb változata.

### Chip-arány javaslatok fázisonként

| Fázis | Platform | Nano cores | Rich cores | Aggregált képesség |
|-------|----------|-----------|-----------|--------------------|
| F3 | Tiny Tapeout | **1** | 0 | Proof of life, első „hálózati csomópont" |
| F4 | FPGA multi-core | **4** | 0 | Első shared-nothing fabric, pure Nano |
| F5 | FPGA heterogén | **4** | **1** | **Első heterogén rendszer**, Rich core teszt |
| F6-FPGA | 3× A7-Lite 200T multi-board (3×134K LUT, Ethernet háló) | **8–10/board, ~26 összesen** | **2** | FPGA-verifikált elosztott Cognitive Fabric |
| F6-Silicon Zero | IHP SG13G2 MPW (3 mm², €0–€4,500) | **8** | **1** | **„Cognitive Fabric Zero"** — első heterogén szilícium |
| F6-Silicon One | ChipIgnite Sky130 (10 mm², ~$15K) | **24** | **2** | **„Cognitive Fabric One"** — teljes demonstráció, benchmark |
| F7 | Termék-chip (jövő) | **64+** | **4–8** | Kereskedelmi Cognitive Fabric |

### Állapot-migráció Nano ↔ Rich

Ha egy Nano core programja túlnő a saját képességén (pl. komplex exception, generikus struktúra, floating-point kell), **üzenetben kérheti** egy Rich core-t, hogy vegye át az állapotát. Ez nem „migráció" a klasszikus értelemben (memória másolás), hanem **egy actor-szerializált üzenet**, ami a shared-nothing modellünkbe természetesen illik.

A Nano core lépései:
1. Megszakítja a jelenlegi feladatot egy `STATE_OVERFLOW` trap-en
2. Az aktuális lokális változók és argumentumok JSON-szerűen szerializálódnak (MessagePack ECMA-335-kompatibilis)
3. Üzenet megy egy kijelölt Rich core-nak „vedd át" kéréssel + serializált állapottal
4. A Rich core folytatja a feladatot natívan, teljes CIL-lel
5. Ha kell, visszaküldi az eredményt a Nano core-nak vagy egy másik címnek

**Ez ritka eset** — a fordítói típus-check a legtöbb esetet build-time elfogja. A runtime migráció csak olyan edge case-ekre, mint a dinamikus reflexió, ami amúgy sem tipikus a cognitive fabric használatban.

### Secure Core — dedikált kód-ellenőrző trust anchor

A Nano és Rich mellett a CLI-CPU egy **harmadik, infrastruktúra jellegű core típust** tartalmaz: a **Secure Core**-t. Ez **nem számítási core** (nem fut rajta felhasználói kód), hanem a rendszer **trust anchor-ja** — minden betöltendő kód rajta keresztül megy.

**Feladata:**
1. **SHA-256 hash** számítás a betöltendő kódra
2. **PQC digitális aláírás ellenőrzés** (Dilithium / XMSS) a hash-re
3. **CIL opkód validáció** (CIL-T0 kompatibilitás ellenőrzés Nano core-ra töltés esetén)
4. **Eredmény:** PASS → a kód betöltődik az operatív memóriába; FAIL → elutasítás, trap

```
   QSPI Flash / Ethernet / UART
              │
              ▼
   ┌──────────────────────┐
   │    Secure Core       │  ← dedikált, egyetlen feladata
   │                      │
   │  1. SHA-256 hash     │
   │  2. PQC aláírás      │
   │     ellenőrzés       │
   │  3. CIL opkód        │
   │     validáció        │
   │                      │
   │  ✅ PASS → betöltés  │
   │  ❌ FAIL → elutasítás│
   └──────────┬───────────┘
              │ csak PASS után
              ▼
   ┌──────────────────────┐
   │  Operatív memória    │
   │  Nano / Rich core-ok │
   │  futtathatják        │
   └──────────────────────┘
```

**Miért dedikált core, nem a Rich core végzi?**

| | Rich core-on | **Dedikált Secure Core** |
|--|-------------|------------------------|
| Feladata | Minden: supervision + GC + crypto + logika | **Egyetlen**: kód ellenőrzés |
| Támadási felület | Nagy (teljes CIL, komplex) | **Minimális** (csak hash + verify) |
| Formálisan verifikálható | Nehéz (túl komplex) | **Igen** (kis, fókuszált kódbázis) |
| Megbízhatóság | Egy Rich core bug → crypto is sérülhet | **Izolált** — más core bugja nem érinti |

**Becsült méret:** ~20-30K std cell — nagyobb mint a Nano (~10K), kisebb mint a Rich (~80K).

**Fázisonként:**

| Fázis | Secure Core |
|-------|------------|
| F3-F4 | Nincs — a host gép ellenőriz build-time |
| **F5** | Bevezetés — SHA-256 + egyszerű aláírás ellenőrzés |
| **F6** | PQC aláírás (Dilithium / XMSS) |
| **F6.5** | Teljes Crypto Actor (Secure Core + TRNG + PUF + tamper detection) |

**A „2 compute core típus" szabály megmarad:** a Nano és Rich a számítási core-ok (big.LITTLE analógia). A Secure Core **infrastruktúra elem** (mint az ARM CryptoCell vagy az Apple Secure Enclave) — nem fut rajta felhasználói kód, kizárólag a rendszer integritását biztosítja.

### Miért nem vezetünk be további core típusokat?

Egy core típust az **ISA-ja** definiál (milyen opkódokat tud végrehajtani), nem a cache vagy SRAM mérete — az csak konfiguráció. Elméletileg lehetne „Micro" (még kisebb ISA, csak 16 opkód) is, de ez **bonyolítja a programozási modellt**: a fejlesztőnek három különböző opkód-készletre kellene figyelnie. A kereskedelmi példák (Apple, ARM, Intel) **mind** pontosan 2 számítási core típust használnak, és ez a sweet spot. A CLI-CPU is **2 számítási core-nál** marad (Nano és Rich), kiegészítve a Secure Core infrastruktúra elemmel.

## Cognitive Fabric One — a referencia silicon target (F6-Silicon)

Ez a szekció a CLI-CPU **első valódi heterogén szilícium chipjének** konkrét vízióját rögzíti: mit tartalmaz, miért éppen ezt a konfigurációt célozzuk, és miért „ütős" — azaz miért demonstrálja, hogy a Cognitive Fabric paradigma **jobb alternatíva** a hagyományos multi-threaded CPU-knál **ugyanazon a szilícium lapkán**.

### Silicon platform: ChipIgnite OpenFrame

A chip az eFabless **ChipIgnite OpenFrame** harness-en készül (~$14,950), amely a Caravel alternatívája:

| | Caravel | **OpenFrame** |
|--|---------|-------------|
| User area | 10 mm² | **~15 mm²** (+50%) |
| User GPIO | 38 | **44** (minden pin szabad) |
| Beépített SoC | RISC-V mgmt core, SPI, UART, DLL | **Nincs** — csak padframe + POR + ID ROM |
| Ár | ~$14,950 | **~$14,950** (azonos) |

Az OpenFrame-et választjuk, mert:
- **15 mm²** területen a 6R+16N+1S konfiguráció **kényelmesen elfér** (~9.73 mm²), és ~5 mm² marad extra SRAM-ra vagy jövőbeli bővítésre
- **44 GPIO** — 6 pinnel több mint a Caravel 38-ja, ami kényelmesebb pin-kiosztást ad
- **Nincs felesleges RISC-V management core** — a CLI-CPU-nak saját Rich core-jai vannak, nem kell külső CPU
- Ugyanaz az ár ($14,950), több terület és flexibilitás

### A chip specifikációja

```
┌──────────────────────────────────────────────────────────────┐
│             CLI-CPU "Cognitive Fabric One"                   │
│                    10 mm² Sky130                             │
│                                                              │
│ ┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐ │
│ │Rich #0 ││Rich #1 ││Rich #2 ││Rich #3 ││Rich #4 ││Rich #5 │ │
│ │ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   ││ 16KB   │ │
│ │Kernel  ││Device  ││App Sup ││Domain  ││Crypto  ││Standby │ │
│ └───┬────┘└───┬────┘└───┬────┘└───┬────┘└───┬────┘└───┬────┘ │
│     │    Mesh Router (2D grid)    │         │         │      │
│     │         │         │         │         │         │      │
│ ┌───┴────┬────┴───┬─────┴───┬─────┴──┬──────┴──┬──────┘      │
│ │N0  4KB │N1  4KB │N2   4KB │N3  4KB │N4  4KB  │             │
│ │N5  4KB │N6  4KB │N7   4KB │N8  4KB │N9  4KB  │ ← 16 Nano   │
│ │N10 4KB │N11 4KB │N12  4KB │N13 4KB │N14 4KB  │   worker    │
│ │N15 4KB │        │         │        │         │   core      │
│ └────────┴────────┴─────────┴────────┴─────────┘             │
│ Minden Nano: saját 4 KB SRAM + Mailbox FIFO + Sleep/Wake     │
│                                                              │
│ ┌──────────────┐                                             │
│ │ Secure Core  │  ← trust anchor (SHA-256 + PQC verify)      │
│ └──────────────┘                                             │
│                                                              │
│ Megosztott OPI busz (8 data + CLK, 2-to-4 CS mux):           │
│ ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌──────────┐            │
│ │OPI Flash│ │OPI PSRAM │ │OPI FRAM │ │(tartalék)│            │
│ │ kód, RO │ │ adat, RW │ │ tartós  │ │          │            │
│ └─────────┘ └──────────┘ └─────────┘ └──────────┘            │
│                                                              │
│ USB 1.1 FS ── Timer ── GPIO                                  │
└──────────────────────────────────────────────────────────────┘

Rich core szerepek:
  #0: Neuron OS kernel — root supervisor, scheduler
  #1: Device drivers — OPI, USB, GPIO (crash → restart)
  #2: Alkalmazás supervisor — app lifecycle, hot code loading
  #3: Komplex domain logika — orchestrátor, string/FP
  #4: Crypto / PQC dedikált számítások
  #5: Hot standby / redundancia
```

### Sky130 területbecslési referencia

A chip tervezési döntései a Sky130 PDK (130nm, SkyWater) fizikai paramétereire épülnek:

| Paraméter | Érték | Forrás |
|-----------|-------|--------|
| **Std cell sűrűség** (sky130_fd_sc_hd) | ~160K gate/mm² (routolva) | SkyWater PDK docs |
| **Raw gate sűrűség** (sky130_fd_sc_hd) | ~266K gate/mm² (routolás nélkül) | SkyWater PDK docs |
| **SRAM sűrűség** (OpenRAM, single-port) | ~0.03 mm²/KB (~30 KB/mm²) | OpenRAM Sky130 referencia |
| **SRAM 4 KB blokk** | ~0.12–0.15 mm² | OpenRAM Sky130 |
| **SRAM 16 KB blokk** | ~0.45–0.55 mm² | OpenRAM Sky130 |
| **SRAM 64 KB blokk** | ~1.7–2.0 mm² | OpenRAM Sky130 |
| **Nano core logika** (~9,100 std cell) | ~0.028–0.031 mm² | ISA-CIL-T0-hu.md becslés |
| **Rich core logika** (~80,000 std cell) | ~0.25 mm² | architecture-hu.md becslés |
| **Routing overhead** | ~25–35% | Általános Sky130 tapasztalat |

**Kulcs felismerés:** Az **SRAM a terület-domináns elem**, nem a logika. Ezért a core-szám és az SRAM-méret közötti trade-off a legfontosabb tervezési döntés.

### Chip terület-bontás

| Elem | Darab | Per-core SRAM | Terület (Sky130) |
|------|-------|-------------|-----------------|
| Rich core + mailbox | 6 | 16 KB | 6 × 0.75 mm² = 4.5 mm² |
| Nano core + mailbox | 16 | 4 KB | 16 × 0.18 mm² = 2.88 mm² |
| Secure Core | 1 | — | ~0.18 mm² |
| Mesh router (2D grid) | 1 | — | 0.02 mm² |
| Perifériák (OPI ctrl, USB, timer, GPIO) | — | — | 0.2 mm² |
| Routing overhead (~25%) | — | — | 1.95 mm² |
| **Összesen** | **23 core + 1 Secure** | **160 KB** | **~9.73 mm²** |
| **Maradék** | | | **~0.27 mm²** (tartalék routing/timing closure-hoz) |

### Külső memória interfész

A 152 KB on-chip SRAM a core-ok lokális cache-ének elég, de a program kód és a nagyobb adatstruktúrák **külső memóriáról** jönnek. A Sky130 I/O cellák ~50-100 MHz SDR-re képesek — ez meghatározza az interfész választást:

| Interfész | Latency @50MHz | Sávszélesség | Pin | Sky130 kompatibilis? |
|-----------|---------------|-------------|-----|---------------------|
| ~~QSPI~~ | 14-20 ciklus | 25 MB/s | 6 | Igen, de lassú |
| **OPI (Octal SPI)** | **6-10 ciklus** | **50 MB/s** | **11** | **Igen (SDR)** |
| ~~HyperRAM~~ | 6-13 ciklus | 200 MB/s | 12 | Nem (DDR signaling kell) |
| ~~DDR3~~ | 5-15 ciklus | 1-2 GB/s | ~40+ | Nem (túl gyors I/O) |

Az **OPI (Octal SPI)** a legjobb illeszkedés a Sky130 ~50 MHz-es I/O-jához: **fele latency** és **dupla sávszélesség** a QSPI-hez képest, de **nem igényel DDR signaling-ot**. A controller egyszerű (a QSPI kiterjesztése 8 adatvonalra), a terület-költsége minimális (~0.08 mm²).

Az OPI Flash, OPI PSRAM és OPI FRAM **egy megosztott buszra** kapcsolódik, **multiplexált chip select-tel** (2 pin → 2-to-4 on-chip dekóder → 4 eszköz):

```
                   Megosztott OPI busz (8 data + CLK)
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
     ┌────┴────┐              │                   │
     │ 2-to-4  │              │                   │
     │ dekóder │              │                   │
     │(on-chip)│              │                   │
     └─┬──┬──┬──┬─┘           │                   │
      CS0 CS1 CS2 CS3         │                   │
       │   │   │   │          │                   │
   ┌───┘   │   │   └───┐     │                   │
   ▼       ▼   ▼       ▼     │                   │
┌──────┐┌──────┐┌──────┐┌──────┐                  │
│ OPI  ││ OPI  ││ OPI  ││(jövő)│                  │
│Flash ││PSRAM ││FRAM  ││      │                  │
│kód,RO││adat, ││tartós││      │                  │
│      ││RW    ││      ││      │                  │
└──────┘└──────┘└──────┘└──────┘
```

A multiplexált CS 2 pin-nel **4 eszközt** kezel (1 tartalék a jövőre). A busz-ütközést a core-ok **prefetch buffer-rel** (64 byte kód előretöltés) minimalizálják — a kód fetch szekvenciális és előrejelezhető, így a busz legtöbbször szabad az adat hozzáférésekhez.

**Háromszintű tartós tárolás:**

| Szint | Memória | Tartós? | Írás latency | Endurance | Típikus tartalom |
|-------|---------|---------|-------------|-----------|-----------------|
| **1. FRAM** | OPI FRAM (256 KB – 4 MB) | **Igen** | **6-10 ciklus** (mint olvasás) | **10^12+ ciklus** | Actor state, journal, kulcsok, konfiguráció |
| **2. Flash partíció** | OPI Flash szabad része | **Igen** | ~1-100 ms (erase+program) | ~100K ciklus | Firmware backup, offline adatok, log archívum |
| **3. Host tárolás** | USB-n át | **Igen** | ~ms (hálózat-függő) | Korlátlan | Adatbázis, backup, szinkronizáció |

### Host kommunikáció: USB 1.1 FS

Az UART helyett **USB 1.1 Full Speed** (12 Mbps) — a Sky130 @50 MHz-en megvalósítható:

| | UART | **USB 1.1 FS** |
|--|------|---------------|
| Sávszélesség | 115.2 Kbps | **12 Mbps** (~100×) |
| Pin szám | 2 (TX, RX) | **2** (D+, D−) |
| Sky130 kompatibilis | Igen | **Igen** (FS PHY egyszerű) |
| Controller terület | ~0.01 mm² | ~0.1-0.2 mm² |
| Host oldal | USB-UART adapter kell | **Natív USB** — bármely PC/tablet |
| Tápellátás | Külön kell | **5V a kábelen** (opcionális) |
| Használat | Mailbox bridge, debug, firmware upload, host tárolás | Ugyanaz, de **100× gyorsabb** |

**Pin kiosztás** (ChipIgnite OpenFrame, 44 GPIO):

| Interfész | Pin szám |
|-----------|----------|
| Megosztott OPI busz (8 data + CLK) | 9 |
| CS multiplex (2-to-4 dekóder) | 2 |
| USB 1.1 FS (D+, D−) | 2 |
| Mailbox bridge (inter-chip) | 4 |
| GPIO / debug | 27 |
| **Összesen** | **44** |

### A core-ok száma konfigurálható

A **6R+17N+1S** a referencia konfiguráció, de az RTL **paraméterezhető** (`#NUM_RICH`, `#NUM_NANO`). Ugyanaz a design különböző arányokkal instanciálható a célpiac szerint:

| Konfiguráció | Rich | Nano | Secure | Összesen | Célpiac |
|-------------|------|------|--------|---------|---------|
| 2R + 34N + 1S | 2 | 34 | 1 | 37 | SNN kutatás, IoT szenzor farm |
| 4R + 26N + 1S | 4 | 26 | 1 | 31 | Neuron OS + worker mix |
| **6R + 17N + 1S** | **6** | **17** | **1** | **24** | **Referencia — alkalmazás + demó egyensúly** |
| 8R + 9N + 1S | 8 | 9 | 1 | 18 | Általános .NET alkalmazás (JokerQ-szerű) |

A konfigurációt **a szintézis előtt** kell megválasztani (nem futásidőben). Az FPGA-n a konfigurációs sweep (F6-FPGA) során szisztematikusan teszteljük a különböző arányokat.

### Miért éppen a 6R+17N+1S a referencia

**Az SRAM a terület-domináns elem, nem a logika.** A 6 Rich + 17 Nano + 1 Secure core logikája összesen ~2.1 mm² (6×0.25 + 17×0.031 + 0.06) — a 10 mm²-es chipnek ez csak ~21%-a. A maradék ~79% SRAM és routing. Ez azt jelenti:
- A core-ok **olcsók** (egy Nano core logikája ~0.031 mm²)
- A memória **drága** (16 KB SRAM ~0.5 mm²)
- A **sweet spot** a 4 KB/Nano + 16 KB/Rich — elég a TOS cache, lokális változók és frame-ek on-chip tartásához, a nagy adat QSPI PSRAM-ról jön

A maradék ~0.9 mm² felhasználása (F6-Silicon döntés):
- **Writable microcode SRAM** — firmware-frissíthető opkód-szemantika
- **Gated store buffer** (GC write barrier batch)
- **Tartalék** routing és timing closure-hoz

### Miért „ütős" — összehasonlítás hagyományos multi-core CPU-val

Ugyanaz a 10 mm² Sky130 terület. A RISC-V-nek **cache coherency kell** ha shared memory-t használ (Linux, .NET runtime):

**RISC-V konfigurációk 10 mm²-en (Sky130):**

| RISC-V konfig | Core terület | Coherency | L2 + periféria | Routing | Összesen | Maradék → extra RAM | Összes RAM |
|--------------|-------------|-----------|---------------|---------|----------|-------------------|-----------|
| **4 core** | 1.80 mm² | 0.75 mm² | 1.40 mm² | 0.99 mm² | 4.94 mm² | 5.06 mm² → ~150 KB | **~214 KB** |
| **6 core** | 2.70 mm² | 1.10 mm² | 1.40 mm² | 1.30 mm² | 6.50 mm² | 3.50 mm² → ~105 KB | **~169 KB** |
| **8 core** | 3.60 mm² | 1.50 mm² | 1.40 mm² | 1.63 mm² | 8.13 mm² | 1.87 mm² → ~56 KB | **~152 KB** |
| **12 core** | 5.40 mm² | 2.50 mm² | 1.40 mm² | 2.33 mm² | 11.63 mm² | **Nem fér el!** | — |

(Egy RV32IMC core ~0.15 mm² logika + 4KB L1 I-cache + 4KB L1 D-cache = ~0.45 mm²/core. A cache coherency a core-számmal szuperlineárisan nő.)

**Összehasonlítás a CLI-CPU Cognitive Fabric One-nal:**

| | **CLI-CPU 6R+17N+1S** | **RISC-V 4 core** | **RISC-V 8 core** |
|--|----------------------|------------------|------------------|
| **Core-ok** | **24** (6 Rich + 17 Nano + 1 Secure) | **4** | **8** |
| **On-chip RAM** | **152 KB** (privát, koherencia nélkül) | **~214 KB** (L1+L2+extra) | **~152 KB** (L1+L2+extra) |
| **Cache coherency területe** | **0 mm²** | **0.75 mm²** (a chip 7.5%-a) | **1.5 mm²** (a chip 15%-a) |
| **Core-okra fordított terület** | 7.3 mm² (73%) | 1.8 mm² (18%) | 3.6 mm² (36%) |
| **.NET futtatás** | **Natív CIL** | Interpreter (10-50× lassabb) vagy AOT (20-50MB bináris) | Ugyanaz |
| **Párhuzamos aktorok** | **24** (hw mailbox) | 4 (sw queue + lock) | 8 (sw queue + lock) |
| **Context switch** | **5-8 ciklus** | 500-2000 ciklus | 500-2000 ciklus |

**A kulcs szám:** a RISC-V **a chip területének 10-20%-át a cache coherency-re költi**. A CLI-CPU-n ez a terület **extra core-nak megy**, mert a shared-nothing architektúrában a koherencia probléma **nem létezik**. Ezért fér el 24 core 10 mm²-en, míg a RISC-V 4-8 core-nál megáll. A RAM mennyiségben hasonlóak (~150 KB), de a CLI-CPU-é **privát** (nincs coherency traffic), a RISC-V-é **megosztott** (coherency lassítja).

### Teljesítmény-összehasonlítás actor-alapú workload-okon

| Metrika | CLI-CPU (6R+17N @50MHz) | RISC-V 4-core (@50MHz, same die) | CLI-CPU előny |
|---------|------------------------|----------------------------------|---------------|
| **Actor üzenet/sec** | ~46M (23 core × ~2M/core, hardveres mailbox) | ~2M (szoftveres queue + lock + context switch) | **~23×** |
| **Üzenet latency** | ~10–20 ciklus (hardveres FIFO) | ~500–2000 ciklus (lock acquire + context switch) | **~50–100×** |
| **Context switch** | ~5–8 ciklus (TOS cache + PC) | ~500–2000 ciklus (register save/restore + TLB flush) | **~100×** |
| **Párhuzamos neuronok (SNN)** | 17 (1/Nano core, determinisztikus) | 4 (thread, nem-determinisztikus) | **4×** |
| **Skálázódás +1 core** | Lineáris | Szub-lineáris (Amdahl + coherency overhead) | **Fundamentális** |
| **Energia (event-driven)** | ~nJ/event (alvó core-ok, wake-on-mailbox) | ~μJ/event (aktív polling, cache traffic) | **~100–1000×** |
| **Determinizmus** | Garantált (nincs OoO, nincs preemption) | Nem garantált (cache timing, preemption) | **Abszolút** |
| **Izolálás** | Hardveres (privát SRAM, Secure Core) | Szoftveres (MMU, de Spectre/Meltdown) | **Erősebb** |

**Fontos:** az egy-core IPC-ben a RISC-V (különösen OoO változatban) gyorsabb. A CLI-CPU **nem az egy-core versenyben** nyer, hanem abban, hogy **ugyanazon a szilíciumon sokkal több hasznos, párhuzamos munkát végez** actor-alapú workload-okon, miközben determinisztikus és biztonságos marad.

### Neuron OS rétegek a chipen

| Réteg | Hol fut | Funkció |
|-------|---------|---------|
| **Neuron OS kernel** | Rich core #0 | Root supervisor, scheduler, capability registry, hot code loader |
| **Device driver aktorok** | Rich core #1 | UART, QSPI, GPIO, timer — crash → supervisor restart, nem kernel panic |
| **Alkalmazás supervisor** | Rich core #0 vagy #1 | App lifecycle, actor spawn/kill, supervision stratégiák |
| **Worker aktorok** (17 db) | Nano core-ok | SNN neuronok, IoT handlerek, filter pipeline, state machine-ek, bármi |
| **GUI aktorok** (jövő) | Rich + Nano mix | Framebuffer aktor (Rich), widget aktorok (Nano) — minden aktor, nincs „UI thread" |

A GUI is aktor-alapú: minden widget egy aktor, minden input event egy üzenet, a rendering egy pipeline aktor-lánc. Nincs globális állapot, nincs race condition. Ha egy widget crash-el, a supervisor újraindítja — a többi widget nem érzi.

### Referencia demók a chipen

| Demó | Core használat | Mit bizonyít |
|------|---------------|-------------|
| **Actor ping-pong throughput** | 17 Nano pár | Üzenet/sec benchmark — összehasonlítható RISC-V-vel |
| **SNN (Spiking Neural Network)** | 17 Nano (LIF/Izhikevich neuron) + 1 Rich coordinator | Lineáris skálázódás, determinizmus, event-driven energia |
| **IoT edge gateway** | 6 Rich (supervisor + protocol) + 17 Nano (handler) | Valós use-case, latency mérés, fault tolerance demó |
| **Akka.NET actor cluster** | 6 Rich (supervisor) + 17 Nano (worker) | C# kódból fordított actor rendszer, hardveresen futva |
| **Hot code loading** | Rich core-on aktor frissítés | Zero-downtime update, Erlang-stílusú |
| **Fault tolerance** | Worker crash → supervisor restart | „Let it crash" — a chip nem áll le, csak az aktor indul újra |

### Publikációs narratíva

A chip célja nem „még egy CPU", hanem **egy új kategória bizonyítéka**:

> *„A Cognitive Fabric One a világ első nyílt forráskódú, heterogén, actor-natív processzora. 24 core-jával + 1 Secure core-ral, cache coherency nélkül, ugyanazon a 10 mm² Sky130 szilíciumon 23× több actor üzenetet kezel másodpercenként, mint egy hagyományos 4-core RISC-V — miközben determinisztikus, hardveresen izolált, és lineárisan skálázódik. Ez nem gyorsabb CPU — ez egy új paradigma."*

## Blokk diagram (egymagos CLI-CPU, F6 single-core cél)

```
                         ┌─────────────────────────────────────────┐
                         │               CLI-CPU                   │
                         │                                         │
  ┌──────────────┐       │  ┌────────────────────────────────────┐ │
  │ QSPI Flash   │◄──────┼─►│         I$  (CIL bytecode cache)   │ │
  │ (kód)        │       │  │         4 KB, 2-way associative    │ │
  └──────────────┘       │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Prefetch Buffer (16 bájt)         │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Length Decoder                    │ │
                         │  │  (1. bájt → teljes opkód hossz)    │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  μop Cache (256 × 8 μop)           │ │
                         │  │  PC-alapú lookup                   │ │
                         │  └──────┬─────────────────┬───────────┘ │
                         │         │ hit             │ miss        │
                         │         │                 ▼             │
                         │         │  ┌──────────────────────┐     │
                         │         │  │  Hardwired Decoder   │──┐  │
                         │         │  │  (triviális opkódok) │  │  │
                         │         │  └──────────────────────┘  │  │
                         │         │  ┌──────────────────────┐  │  │
                         │         │  │  Microcode ROM/SRAM  │──┤  │
                         │         │  │  (komplex opkódok)   │  │  │
                         │         │  └──────────────────────┘  │  │
                         │         │                            ▼  │
                         │         │  ┌──────────────────────────┐ │
                         │         │  │  μop Sequencer           │ │
                         │         │  │  (fill → μop cache)      │ │
                         │         │  └───────────┬──────────────┘ │
                         │         │              │                │
                         │         └──────┬───────┘                │
                         │                │                        │
                         │                ▼                        │
                         │  ┌────────────────────────────────┐     │
                         │  │        Execute Stage           │     │
                         │  │  ┌──────┐ ┌──────┐ ┌────────┐  │     │
                         │  │  │ ALU  │ │ FPU  │ │ Branch │  │     │
                         │  │  │32/64 │ │R4/R8 │ │  Unit  │  │     │
                         │  │  └──────┘ └──────┘ └────────┘  │     │
                         │  │  ┌───────────────────────────┐ │     │
                         │  │  │   Stack Cache (TOS..TOS-7)│ │     │
                         │  │  └───────────────────────────┘ │     │
                         │  │  ┌───────────────────────────┐ │     │
                         │  │  │   Shadow RegFile (exc)    │ │     │
                         │  │  └───────────────────────────┘ │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────┐     │
                         │  │   Load/Store Unit              │     │
                         │  │   + Gated Store Buffer         │     │
                         │  │   + GC Write Barrier           │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────┐     │
                         │  │ D$ (heap + locals + eval-stack)│     │
                         │  │ 4 KB, kártyatábla bitekkel     │     │
                         │  └──────────────┬─────────────────┘     │
                         │                 │                       │
  ┌──────────────┐       │                 ▼                       │
  │ QSPI PSRAM   │◄──────┼───────── Memory Controller              │
  │ (heap+stack) │       │                                         │
  └──────────────┘       │                                         │
                         │  ┌────────────────────────────────┐     │
                         │  │   Metadata Walker Coproc.      │     │
                         │  │   (PE/COFF tábla feloldás)     │     │
                         │  └────────────────────────────────┘     │
                         │  ┌────────────────────────────────┐     │
                         │  │   GC Assist Unit               │     │
                         │  │   (bump alloc, card mark)      │     │
                         │  └────────────────────────────────┘     │
                         │  ┌────────────────────────────────┐     │
                         │  │   Exception Unwinder           │     │
                         │  │   (shadow regfile rollback)    │     │
                         │  └────────────────────────────────┘     │
                         └─────────────────────────────────────────┘
```

## Pipeline

A CLI-CPU **klasszikus 5-fokozatú in-order pipeline-t** használ, a stack-gép szemantikához igazítva:

```
 IF  → FETCH:     Prefetch bufferből bájtok, I$-hez QSPI backing
 ID  → DECODE:    Length decoder + hardwired/mikrokód elágazás
 EX  → EXECUTE:   ALU/FPU/Branch, stack cache-en dolgozik
 MEM → MEMORY:    Load/store, gated buffer, GC barrier
 WB  → WRITEBACK: Stack cache frissítés, PC update
```

Nincs superscalar, nincs out-of-order végrehajtás (F0–F6). Ez két okból tudatos döntés:

1. **Terület:** Sky130-on egy OoO mag magasabb terület-büdzsét igényelne, mint amire számíthatunk még ChipIgnite-on is. Az in-order pipeline kompakt.
2. **Determinizmus:** IoT és biztonsági profil egyaránt determinisztikus végrehajtási időt igényel. OoO és spekuláció Spectre-szerű oldalcsatornákat nyit, amit egy „biztonság-first" CIL CPU-n kerülni akarunk.

A **μop cache** viszont jelentősen csökkenti a dekódolási overhead-et a forró loopokon, tehát az effektív IPC ~1 marad, de alacsony energián.

## Memória modell

### Cím tér

A CLI-CPU 32-bites virtuális címteret használ, logikailag négy régióra osztva:

| Régió | Cím tartomány | Tartalom | Backing |
|-------|---------------|----------|---------|
| **CODE** | `0x0000_0000` – `0x3FFF_FFFF` | CIL bytecode + PE/COFF metaadat táblák | QSPI Flash, csak olvasható |
| **HEAP** | `0x4000_0000` – `0x7FFF_FFFF` | Managed objektum heap (GC) | QSPI PSRAM, olvas/ír |
| **STACK** | `0x8000_0000` – `0x8FFF_FFFF` | Evaluation stack spill + lokális változók + argumentumok + frame-ek | QSPI PSRAM |
| **MMIO** | `0xF000_0000` – `0xFFFF_FFFF` | Perifériák: UART, GPIO, timer, irq controller | On-chip |

### GC kártyatábla

A HEAP régióhoz tartozik egy **kártyatábla**: minden 512 bájt heap adatra 1 bit jelöli, hogy történt-e referencia-írás a régióba. A write barrier hardveresen frissíti. Az F4+ fázisban a GC mikrokód ennek alapján dönti el, melyik kártyát kell végigjárnia.

### Stack struktúra

A CLI-CPU-n a stack **háromszintű**:

1. **Top-of-Stack Cache (TOS cache)** — 8 db 32-bit regiszter a chip-en. A stack felső 8 eleme itt él. Minden ALU művelet ezen dolgozik, **nem nyúl RAM-hoz**.
2. **L1 D-cache** — 4 KB on-chip SRAM, spillezett stack frame-ek, lokális változók, heap hot line-ok.
3. **QSPI PSRAM** — a teljes stack backing, ~8 MB.

A TOS cache felé és felülről spillt automatikusan a hardver intéz. A programozó (és a fordító) számára **egyszerű, korlátlan mélységű stack** látszik.

### Frame felépítés

A CLI-CPU-n a CIL **a gépi kód** — nincs JIT, nincs interpreter, nincs köztes fordítás. Amit a Roslyn generál (method header + opkódok), azt a hardver **közvetlenül végrehajtja**. Ezért a frame struktúrát nem a hardver tervező dönti el szabadon, hanem **a Roslyn kimenete rögzíti**:

- A **method header** (`arg_count`, `local_count`, `max_stack`) meghatározza a frame méretét
- Az **opkódok** (`ldarg.N`, `ldloc.N`, `stloc.N`) indexelik a slotokat
- A hardver feladata: a header-ből **kiszámítani a fizikai SRAM címeket**

Ez különbözik a hagyományos .NET-től, ahol a JIT szabadon dönthet (regiszterbe teszi a lokálist, átrendezi a frame-et, inline-ol). A CLI-CPU-n ilyen szabadság nincs.

### Hardveres frame layout

A `call` mikrokód a method header-ből kiszámítja a frame méretét, és az SP-t tolja. A szimulátor (`TCpu.cs`) és a hardver (F2+ RTL) **azonos SRAM layout-ot** használ — a szimulátor `byte[] FSram` tömbje byte-ról byte-ra megegyezik a hardver STACK SRAM-jával.

**Frame header: 12 byte**

```
 Offszet  Méret  Mező
 +0       4      ReturnPC       (int32 LE, -1 = root frame)
 +4       4      PrevFrameBase  (int32 LE, -1 = root frame)
 +8       1      ArgCount       (byte, 0..16)
 +9       1      LocalCount     (byte, 0..16)
 +10      2      reserved       (alignment)
```

**Teljes frame layout a SRAM-ban:**

```
 Stack SRAM (16 KB Nano / 64-256 KB Rich):

 ┌──────────────────────────────────────────────────────────┐
 │                                                          │
 │  Frame 0 (root):  Add(a, b) — 2 arg, 0 local             │
 │  ┌────────────────────────────────────────────────────┐  │
 │  │ [FP₀+0]   ReturnPC = -1 (root)          │  4 byte  │  │
 │  │ [FP₀+4]   PrevFrameBase = -1 (root)     │  4 byte  │  │
 │  │ [FP₀+8]   ArgCount=2, LocalCount=0      │  4 byte  │  │
 │  │ ─ ─ ─ ─ header vége (12 byte) ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₀+12]  arg[0] = 2                    │  4 byte  │  │
 │  │ [FP₀+16]  arg[1] = 3                    │  4 byte  │  │
 │  │ ─ ─ ─ ─ args vége ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₀+20]  eval[0] (a+b eredmény)        │  4 byte  │  │
 │  └────────────────────────────────────────────────────┘  │
 │  Frame méret: 12 + 2×4 + 0×4 = 20 byte (+ eval stack)    │
 │                                                          │
 │  Frame 1 (callee):  Gcd(a, b) — 2 arg, 1 local           │
 │  ┌────────────────────────────────────────────────────┐  │
 │  │ [FP₁+0]   ReturnPC = (call utáni opkód) │  4 byte  │  │
 │  │ [FP₁+4]   PrevFrameBase = FP₀           │  4 byte  │  │
 │  │ [FP₁+8]   ArgCount=2, LocalCount=1      │  4 byte  │  │
 │  │ ─ ─ ─ ─ header vége (12 byte) ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₁+12]  arg[0] = 48                   │  4 byte  │  │
 │  │ [FP₁+16]  arg[1] = 18                   │  4 byte  │  │
 │  │ ─ ─ ─ ─ args vége ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₁+20]  local[0] = 0                  │  4 byte  │  │
 │  │ ─ ─ ─ ─ locals vége ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │          │  │
 │  │ [FP₁+24]  eval[0]                       │          │  │
 │  │ [FP₁+28]  eval[1]                       │          │  │
 │  │ [FP₁+32]  eval[2]                       │          │  │
 │  └────────────────────────────────────────────────────┘  │
 │  Frame méret: 12 + 2×4 + 1×4 = 24 byte (+ eval stack)    │
 │                                                          │
 │  [szabad SRAM]                                           │
 │                                                          │
 └──────────────────────────────────────────────────────────┘
 SP ──► felfelé nő, a következő szabad byte-ra mutat
```

**Cím számítás** (a `call` mikrokód beállítja a `frame_base` és `arg_count` regisztereket):

```
 ldarg.N   →  SRAM[frame_base + 12 + N×4]
 starg.N   →  SRAM[frame_base + 12 + N×4]
 ldloc.N   →  SRAM[frame_base + 12 + arg_count×4 + N×4]
 stloc.N   →  SRAM[frame_base + 12 + arg_count×4 + N×4]
 eval push →  SRAM[SP] = val; SP += 4
 eval pop  →  SP -= 4; val = SRAM[SP]
```

### Kapacitás

```
 Fibonacci(20) rekurzív: 21 frame × ~16 byte = ~336 byte
 Gcd iteratív:           1 frame × ~28 byte  = ~28 byte
 Worst case (16 arg, 16 local, 64 eval): 12 + 16×4 + 16×4 + 64×4 = 396 byte

 16 KB Nano SRAM-ban:
   - Tipikus frame (~20 byte): ~800 frame mélység ← bőven elég
   - Worst case frame (396 byte): ~41 frame mélység ← szűkös, de ritka
```

### Szimulátor = hardver modell

A szimulátor (`TCpu.cs`) az SRAM refaktor után **azonos belső állapotot** tart, mint a hardver:

| Elem | Szimulátor | Hardver (F2+ RTL) |
|---|---|---|
| SRAM | `byte[] FSram` (16 KB) | Per-core SRAM (16 KB) |
| SP | `int FSp` | SP regiszter |
| Frame base | `int FFrameBase` | FP regiszter |
| `ldarg.1` | `SramReadInt32(FFrameBase + 12 + 1×4)` | `SRAM[FP + 12 + 1×4]` |
| Frame méret | Header-ből számított (változó) | Header-ből számított (változó) |
| Allokáció | `FSp += frameSize` | `SP += frameSize` |
| Debug | `SramSnapshot()` → byte[] | Cocotb: SRAM dump |

Az F2 RTL cocotb tesztjei a szimulátor `SramSnapshot()` kimenetét **byte-ról byte-ra** összehasonlíthatják a Verilog SRAM tartalmával.

**A `call` mikrokód szekvenciája:**
1. Header olvasás a target RVA-ról (arg_count, local_count, code_size validáció)
2. CallDepthExceeded ellenőrzés (max 512)
3. Frame méret számítás: `12 + arg_count×4 + local_count×4`
4. SramOverflow ellenőrzés: `SP + frame_size > SRAM_SIZE`
5. Argumentumok pop-olása a caller eval stack-jéről (fordított sorrendben)
6. Frame header írása: ReturnPC, PrevFrameBase, ArgCount, LocalCount
7. Args írása az SRAM-ba
8. Locals nullázása
9. SP, FrameBase, ArgCount, LocalCount regiszterek frissítése
10. PC beállítása a callee body első byte-jára (header után)

**A `ret` mikrokód szekvenciája:**
1. Return value pop-olása a callee eval stack-jéről (ha van)
2. Root frame ellenőrzés (CallDepth == 1 → Halt)
3. PrevFrameBase, ReturnPC olvasása az SRAM-ból
4. SP visszaállítása a frame_base-re (a callee SRAM-ja felszabadul)
5. FrameBase, ArgCount, LocalCount visszaállítása a caller frame-ből
6. Return value push-olása a caller eval stack-jére
7. PC visszaállítása a mentett ReturnPC-re
3. `frame_base` és `arg_count` visszaállítása a caller értékeire
4. Return value push-olása a **caller** eval stack-jére
5. PC visszaállítása a mentett return PC-re

## Dekódolási stratégia

Részletesen lásd `ISA-CIL-T0-hu.md`, de a stratégia magja:

### Hossz-dekóder

A CIL változó hosszú utasításai **első bájt alapján egyértelműen determinisztikusak** (kivéve a `switch` opkódot, ami a 2. bájttól származtatja a hosszát). Egy 256 bejegyzéses ROM-ban van az első-bájt → hossz tábla:

```
0x00 (nop)      → 1 bájt
0x02 (ldarg.0)  → 1 bájt
0x06 (ldloc.0)  → 1 bájt
...
0x1F (ldc.i4.s) → 2 bájt
0x20 (ldc.i4)   → 5 bájt
...
0x2B (br.s)     → 2 bájt
0x38 (br)       → 5 bájt
...
0xFE (prefix)   → 2 + (ROM2 lookup szerint)
...
```

Prefix-es opkódokra (0xFE) egy második 256 bejegyzéses ROM is van.

### Hardwired vs mikrokódolt osztályozás

~75% hardwired, ~25% mikrokódolt. A hardwired csoport a következő opkód családokat tartalmazza:

- Triviális stack: `nop`, `dup`, `pop`
- Konstans: `ldc.i4.*`, `ldc.i8`, `ldc.r4`, `ldc.r8`
- Lokálisok / argumentumok: `ldloc.*`, `stloc.*`, `ldarg.*`, `starg.*`
- Egyszerű ALU: `add`, `sub`, `and`, `or`, `xor`, `neg`, `not`, `shl`, `shr`, `shr.un`
- Összehasonlítás: `ceq`, `cgt*`, `clt*`
- Rövid elágazás: `br.s`, `brtrue.s`, `brfalse.s`, `beq.s`, stb.
- Egyszerű memória: `ldind.*`, `stind.*`

A mikrokódolt csoport:

- `mul`, `div`, `rem` (iteratív implementáció)
- 64-bit integer aritmetika
- FP aritmetika (FPU sequencer)
- `call`, `callvirt`, `ret`
- `newobj`, `newarr`, `box`, `unbox`
- `isinst`, `castclass`
- `ldfld`, `stfld`, `ldelem.*`, `stelem.*`
- `ldtoken`, `ldftn`, `ldvirtftn`
- `throw`, `rethrow`, `leave`, `endfinally`
- `switch`

## μop-ok

A CLI-CPU belső mikro-utasítás formátuma (F2-ben véglegesítendő, előzetes vázlat):

```
 Mező     | Méret | Leírás
──────────┼───────┼─────────────────────────────────────────
 OP       | 6 bit | mikrokód opcode (pl. TOS_ADD, LOAD, BRANCH)
 DST      | 4 bit | cél: TOS, TOS-1, ..., LOCAL[i], ARG[i]
 SRC1     | 4 bit | forrás 1
 SRC2     | 4 bit | forrás 2
 FLAGS    | 6 bit | uses_sp, writes_flags, last_of_op, trap_enable, ...
 IMM      | 8 bit | opcionális immediate (a CIL bájtokból)
──────────┼───────┼─────────────────────────────────────────
           32 bit
```

Egy CIL `add` = 1 μop (`OP=TOS_ADD, DST=TOS-1, SRC1=TOS-1, SRC2=TOS, FLAGS=pop1 | last`).

Egy CIL `callvirt` = ~8-10 μop (lásd `ISA-CIL-T0-hu.md` részletes trace).

## Kivételkezelés

**Shadow Register File + Checkpoint** (Transmeta-inspiráció):

- A `try` belépéskor a mikrokód egy `SAVE_CHECKPOINT` μop-ot emittál, amely a TOS cache teljes tartalmát, a SP-t, a BP-t, a PC-t **egy ciklus alatt** átmásolja egy árnyék regiszter file-ba.
- A `try` normál kilépéskor (`leave`) a checkpoint eldobható (`DROP_CHECKPOINT` μop).
- `throw` esetén a mikrokód végigjárja a metódus exception tábláját (a PE/COFF metaadatból), megkeresi a megfelelő `catch`/`filter` handlert, és ha talál:
  - `RESTORE_CHECKPOINT` μop visszaállítja a TOS cache-t
  - A throwed object referencia kerül a TOS-ra
  - PC ugrik a handler első opkódjára
- Ha nincs handler a metódusban, a mikrokód `ret`-et emittál a caller felé és megismétli a keresést.

Ez **drámaian gyorsabb**, mint a hagyományos unwind-tábla stepping, mert a mikrokód a hardveres shadow file-t használja, nem kell a stack-et sorban bontania.

## GC (Garbage Collection)

**Generational bump-allocator + stop-the-world mark-sweep** a legegyszerűbb implementáció, ami F4-ben lép be.

### Allokáció

A `newobj` / `newarr` / `box` mikrokódja:

```
 TOS_SIZE  ← objektum_méret (a típusból vagy a tömb hosszából)
 NEW_ADDR  ← HEAP_TOP
 HEAP_TOP ← HEAP_TOP + TOS_SIZE
 if HEAP_TOP > HEAP_LIMIT → TRAP #GC
 store type_ptr at NEW_ADDR
 TOS ← NEW_ADDR
```

~5-8 ciklus, ha nincs GC trap. GC trap esetén a mikrokód meghívja a GC szubrutint (ami szintén mikrokódban vagy egy kis „house-keeping" koprocesszoron fut).

### Write barrier

A `stfld` mikrokódja (ha a mező reference típusú):

```
 STORE    TOS, [TOS-1 + field_offset]
 CARD     ← (TOS-1 + field_offset) >> 9    ; kártya index
 CARD_TBL[CARD] ← 1                        ; kártya jelölés
```

Egyetlen plusz ciklus az egyszerű `stfld`-hez képest. **Hardveresen ingyen** a managed memory safety-hez képest.

### Gated Store Buffer

Az F4+ mikroarchitektúrában a write barrier kártyatábla-frissítései egy **kis store buffer-ben** gyűjtődnek, és csak commit pontoknál (metódus kilépés, `volatile.` prefix) íródnak vissza a D-cache-be. Ez a Transmeta-inspirált optimalizáció a write barrier amortizált költségét **~0.3 ciklusra** csökkenti.

## Metaadat Walker

A CIL metaadat-tokenek (pl. `MethodDef 0x06000042`) a PE/COFF metaadat táblákba mutatnak. A CLI-CPU-n ezek feloldása a **Metadata Walker koprocesszor** feladata (F4-től):

1. A CIL opkód a tokent push-olja egy kis FIFO-ba
2. A Walker elkezdi a PE/COFF táblák járását (Method table, Type table, Field table, stb.)
3. A végeredmény egy **közvetlen pointer** az objektum típusleírójára / metódus belépési pontjára / mező offszetjére
4. A Walker egy **kis TLB-t** használ a gyakran előforduló tokenek gyorsítására

**Fontos:** ez NEM változtatja meg a CIL bájtokat a memóriában. A walker csak egy „címfeloldó szolgáltatás", a kód változatlanul fut tovább.

## Prior art és átvett technikák

A CLI-CPU nem az első bytecode-natív CPU, és érdemes megtanulni mindegyik elődtől.

### Sun picoJava (1997, 1999)

**Mit csinált jól:** Természetes stack-gép Java bytecode-hoz. Top-of-Stack Caching a felső ~4 elemre. Hardveres tömb-bounds-check. Egyszerű, elegáns mikroarchitektúra.

**Miért bukott el:** A sima ARM + HotSpot JIT gyorsabb volt, és ahogy a félvezető-skálázás évtizedeken át tartott, az általános célú CPU + szoftveres runtime nem-várt mértékben utolérte a dedikált hardvert. A Sun nem tudta versenyképesen árazni.

**Mit veszünk át:**
- **Top-of-Stack Caching** — alapvető, átvéve. 4–8 elem.
- **Hardveres tömb-bounds-check** — a biztonság-first profilhoz.
- **Elegáns egyszerűség** — nem próbálunk OoO-t vagy superscalar-t.

### ARM Jazelle (2001)

**Mit csinált jól:** Egy ARM magon belüli **Java bytecode végrehajtási mód** (nem külön CPU). Az ARM decoder egy bit-kapcsolóval átkapcsol Java bytecode-ra, és a legfontosabb ~140 opkódot közvetlenül hardveresen futtatja. A komplex opkódok trap-elnek szoftveres handlerbe.

**Miért érdekes:** Ez a **hibrid** modell — nem akarunk minden opkódot hardverben megvalósítani, a ritka / komplex opkódoknál trap-elhetünk mikrokódba vagy egy kis koprocesszorra.

**Mit veszünk át:**
- **Ritka opkódok trap-elése** a metadata walker-re és a GC koprocesszorra, nem teljes mikrokód ROM implementáció.
- **Mod kapcsoló** — az F4+ verzióban lehet egy „CIL-T0 kompatibilitási mód" és egy „teljes CIL mód".

### Transmeta Crusoe / Efficeon (2000, 2003)

**Mit csinált jól:** Belső VLIW mag, **szoftveres** x86 → VLIW fordítás (Code Morphing Software), trace cache, shadow register file + checkpoint rollback, gated store buffer, writable microcode, agresszív power-gating.

**Miért bukott el:** A szoftveres DBT (Dynamic Binary Translation) warmup lassú volt, az Intel Pentium M (Dothan) megérkezése elvette a fogyasztási USP-t, a szoftveres komplexitás óriási kockázat volt.

**Mit veszünk át (és mit NEM):**

| Technika | Átvesszük? | Hol |
|----------|-----------|-----|
| Code Morphing Software (DBT) | **NEM** | Ellentmond az „CIL = natív ISA" alapelvnek |
| Belső VLIW mag | **NEM** | Stack-gép természetesebb CIL-hez |
| μop cache / trace cache | **IGEN** | F4+, forró loopokon energia-spórolás |
| Shadow register file + checkpoint | **IGEN** | F5 exception handling |
| Gated store buffer | **IGEN** | F4 GC write barrier batch |
| Writable microcode SRAM | **IGEN** | F6 ChipIgnite, firmware-frissíthető opkódok |
| Agresszív power-gating | **IGEN** | F0-tól végig, IoT profil |

### RISC-V

**Nem elődünk**, de referencia architektúra. A RISC-V egy tisztán regiszter-alapú RISC, ami pont az **ellentéte** a stack-gép CLI-CPU-nak. Viszont:

- **OpenLane2 / Sky130 / Caravel tooling** — ezt a RISC-V közösségtől tanuljuk
- **Nyílt forrású szellem** — minden RTL, doksi, teszt public lesz
- **Custom extension pattern** — Ha valaha kellene egy RISC-V mag a CLI-CPU mellé (pl. a GC koprocesszornak vagy a boot-loadernek), ott egy minimális RV32I mag jó választás

## Power management

A CLI-CPU **négy power domain**-re osztott (F6 cél):

1. **Core domain** — fetch, decode, execute, stack cache. Mindig él, amíg a CPU dolgozik.
2. **FPU domain** — csak FP opkód észlelésekor kap áramot. Integer loopokon hideg.
3. **GC / metadata domain** — a walker koprocesszor és a GC assist. Csak allokáció vagy metaadat miss esetén aktív.
4. **I/O domain** — QSPI kontrollerek, UART, GPIO. WFI (wait-for-interrupt) alatt lehalkul.

Clock-gating minden domainben, power-gating a 2., 3., 4. domainben.

## Silicon-grade security

Ez a szekció a CLI-CPU biztonsági architektúráját tárgyalja **az architektúra szemszögéből**. A teljes biztonsági modellt, threat model-t, támadás-immunitási táblázatot, formális verifikáció tervet és tanúsítási útvonalakat külön dokumentum tartalmazza: lásd [`docs/security-hu.md`](security-hu.md).

### A CLI-CPU biztonsági alapelve

> **A memory safety, type safety és control flow integrity nem szoftveres absztrakció, hanem fizikai tulajdonság a szilíciumban.**

Ez a megfogalmazás nem marketing, hanem **architektúra-tervezési következmény**. A jelenlegi mikroarchitektúra a biztonságot **nem extra rétegként** adja hozzá, hanem a tervezési alapelvekből **implicit** módon következik:

1. **Stack-gép modell** → nincs ROP gadget, mert a visszatérési cím nem a user stack-en van, hanem a frame pointer hardveres szerkezetében
2. **Változatlan kód a memóriában** → nincs JIT, nincs AOT patching, ezért nincs JIT spraying, nincs self-modifying code
3. **Shared-nothing multi-core** → nincs cross-core side-channel, nincs false sharing covert channel, nincs cache coherency-n alapuló támadás
4. **In-order pipeline, nincs spekuláció** → immunis a Spectre/Meltdown teljes családra
5. **Harvard memória modell** → a CODE régió QSPI flash-en, fizikailag R/O — nem lehet shellcode-ot injektálni
6. **CIL verified code szemantika** → a type safety és a memory safety az ISA szinten beépített

### Hardveres ellenőrzések — a jelenlegi ISA már tartalmazza

| Ellenőrzés | Hol | Trap | Fázis |
|-----------|-----|------|-------|
| Stack overflow/underflow | Minden push/pop | `STACK_OVERFLOW` / `STACK_UNDERFLOW` | **F3** |
| Lokális/argumentum index bounds | `ldloc`, `stloc`, `ldarg`, `starg` | `INVALID_LOCAL` / `INVALID_ARG` | **F3** |
| Branch target validation | `br*` | `INVALID_BRANCH_TARGET` | **F3** |
| Call target validation | `call` | `INVALID_CALL_TARGET` | **F3** |
| Division by zero | `div`, `rem` | `DIV_BY_ZERO` | **F3** |
| Call depth limit | `call` | `CALL_DEPTH_EXCEEDED` | **F3** |
| Invalid opcode | Dekóder | `INVALID_OPCODE` | **F3** |
| Array bounds check | `ldelem`, `stelem` | `ARRAY_INDEX_OUT_OF_RANGE` | F5 |
| Null reference check | `ldfld`, `stfld`, `callvirt` | `NULL_REFERENCE` | F5 |
| Type check (isinst/castclass) | `isinst`, `castclass` | `INVALID_CAST` | F5 |
| GC write barrier | Reference-type `stfld`/`stelem.ref` | — (mellékhatás) | F5 |

**Fontos megjegyzés:** az F3 Tiny Tapeout chipen **már az alapvető biztonsági ellenőrzések többsége élesben van**. Ez azt jelenti, hogy a CLI-CPU első valódi szilíciuma **már olyan biztonsági tulajdonságokkal rendelkezik, amikkel egyetlen szabványos CPU sem**.

### Támadás-osztályok, amelyekre immunis a CLI-CPU

Rövid összefoglaló (a részletes táblázat a [`docs/security-hu.md`](security-hu.md) fájlban):

| Támadás-család | Státus |
|----------------|--------|
| Buffer overflow (CWE-119, 120, 121, 122) | **Kizárva** (hardveres bounds check) |
| Use-after-free (CWE-416) | **Kizárva** F5-től (GC hardveresen) |
| Type confusion (CWE-843) | **Kizárva** F5-től (hardveres type check) |
| Format string (CWE-134) | **Kizárva** (nincs C string) |
| ROP / JOP | **Kizárva** (hardveres CFI) |
| Shellcode injection (CWE-94) | **Kizárva** (CODE R/O) |
| JIT spraying | **Kizárva** (nincs JIT) |
| Spectre v1/v2/v4, Meltdown, L1TF, MDS | **Kizárva** (nincs spekuláció) |
| Cross-core side-channel | **Kizárva** (shared-nothing) |
| False sharing covert channel | **Kizárva** (nincs shared cache) |
| GC race condition | **Kizárva** (per-core privát heap) |
| Lock deadlock | **Kizárva** (nincs shared lock) |

### Formális verifikáció lehetősége

A CLI-CPU **Nano core** 48 opkódos ISA-ja **gyakorlatilag kisebb, mint a seL4 microkernel** (~10 000 sor C), amit a UNSW csapata 15+ év munka alatt **formálisan bizonyított** Coq + Isabelle eszközökkel.

Ez azt jelenti, hogy a CLI-CPU **formális verifikációja megvalósítható** — nem egyszerű, nem olcsó, de **nem is lehetetlen**, és **sem az x86, sem az ARM, sem a RISC-V teljes extension-készletével nem megvalósítható**.

A formális verifikáció részleteiért lásd a [`docs/security-hu.md`](security-hu.md) **„Formális verifikáció"** szekcióját.

### Kapcsolódó projektek

- **CHERI** (Cambridge) — legközelebbi rokon, capability-based security hardveresen; érdemes akadémiai partner lehet
- **seL4** — formálisan verifikált microkernel, tanulandó precedens
- **CompCert** — formálisan verifikált C fordító, a `cli-cpu-link` tool hosszú távú célja hasonló lehet
- **Project Everest** (Microsoft Research) — formálisan verifikált HTTPS/TLS stack F\*-ban, Microsoft-támogatás lehetősége

## Kétpályás pozicionálás

A CLI-CPU biztonsági profilja a **Cognitive Fabric** (programozható kognitív szubsztrátum) narratíva **mellett** egy második piaci pályát is megnyit:

- **Pálya 1 — „Cognitive Fabric"** — AI kutatóknak, actor rendszereknek, neurális háló szimulációnak, multi-agent rendszereknek. Hosszú távú vízió.
- **Pálya 2 — „Trustworthy Silicon"** — regulated industries-nek: automotive (ISO 26262), aviation (DO-178C), medical (IEC 62304), critical infrastructure (IEC 61508 SIL-3/4), AI safety watchdog chipek, confidential computing. Rövid-közép távú bevételi lehetőség, magas árréssel.

**Ugyanaz a hardver, két különböző piaci szegmens.** Részletek és konkrét cél-piacok a [`docs/security-hu.md`](security-hu.md) **„Mit jelent ez a projekt gyakorlati célja szempontjából"** szekciójában.

## Következő lépés

A `ISA-CIL-T0-hu.md` dokumentum adja a konkrét CIL-T0 subset teljes opkód-specifikációját, kódolási táblákat, stack-effekteket, ciklusszámokat és trap feltételeket. **Ez az F1 C# szimulátor alapja** — minden ottani tesztnek közvetlenül hivatkoznia kell az ISA-CIL-T0 spec egy-egy pontjára, és a property-based tesztek már most megalapozzák a későbbi formális verifikációt.

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
