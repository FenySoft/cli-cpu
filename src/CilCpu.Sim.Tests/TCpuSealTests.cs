using CilCpu.Linker;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpuSeal osztály tesztjei — a Seal Core szimulátor.
/// Minden teszt C# forrásból indul (Roslyn → Linker → TCpuSeal),
/// hogy 100%-ban kompatibilisek legyünk a fordítóval.
/// <br />
/// en: Tests for the TCpuSeal class — the Seal Core simulator.
/// All tests start from C# source (Roslyn → Linker → TCpuSeal)
/// to ensure 100% compatibility with the compiler.
/// </summary>
public class TCpuSealTests
{
    /// <summary>
    /// hu: A CryptoCall attribútum és extern definíciók, amelyeket
    /// minden firmware teszt forrásba be kell illeszteni.
    /// <br />
    /// en: The CryptoCall attribute and extern definitions that must
    /// be included in every firmware test source.
    /// </summary>
    private const string CryptoCallPreamble = """
        using System.Runtime.CompilerServices;

        [System.AttributeUsage(System.AttributeTargets.Method)]
        public sealed class CryptoCallAttribute : System.Attribute
        {
            public CryptoCallAttribute(ushort ADispatchIndex) { DispatchIndex = ADispatchIndex; }
            public ushort DispatchIndex { get; }
        }

        public static class Sha256
        {
            [CryptoCall(0x0000)]
            public static extern byte[] Init();

            [CryptoCall(0x0001)]
            public static extern void Update(byte[] AState, byte[] AData);

            [CryptoCall(0x0002)]
            public static extern byte[] Final(byte[] AState, byte[] AData, int ATotalLength);
        }
        """;

    private (TCpuSeal Cpu, byte[] Binary) CompileAndLink(string AFirmwareSource)
    {
        var fullSource = CryptoCallPreamble + "\n" + AFirmwareSource;
        var dllBytes = TRoslynCompiler.CompileToBytes(fullSource);
        var binary = TCliCpuLinker.Link(dllBytes, "Firmware", "Boot", TIsaLevel.CilSeal);
        return (new TCpuSeal(), binary);
    }

    private int RunFirmware(string AFirmwareSource)
    {
        var (cpu, binary) = CompileAndLink(AFirmwareSource);
        cpu.Execute(binary, 0, null);
        return cpu.Peek(0);
    }

