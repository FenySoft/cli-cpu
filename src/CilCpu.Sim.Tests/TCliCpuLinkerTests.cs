using CilCpu.Linker;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCliCpuLinker integrációs tesztjei. A teszt a Roslyn natív
/// outputjából (egy classlib .dll byte tömbjéből) indul, lefordítja
/// CIL-T0 .t0 binárisra, majd a TCpu szimulátoron futtatja, és
/// ellenőrzi az eredményt. Ez a teljes pipeline (C# → Roslyn → linker
/// → szimulátor) end-to-end validációja.
/// <br />
/// en: Integration tests for TCliCpuLinker. Each test starts from
/// Roslyn-native output (a classlib .dll byte array), links it to a
/// CIL-T0 .t0 binary, runs it on the TCpu simulator, and verifies the
/// result. This is the end-to-end validation of the full pipeline
/// (C# → Roslyn → linker → simulator).
/// </summary>
public class TCliCpuLinkerTests
{
    /// <summary>
    /// hu: TDD iteráció 1 — minimal pure function. A 'public static int
    /// Add(int a, int b) => a + b;' Roslyn natív output-ja átfordul
    /// CIL-T0-ra, és a TCpu szimulátoron Add(2, 3) eredménye 5.
    /// <br />
    /// en: TDD iteration 1 — minimal pure function. The 'public static
    /// int Add(int a, int b) => a + b;' Roslyn-native output translates
    /// to CIL-T0, and the TCpu simulator returns 5 for Add(2, 3).
    /// </summary>
    [Fact]
    public void Link_AddTwoNumbers_TCpuReturnsSum()
    {
        const string source = """
            public static class Pure
            {
                public static int Add(int a, int b)
                {
                    return a + b;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Add");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [2, 3]);

        Assert.Equal(5, cpu.Peek(0));
        Assert.Equal(1, cpu.StackDepth);
    }

    /// <summary>
    /// hu: TDD iteráció 2 — rekurzív self-call. A Fibonacci forrásban
    /// két 'call' instrukció van (Fib(n-1) és Fib(n-2)), amelyek a
    /// linkernek a token → abszolút RVA átalakítást igénylik. A
    /// Fibonacci(20) = 6765 az F1 fázis aranypéldájának megfelelő
    /// integration teszt — most a teljes Roslyn-natív pipeline-on át.
    /// <br />
    /// en: TDD iteration 2 — recursive self-call. The Fibonacci source
    /// has two 'call' instructions (Fib(n-1) and Fib(n-2)) that require
    /// the linker to perform token → absolute RVA resolution. The
    /// Fibonacci(20) = 6765 mirrors the F1 golden integration test,
    /// now over the full Roslyn-native pipeline.
    /// </summary>
    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 1)]
    [InlineData(2, 1)]
    [InlineData(3, 2)]
    [InlineData(5, 5)]
    [InlineData(10, 55)]
    [InlineData(20, 6765)]
    public void Link_Fibonacci_TCpuReturnsCorrectValue(int n, int expected)
    {
        const string source = """
            public static class Math
            {
                public static int Fibonacci(int n)
                {
                    if (n < 2) return n;
                    return Fibonacci(n - 1) + Fibonacci(n - 2);
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Fibonacci");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [n]);

        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: TDD iteráció 3a — cross-method call. A SumOfSquares hívja a
    /// Square-t — két metódus egy .t0 binárisban, a linkernek mindkettőt
    /// be kell foglalnia és a call tokeneket a helyes RVA-kra feloldania.
    /// <br />
    /// en: TDD iteration 3a — cross-method call. SumOfSquares calls
    /// Square — two methods in one .t0 binary, the linker must include
    /// both and resolve call tokens to the correct RVAs.
    /// </summary>
    [Fact]
    public void Link_SumOfSquares_CrossMethodCall_Returns25()
    {
        const string source = """
            public static class Pure
            {
                public static int Square(int x)
                {
                    return x * x;
                }

                public static int SumOfSquares(int a, int b)
                {
                    return Square(a) + Square(b);
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "SumOfSquares");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [3, 4]);

        Assert.Equal(25, cpu.Peek(0)); // 9 + 16
    }

    /// <summary>
    /// hu: TDD iteráció 3b — lokális változóval rendelkező metódus. A GCD
    /// iteratív változata 'int t' lokálist használ (Roslyn ldloc/stloc-ot
    /// generál), amit a linkernek fel kell ismernie a metaadat-ból, és a
    /// CIL-T0 method header-be be kell írnia.
    /// <br />
    /// en: TDD iteration 3b — method with local variables. The iterative
    /// GCD uses an 'int t' local (Roslyn generates ldloc/stloc), which
    /// the linker must detect from metadata and encode in the CIL-T0
    /// method header.
    /// </summary>
    [Theory]
    [InlineData(48, 18, 6)]
    [InlineData(100, 75, 25)]
    [InlineData(17, 13, 1)]
    [InlineData(0, 5, 5)]
    public void Link_Gcd_WithLocals_ReturnsCorrectValue(int a, int b, int expected)
    {
        const string source = """
            public static class Math
            {
                public static int Gcd(int a, int b)
                {
                    while (b != 0)
                    {
                        int t = b;
                        b = a % b;
                        a = t;
                    }
                    return a;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Gcd");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [a, b]);

        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: TDD iteráció 4a — a verifier detektálja a statikus mező
    /// használatot (ldsfld/stsfld), ami NEM CIL-T0 kompatibilis.
    /// A linker TCilT0LinkException-t dob.
    /// <br />
    /// en: TDD iteration 4a — the verifier detects static field usage
    /// (ldsfld/stsfld), which is NOT CIL-T0 compatible. The linker
    /// throws a TCilT0LinkException.
    /// </summary>
    [Fact]
    public void Link_StaticField_ThrowsCilT0LinkException()
    {
        const string source = """
            public static class Bad
            {
                private static int _counter = 0;
                public static int Increment()
                {
                    _counter++;
                    return _counter;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        var ex = Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "Bad", "Increment"));

        Assert.Contains("0x", ex.Message);
    }

    /// <summary>
    /// hu: TDD iteráció 4b — a verifier detektálja a string literál
    /// használatot (ldstr), ami NEM CIL-T0 kompatibilis.
    /// <br />
    /// en: TDD iteration 4b — the verifier detects string literal usage
    /// (ldstr), which is NOT CIL-T0 compatible.
    /// </summary>
    [Fact]
    public void Link_StringLiteral_ThrowsCilT0LinkException()
    {
        const string source = """
            public static class Bad
            {
                public static int Foo()
                {
                    string s = "hello";
                    return s.Length;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        var ex = Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "Bad", "Foo"));

        Assert.Contains("0x", ex.Message);
    }

    /// <summary>
    /// hu: TDD iteráció 4c — a verifier detektálja a tömb használatot
    /// (newarr/ldelem/stelem), ami NEM CIL-T0 kompatibilis.
    /// <br />
    /// en: TDD iteration 4c — the verifier detects array usage
    /// (newarr/ldelem/stelem), which is NOT CIL-T0 compatible.
    /// </summary>
    [Fact]
    public void Link_ArrayUsage_ThrowsCilT0LinkException()
    {
        const string source = """
            public static class Bad
            {
                public static int Foo(int n)
                {
                    int[] arr = new int[n];
                    arr[0] = 42;
                    return arr[0];
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        var ex = Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "Bad", "Foo"));

        Assert.Contains("0x", ex.Message);
    }

    // =====================================================================
    // hu: FIZIKAI DLL TESZTEK — valódi `dotnet build` kimenettel.
    //     A samples/PureMath/PureMath.csproj Release build-je a PureMath.dll
    //     fájlt generálja, amit a linker és a szimulátor feldolgoz.
    //     Ez a teljes fejlesztői workflow validációja.
    // en: PHYSICAL DLL TESTS — with real `dotnet build` output.
    //     The Release build of samples/PureMath/PureMath.csproj generates
    //     the PureMath.dll file, which the linker and simulator process.
    //     This validates the complete developer workflow.
    // =====================================================================

    /// <summary>
    /// hu: A fizikai DLL elérési útjának meghatározása. A teszt a
    /// repo gyökéréből indul, és a samples/PureMath/bin/Release/net10.0/
    /// könyvtárban keresi a PureMath.dll-t.
    /// <br />
    /// en: Resolves the physical DLL path. The test starts from the repo
    /// root and looks for PureMath.dll in samples/PureMath/bin/Release/net10.0/.
    /// </summary>
    private static byte[] LoadPureMathDll()
    {
        // hu: Keressük a repo gyökerét — a .sln fájl mellett.
        // en: Find repo root — next to the .sln file.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);

        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "CLI-CPU.sln")))
            dir = dir.Parent;

        Assert.NotNull(dir);

        var dllPath = Path.Combine(dir!.FullName, "samples", "PureMath", "bin", "Release", "net10.0", "PureMath.dll");

        if (!File.Exists(dllPath))
            throw new FileNotFoundException(
                $"PureMath.dll not found. Run 'dotnet build samples/PureMath/PureMath.csproj -c Release' first.",
                dllPath);

        return File.ReadAllBytes(dllPath);
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — Add(2, 3) = 5. A PureMath.dll-t valódi
    /// 'dotnet build -c Release' állította elő, NEM runtime Roslyn.
    /// <br />
    /// en: Physical DLL test — Add(2, 3) = 5. PureMath.dll was produced by
    /// a real 'dotnet build -c Release', NOT runtime Roslyn compilation.
    /// </summary>
    [Fact]
    public void PhysicalDll_Add_Returns5()
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Add");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [2, 3]);

        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — Fibonacci(20) = 6765. Ez az aranypélda
    /// teszt a valódi 'dotnet build' kimeneten.
    /// <br />
    /// en: Physical DLL test — Fibonacci(20) = 6765. The golden test
    /// on real 'dotnet build' output.
    /// </summary>
    [Fact]
    public void PhysicalDll_Fibonacci20_Returns6765()
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Fibonacci");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [20]);

        Assert.Equal(6765, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — Factorial(10) = 3628800. Iteratív loop
    /// lokális változókkal.
    /// <br />
    /// en: Physical DLL test — Factorial(10) = 3628800. Iterative loop
    /// with local variables.
    /// </summary>
    [Fact]
    public void PhysicalDll_Factorial10_Returns3628800()
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Factorial");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [10]);

        Assert.Equal(3628800, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — Gcd(48, 18) = 6. While loop lokális
    /// változóval.
    /// <br />
    /// en: Physical DLL test — Gcd(48, 18) = 6. While loop with local
    /// variable.
    /// </summary>
    [Fact]
    public void PhysicalDll_Gcd48_18_Returns6()
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Gcd");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [48, 18]);

        Assert.Equal(6, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — SumOfSquares(3, 4) = 25. Cross-method call
    /// (SumOfSquares → Square) valódi DLL-ből.
    /// <br />
    /// en: Physical DLL test — SumOfSquares(3, 4) = 25. Cross-method call
    /// (SumOfSquares → Square) from a real DLL.
    /// </summary>
    [Fact]
    public void PhysicalDll_SumOfSquares_Returns25()
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "SumOfSquares");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [3, 4]);

        Assert.Equal(25, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — IsPrime(17) = 1, IsPrime(18) = 0.
    /// Komplex branch logika lokálissal, while loop-pal.
    /// <br />
    /// en: Physical DLL test — IsPrime(17) = 1, IsPrime(18) = 0.
    /// Complex branch logic with locals and while loop.
    /// </summary>
    [Theory]
    [InlineData(2, 1)]
    [InlineData(3, 1)]
    [InlineData(4, 0)]
    [InlineData(17, 1)]
    [InlineData(18, 0)]
    [InlineData(97, 1)]
    [InlineData(100, 0)]
    public void PhysicalDll_IsPrime_ReturnsCorrectValue(int n, int expected)
    {
        var dllBytes = LoadPureMathDll();
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "IsPrime");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [n]);

        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fizikai DLL teszt — Max(7, 12) = 12, Min(7, 12) = 7, Abs(-5) = 5.
    /// Egyszerű ternary operátorok.
    /// <br />
    /// en: Physical DLL test — Max(7, 12) = 12, Min(7, 12) = 7, Abs(-5) = 5.
    /// Simple ternary operators.
    /// </summary>
    [Fact]
    public void PhysicalDll_MaxMinAbs_ReturnCorrectValues()
    {
        var dllBytes = LoadPureMathDll();

        var cpuMax = new TCpu();
        var t0Max = TCliCpuLinker.Link(dllBytes, "Math", "Max");
        cpuMax.Execute(t0Max, 0, [7, 12]);
        Assert.Equal(12, cpuMax.Peek(0));

        var cpuMin = new TCpu();
        var t0Min = TCliCpuLinker.Link(dllBytes, "Math", "Min");
        cpuMin.Execute(t0Min, 0, [7, 12]);
        Assert.Equal(7, cpuMin.Peek(0));

        var cpuAbs = new TCpu();
        var t0Abs = TCliCpuLinker.Link(dllBytes, "Math", "Abs");
        cpuAbs.Execute(t0Abs, 0, [-5]);
        Assert.Equal(5, cpuAbs.Peek(0));
    }

    // ------------------------------------------------------------------
    // hu: Lefedetlen ág tesztek — linker edge case-ek
    // en: Uncovered branch tests — linker edge cases
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Link null assembly byte-okkal ArgumentNullException-t dob.
    /// <br />
    /// en: Link with null assembly bytes throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void Link_NullAssemblyBytes_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TCliCpuLinker.Link(null!, "Foo", "Bar"));
    }

    /// <summary>
    /// hu: Link null osztálynévvel ArgumentNullException-t dob.
    /// <br />
    /// en: Link with null class name throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void Link_NullClassName_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TCliCpuLinker.Link([], null!, "Bar"));
    }

    /// <summary>
    /// hu: Link null metódusnévvel ArgumentNullException-t dob.
    /// <br />
    /// en: Link with null method name throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void Link_NullMethodName_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TCliCpuLinker.Link([], "Foo", null!));
    }

    /// <summary>
    /// hu: Link nem létező metódussal TCilT0LinkException-t dob.
    /// <br />
    /// en: Link with non-existent method throws TCilT0LinkException.
    /// </summary>
    [Fact]
    public void Link_NonExistentMethod_ThrowsLinkException()
    {
        const string source = """
            public static class Pure
            {
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "Pure", "NonExistent"));
    }

    /// <summary>
    /// hu: Link nem létező osztálynévvel TCilT0LinkException-t dob.
    /// <br />
    /// en: Link with non-existent class name throws TCilT0LinkException.
    /// </summary>
    [Fact]
    public void Link_NonExistentClass_ThrowsLinkException()
    {
        const string source = """
            public static class Pure
            {
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "NonExistent", "Add"));
    }

    /// <summary>
    /// hu: Link nem CIL-T0 kompatibilis opkóddal (static field) TCilT0LinkException-t dob.
    /// <br />
    /// en: Link with non-CIL-T0 compatible opcode (static field) throws TCilT0LinkException.
    /// </summary>
    [Fact]
    public void Link_UnsupportedOpcode_ThrowsLinkException()
    {
        const string source = """
            public static class Bad
            {
                private static int _counter = 0;
                public static int Increment()
                {
                    _counter++;
                    return _counter;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.Link(dllBytes, "Bad", "Increment"));
    }

    /// <summary>
    /// hu: Link lokális változó nélküli metódussal sikeres.
    /// <br />
    /// en: Link with a method without locals succeeds.
    /// </summary>
    [Fact]
    public void Link_NoLocals_LinksSuccessfully()
    {
        const string source = """
            public static class Pure
            {
                public static int Identity(int a) => a;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Identity");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [42]);

        Assert.Equal(42, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link 0xFE prefix opkódot tartalmazó kóddal (ceq) sikeres.
    /// <br />
    /// en: Link with 0xFE-prefixed opcode (ceq) succeeds.
    /// </summary>
    [Fact]
    public void Link_FePrefixedOpcode_Ceq_LinksSuccessfully()
    {
        const string source = """
            public static class Logic
            {
                public static int IsEqual(int a, int b)
                {
                    if (a == b) return 1;
                    return 0;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Logic", "IsEqual");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [5, 5]);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link tranzitív hívással — az entry metódus hív egy másikat.
    /// <br />
    /// en: Link with transitive calls — the entry method calls another.
    /// </summary>
    [Fact]
    public void Link_TransitiveCall_LinksSuccessfully()
    {
        const string source = """
            public static class Math
            {
                public static int Double(int a) => Add(a, a);
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Math", "Double");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [7]);

        Assert.Equal(14, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // hu: OpcodeLength lefedetlen ág tesztek — bitwise és shift opkódok
    // en: OpcodeLength uncovered branch tests — bitwise and shift opcodes
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Link div opkóddal (0x5B) — Div(10, 2) = 5.
    /// <br />
    /// en: Link with div opcode (0x5B) — Div(10, 2) = 5.
    /// </summary>
    [Fact]
    public void Link_DivOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Div(int a, int b) => a / b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Div");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [10, 2]);

        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link bitwise AND opkóddal (0x5F) — And(12, 10) = 8.
    /// <br />
    /// en: Link with bitwise AND opcode (0x5F) — And(12, 10) = 8.
    /// </summary>
    [Fact]
    public void Link_BitwiseAndOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int And(int a, int b) => a & b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "And");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [12, 10]);

        Assert.Equal(8, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link bitwise OR opkóddal (0x60) — Or(12, 10) = 14.
    /// <br />
    /// en: Link with bitwise OR opcode (0x60) — Or(12, 10) = 14.
    /// </summary>
    [Fact]
    public void Link_BitwiseOrOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Or(int a, int b) => a | b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Or");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [12, 10]);

        Assert.Equal(14, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link bitwise XOR opkóddal (0x61) — Xor(12, 10) = 6.
    /// <br />
    /// en: Link with bitwise XOR opcode (0x61) — Xor(12, 10) = 6.
    /// </summary>
    [Fact]
    public void Link_BitwiseXorOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Xor(int a, int b) => a ^ b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Xor");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [12, 10]);

        Assert.Equal(6, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link shift left opkóddal (0x62) — Shl(3, 4) = 48.
    /// <br />
    /// en: Link with shift left opcode (0x62) — Shl(3, 4) = 48.
    /// </summary>
    [Fact]
    public void Link_ShiftLeftOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Shl(int a, int b) => a << b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Shl");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [3, 4]);

        Assert.Equal(48, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link shift right opkóddal (0x63) — Shr(48, 4) = 3.
    /// <br />
    /// en: Link with shift right opcode (0x63) — Shr(48, 4) = 3.
    /// </summary>
    [Fact]
    public void Link_ShiftRightOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Shr(int a, int b) => a >> b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Shr");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [48, 4]);

        Assert.Equal(3, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link bitwise NOT opkóddal (0x66) — Not(0) = -1.
    /// <br />
    /// en: Link with bitwise NOT opcode (0x66) — Not(0) = -1.
    /// </summary>
    [Fact]
    public void Link_BitwiseNotOpcode_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Not(int a) => ~a;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Not");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [0]);

        Assert.Equal(-1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link ldarg.s opkóddal (0x0E) — 5 paraméteres metódus,
    /// az 5. paraméter (index 4) ldarg.s-el töltődik be.
    /// Sum5(1, 2, 3, 4, 5) = 15.
    /// <br />
    /// en: Link with ldarg.s opcode (0x0E) — 5-parameter method,
    /// the 5th parameter (index 4) is loaded via ldarg.s.
    /// Sum5(1, 2, 3, 4, 5) = 15.
    /// </summary>
    [Fact]
    public void Link_LdargS_FiveParams_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Sum5(int a, int b, int c, int d, int e)
                    => a + b + c + d + e;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Sum5");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [1, 2, 3, 4, 5]);

        Assert.Equal(15, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Link starg.s opkóddal (0x10) — paraméterhez értékadás.
    /// Egy metódus, amelyik módosítja saját paraméterét, majd visszaadja.
    /// IncrParam(10) = 11.
    /// <br />
    /// en: Link with starg.s opcode (0x10) — assignment to parameter.
    /// A method that modifies its own parameter and returns it.
    /// IncrParam(10) = 11.
    /// </summary>
    [Fact]
    public void Link_StargS_ParameterAssignment_ReturnsCorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int IncrParam(int a, int b, int c, int d, int e)
                {
                    e = e + 1;
                    return e;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "IncrParam");

        var cpu = new TCpu();
        cpu.Execute(t0Bytes, 0, [0, 0, 0, 0, 10]);

        Assert.Equal(11, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // hu: ResolveCallTokens és OpcodeLength direkt unit tesztek —
    //     internal metódusok hiba-ágai (InternalsVisibleTo).
    // en: ResolveCallTokens and OpcodeLength direct unit tests —
    //     internal method error branches (InternalsVisibleTo).
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ResolveCallTokens non-MethodDef token (tableType != 0x06)
    /// esetén TCilT0LinkException-t dob.
    /// <br />
    /// en: ResolveCallTokens throws TCilT0LinkException when encountering
    /// a non-MethodDef token (tableType != 0x06).
    /// </summary>
    [Fact]
    public void ResolveCallTokens_NonMethodDefToken_ThrowsLinkException()
    {
        // hu: Kézzel készített IL: call 0x0A000001 (MemberRef token, tableType=0x0A)
        // en: Hand-crafted IL: call 0x0A000001 (MemberRef token, tableType=0x0A)
        var il = new byte[] { 0x28, 0x01, 0x00, 0x00, 0x0A };
        var methodRva = new Dictionary<System.Reflection.Metadata.MethodDefinitionHandle, int>();

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.ResolveCallTokens(il, methodRva));
    }

    /// <summary>
    /// hu: ResolveCallTokens ismeretlen MethodDef target esetén
    /// TCilT0LinkException-t dob.
    /// <br />
    /// en: ResolveCallTokens throws TCilT0LinkException when the
    /// MethodDef target is not found in the linked methods.
    /// </summary>
    [Fact]
    public void ResolveCallTokens_UnknownMethodDefTarget_ThrowsLinkException()
    {
        // hu: Kézzel készített IL: call 0x06000099 (MethodDef token, row 153 — nem létezik)
        // en: Hand-crafted IL: call 0x06000099 (MethodDef token, row 153 — doesn't exist)
        var il = new byte[] { 0x28, 0x99, 0x00, 0x00, 0x06 };
        var methodRva = new Dictionary<System.Reflection.Metadata.MethodDefinitionHandle, int>();

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.ResolveCallTokens(il, methodRva));
    }

    /// <summary>
    /// hu: OpcodeLength truncált 0xFE prefix esetén (program vége)
    /// TCilT0LinkException-t dob.
    /// <br />
    /// en: OpcodeLength throws TCilT0LinkException when 0xFE prefix
    /// is truncated (at end of program).
    /// </summary>
    [Fact]
    public void OpcodeLength_TruncatedFePrefix_ThrowsLinkException()
    {
        var program = new byte[] { 0xFE };

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.OpcodeLength(0xFE, program, 0));
    }

    /// <summary>
    /// hu: OpcodeLength érvénytelen 0xFE-prefixes opkód (0xFE 0x99)
    /// esetén TCilT0LinkException-t dob.
    /// <br />
    /// en: OpcodeLength throws TCilT0LinkException for invalid
    /// 0xFE-prefixed opcode (0xFE 0x99).
    /// </summary>
    [Fact]
    public void OpcodeLength_InvalidFePrefixedOpcode_ThrowsLinkException()
    {
        var program = new byte[] { 0xFE, 0x99 };

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.OpcodeLength(0xFE, program, 0));
    }

    /// <summary>
    /// hu: OpcodeLength nem támogatott opkód (0xA0 — nem a CIL-T0 készletben)
    /// esetén TCilT0LinkException-t dob.
    /// <br />
    /// en: OpcodeLength throws TCilT0LinkException for unsupported
    /// opcode (0xA0 — not in CIL-T0 set).
    /// </summary>
    [Fact]
    public void OpcodeLength_UnsupportedOpcode_ThrowsLinkException()
    {
        var program = new byte[] { 0xA0 };

        Assert.Throws<TCilT0LinkException>(() =>
            TCliCpuLinker.OpcodeLength(0xA0, program, 0));
    }

    /// <summary>
    /// hu: OpcodeLength egybyte-os opkódok, amelyek a linker integrációs
    /// teszteken NEM fordulnak elő (dup, pop, ldind.i4, stind.i4, break).
    /// <br />
    /// en: OpcodeLength single-byte opcodes that do NOT appear in linker
    /// integration tests (dup, pop, ldind.i4, stind.i4, break).
    /// </summary>
    [Theory]
    [InlineData(0x25, 1)] // dup
    [InlineData(0x26, 1)] // pop
    [InlineData(0x4A, 1)] // ldind.i4
    [InlineData(0x54, 1)] // stind.i4
    [InlineData(0xDD, 1)] // break
    [InlineData(0x65, 1)] // neg
    [InlineData(0x00, 1)] // nop
    [InlineData(0x14, 1)] // ldnull
    [InlineData(0x0E, 2)] // ldarg.s
    [InlineData(0x10, 2)] // starg.s
    [InlineData(0x11, 2)] // ldloc.s
    [InlineData(0x13, 2)] // stloc.s
    [InlineData(0x1F, 2)] // ldc.i4.s
    [InlineData(0x2B, 2)] // br.s
    [InlineData(0x20, 5)] // ldc.i4
    [InlineData(0x28, 5)] // call
    public void OpcodeLength_AllCilT0Opcodes_ReturnsCorrectLength(byte AOpcode, int AExpectedLength)
    {
        var program = new byte[8];
        program[0] = AOpcode;

        var length = TCliCpuLinker.OpcodeLength(AOpcode, program, 0);

        Assert.Equal(AExpectedLength, length);
    }

    /// <summary>
    /// hu: OpcodeLength érvényes 0xFE prefix opkódok (0x01-0x05) helyes
    /// hosszat adnak vissza (2 byte).
    /// <br />
    /// en: OpcodeLength returns correct length (2 bytes) for valid
    /// 0xFE-prefixed opcodes (0x01-0x05).
    /// </summary>
    [Theory]
    [InlineData(0x01)] // ceq
    [InlineData(0x02)] // cgt
    [InlineData(0x03)] // cgt.un
    [InlineData(0x04)] // clt
    [InlineData(0x05)] // clt.un
    public void OpcodeLength_ValidFePrefixedOpcodes_Returns2(byte ASecondByte)
    {
        var program = new byte[] { 0xFE, ASecondByte };

        var length = TCliCpuLinker.OpcodeLength(0xFE, program, 0);

        Assert.Equal(2, length);
    }
}
