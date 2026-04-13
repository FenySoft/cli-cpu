namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 utasítás-végrehajtó. A <see cref="TCpu"/> dekódolás után
/// ennek az osztálynak adja át a vezérlést egy-egy utasításra. A végrehajtó
/// felelős a stack manipulációért, az aritmetikáért, összehasonlításokért,
/// elágazásokért és a lokális/argumentum hozzáférésért. A trap sorrend
/// (pl. index-ellenőrzés megelőzi a stack-hozzáférést <c>stloc.s</c>-nél,
/// lásd <c>docs/ISA-CIL-T0.md</c>) itt van rögzítve.
/// <br />
/// en: CIL-T0 instruction executor. After decoding, <see cref="TCpu"/>
/// delegates each instruction to this class. The executor is responsible
/// for stack manipulation, arithmetic, comparisons, branches, and local/
/// argument access. Trap ordering (e.g. index check precedes stack access
/// for <c>stloc.s</c>, see <c>docs/ISA-CIL-T0.md</c>) is pinned down here.
/// </summary>
internal static class TExecutor
{
    /// <summary>
    /// hu: Egyetlen dekódolt utasítás végrehajtása a megadott CPU állapoton.
    /// A metódus csak a trap feltételeket lehet, hogy dob — minden egyéb
    /// állapotváltozás a TCpu belső referenciáin keresztül történik.
    /// A PC frissítése itt történik: branch opkódoknál a számolt target
    /// offszet, minden más opkódnál a dekódolt utasítás hossza.
    /// <br />
    /// en: Executes a single decoded instruction on the given CPU state.
    /// The method may only raise trap exceptions — all other state changes
    /// happen via the TCpu internal references. The PC is updated here:
    /// to the computed target offset for branch opcodes, or advanced by
    /// the decoded instruction length for everything else.
    /// </summary>
    /// <param name="ACpu">
    /// hu: A CPU példány, amelynek állapotán dolgozunk.
    /// <br />
    /// en: The CPU instance whose state we operate on.
    /// </param>
    /// <param name="AProgram">
    /// hu: A futtatott program byte-tömbje (a branch target ellenőrzéshez).
    /// <br />
    /// en: The program byte array being executed (used for branch target checks).
    /// </param>
    /// <param name="ADecoded">
    /// hu: A dekódolt utasítás (opkód, hossz, operandus).
    /// <br />
    /// en: The decoded instruction (opcode, length, operand).
    /// </param>
    public static void Execute(TCpu ACpu, byte[] AProgram, TDecodedOpcode ADecoded)
    {
        var pc = ACpu.Pc;

        switch (ADecoded.Opcode)
        {
            case TOpcode.Nop:
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- argumentum load -----
            case TOpcode.Ldarg0:
                LoadArg(ACpu, 0);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldarg1:
                LoadArg(ACpu, 1);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldarg2:
                LoadArg(ACpu, 2);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldarg3:
                LoadArg(ACpu, 3);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdargS:
                LoadArg(ACpu, ADecoded.Operand);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.StargS:
                StoreArg(ACpu, ADecoded.Operand);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- lokális load -----
            case TOpcode.Ldloc0:
                LoadLocal(ACpu, 0);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldloc1:
                LoadLocal(ACpu, 1);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldloc2:
                LoadLocal(ACpu, 2);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Ldloc3:
                LoadLocal(ACpu, 3);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdlocS:
                LoadLocal(ACpu, ADecoded.Operand);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- lokális store -----
            case TOpcode.Stloc0:
                StoreLocal(ACpu, 0);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Stloc1:
                StoreLocal(ACpu, 1);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Stloc2:
                StoreLocal(ACpu, 2);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.Stloc3:
                StoreLocal(ACpu, 3);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.StlocS:
                StoreLocal(ACpu, ADecoded.Operand);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- konstansok -----
            case TOpcode.Ldnull:
            case TOpcode.LdcI40:
                ACpu.EvalPush(0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI4M1:
                ACpu.EvalPush(-1, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI41:
                ACpu.EvalPush(1, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI42:
                ACpu.EvalPush(2, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI43:
                ACpu.EvalPush(3, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI44:
                ACpu.EvalPush(4, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI45:
                ACpu.EvalPush(5, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI46:
                ACpu.EvalPush(6, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI47:
                ACpu.EvalPush(7, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI48:
                ACpu.EvalPush(8, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            case TOpcode.LdcI4S:
            case TOpcode.LdcI4:
                ACpu.EvalPush(ADecoded.Operand, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- stack manipuláció -----
            case TOpcode.Dup:
            {
                // hu: Dup: először underflow check (EvalPeek dob ha üres),
                //     aztán overflow check (EvalPush dob ha tele).
                // en: Dup: underflow check first (EvalPeek throws if empty),
                //     then overflow check (EvalPush throws if full).
                if (ACpu.EvalDepth <= 0)
                    throw new TTrapException(TTrapReason.StackUnderflow, pc);

                if (ACpu.EvalDepth >= TCpu.MaxStackDepth)
                    throw new TTrapException(TTrapReason.StackOverflow, pc);

                ACpu.EvalPush(ACpu.EvalPeek(0), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Pop:
                ACpu.EvalPop(pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;

            // ----- aritmetika (binary) -----
            case TOpcode.Add:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(unchecked(a + b), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Sub:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(unchecked(a - b), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Mul:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(unchecked(a * b), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Div:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (b == 0)
                    throw new TTrapException(TTrapReason.DivByZero, pc,
                        $"div by zero at PC=0x{pc:X4}");

                if (a == int.MinValue && b == -1)
                    throw new TTrapException(TTrapReason.Overflow, pc,
                        $"div INT_MIN / -1 at PC=0x{pc:X4}");

                ACpu.EvalPush(a / b, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Rem:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (b == 0)
                    throw new TTrapException(TTrapReason.DivByZero, pc,
                        $"rem by zero at PC=0x{pc:X4}");

                // hu: INT_MIN % -1 → 0 (nem overflow a spec szerint).
                // en: INT_MIN % -1 → 0 (no overflow per spec).
                var result = (a == int.MinValue && b == -1) ? 0 : a % b;
                ACpu.EvalPush(result, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.And:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a & b, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Or:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a | b, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Xor:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a ^ b, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Shl:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a << (b & 31), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Shr:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a >> (b & 31), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.ShrUn:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                var logical = (int)((uint)a >> (b & 31));
                ACpu.EvalPush(logical, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            // ----- aritmetika (unary) -----
            case TOpcode.Neg:
            {
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(unchecked(-a), pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Not:
            {
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(~a, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            // ----- összehasonlítások -----
            case TOpcode.Ceq:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a == b ? 1 : 0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Cgt:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a > b ? 1 : 0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.CgtUn:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush((uint)a > (uint)b ? 1 : 0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.Clt:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush(a < b ? 1 : 0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            case TOpcode.CltUn:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);
                ACpu.EvalPush((uint)a < (uint)b ? 1 : 0, pc);
                ACpu.Pc = pc + ADecoded.LengthInBytes;
                return;
            }

            // ----- rövid branch-ek -----
            case TOpcode.BrS:
                ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                return;

            case TOpcode.BrfalseS:
            {
                var v = ACpu.EvalPop(pc);

                if (v == 0)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BrtrueS:
            {
                var v = ACpu.EvalPop(pc);

                if (v != 0)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BeqS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a == b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BgeS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a >= b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BgtS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a > b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BleS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a <= b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BltS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a < b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            case TOpcode.BneUnS:
            {
                var b = ACpu.EvalPop(pc);
                var a = ACpu.EvalPop(pc);

                if (a != b)
                    ACpu.Pc = ComputeBranchTarget(AProgram, pc, ADecoded.LengthInBytes, ADecoded.Operand);
                else
                    ACpu.Pc = pc + ADecoded.LengthInBytes;

                return;
            }

            // ----- iteráció 4: hívás / visszatérés -----
            case TOpcode.Call:
                ExecuteCall(ACpu, AProgram, ADecoded, pc);
                return;

            case TOpcode.Ret:
                ExecuteRet(ACpu, pc);
                return;

            // ----- iteráció 4: indirekt memória -----
            case TOpcode.LdindI4:
                ExecuteLdindI4(ACpu, pc);
                return;

            case TOpcode.StindI4:
                ExecuteStindI4(ACpu, pc);
                return;

            // ----- iteráció 4: egyéb -----
            case TOpcode.Break:
                throw new TTrapException(TTrapReason.DebugBreak, pc,
                    $"break opcode at PC=0x{pc:X4}");

            default:
                throw new TTrapException(TTrapReason.InvalidOpcode, pc,
                    $"Unhandled opcode {ADecoded.Opcode} at PC=0x{pc:X4}");
        }
    }

    /// <summary>
    /// hu: A <c>call</c> opkód végrehajtása. A 4 bájtos operandus a callee
    /// metódus header-jének RVA-ja a programban. A header beolvasása után
    /// a hívási mélységet ellenőrizzük, létrehozzuk az új frame-et a header
    /// arg/local count-jával, majd a callee argumentumait pop-oljuk a
    /// caller eval stack-jéből (jobbról balra: TOS = utolsó arg) és
    /// push-oljuk az új SRAM frame-be. A return PC = a call utáni opkód
    /// offszetje.
    /// <br />
    /// en: Executes the <c>call</c> opcode. The 4-byte operand is the RVA
    /// of the callee method header. After reading the header we pop callee
    /// arguments from the caller's eval stack (right to left: TOS = last
    /// arg) and push a new SRAM frame. Return PC = offset of the opcode
    /// after the call.
    /// </summary>
    private static void ExecuteCall(TCpu ACpu, byte[] AProgram, TDecodedOpcode ADecoded, int APc)
    {
        var targetRva = ADecoded.Operand;

        if (targetRva < 0 || targetRva + TMethodHeader.HeaderSize > AProgram.Length)
            throw new TTrapException(TTrapReason.InvalidCallTarget, APc,
                $"call target RVA=0x{targetRva:X4} out of program bounds at PC=0x{APc:X4}.");

        if (AProgram[targetRva] != TMethodHeader.MagicValue)
            throw new TTrapException(TTrapReason.InvalidCallTarget, APc,
                $"call target RVA=0x{targetRva:X4} has invalid header magic at PC=0x{APc:X4}.");

        var argCount = AProgram[targetRva + 1];
        var localCount = AProgram[targetRva + 2];
        var codeSize = (ushort)(AProgram[targetRva + 4] | (AProgram[targetRva + 5] << 8));

        if (argCount > TCpu.MaxArgs || localCount > TCpu.MaxLocals)
            throw new TTrapException(TTrapReason.InvalidCallTarget, APc,
                $"call target RVA=0x{targetRva:X4} has invalid arg/local count at PC=0x{APc:X4}.");

        if (targetRva + TMethodHeader.HeaderSize + codeSize > AProgram.Length)
            throw new TTrapException(TTrapReason.InvalidCallTarget, APc,
                $"call target RVA=0x{targetRva:X4} code extends past program end at PC=0x{APc:X4}.");

        // hu: Pop az argumentumokat fordítva (TOS = utolsó arg).
        // en: Pop arguments in reverse (TOS = last arg).
        var args = new int[argCount];

        for (var i = argCount - 1; i >= 0; i--)
            args[i] = ACpu.EvalPop(APc);

        // hu: Push a callee frame-et az SRAM-ba.
        // en: Push the callee frame onto SRAM.
        var returnPc = APc + ADecoded.LengthInBytes;
        ACpu.PushCallFrame(returnPc, argCount, localCount, args, APc);
        ACpu.Pc = targetRva + TMethodHeader.HeaderSize;
    }

    /// <summary>
    /// hu: A <c>ret</c> opkód végrehajtása. Ha a callee eval stackjén
    /// legalább egy érték van, az lesz a return value. Root frame esetén
    /// megállítjuk a CPU-t; egyébként a return value-t a caller eval
    /// stack-jére push-oljuk.
    /// <br />
    /// en: Executes the <c>ret</c> opcode. If the callee's eval stack
    /// holds at least one value it becomes the return value. For the root
    /// frame we halt the CPU; otherwise the return value is pushed onto
    /// the caller's eval stack.
    /// </summary>
    private static void ExecuteRet(TCpu ACpu, int APc)
    {
        var hasReturnValue = ACpu.EvalDepth >= 1;
        var returnValue = hasReturnValue ? ACpu.EvalPop(APc) : 0;

        // hu: Root frame esetén nem pop-olunk, hanem leállítjuk a CPU-t és
        //     a return value-t a frame stackjére visszahelyezzük, hogy a
        //     teszt Peek-kel láthassa.
        // en: For the root frame we don't pop; we halt the CPU and put the
        //     return value back on the frame stack so tests can Peek it.
        if (ACpu.CallDepth == 1)
        {
            if (hasReturnValue)
                ACpu.EvalPush(returnValue, APc);

            ACpu.Halt();
            return;
        }

        var returnPc = ACpu.PopCallFrame();

        if (hasReturnValue)
            ACpu.EvalPush(returnValue, APc);

        ACpu.Pc = returnPc;
    }

    /// <summary>
    /// hu: A <c>ldind.i4</c> opkód: pop a TOS címet, olvas egy 32-bit LE
    /// int-et a data memory-ból, push az eredményt. Ha nincs data memory
    /// vagy a cím a tartomány kívülre esik,
    /// <see cref="TTrapReason.InvalidMemoryAccess"/> trap. Az F2 RTL ezt
    /// a hardveres memory controller hibájának fogja értelmezni.
    /// <br />
    /// en: <c>ldind.i4</c>: pop the TOS address, read a 32-bit LE int from
    /// data memory, push the result. If no data memory is configured or
    /// the address is out of bounds, raises an
    /// <see cref="TTrapReason.InvalidMemoryAccess"/> trap. The F2 RTL will
    /// treat this as a memory controller fault.
    /// </summary>
    private static void ExecuteLdindI4(TCpu ACpu, int APc)
    {
        var data = ACpu.DataMemory;

        if (data is null)
            throw new TTrapException(TTrapReason.InvalidMemoryAccess, APc,
                $"ldind.i4 with no data memory at PC=0x{APc:X4}.");

        var addr = ACpu.EvalPop(APc);

        if (addr < 0 || (long)addr + 4 > data.Length)
            throw new TTrapException(TTrapReason.InvalidMemoryAccess, APc,
                $"ldind.i4 address 0x{addr:X8} out of data memory bounds at PC=0x{APc:X4}.");

        var value = data[addr]
            | (data[addr + 1] << 8)
            | (data[addr + 2] << 16)
            | (data[addr + 3] << 24);

        ACpu.EvalPush(value, APc);
        ACpu.Pc = APc + 1;
    }

    /// <summary>
    /// hu: A <c>stind.i4</c> opkód: pop érték, pop cím, ír egy 32-bit LE
    /// int-et a data memory-ba. Ha nincs data memory vagy a cím a tartomány
    /// kívülre esik, <see cref="TTrapReason.InvalidMemoryAccess"/> trap.
    /// <br />
    /// en: <c>stind.i4</c>: pop value, pop address, write a 32-bit LE int
    /// to data memory. Out-of-bounds or no-memory raises an
    /// <see cref="TTrapReason.InvalidMemoryAccess"/> trap.
    /// </summary>
    private static void ExecuteStindI4(TCpu ACpu, int APc)
    {
        var data = ACpu.DataMemory;

        if (data is null)
            throw new TTrapException(TTrapReason.InvalidMemoryAccess, APc,
                $"stind.i4 with no data memory at PC=0x{APc:X4}.");

        var value = ACpu.EvalPop(APc);
        var addr = ACpu.EvalPop(APc);

        if (addr < 0 || (long)addr + 4 > data.Length)
            throw new TTrapException(TTrapReason.InvalidMemoryAccess, APc,
                $"stind.i4 address 0x{addr:X8} out of data memory bounds at PC=0x{APc:X4}.");

        data[addr] = (byte)(value & 0xFF);
        data[addr + 1] = (byte)((value >> 8) & 0xFF);
        data[addr + 2] = (byte)((value >> 16) & 0xFF);
        data[addr + 3] = (byte)((value >> 24) & 0xFF);

        ACpu.Pc = APc + 1;
    }

    /// <summary>
    /// hu: Branch target kiszámítása: a branch target PC = (kezdő PC + utasítás hossz + signed offset).
    /// Ha a cél kívül esik a <c>[0, AProgram.Length]</c> zárt tartományon,
    /// <see cref="TTrapReason.InvalidBranchTarget"/> trap-et dob. A program
    /// vége (<c>AProgram.Length</c>) érvényes cél — ez a normál fallthrough-nál
    /// is előfordulhat, a végrehajtási ciklus ott természetesen leáll.
    /// <br />
    /// en: Computes branch target PC = (start PC + instruction length + signed offset).
    /// Raises <see cref="TTrapReason.InvalidBranchTarget"/> if the target lies
    /// outside the closed range <c>[0, AProgram.Length]</c>. The end-of-program
    /// value (<c>AProgram.Length</c>) is a valid target — it also occurs for a
    /// normal fall-through and the executor loop stops there naturally.
    /// </summary>
    private static int ComputeBranchTarget(byte[] AProgram, int APcBeforeBranch, int ALengthInBytes, int AOffset)
    {
        var fallThrough = APcBeforeBranch + ALengthInBytes;
        var target = fallThrough + AOffset;

        if (target < 0 || target > AProgram.Length)
            throw new TTrapException(TTrapReason.InvalidBranchTarget, APcBeforeBranch,
                $"Branch target 0x{target:X4} out of range [0, 0x{AProgram.Length:X4}] at PC=0x{APcBeforeBranch:X4}");

        return target;
    }

    /// <summary>
    /// hu: Lokális változó push a stack-re. Érvénytelen index esetén
    /// <see cref="TTrapReason.InvalidLocal"/> trap.
    /// <br />
    /// en: Pushes a local variable onto the stack. Invalid index raises
    /// <see cref="TTrapReason.InvalidLocal"/>.
    /// </summary>
    private static void LoadLocal(TCpu ACpu, int AIndex)
    {
        if (AIndex < 0 || AIndex >= TCpu.MaxLocals || AIndex >= ACpu.LocalCount)
            throw new TTrapException(TTrapReason.InvalidLocal, ACpu.Pc,
                $"Invalid local index {AIndex} at PC=0x{ACpu.Pc:X4}");

        var value = ACpu.LoadLocal(AIndex, ACpu.Pc);
        ACpu.EvalPush(value, ACpu.Pc);
    }

    /// <summary>
    /// hu: TOS pop → lokális változó. <b>Trap sorrend:</b> először index
    /// ellenőrzés (<see cref="TTrapReason.InvalidLocal"/>), csak utána pop
    /// (<see cref="TTrapReason.StackUnderflow"/>). Az invalid index mindig
    /// megelőzi a stack underflow-t — lásd <c>docs/ISA-CIL-T0.md</c>.
    /// <br />
    /// en: Pops TOS into a local variable. <b>Trap ordering:</b> index check
    /// first (<see cref="TTrapReason.InvalidLocal"/>), then pop
    /// (<see cref="TTrapReason.StackUnderflow"/>). An invalid index always
    /// takes precedence over stack underflow — see <c>docs/ISA-CIL-T0.md</c>.
    /// </summary>
    private static void StoreLocal(TCpu ACpu, int AIndex)
    {
        // hu: Index check BEFORE pop (ISA spec trap sorrend)
        // en: Index check BEFORE pop (ISA spec trap ordering)
        if (AIndex < 0 || AIndex >= TCpu.MaxLocals || AIndex >= ACpu.LocalCount)
            throw new TTrapException(TTrapReason.InvalidLocal, ACpu.Pc,
                $"Invalid local index {AIndex} at PC=0x{ACpu.Pc:X4}");

        var value = ACpu.EvalPop(ACpu.Pc);
        ACpu.StoreLocal(AIndex, value, ACpu.Pc);
    }

    /// <summary>
    /// hu: Argumentum push a stack-re. Érvénytelen index esetén
    /// <see cref="TTrapReason.InvalidArg"/> trap.
    /// <br />
    /// en: Pushes an argument onto the stack. Invalid index raises
    /// <see cref="TTrapReason.InvalidArg"/>.
    /// </summary>
    private static void LoadArg(TCpu ACpu, int AIndex)
    {
        if (AIndex < 0 || AIndex >= TCpu.MaxArgs || AIndex >= ACpu.ArgCount)
            throw new TTrapException(TTrapReason.InvalidArg, ACpu.Pc,
                $"Invalid arg index {AIndex} at PC=0x{ACpu.Pc:X4}");

        var value = ACpu.LoadArg(AIndex, ACpu.Pc);
        ACpu.EvalPush(value, ACpu.Pc);
    }

    /// <summary>
    /// hu: TOS pop → argumentum. <b>Trap sorrend:</b> előbb index check
    /// (<see cref="TTrapReason.InvalidArg"/>), utána pop.
    /// <br />
    /// en: Pops TOS into an argument. <b>Trap ordering:</b> index check first
    /// (<see cref="TTrapReason.InvalidArg"/>), then pop.
    /// </summary>
    private static void StoreArg(TCpu ACpu, int AIndex)
    {
        // hu: Index check BEFORE pop (ISA spec trap sorrend)
        // en: Index check BEFORE pop (ISA spec trap ordering)
        if (AIndex < 0 || AIndex >= TCpu.MaxArgs || AIndex >= ACpu.ArgCount)
            throw new TTrapException(TTrapReason.InvalidArg, ACpu.Pc,
                $"Invalid arg index {AIndex} at PC=0x{ACpu.Pc:X4}");

        var value = ACpu.EvalPop(ACpu.Pc);
        ACpu.StoreArg(AIndex, value, ACpu.Pc);
    }
}
