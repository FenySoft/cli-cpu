# Hozzájárulás a CLI-CPU projekthez

> English version: [CONTRIBUTING.md](CONTRIBUTING.md)

Köszönjük, hogy érdeklődsz a CLI-CPU projekt iránt!

## Első lépések

```bash
git clone https://github.com/FenySoft/cli-cpu.git
cd cli-cpu
dotnet build CLI-CPU.sln -c Debug
dotnet test
```

**Követelmények:** .NET 10.0, `TreatWarningsAsErrors=true`, `Nullable=enable`

## Fejlesztési szabályok

### Teszt-vezérelt fejlesztés (TDD) — kötelező

Minden új funkció, javítás vagy refaktor **teszttel kezdődik**:
1. Először a teszt — **buknia kell** (piros)
2. Minimális kód, ami zöldre fordítja (zöld)
3. Refaktor — a tesztek továbbra is zöldek
4. Commit — csak zöld tesztekkel

**Mikor NEM kell teszt:**
- Tisztán UI/AXAML view fájlok
- Konfigurációs fájlok (manifest, props, csproj)
- Dokumentáció (md, txt)

### Elnevezési konvenciók

| Elem | Prefix | Példa |
|------|--------|-------|
| Osztály, record, enum | `T` | `TCpu`, `TOpcode` |
| Interfész | `I` | `IService` |
| Metódus paraméter | `A` | `AProgram`, `AArgCount` |
| Privát mező | `F` | `FCallStack`, `FProgramCounter` |

**Megjegyzés:** Record property-ken NEM használunk `A` prefixet — az `A` csak metódus paramétereknél.

### Kód formázás

Vezérlési szerkezetek előtt és után üres sor (`if`, `while`, `for`, `switch`, `try`):

```csharp
// Helyes
x = 1;
y = 2;

if (x > 0)
    DoA();

z = 3;
```

### Dokumentáció

Kétnyelvű XML doc megjegyzés kötelező minden publikus tagon:
```csharp
/// <summary>
/// hu: Magyar leírás
/// <br />
/// en: English description
/// </summary>
```

### Commit üzenetek

Formátum: `<típus>: <Rövid magyar összefoglaló>`

Típusok: `fix`, `feat`, `refactor`, `docs`, `chore`, `test`, `perf`

A commit üzenetek kétnyelvűek (magyar + angol):
```
<típus>: <Rövid magyar összefoglaló>

hu: <Magyar részletes leírás — mit és miért>

en: <Angol részletes leírás — mit és miért>
```

**Build szám:** Minden commit előtt a `BuildNumberV2.txt` értékét növeld 1-gyel.

### Tesztek futtatása

```bash
# C# szimulátor tesztek
dotnet test

# RTL (Verilog) tesztek — az rtl/tb/ könyvtárból
cd rtl/tb && PATH="$PATH:$HOME/Library/Python/3.9/bin" make test_alu
```

### Pull Request-ek

1. Fork-old a repository-t
2. Hozz létre egy feature branch-et
3. Először a tesztet írd meg (TDD) — a tesztnek **buknia kell** (piros)
4. Implementáld a kódot, amíg a teszt zöldre nem fordul
5. Győződj meg, hogy minden teszt zöld (`dotnet test`)
6. Küldj egy PR-t világos leírással

## Architektúra áttekintés

Részletek: [docs/architecture-en.md](docs/architecture-en.md) — a teljes architektúra dokumentáció.

## Licenc

A hozzájárulásaiddal elfogadod, hogy azok a [CERN-OHL-S v2](LICENSE) licenc alá kerülnek.
