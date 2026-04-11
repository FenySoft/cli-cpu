namespace CilCpu.Sim;

/// <summary>
/// hu: A CLI-CPU Nano core szoftveres referencia szimulátora.
/// Végrehajtja a CIL-T0 subset opkódjait a <c>docs/ISA-CIL-T0.md</c>
/// specifikáció szerint. Ez az F1 fázis aranypéldája, amelyet az F2
/// RTL implementáció cocotb testbench-csel összehasonlítva validál.
/// <br />
/// en: Software reference simulator for the CLI-CPU Nano core.
/// Executes CIL-T0 subset opcodes per the <c>docs/ISA-CIL-T0.md</c>
/// specification. This is the golden model for the F1 phase, validated
/// against the F2 RTL implementation via cocotb testbench.
/// </summary>
public sealed class TCpu
{
    /// <summary>
    /// hu: Az evaluation stack maximális mélysége a CIL-T0 spec szerint.
    /// Túllépéskor <see cref="TTrapReason.StackOverflow"/> trap.
    /// <br />
    /// en: Maximum evaluation stack depth per CIL-T0 spec. Exceeding it
    /// raises a <see cref="TTrapReason.StackOverflow"/> trap.
    /// </summary>
    public const int MaxStackDepth = TEvaluationStack.MaxDepth;

    private readonly TCallStack FCallStack;
    private readonly byte[]? FDataMemory;
    private int FProgramCounter;
    private bool FHalted;

    /// <summary>
    /// hu: Új CPU példány létrehozása data memory nélkül. Az ldind.i4 és
    /// stind.i4 opkódok ekkor InvalidMemoryAccess trap-et dobnak — használj
    /// data-memory változatot a <see cref="TCpu(byte[])"/> konstruktorral.
    /// <br />
    /// en: Creates a new CPU instance without data memory. The ldind.i4
    /// and stind.i4 opcodes will raise InvalidMemoryAccess traps — use the
    /// <see cref="TCpu(byte[])"/> constructor for a data-memory variant.
    /// </summary>
    public TCpu()
        : this(null)
    {
    }

    /// <summary>
    /// hu: Új CPU példány létrehozása opcionális data memory tömbbel.
    /// A data memory az ldind.i4 / stind.i4 opkódok hátterét adja: a TOS
    /// címet ehhez a tömbhöz indexeli. Ha a paraméter <c>null</c>, ezek
    /// az opkódok InvalidMemoryAccess trap-et dobnak.
    /// <br />
    /// en: Creates a new CPU instance with an optional data memory array.
    /// Data memory backs the ldind.i4 / stind.i4 opcodes: the TOS address
    /// indexes into this array. If <c>null</c>, those opcodes raise
    /// InvalidMemoryAccess traps.
    /// </summary>
    /// <param name="ADataMemory">
    /// hu: A data memory byte-tömb, vagy <c>null</c> ha nincs.
    /// <br />
    /// en: The data memory byte array, or <c>null</c> if none.
    /// </param>
    public TCpu(byte[]? ADataMemory)
    {
        FCallStack = new TCallStack();
        FDataMemory = ADataMemory;
        FProgramCounter = 0;
        FHalted = false;
    }

    /// <summary>
    /// hu: Az aktuális program counter (PC) értéke — a következő végrehajtandó
    /// opkód offszetje a program byte-tömbjében.
    /// <br />
    /// en: Current program counter (PC) value — the offset of the next opcode
    /// to execute in the program byte array.
    /// </summary>
    public int ProgramCounter => FProgramCounter;

    /// <summary>
    /// hu: Az aktuális (top) frame evaluation stackjének mélysége. Ha a
    /// call stack üres (futtatás előtt), 0-t ad vissza.
    /// <br />
    /// en: Depth of the current (top) frame's evaluation stack. Returns 0
    /// if the call stack is empty (before any execution).
    /// </summary>
    public int StackDepth => FCallStack.Depth == 0 ? 0 : FCallStack.Top.EvalStack.Depth;

