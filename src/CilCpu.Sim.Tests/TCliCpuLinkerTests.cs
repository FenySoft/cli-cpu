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
}
