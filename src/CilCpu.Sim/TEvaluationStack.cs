namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 evaluation stack szoftveres reprezentációja. Fix 64 elem
/// mélységű, 32-bit (I4) elemeket tárol. A Push/Pop/Dup műveletek trap-et
/// dobnak overflow/underflow esetén, a megadott program counter értékkel,
/// hogy a TCpu pontosan tudja jelezni a trap helyét. A Peek debug/teszt
/// célú API — érvénytelen offszetnél <see cref="ArgumentOutOfRangeException"/>
/// kivételt dob, NEM trap-et, mert ez nem egy CIL-T0 opkód művelete.
/// <br />
/// en: Software representation of the CIL-T0 evaluation stack. Fixed depth
/// of 64 elements, each a 32-bit (I4) value. The Push/Pop/Dup operations
/// raise a trap on overflow/underflow with the supplied program counter
/// value so TCpu can report the exact trap location. Peek is a debug/test
/// API — invalid offsets raise <see cref="ArgumentOutOfRangeException"/>,
/// NOT a trap, because it is not a CIL-T0 opcode operation.
/// </summary>
public sealed class TEvaluationStack
{
    /// <summary>
    /// hu: Az evaluation stack maximális mélysége a CIL-T0 spec szerint
    /// (64 slot). Túllépéskor <see cref="TTrapReason.StackOverflow"/> trap.
    /// <br />
    /// en: Maximum evaluation stack depth per the CIL-T0 spec (64 slots).
    /// Exceeding it raises a <see cref="TTrapReason.StackOverflow"/> trap.
    /// </summary>
    public const int MaxDepth = 64;

    private readonly int[] FSlots;
    private int FDepth;

    /// <summary>
    /// hu: Új, üres evaluation stack létrehozása.
    /// <br />
    /// en: Creates a new, empty evaluation stack.
    /// </summary>
    public TEvaluationStack()
    {
        FSlots = new int[MaxDepth];
        FDepth = 0;
    }

    /// <summary>
    /// hu: Az evaluation stack jelenlegi mélysége (a benne tárolt elemek száma).
    /// <br />
    /// en: Current depth of the evaluation stack (number of stored elements).
    /// </summary>
    public int Depth => FDepth;

    /// <summary>
    /// hu: Érték push-olása a stack tetejére. Ha a stack már MaxDepth mély,
    /// <see cref="TTrapException"/>-t dob <see cref="TTrapReason.StackOverflow"/>
    /// okkal, a megadott PC értékkel; ilyenkor a stack változatlan marad.
    /// <br />
    /// en: Pushes a value onto the top of the stack. If the stack is already
    /// at MaxDepth, throws <see cref="TTrapException"/> with
    /// <see cref="TTrapReason.StackOverflow"/> and the given PC value; the
    /// stack remains unchanged in that case.
    /// </summary>
    /// <param name="AValue">
    /// hu: A stackre töltendő int32 érték.
    /// <br />
    /// en: The int32 value to push onto the stack.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A program counter értéke, amit a trap kivételbe mentünk, ha a
    /// push sikertelen — a hibás utasítás kezdő offszetje.
    /// <br />
    /// en: Program counter value to record in the trap exception if the push
    /// fails — the offset of the offending instruction.
    /// </param>
    public void Push(int AValue, int APcForTrap)
    {
        if (FDepth >= MaxDepth)
            throw new TTrapException(TTrapReason.StackOverflow, APcForTrap);

        FSlots[FDepth] = AValue;
        FDepth++;
    }

    /// <summary>
    /// hu: A TOS elem kivétele a stack-ről. Ha a stack üres,
    /// <see cref="TTrapException"/>-t dob <see cref="TTrapReason.StackUnderflow"/>
    /// okkal, a megadott PC értékkel.
    /// <br />
    /// en: Pops the TOS element from the stack. If the stack is empty,
    /// throws <see cref="TTrapException"/> with
    /// <see cref="TTrapReason.StackUnderflow"/> and the given PC value.
    /// </summary>
    /// <param name="APcForTrap">
    /// hu: A program counter értéke, amit a trap kivételbe mentünk, ha a
    /// pop sikertelen.
    /// <br />
    /// en: Program counter value to record in the trap exception if the pop
    /// fails.
    /// </param>
    public int Pop(int APcForTrap)
    {
        if (FDepth == 0)
            throw new TTrapException(TTrapReason.StackUnderflow, APcForTrap);

        FDepth--;
        return FSlots[FDepth];
    }

    /// <summary>
    /// hu: Elem olvasása a stack tetejétől számolt offszettel. <c>Peek(0)</c>
    /// a TOS, <c>Peek(1)</c> a TOS-1, stb. Ez debug/teszt célú API —
    /// érvénytelen offszetnél <see cref="ArgumentOutOfRangeException"/>-t
    /// dob, NEM trap-et.
    /// <br />
    /// en: Reads an element from the stack at the given offset from the top.
    /// <c>Peek(0)</c> is TOS, <c>Peek(1)</c> is TOS-1, etc. This is a debug/
    /// test API — invalid offsets throw <see cref="ArgumentOutOfRangeException"/>,
    /// NOT a trap.
    /// </summary>
    /// <param name="AOffsetFromTop">
    /// hu: Offszet a stack tetejétől (0 = TOS).
    /// <br />
    /// en: Offset from the top of the stack (0 = TOS).
    /// </param>
    public int Peek(int AOffsetFromTop)
    {
        if (AOffsetFromTop < 0 || AOffsetFromTop >= FDepth)
            throw new ArgumentOutOfRangeException(
                nameof(AOffsetFromTop),
                $"Offset {AOffsetFromTop} out of range for stack depth {FDepth}.");

        return FSlots[FDepth - 1 - AOffsetFromTop];
    }

    /// <summary>
    /// hu: A TOS elem duplikálása. Üres stacken
    /// <see cref="TTrapReason.StackUnderflow"/> trap, teli stacken
    /// <see cref="TTrapReason.StackOverflow"/> trap — mindkét esetben a
    /// megadott PC értékkel.
    /// <br />
    /// en: Duplicates the TOS element. On an empty stack raises a
    /// <see cref="TTrapReason.StackUnderflow"/> trap; on a full stack a
    /// <see cref="TTrapReason.StackOverflow"/> trap — both with the given
    /// PC value.
    /// </summary>
    /// <param name="APcForTrap">
    /// hu: A program counter értéke, amit a trap kivételbe mentünk.
    /// <br />
    /// en: Program counter value to record in the trap exception.
    /// </param>
    public void Dup(int APcForTrap)
    {
        if (FDepth == 0)
            throw new TTrapException(TTrapReason.StackUnderflow, APcForTrap);

        if (FDepth >= MaxDepth)
            throw new TTrapException(TTrapReason.StackOverflow, APcForTrap);

        FSlots[FDepth] = FSlots[FDepth - 1];
        FDepth++;
    }
}