    /// <summary>
    /// hu: Az aktuális hívási mélység (a call stack frame-jeinek száma).
    /// <br />
    /// en: Current call depth (number of frames in the call stack).
    /// </summary>
    public int CallDepth => FCallStack.Depth;

    /// <summary>
    /// hu: Egy elem olvasása a top frame evaluation stack tetejétől
    /// számolt offszettel. <c>Peek(0)</c> a TOS, <c>Peek(1)</c> a TOS-1, stb.
    /// Ez a metódus tesztelési és debug célra szolgál — a CIL-T0 opkódok
    /// mindig a TOS-on dolgoznak. Üres call stack esetén
    /// <see cref="InvalidOperationException"/>-t dob, mivel ekkor nincs
    /// aktív frame, amelynek eval stackjéből olvashatnánk.
    /// <br />
    /// en: Reads an element from the top frame's evaluation stack at the
    /// given offset from the top. <c>Peek(0)</c> is TOS, <c>Peek(1)</c> is
    /// TOS-1, etc. For testing and debugging. Throws
    /// <see cref="InvalidOperationException"/> if the call stack is empty,
    /// because there is no active frame to read from.
    /// </summary>
    /// <param name="AOffsetFromTop">
    /// hu: Offszet a stack tetejétől (0 = TOS).
    /// <br />
    /// en: Offset from the top of the stack (0 = TOS).
    /// </param>
    public int Peek(int AOffsetFromTop)
    {
        if (FCallStack.Depth == 0)
            throw new InvalidOperationException(
                "Cannot Peek: call stack is empty. Did you call Execute first?");

        return FCallStack.Top.EvalStack.Peek(AOffsetFromTop);
    }

    /// <summary>
    /// hu: Egy CIL-T0 program byte-sorozatának végrehajtása a program
    /// elejétől, üres frame-mel (0 arg, 0 local). Visszafelé kompatibilis
    /// az iter. 1 tesztekkel.
    /// <br />
    /// en: Executes a CIL-T0 program byte sequence from the start with an
    /// empty frame (0 args, 0 locals). Backward compatible with iter. 1
    /// tests.
    /// </summary>
    /// <param name="AProgram">
    /// hu: A végrehajtandó CIL-T0 byte-ok tömbje.
    /// <br />
    /// en: The CIL-T0 byte array to execute.
    /// </param>
    public void Execute(byte[] AProgram) => Execute(AProgram, 0, 0, null);

    /// <summary>
    /// hu: Egy CIL-T0 program byte-sorozatának végrehajtása a program
    /// elejétől egy explicit frame kontextusban (argumentum count, lokális
    /// count, kezdő argumentumok). Ez az "ős-overload": nem header-vezérelt
    /// — a tesztek a CIL-T0 bináris formátum nélkül futtathatnak nyers
    /// kódot. A futtatás akkor áll le, amikor a PC eléri a program végét
    /// VAGY a root frame egy <c>ret</c>-tel kilép.
    /// <br />
    /// en: Executes a CIL-T0 program byte sequence from the start in an
    /// explicit frame context (argument count, local count, initial args).
    /// This is the "raw" overload: not header-driven — tests run raw code
    /// without the CIL-T0 binary format. Execution stops when PC reaches
    /// the end of the program OR the root frame exits via <c>ret</c>.
    /// </summary>
    /// <param name="AProgram">
    /// hu: A végrehajtandó CIL-T0 byte-ok tömbje.
    /// <br />
    /// en: The CIL-T0 byte array to execute.
    /// </param>
    /// <param name="AArgCount">
    /// hu: Az aktuális frame argumentumainak száma (0..16).
    /// <br />
    /// en: Number of arguments in the current frame (0..16).
    /// </param>
    /// <param name="ALocalCount">
    /// hu: Az aktuális frame lokális változóinak száma (0..16).
    /// <br />
    /// en: Number of local variables in the current frame (0..16).
    /// </param>
    /// <param name="AInitialArgs">
    /// hu: A kezdő argumentum értékek; length ≤ AArgCount. Null esetén
    /// az argumentumok mind 0.
    /// <br />
    /// en: Initial argument values; length ≤ AArgCount. Null means all
    /// arguments start at 0.
    /// </param>
    public void Execute(byte[] AProgram, int AArgCount, int ALocalCount, int[]? AInitialArgs = null)
    {
        ArgumentNullException.ThrowIfNull(AProgram);

        FCallStack.Clear();
        FProgramCounter = 0;
        FHalted = false;

        var rootFrame = new TFrame(AArgCount, ALocalCount, AInitialArgs);
        FCallStack.Push(rootFrame, 0);

        RunLoop(AProgram);
    }

