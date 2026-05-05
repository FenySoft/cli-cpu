namespace CilCpu.Sim;

/// <summary>
/// hu: Egy CIL-T0 utasítás végrehajtása ELŐTTI gép-állapot snapshot-ja.
/// A <see cref="TCpuNanoTracer"/> minden lépés előtt egy ilyen entry-t
/// rögzít, az F2.5b golden vector harness alapja: az RTL belső jeleinek
/// (r_pc, r_sp, r_fp, r_call_depth, r_arg_count, r_local_count) lépésről-
/// lépésre összevetése a C# szimulátor (TCpuNano) aranypéldájával.
/// <br />
/// en: Snapshot of the machine state taken BEFORE executing one CIL-T0
/// instruction. <see cref="TCpuNanoTracer"/> records one entry per step,
/// forming the basis of the F2.5b golden vector harness — comparing the
/// RTL internal signals (r_pc, r_sp, r_fp, r_call_depth, r_arg_count,
/// r_local_count) step-by-step against the C# simulator (TCpuNano) golden
/// reference.
/// </summary>
/// <param name="Step">
/// hu: A lépés sorszáma (0-tól indulva).
/// <br />
/// en: Step index (0-based).
/// </param>
/// <param name="Pc">
/// hu: A program counter (a végrehajtandó utasítás byte-címe).
/// <br />
/// en: Program counter (byte address of the instruction to execute).
/// </param>
/// <param name="Sp">
/// hu: A frame END byte-címe az SRAM-ban (NEM az eval_top!). Az F2.5a HW
/// konvenció szerint <c>Sp = Fp + 12 + arg_count*4 + local_count*4</c> és
/// <b>nem mozdul</b> a stack műveletek hatására — a Stack Cache külön
/// kezeli az eval mélységet (lásd <see cref="EvalDepth"/>). A C# TCpuNano
/// belső <c>FSp</c>-je az eval_top-ra mutat, de a tracer ezt
/// <c>FSp - EvalDepth * 4</c>-re normalizálja, hogy közvetlenül
/// összevethető legyen az RTL <c>r_sp</c>-jével. Az eval_top a fogyasztó
/// oldalon kiszámolható: <c>Sp + EvalDepth * 4</c>.
/// <br />
/// en: Frame END byte address in SRAM (NOT eval_top!). Per F2.5a HW
/// convention, <c>Sp = Fp + 12 + arg_count*4 + local_count*4</c> and
/// <b>does not move</b> on stack ops — Stack Cache tracks eval depth
/// separately (see <see cref="EvalDepth"/>). C# TCpuNano's internal
/// <c>FSp</c> points to eval_top, but the tracer normalizes via
/// <c>FSp - EvalDepth * 4</c> for direct comparison with RTL <c>r_sp</c>.
/// Eval_top can be recomputed downstream as <c>Sp + EvalDepth * 4</c>.
/// </param>
/// <param name="Fp">
/// hu: A frame pointer (az aktuális frame kezdő byte-címe az SRAM-ban).
/// <br />
/// en: Frame pointer (start byte address of the current frame in SRAM).
/// </param>
/// <param name="CallDepth">
/// hu: A hívási mélység (root frame-en 1).
/// <br />
/// en: Call depth (1 on the root frame).
/// </param>
/// <param name="ArgCount">
/// hu: Az aktuális frame argumentum-darabszáma.
/// <br />
/// en: Argument count of the current frame.
/// </param>
/// <param name="LocalCount">
/// hu: Az aktuális frame lokális változó-darabszáma.
/// <br />
/// en: Local variable count of the current frame.
/// </param>
/// <param name="EvalDepth">
/// hu: Az eval stack mélysége (0..64) az utasítás VÉGREHAJTÁSA ELŐTT.
/// <br />
/// en: Eval stack depth (0..64) BEFORE the instruction is executed.
/// </param>
/// <param name="Opcode">
/// hu: A végrehajtandó opkód byte-ja (a fő opcode byte; a 0xFE prefixált
/// opkódoknál a következő byte; a CIL-T0 alszet-ben nincs prefixált opkód,
/// így ez mindig az 1-byte opcode).
/// <br />
/// en: The opcode byte of the instruction to execute.
/// </param>
/// <param name="Operand">
/// hu: A dekódolt operandus értéke (32-bit). Ha az opkód operandus nélküli,
/// 0. Branch opkódoknál a sign-extended offset; LDC.I4-nél a 4-byte LE
/// érték; LDC.I4.S-nél az sign-extended 8-bit érték; CALL-nál a target RVA.
/// <br />
/// en: Decoded operand value (32-bit). 0 for operand-less opcodes.
/// </param>
/// <param name="LengthInBytes">
/// hu: Az utasítás teljes hossza byte-ban (1..5).
/// <br />
/// en: Total instruction length in bytes (1..5).
/// </param>
public sealed record TCpuTraceEntry(
    int Step,
    int Pc,
    int Sp,
    int Fp,
    int CallDepth,
    int ArgCount,
    int LocalCount,
    int EvalDepth,
    byte Opcode,
    int Operand,
    int LengthInBytes);
