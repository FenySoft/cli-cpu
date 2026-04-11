namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCallStack osztály unit tesztjei. A call stack a CIL-T0 hívási
/// láncot reprezentálja: minden hívásnál egy új <see cref="TFrame"/> kerül
/// a tetejére, ret-nél lekerül. A maximális mélység a CIL-T0 spec szerint
/// 512.
/// <br />
/// en: Unit tests for the TCallStack class. The call stack represents the
/// CIL-T0 call chain: each call pushes a new <see cref="TFrame"/> on top,
/// each ret pops one. The maximum depth per the CIL-T0 spec is 512.
/// </summary>
public class TCallStackTests
{
    /// <summary>
    /// hu: Új call stack üres — Depth == 0.
    /// <br />
    /// en: A new call stack is empty — Depth == 0.
    /// </summary>
    [Fact]
    public void Constructor_CreatesEmptyStack_DepthIsZero()
    {
        var stack = new TCallStack();

        Assert.Equal(0, stack.Depth);
    }

    /// <summary>
    /// hu: Egy frame push után Depth == 1, Top == frame.
    /// <br />
    /// en: After pushing one frame, Depth == 1 and Top == frame.
    /// </summary>
    [Fact]
    public void Push_OneFrame_DepthIsOne_TopIsFrame()
    {
        var stack = new TCallStack();
        var frame = new TFrame(2, 3);

        stack.Push(frame, 0);

        Assert.Equal(1, stack.Depth);
        Assert.Same(frame, stack.Top);
    }

    /// <summary>
    /// hu: Push, majd Pop ugyanazt a frame-et adja vissza, Depth visszamegy 0-ra.
    /// <br />
    /// en: Push then Pop returns the same frame; Depth goes back to 0.
    /// </summary>
    [Fact]
    public void PushPop_RoundTrip_ReturnsSameFrame()
    {
        var stack = new TCallStack();
        var frame = new TFrame(0, 0);
        stack.Push(frame, 0);

        var popped = stack.Pop();

        Assert.Same(frame, popped);
        Assert.Equal(0, stack.Depth);
    }

    /// <summary>
    /// hu: 512 frame push-olása sikeres — ez a maximális mélység.
    /// <br />
    /// en: Pushing 512 frames succeeds — this is the maximum depth.
    /// </summary>
    [Fact]
    public void Push_UpToMaxDepth_Succeeds()
    {
        var stack = new TCallStack();

        for (var i = 0; i < TCallStack.MaxDepth; i++)
            stack.Push(new TFrame(0, 0), 0);

        Assert.Equal(TCallStack.MaxDepth, stack.Depth);
    }

    /// <summary>
    /// hu: A 513. push CallDepthExceeded trap-et dob a megadott PC-vel.
    /// <br />
    /// en: The 513th push raises a CallDepthExceeded trap with the given PC.
    /// </summary>
    [Fact]
    public void Push_BeyondMaxDepth_ThrowsCallDepthExceededTrap()
    {
        var stack = new TCallStack();

        for (var i = 0; i < TCallStack.MaxDepth; i++)
            stack.Push(new TFrame(0, 0), 0);

        var trap = Assert.Throws<TTrapException>(
            () => stack.Push(new TFrame(0, 0), 0xABCD));

        Assert.Equal(TTrapReason.CallDepthExceeded, trap.Reason);
        Assert.Equal(0xABCD, trap.ProgramCounter);
        Assert.Equal(TCallStack.MaxDepth, stack.Depth);
    }

    /// <summary>
    /// hu: Üres call stack-en a Top hozzáférés InvalidOperationException-t dob —
    /// ez programozói hiba, NEM CIL-T0 trap.
    /// <br />
    /// en: Accessing Top on an empty call stack throws InvalidOperationException —
    /// this is a programmer error, NOT a CIL-T0 trap.
    /// </summary>
    [Fact]
    public void Top_OnEmpty_ThrowsInvalidOperation()
    {
        var stack = new TCallStack();

        Assert.Throws<InvalidOperationException>(() => _ = stack.Top);
    }

    /// <summary>
    /// hu: Üres call stack-en a Pop InvalidOperationException-t dob —
    /// programozói hiba, NEM trap.
    /// <br />
    /// en: Pop on an empty call stack throws InvalidOperationException —
    /// programmer error, NOT a trap.
    /// </summary>
    [Fact]
    public void Pop_OnEmpty_ThrowsInvalidOperation()
    {
        var stack = new TCallStack();

        Assert.Throws<InvalidOperationException>(() => stack.Pop());
    }

    /// <summary>
    /// hu: Több push után a Top mindig a legutoljára push-olt frame.
    /// LIFO viselkedés.
    /// <br />
    /// en: After multiple pushes, Top is always the most recently pushed
    /// frame. LIFO behavior.
    /// </summary>
    [Fact]
    public void Push_Multiple_TopIsLatest()
    {
        var stack = new TCallStack();
        var f1 = new TFrame(1, 0);
        var f2 = new TFrame(2, 0);
        var f3 = new TFrame(3, 0);

        stack.Push(f1, 0);
        stack.Push(f2, 0);
        stack.Push(f3, 0);

        Assert.Same(f3, stack.Top);
        Assert.Equal(3, stack.Depth);

        stack.Pop();
        Assert.Same(f2, stack.Top);

        stack.Pop();
        Assert.Same(f1, stack.Top);
    }

    /// <summary>
    /// hu: Clear() metódus minden frame-et eltávolít, Depth 0.
    /// <br />
    /// en: Clear() removes all frames, Depth becomes 0.
    /// </summary>
    [Fact]
    public void Clear_RemovesAllFrames()
    {
        var stack = new TCallStack();
        stack.Push(new TFrame(0, 0), 0);
        stack.Push(new TFrame(0, 0), 0);

        stack.Clear();

        Assert.Equal(0, stack.Depth);
    }
}
