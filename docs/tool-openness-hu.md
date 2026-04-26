# CLI-CPU — Eszközök nyitottsága és a „libre silicon" stratégia

> English version: [tool-openness-en.md](tool-openness-en.md)
>
> Verzió: 1.0

Ez a dokumentum a CLI-CPU projekt fejlesztéséhez használt eszközök **licencelési státuszát** és a **nyitottsági stratégiát** rögzíti. Az NLnet NGI Zero Commons Fund pályázat explicit módon említi a „libre silicon"-t mint támogatási kritériumot, és ezért fontos, hogy a projekt filozófiája ebben a kérdésben átlátható és konzisztens legyen.

## Alapelv — két elkülönített szint

A CLI-CPU projekt **két különálló nyitottsági dimenziót** különböztet meg:

1. **Output nyitottság** — amit a projekt **létrehoz** (RTL, silicon GDSII, dokumentáció, szoftver, Symphact): **teljesen nyílt forráskódú**.
2. **Process nyitottság** — amit a projekt **használ** a fejlesztés során (dev tool-ok, CAD, szimulátor): **pragmatikus mix**.

**Az output 100%-ban libre, a process-ben minden olyan eszköz nyílt, ahol reális alternatíva van, és csak ott használunk zárt eszközt, ahol a hardver vagy a shuttle platform ezt megköveteli.**

Ez a stratégia megfelel az iparági gyakorlatnak: a **SpinalHDL, NaxRiscv, LibreCores** projektek, valamint szinte minden NLnet-támogatott libre silicon projekt hasonló modellt követ.

## Az outputok — teljesen nyílt forráskódú

| Output | Licenc | Hol található |
|--------|--------|---------------|
| CLI-CPU ISA specifikáció | CC-BY-SA 4.0 | `docs/ISA-CIL-T0-hu.md` |
| C# referencia szimulátor | MIT | `src/CilCpu.Sim/` |
| C# linker és runner | MIT | `src/CilCpu.Linker/`, `src/CilCpu.Sim.Runner/` |
| xUnit tesztek (259+) | MIT | `src/CilCpu.Sim.Tests/` |
| Verilog RTL (ALU, decoder, microcode) | Apache 2.0 | `rtl/src/` |
| cocotb tesztbench | Apache 2.0 | `rtl/tb/` |
| FPGA bring-up smoke teszt | Apache 2.0 | `rtl/fpga/smoke_test/` |
| Roadmap, architektúra, biztonsági modell | CC-BY-SA 4.0 | `docs/` |
| Symphact víziódokumentum és SDK (F7) | MIT + Apache 2.0 | `Symphact/` |
| Silicon GDSII (F3, F6-Silicon) | Apache 2.0 | `tt/`, `mpw/` |

**Mindegyik a projekt GitHub repójában publikus, pull request-ekre nyitott, közösségi hozzájárulás fogadott.**

## A process — fázis-szintű tool mátrix

Az alábbi táblázat minden fejlesztési fázisban felsorolja a használt eszközöket és azok licencelési státuszát.

### F0 — Specifikáció

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| Markdown, Git | Dokumentumkezelés | Public / GPL-2.0 | ✅ |
| GitHub | Hosting, issue tracker, PR | Zárt platform | ⚠️ (de GitLab mirror lehetséges) |

### F1 — C# referencia szimulátor (KÉSZ)

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| .NET 10 SDK | Platform | MIT | ✅ |
| Roslyn C# compiler | Fordítás | Apache 2.0 | ✅ |
| xUnit 2.9.3 | Teszt framework | Apache 2.0 | ✅ |
| Microsoft.CodeAnalysis.CSharp | Linker-hez | Apache 2.0 | ✅ |

**Teljes open source.**

### F1.5 — Linker, Runner, Samples (KÉSZ)

Ugyanaz mint F1 — `System.Reflection.Metadata` (beépített .NET, MIT) hozzáadva.

**Teljes open source.**

### F2 — RTL (folyamatban)

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| Verilog (nyelv) | RTL leírás | Szabvány (IEEE 1364) | ✅ |
| Verilator | Szimuláció | LGPL-3 | ✅ |
| cocotb | Teszt framework Python-ban | BSD-3 | ✅ |
| Yosys | Szintézis (Sky130 célra, F2.6) | ISC | ✅ |
| GTKWave | Waveform viewer (debug) | GPL-2 | ✅ |

