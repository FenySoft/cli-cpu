namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 hívási verem (call stack). Minden bejegyzés egy
/// <see cref="TFrame"/>, amely a hívott metódus argumentumait, lokális
/// változóit és visszatérési PC-jét tartalmazza. A verem maximális
/// mélysége a CIL-T0 spec szerint 512; a 513. push
/// <see cref="TTrapReason.CallDepthExceeded"/> trap-et dob.
/// <br />
/// en: CIL-T0 call stack. Each entry is a <see cref="TFrame"/> holding the
/// callee's arguments, locals and return PC. Per the CIL-T0 spec the
/// maximum depth is 512; the 513th push raises a
/// <see cref="TTrapReason.CallDepthExceeded"/> trap.
/// </summary>
public sealed class TCallStack
{
    /// <summary>
    /// hu: A maximális hívási mélység a CIL-T0 spec szerint.
    /// <br />
    /// en: Maximum call depth per the CIL-T0 spec.
    /// </summary>
    public const int MaxDepth = 512;

    private readonly TFrame?[] FFrames;
    private int FDepth;

    /// <summary>
    /// hu: Új, üres call stack létrehozása.
    /// <br />
    /// en: Creates a new, empty call stack.
    /// </summary>
    public TCallStack()
    {
        FFrames = new TFrame?[MaxDepth];
        FDepth = 0;
    }

    /// <summary>
    /// hu: Az aktuális verem mélysége (a benne tárolt frame-ek száma).
    /// <br />
    /// en: Current stack depth (number of frames stored).
    /// </summary>
    public int Depth => FDepth;

    /// <summary>
    /// hu: A verem tetején lévő frame (a jelenleg végrehajtott metódus
    /// frame-je). Üres veremnél <see cref="InvalidOperationException"/>-t
    /// dob — ez programozói hiba a TCpu kerettel, NEM CIL-T0 trap.
    /// <br />
    /// en: The frame on top of the stack (the currently executing method's
    /// frame). On an empty stack throws <see cref="InvalidOperationException"/>
    /// — this is a TCpu programming error, NOT a CIL-T0 trap.
    /// </summary>
    public TFrame Top
    {
        get
        {
            if (FDepth == 0)
                throw new InvalidOperationException("Call stack is empty.");

            return FFrames[FDepth - 1]!;
        }
    }

    /// <summary>
    /// hu: Egy új frame push-olása a verem tetejére. Ha a verem már a
    /// <see cref="MaxDepth"/>-en áll, <see cref="TTrapException"/>-t dob
    /// <see cref="TTrapReason.CallDepthExceeded"/> okkal, a megadott PC-vel.
    /// <br />
    /// en: Pushes a new frame on top of the stack. If the stack is already
    /// at <see cref="MaxDepth"/>, raises a <see cref="TTrapException"/>
    /// with <see cref="TTrapReason.CallDepthExceeded"/> and the given PC.
    /// </summary>
    /// <param name="AFrame">
    /// hu: A push-olandó frame.
    /// <br />
    /// en: The frame to push.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A trap-be elmentendő PC érték (a hívás opkód offszetje).
    /// <br />
    /// en: PC value to record in the trap (offset of the call opcode).
    /// </param>
    public void Push(TFrame AFrame, int APcForTrap)
    {
        ArgumentNullException.ThrowIfNull(AFrame);

        if (FDepth >= MaxDepth)
            throw new TTrapException(TTrapReason.CallDepthExceeded, APcForTrap,
                $"Call depth would exceed {MaxDepth} at PC=0x{APcForTrap:X4}.");

        FFrames[FDepth] = AFrame;
        FDepth++;
    }

    /// <summary>
    /// hu: A verem tetején lévő frame eltávolítása és visszaadása. Üres
    /// veremnél <see cref="InvalidOperationException"/>-t dob.
    /// <br />
    /// en: Removes and returns the frame on top of the stack. On an empty
    /// stack throws <see cref="InvalidOperationException"/>.
    /// </summary>
    public TFrame Pop()
    {
        if (FDepth == 0)
            throw new InvalidOperationException("Cannot pop from empty call stack.");

        FDepth--;
        var frame = FFrames[FDepth]!;
        FFrames[FDepth] = null;

        return frame;
    }

    /// <summary>
    /// hu: A teljes verem kiürítése — minden frame eltávolítva, Depth = 0.
    /// A TCpu az új Execute hívás elején használja, hogy az előző
    /// futtatás állapota ne szivárogjon át.
    /// <br />
    /// en: Clears the entire stack — all frames removed, Depth = 0. Used
    /// by TCpu at the start of a new Execute call to prevent state from a
    /// previous run leaking through.
    /// </summary>
    public void Clear()
    {
        for (var i = 0; i < FDepth; i++)
            FFrames[i] = null;

        FDepth = 0;
    }
}
