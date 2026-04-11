# CLI-CPU — Architektúra Áttekintés

Ez a dokumentum a CLI-CPU **mikroarchitektúráját** írja le magas szinten: a stack-gép modellt, a pipeline-t, a memória térképet, a dekódolási stratégiát, a GC és kivételkezelés hardveres támogatását, valamint az elődprojektek (picoJava, Jazelle, Transmeta) közül átvett technikákat.

> **Megjegyzés:** Ez az architektúra fokozatosan épül fel az F0–F7 fázisokban. Az itt leírt teljes funkciókészlet **F6-ra** készül el (eFabless ChipIgnite, multi-core). A **Tiny Tapeout (F3)** csak az egymagos CIL-T0 subset-et valósítja meg, amit egy külön dokumentum (`ISA-CIL-T0.md`) ír le.

## Stratégiai pozicionálás: Cognitive Fabric

A CLI-CPU **nem klasszikus bytecode CPU-ként** pozicionálja magát, mint annak idején a Sun picoJava vagy az ARM Jazelle. Azt az utat **már megpróbálták, és megbukott**: a szoftveres JIT + hagyományos CPU olcsóbb és gyorsabb lett, mint a dedikált bytecode hardver. Ugyanezt az utat megismételni **nem lenne értelmes**.

Ehelyett a CLI-CPU egy **programozható kognitív szubsztrátum** — sok kis, független CIL-natív core, amelyek **üzenet-alapú kommunikációval** egy heterogén, eseményvezérelt hálózatot alkotnak. Minden core egy **teljes CIL programot** futtat saját lokális állapottal; a core-ok **mailbox FIFO-kon keresztül** beszélnek egymással, nincs megosztott memória, nincs cache koherencia protokoll, nincs lock contention. A használati mód a programtól függ: egy chip lehet **Akka.NET actor cluster**, **programozható spiking neural network**, **multi-agent szimuláció**, vagy **event-driven IoT edge**.

### Miért más ez, mint a létező megoldások

| Rendszer | Csomópont programozható? | Hardveres? | Nyílt? | .NET natív? |
|---------|--------------------------|------------|--------|-------------|
| Intel Loihi 2 | ❌ rögzített LIF neuron variánsok | ✓ | ❌ | ❌ |
| IBM TrueNorth | ❌ rögzített LIF | ✓ | ❌ | ❌ |
| BrainChip Akida | ❌ MetaTF-ből fordított fix modell | ✓ | ❌ | ❌ |
| GrAI Matter Labs GrAI-1 | ❌ fix | ✓ | ❌ | ❌ |
| SpiNNaker 2 (Manchester) | ✓ C/C++ ARM magokon | ✓ | részben | ❌ |
| Akka.NET / Orleans | ✓ teljes C#/F# | ❌ szoftveres | ✓ | ✓ |
| Erlang BEAM | ✓ Erlang | ❌ szoftveres | ✓ | ❌ |
| **CLI-CPU (Cognitive Fabric)** | **✓ teljes CIL** | **✓** | **✓** | **✓** |

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
  ┌──────────────────────────────────────────────────────────────┐
  │                    CLI-CPU Cognitive Fabric (F4)             │
  │                                                              │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │  │  Core 0      │  │  Core 1      │  │  Core 2      │  │  Core 3      │
  │  │              │  │              │  │              │  │              │
  │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │  │  CIL-T0      │
  │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │  │  Pipeline    │
  │  │              │  │              │  │              │  │              │
  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │
  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │  │  │ SRAM   │  │
  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │  │  │ 16 KB  │  │
  │  │  │ privát │  │  │  │ privát │  │  │  │ privát │  │  │  │ privát │  │
  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │
  │  │              │  │              │  │              │  │              │
  │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │  │ inbox FIFO   │
  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │  │ outbox FIFO  │
  │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │  │ Sleep/Wake   │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
  │         │                 │                 │                 │        │
  │  ═══════╧═════════════════╧═════════════════╧═════════════════╧═══════ │
  │                         Shared Bus (4-port arbiter)                    │
  │                                   │                                    │
  │              ┌────────────────────┼────────────────────┐               │
  │              ▼                    ▼                    ▼               │
  │    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │
  │    │ QSPI Flash ctrl │  │   UART / GPIO   │  │  Timer / IRQ    │      │
  │    │   (kód, R/O)    │  │   (I/O interf.) │  │  (global clock) │      │
  │    └─────────────────┘  └─────────────────┘  └─────────────────┘      │
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

