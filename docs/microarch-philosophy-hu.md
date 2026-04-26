# CFPU Mikroarchitektúra Filozófia

> English version: [microarch-philosophy-en.md](microarch-philosophy-en.md)

> Version: 1.0

> **⚠️ Vízió-szintű dokumentum.** Ez az elemzés az F1.5 fázisban (referencia szimulátor + linker) megfogalmazott elméleti architekturális irányt rögzíti. A számszerű becslések irodalmi precedensek (picoJava-2, Cerebras WSE, Adapteva Epiphany, Tilera, Groq, SpiNNaker) extrapolációi, **nem RTL-szintű mérések**. A tényleges teljesítmény-, terület- és fogyasztási adatok csak az F4 RTL és F6 szilícium (Cognitive Fabric One MPW) után validálhatók — addig minden szám munkahipotézis, ami a roadmap minden fázisában felülvizsgálandó.

## Tézis

A CFPU mikroarchitektúrális filozófiája egyetlen mondatban:

> **Nem ILP-t maximalizálunk magon belül, hanem TLP-t magok között.**

Minden tranzisztor, amit egyetlen mag „okosabbá tételére" költenénk (Out-of-Order, mély pipeline, dinamikus branch predictor, registry rename, spekulatív végrehajtás), egy magból hiányzik. A modern OS-ek workload-ja természetes módon **több ezer szál**, ezeket a CFPU **1:1 vagy közeli arányban** szétosztja a magok között — a single-thread sebességet feláldozva a magszámért.

Ez egybecseng a `feedback_security_first.md` prioritással (biztonság > terület > sebesség): a spekulatív végrehajtás Spectre/Meltdown-osztályú támadásoknak nyit ajtót, az auditálhatóság (Seal core) pedig determinisztikus pipeline-t követel.

## Az adatpont, ami a tézist motiválja

### Modern iMac terhelése (mérési pillanatkép, 2026-04, M-osztályú chip)

| Metrika | Érték |
|---|---|
| Folyamatok | 930+ |
| Szálak | 4 300+ |
| Fizikai magok | 10–12 (4 P + 6–8 E) |
| Szál/mag arány | **~360–430** |
| Aktív szál egy adott pillanatban (becslés Activity Monitor 5–15% idle alapján) | ~50–150 |

A 4 300 szál többsége **blokkolt állapotú** — I/O-, mailbox-, timer-, GUI-event-várakozáson. De még ha csak ~100 szál fut bármely pillanatban, a 12 magnak akkor is forognia kell közöttük 10 ms quantummal.

### Hagyományos megoldás: kevés OoO mag time-slicing-gel

- 4 300 szál / 12 mag = 360 szál/mag
- Quantum 10 ms, scheduler bonyolult priority queue-t kezel
- Minden context switch-nél részleges cache-thrash (L1/L2 invalidálás)
- Modern Linux scheduler-overhead irodalmi értéke: ~3–8% rendszer idő pure scheduling-ra
- Minden további szál szigorúan **rosszabbá** teszi a mag-kihasználtságot

### CFPU megoldás: sok in-order mag persistent affinity-vel

- 4 300 szál / ~300 Rich mag = ~14 szál/mag
- Aktív szál / mag: **<1**
- **Minden aktív szál saját magot kap, nincs preempció**
- A blokkolt szálak fizikailag nem foglalják a magot — SRAM-frame-ben passzívan várnak mailbox-üzenetre
- Hardver-router osztja szét a beérkező üzeneteket idle magokhoz → **scheduler szerepe ~0**

A különbség nem fokozati, hanem kategorikus: a CFPU-n a single-mag *hatékonysága* kevésbé számít, mert a workload természete inherent párhuzamos.

## Alternatívák — döntés-trail

### A) Few cores + erős OoO/ILP (x86, Apple M, ARM Cortex-A75+)