**Teljes open source.**

### F2.7 — FPGA validáció (most tartunk itt, 2026-04-24)

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| **Vivado ML Standard 2024.2** | FPGA szintézis + bitstream | AMD EULA (gratis, zárt) | ❌ **zárt** |
| A7-Lite 200T board | Fizikai hardver | MicroPhase (zárt HW tervek) | ❌ **zárt** |

**Itt vannak zárt eszközök.** A teljes projektben **ez az egyetlen olyan fázis, ahol a fejlesztéshez zárt tool kell**.

### F3 — Tiny Tapeout (silicon)

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| OpenLane2 | Silicon P&R automatizáció | Apache 2.0 | ✅ |
| Magic | Layout editor | BSD-szerű | ✅ |
| KLayout | GDSII viewer | GPL-3 | ✅ |
| Netgen | LVS (Layout vs Schematic) | GPL-2 | ✅ |
| Sky130 PDK | Nyílt PDK (SkyWater/Google) | Apache 2.0 | ✅ |
| Yosys | Szintézis | ISC | ✅ |
| OpenROAD | Placement + Routing | BSD-3 | ✅ |
| Tiny Tapeout harness | Kész shuttle környezet | Apache 2.0 | ✅ |

**Teljes open source silicon pipeline.**

### F4–F5, F6-FPGA — Multi-core és heterogén FPGA

Ugyanaz mint F2.7 — **Vivado** az FPGA-ra, a többi (szimuláció, RTL, verifikáció, tesztek) **open source**.

### F6-Silicon — „Cognitive Fabric Zero / One" (silicon)

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| OpenLane2 / Caravel / OpenFrame harness | ChipIgnite (Sky130) | Apache 2.0 | ✅ |
| IHP Open PDK | IHP SG13G2 (alternatíva) | Apache 2.0 | ✅ |
| Minden F3 tool | Ugyanaz | | ✅ |

**Teljes open source silicon pipeline.**

### F7 — Symphact SDK

| Eszköz | Szerep | Licenc | Nyílt? |
|--------|--------|--------|--------|
| .NET 10 + Roslyn | Platform | MIT / Apache 2.0 | ✅ |
| NuGet | Package manager | Apache 2.0 | ✅ |
| Visual Studio Code | Fejlesztői IDE | MIT (code), zárt (Microsoft.Code build) | ⚠️ VSCodium nyílt build használható |

**Szinte teljes open source** — csak az opcionális VSCode telemetria-tartalmú build a zárt.

## Miért Vivado — és miért most még nem OpenXC7?

A F2.7 és F4–F5 fázisokban a Vivado az egyetlen zárt tool. Három konkrét ok:

**1. A hardver diktálja.** A MicroPhase A7-Lite egy **Xilinx Artix-7** chip. Ennek a bitstream formátuma **zárt**, és natívan **csak a Xilinx/AMD Vivado** tudja generálni. Nem a választás kényszere, hanem a fizikai hardveré.

**2. Van nyílt alternatíva: OpenXC7 — és érettebb, mint sokan gondolják.** Az **OpenXC7** (Yosys + Nextpnr + Project X-Ray) **aktívan karbantartott** projekt (utolsó commit a `prjxray-db`-ben 2026-04-24, azaz napokon belül, az `nextpnr-xilinx`-ben 2026-04-18). A Xilinx 7-series teljes családját támogatja, beleértve az Artix-7-et.

