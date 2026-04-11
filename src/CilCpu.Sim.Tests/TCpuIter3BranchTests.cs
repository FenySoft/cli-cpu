namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu iter. 3 elágazás (branch) tesztjei: br.s, brfalse.s, brtrue.s,
/// beq.s, bge.s, bgt.s, ble.s, blt.s, bne.un.s. A tesztek lefedik a takes /
/// fall-through ágakat, az előre/hátrafelé ugrást, az érvénytelen branch
/// targetet (InvalidBranchTarget trap), és a stack underflow-t.
/// <br />
/// en: TCpu iter. 3 branch tests: br.s, brfalse.s, brtrue.s, beq.s, bge.s,
/// bgt.s, ble.s, blt.s, bne.un.s. The tests cover taken/fall-through branches,
/// forward and backward jumps, invalid branch targets (InvalidBranchTarget
/// trap), and stack underflow.
/// </summary>
public class TCpuIter3BranchTests
{
    // ------------------------------------------------------------------
    // br.s (0x2B) — unconditional
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: br.s előre ugrás: az ugrás után álló pop-ot átugorja, így
    /// a TOS érintetlen marad. Program: ldc.i4.5; br.s +1; pop. Az
    /// ugrás után a PC a program végén van, a stack mélysége 1.
    /// <br />
    /// en: br.s forward jump: skips the trailing pop, leaving TOS intact.
    /// Program: ldc.i4.5; br.s +1; pop. After the jump PC is at end of
    /// program, stack depth is 1.
    /// </summary>
    [Fact]
    public void Execute_BrS_ForwardJump_SkipsPop()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B,       // 0: ldc.i4.5
            0x2B, 0x01, // 1: br.s +1 → target = 1+2+1 = 4
            0x26        // 3: pop  (skipped)
                        // 4: end
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(5, cpu.Peek(0));
        Assert.Equal(4, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s hátrafelé ugrás: ldc.i4.0 → br.s -3 sose terminál... ezért
    /// a tesztben egy kontrollált scenario-t használunk: brtrue.s előre,
    /// majd br.s hátra a kezdő pop-ig egy ciklus formájában. Helyett
    /// egyszerű br.s teszt: két br.s láncolva, ahol a második hátra ugrik
    /// a programban egy NOP-ig, majd onnan tovább a végéig.
    /// Program:
    ///   0: nop
    ///   1: br.s +2 → target 5 (skip a hátra-br-t)
    ///   3: br.s -4 → target 1 (sose hajtódik végre, csak ide ugrunk
    ///                          tesztben br.s offset megfigyeléshez)
    ///   5: nop
    /// Itt a futás végén PC=6.
    /// <br />
    /// en: br.s backward jump: a controlled scenario where one br.s jumps
    /// forward over a second br.s, demonstrating that backward offsets
    /// produce correct PC arithmetic without an actual loop.
    /// Program:
    ///   0: nop
    ///   1: br.s +2 → target 5
    ///   3: br.s -4 → target 1 (not executed)
    ///   5: nop
    /// Final PC = 6.
    /// </summary>
    [Fact]
    public void Execute_BrS_BackwardJumpReachable_ViaForwardSkip()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x00,       // 0: nop
            0x2B, 0x02, // 1: br.s +2 → target = 1+2+2 = 5
            0x2B, 0xFC, // 3: br.s -4 (skipped)
            0x00        // 5: nop
                        // 6: end
        };

        cpu.Execute(program);

