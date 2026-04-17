namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu iter. 3 aritmetika tesztjei: add, sub, mul, div, rem, neg,
/// not, and, or, xor, shl, shr, shr.un. A teszt-készlet lefedi a happy
/// path-okat, a határértékeket (wrap, int.MinValue, stb.), a trap ágakat
/// (StackUnderflow, DivByZero, Overflow) és a shift maszkolási szabályt.
/// <br />
/// en: TCpu iter. 3 arithmetic tests: add, sub, mul, div, rem, neg, not,
/// and, or, xor, shl, shr, shr.un. The suite covers happy paths, edge
/// cases (wrap, int.MinValue, etc.), trap branches (StackUnderflow,
/// DivByZero, Overflow) and the shift masking rule.
/// </summary>
public class TCpuIter3ArithmeticTests
{
    // ------------------------------------------------------------------
    // add (0x58)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: add két pozitív számot: 3 + 4 = 7.
    /// <br />
    /// en: add two positive numbers: 3 + 4 = 7.
    /// </summary>
    [Fact]
    public void Execute_Add_TwoPositives_Sum()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x19, 0x1A, 0x58 }; // ldc.i4.3; ldc.i4.4; add

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(7, cpu.Peek(0));
    }

    /// <summary>
    /// hu: add int.MaxValue + 1 wrap-el int.MinValue-re.
    /// <br />
    /// en: add int.MaxValue + 1 wraps to int.MinValue.
    /// </summary>
    [Fact]
    public void Execute_Add_IntMaxPlusOne_WrapsToIntMin()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x17,                         // ldc.i4.1
            0x58                          // add
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: add üres stacken StackUnderflow trap.
    /// <br />
    /// en: add on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Add_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x58 }; // add

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: add egyetlen elemmel a stacken is StackUnderflow.
    /// <br />
    /// en: add with only one element on stack also raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Add_OneElement_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0x58 }; // ldc.i4.1; add

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(1, trap.ProgramCounter);
    }

    // ------------------------------------------------------------------
    // sub (0x59)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: sub: 10 - 3 = 7.
    /// <br />
    /// en: sub: 10 - 3 = 7.
    /// </summary>
    [Fact]
    public void Execute_Sub_PositiveMinusPositive()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x0A, // ldc.i4.s 10
            0x19,       // ldc.i4.3
            0x59        // sub
        };

        cpu.Execute(program);

        Assert.Equal(7, cpu.Peek(0));
    }

    /// <summary>
    /// hu: sub pozitív - negatív: 5 - (-3) = 8.
    /// <br />
    /// en: sub positive minus negative: 5 - (-3) = 8.
    /// </summary>
    [Fact]
    public void Execute_Sub_PositiveMinusNegative()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B,       // ldc.i4.5
            0x1F, 0xFD, // ldc.i4.s -3
            0x59        // sub
        };

        cpu.Execute(program);

        Assert.Equal(8, cpu.Peek(0));
    }

    /// <summary>
    /// hu: sub int.MinValue - 1 wrap-el int.MaxValue-re.
    /// <br />
    /// en: sub int.MinValue - 1 wraps to int.MaxValue.
    /// </summary>
    [Fact]
    public void Execute_Sub_IntMinMinusOne_WrapsToIntMax()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x17,                         // ldc.i4.1
            0x59                          // sub
        };

        cpu.Execute(program);

        Assert.Equal(int.MaxValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: sub üres stacken StackUnderflow trap.
    /// <br />
    /// en: sub on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Sub_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x59 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // mul (0x5A)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: mul: 6 * 7 = 42.
    /// <br />
    /// en: mul: 6 * 7 = 42.
    /// </summary>
    [Fact]
    public void Execute_Mul_TwoPositives()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1C, 0x1D, 0x5A }; // ldc.i4.6; ldc.i4.7; mul

        cpu.Execute(program);

        Assert.Equal(42, cpu.Peek(0));
    }

    /// <summary>
    /// hu: mul int.MinValue * -1 wrap-el int.MinValue-re (overflow trap NINCS, csak div-nél).
    /// <br />
    /// en: mul int.MinValue * -1 wraps to int.MinValue (no overflow trap here, only for div).
    /// </summary>
    [Fact]
    public void Execute_Mul_IntMinByMinusOne_Wraps()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x15,                         // ldc.i4.m1
            0x5A                          // mul
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: mul negatív eredmény: 3 * -4 = -12.
    /// <br />
    /// en: mul negative result: 3 * -4 = -12.
    /// </summary>
    [Fact]
    public void Execute_Mul_NegativeResult()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x19,       // ldc.i4.3
            0x1F, 0xFC, // ldc.i4.s -4
            0x5A        // mul
        };

        cpu.Execute(program);

        Assert.Equal(-12, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // div (0x5B)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: div: 20 / 4 = 5.
    /// <br />
    /// en: div: 20 / 4 = 5.
    /// </summary>
    [Fact]
    public void Execute_Div_Positive()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x14, // ldc.i4.s 20
            0x1A,       // ldc.i4.4
            0x5B        // div
        };

        cpu.Execute(program);

        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: div negatív eredmény: -12 / 4 = -3.
    /// <br />
    /// en: div negative result: -12 / 4 = -3.
    /// </summary>
    [Fact]
    public void Execute_Div_NegativeResult()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0xF4, // ldc.i4.s -12
            0x1A,       // ldc.i4.4
            0x5B        // div
        };

        cpu.Execute(program);

        Assert.Equal(-3, cpu.Peek(0));
    }

    /// <summary>
    /// hu: div by zero → DivByZero trap.
    /// <br />
    /// en: div by zero → DivByZero trap.
    /// </summary>
    [Fact]
    public void Execute_Div_ByZero_RaisesDivByZero()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1A,       // ldc.i4.4
            0x16,       // ldc.i4.0
            0x5B        // div
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.DivByZero, trap.Reason);
        Assert.Equal(2, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: div int.MinValue / -1 → Overflow trap.
    /// <br />
    /// en: div int.MinValue / -1 → Overflow trap.
    /// </summary>
    [Fact]
    public void Execute_Div_IntMinByMinusOne_RaisesOverflow()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x15,                         // ldc.i4.m1
            0x5B                          // div
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.Overflow, trap.Reason);
        Assert.Equal(6, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: div stack underflow üres stacken.
    /// <br />
    /// en: div stack underflow on empty stack.
    /// </summary>
    [Fact]
    public void Execute_Div_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x5B };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // rem (0x5D)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: rem: 17 % 5 = 2.
    /// <br />
    /// en: rem: 17 % 5 = 2.
    /// </summary>
    [Fact]
    public void Execute_Rem_Positive()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x11, // ldc.i4.s 17
            0x1B,       // ldc.i4.5
            0x5D        // rem
        };

        cpu.Execute(program);

        Assert.Equal(2, cpu.Peek(0));
    }

    /// <summary>
    /// hu: rem by zero → DivByZero trap.
    /// <br />
    /// en: rem by zero → DivByZero trap.
    /// </summary>
    [Fact]
    public void Execute_Rem_ByZero_RaisesDivByZero()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1B,       // ldc.i4.5
            0x16,       // ldc.i4.0
            0x5D        // rem
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.DivByZero, trap.Reason);
    }

    /// <summary>
    /// hu: rem int.MinValue % -1 → 0 (NEM overflow, spec szerint).
    /// <br />
    /// en: rem int.MinValue % -1 → 0 (NOT overflow per spec).
    /// </summary>
    [Fact]
    public void Execute_Rem_IntMinByMinusOne_ReturnsZero()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x15,                         // ldc.i4.m1
            0x5D                          // rem
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // neg (0x65)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: neg pozitív: -5.
    /// <br />
    /// en: neg positive: -5.
    /// </summary>
    [Fact]
    public void Execute_Neg_Positive()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x65 }; // ldc.i4.5; neg

        cpu.Execute(program);

        Assert.Equal(-5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: neg negatív: --5 = 5.
    /// <br />
    /// en: neg negative: --5 = 5.
    /// </summary>
    [Fact]
    public void Execute_Neg_Negative()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1F, 0xFB, 0x65 }; // ldc.i4.s -5; neg

        cpu.Execute(program);

        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: neg int.MinValue → int.MinValue (wraps, no overflow trap).
    /// <br />
    /// en: neg int.MinValue → int.MinValue (wraps, no overflow trap).
    /// </summary>
    [Fact]
    public void Execute_Neg_IntMin_WrapsToIntMin()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x65                          // neg
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: neg üres stacken StackUnderflow.
    /// <br />
    /// en: neg on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_Neg_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x65 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // not (0x66)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: not 0 = -1.
    /// <br />
    /// en: not 0 = -1.
    /// </summary>
    [Fact]
    public void Execute_Not_Zero_ReturnsMinusOne()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x16, 0x66 }; // ldc.i4.0; not

        cpu.Execute(program);

        Assert.Equal(-1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: not -1 = 0.
    /// <br />
    /// en: not -1 = 0.
    /// </summary>
    [Fact]
    public void Execute_Not_NegativeOne_ReturnsZero()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x15, 0x66 }; // ldc.i4.m1; not

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // and (0x5F), or (0x60), xor (0x61)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: and 0x0F &amp; 0x08 = 0x08.
    /// <br />
    /// en: and 0x0F &amp; 0x08 = 0x08.
    /// </summary>
    [Fact]
    public void Execute_And_Bitwise()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x0F, // ldc.i4.s 0x0F
            0x1E,       // ldc.i4.8 (0x08)
            0x5F        // and
        };

        cpu.Execute(program);

        Assert.Equal(0x08, cpu.Peek(0));
    }

    /// <summary>
    /// hu: or 0x05 | 0x08 = 0x0D.
    /// <br />
    /// en: or 0x05 | 0x08 = 0x0D.
    /// </summary>
    [Fact]
    public void Execute_Or_Bitwise()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x1B, 0x1E, 0x60 }; // ldc.i4.5; ldc.i4.8; or

        cpu.Execute(program);

        Assert.Equal(0x0D, cpu.Peek(0));
    }

    /// <summary>
    /// hu: xor 0x0F ^ 0x05 = 0x0A.
    /// <br />
    /// en: xor 0x0F ^ 0x05 = 0x0A.
    /// </summary>
    [Fact]
    public void Execute_Xor_Bitwise()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x0F, // ldc.i4.s 15
            0x1B,       // ldc.i4.5
            0x61        // xor
        };

        cpu.Execute(program);

        Assert.Equal(0x0A, cpu.Peek(0));
    }

    /// <summary>
    /// hu: and üres stacken StackUnderflow.
    /// <br />
    /// en: and on empty stack raises StackUnderflow.
    /// </summary>
    [Fact]
    public void Execute_And_EmptyStack_StackUnderflow()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x5F };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // shl (0x62), shr (0x63), shr.un (0x64)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: shl 1 &lt;&lt; 4 = 16.
    /// <br />
    /// en: shl 1 &lt;&lt; 4 = 16.
    /// </summary>
    [Fact]
    public void Execute_Shl_OneByFour()
    {
        var cpu = new TCpu();
        var program = new byte[] { 0x17, 0x1A, 0x62 }; // ldc.i4.1; ldc.i4.4; shl

        cpu.Execute(program);

        Assert.Equal(16, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shl shift amount maszkolás: 1 &lt;&lt; 33 == 1 &lt;&lt; (33 &amp; 31) == 1 &lt;&lt; 1 == 2.
    /// <br />
    /// en: shl shift amount masking: 1 &lt;&lt; 33 == 1 &lt;&lt; (33 &amp; 31) == 1 &lt;&lt; 1 == 2.
    /// </summary>
    [Fact]
    public void Execute_Shl_MaskAmountTo31()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,       // ldc.i4.1
            0x1F, 0x21, // ldc.i4.s 33
            0x62        // shl
        };

        cpu.Execute(program);

        Assert.Equal(2, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr arithmetic negatív: -8 &gt;&gt; 1 == -4 (sign extend).
    /// <br />
    /// en: shr arithmetic negative: -8 &gt;&gt; 1 == -4 (sign extend).
    /// </summary>
    [Fact]
    public void Execute_Shr_NegativeValue_SignExtends()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0xF8, // ldc.i4.s -8
            0x17,       // ldc.i4.1
            0x63        // shr
        };

        cpu.Execute(program);

        Assert.Equal(-4, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr.un negatív szám logikai jobbra shift-je: -1 &gt;&gt;u 1 == 0x7FFFFFFF.
    /// <br />
    /// en: shr.un logical right shift of a negative value: -1 &gt;&gt;u 1 == 0x7FFFFFFF.
    /// </summary>
    [Fact]
    public void Execute_ShrUn_NegativeValue_ZeroExtends()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x15,       // ldc.i4.m1
            0x17,       // ldc.i4.1
            0x64        // shr.un
        };

        cpu.Execute(program);

        Assert.Equal(0x7FFFFFFF, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr arithmetic pozitív: 16 &gt;&gt; 2 == 4.
    /// <br />
    /// en: shr arithmetic positive: 16 &gt;&gt; 2 == 4.
    /// </summary>
    [Fact]
    public void Execute_Shr_Positive()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x10, // ldc.i4.s 16
            0x18,       // ldc.i4.2
            0x63        // shr
        };

        cpu.Execute(program);

        Assert.Equal(4, cpu.Peek(0));
    }

    // ==================================================================
    // Boundary value tests — Integer Arithmetic
    // ==================================================================

    /// <summary>
    /// hu: add INT_MAX + INT_MAX = -2 (0xFFFFFFFE), túlcsordulás wrap.
    /// <br />
    /// en: add INT_MAX + INT_MAX = -2 (0xFFFFFFFE), overflow wraps.
    /// </summary>
    [Fact]
    public void Execute_Add_IntMaxPlusIntMax_Wraps()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x58                           // add
        };

        cpu.Execute(program);

        Assert.Equal(-2, cpu.Peek(0));
    }

    /// <summary>
    /// hu: sub 0 - INT_MIN = INT_MIN (wrap, mert -INT_MIN nem ábrázolható).
    /// <br />
    /// en: sub 0 - INT_MIN = INT_MIN (wraps, because -INT_MIN is not representable).
    /// </summary>
    [Fact]
    public void Execute_Sub_ZeroMinusIntMin_Wraps()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x16,                         // ldc.i4.0
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x59                           // sub
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: mul INT_MAX * 2 = -2 (túlcsordulás wrap).
    /// <br />
    /// en: mul INT_MAX * 2 = -2 (overflow wraps).
    /// </summary>
    [Fact]
    public void Execute_Mul_IntMaxTimesTwo_Wraps()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x18,                         // ldc.i4.2
            0x5A                          // mul
        };

        cpu.Execute(program);

        Assert.Equal(-2, cpu.Peek(0));
    }

    /// <summary>
    /// hu: div INT_MIN / 1 = INT_MIN (nincs overflow, az osztó 1).
    /// <br />
    /// en: div INT_MIN / 1 = INT_MIN (no overflow, divisor is 1).
    /// </summary>
    [Fact]
    public void Execute_Div_IntMinByOne_ReturnsIntMin()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x17,                         // ldc.i4.1
            0x5B                          // div
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: div INT_MIN / INT_MIN = 1.
    /// <br />
    /// en: div INT_MIN / INT_MIN = 1.
    /// </summary>
    [Fact]
    public void Execute_Div_IntMinByIntMin_ReturnsOne()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x5B                           // div
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: div 1 / INT_MAX = 0 (egész osztás, csonkolás).
    /// <br />
    /// en: div 1 / INT_MAX = 0 (integer division, truncation).
    /// </summary>
    [Fact]
    public void Execute_Div_OneByIntMax_ReturnsZero()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,                         // ldc.i4.1
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x5B                          // div
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    /// <summary>
    /// hu: rem INT_MIN % 1 = 0.
    /// <br />
    /// en: rem INT_MIN % 1 = 0.
    /// </summary>
    [Fact]
    public void Execute_Rem_IntMinByOne_ReturnsZero()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x17,                         // ldc.i4.1
            0x5D                          // rem
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.Peek(0));
    }

    /// <summary>
    /// hu: rem 1 % INT_MAX = 1.
    /// <br />
    /// en: rem 1 % INT_MAX = 1.
    /// </summary>
    [Fact]
    public void Execute_Rem_OneByIntMax_ReturnsOne()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,                         // ldc.i4.1
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x5D                          // rem
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: neg INT_MAX = -2147483647 (-INT_MAX).
    /// <br />
    /// en: neg INT_MAX = -2147483647 (-INT_MAX).
    /// </summary>
    [Fact]
    public void Execute_Neg_IntMax_ReturnsMinIntMaxPlus1()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x65                          // neg
        };

        cpu.Execute(program);

        Assert.Equal(-2147483647, cpu.Peek(0));
    }

    /// <summary>
    /// hu: not INT_MAX = INT_MIN (~0x7FFFFFFF = 0x80000000 = -2147483648).
    /// <br />
    /// en: not INT_MAX = INT_MIN (~0x7FFFFFFF = 0x80000000 = -2147483648).
    /// </summary>
    [Fact]
    public void Execute_Not_IntMax_ReturnsIntMin()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0xFF, 0xFF, 0xFF, 0x7F, // ldc.i4 int.MaxValue
            0x66                          // not
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: not INT_MIN = INT_MAX (~0x80000000 = 0x7FFFFFFF = 2147483647).
    /// <br />
    /// en: not INT_MIN = INT_MAX (~0x80000000 = 0x7FFFFFFF = 2147483647).
    /// </summary>
    [Fact]
    public void Execute_Not_IntMin_ReturnsIntMax()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x66                          // not
        };

        cpu.Execute(program);

        Assert.Equal(int.MaxValue, cpu.Peek(0));
    }

    // ==================================================================
    // Boundary value tests — Shifts
    // ==================================================================

    /// <summary>
    /// hu: shl 0-val eltolás: 42 &lt;&lt; 0 = 42 (identitás).
    /// <br />
    /// en: shl by zero: 42 &lt;&lt; 0 = 42 (identity).
    /// </summary>
    [Fact]
    public void Execute_Shl_ByZero_Identity()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0x2A, // ldc.i4.s 42
            0x16,       // ldc.i4.0
            0x62        // shl
        };

        cpu.Execute(program);

        Assert.Equal(42, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shl 1 &lt;&lt; 31 = INT_MIN (-2147483648), csak a sign bit marad.
    /// <br />
    /// en: shl 1 &lt;&lt; 31 = INT_MIN (-2147483648), only sign bit remains.
    /// </summary>
    [Fact]
    public void Execute_Shl_By31_OnlySignBit()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,       // ldc.i4.1
            0x1F, 0x1F, // ldc.i4.s 31
            0x62        // shl
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shl 1 &lt;&lt; 32 = 1 (32 &amp; 31 = 0, tehát identitás).
    /// <br />
    /// en: shl 1 &lt;&lt; 32 = 1 (32 &amp; 31 = 0, so identity).
    /// </summary>
    [Fact]
    public void Execute_Shl_By32_MasksToZero_Identity()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17,       // ldc.i4.1
            0x1F, 0x20, // ldc.i4.s 32
            0x62        // shl
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr INT_MIN &gt;&gt; 31 = -1 (aritmetikai, sign extend).
    /// <br />
    /// en: shr INT_MIN &gt;&gt; 31 = -1 (arithmetic, sign extend).
    /// </summary>
    [Fact]
    public void Execute_Shr_By31_NegativeBecomesMinusOne()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x1F, 0x1F,                   // ldc.i4.s 31
            0x63                          // shr
        };

        cpu.Execute(program);

        Assert.Equal(-1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr 0-val eltolás: -42 &gt;&gt; 0 = -42 (identitás).
    /// <br />
    /// en: shr by zero: -42 &gt;&gt; 0 = -42 (identity).
    /// </summary>
    [Fact]
    public void Execute_Shr_ByZero_Identity()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x1F, 0xD6, // ldc.i4.s -42
            0x16,       // ldc.i4.0
            0x63        // shr
        };

        cpu.Execute(program);

        Assert.Equal(-42, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr.un INT_MIN &gt;&gt;&gt; 31 = 1 (unsigned, zero extend).
    /// <br />
    /// en: shr.un INT_MIN &gt;&gt;&gt; 31 = 1 (unsigned, zero extend).
    /// </summary>
    [Fact]
    public void Execute_ShrUn_By31_ReturnsOne()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue
            0x1F, 0x1F,                   // ldc.i4.s 31
            0x64                          // shr.un
        };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shr.un 0x80000000 &gt;&gt;&gt; 0 = 0x80000000 (identitás, INT_MIN mint int).
    /// <br />
    /// en: shr.un 0x80000000 &gt;&gt;&gt; 0 = 0x80000000 (identity, INT_MIN as int).
    /// </summary>
    [Fact]
    public void Execute_ShrUn_ByZero_Identity()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x20, 0x00, 0x00, 0x00, 0x80, // ldc.i4 int.MinValue (0x80000000)
            0x16,                         // ldc.i4.0
            0x64                          // shr.un
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }

    /// <summary>
    /// hu: shl negatív eltolás: 1 &lt;&lt; -1 → 1 &lt;&lt; (-1 &amp; 31) = 1 &lt;&lt; 31 = INT_MIN.
    /// <br />
    /// en: shl negative amount: 1 &lt;&lt; -1 → 1 &lt;&lt; (-1 &amp; 31) = 1 &lt;&lt; 31 = INT_MIN.
    /// </summary>
    [Fact]
    public void Execute_Shl_NegativeAmount_MaskedTo31()
    {
        var cpu = new TCpu();
        var program = new byte[]
        {
            0x17, // ldc.i4.1
            0x15, // ldc.i4.m1
            0x62  // shl
        };

        cpu.Execute(program);

        Assert.Equal(int.MinValue, cpu.Peek(0));
    }
}
