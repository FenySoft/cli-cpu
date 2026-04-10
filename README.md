# CLI-CPU

> Egy CPU, amelynek **natív utasításkészlete a .NET CIL** (Common Intermediate Language, ECMA-335).
> Nincs JIT. Nincs AOT. Nincs interpreter. A CIL bájtok közvetlenül a hardverbe mennek.

## Mi ez?

A CLI-CPU egy kutatási és gyártási projekt, amelynek célja egy olyan processzor tervezése és elkészítése, amely a .NET szerelvények (`.dll`, `.exe`) CIL bájtkódját **natívan, fordítási lépés nélkül** hajtja végre. Ez pontosan ugyanaz a filozófia, amit a Sun picoJava és az ARM Jazelle követett a Java bytecode-hoz — csak itt a .NET CIL a cél, és **ma, modern open-source silicon eszközökkel** valósítjuk meg.

## Miért?

Három motiváció együtt:

1. **Teljesítmény** — nincs JIT warmup, nincs AOT build lépés, azonnali indulás.
2. **IoT** — a CIL 30–50%-kal tömörebb, mint a RISC-V RV32I vagy ARM Thumb-2 kód ugyanarra a funkcióra → kevesebb flash, kevesebb fogyasztás, kisebb BOM.
3. **Biztonság** — hardveres típusellenőrzés, stack overflow/underflow trap, GC write barrier mellékhatásként minden `stfld` után. A managed memory safety a szilíciumban él, nem egy runtime-ban, amit esetleg megkerülhetnek.

## Státusz

**F0 — Specifikáció fázis.** A dokumentumok íródnak. Kód még nincs.

Lásd [docs/roadmap.md](docs/roadmap.md) a teljes fázisolásért.

## Dokumentumok

- [docs/roadmap.md](docs/roadmap.md) — Fázisos ütemterv F0-tól F7-ig
- [docs/architecture.md](docs/architecture.md) — CLI-CPU architektúra áttekintés, prior art
- [docs/ISA-CIL-T0.md](docs/ISA-CIL-T0.md) — CIL-T0 subset specifikáció (Tiny Tapeout cél)

## Gyártási útvonal

| Fázis | Cél | Platform |
|-------|-----|----------|
| F0 | Spec dokumentumok | — |
| F1 | C# referencia szimulátor (TDD) | .NET |
| F2 | RTL (Verilog/Amaranth) + cocotb | szimuláció |
| F3 | **Tiny Tapeout submission (CIL-T0 subset)** | Sky130, ~$150 |
| F4–F5 | Teljes CIL kiterjesztés FPGA-n | Artix-7 / ECP5 |
| F6 | **eFabless ChipIgnite — teljes CIL szilícium** | Sky130 Caravel, ~$10k |
| F7 | Bring-up board + demo | PCB |

## Licenc

TBD