**Mi működik 2026 áprilisában a mi A7-Lite 200T-nkhöz:**
- A **`xc7a200tfbg484`** (pontosan a mi chipünk) **szerepel a prjxray-db-ben** mind a 4 speed grade-del (1, 2, 2L, 3)
- **Alapprimitívek bővek:** `MMCME2_ADV/BASIC`, `PLLE2_ADV/BASIC`, `OSERDESE2`, `ISERDESE2`, `IDDR`, `ODDR`, `IDELAYE2`, `ODELAYE2`, `IDELAYCTRL`, `BUFG`, `BUFGCTRL`, `BUFH`, `BUFHCE`, `DSP48E1`, `GTPE2_COMMON`, `GTPE2_CHANNEL`
- **DDR3 demó létezik** Arty S7 (Spartan-7) board-ra, hasonló primitive-családcsal — az Artix-7 DDR3 MIG jó eséllyel közel van a stabil állapothoz
- ✅ **LED blink smoke-teszt LEFUTOTT az A7-Lite 200T-n** (2026-04-24): Yosys 0.38 → nextpnr-xilinx 0.8.2 → fasm2frames → xc7frames2bit teljes pipeline-on. Bitstream: 9.3 MB uncompressed, chipdb: 331 MB (egyszer generálódik). Lásd `rtl/fpga/smoke_test/OpenXC7/` a reprodukálható build-hez.
- ✅ **Board programozás openFPGALoader v1.1.1-gyel, Vivado teljes kikerülésével** (2026-04-24): WSL2 + usbipd-win USB-passthrough → `openFPGALoader --cable ft232 --fpga-part xc7a200tfbg484 --bitstream led_blink.bit` → `isc_done 1 init 1 done 1` → LED-ek villognak. **A teljes F2.7 fejlesztői ciklus (synth + P&R + bitstream + programozás) lefuttatható 100% open source toolchain-en**.

**Amit NEM tudunk biztosan:**
- Konkrét **XC7A200T demó a `demo-projects` repóban nincs** (a legnagyobb validált Artix-7 demó a 100T)
- **Gigabit Ethernet demó sehol a repó-családban nincs** — ez az F6 multi-board bridge-nek kritikus
- **Vivado vs OpenXC7 QoR benchmark nincs publikus** — a ~20-30%-os gyengülés amit becslésünk szerint várni lehet, valódi mérésre vár
- **DDR3 MIG calibration** az A7-Lite-unkon működik-e stabil módon — nem dokumentált

**Reális timeline az átálláshoz:** **6–18 hónap** (2026 második fele – 2027 közepe) alatt az OpenXC7 valószínűleg párhuzamos CI-ba tehető a CLI-CPU-hoz — különösen, mert az F2.7 LED blink és a F4 Nano core elvileg **nem használ DDR3-at vagy Ethernet-et**, csak alap MMCM-et és UART-ot. Az F5 (DDR3 a GC heap-hez) és F6 (Ethernet bridge) csak akkor vár OpenXC7-re, ha addig valaki validálja az A7-Lite-on.

**3. Vivado ML Standard INGYENES.** A WebPACK license (`Vivado ML Standard Edition`) **költségmentes**, és minden Artix-7 chip-et támogat az XC7A200T-ig. Nincs pénzügyi vagy jogi korlátozás kutatási, hobbi, vagy akár kereskedelmi felhasználásra. Ez „gratis" (ingyenes), bár nem „libre" (szabad forráskódú).

**Gratis ≠ libre, de a gyakorlatban a különbség csak akkor számít, ha:**
- A projekt **nem tudja reprodukálni** az eredményeit zárt tool nélkül — **a CLI-CPU tudja**, mert a silicon pipeline (F3, F6-Silicon) teljesen nyílt
- A zárt tool **hiányzó funkciót kényszerít** ki — a Vivado nem diktál design-korlátokat
- A tool megszűnése **blokkolná a fejlődést** — a Vivado 20+ éve elérhető, az AMD várhatóan fenntartja

## Út a nagyobb nyitottság felé

Három konkrét lépés, amivel a CLI-CPU projekt proaktívan csökkentheti a Vivado-függést:

### 1. OpenXC7 párhuzamos CI flow (F4 körül, 2026 második fele)

A mostani becslés alapján már az **F4** fázis idején (4-core Cognitive Fabric FPGA, csak MMCM + UART, sem DDR3, sem Ethernet) bevezethető a **párhuzamos CI**:
- Minden RTL PR lefutja a **Vivado** szintézist (hivatalos bitstream-hez)
- **És** lefutja az **OpenXC7** szintézist (verifikációhoz, hogy nincs Vivado-specifikus kód)

Ez **nem növeli** a függést, **csökkenti** — garantálja, hogy a kódban semmi Vivado-only konstrukció nem szivárog be. Már a **F2.7 LED blink** szintjén is érdemes egy kísérleti OpenXC7 build-et futtatni, hogy tanuljuk a toolchain erősségeit és gyengéit a saját projektünkön.

