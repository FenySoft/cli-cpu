---
status: policy
---

# CLI-CPU Blog sorozat terv

> Belső tervező dokumentum — nem publikált a weboldalon.

> English version: [series-plan.md](series-plan.md)

> Version: 1.2

## Stratégia

- **Nyelv:** Angol (nemzetközi elérés), magyar fordításokkal a clicpu.org-on
- **Platform:** clicpu.org/en/blog/ + clicpu.org/hu/blog/ + Medium
- **Ütemezés:** Heti egy cikk
- **Cél:** Ismertség építése, GitHub csillagok, közösség, NLnet pályázat támogatása

## Tervezett cikkek

| # | Cím | Célközönség | Státusz |
|---|-----|-------------|---------|
| **1** | Miért építek CPU-t, ami natívan futtatja a .NET-et | Mindenki — a nagy kép | Publikált |
| **2** | 24 Core, nulla cache koherencia: hogyan veri a Shared-Nothing a multi-threadinget | CPU architektúra rajongók | Tervezett |
| **3** | 187 teszttől a szilíciumig: tesztvezérelt hardverfejlesztés | .NET / szoftverfejlesztők | Publikált |
| **4** | Hardverszintű biztonság mitigációk nélkül: miért nem tud hozzáérni a Spectre | Biztonsági közönség | Tervezett |
| **5** | A Symphact vízió: miért kell utód a Linux 1970-es évekbeli architektúrájának | OS / rendszerprogramozók | Tervezett |
| **6** | 8 millió .NET fejlesztő, egy hardverplatform: minden nyelv, natív szilícium | .NET közösség | Tervezett |

## 2. cikk — Vázlat

**Cím:** 24 Core, nulla cache koherencia: hogyan veri a Shared-Nothing a multi-threadinget

- A cache koherencia adója (a die terület 15-20%-a hagyományos CPU-kon)
- Miért hoznak csökkenő hozamot a plusz core-ok megosztott memóriával
- A CLI-CPU shared-nothing modellje: privát SRAM, hardveres mailbox FIFO-k
- A matek: 6R+16N+1S 15mm²-en vs 4-8 RISC-V core ugyanazon a területen
- Lineáris skálázás: miért fontos az aktor workload-oknál
- Tervezett mérések (aktor msg/sec, context switch, SNN throughput)

## 3. cikk — Publikált (2026-08-24)

**Cím:** 187 teszttől a szilíciumig: tesztvezérelt hardverfejlesztés
**URL:** `web/{hu,en}/blog/tdd-hardware.html`

- A TDD a szoftverben normális — hardverben ritka
- Hogyan írtunk 187 C# tesztet MIELŐTT bármilyen Verilog-ot írtunk volna
- Az arany vektor megközelítés: cocotb tesztek vs C# szimulátor
- Miért számít: bizalom, hogy az RTL megfelel a specnek
- A Fibonacci(20) = 6765 végponttól végpontig teszt
- F2.7: FPGA validáció a szilícium ELŐTT — a "nincs tape-out FPGA nélkül" elv

## 3.5. cikk — Publikált (2026-05-23)

**Cím:** Szimulációtól a valódi hardverig — az első FPGA futásunk
**URL:** `web/{hu,en}/blog/first-fpga.html`

- A szakadék a szimuláció és a valódi hardver között
- F2.7: egyetlen Nano core futása az A7-Lite XC7A200T-n
- Fibonacci(20) UART-on — az első "hello world" valódi szilíciumon (FPGA)
- Amit tanultunk: timing closure, I/O pin kiosztás, clock domain
- Miért spórol ez pénzt: hibák FPGA-n €0-ba kerülnek, ASIC-on $1300+-ba

## 4. cikk — Vázlat

**Cím:** Hardverszintű biztonság mitigációk nélkül: miért nem tud hozzáérni a Spectre

- A Spectre/Meltdown család: 7+ évnyi javítás, 5-30% teljesítményveszteség
- Miért vesztes játék a mitigáció
- A CLI-CPU megközelítése: a támadási felület megszüntetése, nem foltozása
- Nincs spekulatív végrehajtás, nincs branch predictor, nincs megosztott cache
- A Secure Core: dedikált bizalmi horgony a kód verifikációhoz
- ROP/JOP lehetetlen az ISA tervezéséből adódóan
- Formális verifikáció: miért számít a kis ISA

## 5. cikk — Vázlat

**Cím:** A Symphact vízió: miért kell utód a Linux 1970-es évekbeli architektúrájának

- A Linux örökölte az 1970-es Unix döntéseket: megosztott memória, fork/exec, POSIX
- Miért nem skálázódnak ezek 1000+ core-ra
- Az Erlang/OTP modell: 40 évnyi bizonyíték, hogy az aktorok működnek
- Symphact: minden aktor, hardveresen kényszerített izoláció
- Let it crash + felügyelet: hibatűrés az architektúrából
- Hot code loading: leállás nélküli frissítések

## 6. cikk — Vázlat

**Cím:** 8 millió .NET fejlesztő, egy hardverplatform

- A CIL nemzetközi szabvány (ECMA-335, ISO/IEC)
- Minden .NET nyelv CIL-re fordul: C#, F#, VB.NET
- Az F# mint a "tökéletes CLI-CPU nyelv" (immutable, pattern matching, aktorok)
- Miért nem ugyanaz a RISC-V + .NET AOT
- A vízió: natív szilícium a .NET ökoszisztéma számára

## Medium címkék

Használd ezeket a címkéket minden cikkhez:
- `dotnet`
- `cpu-architecture`
- `open-source`
- `fpga`
- `hardware-security`

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.2 | 2026-08-24 | 3. cikk publikálva (`tdd-hardware.html`), státusz és URL felvéve |
| 1.1 | 2026-07-17 | Tesztszám frissítve a tényleges CI-eredményre: 187 |
| 1.0 | 2026-04-15 | Kezdeti kiadás |
