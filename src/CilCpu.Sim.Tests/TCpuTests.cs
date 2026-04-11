namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu osztály alapvető végrehajtási tesztjei.
/// <br />
/// en: Basic execution tests for the TCpu class.
/// </summary>
public class TCpuTests
{
    /// <summary>
    /// hu: A nop opkód (0x00) semmit nem csinál és az evaluation stack
    /// változatlan marad. Ez a legegyszerűbb opkód, a TDD első lépcsője.
    /// <br />
    /// en: The nop opcode (0x00) does nothing and the evaluation stack
    /// remains unchanged. This is the simplest opcode, the first TDD step.
    /// </summary>
    [Fact]
    public void Execute_Nop_LeavesStackUnchanged()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x00 }; // nop

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: A nop opkód után a ProgramCounter pontosan 1-gyel nő.
    /// <br />
    /// en: After the nop opcode, the ProgramCounter is incremented by exactly 1.
    /// </summary>
    [Fact]
    public void Execute_Nop_AdvancesProgramCounterByOne()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x00, 0x00, 0x00 }; // három nop

        cpu.Execute(program);

        Assert.Equal(3, cpu.ProgramCounter);
        Assert.Equal(0, cpu.StackDepth);
    }

    /// <summary>
    /// hu: Az ldc.i4.0 opkód (0x16) a konstans 0-t tölti az
    /// evaluation stack tetejére. A stack mélysége 1-re nő, és a
    /// TOS (Top-of-Stack) értéke pontosan 0.
    /// <br />
    /// en: The ldc.i4.0 opcode (0x16) pushes the constant 0 to the
    /// top of the evaluation stack. Stack depth becomes 1, and the
    /// TOS (Top-of-Stack) value is exactly 0.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_0_PushesZeroToStack()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x16 }; // ldc.i4.0

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.0 opkód kétszer egymás után két értéket
    /// (mindkettő 0) tölt a stack-re, a mélység 2 lesz, és mindkét
    /// stack slot tartalma 0.
    /// <br />
    /// en: Two consecutive ldc.i4.0 opcodes push two values (both 0)
    /// onto the stack, depth becomes 2, and both stack slots hold 0.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_0_Twice_PushesTwoZeros()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x16, 0x16 }; // ldc.i4.0; ldc.i4.0

        cpu.Execute(program);

        Assert.Equal(2, cpu.StackDepth);
        Assert.Equal(0, cpu.Peek(0));
        Assert.Equal(0, cpu.Peek(1));
        Assert.Equal(2, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldnull opkód (0x14) a null referenciát reprezentáló 0-t
    /// tolja a stack-re. Az I4 modellben null == 0.
    /// <br />
    /// en: The ldnull opcode (0x14) pushes 0 onto the stack to represent
    /// the null reference. In the I4 model, null == 0.
    /// </summary>
    [Fact]
    public void Execute_Ldnull_PushesZero()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x14 }; // ldnull

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.m1 opkód (0x15) a -1 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.m1 opcode (0x15) pushes the constant -1 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_m1_PushesMinusOne()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15 }; // ldc.i4.m1

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(-1, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.1 opkód (0x17) az 1 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.1 opcode (0x17) pushes the constant 1 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_1_PushesOne()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(1, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.2 opkód (0x18) a 2 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.2 opcode (0x18) pushes the constant 2 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_2_PushesTwo()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x18 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(2, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.3 opkód (0x19) a 3 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.3 opcode (0x19) pushes the constant 3 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_3_PushesThree()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(3, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.4 opkód (0x1A) a 4 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.4 opcode (0x1A) pushes the constant 4 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_4_PushesFour()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(4, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.5 opkód (0x1B) az 5 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.5 opcode (0x1B) pushes the constant 5 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_5_PushesFive()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(5, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.6 opkód (0x1C) a 6 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.6 opcode (0x1C) pushes the constant 6 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_6_PushesSix()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1C };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(6, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.7 opkód (0x1D) a 7 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.7 opcode (0x1D) pushes the constant 7 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_7_PushesSeven()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1D };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(7, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.8 opkód (0x1E) a 8 konstanst tolja a stack-re.
    /// <br />
    /// en: The ldc.i4.8 opcode (0x1E) pushes the constant 8 onto the stack.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_8_PushesEight()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1E };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(8, cpu.Peek(0));
        Assert.Equal(1, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.s opkód (0x1F) 8-bit-es immediate-et sign-extended
    /// int32-re. Pozitív érték: 0x7F → +127. A PC 2-vel nő (opkód + operand).
    /// <br />
    /// en: The ldc.i4.s opcode (0x1F) pushes an 8-bit immediate, sign-extended
    /// to int32. Positive value: 0x7F → +127. PC advances by 2 (opcode + operand).
    /// </summary>
    [Fact]
    public void Execute_LdcI4_S_Positive_PushesValue()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1F, 0x7F }; // ldc.i4.s 127

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(127, cpu.Peek(0));
        Assert.Equal(2, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4.s opkód negatív 8-bit immediate-et sign-extended
    /// int32-re: 0xFF → -1, 0x80 → -128.
    /// <br />
    /// en: The ldc.i4.s opcode sign-extends a negative 8-bit immediate:
    /// 0xFF → -1, 0x80 → -128.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_S_Negative_PushesSignExtendedValue()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1F, 0xFF, 0x1F, 0x80 }; // ldc.i4.s -1; ldc.i4.s -128

        cpu.Execute(program);

        Assert.Equal(2, cpu.StackDepth);
        Assert.Equal(-128, cpu.Peek(0));
        Assert.Equal(-1, cpu.Peek(1));
        Assert.Equal(4, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4 opkód (0x20) 32-bit little-endian immediate-et tolja
    /// a stack-re. 0x12345678 little-endian: 0x78 0x56 0x34 0x12.
    /// A PC 5-tel nő (opkód + 4 byte operand).
    /// <br />
    /// en: The ldc.i4 opcode (0x20) pushes a 32-bit little-endian immediate.
    /// 0x12345678 little-endian: 0x78 0x56 0x34 0x12. PC advances by 5.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_Positive_PushesLittleEndianInt32()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x20, 0x78, 0x56, 0x34, 0x12 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x12345678, cpu.Peek(0));
        Assert.Equal(5, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4 negatív int32-t helyesen kezel: 0xFFFFFFFF → -1.
    /// <br />
    /// en: The ldc.i4 opcode correctly handles negative int32: 0xFFFFFFFF → -1.
    /// </summary>
    [Fact]
    public void Execute_LdcI4_Negative_PushesNegativeInt32()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x20, 0xFF, 0xFF, 0xFF, 0xFF };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(-1, cpu.Peek(0));
        Assert.Equal(5, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4 az int.MaxValue (0x7FFFFFFF) értéket helyesen
    /// rakja a stack-re.
    /// <br />
    /// en: The ldc.i4 opcode correctly pushes int.MaxValue (0x7FFFFFFF).
    /// </summary>
    [Fact]
    public void Execute_LdcI4_IntMax_Pushes2147483647()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x20, 0xFF, 0xFF, 0xFF, 0x7F };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(int.MaxValue, cpu.Peek(0));
        Assert.Equal(5, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Az ldc.i4 az int.MinValue (0x80000000) értéket helyesen
    /// rakja a stack-re.
    /// <br />
    /// en: The ldc.i4 opcode correctly pushes int.MinValue (0x80000000).
    /// </summary>
    [Fact]
    public void Execute_LdcI4_IntMin_PushesMinus2147483648()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x20, 0x00, 0x00, 0x00, 0x80 };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(int.MinValue, cpu.Peek(0));
        Assert.Equal(5, cpu.ProgramCounter);
    }

    /// <summary>
    /// hu: Ha a stack eléri a 64 slot maximumot és még egy push jön,
    /// a CPU TTrapException-t dob STACK_OVERFLOW okkal. 65 darab ldc.i4.0:
    /// az első 64 sikerül, a 65. trap-el a PC=64 pozíción.
    /// <br />
    /// en: When the stack reaches its 64-slot maximum and another push arrives,
    /// the CPU throws a TTrapException with StackOverflow reason. 65 ldc.i4.0:
    /// the first 64 succeed, the 65th traps at PC=64.
    /// </summary>
    [Fact]
    public void Execute_StackOverflow_ThrowsTrapException()
    {
        var cpu = new TCpu();
        var program = new byte[65];

        for (var i = 0; i < 65; i++)
            program[i] = 0x16; // ldc.i4.0

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
        Assert.Equal(64, trap.ProgramCounter);
        Assert.Equal(64, cpu.StackDepth);
    }

    /// <summary>
    /// hu: Integrációs teszt: az összes egybyte-os konstans opkód együtt
    /// a helyes sorrendben tolja az értékeket a stack-re. Sorrend:
    /// m1, 0, 1, 2, 3, 4, 5, 6, 7, 8, ldnull. 11 érték, stack mélység 11.
    /// <br />
    /// en: Integration test: all single-byte constant opcodes together push
    /// values onto the stack in the correct order. Sequence:
    /// m1, 0, 1, 2, 3, 4, 5, 6, 7, 8, ldnull. 11 values, stack depth 11.
    /// </summary>
    [Fact]
    public void Execute_AllSingleByteConstants_PushAllInOrder()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x15, // ldc.i4.m1  → -1
            0x16, // ldc.i4.0   → 0
            0x17, // ldc.i4.1   → 1
            0x18, // ldc.i4.2   → 2
            0x19, // ldc.i4.3   → 3
            0x1A, // ldc.i4.4   → 4
            0x1B, // ldc.i4.5   → 5
            0x1C, // ldc.i4.6   → 6
            0x1D, // ldc.i4.7   → 7
            0x1E, // ldc.i4.8   → 8
            0x14  // ldnull     → 0
        };

        cpu.Execute(program);

        Assert.Equal(11, cpu.StackDepth);
        Assert.Equal(11, cpu.ProgramCounter);

        // hu: TOS = ldnull eredménye (0)
        // en: TOS = result of ldnull (0)
        Assert.Equal(0, cpu.Peek(0));

        // hu: Ellenőrizzük a teljes sorrendet (fentről lefelé).
        // en: Verify the entire order (top-down).
        Assert.Equal(8, cpu.Peek(1));
        Assert.Equal(7, cpu.Peek(2));
        Assert.Equal(6, cpu.Peek(3));
        Assert.Equal(5, cpu.Peek(4));
        Assert.Equal(4, cpu.Peek(5));
        Assert.Equal(3, cpu.Peek(6));
        Assert.Equal(2, cpu.Peek(7));
        Assert.Equal(1, cpu.Peek(8));
        Assert.Equal(0, cpu.Peek(9));
        Assert.Equal(-1, cpu.Peek(10));
    }

    /// <summary>
    /// hu: Ismeretlen opkód (0xFF, nincs a CIL-T0 spec táblájában) hatására
    /// a CPU TTrapException-t dob InvalidOpcode okkal, és a PC a hibás byte
    /// offszetjén marad. Ez a Devil's Advocate review alapján az iter.1-ben
    /// bevezetett default ág (InvalidOperationException → TTrapException
    /// refaktor) tesztlefedettségét biztosítja.
    /// <br />
    /// en: Unknown opcode (0xFF, not in the CIL-T0 spec table) causes the CPU
    /// to throw a TTrapException with InvalidOpcode reason, leaving the PC
    /// at the offending byte's offset. Per the Devil's Advocate review, this
    /// test covers the iter.1 default-branch refactor (InvalidOperationException
    /// → TTrapException).
    /// </summary>
    [Fact]
    public void Execute_UnknownOpcode_ThrowsInvalidOpcodeTrap()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0xFF };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: Egy érvényes opkód után egy ismeretlen opkód — a PC a második
    /// (hibás) byte offszetjén van a trap pillanatában.
    /// <br />
    /// en: An unknown opcode after a valid one — the PC is at the second
    /// (offending) byte's offset when the trap occurs.
    /// </summary>
    [Fact]
    public void Execute_UnknownOpcodeAfterValid_TrapProgramCounterPointsToOffender()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x16, 0xFE }; // ldc.i4.0; (ismeretlen 0xFE prefix operand nélkül)

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(1, trap.ProgramCounter);
        Assert.Equal(1, cpu.StackDepth); // ldc.i4.0 lefutott a trap előtt
    }

    /// <summary>
    /// hu: Iter. 3-ban aktivált teszt: a truncated operand (ldc.i4.s az
    /// utolsó byte, operand nélkül) <see cref="TTrapException"/>-t dob
    /// <see cref="TTrapReason.InvalidOpcode"/> okkal, és a PC a hibás
    /// opkód byte offszetjén marad.
    /// <br />
    /// en: Iter. 3 activated test: a truncated operand (ldc.i4.s as the
    /// last byte, without its operand) raises a <see cref="TTrapException"/>
    /// with <see cref="TTrapReason.InvalidOpcode"/>, and the PC remains at
    /// the offending opcode byte's offset.
    /// </summary>
    [Fact]
    public void Execute_TruncatedLdcI4_S_ThrowsInvalidOpcodeTrap()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1F }; // ldc.i4.s, operand hiányzik

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: Iter. 3-ban aktivált teszt: a truncated ldc.i4 operand (4 byte-ból
    /// kevesebb maradt) <see cref="TTrapReason.InvalidOpcode"/> trap-et dob.
    /// <br />
    /// en: Iter. 3 activated test: truncated ldc.i4 operand (fewer than 4
    /// bytes remaining) raises a <see cref="TTrapReason.InvalidOpcode"/>
    /// trap.
    /// </summary>
    [Fact]
    public void Execute_TruncatedLdcI4_ThrowsInvalidOpcodeTrap()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x20, 0x78, 0x56 }; // ldc.i4, 3 byte operand (4 helyett)

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: <c>Peek</c> hívás új <see cref="TCpu"/> példányon (még
    /// <c>Execute</c> hívás nélkül) <see cref="InvalidOperationException"/>-t
    /// dob, mert a call stack üres és nincs aktív frame.
    /// <br />
    /// en: Calling <c>Peek</c> on a fresh <see cref="TCpu"/> instance
    /// (before any <c>Execute</c>) throws
    /// <see cref="InvalidOperationException"/> because the call stack is
    /// empty and there is no active frame.
    /// </summary>
    [Fact]
    public void Peek_OnFreshCpu_ThrowsInvalidOperationException()
    {
        var cpu = new TCpu();

        var ex = Assert.Throws<InvalidOperationException>(() => cpu.Peek(0));

        Assert.Contains("call stack is empty", ex.Message);
    }
}
