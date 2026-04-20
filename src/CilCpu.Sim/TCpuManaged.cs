namespace CilCpu.Sim;

/// <summary>
/// hu: Köztes CPU szint: CIL-T0 + managed referenciák (tömb, heap).
/// A TCpuNano-ból származik, és a TCpuSeal / TCpuActor közös bázisa.
/// Hozzáadja: newarr, ldlen, ldelem.u1, stelem.i1 opkódokat és a
/// heap memória modellt (felülről lefelé nő, a stack-kel szemben).
/// <br />
/// en: Intermediate CPU level: CIL-T0 + managed references (arrays, heap).
/// Extends TCpuNano, serves as common base for TCpuSeal / TCpuActor.
/// Adds: newarr, ldlen, ldelem.u1, stelem.i1 opcodes and the heap
/// memory model (grows downward, opposite to stack).
/// </summary>
public class TCpuManaged : TCpuNano
{
    /// <summary>
    /// hu: A null referencia értéke (0xFFFFFFFF).
    /// <br />
    /// en: The null reference value (0xFFFFFFFF).
    /// </summary>
    public const int NullRef = unchecked((int)0xFFFFFFFF);

    private int FHeapPointer;

    /// <summary>
    /// hu: Új TCpuManaged példány létrehozása.
    /// <br />
    /// en: Creates a new TCpuManaged instance.
    /// </summary>
    public TCpuManaged(int ASramSize = 65536)
        : base(null, ASramSize)
    {
        FHeapPointer = ASramSize;
    }

    /// <summary>
    /// hu: A heap pointer aktuális értéke (felülről lefelé nő).
    /// <br />
    /// en: Current heap pointer value (grows downward from top).
    /// </summary>
    public int HeapPointer => FHeapPointer;

    /// <summary>
    /// hu: Heap pointer beállítása (leszármazottak számára).
    /// <br />
    /// en: Set heap pointer (for subclasses).
    /// </summary>
    protected void SetHeapPointer(int AValue) => FHeapPointer = AValue;

    /// <summary>
    /// hu: A végrehajtási ciklus — a tömb opkódokat kezeli, a többit
    /// a TCpuNano TExecutor-ára delegálja.
    /// <br />
    /// en: The run loop — handles array opcodes, delegates the rest
    /// to TCpuNano's TExecutor.
    /// </summary>
    protected override void RunLoop(byte[] AProgram)
    {
        while (!FHalted && FCallDepth > 0 && FProgramCounter < AProgram.Length)
        {
            ExecuteStep(AProgram);
        }
    }

    /// <summary>
    /// hu: Egyetlen utasítás végrehajtása. A leszármazottak (pl. TCpuSeal)
    /// override-olhatják, hogy extra opkódokat kezeljenek (pl. CryptoCall).
    /// <br />
    /// en: Executes a single instruction. Subclasses (e.g. TCpuSeal) can
    /// override to handle extra opcodes (e.g. CryptoCall).
    /// </summary>
    protected virtual void ExecuteStep(byte[] AProgram)
    {
        var opcode = AProgram[FProgramCounter];

        if (opcode is 0x8D or 0x8E or 0x90 or 0x91 or 0x9C)
        {
            ExecuteArrayOpcode(AProgram, opcode);
        }
        else if (opcode is 0x69 or 0x6D or 0xD3)
        {
            // hu: conv.u / conv.i4 / conv.u4 — nop int32-only rendszerben
            // en: conv.u / conv.i4 / conv.u4 — nop in int32-only system
            FProgramCounter++;
        }
        else
        {
            var decoded = TDecoder.Decode(AProgram, FProgramCounter);
            TExecutor.Execute(this, AProgram, decoded);
        }
    }

    private void ExecuteArrayOpcode(byte[] AProgram, byte AOpcode)
    {
        var pc = FProgramCounter;

        switch (AOpcode)
        {
            case 0x8D: // newarr <token> (5 byte: opcode + 4 byte token ignored)
                ExecuteNewarr(pc);
                FProgramCounter = pc + 5;
                break;

            case 0x8E: // ldlen (1 byte)
                ExecuteLdlen(pc);
                FProgramCounter = pc + 1;
                break;

            case 0x90: // ldelem.u1 (1 byte) — zero-extended
                ExecuteLdelemU1(pc);
                FProgramCounter = pc + 1;
                break;

            case 0x91: // ldelem.i1 (1 byte) — sign-extended
                ExecuteLdelemI1(pc);
                FProgramCounter = pc + 1;
                break;

            case 0x9C: // stelem.i1 (1 byte)
                ExecuteStelemI1(pc);
                FProgramCounter = pc + 1;
                break;
        }
    }