    /// <summary>
    /// hu: A CIL-T0 bináris formátum (header-vezérelt) végrehajtás.
    /// A megadott RVA-n álló metódus header-jét beolvassa, létrehozza a
    /// kezdő frame-et a header alapján, majd futtatja a metódust. A
    /// futtatás akkor áll le, amikor a root frame egy <c>ret</c>-tel
    /// visszatér. Ha a header magic érvénytelen, vagy a header / a code
    /// szegmens kívül esik, <see cref="TTrapReason.InvalidCallTarget"/>
    /// trap-et dob.
    /// <br />
    /// en: CIL-T0 binary format (header-driven) execution. Reads the
    /// method header at the given RVA, creates an initial frame from the
    /// header, then runs the method. Execution stops when the root frame
    /// returns via <c>ret</c>. If the header magic is invalid or the
    /// header/code falls outside the program, raises a
    /// <see cref="TTrapReason.InvalidCallTarget"/> trap.
    /// </summary>
    /// <param name="AProgram">
    /// hu: A teljes CIL-T0 program byte-tömb.
    /// <br />
    /// en: The full CIL-T0 program byte array.
    /// </param>
    /// <param name="AEntryRva">
    /// hu: A belépési metódus header-jének offszete a programban.
    /// <br />
    /// en: Offset of the entry method's header in the program.
    /// </param>
    /// <param name="AInitialArgs">
    /// hu: Opcionális kezdő argumentum értékek a belépési metódusnak.
    /// <br />
    /// en: Optional initial argument values for the entry method.
    /// </param>
    public void Execute(byte[] AProgram, int AEntryRva, int[]? AInitialArgs = null)
    {
        ArgumentNullException.ThrowIfNull(AProgram);

        FCallStack.Clear();
        FProgramCounter = 0;
        FHalted = false;

        // hu: Header validáció. CIL trap (NEM exception), mert a runtime
        //     is így viselkedik a hibás belépési pont esetén.
        // en: Header validation. CIL trap (not exception) so we behave
        //     identically to the runtime on a bad entry point.
        if (!TryReadHeader(AProgram, AEntryRva, out var header))
            throw new TTrapException(TTrapReason.InvalidCallTarget, AEntryRva,
                $"Invalid entry method header at RVA=0x{AEntryRva:X4}.");

        if (AEntryRva + TMethodHeader.HeaderSize + header.CodeSize > AProgram.Length)
            throw new TTrapException(TTrapReason.InvalidCallTarget, AEntryRva,
                $"Entry method code at RVA=0x{AEntryRva:X4} extends past program end.");

        var rootFrame = new TFrame(header.ArgCount, header.LocalCount, AInitialArgs);
        FCallStack.Push(rootFrame, AEntryRva);

        FProgramCounter = AEntryRva + TMethodHeader.HeaderSize;

        RunLoop(AProgram);
    }

