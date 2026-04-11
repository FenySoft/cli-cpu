# CLI-CPU — Roadmap

A CLI-CPU projekt **hét fázisban** épül fel, a spec dokumentumtól az első működő, kezedben tartható szilíciumig és tovább, a teljes ECMA-335 CIL implementációig.

## Vezérelvek

1. **Spec előbb, kód utána.** Minden fázis egy dokumentummal vagy egy pontos követelménylistával kezdődik. Nincs „majd menet közben kitaláljuk".
2. **TDD minden szoftveres rétegre.** A szimulátor és az RTL is tesztelt — a tesztek a spec követelményeiből születnek, nem utólag az implementáció alapján.
3. **Egy aranypélda.** Az F1 C# szimulátor **az aranypélda** — minden későbbi RTL (F2, F4, F5) ezt a viselkedést reprodukálja, cocotb/golden-vector összehasonlítással.
4. **Terjeszkedés alulról felfelé.** F0–F3 a „tiszta, szűk" CIL-T0 subset. F4–F6 csak akkor jön, ha az alap már szilárd.
5. **Valódi szilícium korán.** Az F3 (Tiny Tapeout) a projekt első „kézzel fogható" mérföldköve — akár hiányos is lehet a funkciókészlet, de **létezik fizikailag**.

## Fázisok

### F0 — Specifikáció

**Cél:** Olyan dokumentumok, amelyekből a teljes projekt megépíthető anélkül, hogy menet közben tervezési döntéseket kellene hozni.

**Kimenet:**
- `docs/roadmap.md` — ez a dokumentum
- `docs/architecture.md` — CLI-CPU architektúra: stack-gép, pipeline, memória modell, prior art
- `docs/ISA-CIL-T0.md` — CIL-T0 subset teljes specifikáció (~40 opkód)

**Kész kritérium:** A három dokumentum elolvasása után egy kívülálló mérnök meg tudja mondani, hogy *pontosan* melyik CIL opkód mit csinál a CLI-CPU-n, és hogyan illeszkedik a mikroarchitektúrába.

---

### F1 — C# Referencia Szimulátor

**Cél:** Bithibátlan, TDD-vel fejlesztett szoftveres CLI-CPU szimulátor, amelyhez minden CIL-T0 opkódnak dedikált xUnit tesztje van.

**Platform:** .NET 10, C# 13, xUnit.

**Kimenet:**
- `src/CilCpu.Sim/` — szimulátor könyvtár (fetch, decode, execute)
- `src/CilCpu.Sim.Tests/` — xUnit teszt projekt
- `src/CilCpu.Sim.Runner/` — CLI futtató, ami egy CIL-T0 bináris formátumot tud olvasni és futtatni
- `samples/` — néhány egyszerű C# program (Fibonacci, integer sum, GCD), `ilasm`-mal vagy Roslyn-nal CIL-T0-ba fordítva

**Kész kritérium:**
- 100% opkód lefedettség tesztekkel
- Egy Fibonacci(20) C# kódból fordított CIL-T0 bináris helyesen futtatható a szimulátoron
- A szimulátor **mindent trap-el**, amit a spec előír (stack overflow, invalid branch target, stb.)

**Függőség:** F0 kész.

---

### F2 — RTL (Register Transfer Level)

**Cél:** A CLI-CPU szintetizálható RTL leírása, amely bitről-bitre ugyanúgy viselkedik, mint az F1 szimulátor.

**Platform:**
- **Nyelv:** Verilog (TT mainstream) vagy Amaranth HDL (Python, modernebb) — a végleges döntés F2 indulásakor
- **Szimuláció:** Verilator + cocotb
- **Aranypélda:** F1 C# szimulátor — minden CIL-T0 teszt futtatása egyszerre RTL-en és szimulátoron, eredmény-összehasonlítás

**Kimenet:**
- `rtl/` — RTL források
- `rtl/tb/` — cocotb testbench
- `rtl/scripts/` — szintézis és szimuláció scriptek (OpenLane2 kompatibilis)

**Kész kritérium:**
- Verilator szimuláció minden F1 teszten zöld
- Yosys szintézis Sky130 PDK-ra sikeres
- Timing analízis: min. 30 MHz @ Sky130, cél 50 MHz
- Terület becslés a Tiny Tapeout multi-tile budget-be fér (max 8×2 = 16 tile)

**Függőség:** F1 kész, minden teszt zöld.

---

