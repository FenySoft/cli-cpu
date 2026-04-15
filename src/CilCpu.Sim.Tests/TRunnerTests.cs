using CilCpu.Linker;
using CilCpu.Sim;
using CilCpu.Sim.Runner;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TRunner és Program.Main tesztjei. Lefedi a RunBinary, RunFile,
/// LinkDll metódusokat, a compile+link+run pipeline kompozíciót, és a
/// CLI belépési pontot.
/// <br />
/// en: Tests for TRunner and Program.Main. Covers RunBinary, RunFile,
/// LinkDll methods, the compile+link+run pipeline composition, and the
/// CLI entry point.
/// </summary>
public class TRunnerTests
{
    // ==========================================================================
    // hu: Segédosztály — temp fájl menedzselése teszten belül.
    // en: Helper class — manages a temp file within a test.
    // ==========================================================================

    private sealed class TTempFile : IDisposable
    {
        public string Path { get; } = System.IO.Path.GetTempFileName();

        public void Dispose()
        {
            if (File.Exists(Path))
                File.Delete(Path);
        }
    }

    // ==========================================================================
    // hu: Helper metódusok — CIL-T0 bináris generálása a tesztekhez.
    // en: Helper methods — CIL-T0 binary generation for tests.
    // ==========================================================================

    private static byte[] BuildAddProgram()
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
        return TCliCpuLinker.Link(dllBytes, "Pure", "Add");
    }

    private static byte[] BuildFibonacciProgram()
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
        return TCliCpuLinker.Link(dllBytes, "Math", "Fibonacci");
    }

    private static byte[] BuildDivByZeroProgram()
    {
        const string source = """
            public static class Bad
            {
                public static int DivByZero(int a)
                {
                    return a / 0;
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        return TCliCpuLinker.Link(dllBytes, "Bad", "DivByZero");
    }

    private static byte[] BuildGcdProgram()
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
        return TCliCpuLinker.Link(dllBytes, "Math", "Gcd");
    }

    // ==========================================================================
    // 1. RunBinary tesztek
    // ==========================================================================

    /// <summary>
    /// hu: RunBinary egy egyszerű Add program binárisát futtatja, és ellenőrzi,
    /// hogy Add(2, 3) = 5 eredményt ad.
    /// <br />
    /// en: RunBinary runs a simple Add program binary and verifies that
    /// Add(2, 3) = 5.
    /// </summary>
    [Fact]
    public void RunBinary_AddProgram_ReturnsCorrectSum()
    {
        var t0Bytes = BuildAddProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [2, 3]);

        Assert.False(result.Trapped);
        Assert.Equal(5, result.Result);
        Assert.Null(result.TrapReason);
        Assert.Null(result.TrapMessage);
    }

    /// <summary>
    /// hu: RunBinary üres byte tömbhöz ArgumentException-t dob, mivel
    /// az üres program nem érvényes CIL-T0 bináris.
    /// <br />
    /// en: RunBinary throws ArgumentException for an empty byte array, because
    /// an empty program is not a valid CIL-T0 binary.
    /// </summary>
    [Fact]
    public void RunBinary_EmptyProgram_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            TRunner.RunBinary([], 0));
    }

    /// <summary>
    /// hu: RunBinary DivByZero trap-et okozó program futtatásakor
    /// Trapped=true és TrapReason=DivideByZero értéket ad vissza.
    /// <br />
    /// en: RunBinary returns Trapped=true and TrapReason=DivideByZero when
    /// running a program that causes a DivByZero trap.
    /// </summary>
    [Fact]
    public void RunBinary_TrapProgram_ReturnsTrapResult()
    {
        var t0Bytes = BuildDivByZeroProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [10]);

        Assert.True(result.Trapped);
        Assert.NotNull(result.TrapReason);
        Assert.NotNull(result.TrapMessage);
        Assert.Null(result.Result);
    }

    /// <summary>
    /// hu: RunBinary Fibonacci(20) = 6765 — a teljes pipeline-on át.
    /// <br />
    /// en: RunBinary Fibonacci(20) = 6765 — through the full pipeline.
    /// </summary>
    [Fact]
    public void RunBinary_Fibonacci20_Returns6765()
    {
        var t0Bytes = BuildFibonacciProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [20]);

        Assert.False(result.Trapped);
        Assert.Equal(6765, result.Result);
    }

    // ==========================================================================
    // 2. RunFile tesztek
    // ==========================================================================

    /// <summary>
    /// hu: RunFile egy temp fájlba írt érvényes .t0 binárist futtat, és
    /// ellenőrzi az eredményt.
    /// <br />
    /// en: RunFile runs a valid .t0 binary written to a temp file and verifies
    /// the result.
    /// </summary>
    [Fact]
    public void RunFile_ValidT0File_ReturnsResult()
    {
        var t0Bytes = BuildAddProgram();

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, t0Bytes);

        var result = TRunner.RunFile(tempFile.Path, 0, [2, 3]);

        Assert.False(result.Trapped);
        Assert.Equal(5, result.Result);
    }

    /// <summary>
    /// hu: RunFile nem létező fájl esetén FileNotFoundException-t dob.
    /// <br />
    /// en: RunFile throws FileNotFoundException for a non-existent file.
    /// </summary>
    [Fact]
    public void RunFile_NonExistentFile_ThrowsFileNotFoundException()
    {
        var nonExistentPath = Path.Combine(Path.GetTempPath(), "does_not_exist_99999.t0");

        Assert.Throws<FileNotFoundException>(() =>
            TRunner.RunFile(nonExistentPath, 0));
    }

    /// <summary>
    /// hu: RunFile hibás bináris futtatásakor trap eredményt ad vissza.
    /// <br />
    /// en: RunFile returns a trap result when running an invalid binary.
    /// </summary>
    [Fact]
    public void RunFile_InvalidBinary_ReturnsTrapResult()
    {
        var invalidBytes = new byte[] { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, invalidBytes);

        var result = TRunner.RunFile(tempFile.Path, 0);

        Assert.True(result.Trapped);
        Assert.NotNull(result.TrapMessage);
    }

    // ==========================================================================
    // 3. Pipeline kompozíció tesztek (compile + link + RunBinary)
    // hu: A RunSource/LinkSource funkciót a teszt oldalon kompozícióval
    //     valósítjuk meg: TRoslynCompiler → TCliCpuLinker → TRunner.RunBinary.
    // en: RunSource/LinkSource functionality is achieved via composition in
    //     tests: TRoslynCompiler → TCliCpuLinker → TRunner.RunBinary.
    // ==========================================================================

    /// <summary>
    /// hu: A teljes pipeline (C# → Roslyn → linker → RunBinary) Add(2,3)=5
    /// eredményt ad.
    /// <br />
    /// en: The full pipeline (C# → Roslyn → linker → RunBinary) returns
    /// Add(2,3)=5.
    /// </summary>
    [Fact]
    public void Pipeline_AddTwoNumbers_Returns5()
    {
        var t0Bytes = BuildAddProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [2, 3]);

        Assert.False(result.Trapped);
        Assert.Equal(5, result.Result);
    }

    /// <summary>
    /// hu: A teljes pipeline-on keresztül Fibonacci(10) = 55.
    /// <br />
    /// en: Fibonacci(10) = 55 through the full pipeline.
    /// </summary>
    [Fact]
    public void Pipeline_Fibonacci10_Returns55()
    {
        var t0Bytes = BuildFibonacciProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [10]);

        Assert.False(result.Trapped);
        Assert.Equal(55, result.Result);
    }

    /// <summary>
    /// hu: A teljes pipeline-on keresztül GCD(48, 18) = 6.
    /// <br />
    /// en: GCD(48, 18) = 6 through the full pipeline.
    /// </summary>
    [Fact]
    public void Pipeline_GcdWithLocals_Returns6()
    {
        var t0Bytes = BuildGcdProgram();

        var result = TRunner.RunBinary(t0Bytes, 0, [48, 18]);

        Assert.False(result.Trapped);
        Assert.Equal(6, result.Result);
    }

    /// <summary>
    /// hu: A Roslyn-linker pipeline CIL-T0 inkompatibilis kódnál
    /// TCilT0LinkException-t dob.
    /// <br />
    /// en: The Roslyn-linker pipeline throws TCilT0LinkException for
    /// CIL-T0 incompatible code.
    /// </summary>
    [Fact]
    public void Pipeline_IncompatibleCode_ThrowsLinkException()
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

    // ==========================================================================
    // 4. LinkDll tesztek
    // ==========================================================================

    /// <summary>
    /// hu: LinkDll egy érvényes Add függvényből nem üres byte tömböt ad
    /// vissza.
    /// <br />
    /// en: LinkDll returns a non-empty byte array from a valid Add function.
    /// </summary>
    [Fact]
    public void LinkDll_ValidAssembly_ReturnsNonEmptyBytes()
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
        var t0Bytes = TRunner.LinkDll(dllBytes, "Pure", "Add");

        Assert.NotNull(t0Bytes);
        Assert.True(t0Bytes.Length > 0);
    }

    /// <summary>
    /// hu: LinkDll null DLL byte-okhoz ArgumentNullException-t dob.
    /// <br />
    /// en: LinkDll throws ArgumentNullException for null DLL bytes.
    /// </summary>
    [Fact]
    public void LinkDll_NullBytes_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TRunner.LinkDll(null!, "Pure", "Add"));
    }

    /// <summary>
    /// hu: LinkDll nem létező osztálynévhez TCilT0LinkException-t dob.
    /// <br />
    /// en: LinkDll throws TCilT0LinkException for a non-existent class name.
    /// </summary>
    [Fact]
    public void LinkDll_InvalidClassName_ThrowsLinkException()
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

        Assert.Throws<TCilT0LinkException>(() =>
            TRunner.LinkDll(dllBytes, "NonExistentClass", "Add"));
    }

    // ==========================================================================
    // 5. Program.Main tesztek
    // ==========================================================================

    /// <summary>
    /// hu: Program.Main argumentum nélkül nem nulla exit kóddal tér vissza.
    /// <br />
    /// en: Program.Main returns a non-zero exit code when called without args.
    /// </summary>
    [Fact]
    public void Main_NoArgs_ReturnsNonZero()
    {
        var exitCode = Program.Main([]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main érvényes .t0 fájl futtatásakor 0 exit kóddal tér
    /// vissza.
    /// <br />
    /// en: Program.Main returns exit code 0 when running a valid .t0 file.
    /// </summary>
    [Fact]
    public void Main_RunT0File_ReturnsZero()
    {
        var t0Bytes = BuildAddProgram();

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, t0Bytes);

        var exitCode = Program.Main(["run", tempFile.Path, "--args", "2,3"]);

        Assert.Equal(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main .dll fájl linkelése után létrehozza a .t0 kimeneti
    /// fájlt.
    /// <br />
    /// en: Program.Main creates the .t0 output file after linking a .dll file.
    /// </summary>
    [Fact]
    public void Main_LinkDllFile_CreatesT0File()
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

        using var dllFile = new TTempFile();
        var dllPath = Path.ChangeExtension(dllFile.Path, ".dll");
        var t0Path = Path.ChangeExtension(dllFile.Path, ".t0");

        File.WriteAllBytes(dllPath, dllBytes);

        try
        {
            var exitCode = Program.Main(["link", dllPath, "--class", "Pure", "--method", "Add", "-o", t0Path]);

            Assert.Equal(0, exitCode);
            Assert.True(File.Exists(t0Path), $"Expected .t0 file at: {t0Path}");
            Assert.True(new FileInfo(t0Path).Length > 0);
        }
        finally
        {
            if (File.Exists(dllPath))
                File.Delete(dllPath);

            if (File.Exists(t0Path))
                File.Delete(t0Path);
        }
    }

    // ==========================================================================
    // 6. CLI edge case tesztek (Ördög Ügyvédje feedback)
    // ==========================================================================

    /// <summary>
    /// hu: Program.Main érvénytelen --args értékkel (nem szám) non-zero
    /// exit kóddal tér vissza.
    /// <br />
    /// en: Program.Main returns non-zero exit code for invalid --args value.
    /// </summary>
    [Fact]
    public void Main_InvalidArgsFormat_ReturnsNonZero()
    {
        var t0Bytes = BuildAddProgram();

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, t0Bytes);

        var exitCode = Program.Main(["run", tempFile.Path, "--args", "abc,xyz"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main ismeretlen parancs esetén non-zero exit kóddal
    /// tér vissza.
    /// <br />
    /// en: Program.Main returns non-zero exit code for an unknown command.
    /// </summary>
    [Fact]
    public void Main_UnknownCommand_ReturnsNonZero()
    {
        var exitCode = Program.Main(["foobar"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main run parancs fájl nélkül non-zero exit kóddal
    /// tér vissza.
    /// <br />
    /// en: Program.Main returns non-zero exit code for run without a file.
    /// </summary>
    [Fact]
    public void Main_RunWithoutFile_ReturnsNonZero()
    {
        var exitCode = Program.Main(["run"]);

        Assert.NotEqual(0, exitCode);
    }

    // ------------------------------------------------------------------
    // hu: Lefedetlen ág tesztek — Runner és Program edge case-ek
    // en: Uncovered branch tests — Runner and Program edge cases
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: RunBinary null programmal ArgumentNullException-t dob.
    /// <br />
    /// en: RunBinary with null program throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void RunBinary_NullProgram_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TRunner.RunBinary(null!, 0));
    }

    /// <summary>
    /// hu: RunBinary void metódussal (üres stack) → Result = null.
    /// <br />
    /// en: RunBinary with void method (empty stack) → Result = null.
    /// </summary>
    [Fact]
    public void RunBinary_VoidMethod_ReturnsNullResult()
    {
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
            0x2A
        };

        var result = TRunner.RunBinary(program, 0);

        Assert.False(result.Trapped);
        Assert.Null(result.Result);
    }

    /// <summary>
    /// hu: LinkDll null osztálynévvel ArgumentNullException-t dob.
    /// <br />
    /// en: LinkDll with null class name throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void LinkDll_NullClassName_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TRunner.LinkDll([], null!, "Add"));
    }

    /// <summary>
    /// hu: LinkDll null metódusnévvel ArgumentNullException-t dob.
    /// <br />
    /// en: LinkDll with null method name throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void LinkDll_NullMethodName_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() =>
            TRunner.LinkDll([], "Pure", null!));
    }

    /// <summary>
    /// hu: Program.Main run nem létező fájlhoz non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main run with non-existent file returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_RunNonExistentFile_ReturnsNonZero()
    {
        var exitCode = Program.Main(["run", "/tmp/does_not_exist_99999.t0"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main run trap-et okozó programmal exit code 2.
    /// <br />
    /// en: Program.Main run with a trap-causing program returns exit code 2.
    /// </summary>
    [Fact]
    public void Main_RunTrapProgram_ReturnsExitCode2()
    {
        var t0Bytes = BuildDivByZeroProgram();

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, t0Bytes);

        var exitCode = Program.Main(["run", tempFile.Path, "--args", "10"]);

        Assert.Equal(2, exitCode);
    }

    /// <summary>
    /// hu: Program.Main run --entry flag-gel az entry RVA-t használja.
    /// <br />
    /// en: Program.Main run with --entry flag uses the entry RVA.
    /// </summary>
    [Fact]
    public void Main_RunWithEntryFlag_UsesEntryRva()
    {
        var t0Bytes = BuildAddProgram();

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, t0Bytes);

        var exitCode = Program.Main(["run", tempFile.Path, "--entry", "0", "--args", "2,3"]);

        Assert.Equal(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main void metódussal exit code 0.
    /// <br />
    /// en: Program.Main with void method returns exit code 0.
    /// </summary>
    [Fact]
    public void Main_RunVoidProgram_ReturnsZero()
    {
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
            0x2A
        };

        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, program);

        var exitCode = Program.Main(["run", tempFile.Path]);

        Assert.Equal(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link --class nélkül non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link without --class returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkMissingClass_ReturnsNonZero()
    {
        using var tempFile = new TTempFile();

        var exitCode = Program.Main(["link", tempFile.Path, "--method", "Add", "-o", "out.t0"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link --method nélkül non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link without --method returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkMissingMethod_ReturnsNonZero()
    {
        using var tempFile = new TTempFile();

        var exitCode = Program.Main(["link", tempFile.Path, "--class", "Pure", "-o", "out.t0"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link -o nélkül non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link without -o returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkMissingOutput_ReturnsNonZero()
    {
        using var tempFile = new TTempFile();

        var exitCode = Program.Main(["link", tempFile.Path, "--class", "Pure", "--method", "Add"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link parancs fájl nélkül non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link without file returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkWithoutFile_ReturnsNonZero()
    {
        var exitCode = Program.Main(["link"]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link nem létező DLL-lel non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link with non-existent DLL returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkNonExistentDll_ReturnsNonZero()
    {
        var exitCode = Program.Main([
            "link", "/tmp/does_not_exist_99999.dll",
            "--class", "Pure", "--method", "Add", "-o", "/tmp/out.t0"
        ]);

        Assert.NotEqual(0, exitCode);
    }

    /// <summary>
    /// hu: Program.Main link érvénytelen DLL-lel (nem PE) non-zero exit kódot ad.
    /// <br />
    /// en: Program.Main link with invalid DLL (not PE) returns non-zero exit code.
    /// </summary>
    [Fact]
    public void Main_LinkInvalidDll_ReturnsNonZero()
    {
        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, [0xFF, 0xFF, 0xFF, 0xFF]);

        var t0Path = Path.ChangeExtension(tempFile.Path, ".t0");

        try
        {
            var exitCode = Program.Main([
                "link", tempFile.Path,
                "--class", "Pure", "--method", "Add", "-o", t0Path
            ]);

            Assert.NotEqual(0, exitCode);
        }
        finally
        {
            if (File.Exists(t0Path))
                File.Delete(t0Path);
        }
    }

    /// <summary>
    /// hu: TRunResult.Trapped true, ha TrapReason nem null.
    /// <br />
    /// en: TRunResult.Trapped is true when TrapReason is not null.
    /// </summary>
    [Fact]
    public void TRunResult_Trapped_TrueWhenTrapReasonSet()
    {
        var result = new TRunResult(null, TTrapReason.DivByZero, "test");

        Assert.True(result.Trapped);
    }

    /// <summary>
    /// hu: TRunResult.Trapped false, ha TrapReason null.
    /// <br />
    /// en: TRunResult.Trapped is false when TrapReason is null.
    /// </summary>
    [Fact]
    public void TRunResult_Trapped_FalseWhenNoTrap()
    {
        var result = new TRunResult(42, null, null);

        Assert.False(result.Trapped);
    }

    /// <summary>
    /// hu: Program.Main run üres .t0 fájllal non-zero exit kódot ad vissza —
    /// az ArgumentException a generic Exception catch ágát aktiválja a
    /// HandleRun metódusban (nem FileNotFoundException, nem FormatException).
    /// <br />
    /// en: Program.Main run with an empty .t0 file returns non-zero exit code —
    /// ArgumentException activates the generic Exception catch branch in
    /// HandleRun (not FileNotFoundException, not FormatException).
    /// </summary>
    [Fact]
    public void Main_RunEmptyFile_ReturnsNonZero()
    {
        using var tempFile = new TTempFile();
        File.WriteAllBytes(tempFile.Path, []);

        var exitCode = Program.Main(["run", tempFile.Path]);

        Assert.NotEqual(0, exitCode);
    }
}
