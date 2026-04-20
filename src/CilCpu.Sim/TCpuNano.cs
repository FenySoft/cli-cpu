namespace CilCpu.Sim;

/// <summary>
/// hu: A CLI-CPU Nano core szoftveres referencia szimulátora.
/// Végrehajtja a CIL-T0 subset opkódjait a <c>docs/ISA-CIL-T0.md</c>
/// specifikáció szerint. Ez az F1 fázis aranypéldája, amelyet az F2
/// RTL implementáció cocotb testbench-csel összehasonlítva validál.
/// A belső állapot SRAM-alapú: a hívási keretek, argumentumok, lokálisok
/// és az eval stack egyetlen byte[] tömbben élnek, byte-ra megegyezően
/// a hardverrel.
/// <br />
/// en: Software reference simulator for the CLI-CPU Nano core.
/// Executes CIL-T0 subset opcodes per the <c>docs/ISA-CIL-T0.md</c>
/// specification. This is the golden model for the F1 phase, validated
/// against the F2 RTL implementation via cocotb testbench.
/// Internal state is SRAM-based: call frames, arguments, locals and the
/// eval stack live in a single byte[] array, byte-identical to hardware.
/// </summary>
public class TCpuNano
{
    /// <summary>
    /// hu: Az evaluation stack maximális mélysége a CIL-T0 spec szerint.
    /// Túllépéskor <see cref="TTrapReason.StackOverflow"/> trap.
    /// <br />
    /// en: Maximum evaluation stack depth per CIL-T0 spec. Exceeding it
    /// raises a <see cref="TTrapReason.StackOverflow"/> trap.
    /// </summary>
    public const int MaxStackDepth = 64;

    /// <summary>
    /// hu: A maximális hívási mélység a CIL-T0 spec szerint.
    /// <br />
    /// en: Maximum call depth per the CIL-T0 spec.
    /// </summary>
    public const int MaxCallDepth = 512;

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
    /// hu: Az alapértelmezett SRAM méret bájtban (16 KB).
    /// <br />
    /// en: Default SRAM size in bytes (16 KB).
    /// </summary>
    public const int DefaultSramSize = 16384;

    /// <summary>
    /// hu: A frame header mérete bájtban (ReturnPC 4 + PrevFrameBase 4 +
    /// ArgCount 1 + LocalCount 1 + reserved 2 = 12).
    /// <br />
    /// en: Frame header size in bytes (ReturnPC 4 + PrevFrameBase 4 +
    /// ArgCount 1 + LocalCount 1 + reserved 2 = 12).
    /// </summary>
    internal const int FrameHeaderSize = 12;

    /// <summary>
    /// hu: A ReturnPC mező offszetje a frame header-en belül.
    /// <br />
    /// en: Offset of the ReturnPC field within the frame header.
    /// </summary>
    internal const int OffsetReturnPc = 0;

    /// <summary>
    /// hu: A PrevFrameBase mező offszetje a frame header-en belül.
    /// <br />
    /// en: Offset of the PrevFrameBase field within the frame header.
    /// </summary>
    internal const int OffsetPrevFrameBase = 4;

    /// <summary>
    /// hu: Az ArgCount mező offszetje a frame header-en belül.
    /// <br />
    /// en: Offset of the ArgCount field within the frame header.
    /// </summary>
    internal const int OffsetArgCount = 8;

    /// <summary>
    /// hu: A LocalCount mező offszetje a frame header-en belül.
    /// <br />
    /// en: Offset of the LocalCount field within the frame header.
    /// </summary>
    internal const int OffsetLocalCount = 9;

    protected readonly byte[] FSram;
    private readonly byte[]? FDataMemory;
    protected int FSp;
    protected int FFrameBase;
    protected int FArgCount;
    protected int FLocalCount;
    protected int FCallDepth;
    protected int FProgramCounter;
    protected bool FHalted;

    /// <summary>
    /// hu: Új CPU példány létrehozása data memory nélkül. Az ldind.i4 és
    /// stind.i4 opkódok ekkor InvalidMemoryAccess trap-et dobnak — használj
    /// data-memory változatot a <see cref="TCpuNano(byte[])"/> konstruktorral.
    /// <br />
    /// en: Creates a new CPU instance without data memory. The ldind.i4
    /// and stind.i4 opcodes will raise InvalidMemoryAccess traps — use the
    /// <see cref="TCpuNano(byte[])"/> constructor for a data-memory variant.
    /// </summary>
    public TCpuNano()
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
    public TCpuNano(byte[]? ADataMemory)
        : this(ADataMemory, DefaultSramSize)
    {
    }