### F3 — Tiny Tapeout Submission (egymagos CIL-T0 + Mailbox)

**Cél:** Az első valódi CLI-CPU szilícium. Sky130 PDK-n, Tiny Tapeout shuttle-n, egymagos CIL-T0 subset + **hardveres mailbox interfésszel**, ami az első „hálózatba illeszthető csomópont" demót teszi lehetővé.

**Platform:** Tiny Tapeout (jelenlegi shuttle — TT10/TT11/..., amelyik időben elérhető), Sky130, OpenLane2.

**Kimenet:**
- `tt/` — Tiny Tapeout submission könyvtár (`info.yaml`, `src/`, `docs/`, stb.)
- `tt/test/` — post-silicon bring-up tesztek
- `hw/bringup/` — bring-up board tervei (KiCad): QSPI flash socket, QSPI PSRAM socket, FTDI USB-UART (a mailbox külső bridge-éhez), power, debug LEDek, PMOD csatlakozók

**Új F3 komponens a spec szerint:**
- **Mailbox MMIO blokk** — 8 mélységű inbox + outbox FIFO, `0xF000_0100` címen, részletek a `docs/ISA-CIL-T0.md`-ben. Lehetővé teszi, hogy egy host számítógép UART-on keresztül üzeneteket küldjön a chipnek, amit a chip CIL programmal dolgoz fel és válaszol vissza.

**Kész kritérium:**
- GDS elfogadva a Tiny Tapeout shuttle-re
- Gate-level szimuláció zöld
- Bring-up board legyártatva (JLCPCB), bekábelezve
- **Fizikailag futó `Fibonacci(10)` a saját chipeden**, UART-on kiíratva
- **Első „echo neuron" demó:** a host üzenetet küld a mailbox-on át, a chip CIL programja feldolgozza és visszaküldi — a cognitive fabric koncepció első szilícium-szintű bizonyítéka

**Függőség:** F2 kész.

**Költség-nagyságrend:** ~$150 (TT submission) + ~$80 (bring-up PCB + alkatrészek).

---

### F4 — Multi-core Cognitive Fabric FPGA-n

**Cél:** **A stratégiai pivot pillanata.** A CLI-CPU először válik valódi hálózattá — 4 egymagos CIL-T0 core dolgozik együtt egyetlen FPGA chipen, **shared-nothing modellben**, kizárólag mailbox üzenetekkel kommunikálva, eseményvezérelt (event-driven) működéssel.

**Miért itt van a fő pivot:** Ez a fázis megkülönbözteti a CLI-CPU-t a történelmi Jazelle/picoJava „bytecode CPU" bukásoktól. A `docs/architecture.md` „Stratégiai pozicionálás: Cognitive Fabric" szekciója részletesen érvel amellett, hogy miért itt van a projekt valódi értéke, és miért nem az egymagos sebesség-verseny.

**Új funkciók:**
- **4 darab CIL-T0 core** egy FPGA-n (az F3 RTL 4 példányban instanciálva)
- **Mailbox router** — a core-ok közötti üzenetek célzott továbbítása (4-portú mux-köteg, nem crossbar)
- **Per-core privát SRAM** (16 KB/core), shared-nothing modell
- **Sleep/Wake logika** — a core elalszik üres inbox-on, új üzenetre ébred (wake-from-sleep interrupt)
- **Globális időbázis** — egyetlen szinkronizált clock counter, amit minden core olvas (a neuron-modellek időfüggőségéhez)
- **Shared slow bus** — csak a QSPI flash, UART, timer eléréshez, nem a kritikus inter-core kommunikációhoz

**Új mikroarchitektúra elemek:**
- Router FSM (~1000 std cell)
- Per-core mailbox FIFO (már F3-ban megvolt, itt csak kapcsolódik a router-re)
- Wake-from-sleep interrupt vonal
- Globális clock broadcast hálózat

**Platform:** Xilinx Artix-7 (Digilent Arty A7-100T, ~$250) vagy Lattice ECP5 (OrangeCrab, ~$130). FPGA-n még 100% megvalósítható.

**Kész kritérium:**
- 4 core egyszerre futtat különböző CIL programokat, üzenetekkel kommunikálnak
- **Ping-pong demó:** Core 0 üzenetet küld Core 1-nek, Core 1 válaszol — minimal actor pattern
- **Echo háló demó:** 4 core láncban továbbad egy üzenetet, az első útnak indítja, a negyedik kiküldi UART-ra
- **Spiking neural network demó:** mind a 4 core egy-egy LIF neuron CIL programot futtat, konfigurálható topológiával — a cognitive fabric első valódi neuromorphic felhasználása
- Event-driven mód: idle energia mérve, megjelenik az alvási állapot nyeresége

