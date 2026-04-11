namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu iter. 3 összehasonlítás tesztjei: ceq, cgt, cgt.un, clt,
/// clt.un. Mind a 0xFE prefix-szel kódolt opkódok. A teszt-készlet
/// lefedi a takes/doesn't take ágakat, az unsigned/signed különbséget,
/// a stack underflow trapot, és az érvénytelen 0xFE prefix kombinációt.
/// <br />
/// en: TCpu iter. 3 comparison tests: ceq, cgt, cgt.un, clt, clt.un.
/// All are 0xFE-prefixed opcodes. The suite covers takes/doesn't-take
/// branches, signed/unsigned differences, stack underflow trap, and
/// invalid 0xFE prefix combinations.
/// </summary>
public class TCpuIter3ComparisonTests
{
    // ------------------------------------------------------------------
    // ceq (0xFE 0x01)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ceq egyenlő értékek → 1.
    /// <br />
    /// en: ceq equal values → 1.
    /// </summary>
    [Fact]
    public void Execute_Ceq_Equal_Returns1()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x1B, 0xFE, 0x01 }; // ldc.i4.5; ldc.i4.5; ceq

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ceq különböző értékek → 0.
    /// <br />
    /// en: ceq unequal values → 0.
    /// </summary>
    [Fact]
    public void Execute_Ceq_NotEqual_Returns0()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x1A, 0xFE, 0x01 }; // ldc.i4.5; ldc.i4.4; ceq

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // cgt (0xFE 0x02)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: cgt 5 &gt; 3 → 1.
    /// <br />
    /// en: cgt 5 &gt; 3 → 1.
    /// </summary>
    [Fact]
    public void Execute_Cgt_Greater_Returns1()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x19, 0xFE, 0x02 }; // ldc.i4.5; ldc.i4.3; cgt

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: cgt 3 &gt; 5 → 0.
    /// <br />
    /// en: cgt 3 &gt; 5 → 0.
    /// </summary>
    [Fact]
    public void Execute_Cgt_NotGreater_Returns0()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19, 0x1B, 0xFE, 0x02 }; // ldc.i4.3; ldc.i4.5; cgt

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    /// <summary>
    /// hu: cgt signed: -1 &gt; 1 → 0.
    /// <br />
    /// en: cgt signed: -1 &gt; 1 → 0.
    /// </summary>
    [Fact]
    public void Execute_Cgt_NegativeNotGreaterThanOne_Signed()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15, 0x17, 0xFE, 0x02 }; // ldc.i4.m1; ldc.i4.1; cgt

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // cgt.un (0xFE 0x03)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: cgt.un -1 &gt; 1 → 1 (mert -1 unsigned == 0xFFFFFFFF).
    /// <br />
    /// en: cgt.un -1 &gt; 1 → 1 (because -1 unsigned == 0xFFFFFFFF).
    /// </summary>
    [Fact]
    public void Execute_CgtUn_NegativeGreaterThanOne_UnsignedCompare()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15, 0x17, 0xFE, 0x03 }; // ldc.i4.m1; ldc.i4.1; cgt.un

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: cgt.un 1 &gt; 2 (unsigned) → 0.
    /// <br />
    /// en: cgt.un 1 &gt; 2 (unsigned) → 0.
    /// </summary>
    [Fact]
    public void Execute_CgtUn_OneNotGreaterThanTwo()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0x18, 0xFE, 0x03 }; // ldc.i4.1; ldc.i4.2; cgt.un

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // clt (0xFE 0x04)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: clt 3 &lt; 5 → 1.
    /// <br />
    /// en: clt 3 &lt; 5 → 1.
    /// </summary>
    [Fact]
    public void Execute_Clt_Less_Returns1()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19, 0x1B, 0xFE, 0x04 }; // ldc.i4.3; ldc.i4.5; clt

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: clt 5 &lt; 3 → 0.
    /// <br />
    /// en: clt 5 &lt; 3 → 0.
    /// </summary>
    [Fact]
    public void Execute_Clt_NotLess_Returns0()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x19, 0xFE, 0x04 }; // ldc.i4.5; ldc.i4.3; clt

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    /// <summary>
    /// hu: clt signed: -1 &lt; 1 → 1.
    /// <br />
    /// en: clt signed: -1 &lt; 1 → 1.
    /// </summary>
    [Fact]
    public void Execute_Clt_NegativeLessThanOne_Signed()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15, 0x17, 0xFE, 0x04 }; // ldc.i4.m1; ldc.i4.1; clt

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // clt.un (0xFE 0x05)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: clt.un -1 &lt; 1 → 0 (mert -1 unsigned == 0xFFFFFFFF, ami nagyobb).
    /// <br />
    /// en: clt.un -1 &lt; 1 → 0 (because -1 unsigned == 0xFFFFFFFF, which is larger).
    /// </summary>
    [Fact]
    public void Execute_CltUn_ForNegative_UnsignedCompare()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15, 0x17, 0xFE, 0x05 }; // ldc.i4.m1; ldc.i4.1; clt.un

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    /// <summary>
    /// hu: clt.un 1 &lt; 2 (unsigned) → 1.
    /// <br />
    /// en: clt.un 1 &lt; 2 (unsigned) → 1.
    /// </summary>
    [Fact]
    public void Execute_CltUn_OneLessThanTwo()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0x18, 0xFE, 0x05 }; // ldc.i4.1; ldc.i4.2; clt.un

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // Stack underflow tesztek (a 0xFE-prefixes opkódoknál is)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ceq üres stacken StackUnderflow trap.
    /// <br />
    /// en: ceq on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Ceq_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0xFE, 0x01 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: clt egyetlen elemmel a stacken StackUnderflow.
    /// <br />
    /// en: clt with one element on stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Clt_OneElement_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0xFE, 0x04 }; // ldc.i4.1; clt

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(1, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // Invalid prefix-byte kombináció
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A 0xFE 0xFF kombináció érvénytelen — a CIL-T0 nem definiálja —
    /// és <see cref="TTrapReason.InvalidOpcode"/> trap-et dob a 0xFE byte
    /// PC-jén.
    /// <br />
    /// en: The 0xFE 0xFF combination is invalid — CIL-T0 does not define it —
    /// and raises <see cref="TTrapReason.InvalidOpcode"/> at the 0xFE byte's
    /// PC.
    /// </summary>
    [Fact]
    public void Execute_InvalidPrefixByte_0xFE_0xFF_RaisesInvalidOpcode()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0xFE, 0xFF };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: Truncated 0xFE prefix — csak a prefix byte van, a következő
    /// byte hiányzik. <see cref="TTrapReason.InvalidOpcode"/> trap.
    /// <br />
    /// en: Truncated 0xFE prefix — only the prefix byte is present, the
    /// following byte is missing. <see cref="TTrapReason.InvalidOpcode"/>
    /// trap.
    /// </summary>
    [Fact]
    public void Execute_Truncated0xFEPrefix_RaisesInvalidOpcode()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0xFE };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidOpcode, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }
}
