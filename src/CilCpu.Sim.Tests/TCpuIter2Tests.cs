namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu iter. 2 tesztjei: stack manipuláció (dup, pop), lokális
/// változók (ldloc.0..3, ldloc.s, stloc.0..3, stloc.s), és argumentumok
/// (ldarg.0..3, ldarg.s, starg.s). A trap-tesztek lefedik a StackUnderflow,
/// InvalidLocal és InvalidArg trap ágakat.
/// <br />
/// en: TCpu iter. 2 tests: stack manipulation (dup, pop), locals
/// (ldloc.0..3, ldloc.s, stloc.0..3, stloc.s), and arguments
/// (ldarg.0..3, ldarg.s, starg.s). The trap tests cover the
/// StackUnderflow, InvalidLocal and InvalidArg trap branches.
/// </summary>
public class TCpuIter2Tests
{
    // ------------------------------------------------------------------
    // dup (0x25)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A dup opkód (0x25) a TOS-t duplikálja. A mélység +1, Peek(0) és
    /// Peek(1) is az eredeti érték.
    /// <br />
    /// en: The dup opcode (0x25) duplicates TOS. Depth grows by 1, and
    /// Peek(0) and Peek(1) both hold the original value.
    /// </summary>
    [Fact]
    public void Execute_Dup_OnNonEmpty_DuplicatesTos_DepthGrows()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x25 }; // ldc.i4.5; dup

        cpu.Execute(program);

        Assert.Equal(2, cpu.StackDepth);
        Assert.Equal(5, cpu.Peek(0));
        Assert.Equal(5, cpu.Peek(1));
        Assert.Equal(2, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: A dup üres stacken StackUnderflow trap — a PC a dup byte
    /// offszetjén marad.
    /// <br />
    /// en: Dup on an empty stack raises a StackUnderflow trap — the PC
    /// stays at the dup byte's offset.
    /// </summary>
    [Fact]
    public void Execute_Dup_OnEmpty_ThrowsStackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x25 }; // dup

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: A dup a max mélységen StackOverflow trap.
    /// <br />
    /// en: Dup at max depth raises a StackOverflow trap.
    /// </summary>
    [Fact]
    public void Execute_Dup_AtMaxDepth_ThrowsStackOverflow()
    {
        var cpu = new TCpu();
        // 64 ldc.i4.0 + dup
        var program = new byte[65];

        for (var i = 0; i < 64; i++)
            program[i] = 0x16;

        program[64] = 0x25; // dup

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
        Assert.Equal(64, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // pop (0x26)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A pop opkód (0x26) eldobja a TOS-t. A mélység -1.
    /// <br />
    /// en: The pop opcode (0x26) discards TOS. Depth decreases by 1.
    /// </summary>
    [Fact]
    public void Execute_Pop_OnNonEmpty_RemovesTos_DepthShrinks()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19, 0x26 }; // ldc.i4.3; pop

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(2, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: A pop üres stacken StackUnderflow trap.
    /// <br />
    /// en: Pop on an empty stack raises a StackUnderflow trap.
    /// </summary>
    [Fact]
    public void Execute_Pop_OnEmpty_ThrowsStackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x26 }; // pop

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // ldloc.0..3 (0x06..0x09)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldloc.0 (0x06) az első lokálist pusholja. Használati minta:
    /// először stloc.0 egy ismert konstanssal, majd ldloc.0 visszaolvasás.
    /// <br />
    /// en: ldloc.0 (0x06) pushes the first local. Pattern: first stloc.0
    /// a known constant, then ldloc.0 to read it back.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_0_PushesLocal0()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x0A, 0x06 }; // ldc.i4.5; stloc.0; ldloc.0

        cpu.Execute(program, 0, 1);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldloc.1 (0x07) a második lokálist pusholja.
    /// <br />
    /// en: ldloc.1 (0x07) pushes the second local.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_1_PushesLocal1()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1C, 0x0B, 0x07 }; // ldc.i4.6; stloc.1; ldloc.1

        cpu.Execute(program, 0, 2);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(6, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldloc.2 (0x08) a harmadik lokálist pusholja.
    /// <br />
    /// en: ldloc.2 (0x08) pushes the third local.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_2_PushesLocal2()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1D, 0x0C, 0x08 }; // ldc.i4.7; stloc.2; ldloc.2

        cpu.Execute(program, 0, 3);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(7, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldloc.3 (0x09) a negyedik lokálist pusholja.
    /// <br />
    /// en: ldloc.3 (0x09) pushes the fourth local.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_3_PushesLocal3()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1E, 0x0D, 0x09 }; // ldc.i4.8; stloc.3; ldloc.3

        cpu.Execute(program, 0, 4);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(8, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // ldloc.s (0x11)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldloc.s 4 (0x11 0x04) a 4-es indexű lokálist pusholja.
    /// <br />
    /// en: ldloc.s 4 (0x11 0x04) pushes the local at index 4.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_S_Index4_PushesLocal4()
    {
        var cpu = new TCpu();
        // ldc.i4.s 42; stloc.s 4; ldloc.s 4
        var program = new byte[] { 0x1F, 0x2A, 0x13, 0x04, 0x11, 0x04 };

        cpu.Execute(program, 0, 5);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(42, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldloc.s 15 (0x11 0x0F) — a legmagasabb érvényes index.
    /// <br />
    /// en: ldloc.s 15 (0x11 0x0F) — the highest valid index.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_S_Index15_PushesLocal15()
    {
        var cpu = new TCpu();
        // ldc.i4.s 99; stloc.s 15; ldloc.s 15
        var program = new byte[] { 0x1F, 0x63, 0x13, 0x0F, 0x11, 0x0F };

        cpu.Execute(program, 0, 16);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(99, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldloc.s 16 (0x11 0x10) — index ≥ MaxLocals → InvalidLocal trap.
    /// <br />
    /// en: ldloc.s 16 (0x11 0x10) — index ≥ MaxLocals → InvalidLocal trap.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_S_InvalidIndex_ThrowsInvalidLocal()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x11, 0x10 }; // ldloc.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 16));

        Assert.Equal(TTrapReason.InvalidLocal, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: ldloc.s index ≥ a tényleges LocalCount → InvalidLocal trap,
    /// még akkor is, ha index &lt; 16.
    /// <br />
    /// en: ldloc.s with index ≥ the actual LocalCount → InvalidLocal trap,
    /// even if index &lt; 16.
    /// </summary>
    [Fact]
    public void Execute_LdLoc_S_IndexBeyondLocalCount_ThrowsInvalidLocal()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x11, 0x04 }; // ldloc.s 4

        // hu: LocalCount = 4, index = 4 → index ≥ count
        // en: LocalCount = 4, index = 4 → index ≥ count
        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 4));

        Assert.Equal(TTrapReason.InvalidLocal, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // stloc.0..3 (0x0A..0x0D)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: stloc.0 (0x0A) a TOS-t a lokális 0-ba menti. Ellenőrzés: stloc
    /// után ldloc-al visszaolvasunk ugyanabba a slotba.
    /// <br />
    /// en: stloc.0 (0x0A) stores TOS into local 0. Verified by reading it
    /// back with ldloc.0.
    /// </summary>
    [Fact]
    public void Execute_StLoc_0_StoresTosIntoLocal0()
    {
        var cpu = new TCpu();
        // ldc.i4.s 11; stloc.0; ldloc.0
        var program = new byte[] { 0x1F, 0x0B, 0x0A, 0x06 };

        cpu.Execute(program, 0, 1);

        Assert.Equal(11, cpu.Peek(0));
    }

    /// <summary>
    /// hu: stloc.1 (0x0B), stloc.2 (0x0C), stloc.3 (0x0D) mind a megfelelő
    /// lokálisba menti a TOS-t.
    /// <br />
    /// en: stloc.1 (0x0B), stloc.2 (0x0C), stloc.3 (0x0D) all store TOS
    /// into the corresponding local.
    /// </summary>
    [Fact]
    public void Execute_StLoc_1_2_3_StoreTosIntoCorrectLocal()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x14, // ldc.i4.s 20
            0x0B,       // stloc.1
            0x1F, 0x1E, // ldc.i4.s 30
            0x0C,       // stloc.2
            0x1F, 0x28, // ldc.i4.s 40
            0x0D,       // stloc.3
            0x07,       // ldloc.1
            0x08,       // ldloc.2
            0x09        // ldloc.3
        };

        cpu.Execute(program, 0, 4);

        Assert.Equal(3, cpu.StackDepth);
        Assert.Equal(40, cpu.Peek(0));
        Assert.Equal(30, cpu.Peek(1));
        Assert.Equal(20, cpu.Peek(2));
    }

    /// <summary>
    /// hu: stloc.s érvénytelen index → InvalidLocal trap.
    /// <br />
    /// en: stloc.s invalid index → InvalidLocal trap.
    /// </summary>
    [Fact]
    public void Execute_StLoc_S_InvalidIndex_ThrowsInvalidLocal()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x13, 0x10 }; // stloc.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 16));

        Assert.Equal(TTrapReason.InvalidLocal, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: G1 trap sorrend (iter. 3 fixálta a Devil's Advocate review után):
    /// stloc.s érvénytelen INDEX-szel ÉS üres stack-kel együtt — a hardver
    /// és a szimulátor egyaránt először az index ellenőrzést végzi, így
    /// <see cref="TTrapReason.InvalidLocal"/> az elsőbbség, NEM
    /// <see cref="TTrapReason.StackUnderflow"/>. Ezt az ISA-CIL-T0.md
    /// "Trap (kivétel) típusok" szekciója rögzíti.
    /// <br />
    /// en: G1 trap ordering (pinned down in iter. 3 after the Devil's
    /// Advocate review): stloc.s with both an invalid INDEX and an empty
    /// stack — both hardware and simulator perform the index check first,
    /// so <see cref="TTrapReason.InvalidLocal"/> takes precedence, NOT
    /// <see cref="TTrapReason.StackUnderflow"/>. Pinned in the ISA-CIL-T0.md
    /// "Trap types" section.
    /// </summary>
    [Fact]
    public void Execute_StLoc_S_InvalidIndexAndEmptyStack_InvalidLocalTakesPrecedence()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x13, 0x10 }; // stloc.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 16));

        Assert.Equal(TTrapReason.InvalidLocal, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: G1 trap sorrend, starg.s változat: érvénytelen index ÉS üres
    /// stack együtt — <see cref="TTrapReason.InvalidArg"/> az elsőbbség.
    /// <br />
    /// en: G1 trap ordering, starg.s variant: invalid index AND empty
    /// stack together — <see cref="TTrapReason.InvalidArg"/> takes
    /// precedence.
    /// </summary>
    [Fact]
    public void Execute_StArg_S_InvalidIndexAndEmptyStack_InvalidArgTakesPrecedence()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x10, 0x10 }; // starg.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 0));

        Assert.Equal(TTrapReason.InvalidArg, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: stloc.0 üres stacken StackUnderflow trap.
    /// <br />
    /// en: stloc.0 on an empty stack raises a StackUnderflow trap.
    /// </summary>
    [Fact]
    public void Execute_StLoc_S_StackUnderflow_ThrowsStackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x0A }; // stloc.0

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0, 1));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // ldarg.0..3 (0x02..0x05)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldarg.0 (0x02) az első argumentumot pusholja.
    /// <br />
    /// en: ldarg.0 (0x02) pushes the first argument.
    /// </summary>
    [Fact]
    public void Execute_LdArg_0_PushesArg0()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x02 }; // ldarg.0

        cpu.Execute(program, 4, 0, new[] { 10, 20, 30, 40 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(10, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldarg.1..3 a megfelelő argumentumokat pusholja.
    /// <br />
    /// en: ldarg.1..3 push the corresponding arguments.
    /// </summary>
    [Fact]
    public void Execute_LdArg_1_2_3_PushCorrectArgs()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x03, 0x04, 0x05 }; // ldarg.1; ldarg.2; ldarg.3

        cpu.Execute(program, 4, 0, new[] { 10, 20, 30, 40 });

        Assert.Equal(3, cpu.StackDepth);
        Assert.Equal(40, cpu.Peek(0));
        Assert.Equal(30, cpu.Peek(1));
        Assert.Equal(20, cpu.Peek(2));
    }

    // ------------------------------------------------------------------
    // ldarg.s (0x0E)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldarg.s 4 (0x0E 0x04) — arg index 4 push-olása.
    /// <br />
    /// en: ldarg.s 4 (0x0E 0x04) — push arg at index 4.
    /// </summary>
    [Fact]
    public void Execute_LdArg_S_Index4_PushesArg4()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x0E, 0x04 }; // ldarg.s 4

        var initial = new[] { 0, 1, 2, 3, 40, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
        cpu.Execute(program, 16, 0, initial);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(40, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldarg.s 16 (0x0E 0x10) — index ≥ MaxArgs → InvalidArg trap.
    /// <br />
    /// en: ldarg.s 16 (0x0E 0x10) — index ≥ MaxArgs → InvalidArg trap.
    /// </summary>
    [Fact]
    public void Execute_LdArg_S_InvalidIndex_ThrowsInvalidArg()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x0E, 0x10 }; // ldarg.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 16, 0));

        Assert.Equal(TTrapReason.InvalidArg, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: ldarg.s index ≥ a tényleges ArgCount → InvalidArg trap.
    /// <br />
    /// en: ldarg.s with index ≥ the actual ArgCount → InvalidArg trap.
    /// </summary>
    [Fact]
    public void Execute_LdArg_S_IndexBeyondArgCount_ThrowsInvalidArg()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x0E, 0x03 }; // ldarg.s 3

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 2, 0));

        Assert.Equal(TTrapReason.InvalidArg, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // starg.s (0x10)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: starg.s 0 frissíti az args[0] értékét a TOS-ról, aminek aztán
    /// ldarg.0-val visszaolvasva ugyanaz lesz az értéke.
    /// <br />
    /// en: starg.s 0 updates args[0] from TOS, which is then read back
    /// with ldarg.0.
    /// </summary>
    [Fact]
    public void Execute_StArg_S_UpdatesArg()
    {
        var cpu = new TCpu();
        // ldc.i4.s 77; starg.s 0; ldarg.0
        var program = new byte[] { 0x1F, 0x4D, 0x10, 0x00, 0x02 };

        cpu.Execute(program, 1, 0, new[] { 5 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(77, cpu.Peek(0));
    }

    /// <summary>
    /// hu: starg.s 16 (0x10 0x10) — index ≥ MaxArgs → InvalidArg trap.
    /// <br />
    /// en: starg.s 16 (0x10 0x10) — index ≥ MaxArgs → InvalidArg trap.
    /// </summary>
    [Fact]
    public void Execute_StArg_S_InvalidIndex_ThrowsInvalidArg()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x10, 0x10 }; // starg.s 16

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 16, 0));

        Assert.Equal(TTrapReason.InvalidArg, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: starg.s üres stacken StackUnderflow trap.
    /// <br />
    /// en: starg.s on an empty stack raises a StackUnderflow trap.
    /// </summary>
    [Fact]
    public void Execute_StArg_S_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x10, 0x00 }; // starg.s 0

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 1, 0, new[] { 5 }));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // Integration tests
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Swap program: két argumentumot felcserél lokálisokon keresztül.
    /// ldarg.0, ldarg.1, stloc.0, stloc.1, ldloc.0, ldloc.1.
    /// Bemenet: args = [100, 200]. Ellenőrzés:
    /// Először ldarg.0=100-at, ldarg.1=200-at push-olunk → stack: [100, 200].
    /// stloc.0 → local[0]=200 (TOS), stloc.1 → local[1]=100.
    /// ldloc.0 → 200, ldloc.1 → 100. Végleges: TOS=100, TOS-1=200.
    /// <br />
    /// en: Swap program: swaps two arguments via locals. ldarg.0, ldarg.1,
    /// stloc.0, stloc.1, ldloc.0, ldloc.1. Input: args = [100, 200].
    /// Verification: ldarg.0=100 then ldarg.1=200 push → stack [100, 200].
    /// stloc.0 → local[0]=200, stloc.1 → local[1]=100. ldloc.0 → 200,
    /// ldloc.1 → 100. Final: TOS=100, TOS-1=200.
    /// </summary>
    [Fact]
    public void Execute_SwapViaLocals_ResultIsSwapped()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x02, // ldarg.0 → push 100
            0x03, // ldarg.1 → push 200
            0x0A, // stloc.0 → local[0] = 200
            0x0B, // stloc.1 → local[1] = 100
            0x06, // ldloc.0 → push 200
            0x07  // ldloc.1 → push 100
        };

        cpu.Execute(program, 2, 2, new[] { 100, 200 });

        Assert.Equal(2, cpu.StackDepth);
        Assert.Equal(100, cpu.Peek(0));
        Assert.Equal(200, cpu.Peek(1));
    }

    /// <summary>
    /// hu: Dup + pop integrációs mikroteszt: ldc.i4.5; dup → stack [5, 5];
    /// majd pop pop → üres stack.
    /// <br />
    /// en: Dup + pop integration micro-test: ldc.i4.5; dup → stack [5, 5];
    /// then pop pop → empty stack.
    /// </summary>
    [Fact]
    public void Execute_LdcDupPopPop_EndsEmpty()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x25, 0x26, 0x26 }; // ldc.i4.5; dup; pop; pop

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(4, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Push + pop cycle: ldc.i4.3; pop → üres stack.
    /// <br />
    /// en: Push + pop cycle: ldc.i4.3; pop → empty stack.
    /// </summary>
    [Fact]
    public void Execute_PushPopCycle_EndsEmpty()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19, 0x26 }; // ldc.i4.3; pop

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(2, cpu.ProgramCounter);
    }
}