Az F5 fázistól a CLI-CPU **heterogén multi-core** architektúrára vált, analóg módon az ARM **big.LITTLE**, Apple **P-core + E-core**, és Intel **Alder Lake P+E** megközelítéseihez, csak a CLI világra alkalmazva. Egyetlen chipen **kétféle core** él együtt:

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
F3 (Tiny Tapeout)  ─►  Nano core 1×  ──┐
                                        │
F4 (FPGA multi-core) ─►  Nano core 4×  ─┤
                                        │
F5 (FPGA Rich)     ─►  Rich core 1×  ──┤
                                        │
                                        ▼
F6 (ChipIgnite MPW) ─►  Heterogén: Rich 2-4× + Nano 32-48×
                        + floorplan + Roslyn [RunsOn] + bridge
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
| F6 | ChipIgnite (Sky130 vagy IHP MPW) | **32–48** | **2–4** | Valódi heterogén szilícium |
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

### Miért nem 3 vagy több core típus

Elméletileg lehetne „Micro" (még kisebb, csak 16 opkód) és „Mega" (Rich + több cache) is — de ez **bonyolítja a programozási modellt** és **a floorplan tervezést**. A kereskedelmi példák (Apple, ARM, Intel) **mind** pontosan 2 core típust használnak, és ez a sweet spot. A CLI-CPU is **2 core típusnál** marad: Nano és Rich.

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
                         │  │  μop Cache (256 × 8 μop) ◄────────┐│ │
                         │  │  hit? ──► kikapcsolt dekóder      ││ │
                         │  └──────────────┬─────────────────┬──┘│ │
                         │                 │ miss            │   │ │
                         │                 ▼                 │   │ │
                         │  ┌──────────────────────┐        │   │ │
                         │  │  Hardwired Decoder   │──┐     │   │ │
                         │  │  (triviális opkódok) │  │     │   │ │
                         │  └──────────────────────┘  │     │   │ │
                         │  ┌──────────────────────┐  │     │   │ │
                         │  │  Microcode ROM/SRAM  │──┤     │   │ │
                         │  │  (komplex opkódok)   │  │     │   │ │
                         │  └──────────────────────┘  │     │   │ │
                         │                            ▼     │   │ │
                         │  ┌────────────────────────────┐  │   │ │
                         │  │    μop Sequencer           │──┘   │ │
                         │  └──────────────┬─────────────┘      │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │        Execute Stage           │  │ │
                         │  │  ┌──────┐ ┌──────┐ ┌────────┐  │  │ │
                         │  │  │ ALU  │ │ FPU  │ │ Branch │  │  │ │
                         │  │  │32/64 │ │R4/R8 │ │  Unit  │  │  │ │
                         │  │  └──────┘ └──────┘ └────────┘  │  │ │
                         │  │  ┌───────────────────────────┐ │  │ │
                         │  │  │   Stack Cache (TOS..TOS-7)│ │  │ │
                         │  │  └───────────────────────────┘ │  │ │
                         │  │  ┌───────────────────────────┐ │  │ │
                         │  │  │   Shadow RegFile (exc)    │ │  │ │
                         │  │  └───────────────────────────┘ │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │   Load/Store Unit              │  │ │
                         │  │   + Gated Store Buffer         │  │ │
                         │  │   + GC Write Barrier           │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │ D$ (heap + locals + eval-stack) │  │ │
                         │  │ 4 KB, kártyatábla bitekkel     │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
  ┌──────────────┐       │                 ▼                    │ │
  │ QSPI PSRAM   │◄──────┼───────── Memory Controller ──────────┘ │
  │ (heap+stack) │       │                                        │
  └──────────────┘       │                                        │
                         │  ┌────────────────────────────────┐    │
                         │  │   Metadata Walker Coproc.      │    │
                         │  │   (PE/COFF tábla feloldás)     │    │
                         │  └────────────────────────────────┘    │
                         │  ┌────────────────────────────────┐    │
                         │  │   GC Assist Unit               │    │
                         │  │   (bump alloc, card mark)      │    │
                         │  └────────────────────────────────┘    │
                         │  ┌────────────────────────────────┐    │
                         │  │   Exception Unwinder           │    │
                         │  │   (shadow regfile rollback)    │    │
                         │  └────────────────────────────────┘    │
                         └─────────────────────────────────────────┘