**Függőség:** F3 kész, post-silicon tanulságok visszaportolva az RTL-re.

---

### F5 — Rich core (teljes CIL) FPGA-n, első heterogén rendszer

**Cél:** **A Rich core születése.** Ez az a fázis, amikor a CIL-T0 szűk subset mellé **megszületik a „nagy testvér"** — egy teljes ECMA-335 CIL core objektum-modellel, GC-vel, virtuális hívásokkal, kivételekkel, FPU-val, 64-bit integer-rel, generikusokkal. A fázis végén **először futtatunk egy heterogén multi-core rendszert**: 4 Nano core (F4-ből) **mellett** 1 Rich core, közös mailbox hálózaton.

**Miért „Rich core" és nem csak „teljes CIL"?** A `docs/architecture.md` **„Heterogén multi-core: Nano + Rich"** szekciója részletezi: a CLI-CPU heterogén (big.LITTLE-szerű) architektúrát fog használni az F6-tól, **kétféle core típussal**. A Nano (CIL-T0) F3-ban született meg, a Rich (teljes CIL) itt, F5-ben. Ez a terminológia-egységesítés csak átnevezés — a technikai tartalom az, ami eddig is „teljes CIL" volt a roadmap-ben.

**Új opkódok a Rich core-on (a Nano 48 opkódon felül):**
- Objektum modell: `newobj`, `newarr`, `ldfld`, `stfld`, `ldelem.*`, `stelem.*`, `ldlen`, `initobj`
- Virtuális hívás és metadata: `callvirt`, `ldtoken`, `ldftn`, `ldvirtftn`
- Típusellenőrzés: `isinst`, `castclass`, `box`, `unbox`
- String: `ldstr`
- Kivételkezelés: `throw`, `rethrow`, `leave`, `endfinally`, `endfilter`
- 64-bit integer: minden aritmetika `.i8` változata
- Floating point: `ldc.r4`, `ldc.r8`, `add` (FP), `mul` (FP), `div` (FP), `conv.*`
- Generics: runtime típusparaméter feloldás

**Új mikroarchitektúra a Rich core-on:**
- **Metaadat TLB + token-resolver** — PE/COFF táblákat jár be
- **vtable inline cache** — virtuális hívás gyorsítás
- **Per-core GC assist unit** — bump allocator a privát heap-en. **Nincs globális GC**, mert nincs shared heap — ez a shared-nothing modell **nagy egyszerűsítése**, a GC nem kell stop-the-world globálisan
- **Shadow register file + exception unwinder** (Transmeta-inspiráció)
- **μop cache** (Transmeta-stílus, forró loopokon energia-spórolás)
- **FPU** (IEEE-754 R4, R8)

**Új szoftveres munka:**
- **Roslyn source generator** a `[RunsOn(CoreType.Nano)]` / `[RunsOn(CoreType.Rich)]` attribútumokra
- A generator ellenőrzi build-time, hogy a Nano-jelölt metódusok csak CIL-T0 opkódokat használnak (verifikáció)
- Két külön bináris kimenet: `.t0` (Nano) és `.tr` (Rich)

**Platform:** Ugyanaz az FPGA, mint F4 — de most 4 Nano core + 1 Rich core együtt. A Rich core **~8x nagyobb**, mint egy Nano, úgyhogy az FPGA-n több LUT-ot használ. Egy Artix-7 100T még elférnek benne kényelmesen.

**Kész kritérium:**
- Minden ECMA-335 opkódra van teszt a C# referencia szimulátoron és az RTL-en
- Egy C# program osztályokkal, virtuális metódusokkal, tömbökkel, stringekkel, kivételekkel **fut a Rich core-on**
- Egy C# program, ahol **egyes osztályok `[RunsOn(CoreType.Nano)]`, mások `[RunsOn(CoreType.Rich)]`** — fut heterogén rendszerben
- **Multi-core Akka.NET demó:** supervisor a Rich core-on, worker-ek a Nano core-okon, üzenetek a mailbox-on át
- **Multi-core SNN demó:** Izhikevich vagy Hodgkin-Huxley modell mind a 4 Nano core-on, egy Rich core koordinálja

