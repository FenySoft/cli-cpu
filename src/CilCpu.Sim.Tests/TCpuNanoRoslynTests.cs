using CilCpu.Linker;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpuNano Roslyn-alapú tesztjei. Minden teszt C# forrásból indul
/// (Roslyn → Linker → TCpuNano), hogy 100%-ban kompatibilisek legyünk
/// a fordítóval. A régi bytecode-alapú teszteket ezek váltják le.
/// <br />
/// en: Roslyn-based tests for TCpuNano. All tests start from C# source
/// (Roslyn → Linker → TCpuNano) for 100% compiler compatibility.
/// These replace the old bytecode-based tests.
/// </summary>
public class TCpuNanoRoslynTests
{
    private int Run(string ASource, string AClass = "Pure", string AMethod = "Run", int[]? AArgs = null)
    {
        var dllBytes = TRoslynCompiler.CompileToBytes(ASource);
        var binary = TCliCpuLinker.Link(dllBytes, AClass, AMethod);
        var cpu = new TCpuNano();
        cpu.Execute(binary, 0, AArgs);
        return cpu.Peek(0);
    }

    // ------------------------------------------------------------------
    // Aritmetika
    // ------------------------------------------------------------------

    [Fact]
    public void Add_2_3_Returns5() =>
        Assert.Equal(5, Run("public static class Pure { public static int Run(int a, int b) => a + b; }", AArgs: [2, 3]));

    [Fact]
    public void Sub_10_4_Returns6() =>
        Assert.Equal(6, Run("public static class Pure { public static int Run(int a, int b) => a - b; }", AArgs: [10, 4]));

    [Fact]
    public void Mul_7_8_Returns56() =>
        Assert.Equal(56, Run("public static class Pure { public static int Run(int a, int b) => a * b; }", AArgs: [7, 8]));

    [Fact]
    public void Div_20_4_Returns5() =>
        Assert.Equal(5, Run("public static class Pure { public static int Run(int a, int b) => a / b; }", AArgs: [20, 4]));

    [Fact]
    public void Rem_17_5_Returns2() =>
        Assert.Equal(2, Run("public static class Pure { public static int Run(int a, int b) => a % b; }", AArgs: [17, 5]));

    [Fact]
    public void Neg_Minus7_Returns7() =>
        Assert.Equal(7, Run("public static class Pure { public static int Run(int a) => -a; }", AArgs: [-7]));

    [Fact]
    public void Not_0_ReturnsMinus1() =>
        Assert.Equal(-1, Run("public static class Pure { public static int Run(int a) => ~a; }", AArgs: [0]));

    [Fact]
    public void And_0xFF_0x0F_Returns0x0F() =>
        Assert.Equal(0x0F, Run("public static class Pure { public static int Run(int a, int b) => a & b; }", AArgs: [0xFF, 0x0F]));

    [Fact]
    public void Or_0xF0_0x0F_Returns0xFF() =>
        Assert.Equal(0xFF, Run("public static class Pure { public static int Run(int a, int b) => a | b; }", AArgs: [0xF0, 0x0F]));

    [Fact]
    public void Xor_0xFF_0x0F_Returns0xF0() =>
        Assert.Equal(0xF0, Run("public static class Pure { public static int Run(int a, int b) => a ^ b; }", AArgs: [0xFF, 0x0F]));

    [Fact]
    public void Shl_1_4_Returns16() =>
        Assert.Equal(16, Run("public static class Pure { public static int Run(int a, int b) => a << b; }", AArgs: [1, 4]));

    [Fact]
    public void Shr_Minus16_2_ReturnsMinus4() =>
        Assert.Equal(-4, Run("public static class Pure { public static int Run(int a, int b) => a >> b; }", AArgs: [-16, 2]));

    // ------------------------------------------------------------------
    // Összehasonlítás és branch
    // ------------------------------------------------------------------

    [Fact]
    public void IfEqual_True_Returns1() =>
        Assert.Equal(1, Run("public static class Pure { public static int Run(int a, int b) => a == b ? 1 : 0; }", AArgs: [5, 5]));

    [Fact]
    public void IfEqual_False_Returns0() =>
        Assert.Equal(0, Run("public static class Pure { public static int Run(int a, int b) => a == b ? 1 : 0; }", AArgs: [5, 6]));

    [Fact]
    public void IfGreaterThan_True_Returns1() =>
        Assert.Equal(1, Run("public static class Pure { public static int Run(int a, int b) => a > b ? 1 : 0; }", AArgs: [10, 5]));

    [Fact]
    public void IfLessThan_True_Returns1() =>
        Assert.Equal(1, Run("public static class Pure { public static int Run(int a, int b) => a < b ? 1 : 0; }", AArgs: [3, 7]));

    [Fact]
    public void WhileLoop_Sum1To10_Returns55() =>
        Assert.Equal(55, Run("""
            public static class Pure
            {
                public static int Run(int n)
                {
                    int sum = 0;
                    int i = 1;
                    while (i <= n)
                    {
                        sum += i;
                        i++;
                    }
                    return sum;
                }
            }
            """, AArgs: [10]));

    [Fact]
    public void ForLoop_Factorial5_Returns120() =>
        Assert.Equal(120, Run("""
            public static class Pure
            {
                public static int Run(int n)
                {
                    int result = 1;
                    for (int i = 2; i <= n; i++)
                        result *= i;
                    return result;
                }
            }
            """, AArgs: [5]));