```

## Pipeline

A CLI-CPU **klasszikus 5-fokozatú in-order pipeline-t** használ, a stack-gép szemantikához igazítva:

```
 IF  → FETCH:    Prefetch bufferből bájtok, I$-hez QSPI backing
 ID  → DECODE:   Length decoder + hardwired/mikrokód elágazás
 EX  → EXECUTE:  ALU/FPU/Branch, stack cache-en dolgozik
 MEM → MEMORY:   Load/store, gated buffer, GC barrier
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

Egy metódushívás frame-je a következőt tartalmazza (felülről lefelé):

```
 magas cím
  ┌───────────────────────┐
  │   return PC           │   ← PC+len(call utasítás)
  │   saved frame pointer │
  │   saved stack pointer │
  ├───────────────────────┤
  │   arg 0               │   ← metódus paraméterei (caller pushed)
  │   arg 1               │
  │   ...                 │
  ├───────────────────────┤
  │   local 0             │   ← .locals init
  │   local 1             │
  │   ...                 │
  ├───────────────────────┤
  │   eval stack bottom   │   ← ez innen spillel a TOS cache
  │   ...                 │
  │   eval stack top      │
  └───────────────────────┘
 alacsony cím
```

A `call` mikrokód szekvenciája ezt automatikusan felépíti, a `ret` pedig lebontja.

## Dekódolási stratégia

Részletesen lásd `ISA-CIL-T0.md`, de a stratégia magja:

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

Egy CIL `callvirt` = ~8-10 μop (lásd `ISA-CIL-T0.md` részletes trace).

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

Ez a szekció a CLI-CPU biztonsági architektúráját tárgyalja **az architektúra szemszögéből**. A teljes biztonsági modellt, threat model-t, támadás-immunitási táblázatot, formális verifikáció tervet és tanúsítási útvonalakat külön dokumentum tartalmazza: lásd [`docs/security.md`](security.md).

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

Rövid összefoglaló (a részletes táblázat a [`docs/security.md`](security.md) fájlban):

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

A formális verifikáció részleteiért lásd a [`docs/security.md`](security.md) **„Formális verifikáció"** szekcióját.

### Kapcsolódó projektek

- **CHERI** (Cambridge) — legközelebbi rokon, capability-based security hardveresen; érdemes akadémiai partner lehet
- **seL4** — formálisan verifikált microkernel, tanulandó precedens
- **CompCert** — formálisan verifikált C fordító, a `cli-cpu-link` tool hosszú távú célja hasonló lehet
- **Project Everest** (Microsoft Research) — formálisan verifikált HTTPS/TLS stack F\*-ban, Microsoft-támogatás lehetősége

## Kétpályás pozicionálás

A CLI-CPU biztonsági profilja a **Cognitive Fabric** (programozható kognitív szubsztrátum) narratíva **mellett** egy második piaci pályát is megnyit:

- **Pálya 1 — „Cognitive Fabric"** — AI kutatóknak, actor rendszereknek, neurális háló szimulációnak, multi-agent rendszereknek. Hosszú távú vízió.
- **Pálya 2 — „Trustworthy Silicon"** — regulated industries-nek: automotive (ISO 26262), aviation (DO-178C), medical (IEC 62304), critical infrastructure (IEC 61508 SIL-3/4), AI safety watchdog chipek, confidential computing. Rövid-közép távú bevételi lehetőség, magas árréssel.

**Ugyanaz a hardver, két különböző piaci szegmens.** Részletek és konkrét cél-piacok a [`docs/security.md`](security.md) **„Mit jelent ez a projekt gyakorlati célja szempontjából"** szekciójában.

## Következő lépés

A `ISA-CIL-T0.md` dokumentum adja a konkrét CIL-T0 subset teljes opkód-specifikációját, kódolási táblákat, stack-effekteket, ciklusszámokat és trap feltételeket. **Ez az F1 C# szimulátor alapja** — minden ottani tesztnek közvetlenül hivatkoznia kell az ISA-CIL-T0 spec egy-egy pontjára, és a property-based tesztek már most megalapozzák a későbbi formális verifikációt.
