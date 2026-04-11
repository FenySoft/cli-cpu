namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TFrame osztály unit tesztjei. A frame a CIL-T0 metódus hívási
/// kontextust reprezentálja: argumentum- és lokális-tömböket.
/// <br />
/// en: Unit tests for the TFrame class. The frame represents the CIL-T0
/// method call context: argument and local arrays.
/// </summary>
public class TFrameTests
{
    /// <summary>
    /// hu: Happy path — érvényes arg és local count, null kezdő args.
    /// Az Args és Locals tömbök fix méretűek (16-16), és minden slot 0.
    /// <br />
    /// en: Happy path — valid arg and local counts, null initial args.
    /// The Args and Locals arrays have fixed size (16-16), all slots 0.
    /// </summary>
    [Fact]
    public void Constructor_ValidCounts_CreatesFrameWithZeroedArrays()
    {
        var frame = new TFrame(3, 5);

        Assert.Equal(3, frame.ArgCount);
        Assert.Equal(5, frame.LocalCount);
        Assert.Equal(TFrame.MaxArgs, frame.Args.Length);
        Assert.Equal(TFrame.MaxLocals, frame.Locals.Length);

        for (var i = 0; i < TFrame.MaxArgs; i++)
            Assert.Equal(0, frame.Args[i]);

        for (var i = 0; i < TFrame.MaxLocals; i++)
            Assert.Equal(0, frame.Locals[i]);
    }

    /// <summary>
    /// hu: A kezdő argumentumok átmásolódnak az Args tömb elejére.
    /// A használatlan slot-ok 0-val töltődnek.
    /// <br />
    /// en: Initial arguments are copied into the start of the Args array.
    /// Unused slots are zero-filled.
    /// </summary>
    [Fact]
    public void Constructor_WithInitialArgs_CopiesValues()
    {
        var initial = new[] { 10, 20, 30 };

        var frame = new TFrame(4, 2, initial);

        Assert.Equal(10, frame.Args[0]);
        Assert.Equal(20, frame.Args[1]);
        Assert.Equal(30, frame.Args[2]);
        Assert.Equal(0, frame.Args[3]);
    }

    /// <summary>
    /// hu: Érvénytelen ArgCount (negatív vagy > 16) ArgumentOutOfRangeException.
    /// <br />
    /// en: Invalid ArgCount (negative or > 16) throws ArgumentOutOfRangeException.
    /// </summary>
    [Fact]
    public void Constructor_InvalidArgCount_ThrowsArgumentOutOfRange()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new TFrame(-1, 0));
        Assert.Throws<ArgumentOutOfRangeException>(() => new TFrame(17, 0));
    }

    /// <summary>
    /// hu: Érvénytelen LocalCount (negatív vagy > 16) ArgumentOutOfRangeException.
    /// <br />
    /// en: Invalid LocalCount (negative or > 16) throws ArgumentOutOfRangeException.
    /// </summary>
    [Fact]
    public void Constructor_InvalidLocalCount_ThrowsArgumentOutOfRange()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new TFrame(0, -1));
        Assert.Throws<ArgumentOutOfRangeException>(() => new TFrame(0, 17));
    }

    /// <summary>
    /// hu: Ha a kezdő arg tömb hossza nagyobb, mint az ArgCount,
    /// ArgumentException dobódik.
    /// <br />
    /// en: If the initial args array is longer than ArgCount, an
    /// ArgumentException is thrown.
    /// </summary>
    [Fact]
    public void Constructor_InitialArgsLongerThanArgCount_ThrowsArgumentException()
    {
        var initial = new[] { 1, 2, 3, 4, 5 };

        Assert.Throws<ArgumentException>(() => new TFrame(3, 0, initial));
    }

    /// <summary>
    /// hu: Null kezdő args — minden argument slot 0.
    /// <br />
    /// en: Null initial args — all argument slots are zero.
    /// </summary>
    [Fact]
    public void Constructor_NullInitialArgs_AllArgsZero()
    {
        var frame = new TFrame(4, 0, null);

        for (var i = 0; i < TFrame.MaxArgs; i++)
            Assert.Equal(0, frame.Args[i]);
    }

    /// <summary>
    /// hu: A határértékek (0 és 16) elfogadottak.
    /// <br />
    /// en: Boundary values (0 and 16) are accepted.
    /// </summary>
    [Fact]
    public void Constructor_BoundaryCounts_Accepted()
    {
        var zero = new TFrame(0, 0);
        Assert.Equal(0, zero.ArgCount);
        Assert.Equal(0, zero.LocalCount);

        var max = new TFrame(TFrame.MaxArgs, TFrame.MaxLocals);
        Assert.Equal(TFrame.MaxArgs, max.ArgCount);
        Assert.Equal(TFrame.MaxLocals, max.LocalCount);
    }
}
