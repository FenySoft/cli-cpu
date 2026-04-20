namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: TSramModelTests — a TCpuNano SRAM-alapú belső állapot modelljének
/// TDD-Red fázis tesztjei. Ezek a tesztek MOST NEM FORDULNAK LE, mert
/// a TCpuNano-ban még nem létezik: Sp, FrameBase, SramSnapshot(), SramSize,
/// és a TCpuNano(byte[]?, int) konstruktor. A tesztek a frame layout helyességét
/// ellenőrzik az SRAM byte-tömbön keresztül.
/// <br />
/// en: TSramModelTests — TDD-Red phase tests for the SRAM-based internal
/// state model of TCpuNano. These tests DO NOT COMPILE YET because TCpuNano does
/// not yet have: Sp, FrameBase, SramSnapshot(), SramSize, and the
/// TCpuNano(byte[]?, int) constructor. The tests verify frame layout correctness
/// by inspecting the SRAM byte array.
/// </summary>
public class TSramModelTests
{
    // ------------------------------------------------------------------
    // hu: SRAM frame layout konstansok
    // en: SRAM frame layout constants
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A frame header mérete byte-ban (ReturnPC + PrevFrameBase +
    /// ArgCount + LocalCount + reserved = 4+4+1+1+2 = 12 byte).
    /// <br />
    /// en: Frame header size in bytes (ReturnPC + PrevFrameBase +
    /// ArgCount + LocalCount + reserved = 4+4+1+1+2 = 12 bytes).
    /// </summary>
    private const int FrameHeaderSize = 12;

    // ------------------------------------------------------------------
    // 1. Root frame SRAM layout tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Execute(program, rva, args) után a FrameBase == 0 (a root frame
    /// az SRAM legelején kezdődik).
    /// <br />
    /// en: After Execute(program, rva, args) the FrameBase == 0 (the root
    /// frame starts at the very beginning of SRAM).
    /// </summary>
    [Fact]
    public void Execute_RootFrame_FrameBaseIsZero()
    {
        var cpu = new TCpuNano();

        // header: magic=0xFE, arg=2, local=0, max_stack=2, code_size=3
        // code: ldarg.0, ldarg.1, add
        var program = new byte[]
        {
            0xFE, 0x02, 0x00, 0x02, 0x03, 0x00, 0x00, 0x00,
            0x02, 0x03, 0x58
        };

        cpu.Execute(program, 0, new[] { 10, 20 });

        Assert.Equal(0, cpu.FrameBase);
    }

    /// <summary>
    /// hu: Az SRAM[0..11] a helyes root frame header adatokat tartalmazza:
    /// ReturnPC == -1 (root), PrevFrameBase == -1 (root),
    /// ArgCount és LocalCount a header értékei.
    /// <br />
    /// en: SRAM[0..11] contains the correct root frame header data:
    /// ReturnPC == -1 (root), PrevFrameBase == -1 (root),
    /// ArgCount and LocalCount match the method header values.
    /// </summary>
    [Fact]
    public void Execute_RootFrame_SramHeaderCorrect()
    {
        var cpu = new TCpuNano();

        // header: magic=0xFE, arg=2, local=1, max_stack=2, code_size=3
        // code: ldarg.0, ldarg.1, add
        var program = new byte[]
        {
            0xFE, 0x02, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00,
            0x02, 0x03, 0x58
        };

        cpu.Execute(program, 0, new[] { 5, 7 });

        var sram = cpu.SramSnapshot();

        // ReturnPC @ [FP+0] == -1 (root frame, little-endian)
        var returnPc = BitConverter.ToInt32(sram, 0);
        Assert.Equal(-1, returnPc);

        // PrevFrameBase @ [FP+4] == -1 (root, little-endian)
        var prevFrameBase = BitConverter.ToInt32(sram, 4);
        Assert.Equal(-1, prevFrameBase);

        // ArgCount @ [FP+8] == 2
        Assert.Equal(2, sram[8]);

        // LocalCount @ [FP+9] == 1
        Assert.Equal(1, sram[9]);
    }

    /// <summary>
    /// hu: A root frame argumentumai az SRAM[12..] pozícióban vannak,
    /// helyes értékekkel (little-endian int32).
    /// <br />
    /// en: Root frame arguments are at SRAM[12..] with correct values
    /// (little-endian int32).
    /// </summary>
    [Fact]
    public void Execute_RootFrame_ArgsInSram()
    {
        var cpu = new TCpuNano();

        // header: arg=2, local=0, max_stack=2, code_size=3
        // code: ldarg.0, ldarg.1, add
        var program = new byte[]
        {
            0xFE, 0x02, 0x00, 0x02, 0x03, 0x00, 0x00, 0x00,
            0x02, 0x03, 0x58
        };

        cpu.Execute(program, 0, new[] { 42, 99 });

        var sram = cpu.SramSnapshot();

        // arg[0] @ [FP+12] == 42
        var arg0 = BitConverter.ToInt32(sram, FrameHeaderSize);
        Assert.Equal(42, arg0);

        // arg[1] @ [FP+16] == 99
        var arg1 = BitConverter.ToInt32(sram, FrameHeaderSize + 4);
        Assert.Equal(99, arg1);
    }

    /// <summary>
    /// hu: A root frame lokális változói az SRAM-ban args után következnek,
    /// és mind 0-val inicializáltak.
    /// <br />
    /// en: Root frame locals follow the args in SRAM and are all
    /// zero-initialized.
    /// </summary>
    [Fact]
    public void Execute_RootFrame_LocalsZeroed()
    {
        var cpu = new TCpuNano();

        // header: arg=1, local=2, max_stack=1, code_size=2
        // code: ldarg.0, ret
        var program = new byte[]
        {
            0xFE, 0x01, 0x02, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x02, 0x2A
        };

        cpu.Execute(program, 0, new[] { 7 });

        var sram = cpu.SramSnapshot();

        // locals start @ [FP+12 + argCount*4] = [12 + 1*4] = [16]
        var local0 = BitConverter.ToInt32(sram, FrameHeaderSize + 4);
        var local1 = BitConverter.ToInt32(sram, FrameHeaderSize + 8);

        Assert.Equal(0, local0);
        Assert.Equal(0, local1);
    }

    /// <summary>
    /// hu: Az Sp értéke a végrehajtás után helyes: a frame header (12) +
    /// args (argCount*4) + locals (localCount*4) + eval stack mélység*4
    /// byte az SRAM elején.
    /// <br />
    /// en: Sp after execution is correct: frame header (12) + args
    /// (argCount*4) + locals (localCount*4) + eval stack depth*4 bytes
    /// from the SRAM start.
    /// </summary>
    [Fact]
    public void Execute_RootFrame_SpAfterExecution()
    {
        var cpu = new TCpuNano();

        // header: arg=2, local=1, max_stack=2, code_size=3
        // code: ldarg.0, ldarg.1, add
        // After execution: eval stack depth = 1 (the sum on TOS)
        var program = new byte[]
        {
            0xFE, 0x02, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00,
            0x02, 0x03, 0x58
        };

        cpu.Execute(program, 0, new[] { 3, 4 });

        // SP = FrameBase + header(12) + args(2*4=8) + locals(1*4=4) + evalDepth(1*4=4) = 28
        var expectedSp = 0 + FrameHeaderSize + 2 * 4 + 1 * 4 + 1 * 4;
        Assert.Equal(expectedSp, cpu.Sp);
    }

    // ------------------------------------------------------------------
    // 2. Call/Ret SRAM tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A callee frame FrameBase-je a caller frame végén kezdődik
    /// (közvetlenül a caller eval stack után).
    /// <br />
    /// en: The callee frame's FrameBase starts immediately after the caller
    /// frame's end (right after the caller's eval stack).
    /// </summary>
    [Fact]
    public void Execute_Call_CalleeFrameBaseCorrect()
    {
        var cpu = new TCpuNano();

        // Caller at 0: arg=0, local=0, max=1, code_size=6
        //   call 14; ret
        // Callee at 14: arg=0, local=0, max=1, code_size=2
        //   ldc.i4.5; ret   → TOS=5, mélység=1
        // After ret: caller has TOS=5 on stack, FrameBase returns to 0
        var program = new byte[]
        {
            // caller header (0..7)
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            // caller code (8..13): call 14, ret
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            // callee header (14..21)
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            // callee code (22..23): ldc.i4.5, ret
            0x1B, 0x2A
        };

        cpu.Execute(program, 0);

        // hu: Execution végén a caller frame-ben vagyunk, FrameBase == 0
        // en: At end of execution we're in the caller frame, FrameBase == 0
        Assert.Equal(0, cpu.FrameBase);
    }

    /// <summary>
    /// hu: A callee SRAM header-je helyes: ReturnPC a call utáni opkód
    /// offszetje, PrevFrameBase a caller FrameBase-je, ArgCount és
    /// LocalCount a callee header-ből.
    /// <br />
    /// en: The callee SRAM header is correct: ReturnPC is the offset of the
    /// opcode following call, PrevFrameBase is the caller FrameBase,
    /// ArgCount and LocalCount come from the callee header.
    /// </summary>
    [Fact]
    public void Execute_Call_CalleeHeaderInSram()
    {
        var cpu = new TCpuNano();

        // hu: Egy "instrumented" program: caller breakpoint-ot szeretnénk
        // a callee visszatérése ELŐtt, de mivel a végrehajtás befejezése
        // után SRAM snapshot-ot kérünk, a ret után a caller frame aktív.
        // A caller arg=2, local=0 frame-je: header(12)+args(8)=20 byte.
        // Callee FB = 20.
        //
        // en: Program where caller has arg=2, local=0:
        // header(12)+args(2*4=8)=20 bytes. Callee FB = 20.
        //
        // Caller at 0: arg=2, local=0, max=2, code_size=9
        //   ldc.i4.3; ldc.i4.4; call 17; ret
        // Callee at 17: arg=2, local=0, max=2, code_size=4
        //   ldarg.0; ldarg.1; add; ret

        var program = new byte[]
        {
            // 0..7 caller header: arg=2, local=0, max=2, code_size=9
            0xFE, 0x02, 0x00, 0x02, 0x09, 0x00, 0x00, 0x00,
            // 8..16 caller code: ldc.i4.3, ldc.i4.4, call 17, ret
            0x19, 0x1A, 0x28, 0x11, 0x00, 0x00, 0x00, 0x2A,
            0x00, // padding to 17
            // 17..24 callee header: arg=2, local=0, max=2, code_size=4
            0xFE, 0x02, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00,
            // 25..28 callee code: ldarg.0, ldarg.1, add, ret
            0x02, 0x03, 0x58, 0x2A
        };

        cpu.Execute(program, 0, new[] { 10, 20 });

        // hu: Végrehajtás után a caller frame aktív, TOS = 3+4 = 7
        // en: After execution caller frame is active, TOS = 3+4 = 7
        Assert.Equal(7, cpu.Peek(0));

        var sram = cpu.SramSnapshot();

        // hu: Caller SRAM layout:
        //   [0..3]  ReturnPC == -1 (root)
        //   [4..7]  PrevFrameBase == -1 (root)
        //   [8]     ArgCount == 2
        //   [9]     LocalCount == 0
        //   [12..15] arg[0] == 10
        //   [16..19] arg[1] == 20
        //   Callee FB = 12 + 2*4 = 20
        //   [20..23] CallerReturnPC (= opcode after call = 8+2+1+5 = 16)
        //   [24..27] CallerPrevFrameBase == 0
        //   [28]    CalleArgCount == 2
        //   [29]    CalleLocalCount == 0
        //   [32..35] callee arg[0] == 3
        //   [36..39] callee arg[1] == 4
        // en: Caller SRAM layout as above; callee FB = 20.

        var callerArgCount = 2;
        var calleeFrameBase = FrameHeaderSize + callerArgCount * 4; // = 12 + 8 = 20

        var calleeArgCount = BitConverter.ToInt32(sram, calleeFrameBase + 8);
        Assert.Equal(2, calleeArgCount);

        var calleePrevFrameBase = BitConverter.ToInt32(sram, calleeFrameBase + 4);
        Assert.Equal(0, calleePrevFrameBase);
    }

    /// <summary>
    /// hu: A callee argumentumai az SRAM-ban a callee frame header (12 byte)
    /// után helyezkednek el, helyes értékekkel.
    /// <br />
    /// en: Callee arguments in SRAM are located after the callee frame header
    /// (12 bytes) with correct values.
    /// </summary>
    [Fact]
    public void Execute_Call_CalleeArgsInSram()
    {
        var cpu = new TCpuNano();

        // hu: Caller arg=0, local=0 → callee FB = 12 + 0 = 12
        // Caller pushes ldc.i4.3 és ldc.i4.4, hívja a callee-t (arg=2)
        // en: Caller arg=0, local=0 → callee FB = 12 + 0 = 12
        // Caller pushes ldc.i4.3 and ldc.i4.4, calls callee (arg=2)
        var program = new byte[]
        {
            // 0..7 caller header: arg=0, local=0, max=2, code_size=9
            0xFE, 0x00, 0x00, 0x02, 0x09, 0x00, 0x00, 0x00,
            // 8..16 caller code: ldc.i4.3, ldc.i4.4, call 17, ret
            0x19, 0x1A, 0x28, 0x11, 0x00, 0x00, 0x00, 0x2A,
            0x00,
            // 17..24 callee header: arg=2, local=0, max=2, code_size=4
            0xFE, 0x02, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00,
            // 25..28 callee code: ldarg.0, ldarg.1, add, ret
            0x02, 0x03, 0x58, 0x2A
        };

        cpu.Execute(program, 0);

        var sram = cpu.SramSnapshot();

        // Callee FB = FrameHeaderSize + 0*4 = 12 (caller has 0 args)
        var calleeFrameBase = FrameHeaderSize;
        var calleeArg0 = BitConverter.ToInt32(sram, calleeFrameBase + FrameHeaderSize);
        var calleeArg1 = BitConverter.ToInt32(sram, calleeFrameBase + FrameHeaderSize + 4);

        Assert.Equal(3, calleeArg0);
        Assert.Equal(4, calleeArg1);
    }

    /// <summary>
    /// hu: A ret utasítás végrehajtása után az Sp visszaáll a caller szintjére
    /// (a callee frame felszabadul az SRAM-ból).
    /// <br />
    /// en: After ret the Sp is restored to the caller level (the callee
    /// frame is freed from SRAM).
    /// </summary>
    [Fact]
    public void Execute_Ret_SpRestoredToCallerLevel()
    {
        var cpu = new TCpuNano();

        // hu: Caller: arg=0, local=0 → alap frame méret = 12 byte
        // A call visszatér, a caller TOS-ra kerül az eredmény (1 elem).
        // Végrehajtás végén: SP = 12 + 0 + 0 + 1*4 = 16
        // en: Caller: arg=0, local=0 → base frame size = 12 bytes
        // After call returns, result is on caller TOS (1 element).
        // At end: SP = 12 + 0 + 0 + 1*4 = 16
        var program = new byte[]
        {
            // 0..7 caller header: arg=0, local=0, max=1, code_size=6
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            // 8..13 caller code: call 14, ret
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            // 14..21 callee header: arg=0, local=0, max=1, code_size=2
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            // 22..23 callee code: ldc.i4.5, ret
            0x1B, 0x2A
        };

        cpu.Execute(program, 0);

        // hu: Caller frame: header(12) + args(0) + locals(0) + TOS(1*4=4) = 16
        // en: Caller frame: header(12) + args(0) + locals(0) + TOS(1*4=4) = 16
        var expectedSp = FrameHeaderSize + 0 + 0 + 1 * 4;
        Assert.Equal(expectedSp, cpu.Sp);
    }

    /// <summary>
    /// hu: A ret utasítás után a FrameBase visszaáll a caller frame bázisára.
    /// <br />
    /// en: After ret the FrameBase is restored to the caller frame's base.
    /// </summary>
    [Fact]
    public void Execute_Ret_FrameBaseRestoredToCaller()
    {
        var cpu = new TCpuNano();

        var program = new byte[]
        {
            // 0..7 caller header: arg=0, local=0, max=1, code_size=6
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            // 8..13 caller code: call 14, ret
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            // 14..21 callee header: arg=0, local=0, max=1, code_size=2
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            // 22..23 callee code: ldc.i4.7, ret
            0x1D, 0x2A
        };

        cpu.Execute(program, 0);

        // hu: Ret után visszatértünk a caller frame-be, FrameBase == 0
        // en: After ret we are back in the caller frame, FrameBase == 0
        Assert.Equal(0, cpu.FrameBase);
    }

    // ------------------------------------------------------------------
    // 3. Overflow tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Kis SRAM mérettel (128 byte) mély rekurzió SramOverflow trap-et
    /// dob, mert a stack már nem fér el az SRAM-ban.
    /// <br />
    /// en: With a small SRAM size (128 bytes) deep recursion raises a
    /// SramOverflow trap because the stack no longer fits in SRAM.
    /// </summary>
    [Fact]
    public void Execute_SramOverflow_SmallSram_Traps()
    {
        // hu: 128 byte SRAM — minden frame legalább 12 byte, tehát
        // ~10 szint után overflow kell. Az önhívó rekurzió garantáltan
        // feltölti az SRAM-ot.
        // en: 128-byte SRAM — each frame is at least 12 bytes, so after
        // ~10 levels overflow must occur. Self-recursive call fills SRAM.
        var cpu = new TCpuNano(null, 128);

        // self-recursive: header code_size=6, call rva=0, ret
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x00, 0x00, 0x00, 0x00, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.SramOverflow, trap.Reason);
    }

