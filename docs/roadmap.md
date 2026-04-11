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

### F1 — C# Referencia Szimulátor — **KÉSZ**

**Cél:** Bithibátlan, TDD-vel fejlesztett szoftveres CLI-CPU szimulátor, amelyhez minden CIL-T0 opkódnak dedikált xUnit tesztje van.

**Platform:** .NET 10, C# 13, xUnit.

**Kimenet:**
- `src/CilCpu.Sim/` — szimulátor könyvtár (fetch, decode, execute) — **kész**
- `src/CilCpu.Sim.Tests/` — xUnit teszt projekt — **kész, 218 zöld teszt**
- `src/CilCpu.Sim.Runner/` — CLI futtató, ami egy CIL-T0 bináris formátumot tud olvasni és futtatni — F1.5-re halasztva
- `samples/` — néhány egyszerű C# program (Fibonacci, integer sum, GCD), `ilasm`-mal vagy Roslyn-nal CIL-T0-ba fordítva — F1.5-re halasztva

**Kész kritérium — teljesítve:**
- ✅ 100% opkód lefedettség tesztekkel — mind a 48 CIL-T0 opkód külön teszttel
- ✅ Egy Fibonacci(20) C# kódból fordított CIL-T0 bináris helyesen futtatható a szimulátoron — `Fibonacci(20) = 6765` zöld
- ✅ A szimulátor **mindent trap-el**, amit a spec előír (stack overflow, invalid branch target, invalid memory access, call depth exceeded, stb.)
- ✅ TDD-vel fejlesztve, 4 iteráció (konstansok → stack/local/arg → arit/branch/cmp → call/ret/mem/break)
- ✅ Devil's Advocate review minden iteráció után, finalizálás QR pass-szal

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

### F6 — Cognitive Fabric Maximum Demonstration (heterogén Nano + Rich)

Az F6 mérföldkő **két párhuzamos variánsban** valósul meg. **Az F6-FPGA az elsődleges, ajánlott út**, mert a CLI-CPU nyílt forráskódú filozófiájához tisztán illeszkedik — **100% nyílt toolchain end-to-end**, **reprodukálható**, **iterálható órák alatt**, és **nagyságrendekkel olcsóbb**, mint a silicon tape-out. **Az F6-Silicon opcionális, halasztható**, és csak akkor indul, ha az F6-FPGA-ban érlelt design valós szilíciumon is bizonyíthatóvá kell válnia (kereskedelmi termék, energia mérés, F6.5 Secure Edition előfeltétel).

**Közös arány az F6-ra:** **2–4 Rich core** (supervisor) **+ 32–48 Nano core** (worker), mesh router-rel összekötve. A Rich core-ok kevés számban felügyelnek, a Nano core-ok nagy tömegben végzik a konkrét munkát. Ez pontosan a `docs/architecture.md`-ben tárgyalt heterogén modell.

#### F6-FPGA — Maximum heterogén demonstráció a 7-series csúcson (elsődleges)

**Cél:** A teljes Cognitive Fabric architektúra **maximális demonstrálása** a legnagyobb OpenXC7-támogatott Xilinx FPGA-kon, **silicon nélkül**, **nyílt toolchain end-to-end**. Az F6-FPGA **bizonyítja, hogy az architektúra működik a tape-out méretben**, mielőtt bárki ~$10k-t kockáztatna egy MPW shuttle-re.

**Stratégiai indoklás:** Az **OpenXC7** a Xilinx 7-series családot támogatja érdemben (Artix-7, Kintex-7), és ezen belül a **Kintex-7 XC7K325T** és **XC7K480T** a legnagyobb chipek. Ezeket „kimaxolva" különböző (Rich, Nano) kombinációkkal a CLI-CPU **adatvezérelt sweet spot keresést** végez **a tényleges silicon tape-out előtt**, **nyílt build chain-en**, **teljesen reprodukálható módon**.

**Új munka az F4+F5-höz képest:**
- **Adaptív top-level instanciálás** — paraméterezhető (`#NUM_RICH`, `#NUM_NANO`) az ugyanazon RTL-re
- **Mesh router** skálázhatóság — 4 core-nál nagyobb rendszerhez 2D grid topológia (~1 mérnökhónap)
- **Heterogén verification** és többkonfigurációs test harness (~1 mérnökhónap)
- **Configuration sweep script** — automatikus szintézis és P&R több (Rich, Nano) párra, LUT/timing/throughput riport
- **Összesen: ~2-3 mérnökhónap**, **csak instanciálás és test harness**, **nincs új RTL komponens**

