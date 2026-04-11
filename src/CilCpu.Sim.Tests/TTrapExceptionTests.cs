namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TTrapException osztály tesztjei. A trap kivétel a CIL-T0 hardveres
/// trap feltételek szoftveres reprezentációja az F1 szimulátorban.
/// <br />
/// en: Tests for the TTrapException class. The trap exception is the software
/// representation of CIL-T0 hardware trap conditions in the F1 simulator.
/// </summary>
public class TTrapExceptionTests
{
    /// <summary>
    /// hu: A konstruktor helyesen eltárolja a trap okát és a program counter
    /// értékét. Ezek a trap diagnosztika minimum mezői.
    /// <br />
    /// en: The constructor correctly stores the trap reason and program counter
    /// value. These are the minimum diagnostic fields of a trap.
    /// </summary>
    [Fact]
    public void Constructor_SetsReasonAndProgramCounter()
    {
        var trap = new TTrapException(TTrapReason.StackOverflow, 42);

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
        Assert.Equal(42, trap.ProgramCounter);
    }
}