    private void ExecuteNewarr(int APc)
    {
        var length = EvalPop(APc);

        if (length < 0)
            throw new TTrapException(TTrapReason.NegativeArraySize, APc,
                $"newarr with negative size {length} at PC=0x{APc:X4}.");

        // hu: Allokáció: 4 byte length header + data (4-byte aligned)
        // en: Allocation: 4 byte length header + data (4-byte aligned)
        var dataSize = (length + 3) & ~3; // 4-byte alignment
        var totalSize = 4 + dataSize;

        var newHp = FHeapPointer - totalSize;

        if (newHp <= FSp)
            throw new TTrapException(TTrapReason.SramOverflow, APc,
                $"Heap/stack collision at PC=0x{APc:X4}.");

        FHeapPointer = newHp;

        // hu: Length mező írása a heap-re
        // en: Write length field to heap
        SramWriteInt32(newHp, length);

        // hu: Adat nullázása (SRAM lehet nem tiszta)
        // en: Zero data (SRAM may not be clean)
        for (var i = 4; i < totalSize; i++)
            FSram[newHp + i] = 0;

        // hu: Referencia (heap cím) push a stackre
        // en: Push reference (heap address) onto stack
        EvalPush(newHp, APc);
    }

    private void ExecuteLdlen(int APc)
    {
        var arrayRef = EvalPop(APc);

        if (arrayRef == NullRef)
            throw new TTrapException(TTrapReason.NullReference, APc,
                $"ldlen on null reference at PC=0x{APc:X4}.");

        var length = SramReadInt32(arrayRef);
        EvalPush(length, APc);
    }

    private void ExecuteLdelemU1(int APc)
    {
        var index = EvalPop(APc);
        var arrayRef = EvalPop(APc);

        if (arrayRef == NullRef)
            throw new TTrapException(TTrapReason.NullReference, APc,
                $"ldelem.u1 on null reference at PC=0x{APc:X4}.");

        var length = SramReadInt32(arrayRef);

        if (index < 0 || index >= length)
            throw new TTrapException(TTrapReason.IndexOutOfRange, APc,
                $"ldelem.u1 index {index} out of range [0..{length - 1}] at PC=0x{APc:X4}.");

        var value = FSram[arrayRef + 4 + index];
        EvalPush(value, APc);
    }

    private void ExecuteLdelemI1(int APc)
    {
        var index = EvalPop(APc);
        var arrayRef = EvalPop(APc);

        if (arrayRef == NullRef)
            throw new TTrapException(TTrapReason.NullReference, APc,
                $"ldelem.i1 on null reference at PC=0x{APc:X4}.");

        var length = SramReadInt32(arrayRef);

        if (index < 0 || index >= length)
            throw new TTrapException(TTrapReason.IndexOutOfRange, APc,
                $"ldelem.i1 index {index} out of range [0..{length - 1}] at PC=0x{APc:X4}.");

        var value = (int)(sbyte)FSram[arrayRef + 4 + index]; // sign-extended
        EvalPush(value, APc);
    }

    private void ExecuteStelemI1(int APc)
    {
        var value = EvalPop(APc);
        var index = EvalPop(APc);
        var arrayRef = EvalPop(APc);

        if (arrayRef == NullRef)
            throw new TTrapException(TTrapReason.NullReference, APc,
                $"stelem.i1 on null reference at PC=0x{APc:X4}.");

        var length = SramReadInt32(arrayRef);

        if (index < 0 || index >= length)
            throw new TTrapException(TTrapReason.IndexOutOfRange, APc,
                $"stelem.i1 index {index} out of range [0..{length - 1}] at PC=0x{APc:X4}.");

        FSram[arrayRef + 4 + index] = (byte)(value & 0xFF);
    }
}