    /// <summary>
    /// hu: A meglévő eval stack overflow trap (64+ push) az SRAM refaktor
    /// után is helyesen működik.
    /// <br />
    /// en: The existing eval stack overflow trap (64+ pushes) still works
    /// correctly after the SRAM refactor.
    /// </summary>
    [Fact]
    public void Execute_EvalStackOverflow_StillTraps()
    {
        var cpu = new TCpuNano();

        // hu: 65 × ldc.i4.0 push → 65. push-on StackOverflow trap
        // en: 65 × ldc.i4.0 pushes → StackOverflow trap on the 65th push
        var opcodes = new byte[65];

        for (var i = 0; i < 65; i++)
            opcodes[i] = 0x16; // ldc.i4.0

        var codeSize = (ushort)opcodes.Length;
        var header = new byte[]
        {
            0xFE, 0x00, 0x00, 0x40,
            (byte)(codeSize & 0xFF), (byte)(codeSize >> 8),
            0x00, 0x00
        };

        var program = new byte[header.Length + opcodes.Length];
        header.CopyTo(program, 0);
        opcodes.CopyTo(program, header.Length);

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // 4. Kompatibilitás tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A Peek(0) az SRAM refaktor után is helyesen olvas az eval
    /// stack tetejéről.
    /// <br />
    /// en: Peek(0) correctly reads from the top of the eval stack after
    /// the SRAM refactor.
    /// </summary>
    [Fact]
    public void Execute_PeekStillWorks_AfterSramRefactor()
    {
        var cpu = new TCpuNano();

        // header: arg=2, local=0, max=2, code_size=3
        // code: ldarg.0, ldarg.1, add
        var program = new byte[]
        {
            0xFE, 0x02, 0x00, 0x02, 0x03, 0x00, 0x00, 0x00,
            0x02, 0x03, 0x58
        };

        cpu.Execute(program, 0, new[] { 11, 22 });

        Assert.Equal(33, cpu.Peek(0));
    }

    /// <summary>
    /// hu: A StackDepth az SRAM refaktor után is helyesen tükrözi az
    /// eval stack mélységét.
    /// <br />
    /// en: StackDepth correctly reflects eval stack depth after the
    /// SRAM refactor.
    /// </summary>
    [Fact]
    public void Execute_StackDepthStillWorks()
    {
        var cpu = new TCpuNano();

        // header: arg=0, local=0, max=3, code_size=3
        // code: ldc.i4.1, ldc.i4.2, ldc.i4.3  → depth = 3
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x00,
            0x17, 0x18, 0x19
        };

        cpu.Execute(program, 0);

        Assert.Equal(3, cpu.StackDepth);
    }