    /// <summary>
    /// hu: Új CPU példány létrehozása opcionális data memory tömbbel és
    /// egyedi SRAM mérettel. Kis SRAM méret hasznos a SramOverflow trap
    /// tesztelésére.
    /// <br />
    /// en: Creates a new CPU instance with an optional data memory array
    /// and a custom SRAM size. A small SRAM size is useful for testing the
    /// SramOverflow trap.
    /// </summary>
    /// <param name="ADataMemory">
    /// hu: A data memory byte-tömb, vagy <c>null</c> ha nincs.
    /// <br />
    /// en: The data memory byte array, or <c>null</c> if none.
    /// </param>
    /// <param name="ASramSize">
    /// hu: Az SRAM mérete bájtban.
    /// <br />
    /// en: The SRAM size in bytes.
    /// </param>
    public TCpuNano(byte[]? ADataMemory, int ASramSize)
    {
        FSram = new byte[ASramSize];
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
    public int StackDepth => FCallDepth == 0 ? 0 : EvalDepth;

    /// <summary>
    /// hu: Az aktuális hívási mélység (a call stack frame-jeinek száma).
    /// <br />
    /// en: Current call depth (number of frames in the call stack).
    /// </summary>
    public int CallDepth => FCallDepth;

    /// <summary>
    /// hu: Az aktuális stack pointer értéke az SRAM-ban (debug/hardware
    /// verification).
    /// <br />
    /// en: Current stack pointer value in SRAM (debug/hardware verification).
    /// </summary>
    public int Sp => FSp;

    /// <summary>
    /// hu: Az aktuális frame báziscíme az SRAM-ban (debug/hardware
    /// verification).
    /// <br />
    /// en: Current frame base address in SRAM (debug/hardware verification).
    /// </summary>
    public int FrameBase => FFrameBase;

    /// <summary>
    /// hu: Az SRAM mérete bájtban.
    /// <br />
    /// en: The SRAM size in bytes.
    /// </summary>
    public int SramSize => FSram.Length;

    /// <summary>
    /// hu: Az SRAM teljes tartalmának másolata (debug/hardware verification).
    /// <br />
    /// en: A copy of the full SRAM contents (debug/hardware verification).
    /// </summary>
    public byte[] SramSnapshot() => (byte[])FSram.Clone();

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
        if (FCallDepth == 0)
            throw new InvalidOperationException(
                "Cannot Peek: call stack is empty. Did you call Execute first?");

        return SramReadInt32(FSp - (AOffsetFromTop + 1) * 4);
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
    public void Execute(byte[] AProgram)
    {
        ArgumentNullException.ThrowIfNull(AProgram);
        InitRootFrame(0, 0, null);
        RunLoop(AProgram);
    }

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
        InitRootFrame(AArgCount, ALocalCount, AInitialArgs);
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

        InitRootFrame(header.ArgCount, header.LocalCount, AInitialArgs);
        FProgramCounter = AEntryRva + TMethodHeader.HeaderSize;

        RunLoop(AProgram);
    }