- ~70 mag 100 mm²-en, mindegyik 4-IPC OoO
- Aggregate: ~280 utasítás/cycle
- **Spekulatív végrehajtás**: Spectre/Meltdown osztályú támadási felület
- Determinizmus elveszik → audit lehetetlen
- Cache koherencia protokoll (MOESI/MESIF) szükséges → drága, nem skálázódik

**Elvetve.** Indok:
- A `feedback_security_first.md` prioritás kizárja a spekulációt
- A Seal core auditálhatósága determinisztikus pipeline-t követel
- A multi-task workload-on amúgy sem a per-mag IPC számít, hanem az aggregate

### B) Many cores + in-order, statikus ILP (CFPU választás, Cerebras, Groq, Tenstorrent, Adapteva, SpiNNaker)

- ~300 Rich mag 100 mm²-en, mindegyik ~1,2-IPC in-order
- Aggregate: ~360 utasítás/cycle (ha a Linker párba állítja, ahol lehet)
- Spekuláció kizárva → side-channel mentes
- Linker felelős az utasítás-szintű párhuzamosításért (EPIC-stílus pair-bit + macro-op fusion)
- Determinisztikus pipeline → minden utasítás cycle-pontosan jósolható

**Választott.** Indok:
- Konzisztens biztonság-első prioritással
- Sok-magos és aktor-modellal természetesen összepárosul
- A Linker-szintű optimalizáció open source projektben olcsóbb, mint dinamikus HW

### C) Massive cores + minimal ISA (Cerebras WSE-3 stílusú extrém)

- ~10 000+ mag 100 mm²-en, mindegyik triviális
- Aggregate óriási, de ISA túl szegény általános C# kódhoz
- Speciális workload-ra (ML inference, neuron-szimuláció) ideális
- Általános futtatáshoz nem alkalmas

**Részben átvéve.** A Nano core ezt a szellemiséget képviseli (48 opkód, int32, 0,005 mm² 5nm-en); de a Rich/Actor megtartjuk az általános .NET kódhoz, hogy a CFPU egyetlen szubsztrátumon futtasson **mindkét** profilt.

## Mit nem építünk

A „nem építjük" lista épp olyan fontos, mint a „mit építünk":

- **Nincs Out-of-Order Execution** (a fenti döntés-trail B) ágában rögzítve)
- **Nincs spekulatív végrehajtás** — még branch prediction sem dinamikus history table alapján
- **Nincs registry rename engine** — ami stack→reg fordítás történik, az kizárólag dekódolás-szintű, statikus
- **Nincs reorder buffer**, scheduler queue, retire stage
- **Nincs mély pipeline** (>5–7 stage)
- **Nincs SMT** — egy mag egy szálat futtat egyszerre (a warm-context cache aktor-szintű váltást ad mailbox-érkezésre, lásd `core-types-hu.md`)

## Mit építünk — statikus ILP a Linker-ben

Az utasítás-szintű párhuzamosság nem dinamikus reordering-ből jön, hanem statikusan, `CilCpu.Linker` szinten generálva:

1. **Macro-op fusion decode-kor** — gyakori 3–4-utasításos minták (pl. `ldloc + ldloc + add`) egy fused opkód-csomagba. A HW felismeri, a `.t0` bináris kompatibilitása megmarad.
2. **Linker pair-bit annotation** — két egymás utáni utasítás közé jelet tesz, ha párhuzamosan kibocsátható (EPIC-stílus). Ez az Itanium-tanulság inverzelése: kevesebb HW spekuláció, okosabb fordító.
3. **In-order N-wide pipeline** — 2-wide a Rich-ben, 1-wide a Nano/Actor/Seal-ben. Ha a Linker párba állította és nincs hazard → 2 issue/cycle, különben 1.
4. **TOS register stack** — 16–32 reg fizikai stack-frame, nem SRAM. Eltünteti a port-bottleneck-et (lásd `internal-bus-hu.md`).
5. **Statikus branch hint** — Linker eldönti a forward/backward likely irányt (profile-guided vagy heurisztika); HW egy bit alapján prefetch-el. Dinamikus history table **nincs**.
6. **Wide internal bus** — 256/512/1024 bit core típustól függően; context move 1–3 cycle.