    // ------------------------------------------------------------------
    // 5. Raw Execute overload tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A nyers Execute(program, argCount, localCount, args) overload is
    /// az SRAM-ban építi fel a root frame-et.
    /// <br />
    /// en: The raw Execute(program, argCount, localCount, args) overload
    /// also builds the root frame in SRAM.
    /// </summary>
    [Fact]
    public void Execute_Raw_RootFrameInSram()
    {
        var cpu = new TCpuNano();

        // nyers kód, header nélkül: ldarg.0, ldarg.1, add
        var program = new byte[] { 0x02, 0x03, 0x58 };

        cpu.Execute(program, 2, 0, new[] { 5, 6 });

        var sram = cpu.SramSnapshot();

        // ReturnPC @ [0] == -1 (root)
        var returnPc = BitConverter.ToInt32(sram, 0);
        Assert.Equal(-1, returnPc);

        // ArgCount @ [8] == 2
        Assert.Equal(2, sram[8]);

        // arg[0] @ [12] == 5
        var arg0 = BitConverter.ToInt32(sram, FrameHeaderSize);
        Assert.Equal(5, arg0);

        // arg[1] @ [16] == 6
        var arg1 = BitConverter.ToInt32(sram, FrameHeaderSize + 4);
        Assert.Equal(6, arg1);

        // TOS == 11
        Assert.Equal(11, cpu.Peek(0));
    }

