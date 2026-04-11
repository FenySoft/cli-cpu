namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 hardveres trap típusai a <c>docs/ISA-CIL-T0.md</c>
/// "Trap (kivétel) típusok" szekciója szerint. A byte értékek megegyeznek
/// a spec trap számaival, így az F2 RTL-lel bit-szinten kompatibilisek.
/// <br />
/// en: CIL-T0 hardware trap types per the "Trap types" section of
/// <c>docs/ISA-CIL-T0.md</c>. Byte values match the spec trap numbers,
/// so they are bit-compatible with the F2 RTL implementation.
/// </summary>
public enum TTrapReason : byte
{
    /// <summary>
    /// hu: Nincs trap — normál végrehajtás.
    /// <br />
    /// en: No trap — normal execution.
    /// </summary>
    None = 0x00,

    /// <summary>
    /// hu: Az evaluation stack eléri a maximális mélységet (64 slot)
    /// egy push műveletnél.
    /// <br />
    /// en: The evaluation stack reaches its maximum depth (64 slots)
    /// during a push operation.
    /// </summary>
    StackOverflow = 0x01,

    /// <summary>
    /// hu: Pop egy üres evaluation stack-ről.
    /// <br />
    /// en: Pop from an empty evaluation stack.
    /// </summary>
    StackUnderflow = 0x02,

    /// <summary>
    /// hu: Ismeretlen opkód bájt a dekóderben.
    /// <br />
    /// en: Unknown opcode byte at the decoder.
    /// </summary>
    InvalidOpcode = 0x03,

    /// <summary>
    /// hu: Local index ≥ 16 vagy ≥ a tényleges local count.
    /// <br />
    /// en: Local index ≥ 16 or ≥ the actual local count.
    /// </summary>
    InvalidLocal = 0x04,

    /// <summary>
    /// hu: Argument index ≥ 16 vagy ≥ a tényleges arg count.
    /// <br />
    /// en: Argument index ≥ 16 or ≥ the actual arg count.
    /// </summary>
    InvalidArg = 0x05,

    /// <summary>
    /// hu: Branch target a metódus kód-tartományán kívül esik.
    /// <br />
    /// en: Branch target outside the method's code range.
    /// </summary>
    InvalidBranchTarget = 0x06,

    /// <summary>
    /// hu: Call target RVA a CODE régión kívül esik.
    /// <br />
    /// en: Call target RVA outside the CODE region.
    /// </summary>
    InvalidCallTarget = 0x07,

    /// <summary>
    /// hu: <c>div</c> vagy <c>rem</c> nulla osztóval.
    /// <br />
    /// en: <c>div</c> or <c>rem</c> with a zero divisor.
    /// </summary>
    DivByZero = 0x08,

    /// <summary>
    /// hu: <c>div</c> esetén INT_MIN / -1 túlcsordulás.
    /// <br />
    /// en: INT_MIN / -1 overflow in <c>div</c>.
    /// </summary>
    Overflow = 0x09,

    /// <summary>
    /// hu: A hívási mélység eléri a maximumot (512).
    /// <br />
    /// en: Call depth reaches the maximum (512).
    /// </summary>
    CallDepthExceeded = 0x0A,

    /// <summary>
    /// hu: A <c>break</c> opkód (debug trap).
    /// <br />
    /// en: The <c>break</c> opcode (debug trap).
    /// </summary>
    DebugBreak = 0x0B,

    /// <summary>
    /// hu: Érvénytelen memória hozzáférés: az <c>ldind.i4</c> /
    /// <c>stind.i4</c> opkód olyan címet használ, amely a data memory
    /// tartományán kívül esik, vagy a CPU-hoz nincs data memory rendelve.
    /// Az F2 RTL-ben ez a hardveres memory controller hibájának felel meg.
    /// <br />
    /// en: Invalid memory access: an <c>ldind.i4</c> / <c>stind.i4</c>
    /// opcode targets an address outside the data memory range, or the
    /// CPU has no data memory configured. In the F2 RTL this corresponds
    /// to a hardware memory controller fault.
    /// </summary>
    InvalidMemoryAccess = 0x0C
}
