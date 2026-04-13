# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projekt

**CLI-CPU** — nyílt forráskódú processzor, amely .NET CIL bytecode-ot hajt végre natívan hardverben. "Cognitive Fabric": több kis, független core egyetlen chipben, mailbox-alapú üzenetküldéssel.

Jelenlegi fázis: **F1.5 KÉSZ** (szimulátor + linker + CLI runner, TDD). A roadmap F0–F7-ig terjed (spec → RTL → FPGA → szilícium → Neuron OS).

## Build és teszt

```bash
# Teljes build
dotnet build CLI-CPU.sln -c Debug

# Összes teszt futtatása
dotnet test

# Egyetlen teszt osztály futtatása
dotnet test --filter "FullyQualifiedName~TCpuIter3ArithmeticTests"

# Egyetlen teszt futtatása
dotnet test --filter "FullyQualifiedName~Fibonacci_Iterative_10_Returns_55"

# Build restore nélkül (ha már le volt fordítva)
dotnet build CLI-CPU.sln -c Debug --no-restore
```

```bash
# Runner CLI — .t0 bináris futtatása
dotnet run --project src/CilCpu.Sim.Runner -- run samples/program.t0 --args 2,3

# Runner CLI — .dll linkelése .t0 binárisra
dotnet run --project src/CilCpu.Sim.Runner -- link assembly.dll --class Pure --method Add -o output.t0
```

**Keretrendszer:** .NET 10.0, xUnit 2.9.3, `TreatWarningsAsErrors=true`, `Nullable=enable`

## Architektúra

```
C# forráskód → dotnet build → .dll (Roslyn IL)
    → TCliCpuLinker.Link() → CIL-T0 bináris
    → TCpu.Execute() → TDecoder → TExecutor → eredmény/trap
```

### Projektek

| Projekt | Szerep |
|---------|--------|
| `CilCpu.Sim` | Referencia szimulátor: TCpu, TDecoder, TExecutor, TEvaluationStack, TCallStack, TFrame, TMethodHeader |
| `CilCpu.Linker` | Roslyn .dll → CIL-T0 bináris konverzió (System.Reflection.Metadata) |
| `CilCpu.Sim.Runner` | CLI futtatóeszköz: `run` (`.t0` bináris futtatás) és `link` (`.dll` → `.t0` konverzió) |
| `CilCpu.Sim.Tests` | xUnit tesztek (267+), minden projekthez |
| `samples/PureMath` | Példa: tiszta int-only statikus C# függvények, CIL-T0 kompatibilis |

### Végrehajtási pipeline kulcs osztályok

- **TCpu** (`src/CilCpu.Sim/TCpu.cs`) — fő végrehajtó motor, program counter, halt/trap kezelés
- **TExecutor** (`src/CilCpu.Sim/TExecutor.cs`) — 48 opkód végrehajtási logika
- **TDecoder** (`src/CilCpu.Sim/TDecoder.cs`) — bináris → opkód dekódolás
- **TCliCpuLinker** (`src/CilCpu.Linker/TCliCpuLinker.cs`) — assembly linkelés, call-token feloldás

### CIL-T0 ISA

48 opkód, int32-only, objektumok nélkül. Részletes spec: `docs/ISA-CIL-T0.md`

Memória modell:
- CODE: 0x0000_0000 (1 MB), DATA: 0x1000_0000 (256 KB), STACK: 0x2000_0000 (16 KB)
- MMIO/Mailbox: 0xF000_0000 (F3-tól)

### Trap kezelés

`TTrapException` + `TTrapReason` enum: StackUnderflow, StackOverflow, DivByZero, InvalidMemoryAccess, InvalidCallTarget stb.

## Elnevezési konvenciók

| Elem | Prefix | Példa |
|------|--------|-------|
| Osztály, record, enum | `T` | `TCpu`, `TOpcode`, `TTrapReason` |
| Interfész | `I` | `IService` |
| Metódus paraméter | `A` | `AProgram`, `AArgCount` |
| Privát mező | `F` | `FCallStack`, `FProgramCounter` |

## Dokumentáció

Kétnyelvű (hu/en) XML doc kötelező minden publikus tagon:
```csharp
/// <summary>
/// hu: Magyar leírás
/// <br />
/// en: English description
/// </summary>
```

A `docs/` könyvtár tartalmazza az architektúrát, roadmap-et, ISA spec-et, biztonsági modellt és a Neuron OS víziót.

## Függőségek

- **CilCpu.Sim**: nulla külső NuGet csomag
- **CilCpu.Linker**: csak System.Reflection.Metadata (beépített)
- **Tesztek**: xUnit, Microsoft.CodeAnalysis.CSharp (Roslyn kódelemzés a linker tesztekhez)