    /// <summary>
    /// hu: A nyers Execute(program) overload (0 arg, 0 local) is FrameBase=0-t
    /// produkál.
    /// <br />
    /// en: The raw Execute(program) overload (0 args, 0 locals) also
    /// produces FrameBase=0.
    /// </summary>
    [Fact]
    public void Execute_RawNoArgs_FrameBaseZero()
    {
        var cpu = new TCpuNano();

        // ldc.i4.7
        var program = new byte[] { 0x1D };

        cpu.Execute(program);

        Assert.Equal(0, cpu.FrameBase);
    }

    // ------------------------------------------------------------------
    // 6. SramSize teszt
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A TCpuNano(null, ASramSize) konstruktor a megadott SRAM méretet
    /// hozza létre, és ezt a SramSize property tükrözi.
    /// <br />
    /// en: The TCpuNano(null, ASramSize) constructor creates SRAM with the
    /// specified size, reflected by the SramSize property.
    /// </summary>
    [Fact]
    public void Constructor_CustomSramSize_SramSizeMatchesParameter()
    {
        var cpu = new TCpuNano(null, 4096);

        Assert.Equal(4096, cpu.SramSize);
    }

    /// <summary>
    /// hu: Az alapértelmezett TCpuNano() konstruktor 16384 byte SRAM-ot hoz létre.
    /// <br />
    /// en: The default TCpuNano() constructor creates 16384 bytes of SRAM.
    /// </summary>
    [Fact]
    public void Constructor_Default_SramSizeIs16384()
    {
        var cpu = new TCpuNano();

        Assert.Equal(16384, cpu.SramSize);
    }
}