    // ------------------------------------------------------------------
    // Call / Ret — rekurzió
    // ------------------------------------------------------------------

    [Fact]
    public void Fibonacci_10_Returns55() =>
        Assert.Equal(55, Run("""
            public static class Pure
            {
                public static int Run(int n) => Fib(n);
                private static int Fib(int n)
                {
                    if (n < 2) return n;
                    return Fib(n - 1) + Fib(n - 2);
                }
            }
            """, AArgs: [10]));

    [Fact]
    public void GCD_48_18_Returns6() =>
        Assert.Equal(6, Run("""
            public static class Pure
            {
                public static int Run(int a, int b) => Gcd(a, b);
                private static int Gcd(int a, int b)
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
            """, AArgs: [48, 18]));

    [Fact]
    public void MultiCall_Chain_ReturnsCorrect() =>
        Assert.Equal(30, Run("""
            public static class Pure
            {
                public static int Run(int x) => A(x);
                private static int A(int x) => B(x) + 10;
                private static int B(int x) => C(x) + 10;
                private static int C(int x) => x + 10;
            }
            """, AArgs: [0]));

    // ------------------------------------------------------------------
    // Lokálisok és argumentumok
    // ------------------------------------------------------------------

    [Fact]
    public void Locals_Swap_ReturnsSwapped() =>
        Assert.Equal(3, Run("""
            public static class Pure
            {
                public static int Run(int a, int b)
                {
                    int temp = a;
                    a = b;
                    b = temp;
                    return a; // was b (3)
                }
            }
            """, AArgs: [5, 3]));

    [Fact]
    public void MultipleLocals_Complex_ReturnsCorrect() =>
        Assert.Equal(100, Run("""
            public static class Pure
            {
                public static int Run(int x)
                {
                    int a = x * 2;
                    int b = a + 10;
                    int c = b * 2;
                    int d = c - a;
                    return d; // (x*2+10)*2 - x*2 = x*2+20, x=40 → 100
                }
            }
            """, AArgs: [40]));

    // ------------------------------------------------------------------
    // Trap tesztek
    // ------------------------------------------------------------------

    [Fact]
    public void DivByZero_Traps()
    {
        var source = "public static class Pure { public static int Run(int a, int b) => a / b; }";
        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var binary = TCliCpuLinker.Link(dllBytes, "Pure", "Run");
        var cpu = new TCpuNano();

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(binary, 0, [10, 0]));

        Assert.Equal(TTrapReason.DivByZero, ex.Reason);
    }

    [Fact]
    public void RemByZero_Traps()
    {
        var source = "public static class Pure { public static int Run(int a, int b) => a % b; }";
        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var binary = TCliCpuLinker.Link(dllBytes, "Pure", "Run");
        var cpu = new TCpuNano();

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(binary, 0, [10, 0]));

        Assert.Equal(TTrapReason.DivByZero, ex.Reason);
    }

    [Fact]
    public void StackOverflow_DeepRecursion_Traps()
    {
        var source = """
            public static class Pure
            {
                public static int Run(int n) => Run(n + 1); // infinite recursion
            }
            """;
        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var binary = TCliCpuLinker.Link(dllBytes, "Pure", "Run");
        var cpu = new TCpuNano();

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(binary, 0, [0]));

        Assert.True(
            ex.Reason == TTrapReason.CallDepthExceeded || ex.Reason == TTrapReason.SramOverflow,
            $"Expected CallDepthExceeded or SramOverflow, got {ex.Reason}");
    }

    [Fact]
    public void IntMinDivMinus1_Overflow_Traps()
    {
        var source = "public static class Pure { public static int Run(int a, int b) => a / b; }";
        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var binary = TCliCpuLinker.Link(dllBytes, "Pure", "Run");
        var cpu = new TCpuNano();

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(binary, 0, [int.MinValue, -1]));

        Assert.Equal(TTrapReason.Overflow, ex.Reason);
    }

    // hu: Az ldind.i4/stind.i4 (indirekt memória) Roslyn-ból unsafe pointer-rel
    //     generálódik, de az conv.u opkódot is tartalmazza amit a CIL-T0 nem kezel.
    //     Ez a funkció a meglévő bytecode tesztekkel marad lefedve (TCpuIter4Tests),
    //     amíg a CIL-T0 ISA-t nem bővítjük pointer konverziókkal.
    // en: ldind.i4/stind.i4 (indirect memory) generates conv.u from Roslyn unsafe,
    //     which CIL-T0 doesn't handle. This feature stays covered by existing
    //     bytecode tests (TCpuIter4Tests) until the ISA is extended.

    // ------------------------------------------------------------------
    // Boundary tesztek
    // ------------------------------------------------------------------

    [Fact]
    public void IntMax_Plus1_Wraps() =>
        Assert.Equal(int.MinValue, Run(
            "public static class Pure { public static int Run(int a) => a + 1; }", AArgs: [int.MaxValue]));

    [Fact]
    public void IntMin_Minus1_Wraps() =>
        Assert.Equal(int.MaxValue, Run(
            "public static class Pure { public static int Run(int a) => a - 1; }", AArgs: [int.MinValue]));
}
