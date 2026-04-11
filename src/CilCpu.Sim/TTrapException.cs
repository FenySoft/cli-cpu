namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 szimulátor által dobott trap kivétel. Az F1 fázisban
/// a hardveres trap feltételeket (stack over/underflow, div-by-zero,
/// invalid opcode, stb.) szoftveres kivételként jelezzük a hívónak;
/// az F2 RTL ugyanezt a <c>STATUS</c> regiszter és UART-on keresztül
/// adja ki. A <see cref="Reason"/> és <see cref="ProgramCounter"/>
/// mezők biztosítják a diagnosztikához szükséges minimum kontextust.
/// <br />
/// en: Trap exception thrown by the CIL-T0 simulator. In the F1 phase,
/// hardware trap conditions (stack over/underflow, div-by-zero, invalid
/// opcode, etc.) are reported to the caller as software exceptions;
/// the F2 RTL implementation reports the same via the <c>STATUS</c>
/// register and UART. The <see cref="Reason"/> and <see cref="ProgramCounter"/>
/// fields provide the minimum diagnostic context.
/// </summary>
public sealed class TTrapException : Exception
{
    /// <summary>
    /// hu: A trap kiváltó oka (lásd <see cref="TTrapReason"/>).
    /// <br />
    /// en: The trap cause (see <see cref="TTrapReason"/>).
    /// </summary>
    public TTrapReason Reason { get; }

    /// <summary>
    /// hu: A program counter értéke a trap pillanatában — a hibás
    /// utasítás kezdő offszetje a program byte-tömbben.
    /// <br />
    /// en: Program counter value at the moment of the trap — the starting
    /// offset of the offending instruction in the program byte array.
    /// </summary>
    public int ProgramCounter { get; }

    /// <summary>
    /// hu: Új trap kivétel létrehozása a megadott ok-kal és PC értékkel.
    /// <br />
    /// en: Creates a new trap exception with the given reason and PC value.
    /// </summary>
    /// <param name="AReason">
    /// hu: A trap kiváltó oka.
    /// <br />
    /// en: The trap cause.
    /// </param>
    /// <param name="AProgramCounter">
    /// hu: A program counter értéke a trap pillanatában.
    /// <br />
    /// en: Program counter value at the time of the trap.
    /// </param>
    /// <param name="AMessage">
    /// hu: Opcionális emberi olvasható üzenet.
    /// <br />
    /// en: Optional human-readable message.
    /// </param>
    public TTrapException(TTrapReason AReason, int AProgramCounter, string? AMessage = null)
        : base(AMessage ?? $"CIL-T0 trap {AReason} at PC=0x{AProgramCounter:X4}")
    {
        Reason = AReason;
        ProgramCounter = AProgramCounter;
    }
}
