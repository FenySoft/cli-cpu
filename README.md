# CLI-CPU

> **Trustworthy Cognitive Fabric — szilíciumban élő memory safety + sok kis CIL-natív core egyetlen chipen, mailbox-alapú üzenetekkel, eseményvezérelt működéssel.**
> Nincs JIT. Nincs AOT. Nincs interpreter. A CIL bájtok közvetlenül a hardverbe mennek — **és a hardveres biztonság nem megkerülhető.**

🌐 [clicpu.org](https://clicpu.org) *(hamarosan)*

## Mi ez?

A CLI-CPU egy nyílt forráskódú processzor-projekt, amely **a .NET CIL bájtkódot natívan, hardveresen futtatja**, fordítási lépés nélkül — és **sok kis egyszerű core-t** helyez egyetlen chipre, amelyek **üzenet-alapú hálózatként** működnek együtt. Minden core egy teljes CIL programot futtat saját lokális állapottal, és a core-ok kizárólag **mailbox FIFO-kon** keresztül beszélnek egymással — nincs shared memory, nincs cache koherencia, nincs lock contention.

A program választásától függően ugyanaz a hardver lehet:

- **Natív Akka.NET / Orleans actor cluster** — hardveresen, zero overhead
- **Programozható spiking neural network** — minden core egy LIF / Izhikevich / saját neuron-modell
- **Multi-agent szimuláció** — swarm intelligencia, cellular automata, komplex rendszerek
- **Event-driven dataflow pipeline** — DSP, stream feldolgozás
- **IoT edge gateway** — sok szenzor, párhuzamos feldolgozás, ultra-alacsony fogyasztás
- **Embedded web szerver** — per-request egy core

**Egy hardver, sok paradigma.** Ez az a pozíció, amit eddig egyetlen létező rendszer sem fed le: nincs olyan chip, ami egyszerre lenne **hardveres + teljesen programozható csomópontokkal + nyílt forráskódú + .NET natív**. A meglévő neuromorphic chipek (Intel Loihi, IBM TrueNorth, BrainChip Akida) mind **rögzített neuron-modellel** dolgoznak; a szoftveres actor rendszerek (Akka.NET, Erlang) rugalmasak, de a host CPU-n versenyeznek a scheduler, GC, lock overhead-jével.

## Miért nem a klasszikus „bytecode CPU" út

A Sun **picoJava** (1997) és az ARM **Jazelle** (2001) pontosan azt próbálta, amit a CLI-CPU is akarhatna naivan: egy hagyományos, egymagos bytecode-natív processzort a szoftveres JIT alternatíváiként. **Mindkettő megbukott**, mert a szoftveres JIT + általános célú CPU évek alatt olcsóbb és gyorsabb lett, mint a dedikált hardver.

**A CLI-CPU nem ismétli ezt a hibát.** Nem egymagos sebességben akar versenyezni a modern OoO CPU-kkal — az lehetetlen. Ehelyett **más dimenzióban** pozicionál: sok kis independens core, event-driven működés, shared-nothing izoláció, és olyan programozási modell, ami **természetesen illik a modern multi-threaded .NET alkalmazásokhoz** (Task, async/await, Akka.NET, Orleans, Channel).

Részletek a `docs/architecture.md` **„Stratégiai pozicionálás: Cognitive Fabric"** szekciójában.

## Négy ütőkártya

1. **Silicon-grade security** — a memory safety, type safety és control flow integrity **fizikai tulajdonságok a szilíciumban**, nem szoftveres absztrakciók. Immunis a Spectre/Meltdown típusú mikroarch-támadásokra (nincs spekulatív végrehajtás), a ROP/JOP támadásokra (hardveres CFI), a buffer overflow-ra (hardveres bounds check), és a JIT spraying-ra (nincs JIT). **Formálisan verifikálható** ISA, ami a CompCert/seL4 tanulságára épít. Részletek: [`docs/security.md`](docs/security.md).
2. **Kódtömörség** — a CIL bytecode 30–50%-kal kompaktabb, mint a RISC-V RV32I vagy ARM Thumb-2 ugyanarra a funkcióra → kevesebb flash, kevesebb fogyasztás, **több neuron fér el egy chip-re**.
3. **Shared-nothing skálázódás** — mivel a core-ok között nincs megosztott memória, a teljesítmény **lineárisan nő** a core-számmal. Nincs MESI, nincs cache coherency overhead, nincs lock contention, nincs cross-core side-channel.
4. **Event-driven power profile** — a core-ok alapértelmezésben alvó üzemmódban vannak, és csak akkor ébrednek, amikor mailbox üzenet érkezik. **Ultra-alacsony alapfogyasztás**, ami kulcsfontosságú IoT, kritikus infrastruktúra és neuromorphic workload-okon.

## Kétpályás pozicionálás — hosszú távon a Linux utódja

A CLI-CPU + Neuron OS **két párhuzamos piaci narratívát** követ, ugyanazzal a hardverrel, és hosszú távon **egyetlen közös történeti célt** szolgál: **a Linux által örökölt 1970-es évek Unix alapjainak felváltását** modern, biztonságos, skálázható, aktor-alapú architektúrára.

**Pálya 1 — „Cognitive Fabric"**: programozható kognitív szubsztrátum AI kutatóknak, Akka.NET / Orleans actor rendszereknek, spiking neural network szimulációnak, multi-agent szimulációnak, IoT edge gateway-nek. **Hosszú távú vízió.**

**Pálya 2 — „Trustworthy Silicon"**: formálisan verifikálható, tanúsítható processzor regulated industries-nek — automotive (ISO 26262 ASIL-B/C/D), aviation (DO-178C), medical (IEC 62304), critical infrastructure (IEC 61508 SIL-3/4), AI safety watchdog, confidential computing. **Rövid-közép távú bevételi lehetőség.**

Ugyanaz a chip, két különböző piaci szegmens — **de ugyanaz a történeti cél**: ahogy az x86 leváltotta a mainframe-et, a mobile leváltotta a desktopot, a cloud leváltotta az on-prem szerverközpontot, úgy **a Cognitive Fabric + Neuron OS lesz a következő leváltási ciklus**, amely a modern, AI-vezérelt, biztonság-kritikus, masszívan elosztott korszak OS-ét adja. Részletek a [`docs/neuron-os.md`](docs/neuron-os.md) „A Linux öröklött problémái és a Neuron OS válasza" szekciójában.

## Heterogén multi-core: Nano + Rich

Az F5 fázistól a CLI-CPU **heterogén multi-core** architektúrát használ, analóg módon az ARM big.LITTLE, Apple P-core + E-core, és Intel Alder Lake megközelítéseihez — csak a .NET világra alkalmazva:

| | **Nano core** | **Rich core** |
|-|---------------|---------------|
| ISA | CIL-T0 (48 opkód, integer-only) | Teljes ECMA-335 CIL (~220 opkód) |
| Méret | ~10k std cell | ~80k std cell |
| Funkciók | Integer, stack cache, mailbox | Nano + objektum modell + GC + FPU + kivételek + generikusok |
| Szerep | Worker / neuron / filter / egyszerű actor | Supervisor / orchestrator / komplex domain logika |
| Tipikus arány F6-on | **32–48 db** (sok) | **2–4 db** (kevés) |

A C# programok **`[RunsOn(CoreType.Nano)]`** vagy **`[RunsOn(CoreType.Rich)]`** attribútummal jelölik, hogy melyik osztály melyik core-ra fordul. A Roslyn source generator build-time ellenőrzi, hogy a Nano-jelölt kód **csak** CIL-T0 opkódokat használ.

## Státusz

**F0 — Specifikáció fázis.** A dokumentumok készen vannak a Cognitive Fabric iránnyal, kód még nincs. A következő lépés az **F1 C# referencia szimulátor** TDD-vel.

Lásd [docs/roadmap.md](docs/roadmap.md) a teljes fázisolásért.

## Dokumentumok

- [docs/roadmap.md](docs/roadmap.md) — Hétfázisú ütemterv F0-tól F7-ig, a Cognitive Fabric pivottal F4-ben
- [docs/architecture.md](docs/architecture.md) — CLI-CPU mikroarchitektúra, Cognitive Fabric pozicionálás, prior art elemzés (picoJava, Jazelle, Transmeta, Loihi, SpiNNaker), heterogén Nano + Rich multi-core
- [docs/ISA-CIL-T0.md](docs/ISA-CIL-T0.md) — CIL-T0 subset specifikáció (48 opkód), mailbox MMIO interfész
- [docs/security.md](docs/security.md) — Threat model, architekturális biztonsági garanciák, támadás-immunitási táblázat, formális verifikáció terv, tanúsítási útvonalak (IEC 61508, ISO 26262, DO-178C, IEC 62304)
- [docs/neuron-os.md](docs/neuron-os.md) — Neuron OS vízió: aktor-alapú operációs rendszer a CLI-CPU-ra, „Erlang in silicon"

## Gyártási útvonal

| Fázis | Cél | Platform |
|-------|-----|----------|
| F0 | Spec dokumentumok | — |
| F1 | C# referencia szimulátor (TDD) | .NET |
| F2 | RTL (Verilog/Amaranth) + cocotb, Nano core egymagos | szimuláció |
| F3 | **Tiny Tapeout submission** — 1× Nano core + mailbox MMIO, első hálózatba illeszthető csomópont | Sky130, ~$150 |
| F4 | **Cognitive Fabric pivot** — 4× Nano core FPGA, shared-nothing, event-driven | Artix-7 / ECP5, ~$250 |
| F5 | **Rich core születése** — 4× Nano + 1× Rich (teljes CIL) FPGA, első heterogén rendszer | ugyanaz az FPGA |
| F6 | **Cognitive Fabric real silicon** — 2–4× Rich + 32–48× Nano, heterogén multi-core MPW tape-out | Sky130 ChipIgnite vagy IHP MPW, ~$10k |
| F7 | Demonstrációs platform + Neuron OS csírái | PCB + szoftver |

## Licenc

TBD (valószínűleg Apache 2.0 a kódra és CC-BY 4.0 a dokumentációra)
