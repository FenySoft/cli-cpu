using CilCpu.Sim;

namespace CilCpu.Sim.Runner;

/// <summary>
/// hu: A Runner végrehajtás eredménye — tartalmazza a TOS értéket,
/// a végrehajtott utasítások számát, és az esetleges trap információt.
/// <br />
/// en: Runner execution result — contains the TOS value, instruction
/// count, and optional trap information.
/// </summary>
/// <param name="Result">
/// hu: A stack tetején lévő érték (TOS) a végrehajtás végén.
/// Trap esetén null.
/// <br />
/// en: Top-of-stack value after execution. Null on trap.
/// </param>
/// <param name="TrapReason">
/// hu: A trap oka, ha a végrehajtás trap-be futott. Egyébként null.
/// <br />
/// en: The trap reason, if execution ended in a trap. Null otherwise.
/// </param>
/// <param name="TrapMessage">
/// hu: A trap üzenet, ha volt trap. Egyébként null.
/// <br />
/// en: The trap message, if any. Null otherwise.
/// </param>
public sealed record TRunResult(
    int? Result,
    TTrapReason? TrapReason,
    string? TrapMessage)
{
    /// <summary>
    /// hu: True, ha a végrehajtás trap-be futott.
    /// <br />
    /// en: True if execution ended in a trap.
    /// </summary>
    public bool Trapped => TrapReason is not null;
}