Mindezek **determinisztikus, auditálható** technikák — minden utasítás cycle-pontosan jósolható, side-channel mentesen.

## Throughput-számolás (becslés, nem mérés)

| Konfiguráció | Mag | Per-mag IPC | Aggregate IPC | Wall-clock 4300-task workloadon |
|---|---|---|---|---|
| Apple M3/M4 Pro (12 OoO) | 12 | ~4,0 | 48 | Referencia (1×) |
| ARM Cortex-A75 sok-mag (70× OoO 3-IPC, ugyanazon area) | 70 | ~3,0 | 210 | ~4× |
| **CFPU Rich (300× in-order 1,2-IPC)** | **300** | **~1,2** | **360** | **~7×** (clock-paritást feltételezve) |
| **CFPU vegyes (Rich+Actor+Nano, ~1 000× core)** | 1 000 | ~0,8 átlag | 800 | **~15×** |

**Korrekciós tényezők, amiket figyelembe kell venni:**

- **Clock különbség**: az M-chip ~4 GHz, a CFPU célzott ~1,5–2 GHz → 2–3×-os kompenzáció a CFPU rovására
- **Memória bandwidth**: a CFPU shared-nothing → DRAM kontroller-igény nő magszámmal
- **Workload-jelleg**: a 4300-task csak akkor érvényes, ha minden task valóban egymástól független; szigorú dependency lánc (pl. tisztán soros algoritmus) nem nyer

Net: a CFPU **várhatóan 2–5× nagyobb aggregate throughput-ot ad sok-task workloadon**, ugyanazon die-területen, modulo clock és memory-system kompenzáció.

> **Ez becslés, nem mérés.** F4 RTL és F6 szilícium után validálható.

## Validálási terv

A téziseket lépésről lépésre lehet csak igazolni:

1. **F1.5 (most)** — szimulátor szintű dynamic instruction count mérés a `samples/PureMath` benchmark-okon. Eredmény: utasítás-szám arány RV32 ekvivalenshez (Spike emulátor).
2. **F2 / F2.7 (FPGA)** — A7-Lite 200T-n a Rich core RTL-prototípus, cycle-accurate teljesítmény. Eredmény: ténylegesen mért IPC, clock domain validálva.
3. **F4 (multi-core RTL)** — egy 16-core cluster + interconnect, 4 300-thread szimulált workload. Eredmény: aggregate throughput, scheduler-overhead arány.
4. **F6 (silicon)** — Cognitive Fabric One MPW (15 mm², 6R+16N+1S), valós workload, valós power, valós area. Eredmény: a tézis empirikus igazolása vagy cáfolata.

A tézis **csak az F6 szilíciummal igazolható maradéktalanul.** Addig minden szám munka-becslés.

## Kapcsolódó dokumentumok

- [`core-types-hu.md`](core-types-hu.md) — a 4 core típus, mindegyik in-order, statikus ILP-vel
- [`internal-bus-hu.md`](internal-bus-hu.md) — busz méretezés a context-move bottleneck eliminálására
- [`interconnect-hu.md`](interconnect-hu.md) — magok közti kommunikáció: mailbox + router, lock-free
- [`security-hu.md`](security-hu.md) — biztonság-első prioritás, ami kizárja a spekulatív végrehajtást
- [`perf-vs-riscv-hu.md`](perf-vs-riscv-hu.md) — single-thread perf összehasonlítás módszertana
- [`architecture-hu.md`](architecture-hu.md) — átfogó CFPU architektúra

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|--------------|
| 1.0 | 2026-04-25 | Kezdeti verzió — TLP > ILP tézis, döntés-trail (few-OoO vs many-in-order vs minimal), 4 300-szál iMac adatpont, statikus ILP komponensek, validálási terv F1.5 → F6 |
