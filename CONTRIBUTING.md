# Contributing to CLI-CPU

> Magyar verzió: [CONTRIBUTING-hu.md](CONTRIBUTING-hu.md)

Thank you for your interest in contributing to CLI-CPU!

## Getting Started

```bash
git clone https://github.com/FenySoft/cli-cpu.git
cd cli-cpu
dotnet build CLI-CPU.sln -c Debug
dotnet test
```

**Requirements:** .NET 10.0, `TreatWarningsAsErrors=true`, `Nullable=enable`

## Development Rules

### Test-Driven Development (TDD) — Mandatory

Every new feature, fix, or refactor **must start with a test**:
1. Write the test first — it must FAIL (red)
2. Implement the minimum code to make it pass (green)
3. Refactor — tests stay green
4. Commit — only with green tests

**When tests are NOT required:**
- Pure UI/AXAML view files
- Configuration files (manifest, props, csproj)
- Documentation (md, txt)

### Naming Conventions

| Element | Prefix | Example |
|---------|--------|---------|
| Class, record, enum | `T` | `TCpu`, `TOpcode` |
| Interface | `I` | `IService` |
| Method parameter | `A` | `AProgram`, `AArgCount` |
| Private field | `F` | `FCallStack`, `FProgramCounter` |

**Note:** Record properties do NOT use the `A` prefix — `A` is only for method parameters.

### Code Formatting

Empty line before and after control structures (`if`, `while`, `for`, `switch`, `try`):

```csharp
// Correct
x = 1;
y = 2;

if (x > 0)
    DoA();

z = 3;
```

### Documentation

Bilingual XML doc comments are required on all public members:
```csharp
/// <summary>
/// hu: Magyar leírás
/// <br />
/// en: English description
/// </summary>
```

### Commit Messages

Format: `<type>: <Short Hungarian summary>`

Types: `fix`, `feat`, `refactor`, `docs`, `chore`, `test`, `perf`

Commit messages are bilingual (Hungarian + English):
```
<type>: <Short Hungarian summary>

hu: <Detailed Hungarian description — what and why>

en: <Detailed English description — what and why>
```

**Build number:** Before each commit, increment `BuildNumberV2.txt` by 1.

### Running Tests

```bash
# C# simulator tests
dotnet test

# RTL (Verilog) tests — from rtl/tb/
cd rtl/tb && PATH="$PATH:$HOME/Library/Python/3.9/bin" make test_alu
```

### Pull Requests

1. Fork the repository
2. Create a feature branch
3. Write tests first (TDD) — tests must **fail** initially (red)
4. Implement the code until tests turn green
5. Ensure all tests pass (`dotnet test`)
6. Submit a PR with a clear description

## Architecture Overview

See [docs/architecture-en.md](docs/architecture-en.md) for the full architecture documentation.

## License

By contributing, you agree that your contributions will be licensed under [CERN-OHL-S v2](LICENSE).