    /// <summary>
    /// hu: A root frame inicializálása az SRAM-ban. Minden Execute overload
    /// ezt hívja a futtatás megkezdése előtt.
    /// <br />
    /// en: Initializes the root frame in SRAM. All Execute overloads call
    /// this before starting execution.
    /// </summary>
    private void InitRootFrame(int AArgCount, int ALocalCount, int[]? AInitialArgs)
    {
        Array.Clear(FSram);
        FSp = 0;
        FFrameBase = 0;
        FCallDepth = 0;
        FProgramCounter = 0;
        FHalted = false;

        // hu: Root frame header
        // en: Root frame header
        SramWriteInt32(0 + OffsetReturnPc, -1);       // nincs return
        SramWriteInt32(0 + OffsetPrevFrameBase, -1);   // nincs előző frame
        FSram[0 + OffsetArgCount] = (byte)AArgCount;
        FSram[0 + OffsetLocalCount] = (byte)ALocalCount;
        // reserved [10..11] már 0

        FSp = FrameHeaderSize;  // 12

        // hu: Args írása
        // en: Write args
        if (AInitialArgs != null)
        {
            for (var i = 0; i < AInitialArgs.Length; i++)
                SramWriteInt32(FSp + i * 4, AInitialArgs[i]);
        }

        FSp += AArgCount * 4;

        // hu: Locals nullázása (SRAM már 0, de SP előre léptetése)
        // en: Zero locals (SRAM is already 0, but advance SP)
        FSp += ALocalCount * 4;

        FArgCount = AArgCount;
        FLocalCount = ALocalCount;
        FCallDepth = 1;
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
    protected virtual void RunLoop(byte[] AProgram)
    {
        while (!FHalted && FCallDepth > 0 && FProgramCounter < AProgram.Length)
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

        if (argCount > MaxArgs || localCount > MaxLocals)
            return false;

        AHeader = new TMethodHeader(TMethodHeader.MagicValue, argCount, localCount, maxStack, codeSize);

        return true;
    }

    // ------------------------------------------------------------------
    // hu: Belső SRAM helper-ek, amiket a TExecutor használ a CPU-állapot
    //     manipulációjához. Nem publikus — csak az assembly-n belül.
    // en: Internal SRAM helpers used by TExecutor to manipulate CPU state.
    //     Not public — only within the assembly.
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Egy 32-bites little-endian int olvasása az SRAM megadott címéről.
    /// <br />
    /// en: Reads a 32-bit little-endian int from the given SRAM address.
    /// </summary>
    /// <param name="AAddress">
    /// hu: Az SRAM cím (byte offset).
    /// <br />
    /// en: The SRAM address (byte offset).
    /// </param>
    internal int SramReadInt32(int AAddress)
    {
        return BitConverter.ToInt32(FSram, AAddress);
    }

    /// <summary>
    /// hu: Egy 32-bites little-endian int írása az SRAM megadott címére.
    /// <br />
    /// en: Writes a 32-bit little-endian int to the given SRAM address.
    /// </summary>
    /// <param name="AAddress">
    /// hu: Az SRAM cím (byte offset).
    /// <br />
    /// en: The SRAM address (byte offset).
    /// </param>
    /// <param name="AValue">
    /// hu: Az írandó int32 érték.
    /// <br />
    /// en: The int32 value to write.
    /// </param>
    internal void SramWriteInt32(int AAddress, int AValue)
    {
        BitConverter.TryWriteBytes(FSram.AsSpan(AAddress), AValue);
    }

    /// <summary>
    /// hu: Egy int32 érték push-olása az eval stack tetejére (az SRAM-ban).
    /// Ha a stack már MaxStackDepth mély, StackOverflow trap.
    /// <br />
    /// en: Pushes an int32 value onto the top of the eval stack (in SRAM).
    /// Raises a StackOverflow trap if the stack is already at MaxStackDepth.
    /// </summary>
    /// <param name="AValue">
    /// hu: A push-olandó érték.
    /// <br />
    /// en: The value to push.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal void EvalPush(int AValue, int APcForTrap)
    {
        if (EvalDepth >= MaxStackDepth)
            throw new TTrapException(TTrapReason.StackOverflow, APcForTrap,
                $"Evaluation stack overflow at PC=0x{APcForTrap:X4}.");

        SramWriteInt32(FSp, AValue);
        FSp += 4;
    }

    /// <summary>
    /// hu: A TOS elem kivétele az eval stack-ről (az SRAM-ban). Ha a stack
    /// üres, StackUnderflow trap.
    /// <br />
    /// en: Pops the TOS element from the eval stack (in SRAM). Raises a
    /// StackUnderflow trap if the stack is empty.
    /// </summary>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal int EvalPop(int APcForTrap)
    {
        if (EvalDepth <= 0)
            throw new TTrapException(TTrapReason.StackUnderflow, APcForTrap,
                $"Evaluation stack underflow at PC=0x{APcForTrap:X4}.");

        FSp -= 4;
        return SramReadInt32(FSp);
    }

    /// <summary>
    /// hu: Elem olvasása az eval stack tetejétől számolt offszettel (az
    /// SRAM-ban). <c>EvalPeek(0)</c> a TOS.
    /// <br />
    /// en: Reads an element from the eval stack at the given offset from the
    /// top (in SRAM). <c>EvalPeek(0)</c> is TOS.
    /// </summary>
    /// <param name="AOffsetFromTop">
    /// hu: Offszet a stack tetejétől (0 = TOS).
    /// <br />
    /// en: Offset from the top of the stack (0 = TOS).
    /// </param>
    internal int EvalPeek(int AOffsetFromTop)
    {
        if (AOffsetFromTop < 0 || AOffsetFromTop >= EvalDepth)
            throw new ArgumentOutOfRangeException(nameof(AOffsetFromTop),
                $"Offset {AOffsetFromTop} out of range for eval stack depth {EvalDepth}.");

        return SramReadInt32(FSp - (AOffsetFromTop + 1) * 4);
    }

    /// <summary>
    /// hu: Az eval stack aktuális mélysége (elemek száma) az SRAM-ban.
    /// <br />
    /// en: Current eval stack depth (element count) in SRAM.
    /// </summary>
    internal int EvalDepth
    {
        get
        {
            var evalBase = FFrameBase + FrameHeaderSize + FArgCount * 4 + FLocalCount * 4;
            return (FSp - evalBase) / 4;
        }
    }

    /// <summary>
    /// hu: Az aktuális frame argumentumainak száma.
    /// <br />
    /// en: Number of arguments in the current frame.
    /// </summary>
    internal int ArgCount => FArgCount;

    /// <summary>
    /// hu: Az aktuális frame lokális változóinak száma.
    /// <br />
    /// en: Number of local variables in the current frame.
    /// </summary>
    internal int LocalCount => FLocalCount;

    /// <summary>
    /// hu: Argumentum olvasása az SRAM-ból index alapján.
    /// <br />
    /// en: Loads an argument from SRAM by index.
    /// </summary>
    /// <param name="AIndex">
    /// hu: Az argumentum indexe (0-alapú).
    /// <br />
    /// en: The argument index (0-based).
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal int LoadArg(int AIndex, int APcForTrap)
    {
        if (AIndex < 0 || AIndex >= FArgCount)
            throw new TTrapException(TTrapReason.InvalidArg, APcForTrap,
                $"Invalid arg index {AIndex} at PC=0x{APcForTrap:X4}");

        return SramReadInt32(FFrameBase + FrameHeaderSize + AIndex * 4);
    }

    /// <summary>
    /// hu: Argumentum írása az SRAM-ba index alapján.
    /// <br />
    /// en: Stores a value into an argument in SRAM by index.
    /// </summary>
    /// <param name="AIndex">
    /// hu: Az argumentum indexe (0-alapú).
    /// <br />
    /// en: The argument index (0-based).
    /// </param>
    /// <param name="AValue">
    /// hu: Az írandó érték.
    /// <br />
    /// en: The value to store.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal void StoreArg(int AIndex, int AValue, int APcForTrap)
    {
        if (AIndex < 0 || AIndex >= FArgCount)
            throw new TTrapException(TTrapReason.InvalidArg, APcForTrap,
                $"Invalid arg index {AIndex} at PC=0x{APcForTrap:X4}");

        SramWriteInt32(FFrameBase + FrameHeaderSize + AIndex * 4, AValue);
    }

    /// <summary>
    /// hu: Lokális változó olvasása az SRAM-ból index alapján.
    /// <br />
    /// en: Loads a local variable from SRAM by index.
    /// </summary>
    /// <param name="AIndex">
    /// hu: A lokális változó indexe (0-alapú).
    /// <br />
    /// en: The local variable index (0-based).
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal int LoadLocal(int AIndex, int APcForTrap)
    {
        if (AIndex < 0 || AIndex >= FLocalCount)
            throw new TTrapException(TTrapReason.InvalidLocal, APcForTrap,
                $"Invalid local index {AIndex} at PC=0x{APcForTrap:X4}");

        return SramReadInt32(FFrameBase + FrameHeaderSize + FArgCount * 4 + AIndex * 4);
    }

    /// <summary>
    /// hu: Lokális változó írása az SRAM-ba index alapján.
    /// <br />
    /// en: Stores a value into a local variable in SRAM by index.
    /// </summary>
    /// <param name="AIndex">
    /// hu: A lokális változó indexe (0-alapú).
    /// <br />
    /// en: The local variable index (0-based).
    /// </param>
    /// <param name="AValue">
    /// hu: Az írandó érték.
    /// <br />
    /// en: The value to store.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal void StoreLocal(int AIndex, int AValue, int APcForTrap)
    {
        if (AIndex < 0 || AIndex >= FLocalCount)
            throw new TTrapException(TTrapReason.InvalidLocal, APcForTrap,
                $"Invalid local index {AIndex} at PC=0x{APcForTrap:X4}");

        SramWriteInt32(FFrameBase + FrameHeaderSize + FArgCount * 4 + AIndex * 4, AValue);
    }

    /// <summary>
    /// hu: Új hívási keret push-olása az SRAM-ba. A TExecutor a call
    /// opkódból hívja.
    /// <br />
    /// en: Pushes a new call frame onto SRAM. Called by TExecutor from the
    /// call opcode.
    /// </summary>
    /// <param name="AReturnPc">
    /// hu: A visszatérési PC (a call utáni opkód offszetje).
    /// <br />
    /// en: The return PC (offset of the opcode after the call).
    /// </param>
    /// <param name="AArgCount">
    /// hu: A callee argumentumainak száma.
    /// <br />
    /// en: The callee's argument count.
    /// </param>
    /// <param name="ALocalCount">
    /// hu: A callee lokális változóinak száma.
    /// <br />
    /// en: The callee's local variable count.
    /// </param>
    /// <param name="AArgs">
    /// hu: A callee argumentum értékei.
    /// <br />
    /// en: The callee's argument values.
    /// </param>
    /// <param name="APcForTrap">
    /// hu: A PC érték a trap-hez.
    /// <br />
    /// en: The PC value for the trap.
    /// </param>
    internal void PushCallFrame(int AReturnPc, int AArgCount, int ALocalCount, int[] AArgs, int APcForTrap)
    {
        if (FCallDepth >= MaxCallDepth)
            throw new TTrapException(TTrapReason.CallDepthExceeded, APcForTrap,
                $"Call depth would exceed {MaxCallDepth} at PC=0x{APcForTrap:X4}.");

        var frameSize = FrameHeaderSize + AArgCount * 4 + ALocalCount * 4;

        if (FSp + frameSize > FSram.Length)
            throw new TTrapException(TTrapReason.SramOverflow, APcForTrap,
                $"SRAM overflow at PC=0x{APcForTrap:X4}.");

        var newBase = FSp;

        // hu: Frame header
        // en: Frame header
        SramWriteInt32(newBase + OffsetReturnPc, AReturnPc);
        SramWriteInt32(newBase + OffsetPrevFrameBase, FFrameBase);
        FSram[newBase + OffsetArgCount] = (byte)AArgCount;
        FSram[newBase + OffsetLocalCount] = (byte)ALocalCount;

        // hu: Args
        // en: Args
        var argsOffset = newBase + FrameHeaderSize;

        for (var i = 0; i < AArgCount; i++)
            SramWriteInt32(argsOffset + i * 4, AArgs[i]);

        // hu: Locals (nullázás)
        // en: Locals (zero-fill)
        var localsOffset = argsOffset + AArgCount * 4;

        for (var i = 0; i < ALocalCount * 4; i++)
            FSram[localsOffset + i] = 0;

        FSp = localsOffset + ALocalCount * 4;
        FFrameBase = newBase;
        FArgCount = AArgCount;
        FLocalCount = ALocalCount;
        FCallDepth++;
    }

    /// <summary>
    /// hu: A legfelső hívási keret eltávolítása az SRAM-ból. Visszaadja a
    /// callee ReturnPC értékét. A TExecutor a ret opkódból hívja.
    /// <br />
    /// en: Pops the topmost call frame from SRAM. Returns the callee's
    /// ReturnPC value. Called by TExecutor from the ret opcode.
    /// </summary>
    internal int PopCallFrame()
    {
        var oldBase = FFrameBase;
        var returnPc = SramReadInt32(oldBase + OffsetReturnPc);
        var prevBase = SramReadInt32(oldBase + OffsetPrevFrameBase);

        FSp = oldBase;  // callee frame teljes SRAM-ja felszabadul
        FFrameBase = prevBase;

        if (prevBase >= 0)
        {
            FArgCount = FSram[prevBase + OffsetArgCount];
            FLocalCount = FSram[prevBase + OffsetLocalCount];
        }
        else
        {
            // hu: Root frame — az SRAM[0] header-ből olvassuk vissza.
            // en: Root frame — read back from SRAM[0] header.
            FArgCount = FSram[OffsetArgCount];
            FLocalCount = FSram[OffsetLocalCount];
        }

        FCallDepth--;
        return returnPc;
    }

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