        Assert.Equal(6, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s hátraugrás konkrét scenario-ja egy számlálós ciklussal.
    /// stloc.0 = 0; loop: ldloc.0; ldc.i4.1; add; stloc.0; ldloc.0; ldc.i4.s 3; bge.s end; br.s loop; end:
    /// — itt a br.s hátra mutat, a bge.s pedig kilép a ciklusból. Várjuk, hogy a
    /// loop legalább egyszer lefusson és a végén a lokális 0 értéke 3 legyen.
    /// <br />
    /// en: br.s backward jump in a real counter loop. The loop increments
    /// local 0 until it reaches 3, then bge.s exits. Verifies br.s correctly
    /// goes back to the loop start.
    /// </summary>
    [Fact]
    public void Execute_BrS_BackwardJump_PcReturnsEarlier()
    {
        var cpu = new TCpu();
        // 0: ldc.i4.0       (push 0)
        // 1: stloc.0        (local0 = 0)
        // 2: ldloc.0        (push local0)             ← LOOP
        // 3: ldc.i4.1
        // 4: add
        // 5: stloc.0        (local0++)
        // 6: ldloc.0
        // 7: ldc.i4.3
        // 8: bge.s +2 → target 12 (END)
        // 10: br.s -8 → target 2 (LOOP)
        // 12: ldloc.0       (push final local0)
        // 13: end
        var program = new byte[]
        {
            0x16,       // 0: ldc.i4.0
            0x0A,       // 1: stloc.0
            0x06,       // 2: ldloc.0       (LOOP)
            0x17,       // 3: ldc.i4.1
            0x58,       // 4: add
            0x0A,       // 5: stloc.0
            0x06,       // 6: ldloc.0
            0x19,       // 7: ldc.i4.3
            0x2F, 0x02, // 8: bge.s +2 → target = 8+2+2 = 12
            0x2B, 0xF6, // 10: br.s -10 → target = 10+2-10 = 2 (LOOP)
            0x06        // 12: ldloc.0
        };

        cpu.Execute(program, 0, 1);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(3, cpu.Peek(0));
    }

    /// <summary>
    /// hu: br.s előre az érvényes tartományon kívülre → InvalidBranchTarget.
    /// <br />
    /// en: br.s forward beyond program length → InvalidBranchTarget.
    /// </summary>
    [Fact]
    public void Execute_BrS_JumpOutOfRange_Forward_RaisesInvalidBranchTarget()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x2B, 0x7F  // 0: br.s +127 → target 129, prog hossz 2
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidBranchTarget, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s hátrafelé negatív cím → InvalidBranchTarget.
    /// <br />
    /// en: br.s backward to negative target → InvalidBranchTarget.
    /// </summary>
    [Fact]
    public void Execute_BrS_JumpOutOfRange_Backward_RaisesInvalidBranchTarget()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x2B, 0x80  // 0: br.s -128 → target = 0+2-128 = -126
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidBranchTarget, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // brfalse.s (0x2C)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: brfalse.s 0 TOS-szal → branch.
    /// <br />
    /// en: brfalse.s with TOS == 0 → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BrfalseS_ZeroTos_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x16,       // 0: ldc.i4.0
            0x2C, 0x01, // 1: brfalse.s +1 → target 4
            0x17        // 3: ldc.i4.1 (skipped)
                        // 4: end
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(4, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: brfalse.s nem nulla TOS-szal → fall-through.
    /// <br />
    /// en: brfalse.s with non-zero TOS → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BrfalseS_NonzeroTos_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,       // 0: ldc.i4.1
            0x2C, 0x01, // 1: brfalse.s +1 (not taken)
            0x18        // 3: ldc.i4.2 (executed)
                        // 4: end
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(2, cpu.Peek(0));
        Assert.Equal(4, cpu.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // brtrue.s (0x2D)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: brtrue.s nem nulla TOS-szal → branch.
    /// <br />
    /// en: brtrue.s with non-zero TOS → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BrtrueS_NonzeroTos_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,       // 0: ldc.i4.1
            0x2D, 0x01, // 1: brtrue.s +1
            0x18        // 3: ldc.i4.2 (skipped)
                        // 4: end
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(4, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: brtrue.s 0 TOS-szal → fall-through.
    /// <br />
    /// en: brtrue.s with TOS == 0 → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BrtrueS_ZeroTos_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x16,       // 0: ldc.i4.0
            0x2D, 0x01, // 1: brtrue.s +1 (not taken)
            0x18        // 3: ldc.i4.2 (executed)
                        // 4: end
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(2, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // beq.s (0x2E)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: beq.s egyenlő → branch.
    /// <br />
    /// en: beq.s equal → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BeqS_Equal_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1B,       // ldc.i4.5; ldc.i4.5
            0x2E, 0x01,       // beq.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: beq.s nem egyenlő → fall-through.
    /// <br />
    /// en: beq.s not equal → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BeqS_NotEqual_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1A,       // ldc.i4.5; ldc.i4.4
            0x2E, 0x01,       // beq.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // bge.s (0x2F)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: bge.s greater → branch.
    /// <br />
    /// en: bge.s greater → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BgeS_Greater_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x19,       // ldc.i4.5; ldc.i4.3
            0x2F, 0x01,       // bge.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: bge.s less → fall-through.
    /// <br />
    /// en: bge.s less → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BgeS_Less_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x19, 0x1B,       // ldc.i4.3; ldc.i4.5
            0x2F, 0x01,       // bge.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // bgt.s (0x30)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: bgt.s greater → branch.
    /// <br />
    /// en: bgt.s greater → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BgtS_Greater_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x19,       // ldc.i4.5; ldc.i4.3
            0x30, 0x01,       // bgt.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: bgt.s equal → fall-through (mert &gt;, nem ≥).
    /// <br />
    /// en: bgt.s equal → fall-through (because &gt;, not ≥).
    /// </summary>
    [Fact]
    public void Execute_BgtS_Equal_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1B,       // ldc.i4.5; ldc.i4.5
            0x30, 0x01,       // bgt.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // ble.s (0x31)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ble.s less → branch.
    /// <br />
    /// en: ble.s less → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BleS_Less_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x19, 0x1B,       // ldc.i4.3; ldc.i4.5
            0x31, 0x01,       // ble.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: ble.s greater → fall-through.
    /// <br />
    /// en: ble.s greater → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BleS_Greater_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x19,       // ldc.i4.5; ldc.i4.3
            0x31, 0x01,       // ble.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // blt.s (0x32)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: blt.s less → branch.
    /// <br />
    /// en: blt.s less → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BltS_Less_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x19, 0x1B,       // ldc.i4.3; ldc.i4.5
            0x32, 0x01,       // blt.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: blt.s equal → fall-through.
    /// <br />
    /// en: blt.s equal → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BltS_Equal_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1B,       // ldc.i4.5; ldc.i4.5
            0x32, 0x01,       // blt.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // bne.un.s (0x33)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: bne.un.s nem egyenlő → branch.
    /// <br />
    /// en: bne.un.s not equal → takes branch.
    /// </summary>
    [Fact]
    public void Execute_BneUnS_NotEqual_TakesBranch()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1A,       // ldc.i4.5; ldc.i4.4
            0x33, 0x01,       // bne.un.s +1
            0x17              // ldc.i4.1 (skipped)
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: bne.un.s egyenlő → fall-through.
    /// <br />
    /// en: bne.un.s equal → fall-through.
    /// </summary>
    [Fact]
    public void Execute_BneUnS_Equal_FallThrough()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B, 0x1B,       // ldc.i4.5; ldc.i4.5
            0x33, 0x01,       // bne.un.s +1 (not taken)
            0x17              // ldc.i4.1 (executed)
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // Stack underflow & truncated branch tesztek
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: brfalse.s üres stacken StackUnderflow.
    /// <br />
    /// en: brfalse.s on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_BrfalseS_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x2C, 0x00 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: beq.s egy elemmel a stacken StackUnderflow.
    /// <br />
    /// en: beq.s with one element on stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_BeqS_OneElement_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0x2E, 0x00 }; // ldc.i4.1; beq.s +0

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(1, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s csak az opkód byte van, operand hiányzik → InvalidOpcode trap.
    /// <br />
    /// en: br.s with the opcode byte only, operand missing → InvalidOpcode.
    /// </summary>
    [Fact]
    public void Execute_BrS_TruncatedOperand_RaisesInvalidOpcode()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x2B };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s offset 0 — érvényes (fall-through targetre ugrik).
    /// <br />
    /// en: br.s offset 0 — valid (jumps to fall-through target).
    /// </summary>
    [Fact]
    public void Execute_BrS_OffsetZero_Valid()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x2B, 0x00, // 0: br.s +0 → target 2
            0x00        // 2: nop
        };

        cpu.Execute(program);

        Assert.Equal(3, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: br.s a program végére (target == AProgram.Length) érvényes — a végrehajtó leáll.
    /// <br />
    /// en: br.s to program end (target == AProgram.Length) is valid — executor halts.
    /// </summary>
    [Fact]
    public void Execute_BrS_TargetIsEndOfProgram_Valid()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x2B, 0x00 // 0: br.s +0 → target 2 == AProgram.Length
        };

        cpu.Execute(program);

        Assert.Equal(2, cpu.ProgramCounter);
    }
}
