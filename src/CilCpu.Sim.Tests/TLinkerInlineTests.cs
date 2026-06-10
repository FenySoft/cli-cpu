using CilCpu.Linker;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A Linker-inline optimalizáció tesztjei. Az inline logika a
/// TCliCpuLinker.Link() lépésben fut: ha egy callee megfelel az
/// inline-kritériumoknak (rövid, elágazás nélküli, szekvenciális
/// ldarg-prefix), akkor a call utasítás a callee törzsével helyettesítődik.
/// <br />
/// en: Tests for the Linker-inline optimisation. The inline logic runs
/// inside TCliCpuLinker.Link(): if a callee meets the inline criteria
/// (short, branch-free, sequential ldarg prefix), the call instruction
/// is replaced by the callee body.
/// </summary>
public class TLinkerInlineTests
{
    /// <summary>
    /// hu: IsInlineCandidate — ismert byte-minták ellenőrzése.
    /// Minden sor egy (IL-tömb, argCount, várt-eredmény) hármas.
    /// <br />
    /// en: IsInlineCandidate — verification against known byte patterns.
    /// Each row is an (IL array, argCount, expected result) triple.
    /// </summary>
    [Theory]
    // ✓ inline-képes: Add(a,b)=>a+b
    [InlineData(new byte[] { 0x02, 0x03, 0x58, 0x2A }, 2, true)]
    // ✓ inline-képes: Sub(a,b)=>a-b
    [InlineData(new byte[] { 0x02, 0x03, 0x59, 0x2A }, 2, true)]
    // ✓ inline-képes: Negate(x)=>-x
    [InlineData(new byte[] { 0x02, 0x65, 0x2A }, 1, true)]
    // ✓ inline-képes: GetFive()=>5  (0 argumentum)
    [InlineData(new byte[] { 0x1B, 0x2A }, 0, true)]
    // ✗ ldarg.0 kétszer a törzsben (Square idiom kézi)
    [InlineData(new byte[] { 0x02, 0x02, 0x5A, 0x2A }, 1, false)]
    // ✗ elágazás a törzsben (beq.s)
    [InlineData(new byte[] { 0x02, 0x03, 0x2E, 0x01, 0x02, 0x2A }, 2, false)]
    // ✗ stloc.0 a törzsben (lokális változó)
    [InlineData(new byte[] { 0x02, 0x03, 0x58, 0x0A, 0x06, 0x2A }, 2, false)]
    // ✗ call a törzsben
    [InlineData(new byte[] { 0x02, 0x03, 0x28, 0x00, 0x00, 0x00, 0x00, 0x2A }, 2, false)]
    // ✗ túl hosszú (17 byte > 16)
    [InlineData(new byte[] { 0x02, 0x03, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x58, 0x2A }, 2, false)]
    // ✗ argCount > 4
    [InlineData(new byte[] { 0x02, 0x03, 0x04, 0x05, 0x58, 0x2A }, 5, false)]
    public void IsInlineCandidate_KnownPatterns_ReturnsExpected(byte[] AIl, int AArgCount, bool AExpected)
    {
        Assert.Equal(AExpected, TCliCpuLinker.IsInlineCandidate(AIl, AArgCount));
    }

    /// <summary>
    /// hu: Wrapper hív egy inline-képes Add metódust — az eredmény helyes.
    /// <br />
    /// en: Wrapper calls an inline-eligible Add method — result is correct.
    /// </summary>
    [Fact]
    public void Link_WrapperCallsAdd_InlinedResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Run(int a, int b) => Add(a, b);
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Run");

        var cpu = new TCpuNano();
        cpu.Execute(t0Bytes, 0, [2, 3]);

        Assert.Equal(5, cpu.Peek(0));
        Assert.Equal(1, cpu.StackDepth);
    }

    /// <summary>
    /// hu: Inline után a bináris kisebb: a call (5 byte) helyén a törzs
    /// (1 byte: add) áll — a Run kódmérete 8 byte-ról 4 byte-ra csökken,
    /// a teljes bináris 28-ról 24 byte-ra.
    /// <br />
    /// en: After inline the binary is smaller: the 5-byte call is replaced
    /// by the 1-byte body (add) — Run's code shrinks from 8 to 4 bytes,
    /// total binary from 28 to 24 bytes.
    /// </summary>
    [Fact]
    public void Link_WrapperCallsAdd_BinaryShrinksTo24Bytes()
    {
        const string source = """
            public static class Pure
            {
                public static int Run(int a, int b) => Add(a, b);
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Run");

        // Run: 8-byte header + 4-byte code (ldarg.0; ldarg.1; add; ret)
        // Add: 8-byte header + 4-byte code (ldarg.0; ldarg.1; add; ret)
        Assert.Equal(24, t0Bytes.Length);
    }

    /// <summary>
    /// hu: Inline után a Run kódjában nincs 0x28 (call) bájt a callee
    /// helyén — az opkód közvetlenül az add (0x58).
    /// <br />
    /// en: After inline the Run code has no 0x28 (call) byte at the
    /// callee site — the opcode is directly add (0x58).
    /// </summary>
    [Fact]
    public void Link_WrapperCallsAdd_NoCallOpcodeAtCallSite()
    {
        const string source = """
            public static class Pure
            {
                public static int Run(int a, int b) => Add(a, b);
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Run");

        // Run code: offset 8..11 = ldarg.0 (0x02) | ldarg.1 (0x03) | add (0x58) | ret (0x2A)
        Assert.Equal(0x02, t0Bytes[8]);  // ldarg.0
        Assert.Equal(0x03, t0Bytes[9]);  // ldarg.1
        Assert.Equal(0x58, t0Bytes[10]); // add — NEM call (0x28)
        Assert.Equal(0x2A, t0Bytes[11]); // ret
    }

    /// <summary>
    /// hu: Két call-site ugyanarra az inline-képes callee-re — mindkettő
    /// inline-olódik, az eredmény helyes.
    /// <br />
    /// en: Two call sites to the same inline-eligible callee — both are
    /// inlined, result is correct.
    /// </summary>
    [Fact]
    public void Link_TwoCallSitesToSameCallee_BothInlined_CorrectResult()
    {
        const string source = """
            public static class Pure
            {
                public static int Run(int a, int b) => Add(a, a) + Add(b, b);
                public static int Add(int a, int b) => a + b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Run");

        var cpu = new TCpuNano();
        cpu.Execute(t0Bytes, 0, [3, 4]);

        // Run(3, 4) = Add(3,3) + Add(4,4) = 6 + 8 = 14
        Assert.Equal(14, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Elágazást tartalmazó callee NEM inline-olódik — a végrehajtás
    /// mégis helyes (normál CALL útvonalon fut).
    /// <br />
    /// en: A callee with a branch is NOT inlined — execution is still
    /// correct via the normal CALL path.
    /// </summary>
    [Fact]
    public void Link_MethodWithBranch_NotInlined_StillCorrect()
    {
        const string source = """
            public static class Pure
            {
                public static int Run(int a, int b) => Max(a, b);
                public static int Max(int a, int b) => a > b ? a : b;
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var t0Bytes = TCliCpuLinker.Link(dllBytes, "Pure", "Run");

        var cpu = new TCpuNano();
        cpu.Execute(t0Bytes, 0, [3, 7]);

        Assert.Equal(7, cpu.Peek(0));
    }
}