**Platform:**
- **Elsődleges:** **Kintex-7 XC7K480T** (pl. Inspur YPCB-00338-1P1 / YZCA-00338, ex-data center, ~$60-200) — **298k LUT**, elég az F6 alsó-közép célra (2-3 Rich + 32-40 Nano)
- **Másodlagos:** **Kintex-7 XC7K325T** (pl. SITLINV CERN-OHL-P-2.0 nyílt hardver dev board ~$220-265, vagy QMTECH ~$127) — **204k LUT**, kisebb konfigurációkra (1-2 Rich + 16-24 Nano), **nyílt hardver licenc**
- **Mindkettő OpenXC7 + yosys + nextpnr-xilinx** kompatibilis, **Vivado licenc nem szükséges**

**Kimenet:**
- `rtl/top_f6_fpga/` — paraméterezhető top-level (Nano és Rich core szám konfigurációs paraméter)
- `rtl/test_harness/` — multi-core stress teszt szcenáriók
- `bring-up/f6_fpga_results.md` — multi-konfiguráció riport (LUT, timing, throughput, power becslés)
- `bring-up/f6_fpga_sweet_spot.md` — javaslat az F6-Silicon (Rich, Nano) konfigurációra

**Konfigurációs sweep — kimaxolt 7-series kombinációk:**

A K7-325T és K7-480T-n szisztematikusan próbáljuk ki a legalább következő (Rich, Nano) párokat:

| FPGA | (Rich, Nano) | Becsült LUT | Cél |
|------|--------------|-------------|-----|
| K7-325T | (0, 30) | ~180k | Tiszta Nano fabric (SNN) |
| K7-325T | (1, 24) | ~176k | „1 supervisor + sok worker" |
| K7-325T | (2, 16) | ~184k | Heterogén közép |
| K7-325T | (3, 6) | ~186k | Rich-domináns |
| K7-480T | (2, 32) | ~232k | **F6 alsó silicon target megfelelője** |
| K7-480T | (3, 24) | ~234k | Heterogén közép-nagy |
| K7-480T | (4, 12) | ~248k | Apple-szerű big.LITTLE arány |
| K7-480T | (1, 38) | ~232k | Nano-domináns |
| K7-480T | (0, 45) | ~270k | Tiszta SNN max |

**Kész kritérium:**
- **Legalább 4 különböző (Rich, Nano) konfiguráció** szintetizálva és futtatva K7-480T-n vagy K7-325T-n
- **A 2 Rich + 32 Nano konfiguráció (F6 alsó silicon target FPGA megfelelője)** stabilan fut a K7-480T-n
- **Mesh router stress teszt** 32+ core-on, 1 perc, deadlock nélkül
- **A négy F4 demó** (ping-pong, echo-chain, ping-network, SNN) **fut a teljes 32+ magon**
- **Rich core demó:** C# webhandler fut a Rich core-on (tömbök, stringek, kivételek)
- **Heterogén demó:** Rich core supervisor koordinál Nano core-okon futó neurális hálót
- **Nagyobb SNN demó:** MNIST klasszifikátor 32+ Nano core-on, 1-2 Rich coordinator-ral
- **Akka.NET cluster demó:** valós C# kódból fordított actor rendszer hardveresen futva
- **Aggregate throughput** mérés (üzenet/sec a teljes mesh-en)
- **Power becslés** (FPGA fogyasztás × empirikus FPGA→silicon konverziós faktor)
- **Multi-konfiguráció riport** publikálva (LUT, timing, throughput összehasonlítás)

**Függőség:** F5 kész, FPGA stabil (mind Nano, mind Rich core-ral), minden teszt zöld, OpenXC7 működik a kiválasztott Kintex-7 hardveren.

**Költség-nagyságrend:** ~$60-200 (K7-480T) **vagy** ~$220-265 (SITLINV K7-325T) **vagy** mindkettő ~$280-465. **JTAG kábel** ~$25 (csak ha nem beépített). **Vivado licenc: $0** (OpenXC7 nyílt toolchain). **Mérnöki munka:** 2-3 mérnökhónap.

#### F6-Silicon — MPW tape-out (opcionális, halasztható)

