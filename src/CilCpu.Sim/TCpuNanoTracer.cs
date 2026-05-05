namespace CilCpu.Sim;

/// <summary>
/// hu: A <see cref="TCpuNano"/> alosztálya, amely minden CIL-T0 utasítás
/// VÉGREHAJTÁSA ELŐTT egy <see cref="TCpuTraceEntry"/>-t rögzít a fő
/// futási loopban. A trace az F2.5b golden vector harness alapja: a
/// cocotb tesztek beolvassák ezt a sorozatot, indítják az RTL-t a megadott
/// programmal, és lépésről-lépésre összevetik az RTL belső jeleit
/// (r_pc, r_sp, r_fp, r_call_depth, r_arg_count, r_local_count) az itt
/// rögzített aranypéldával.
/// <br />
/// en: A subclass of <see cref="TCpuNano"/> that records a
/// <see cref="TCpuTraceEntry"/> snapshot BEFORE every CIL-T0 instruction
/// in the main execution loop. The trace is the foundation of the F2.5b
/// golden vector harness: cocotb tests parse this sequence, drive the RTL
/// with the same program, and compare RTL internal signals (r_pc, r_sp,
/// r_fp, r_call_depth, r_arg_count, r_local_count) step-by-step against
/// this golden reference.
/// </summary>
public class TCpuNanoTracer : TCpuNano
{
    private readonly List<TCpuTraceEntry> FEntries = new();

    /// <summary>
    /// hu: Új tracer adatmemória nélkül.
    /// <br />
    /// en: New tracer with no data memory.
    /// </summary>
    public TCpuNanoTracer()
        : base()
    {
    }

    /// <summary>
    /// hu: Új tracer a megadott data memóriával (ldind.i4 / stind.i4 ehhez fér).
    /// <br />
    /// en: New tracer with the given data memory (used by ldind.i4 / stind.i4).
    /// </summary>
    public TCpuNanoTracer(byte[]? ADataMemory)
        : base(ADataMemory)
    {
    }

    /// <summary>
    /// hu: Új tracer egyedi SRAM mérettel (alapértelmezetten 16 KB).
    /// <br />
    /// en: New tracer with a custom SRAM size (default 16 KB).
    /// </summary>
    public TCpuNanoTracer(byte[]? ADataMemory, int ASramSize)
        : base(ADataMemory, ASramSize)
    {
    }

    /// <summary>
    /// hu: A rögzített trace-bejegyzések, az első futtatott utasítástól
    /// (Step 0) az utolsóig (a halt vagy trap előtti utasításig). Új
    /// <c>Execute</c> hívás NEM törli az előző trace-t — több futás
    /// trace-e ugyanabba a listába gyűlik (a Step indexelés folytonos).
    /// <br />
    /// en: Recorded trace entries, from the first executed instruction
    /// (Step 0) to the last (the instruction before halt/trap). A new
    /// <c>Execute</c> call does NOT clear the previous trace — multiple
    /// runs accumulate in the same list (Step indexing remains continuous).
    /// </summary>
    public IReadOnlyList<TCpuTraceEntry> Entries => FEntries;

    /// <summary>
    /// hu: A trace-lista törlése — a következő <c>Execute</c> hívás 0-tól
    /// kezdi a Step indexelést.
    /// <br />
    /// en: Clears the trace list — the next <c>Execute</c> starts Step
    /// indexing from 0.
    /// </summary>
    public void ClearTrace() => FEntries.Clear();

    /// <summary>
    /// hu: A fő végrehajtási loop felüldefiniálva: minden utasítás
    /// dekódolása UTÁN, de a végrehajtás ELŐTT egy <see cref="TCpuTraceEntry"/>-t
    /// rögzít a teljes gép-állapottal. A halt/trap utáni állapot nem
    /// kerül a trace-be.
    /// <br />
    /// en: Overrides the main execution loop: after each instruction is
    /// decoded but BEFORE it executes, records a <see cref="TCpuTraceEntry"/>
    /// with the full machine state. State after halt/trap is not recorded.
    /// </summary>
    protected override void RunLoop(byte[] AProgram)
    {
        var step = FEntries.Count;

        while (!FHalted && FCallDepth > 0 && FProgramCounter < AProgram.Length)
        {
            var decoded = TDecoder.Decode(AProgram, FProgramCounter);

            // hu: Sp = frame_end (RTL r_sp konvenció, nem az eval_top).
            //     A C# TCpuNano FSp az eval_top-ra mutat (EvalPush növeli),
            //     az RTL r_sp viszont a frame VÉGÉT jelöli, és nem mozdul a
            //     stack műveletek hatására (a Stack Cache külön kezeli az
            //     eval mélységet). A trace-be a frame_end-t írjuk, hogy a
            //     cocotb golden harness közvetlenül összevethesse az r_sp-vel.
            //     Az eval_top a fogyasztó oldalon kiszámolható: sp + ed*4.
            // en: Sp = frame_end (matches RTL r_sp convention, not the C#
            //     eval_top). C# TCpuNano's FSp tracks eval_top (grows with
            //     EvalPush), but RTL r_sp denotes the frame END and is
            //     immutable across stack ops (the Stack Cache tracks eval
            //     depth separately). The trace records frame_end so the
            //     cocotb golden harness can compare directly to r_sp. The
            //     consumer can recompute eval_top via sp + ed*4.
            var frameEnd = FSp - EvalDepth * 4;

            FEntries.Add(new TCpuTraceEntry(
                Step: step,
                Pc: FProgramCounter,
                Sp: frameEnd,
                Fp: FFrameBase,
                CallDepth: FCallDepth,
                ArgCount: FArgCount,
                LocalCount: FLocalCount,
                EvalDepth: EvalDepth,
                Opcode: AProgram[FProgramCounter],
                Operand: decoded.Operand,
                LengthInBytes: decoded.LengthInBytes));

            TExecutor.Execute(this, AProgram, decoded);
            step++;
        }
    }
}