    // ------------------------------------------------------------------
    // CIL-T0 kompatibilitás
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Alapvető aritmetika — a TCpuSeal a CIL-T0 opkódokat is kezeli.
    /// <br />
    /// en: Basic arithmetic — TCpuSeal handles CIL-T0 opcodes too.
    /// </summary>
    [Fact]
    public void Firmware_Add_ReturnSum()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    return 2 + 3;
                }
            }
            """);

        Assert.Equal(5, result);
    }

    /// <summary>
    /// hu: Rekurzív Fibonacci — a CIL-T0 call/ret kompatibilitás igazolása.
    /// <br />
    /// en: Recursive Fibonacci — verifies CIL-T0 call/ret compatibility.
    /// </summary>
    [Fact]
    public void Firmware_Fibonacci10_Returns55()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    return Fib(10);
                }

                private static int Fib(int n)
                {
                    if (n < 2) return n;
                    return Fib(n - 1) + Fib(n - 2);
                }
            }
            """);

        Assert.Equal(55, result);
    }

    // ------------------------------------------------------------------
    // Tömb opkódok (newarr, ldlen, ldelem, stelem)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: newarr + ldlen — tömb allokáció és méret lekérdezés.
    /// <br />
    /// en: newarr + ldlen — array allocation and length query.
    /// </summary>
    [Fact]
    public void Firmware_NewarrLdlen_ReturnsLength()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] arr = new byte[42];
                    return arr.Length;
                }
            }
            """);

        Assert.Equal(42, result);
    }

    /// <summary>
    /// hu: stelem.i1 + ldelem — byte írás és olvasás.
    /// <br />
    /// en: stelem.i1 + ldelem — byte write and read.
    /// </summary>
    [Fact]
    public void Firmware_StelemLdelem_WritesAndReads()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] arr = new byte[4];
                    arr[2] = 0x7F;
                    return arr[2];
                }
            }
            """);

        Assert.Equal(0x7F, result);
    }

    // ------------------------------------------------------------------
    // SHA-256 CryptoCall
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Sha256.Init — 32 byte-os tömböt ad vissza.
    /// <br />
    /// en: Sha256.Init — returns a 32-byte array.
    /// </summary>
    [Fact]
    public void Firmware_Sha256Init_Returns32Bytes()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] state = Sha256.Init();
                    return state.Length;
                }
            }
            """);

        Assert.Equal(32, result);
    }

    /// <summary>
    /// hu: Sha256.Init — az első byte 0x6A (h0=0x6a09e667 MSB).
    /// <br />
    /// en: Sha256.Init — first byte is 0x6A (h0=0x6a09e667 MSB).
    /// </summary>
    [Fact]
    public void Firmware_Sha256Init_FirstByteCorrect()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] state = Sha256.Init();
                    return state[0];
                }
            }
            """);

        // hu: ldelem.i1 sign-extends: 0x6A < 128 → positive → 0x6A
        // en: ldelem.i1 sign-extends: 0x6A < 128 → positive → 0x6A
        Assert.Equal(0x6A, result);
    }

    /// <summary>
    /// hu: Sha256.Update — void, nem trap-el, a state nem módosul 3 byte inputra.
    /// <br />
    /// en: Sha256.Update — void, does not trap, state unchanged for 3-byte input.
    /// </summary>
    [Fact]
    public void Firmware_Sha256Update_SmallInput_NoTrap()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] state = Sha256.Init();
                    byte[] data = new byte[3];
                    data[0] = 0x61;
                    data[1] = 0x62;
                    data[2] = 0x63;
                    Sha256.Update(state, data);
                    return state[0]; // still 0x6A (no full block)
                }
            }
            """);

        Assert.Equal(0x6A, result);
    }

    /// <summary>
    /// hu: Teljes SHA-256("abc") — NIST FIPS 180-4 tesztvektor.
    /// SHA-256("abc") = BA7816BF 8F01CFEA 414140DE 5DAE2223...
    /// A hash[0] = 0xBA (sign-extended: -70).
    /// <br />
    /// en: Full SHA-256("abc") — NIST FIPS 180-4 test vector.
    /// hash[0] = 0xBA (sign-extended as int: -70).
    /// </summary>
    [Fact]
    public void Firmware_Sha256Abc_MatchesNistVector()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] state = Sha256.Init();
                    byte[] data = new byte[3];
                    data[0] = 0x61; // 'a'
                    data[1] = 0x62; // 'b'
                    data[2] = 0x63; // 'c'
                    Sha256.Update(state, data);
                    byte[] hash = Sha256.Final(state, data, 3);
                    return hash[0];
                }
            }
            """);

        // hu: 0xBA sign-extended = -70 (ldelem.i1 semantics)
        // en: 0xBA sign-extended = -70 (ldelem.i1 semantics)
        Assert.Equal(unchecked((int)(sbyte)0xBA), result);
    }

    /// <summary>
    /// hu: SHA-256("abc") — a hash[1] byte is helyes (0x78 = 120).
    /// <br />
    /// en: SHA-256("abc") — hash[1] is also correct (0x78 = 120).
    /// </summary>
    [Fact]
    public void Firmware_Sha256Abc_SecondByteCorrect()
    {
        var result = RunFirmware("""
            public static class Firmware
            {
                public static int Boot()
                {
                    byte[] state = Sha256.Init();
                    byte[] data = new byte[3];
                    data[0] = 0x61;
                    data[1] = 0x62;
                    data[2] = 0x63;
                    Sha256.Update(state, data);
                    byte[] hash = Sha256.Final(state, data, 3);
                    return hash[1];
                }
            }
            """);

        Assert.Equal(0x78, result); // 0x78 < 128 → no sign issue
    }

    // ------------------------------------------------------------------
    // CryptoCall — ismeretlen dispatch
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Ismeretlen CryptoCall dispatch index → INVALID_EXTERNAL_CALL trap.
    /// <br />
    /// en: Unknown CryptoCall dispatch index → INVALID_EXTERNAL_CALL trap.
    /// </summary>
    [Fact]
    public void Firmware_UnknownCryptoCall_Traps()
    {
        const string source = CryptoCallPreamble + """

            public static class BadCrypto
            {
                [CryptoCall(0x9999)]
                public static extern int Unknown();
            }

            public static class Firmware
            {
                public static int Boot()
                {
                    return BadCrypto.Unknown();
                }
            }
            """;

        var dllBytes = TRoslynCompiler.CompileToBytes(source);
        var binary = TCliCpuLinker.Link(dllBytes, "Firmware", "Boot", TIsaLevel.CilSeal);

        var cpu = new TCpuSeal();
        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(binary, 0, null));

        Assert.Equal(TTrapReason.InvalidExternalCall, ex.Reason);
    }
}
