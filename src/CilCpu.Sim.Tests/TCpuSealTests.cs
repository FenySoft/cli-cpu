namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpuSeal osztály tesztjei — a Seal Core szimulátor.
/// Az első tesztek a CIL-T0 kompatibilitást igazolják (a TCpuSeal
/// a TCpuNano superset-je).
/// <br />
/// en: Tests for the TCpuSeal class — the Seal Core simulator.
/// The first tests verify CIL-T0 compatibility (TCpuSeal is a
/// superset of TCpuNano).
/// </summary>
public class TCpuSealTests
{
    /// <summary>
    /// hu: A TCpuSeal alapértelmezett SRAM mérete 64 KB (a Seal Core spec szerint).
    /// <br />
    /// en: TCpuSeal default SRAM size is 64 KB (per Seal Core spec).
    /// </summary>
    [Fact]
    public void Constructor_DefaultSramSize_Is64KB()
    {
        var cpu = new TCpuSeal();

        Assert.Equal(65536, cpu.SramSize);
    }

    /// <summary>
    /// hu: A nop opkód működik — CIL-T0 kompatibilitás alapja.
    /// <br />
    /// en: The nop opcode works — CIL-T0 compatibility baseline.
    /// </summary>
    [Fact]
    public void Execute_Nop_LeavesStackUnchanged()
    {
        var cpu = new TCpuSeal();
        var program = new byte[] { 0x00 }; // nop

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: ldc.i4.1 + ret — a legegyszerűbb program ami értéket ad vissza.
    /// <br />
    /// en: ldc.i4.1 + ret — simplest program that returns a value.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_1_PushesOneToStack()
    {
        var cpu = new TCpuSeal();
        var program = new byte[] { 0x17 }; // ldc.i4.1

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: A heap pointer kezdetben az SRAM tetejére mutat (felülről lefelé nő).
    /// <br />
    /// en: The heap pointer initially points to the top of SRAM (grows downward).
    /// </summary>
    [Fact]
    public void Constructor_HeapPointer_StartsAtSramTop()
    {
        var cpu = new TCpuSeal();

        Assert.Equal(65536, cpu.HeapPointer);
    }

    /// <summary>
    /// hu: A newarr opkód allokál egy byte tömböt a heap-en.
    /// A stack-re a tömb heap-címe kerül.
    /// <br />
    /// en: The newarr opcode allocates a byte array on the heap.
    /// The array's heap address is pushed onto the stack.
    /// </summary>
    [Fact]
    public void Execute_Newarr_AllocatesByteArray()
    {
        var cpu = new TCpuSeal();
        // ldc.i4.s 32, newarr <token ignored>
        var program = new byte[] { 0x1F, 0x20, 0x8D, 0x00, 0x00, 0x00, 0x00 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);

        var arrayRef = cpu.Peek(0);

        // hu: A heap a tetejéről lefelé nő: 65536 - 4 (length) - 32 (data) = 65500
        // en: Heap grows downward from top: 65536 - 4 (length) - 32 (data) = 65500
        Assert.Equal(65500, arrayRef);
        Assert.Equal(65500, cpu.HeapPointer);
    }

    /// <summary>
    /// hu: A ldlen opkód visszaadja a tömb hosszát.
    /// <br />
    /// en: The ldlen opcode returns the array length.
    /// </summary>
    [Fact]
    public void Execute_Ldlen_ReturnsArrayLength()
    {
        var cpu = new TCpuSeal();
        // ldc.i4.s 10, newarr, ldlen
        var program = new byte[]
        {
            0x1F, 0x0A,                         // ldc.i4.s 10
            0x8D, 0x00, 0x00, 0x00, 0x00,       // newarr
            0x8E                                 // ldlen
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(10, cpu.Peek(0));
    }

    /// <summary>
    /// hu: stelem.i1 + ldelem.u1 — byte írás és olvasás a tömbből.
    /// <br />
    /// en: stelem.i1 + ldelem.u1 — byte write and read from array.
    /// </summary>
    [Fact]
    public void Execute_Stelem_Ldelem_WritesAndReadsByte()
    {
        var cpu = new TCpuSeal();
        // Allokálunk egy 4-elemű tömböt, beírunk 0xAB-t az [2]-be, visszaolvassuk
        var program = new byte[]
        {
            // newarr(4)
            0x1F, 0x04,                         // ldc.i4.s 4
            0x8D, 0x00, 0x00, 0x00, 0x00,       // newarr
            // dup — 2 ref a stacken (1 stelem-hez, 1 ldelem-hez)
            0x25,                                // dup
            // stelem.i1: array[2] = 0xAB
            0x18,                                // ldc.i4.2 (index)
            0x1F, 0xAB,                         // ldc.i4.s 0xAB (value, signed: -85)
            0x9C,                                // stelem.i1
            // ldelem.u1: push array[2]
            0x18,                                // ldc.i4.2 (index)
            0x90                                 // ldelem.u1
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0xAB, cpu.Peek(0)); // zero-extended byte
    }

    /// <summary>
    /// hu: newarr negatív mérettel NEGATIVE_ARRAY_SIZE trap-et dob.
    /// <br />
    /// en: newarr with negative size throws NEGATIVE_ARRAY_SIZE trap.
    /// </summary>
    [Fact]
    public void Execute_Newarr_NegativeSize_Traps()
    {
        var cpu = new TCpuSeal();
        // ldc.i4.s -1 (0xFF signed = -1), newarr
        var program = new byte[] { 0x1F, 0xFF, 0x8D, 0x00, 0x00, 0x00, 0x00 };

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.NegativeArraySize, ex.Reason);
    }

    /// <summary>
    /// hu: ldelem.u1 index-szel a határokon kívül INDEX_OUT_OF_RANGE trap-et dob.
    /// <br />
    /// en: ldelem.u1 with out-of-bounds index throws INDEX_OUT_OF_RANGE trap.
    /// </summary>
    [Fact]
    public void Execute_Ldelem_OutOfBounds_Traps()
    {
        var cpu = new TCpuSeal();
        // newarr(4), ldc.i4.s 5, ldelem.u1
        var program = new byte[]
        {
            0x1F, 0x04,                         // ldc.i4.s 4
            0x8D, 0x00, 0x00, 0x00, 0x00,       // newarr
            0x1F, 0x05,                         // ldc.i4.s 5 (index = 5, out of bounds)
            0x90                                 // ldelem.u1
        };

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.IndexOutOfRange, ex.Reason);
    }

    /// <summary>
    /// hu: ldlen null referenciával (0xFFFFFFFF) NULL_REFERENCE trap-et dob.
    /// <br />
    /// en: ldlen on null reference (0xFFFFFFFF) throws NULL_REFERENCE trap.
    /// </summary>
    [Fact]
    public void Execute_Ldlen_NullRef_Traps()
    {
        var cpu = new TCpuSeal();
        // ldc.i4 0xFFFFFFFF, ldlen
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0xFF,       // ldc.i4 -1 (= 0xFFFFFFFF = null ref)
            0x8E                                 // ldlen
        };

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.NullReference, ex.Reason);
    }

    // ------------------------------------------------------------------
    // CryptoCall dispatch tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: External call (CryptoCall) — ismeretlen dispatch index
    /// INVALID_EXTERNAL_CALL trap-et dob.
    /// <br />
    /// en: External call (CryptoCall) — unknown dispatch index
    /// throws INVALID_EXTERNAL_CALL trap.
    /// </summary>
    [Fact]
    public void Execute_CryptoCall_UnknownIndex_Traps()
    {
        var cpu = new TCpuSeal();
        // call 0xFFFF_9999 (ismeretlen dispatch index)
        var program = new byte[]
        {
            0x28,                                // call opcode
            0x99, 0x99, 0xFF, 0xFF              // target RVA = 0xFFFF9999 (little-endian)
        };

        var ex = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidExternalCall, ex.Reason);
    }

    /// <summary>
    /// hu: Sha256.Init (dispatch 0x0000) — visszaad egy 32 byte-os tömböt
    /// a SHA-256 kezdő hash értékekkel (FIPS 180-4).
    /// <br />
    /// en: Sha256.Init (dispatch 0x0000) — returns a 32-byte array
    /// with the SHA-256 initial hash values (FIPS 180-4).
    /// </summary>
    [Fact]
    public void Execute_Sha256Init_Returns32ByteInitialHash()
    {
        var cpu = new TCpuSeal();
        // call 0xFFFF0000 (Sha256.Init), ldlen
        var program = new byte[]
        {
            0x28,                                // call
            0x00, 0x00, 0xFF, 0xFF,              // target = 0xFFFF0000 (little-endian)
            0x8E                                 // ldlen — ellenőrizzük, hogy 32 byte-os tömb
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(32, cpu.Peek(0)); // length == 32
    }

    /// <summary>
    /// hu: Sha256.Init — a kezdő hash első byte-ja 0x6A (a h0=0x6a09e667 big-endian).
    /// <br />
    /// en: Sha256.Init — first byte of initial hash is 0x6A (h0=0x6a09e667 big-endian).
    /// </summary>
    [Fact]
    public void Execute_Sha256Init_FirstByteIs0x6A()
    {
        var cpu = new TCpuSeal();
        // call Sha256.Init, ldc.i4.0, ldelem.u1
        var program = new byte[]
        {
            0x28,                                // call
            0x00, 0x00, 0xFF, 0xFF,              // target = 0xFFFF0000
            0x16,                                // ldc.i4.0 (index = 0)
            0x90                                 // ldelem.u1
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x6A, cpu.Peek(0)); // h0 MSB = 0x6A
    }

    /// <summary>
    /// hu: Sha256.Init — a kezdő hash utolsó byte-ja 0x19 (a h7=0x5be0cd19 LSB).
    /// <br />
    /// en: Sha256.Init — last byte of initial hash is 0x19 (h7=0x5be0cd19 LSB).
    /// </summary>
    [Fact]
    public void Execute_Sha256Init_LastByteIs0x19()
    {
        var cpu = new TCpuSeal();
        // call Sha256.Init, ldc.i4.s 31, ldelem.u1
        var program = new byte[]
        {
            0x28,                                // call
            0x00, 0x00, 0xFF, 0xFF,              // target = 0xFFFF0000
            0x1F, 0x1F,                          // ldc.i4.s 31 (last index)
            0x90                                 // ldelem.u1
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x19, cpu.Peek(0)); // h7 LSB = 0x19
    }

    /// <summary>
    /// hu: Sha256.Update (dispatch 0x0001) — 3 byte input (nem teljes blokk),
    /// az Update nem módosítja a state-et, de nem trap-el. A state ref
    /// visszakerül a stackre.
    /// Stack: pop AData (ref), pop AState (ref). Push AState ref.
    /// <br />
    /// en: Sha256.Update (dispatch 0x0001) — 3-byte input (no full block),
    /// Update does not modify state but does not trap. State ref is
    /// pushed back onto stack.
    /// </summary>
    [Fact]
    public void Execute_Sha256Update_SmallInput_StateUnchanged()
    {
        var cpu = new TCpuSeal();
        var program = new byte[]
        {
            // Sha256.Init → state ref
            0x28, 0x00, 0x00, 0xFF, 0xFF,        // call 0xFFFF0000

            // newarr(3) → data ref, fill "abc"
            0x1F, 0x03,                          // ldc.i4.s 3
            0x8D, 0x00, 0x00, 0x00, 0x00,        // newarr
            0x25, 0x16, 0x1F, 0x61, 0x9C,        // dup, ldc.i4.0, ldc.i4.s 'a', stelem.i1
            0x25, 0x17, 0x1F, 0x62, 0x9C,        // dup, ldc.i4.1, ldc.i4.s 'b', stelem.i1
            0x25, 0x18, 0x1F, 0x63, 0x9C,        // dup, ldc.i4.2, ldc.i4.s 'c', stelem.i1

            // Stack: [state, data]
            // Sha256.Update(state, data) → push [state, data] back
            0x28, 0x01, 0x00, 0xFF, 0xFF,        // call 0xFFFF0001

            // Stack: [state, data]
            // pop data, read state[0] — still initial hash (no full block processed)
            0x26,                                 // pop (drop data ref)
            0x16,                                 // ldc.i4.0
            0x90                                  // ldelem.u1
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x6A, cpu.Peek(0)); // state unchanged — no full block
    }

    /// <summary>
    /// hu: End-to-end SHA-256("abc") — az ismert NIST tesztvektor.
    /// SHA-256("abc") = BA7816BF 8F01CFEA 414140DE 5DAE2223
    ///                  B00361A3 96177A9C B410FF61 F20015AD
    /// A Final megkapja a data ref-et is (a maradék byte-ok kiolvasásához).
    /// Stack: Final(state, data, totalLength) → hash ref.
    /// <br />
    /// en: End-to-end SHA-256("abc") — the known NIST test vector.
    /// Final receives the data ref too (to read remainder bytes).
    /// Stack: Final(state, data, totalLength) → hash ref.
    /// </summary>
    [Fact]
    public void Execute_Sha256_Abc_MatchesNistVector()
    {
        var cpu = new TCpuSeal();
        var program = new byte[]
        {
            // Sha256.Init → state ref
            0x28, 0x00, 0x00, 0xFF, 0xFF,        // call 0xFFFF0000

            // newarr(3) → data ref, fill "abc"
            0x1F, 0x03,                          // ldc.i4.s 3
            0x8D, 0x00, 0x00, 0x00, 0x00,        // newarr
            0x25, 0x16, 0x1F, 0x61, 0x9C,        // dup, ldc.i4.0, ldc.i4.s 'a', stelem.i1
            0x25, 0x17, 0x1F, 0x62, 0x9C,        // dup, ldc.i4.1, ldc.i4.s 'b', stelem.i1
            0x25, 0x18, 0x1F, 0x63, 0x9C,        // dup, ldc.i4.2, ldc.i4.s 'c', stelem.i1

            // Stack: [state, data]
            // Sha256.Update(state, data) → push state ref
            0x28, 0x01, 0x00, 0xFF, 0xFF,        // call 0xFFFF0001

            // Stack Update után: [state, data]

            // Sha256.Final(state, data, totalLength=3) → hash ref
            0x1F, 0x03,                          // ldc.i4.s 3 (total length)
            0x28, 0x02, 0x00, 0xFF, 0xFF,        // call 0xFFFF0002

            // Stack: [hash]
            0x16,                                 // ldc.i4.0
            0x90                                  // ldelem.u1
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0xBA, cpu.Peek(0)); // SHA-256("abc") first byte
    }
}