    /// <summary>
    /// hu: A főciklus: amíg a végrehajtás nem áll le (Halted), a PC a
    /// program határain belül van, és van legalább egy frame a call
    /// stack-en, dekódolja és végrehajtja az aktuális utasítást.
    /// <br />
    /// en: The main loop: while execution is not halted, PC is within the
    /// program bounds and at least one frame is on the call stack, decode
    /// and execute the current instruction.
    /// </summary>
    private void RunLoop(byte[] AProgram)
    {
        while (!FHalted && FCallStack.Depth > 0 && FProgramCounter < AProgram.Length)
        {
            var decoded = TDecoder.Decode(AProgram, FProgramCounter);
            TExecutor.Execute(this, AProgram, decoded);
        }
    }

    /// <summary>
    /// hu: Próbál egy header-t parse-olni a megadott RVA-n. Visszaadja,
    /// hogy sikerült-e (false ha a tartomány érvénytelen vagy a magic
    /// rossz). Belső segédfüggvény, NEM dob exception-t.
    /// <br />
    /// en: Attempts to parse a header at the given RVA. Returns whether
    /// it succeeded (false if range is invalid or magic is wrong). Internal
    /// helper, does NOT throw.
    /// </summary>
    private static bool TryReadHeader(byte[] AProgram, int AHeaderRva, out TMethodHeader AHeader)
    {
        AHeader = default;

        if (AHeaderRva < 0 || AHeaderRva + TMethodHeader.HeaderSize > AProgram.Length)
            return false;

        if (AProgram[AHeaderRva] != TMethodHeader.MagicValue)
            return false;

        var argCount = AProgram[AHeaderRva + 1];
        var localCount = AProgram[AHeaderRva + 2];
        var maxStack = AProgram[AHeaderRva + 3];
        var codeSize = (ushort)(AProgram[AHeaderRva + 4] | (AProgram[AHeaderRva + 5] << 8));

        if (argCount > TFrame.MaxArgs || localCount > TFrame.MaxLocals)
            return false;

        AHeader = new TMethodHeader(TMethodHeader.MagicValue, argCount, localCount, maxStack, codeSize);

        return true;
    }

    // ------------------------------------------------------------------
    // hu: Belső API-k, amiket a TExecutor használ a CPU-állapot
    //     manipulációjához. Nem publikus — csak az assembly-n belül.
    // en: Internal APIs used by TExecutor to manipulate CPU state.
    //     Not public — only within the assembly.
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Az aktuális (top) frame evaluation stackje a TExecutor számára.
    /// <br />
    /// en: Current (top) frame's evaluation stack for TExecutor.
    /// </summary>
    internal TEvaluationStack EvalStack => FCallStack.Top.EvalStack;

    /// <summary>
    /// hu: Az aktuális (top) frame hozzáférése a TExecutor számára.
    /// <br />
    /// en: Current (top) frame access for TExecutor.
    /// </summary>
    internal TFrame CurrentFrame => FCallStack.Top;

    /// <summary>
    /// hu: A call stack hozzáférése a TExecutor számára (call/ret).
    /// <br />
    /// en: Call stack access for TExecutor (call/ret).
    /// </summary>
    internal TCallStack CallStack => FCallStack;

    /// <summary>
    /// hu: A data memory hozzáférése a TExecutor számára (ldind.i4 / stind.i4).
    /// <br />
    /// en: Data memory access for TExecutor (ldind.i4 / stind.i4).
    /// </summary>
    internal byte[]? DataMemory => FDataMemory;

    /// <summary>
    /// hu: A program counter olvasása/írása a TExecutor számára.
    /// <br />
    /// en: Program counter read/write for TExecutor.
    /// </summary>
    internal int Pc
    {
        get => FProgramCounter;
        set => FProgramCounter = value;
    }

    /// <summary>
    /// hu: A "halted" jelző írása — a TExecutor a root frame ret-jénél
    /// állítja, hogy a futási loop azonnal leálljon, függetlenül a PC-től.
    /// <br />
    /// en: Sets the "halted" flag — TExecutor sets it on root-frame ret so
    /// the run loop stops immediately, regardless of PC.
    /// </summary>
    internal void Halt() => FHalted = true;
}