**Függőség:** F4 kész.

---

### F6 — Cognitive Fabric Real Silicon (heterogén Nano + Rich)

**Cél:** **A teljes Cognitive Fabric valódi szilíciumon, heterogén multi-core architektúrával.** Nem Tiny Tapeout, mert a rendszer nem fér el — eFabless Caravel harness-en (vagy IHP SG13G2 MPW, ha az ingyenes shuttle elérhető F6 időzítéskor), full MPW shuttle-n.

**Arány F6-ra:** **2–4 Rich core** (supervisor) **+ 32–48 Nano core** (worker), mesh router-rel összekötve. A Rich core-ok kevés számban felügyelnek, a Nano core-ok nagy tömegben végzik a konkrét munkát. Ez pontosan a `docs/architecture.md`-ben tárgyalt heterogén modell.

**Platform-döntés későbbre halasztva:** Az F6 tényleges tape-out előtt (F5 végén) újra kell nézni a három opciót:
- **Sky130 @ Caravel (eFabless ChipIgnite)** — ismert, megbízható, ~$10k, ismert toolchain
- **IHP SG13G2 MPW** — európai, potenciálisan ingyenes/olcsóbb shuttle, hasonló digitális teljesítmény
- **Pragmatic FlexIC** — nem valószínű, túl korlátos tranzisztor-budget, megfigyelés alatt

**Új funkciók az F4+F5-höz képest:**
- **Heterogén instanciálás** — 2-4 Rich core + 32-48 Nano core egy chipen
- **Floorplan optimalizáció** — a Rich core-ok központi helyen, a Nano core-ok köré csoportosítva
- **Mesh router** — 4 core-nál nagyobb rendszerhez 2D grid topológia kell
- **Writable microcode** SRAM — firmware-ből frissíthető opkód viselkedés
- **Gated store buffer** (GC write barrier batch, Transmeta-inspiráció)
- **Agresszív power-gating** — a nem használt core-ok teljesen hideg állapotban
- **Core-típusok közötti bridge** — Nano ↔ Rich üzenetek és állapot-migráció (egyszerű, mert ugyanazon az mailbox MMIO-n dolgoznak)

**Új tervezési munka F6-hoz (a már meglévő F4+F5 munkán felül):**
- Floorplan: **~2–4 mérnökhét**
- Heterogén instanciálás és verification: **~1 mérnökhónap**
- Mesh router (4+ core-hoz): **~1 mérnökhónap**
- **Összesen: ~1.5–2 mérnökhónap plusz munka**, ami elhanyagolható a teljes projekthez képest

**Kimenet:**
- `mpw/` — eFabless/IHP submission könyvtár
- `mpw/firmware/` — boot-loader, mikrokód image, Nano/Rich kód-loader
- `hw/chipignite-board/` — ChipIgnite (vagy IHP) bring-up board

**Kész kritérium:**
- Heterogén lapka legyártva és a kezedben
- A négy F4 demó (ping-pong, echo-chain, ping-network, SNN) fut valódi szilíciumon a Nano core-okon
- **Rich core demó:** egy teljes C# webhandler fut a Rich core-on, tömbökkel, stringekkel, objektumokkal, kivételekkel
- **Heterogén demó:** egy Rich core supervisor koordinálja a Nano core-okon futó neurális hálót
- **Nagyobb SNN demó:** MNIST klasszifikátor spiking neural network-ként 32-48 Nano core-on, 1-2 Rich core coordinator-ral
- **Akka.NET cluster demó:** valós C# kódból fordított actor rendszer hardveresen futva
- **Energia / teljesítmény mérés** ARM Cortex-M4 / RISC-V RV32 ellen, event-driven workload-okon

**Függőség:** F5 kész, FPGA stabil (mind Nano, mind Rich core-ral), minden teszt zöld.

**Költség-nagyságrend:** ~$9,750 (eFabless ChipIgnite, 100 db bring-up chip-pel), vagy ~€0–3k (IHP MPW, ha ingyenes shuttle nyílik), vagy $0 (Open MPW free shuttle, ha elérhető).

---

### F7 — Demonstrációs platform + Neuron OS csírái

**Cél:** A Cognitive Fabric ne csak egy lapka legyen, hanem egy **demonstrálható, fejleszthető platform** több valós use-case-re. Itt kezd kialakulni az a runtime/OS réteg, ami a hardver fölött a programozhatóságot biztosítja — ezt nevezzük itt informálisan **„neuron OS"**-nek.

