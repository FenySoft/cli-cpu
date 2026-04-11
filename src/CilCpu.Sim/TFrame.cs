namespace CilCpu.Sim;

/// <summary>
/// hu: Egy CIL-T0 metódus hívási keret (frame) reprezentációja: fix méretű
/// argumentum- és lokális-tömbök, a tényleges használt számokkal. A CIL-T0
/// specifikáció szerint metódusonként maximum 16 argumentum és 16 lokális
/// engedélyezett. A frame nem tárolja az eval stack-et — az a <see cref="TEvaluationStack"/>
/// felelőssége.
/// <br />
/// en: Represents a CIL-T0 method call frame: fixed-size argument and local
/// arrays, with the actual counts in use. The CIL-T0 specification allows
/// up to 16 arguments and 16 locals per method. The frame does not store
/// the evaluation stack — that is the responsibility of <see cref="TEvaluationStack"/>.
/// </summary>
public sealed class TFrame
{
    /// <summary>
    /// hu: Metódusonként engedélyezett maximális argumentum szám.
    /// <br />
    /// en: Maximum number of arguments allowed per method.
    /// </summary>
    public const int MaxArgs = 16;

    /// <summary>
    /// hu: Metódusonként engedélyezett maximális lokális változó szám.
    /// <br />
    /// en: Maximum number of local variables allowed per method.
    /// </summary>
    public const int MaxLocals = 16;

    /// <summary>
    /// hu: Az aktuális frame argumentumainak száma (0..16).
    /// <br />
    /// en: Number of arguments in the current frame (0..16).
    /// </summary>
    public int ArgCount { get; }

    /// <summary>
    /// hu: Az aktuális frame lokális változóinak száma (0..16).
    /// <br />
    /// en: Number of local variables in the current frame (0..16).
    /// </summary>
    public int LocalCount { get; }

    /// <summary>
    /// hu: Az argumentumok tömbje, length == <see cref="MaxArgs"/>. Csak az
    /// első <see cref="ArgCount"/> slot-ot használjuk; a tobbi nulla marad.
    /// <br />
    /// en: Arguments array, length == <see cref="MaxArgs"/>. Only the first
    /// <see cref="ArgCount"/> slots are used; the rest remain zero.
    /// </summary>
    public int[] Args { get; }

    /// <summary>
    /// hu: A lokális változók tömbje, length == <see cref="MaxLocals"/>.
    /// Minden slot 0-val inicializálva.
    /// <br />
    /// en: Locals array, length == <see cref="MaxLocals"/>. All slots are
    /// initialized to 0.
    /// </summary>
    public int[] Locals { get; }

    /// <summary>
    /// hu: A frame saját evaluation stackje. Minden hívási keret különálló
    /// eval stacket kap, így a caller TOS-ai sértetlenül megőrződnek a
    /// hívás alatt.
    /// <br />
    /// en: The frame's own evaluation stack. Each call frame gets its own
    /// eval stack so the caller's TOS values are preserved untouched
    /// across the call.
    /// </summary>
    public TEvaluationStack EvalStack { get; }

    /// <summary>
    /// hu: A visszatérési PC — a hívó utáni opkód kezdő offszete a
    /// programban. A <c>ret</c> opkód ezt állítja vissza a PC-be a callee
    /// frame eldobása után. A root (gyökér) frame esetén 0 (nincs caller).
    /// <br />
    /// en: Return PC — offset of the opcode following the caller's call
    /// instruction. The <c>ret</c> opcode restores this into PC after
    /// discarding the callee frame. For the root frame this is 0 (no caller).
    /// </summary>
    public int ReturnPc { get; set; }

    /// <summary>
    /// hu: Új frame létrehozása adott arg count, local count és opcionális
    /// kezdő argumentum tömbbel. A konstruktor validálja az intervallumokat
    /// (0..16); érvénytelen esetén <see cref="ArgumentOutOfRangeException"/>-t
    /// dob. Ha <paramref name="AInitialArgs"/> nem null, a length ≤ AArgCount
    /// kell legyen (<see cref="ArgumentException"/>), és az értékek átmásolódnak
    /// az <see cref="Args"/> tömb első AArgCount slot-jába. Locals mindig 0.
    /// <br />
    /// en: Creates a new frame with the given arg count, local count and an
    /// optional initial arguments array. The constructor validates the
    /// ranges (0..16); on invalid input throws <see cref="ArgumentOutOfRangeException"/>.
    /// If <paramref name="AInitialArgs"/> is non-null, its length must be
    /// ≤ AArgCount (<see cref="ArgumentException"/>), and the values are
    /// copied into the first AArgCount slots of <see cref="Args"/>. Locals
    /// are always zero-initialized.
    /// </summary>
    /// <param name="AArgCount">
    /// hu: Az argumentumok száma (0..16).
    /// <br />
    /// en: Argument count (0..16).
    /// </param>
    /// <param name="ALocalCount">
    /// hu: A lokális változók száma (0..16).
    /// <br />
    /// en: Local variable count (0..16).
    /// </param>
    /// <param name="AInitialArgs">
    /// hu: Opcionális kezdő argumentum értékek; length ≤ AArgCount.
    /// <br />
    /// en: Optional initial argument values; length ≤ AArgCount.
    /// </param>
    public TFrame(int AArgCount, int ALocalCount, int[]? AInitialArgs = null)
    {
        if (AArgCount < 0 || AArgCount > MaxArgs)
            throw new ArgumentOutOfRangeException(nameof(AArgCount),
                $"ArgCount {AArgCount} out of range [0..{MaxArgs}].");

        if (ALocalCount < 0 || ALocalCount > MaxLocals)
            throw new ArgumentOutOfRangeException(nameof(ALocalCount),
                $"LocalCount {ALocalCount} out of range [0..{MaxLocals}].");

        if (AInitialArgs is not null && AInitialArgs.Length > AArgCount)
            throw new ArgumentException(
                $"InitialArgs length {AInitialArgs.Length} exceeds ArgCount {AArgCount}.",
                nameof(AInitialArgs));

        ArgCount = AArgCount;
        LocalCount = ALocalCount;
        Args = new int[MaxArgs];
        Locals = new int[MaxLocals];
        EvalStack = new TEvaluationStack();
        ReturnPc = 0;

        if (AInitialArgs is not null)
        {
            for (var i = 0; i < AInitialArgs.Length; i++)
                Args[i] = AInitialArgs[i];
        }
    }
}
