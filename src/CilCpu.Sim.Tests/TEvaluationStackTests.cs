namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TEvaluationStack osztály unit tesztjei. Az evaluation stack a CIL-T0
/// szimulátor központi adatstruktúrája — külön osztályba emelve egyszerűbb
/// tesztelni és független a TCpu állapotgépétől.
/// <br />
/// en: Unit tests for the TEvaluationStack class. The evaluation stack is
/// the central data structure of the CIL-T0 simulator — extracted to a
/// separate class for easier testing, decoupled from the TCpu state machine.
/// </summary>
public class TEvaluationStackTests
{
    /// <summary>
    /// hu: Új stack létrehozáskor a mélység pontosan 0.
    /// <br />
    /// en: A freshly constructed stack has depth exactly 0.
    /// </summary>
    [Fact]
    public void Constructor_CreatesEmptyStack_DepthIsZero()
    {
        var stack = new TEvaluationStack();

        Assert.Equal(0, stack.Depth);
    }

    /// <summary>
    /// hu: Egy érték push-olása után a mélység 1, és a Peek(0) a push-olt
    /// értéket adja vissza.
    /// <br />
    /// en: After pushing one value, depth is 1 and Peek(0) returns the
    /// pushed value.
    /// </summary>
    [Fact]
    public void Push_OneValue_DepthIsOne_AndPeekReturnsValue()
    {
        var stack = new TEvaluationStack();

        stack.Push(42, 0);

        Assert.Equal(1, stack.Depth);
        Assert.Equal(42, stack.Peek(0));
    }

    /// <summary>
    /// hu: Ha a stack eléri a MaxDepth-et (64), a következő Push
    /// TTrapException-t dob StackOverflow okkal, és a megadott PC értékkel.
    /// <br />
    /// en: When the stack reaches MaxDepth (64), the next Push throws a
    /// TTrapException with StackOverflow reason and the given PC value.
    /// </summary>
    [Fact]
    public void Push_AtMaxDepth_ThrowsStackOverflowTrap()
    {
        var stack = new TEvaluationStack();

        for (var i = 0; i < TEvaluationStack.MaxDepth; i++)
            stack.Push(i, 0);

        var trap = Assert.Throws<TTrapException>(() => stack.Push(999, 0x1234));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
        Assert.Equal(0x1234, trap.ProgramCounter);
        Assert.Equal(TEvaluationStack.MaxDepth, stack.Depth);
    }

    /// <summary>
    /// hu: Egy érték push-olása után a Pop ugyanazt az értéket adja vissza,
    /// és a mélység 0-ra csökken.
    /// <br />
    /// en: After pushing one value, Pop returns the same value and depth
    /// drops back to 0.
    /// </summary>
    [Fact]
    public void Pop_OneValue_ReturnsValue_AndDepthIsZero()
    {
        var stack = new TEvaluationStack();
        stack.Push(77, 0);

        var value = stack.Pop(0);

        Assert.Equal(77, value);
        Assert.Equal(0, stack.Depth);
    }

    /// <summary>
    /// hu: Üres stackről Pop-olás TTrapException-t dob StackUnderflow okkal,
    /// a megadott PC értékkel.
    /// <br />
    /// en: Popping from an empty stack throws TTrapException with
    /// StackUnderflow reason and the given PC value.
    /// </summary>
    [Fact]
    public void Pop_FromEmpty_ThrowsStackUnderflowTrap()
    {
        var stack = new TEvaluationStack();

        var trap = Assert.Throws<TTrapException>(() => stack.Pop(0x5678));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0x5678, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: Peek különböző offszeteken a megfelelő stack elemeket adja vissza.
    /// Peek(0) = TOS, Peek(1) = TOS-1, stb.
    /// <br />
    /// en: Peek at different offsets returns the corresponding stack elements.
    /// Peek(0) = TOS, Peek(1) = TOS-1, etc.
    /// </summary>
    [Fact]
    public void Peek_ValidOffset_ReturnsValue()
    {
        var stack = new TEvaluationStack();
        stack.Push(10, 0);
        stack.Push(20, 0);
        stack.Push(30, 0);

        Assert.Equal(30, stack.Peek(0));
        Assert.Equal(20, stack.Peek(1));
        Assert.Equal(10, stack.Peek(2));
    }

    /// <summary>
    /// hu: Peek érvénytelen offszeten ArgumentOutOfRangeException-t dob
    /// (debug API, NEM trap).
    /// <br />
    /// en: Peek with an invalid offset throws ArgumentOutOfRangeException
    /// (debug API, NOT a trap).
    /// </summary>
    [Fact]
    public void Peek_InvalidOffset_ThrowsArgumentOutOfRange()
    {
        var stack = new TEvaluationStack();
        stack.Push(1, 0);

        Assert.Throws<ArgumentOutOfRangeException>(() => stack.Peek(-1));
        Assert.Throws<ArgumentOutOfRangeException>(() => stack.Peek(1));
        Assert.Throws<ArgumentOutOfRangeException>(() => stack.Peek(100));
    }

    /// <summary>
    /// hu: Dup egy nem üres stacken a TOS-t duplikálja — a mélység +1,
    /// és Peek(0) == Peek(1) == eredeti TOS.
    /// <br />
    /// en: Dup on a non-empty stack duplicates TOS — depth grows by 1,
    /// and Peek(0) == Peek(1) == original TOS.
    /// </summary>
    [Fact]
    public void Dup_NonEmpty_DuplicatesTos()
    {
        var stack = new TEvaluationStack();
        stack.Push(99, 0);

        stack.Dup(0);

        Assert.Equal(2, stack.Depth);
        Assert.Equal(99, stack.Peek(0));
        Assert.Equal(99, stack.Peek(1));
    }

    /// <summary>
    /// hu: Dup egy üres stacken StackUnderflow trap-et dob (nincs mit
    /// duplikálni).
    /// <br />
    /// en: Dup on an empty stack throws a StackUnderflow trap (nothing
    /// to duplicate).
    /// </summary>
    [Fact]
    public void Dup_FromEmpty_ThrowsStackUnderflowTrap()
    {
        var stack = new TEvaluationStack();

        var trap = Assert.Throws<TTrapException>(() => stack.Dup(0x42));

        Assert.Equal(TTrapReason.StackUnderflow, trap.Reason);
        Assert.Equal(0x42, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: Dup a max mélységen StackOverflow trap-et dob (a TOS duplikátuma
    /// nem fér el).
    /// <br />
    /// en: Dup at max depth throws a StackOverflow trap (the duplicate
    /// doesn't fit).
    /// </summary>
    [Fact]
    public void Dup_AtMaxDepth_ThrowsStackOverflowTrap()
    {
        var stack = new TEvaluationStack();

        for (var i = 0; i < TEvaluationStack.MaxDepth; i++)
            stack.Push(i, 0);

        var trap = Assert.Throws<TTrapException>(() => stack.Dup(0x99));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
        Assert.Equal(0x99, trap.ProgramCounter);
        Assert.Equal(TEvaluationStack.MaxDepth, stack.Depth);
    }
}