**Kimenet:**
- **Referencia PCB-k** több use-case-re:
  - IoT szenzor node (QSPI flash, PSRAM, LoRa/WiFi, néhány szenzor)
  - Akka.NET cluster demó dev kit (több chip hálózatban)
  - SNN inference board (MNIST/CIFAR szintű feladatra)
- **„Neuron OS" minimum runtime**:
  - Bootloader (F3 óta létezik, itt formalizálódik)
  - Core allocation: melyik core melyik CIL kódot futtatja
  - Message routing szoftveres kiegészítés (hardveres router felett)
  - Topológia manager: virtuális aktor-kapcsolatok
  - Lifecycle: actor létrehozás, szüneteltetés, megszüntetés
  - Dinamikus CIL kód-betöltés core-ra futás közben
  - Monitoring: spike rate, CPU használat, memória — debug/telemetria
- **Fejlesztői eszközök:**
  - `dotnet publish` target a CLI-CPU-ra
  - Referencia C# példák (Akka.NET, LIF háló, dataflow pipeline, IoT gateway)
  - Szimulátor/hardver bridge (VSCode debugger kapcsolat)
- **Publikációs anyag:** cikk, előadás, demo video — az egész projektet bemutató narratíva

**Függőség:** F6 kész, chip a kézben.

**Megjegyzés:** A „neuron OS" rétegei **organikusan épülnek fel** az F1-F6 munka mellett — minden fázis ad hozzá valamit (F1: boot + trap handler, F4: scheduler + router, F5: memory manager, F6: lifecycle). Az F7-ben csak **nevet és formalizálást** kapnak. **Nem tervezzük meg előre az egész OS-t**, mert az hónapokat venne el a hardver munkától.

---

## Függőségi gráf

```
                          ┌── Nano core út ──┐         ┌── Rich core út ──┐
                          │                  │         │                  │
F0 ──► F1 ──► F2 ──► F3 ──┘──► F4 ──►────────┘─► F5 ──┴──► F6 ──► F7
  spec   sim    RTL    TT       multi-         heterogén   heterogén  demo
              │         1×      Nano          (Rich+Nano) (2-4 Rich  + Neuron
              │         +        4×            FPGA       + 32-48    OS
              │        mbox     FPGA                       Nano MPW)
              │              ▲
              └──── FPGA ────┘
                 (opcionális
                  korai F2 után)
```

Az F2 után opcionálisan FPGA-n is futtatható a CIL-T0 subset, még F3 (Tiny Tapeout) előtt — ez segít a bring-up board tervezésében.

## Két kulcs pivot a roadmap történetében

**1. pivot — F4: Cognitive Fabric irány (shared-nothing multi-core)**

A **korábbi** F4 a „CIL object model + GC FPGA-n" volt, a mostani **új** F4 viszont a „4-core multi-core FPGA Cognitive Fabric". Az object model + GC átcsúszott F5-re. A **hardware alap (stack-gép core) nem változik** — F3-ból emelődik át F4-be, csak 4 példányban. Ezzel a pivot **minimális kódcserével** megvalósítható, és megőrzi minden eddigi F0-F3 munkát. Ez a lépés megkülönbözteti a CLI-CPU-t a történelmi picoJava/Jazelle bukásoktól.

**2. pivot — F5: Heterogén Nano + Rich terminológia**

A korábbi „F5 — CIL Object Model + GC egymagos kiterjesztés" címet átneveztük **„F5 — Rich core (teljes CIL) FPGA-n, első heterogén rendszer"** címre. Technikailag a tartalom majdnem ugyanaz (teljes CIL kiterjesztés), de most már explicite úgy fogalmazzuk, hogy itt **születik meg a Rich core** mint a Nano core „nagy testvére". Az F6 ChipIgnite ezek után egy **heterogén Nano+Rich multi-core chip**, analóg módon az ARM big.LITTLE, Apple P/E-core, Intel Alder Lake modellekhez. Lásd `docs/architecture.md` „Heterogén multi-core: Nano + Rich" szekciót.

## Mai státusz

**F0 folyamatban.** `roadmap.md`, `architecture.md`, `ISA-CIL-T0.md`, `README.md` mind frissítve a Cognitive Fabric iránnyal és a heterogén Nano+Rich modellel. A következő érdemi lépés az **F1 — C# referencia szimulátor** TDD-vel.