**Cél:** Az F6-FPGA-ban érlelt és sweet spot-ra optimalizált design **valós szilíciumon**, eFabless Caravel harness-en (vagy IHP SG13G2 MPW, ha az ingyenes shuttle elérhető F6-Silicon időzítéskor), full MPW shuttle-n.

**Mikor indul:** **Csak az F6-FPGA után**, és csak akkor, ha legalább egy a következőkből igaz:
- A projekt **finanszírozást vagy ipari partnert** kapott a tape-out fedezésére
- A **kereskedelmi termék útvonalra** ([F6.5 Secure Edition](#f65--secure-edition-parallel-tape-out-opcionális), F7 demó hardver) **silicon-előfeltétel** van
- A **valós energia hatékonyság** és **>500 MHz órajel** mérése **kritikus** a következő mérföldkőhöz
- Az **F6.5 Secure Edition tape-out** közeledik, és a Cognitive Fabric base **szilíciumon** kell legyen először

**Platform-döntés (F6-Silicon indulása előtt):**
- **Sky130 @ Caravel (eFabless ChipIgnite)** — ismert, megbízható, ~$10k, ismert toolchain
- **IHP SG13G2 MPW** — európai, potenciálisan ingyenes/olcsóbb shuttle, hasonló digitális teljesítmény
- **Pragmatic FlexIC** — nem valószínű, túl korlátos tranzisztor-budget, megfigyelés alatt

**Új funkciók a F6-FPGA-hoz képest (silicon-specifikus):**
- **Floorplan optimalizáció** — a Rich core-ok központi helyen, a Nano core-ok köré csoportosítva
- **Writable microcode** SRAM — firmware-ből frissíthető opkód viselkedés (FPGA-n BRAM-mal szimulálva, silicon-on dedikált SRAM)
- **Gated store buffer** (GC write barrier batch, Transmeta-inspiráció)
- **Agresszív power-gating** — a nem használt core-ok teljesen hideg állapotban (FPGA-n nem reális)
- **Core-típusok közötti bridge** — Nano ↔ Rich üzenetek és állapot-migráció hardveres optimalizációval

**Új tervezési munka F6-Silicon-hoz (az F6-FPGA-n felül):**
- Floorplan: **~2–4 mérnökhét**
- Power gating és clock tree CTS: **~1 mérnökhónap**
- DFT scan chain insertion: **~2 mérnökhét**
- Tape-out checklist és sign-off: **~1 mérnökhónap**
- **Összesen: ~2-3 mérnökhónap plusz munka**

**Kimenet:**
- `mpw/` — eFabless/IHP submission könyvtár
- `mpw/firmware/` — boot-loader, mikrokód image, Nano/Rich kód-loader
- `hw/chipignite-board/` — ChipIgnite (vagy IHP) bring-up board

**Kész kritérium:**
- Heterogén lapka legyártva és a kezedben
- A négy F4 demó valós szilíciumon a Nano core-okon
- Rich core demó: teljes C# webhandler (tömbök, stringek, kivételek) silicon-on
- Heterogén demó: Rich supervisor + Nano neurális háló silicon-on
- **Nagyobb SNN demó:** MNIST klasszifikátor 32-48 Nano core-on, 1-2 Rich coordinator-ral, valós szilíciumon
- **Akka.NET cluster demó** valós szilíciumon
- **Energia / teljesítmény mérés** ARM Cortex-M4 / RISC-V RV32 ellen, event-driven workload-okon — **az F6-FPGA power becslés validálása**

**Függőség:** **F6-FPGA kész**, sweet spot kiválasztva, multi-konfiguráció riport elérhető, a kiválasztott (Rich, Nano) konfiguráció minden teszten zöld.

**Költség-nagyságrend:** ~$9,750 (eFabless ChipIgnite, 100 db bring-up chip-pel), vagy ~€0–3k (IHP MPW, ha ingyenes shuttle nyílik), vagy $0 (Open MPW free shuttle, ha elérhető).

---

### F6.5 — Secure Edition parallel tape-out (opcionális)

**Cél:** A CLI-CPU Secure Edition parallel tape-out változata, amely a Secure Element / TEE / JavaCard piacot célozza. Ugyanaz az alap architektúra (Nano + Rich core), **plusz** Secure Element-specifikus hardveres komponensek: Crypto Actor (SPECT-ihletett), TRNG, PUF, secure boot + attestation, tamper detection, DPA countermeasures, OTP kulcstárolás.

**Részletes dokumentum:** [`docs/secure-element.md`](secure-element.md) — ez rögzíti a teljes Secure Element pozicionálást, a TROPIC01 (Tropic Square első nyílt kereskedelmi SE) részletes elemzését, a megkülönböztető architektúrális előnyöket (multi-core, több független security domain egyetlen chipen), a tanúsítási útvonalat (EAL-5+), és a konkrét termékcsaládot (open banking card, open eSIM, open eID, open FIDO2 authenticator, open TPM, open hardware wallet, open V2X, open medical SE).

**Miért „F6.5" és nem „F6"?** Mert ez **egy parallel tape-out variáns**, nem egy önálló fázis. Ugyanaz a F5 RTL alap, csak kiegészítve a Secure Element hardveres komponensekkel. Az F6-Silicon Cognitive Fabric tape-out után **~6 hónappal** készíthető el — a Secure Edition silicon-előfeltétel, ezért az F6.5 az F6-Silicon variánsra épít, **nem** az F6-FPGA-ra.

**Új funkciók az F6-hoz képest:**
- **Crypto Actor** — SPECT-ihletett dedikált kriptográfiai egység (AES, SHA, ECC, post-quantum: Kyber/Dilithium/Falcon)
- **TRNG** — true random number generator (ring oscillator jitter + whitening)
- **PUF** — Physically Unclonable Function (SRAM PUF + error correction)
- **OTP / eFuse tároló** — write-once root key storage
- **Secure boot + remote attestation** — mérési lánc és chip identity
- **Tamper detection** — 6 komponens (EM pulse, voltage glitch, temperature, laser, active shield, frequency monitor)
- **DPA countermeasures** — masking, hiding, constant-time, noise injection

**Becsült plusz tervezési munka:** ~30-50 mérnökhónap (F6-hoz képest), egy 3-5 fős csapat számára ~1-1.5 év.

**Becsült plusz terület:** ~64k std cell Sky130-on (~32% növekedés az F6 ~200k-hoz képest). **Belefér** egy ChipIgnite MPW-ba (~10 mm²) vagy egy IHP SG13G2 MPW-ba (~15 mm²).

**Kész kritérium:**
- F6.5 tape-out sikeresen elkészül
- Első bring-up board legyártva
- Crypto Actor helyesen implementálja a cél algoritmusokat
- Tamper detection triggerel a tesztelt támadásokra (voltage glitch, EM, laser)
- TRNG megfelel a NIST SP 800-90B entrópia követelményeknek
- Első **Common Criteria pre-evaluation** megkezdődik

**Függőség:** F6-Silicon Cognitive Fabric tape-out kész (az F6-FPGA önmagában nem elegendő, mert a Secure Element komponensek — Crypto Actor, TRNG, PUF, tamper detection — silicon-specifikus hardvert igényelnek).

**Költség-nagyságrend:** ~$10-50k (MPW tape-out) + ~$0.5-1.2M (plusz mérnökbér) + ~$400k-1M (later Common Criteria evaluation).

**Tanúsítási cél (F7 utáni):** **Common Criteria EAL-5+** a BSI (Németország) vagy ANSSI (Franciaország) akkreditált laborban. **Idő**: 2-3 év az evaluation-re. **Várható első kereskedelmi termékek**: 2033-2034.

---

### F7 — Demonstrációs platform + Neuron OS fejlesztői SDK

**Cél:** A Cognitive Fabric + Neuron OS kombináció mint **demonstrálható, fejleszthető platform** több valós use-case-re. A `Neuron OS` itt lép ki kutatási státuszból valós fejlesztői platform szintre.

**A Neuron OS teljes víziója egy külön dokumentumban**: [`docs/neuron-os.md`](neuron-os.md). Röviden: aktor-alapú operációs rendszer, amely az Erlang OTP víziót valósítja meg hardveres támogatással (Erlang in silicon). Everything is an actor, shared-nothing, let it crash, supervision hierarchia, capability-alapú biztonság, hot code loading, location transparency.

**Kimenet:**
- **Referencia PCB-k** több use-case-re:
  - IoT szenzor node (QSPI flash, PSRAM, LoRa/WiFi, néhány szenzor)
  - Akka.NET cluster demó dev kit (több chip hálózatban)
  - SNN inference board (MNIST/CIFAR szintű feladatra)
- **Neuron OS fejlesztői SDK**:
  - `NeuronOS.Core` — aktor alapkönyvtár (Actor<T>, Supervisor, Spawn, Send, Receive)
  - `NeuronOS.Devices` — device aktor library (UART, GPIO, QSPI, timer)
  - `NeuronOS.Distributed` — inter-chip aktor protokoll
  - `dotnet publish` target Neuron OS-re
  - VSCode / VS extension debugger aktor message replay-jel
  - NuGet csomagok publikus feed-en
- **Referencia C# demó alkalmazások:**
  - Akka.NET-szerű actor cluster (supervisor hierarchia, hot code loading)
  - LIF spiking neural network 32-48 Nano core-on
  - IoT edge gateway (szenzor handlerek + LoRa protokoll)
  - Multi-agent szimuláció (Boids, Conway's Game of Life kiterjesztése)
- **Publikációs anyag:** cikk, előadás, demo video — az egész projektet bemutató narratíva, Linux Foundation projekt-státusz kérelem

**Függőség:** F6 kész, chip a kézben, Neuron OS alfa (F5 óta) stabil.

**Megjegyzés a Neuron OS fázisolásáról:** A Neuron OS **nem önálló fázis**, hanem **organikusan épül fel** az F1-F7 fázisok mentén:
- **F1**: minimal `NeuronOS.Core` library a C# szimulátorban (Actor<T>, in-memory mailbox)
- **F3**: egy-aktoros bootloader a Tiny Tapeout chipen (echo neuron demó)
- **F4**: 4-aktoros rendszer scheduler + router kezdeti implementációval
- **F5**: teljes supervision fa, per-core GC, capability-alapú isolation, Roslyn source generator a `[RunsOn]` attribútumra
- **F6**: hot code loading, writable microcode, elosztott aktorok több chipen
- **F7**: fejlesztői SDK, VSCode integráció, NuGet publikálás, valódi alkalmazás demók

Részletek és fejlesztői API példák: [`docs/neuron-os.md`](neuron-os.md).

---

## Függőségi gráf

```
                          ┌── Nano core út ──┐         ┌── Rich core út ──┐
                          │                  │         │                  │
F0 ──► F1 ──► F2 ──► F3 ──┘──► F4 ──►────────┘─► F5 ──┴──► F6-FPGA ──► F7
  spec   sim    RTL    TT       multi-         heterogén   maximum     demo
              │         1×      Nano          (Rich+Nano) demonstration + Neuron
              │         +        4×            FPGA       (K7-325T /     OS SDK
              │        mbox     FPGA                       K7-480T,      ▲
              │              ▲                             OpenXC7)      │
              └──── FPGA ────┘                                │          │
                 (opcionális                                  │          │
                  korai F2 után)                              │          │
                                                              ▼          │
                                                       F6-Silicon ───────┘
                                                       (opcionális,
                                                        halasztható,
                                                        Sky130 / IHP MPW
                                                        ~$10k)
                                                              │
                                                              ▼
                                                         F6.5 ──► Secure Edition
                                                          parallel tape-out
                                                          (Crypto Actor + TRNG +
                                                          PUF + tamper + DPA)
                                                              │
                                                              ▼
                                                     Common Criteria EAL-5+
                                                     evaluation (~2-3 év)
                                                              │
                                                              ▼
                                                   Kereskedelmi SE termékek
                                                   (open wallet, eSIM, eID,
                                                    FIDO, TPM, V2X, medical)
```

Az F2 után opcionálisan FPGA-n is futtatható a CIL-T0 subset, még F3 (Tiny Tapeout) előtt — ez segít a bring-up board tervezésében.

## Három kulcs pivot a roadmap történetében

**1. pivot — F4: Cognitive Fabric irány (shared-nothing multi-core)**

A **korábbi** F4 a „CIL object model + GC FPGA-n" volt, a mostani **új** F4 viszont a „4-core multi-core FPGA Cognitive Fabric". Az object model + GC átcsúszott F5-re. A **hardware alap (stack-gép core) nem változik** — F3-ból emelődik át F4-be, csak 4 példányban. Ezzel a pivot **minimális kódcserével** megvalósítható, és megőrzi minden eddigi F0-F3 munkát. Ez a lépés megkülönbözteti a CLI-CPU-t a történelmi picoJava/Jazelle bukásoktól.

**2. pivot — F5: Heterogén Nano + Rich terminológia**

A korábbi „F5 — CIL Object Model + GC egymagos kiterjesztés" címet átneveztük **„F5 — Rich core (teljes CIL) FPGA-n, első heterogén rendszer"** címre. Technikailag a tartalom majdnem ugyanaz (teljes CIL kiterjesztés), de most már explicite úgy fogalmazzuk, hogy itt **születik meg a Rich core** mint a Nano core „nagy testvére". Az F6 ezek után egy **heterogén Nano+Rich multi-core chip**, analóg módon az ARM big.LITTLE, Apple P/E-core, Intel Alder Lake modellekhez. Lásd `docs/architecture.md` „Heterogén multi-core: Nano + Rich" szekciót.

**3. pivot — F6: F6-FPGA mint elsődleges, F6-Silicon mint opcionális**

A **korábbi** F6 egyetlen célt definiált: **eFabless ChipIgnite vagy IHP SG13G2 silicon tape-out** ~$10k költséggel. A **mostani új** F6 **két párhuzamos variánst** ad: **F6-FPGA** (elsődleges, ajánlott) és **F6-Silicon** (opcionális, halasztható). Az F6-FPGA a legnagyobb OpenXC7-támogatott Xilinx FPGA-kat (Kintex-7 325T és 480T) **maxolja ki** különböző (Rich, Nano) kombinációkkal — **100% nyílt toolchain end-to-end**, **~$200-400 költség**, **órák alatti rebuild ciklus**, **adatvezérelt sweet spot keresés** a tényleges silicon tape-out előtt. **A pivot oka**: az OpenXC7 jelenlegi technikai határa (Kintex-7) **pontosan elég** a Cognitive Fabric architektúra teljes demonstrálásához, és a CLI-CPU **nyílt forráskódú filozófiájához** tisztábban illeszkedik a 100% reprodukálható, audálható FPGA build, mint egy zárt foundry processzre épülő silicon tape-out. **Az F6-Silicon nem törlődik**, csak **opcionálissá és halasztottá** válik — csak akkor indul, ha kereskedelmi termék, F6.5 Secure Edition, vagy valós energia mérés silicon-előfeltétel jelentkezik.

## Mai státusz

**F0 koncepcionálisan készen van.** Hét dokumentum a `docs/` és a `README.md` alatt együtt ~3500+ sor, belsőleg konzisztens projekt-terv a **hárompályás pozicionálással** (Cognitive Fabric + Trustworthy Silicon + Secure Edition), a heterogén Nano+Rich multi-core modellel, a silicon-grade security pozicionálással, a Neuron OS vízióval, és a Secure Element stratégiai tervvel (F6.5 parallel tape-out).

**F1 — C# referencia szimulátor lezárva.** Az `src/CilCpu.Sim` és `src/CilCpu.Sim.Tests` projektek **218 zöld xUnit teszttel**, **0 warning, 0 error** állapotban. Minden a CIL-T0 spec által rögzített **48 opkód** implementálva van (`nop`, konstansok, lokális/argumentum hozzáférés, stack manipuláció, aritmetika, összehasonlítás, rövid branch-ek, `call`/`ret`, `ldind.i4`/`stind.i4` ECMA-335 byte-értékekkel, `break`), és minden hardveres trap (stack over/underflow, invalid opcode, invalid local/arg, invalid branch/call target, div-by-zero, overflow, call depth exceeded, debug break, **invalid memory access**) trigger-elhető és tesztelt. Az **F1 aranypélda**: `Fibonacci(20) = 6765` zöld a header-vezérelt `Execute` overload-on, ahogy a faktoriális (n=10 → 3628800) és iteratív GCD is. A fejlesztés **4 iterációban** zajlott szigorú TDD-vel, minden iterációhoz Devil's Advocate review, a fázis lezárását egy Finalizer QR pass adta, amely a critical fix-eket és a CLAUDE.md compliance-t ellenőrizte.

**Következő érdemi lépés:** **F1.5** — `CilCpu.Sim.Runner` CLI futtató és egy `samples/` mappa Roslyn-nal CIL-T0-ba fordított példa programokkal, majd **F2 — RTL** kezdete (Verilog vagy Amaranth HDL döntés, cocotb testbench infrastruktúra).