**F5+ (DDR3, F6 (Ethernet) OpenXC7-re áttelepítés** attól függ, hogy:
- Az A7-Lite DDR3 MIG calibration stabil-e OpenXC7 flow-val (2026 folyamán valószínűleg validálódik, akár a közösség, akár mi magunk által)
- A Gigabit Ethernet RGMII elég megbízhatóan működik-e

Ha ezek validálódnak 2027 közepéig, az F6-Silicon tape-out előtt **teljes Vivado-free FPGA pipeline-t** is elérhetünk.

### 2. Yosys Sky130 szintézis jelenleg (F2.6)

Az **F2.6** fázis kimenete: **Yosys** szintézis **Sky130 PDK**-ra. Ez **Vivado nélkül** működik, és az F3 Tiny Tapeout submission-höz ez az útvonal kerül használatra. A Vivado ebben a fázisban **nem is kerül elő** — a silicon gyártás path 100%-ban nyílt.

Tehát a **„hivatalos" silicon bitstream** (a Tiny Tapeout chipre) **teljes open source toolchain**-nel készül — a Vivado **csak a köztes FPGA fejlesztés-verifikáció** fázisban szerepel.

### 3. Hosszú távú cél — teljes OpenXC7 migráció

A projekt dokumentált szándéka, hogy **amint az OpenXC7 érettsége engedi** (várhatóan 2027 közepére az F2–F4 scope-ra, 2027 végére vagy 2028 elejére az F5–F6 DDR3/Ethernet scope-ra), a teljes FPGA flow-t átállítja nyílt toolchain-re. Ez **csak idő kérdése** — nem új design szükséges, a meglévő Verilog RTL megy mindkettőn.

## Összevetés más libre silicon projektekkel

| Projekt | Silicon toolchain | FPGA dev tool | Policy |
|---------|-------------------|---------------|--------|
| **CLI-CPU (ez)** | OpenLane2 / Sky130 (nyílt) | Vivado (zárt) | Silicon nyílt, FPGA pragmatikus |
| **NaxRiscv** (SpinalHDL) | OpenLane / Sky130 (nyílt) | Vivado (Kintex-7) | Ugyanaz |
| **OpenPiton** | Multi-fab (részben nyílt) | Vivado / Quartus | Ugyanaz |
| **PicoRV32** | Yosys + OpenLane (nyílt) | Vivado / iCE40 nyílt | Ahol tud, nyitott |
| **CVA6 (Ariane)** | PULP flow + OpenLane | Vivado (Genesys-2) | Ugyanaz |

**Ez az iparági norma libre silicon projekteknél.** Az NLnet evaluátorok és a közösség egyaránt ismerik és elfogadják — amíg az **output** és a **silicon pipeline** nyílt, a zárt FPGA dev tool **pragmatikus kényszer**, nem ideológiai megalkuvás.

## Összefoglalás — „Mi a CLI-CPU libre silicon státusza?"

- **A projekt összes eredménye (RTL, ISA, specifikáció, szoftver, silicon) nyílt forráskódú.** ✅
- **A silicon gyártási pipeline (F3, F6-Silicon) teljesen nyílt forráskódú.** ✅
- **Az FPGA fejlesztési fázisokban (F2.7, F4–F5, F6-FPGA) a Vivado zárt, de ingyenes.** ⚠️
- **A projekt proaktívan tervez átállni nyílt FPGA toolchain-re (OpenXC7), amint az érettsége engedi.** ✅
- **Ez az iparági standard libre silicon projekteknél, az NLnet elfogadja ezt a modellt.** ✅

**A CLI-CPU egyértelműen libre silicon projekt** — a „libre" jelző a projekt outputjára és a silicon pipeline-re vonatkozik, nem minden egyes dev tool-ra. Az **gratis de nem libre** Vivado-használat az FPGA dev fázisokban pragmatikus választás, nem kompromisszum.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-24 | Kezdeti verzió — az FPGA bring-up (F2.7 smoke teszt) alkalmából írva, amikor a Vivado először került be a dev flow-ba. Az OpenXC7 érettség-felmérés a repó közvetlen vizsgálata alapján (xc7a200tfbg484 a prjxray-db-ben, MMCM/PLL/IDDR/ODDR/IDELAY/DSP48/SerDes/GTP primitívek támogatva, aktív karbantartás). |
