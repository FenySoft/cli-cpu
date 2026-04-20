namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpuNano iter. 4 opkód-szintű tesztjei: call, ret, ldind.i4, stind.i4,
/// break. Ezek a tesztek izolált, kis programokon ellenőrzik az iter. 4
/// opkódok szemantikáját és a hozzájuk tartozó trapeket
/// (InvalidCallTarget, CallDepthExceeded, DebugBreak).
/// <br />
/// en: TCpuNano iter. 4 opcode-level tests: call, ret, ldind.i4, stind.i4, break.
/// These tests verify the semantics of the iter. 4 opcodes with isolated
/// small programs and the corresponding traps (InvalidCallTarget,
/// CallDepthExceeded, DebugBreak).
/// </summary>
public class TCpuIter4Tests
{
    // ------------------------------------------------------------------
    // break (0xDD)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: A break opkód mindig DebugBreak trap-et dob, a PC a break byte
    /// offszetjén marad.
    /// <br />
    /// en: The break opcode always raises a DebugBreak trap; the PC stays
    /// at the break byte's offset.
    /// </summary>
    [Fact]
    public void Execute_Break_ThrowsDebugBreakTrap()
    {
        var cpu = new TCpuNano();
        var program = new byte[] { 0xDD };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.DebugBreak, trap.Reason);
        Assert.Equal(0, trap.ProgramCounter);
    }

    /// <summary>
    /// hu: A break opkód a program közepén — a megelőző opkód lefut, a break
    /// byte offszetjén trap.
    /// <br />
    /// en: A break opcode in the middle of a program — the preceding opcode
    /// runs, then the break traps at its byte offset.
    /// </summary>
    [Fact]
    public void Execute_BreakAfterValid_TrapsAtBreakOffset()
    {
        var cpu = new TCpuNano();
        var program = new byte[] { 0x16, 0xDD }; // ldc.i4.0; break

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.DebugBreak, trap.Reason);
        Assert.Equal(1, trap.ProgramCounter);
        Assert.Equal(1, cpu.StackDepth);
    }

    // ------------------------------------------------------------------
    // ldind.i4 (0x4A) — read int32 from data memory
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldind.i4: a TOS cím, a data memory adott címéről olvas egy
    /// little-endian int32-t és push-olja a TOS-ra.
    /// <br />
    /// en: ldind.i4: TOS is the address; reads a little-endian int32 from
    /// data memory at that address and pushes it on TOS.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_ReadsInt32FromDataMemory()
    {
        var data = new byte[] { 0x78, 0x56, 0x34, 0x12 }; // 0x12345678 LE
        var cpu = new TCpuNano(data);
        // ldc.i4.0 (cím=0); ldind.i4
        var program = new byte[] { 0x16, 0x4A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x12345678, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldind.i4 negatív értéket is helyesen olvas (sign-extended int32).
    /// <br />
    /// en: ldind.i4 reads negative int32 values correctly (sign-extended).
    /// </summary>
    [Fact]
    public void Execute_LdindI4_NegativeValue()
    {
        var data = new byte[] { 0xFF, 0xFF, 0xFF, 0xFF };
        var cpu = new TCpuNano(data);
        var program = new byte[] { 0x16, 0x4A };

        cpu.Execute(program);

        Assert.Equal(-1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldind.i4 egy nem-0 címről olvas: cím = 4, érték a data[4..7].
    /// <br />
    /// en: ldind.i4 reads from a non-zero address: addr = 4, value at data[4..7].
    /// </summary>
    [Fact]
    public void Execute_LdindI4_NonZeroAddress()
    {
        var data = new byte[] { 0, 0, 0, 0, 0x01, 0x00, 0x00, 0x00 };
        var cpu = new TCpuNano(data);
        // ldc.i4.4; ldind.i4
        var program = new byte[] { 0x1A, 0x4A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldind.i4 ha nincs data memory (null) → InvalidMemoryAccess trap.
    /// <br />
    /// en: ldind.i4 when no data memory is configured → InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_NoDataMemory_Traps()
    {
        var cpu = new TCpuNano();
        var program = new byte[] { 0x16, 0x4A };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: ldind.i4 cím a data memory határain kívül → InvalidMemoryAccess trap.
    /// <br />
    /// en: ldind.i4 with an address outside data memory → InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_OutOfBounds_Traps()
    {
        var data = new byte[4];
        var cpu = new TCpuNano(data);
        // ldc.i4.s 100; ldind.i4
        var program = new byte[] { 0x1F, 0x64, 0x4A };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    // ------------------------------------------------------------------
    // stind.i4 (0x54) — write int32 to data memory
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: stind.i4: TOS-1 = cím, TOS = érték. Pop érték, pop cím, ír.
    /// (Stack alulról: cím, érték — az érték kerül a memóriába.)
    /// <br />
    /// en: stind.i4: TOS-1 = address, TOS = value. Pop value, pop address,
    /// store. (Stack from bottom: addr, value — value is written to memory.)
    /// </summary>
    [Fact]
    public void Execute_StindI4_WritesInt32ToDataMemory()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        // ldc.i4.0 (addr=0); ldc.i4.s 0x42 (value); stind.i4
        var program = new byte[] { 0x16, 0x1F, 0x42, 0x54 };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(0x42, data[0]);
        Assert.Equal(0x00, data[1]);
        Assert.Equal(0x00, data[2]);
        Assert.Equal(0x00, data[3]);
    }

    /// <summary>
    /// hu: stind.i4 a teljes 32-bit-et helyesen írja LE sorrendben.
    /// <br />
    /// en: stind.i4 writes the full 32 bits in little-endian order.
    /// </summary>
    [Fact]
    public void Execute_StindI4_WritesAllFourBytesLittleEndian()
    {
        var data = new byte[4];
        var cpu = new TCpuNano(data);
        // ldc.i4.0; ldc.i4 0x12345678; stind.i4
        var program = new byte[] { 0x16, 0x20, 0x78, 0x56, 0x34, 0x12, 0x54 };

        cpu.Execute(program);

        Assert.Equal(0x78, data[0]);
        Assert.Equal(0x56, data[1]);
        Assert.Equal(0x34, data[2]);
        Assert.Equal(0x12, data[3]);
    }

    /// <summary>
    /// hu: stind.i4 ha nincs data memory → InvalidMemoryAccess trap.
    /// <br />
    /// en: stind.i4 with no data memory → InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_StindI4_NoDataMemory_Traps()
    {
        var cpu = new TCpuNano();
        var program = new byte[] { 0x16, 0x16, 0x54 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: stind.i4 cím a data memory határain kívül → InvalidMemoryAccess trap.
    /// <br />
    /// en: stind.i4 with an address outside data memory → InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_StindI4_OutOfBounds_Traps()
    {
        var data = new byte[4];
        var cpu = new TCpuNano(data);
        // ldc.i4.s 100; ldc.i4.0; stind.i4
        var program = new byte[] { 0x1F, 0x64, 0x16, 0x54 };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: ldind/stind round-trip: írunk egy értéket, visszaolvassuk.
    /// <br />
    /// en: ldind/stind round-trip: store a value, then load it back.
    /// </summary>
    [Fact]
    public void Execute_StindThenLdind_RoundTrip()
    {
        var data = new byte[4];
        var cpu = new TCpuNano(data);
        // ldc.i4.0; ldc.i4.s 42; stind.i4; ldc.i4.0; ldind.i4
        var program = new byte[] { 0x16, 0x1F, 0x2A, 0x54, 0x16, 0x4A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(42, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // call / ret with method header (Execute(byte[], int, int[]?))
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Egyszerű "konstans visszatérés" metódus: a callee csak push 7-et
    /// és ret. A header-vezérelt Execute fut, és a TOS = 7.
    /// <br />
    /// en: Simple "constant return" method: the callee just pushes 7 and
    /// rets. The header-driven Execute runs and TOS = 7.
    /// </summary>
    [Fact]
    public void Execute_HeaderEntry_ReturnsConstant()
    {
        var cpu = new TCpuNano();
        // header: magic=0xFE, arg=0, local=0, max_stack=1, code_size=2
        // code: ldc.i4.7; ret
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x1D, 0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(7, cpu.Peek(0));
    }

    /// <summary>
    /// hu: A header-vezérelt Execute kezdő argumentumokat kap.
    /// A metódus egyszerűen visszaadja az argumentumát.
    /// <br />
    /// en: The header-driven Execute receives initial arguments.
    /// The method simply returns its argument.
    /// </summary>
    [Fact]
    public void Execute_HeaderEntry_WithArg_ReturnsArg()
    {
        var cpu = new TCpuNano();
        // header: magic, arg=1, local=0, max=1, code_size=2
        // code: ldarg.0; ret
        var program = new byte[]
        {
            0xFE, 0x01, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x02, 0x2A
        };

        cpu.Execute(program, 0, new[] { 99 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(99, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Hívás (call): caller meghívja a callee-t, ami konstans 5-öt ad
    /// vissza. A caller a return value-t megtartja, majd ret.
    /// <br />
    /// en: Call test: caller calls callee, which returns the constant 5.
    /// The caller keeps the return value and rets.
    /// </summary>
    [Fact]
    public void Execute_Call_VoidArgsReturnsConstant()
    {
        var cpu = new TCpuNano();
        // Caller header at 0: magic, arg=0, local=0, max=1, code_size=6
        //   call <RVA=14>; ret           (length: 5+1=6)
        // Callee header at 14: magic, arg=0, local=0, max=1, code_size=2
        //   ldc.i4.5; ret
        var program = new byte[]
        {
            // 0..7: caller header
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            // 8..13: caller code (call 14, ret)
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            // 14..21: callee header
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            // 22..23: callee code (ldc.i4.5, ret)
            0x1B, 0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(5, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Hívás argumentummal: caller push-olja az 5-öt, majd hív egy
    /// callee-t, ami 1-et ad hozzá és visszaadja.
    /// <br />
    /// en: Call with argument: caller pushes 5, then calls a callee that
    /// adds 1 and returns the result.
    /// </summary>
    [Fact]
    public void Execute_Call_WithArg_PassesAndReturns()
    {
        var cpu = new TCpuNano();
        // Caller header at 0: arg=0, local=0, max=2, code_size=8
        //   ldc.i4.5; call 16; ret
        // Callee header at 16: arg=1, local=0, max=2, code_size=4
        //   ldarg.0; ldc.i4.1; add; ret
        var program = new byte[]
        {
            // header caller
            0xFE, 0x00, 0x00, 0x02, 0x08, 0x00, 0x00, 0x00,
            // caller code (8..15): ldc.i4.5, call 16, ret
            0x1B, 0x28, 0x10, 0x00, 0x00, 0x00, 0x2A,
            // padding to 16
            0x00,
            // callee header at 16
            0xFE, 0x01, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00,
            // callee code: ldarg.0, ldc.i4.1, add, ret
            0x02, 0x17, 0x58, 0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(6, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Két argumentumos hívás: caller push 3, push 4, call add(a,b)
    /// callee, ami a+b-t ad vissza.
    /// <br />
    /// en: Two-argument call: caller pushes 3, 4, calls add(a,b) callee
    /// that returns a+b.
    /// </summary>
    [Fact]
    public void Execute_Call_TwoArgs_Adds()
    {
        var cpu = new TCpuNano();
        // caller header: arg=0, local=0, max=2, code_size=9
        //   ldc.i4.3; ldc.i4.4; call 17; ret
        // callee header at 17: arg=2, local=0, max=2, code_size=4
        //   ldarg.0; ldarg.1; add; ret
        var program = new byte[]
        {
            // 0..7
            0xFE, 0x00, 0x00, 0x02, 0x09, 0x00, 0x00, 0x00,
            // 8..16: caller code  ldc.i4.3, ldc.i4.4, call 17, ret
            0x19, 0x1A, 0x28, 0x11, 0x00, 0x00, 0x00, 0x2A,
            0x00, // padding to 17
            // 17..24
            0xFE, 0x02, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00,
            // 25..28
            0x02, 0x03, 0x58, 0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(7, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Call target RVA a programon kívül → InvalidCallTarget trap.
    /// <br />
    /// en: Call target RVA outside the program → InvalidCallTarget trap.
    /// </summary>
    [Fact]
    public void Execute_Call_OutOfBoundsRva_TrapsInvalidCallTarget()
    {
        var cpu = new TCpuNano();
        // caller header: code_size=6, code = call 0xFFFF; ret
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0xFF, 0xFF, 0x00, 0x00, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Call target nem érvényes header (magic != 0xFE) → InvalidCallTarget.
    /// <br />
    /// en: Call target without a valid header (magic != 0xFE) → InvalidCallTarget.
    /// </summary>
    [Fact]
    public void Execute_Call_InvalidHeaderMagic_Traps()
    {
        var cpu = new TCpuNano();
        // caller header (8) + caller code (6 = call 14, ret) + 8 byte fake header without 0xFE magic
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            0x00, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x1B, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Végtelen rekurzió → CallDepthExceeded trap a 513. híváson.
    /// <br />
    /// en: Infinite recursion → CallDepthExceeded trap at the 513th call.
    /// </summary>
    [Fact]
    public void Execute_InfiniteRecursion_TrapsCallDepthExceeded()
    {
        var cpu = new TCpuNano();
        // header: arg=0, local=0, max=1, code_size=6
        //   call 0; ret  (calls itself forever)
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x00, 0x00, 0x00, 0x00, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.CallDepthExceeded, trap.Reason);
    }

    /// <summary>
    /// hu: Nested call: f → g → h, mindegyik konstans-rétegező +1.
    /// <br />
    /// en: Nested calls: f → g → h, each adding +1 to a returned constant.
    /// </summary>
    [Fact]
    public void Execute_NestedCalls_ReturnsCorrectChain()
    {
        var cpu = new TCpuNano();
        // f at 0: arg=0, local=0, max=2, code_size=8
        //   call g (rva=16); ldc.i4.1; add; ret
        // g at 16: arg=0, local=0, max=2, code_size=8
        //   call h (rva=32); ldc.i4.2; add; ret
        // h at 32: arg=0, local=0, max=1, code_size=2
        //   ldc.i4.3; ret
        var program = new byte[]
        {
            // 0..7 f header (code_size=8)
            0xFE, 0x00, 0x00, 0x02, 0x08, 0x00, 0x00, 0x00,
            // 8..15 f code: call 16, ldc.i4.1, add, ret
            0x28, 0x10, 0x00, 0x00, 0x00, 0x17, 0x58, 0x2A,
            // 16..23 g header
            0xFE, 0x00, 0x00, 0x02, 0x08, 0x00, 0x00, 0x00,
            // 24..31 g code: call 32, ldc.i4.2, add, ret
            0x28, 0x20, 0x00, 0x00, 0x00, 0x18, 0x58, 0x2A,
            // 32..39 h header
            0xFE, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            // 40..41 h code: ldc.i4.3, ret
            0x19, 0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(3 + 2 + 1, cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // hu: Lefedetlen ág tesztek — call/ret/memory edge case-ek
    // en: Uncovered branch tests — call/ret/memory edge cases
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Call negatív target RVA-val InvalidCallTarget trap-et dob.
    /// <br />
    /// en: Call with negative target RVA raises InvalidCallTarget trap.
    /// </summary>
    [Fact]
    public void Execute_Call_NegativeTargetRva_TrapsInvalidCallTarget()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0xF0, 0xFF, 0xFF, 0xFF, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Call target, ahol argCount > MaxArgs → InvalidCallTarget trap.
    /// <br />
    /// en: Call target with argCount > MaxArgs raises InvalidCallTarget trap.
    /// </summary>
    [Fact]
    public void Execute_Call_TargetArgCountExceedsMax_TrapsInvalidCallTarget()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            0xFE, 0xFF, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x16, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Call target, ahol localCount > MaxLocals → InvalidCallTarget trap.
    /// <br />
    /// en: Call target with localCount > MaxLocals raises InvalidCallTarget trap.
    /// </summary>
    [Fact]
    public void Execute_Call_TargetLocalCountExceedsMax_TrapsInvalidCallTarget()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            0xFE, 0x00, 0xFF, 0x01, 0x02, 0x00, 0x00, 0x00,
            0x16, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Call target, ahol a callee kódja túlnyúlik a program végén.
    /// <br />
    /// en: Call target where callee code extends past program end.
    /// </summary>
    [Fact]
    public void Execute_Call_TargetCodePastEnd_TrapsInvalidCallTarget()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            0xFE, 0x00, 0x00, 0x01, 0x64, 0x00, 0x00, 0x00,
            0x16, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.InvalidCallTarget, trap.Reason);
    }

    /// <summary>
    /// hu: Ret üres eval stack-kel (void metódus) — a caller eval stack-je
    /// változatlan marad.
    /// <br />
    /// en: Ret with empty eval stack (void method) — caller's eval stack is
    /// unchanged.
    /// </summary>
    [Fact]
    public void Execute_RetVoid_NoReturnValuePushed()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            // caller header: arg=0, local=0, max=2, code_size=8
            0xFE, 0x00, 0x00, 0x02, 0x08, 0x00, 0x00, 0x00,
            // caller code (8..15): ldc.i4.s 99, call 16, ret, padding
            0x1F, 0x63, 0x28, 0x10, 0x00, 0x00, 0x00, 0x2A,
            // callee header at 16: arg=0, local=0, max=1, code_size=1
            0xFE, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,
            // callee code: ret (no value pushed)
            0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(99, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldind.i4 negatív címmel InvalidMemoryAccess trap-et dob.
    /// <br />
    /// en: ldind.i4 with negative address raises InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_NegativeAddress_TrapsInvalidMemory()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        var program = new byte[] { 0x15, 0x4A }; // ldc.i4.m1; ldind.i4

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: stind.i4 negatív címmel InvalidMemoryAccess trap-et dob.
    /// <br />
    /// en: stind.i4 with negative address raises InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_StindI4_NegativeAddress_TrapsInvalidMemory()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        var program = new byte[] { 0x15, 0x16, 0x54 }; // ldc.i4.m1; ldc.i4.0; stind.i4

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: PushCallFrame kis SRAM-mal SramOverflow trap-et dob.
    /// <br />
    /// en: PushCallFrame with small SRAM raises SramOverflow trap.
    /// </summary>
    [Fact]
    public void Execute_Call_SmallSram_TrapsSramOverflow()
    {
        var cpu = new TCpuNano(null, 80);
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x00, 0x00, 0x00, 0x00, 0x2A
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program, 0));

        Assert.Equal(TTrapReason.SramOverflow, trap.Reason);
    }

    // ------------------------------------------------------------------
    // hu: Memória határ tesztek (ldind.i4 / stind.i4)
    // en: Memory boundary tests (ldind.i4 / stind.i4)
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: ldind.i4 az utolsó érvényes címről (4) 8 byte-os data memory-ból —
    /// 4+4=8 ≤ 8, sikeres olvasás.
    /// <br />
    /// en: ldind.i4 from the last valid address (4) in 8-byte data memory —
    /// 4+4=8 ≤ 8, succeeds.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_LastValidAddress_Succeeds()
    {
        var data = new byte[8];
        data[4] = 0x78;
        data[5] = 0x56;
        data[6] = 0x34;
        data[7] = 0x12;
        var cpu = new TCpuNano(data);
        // ldc.i4 4; ldind.i4
        var program = new byte[] { 0x20, 0x04, 0x00, 0x00, 0x00, 0x4A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(0x12345678, cpu.Peek(0));
    }

    /// <summary>
    /// hu: ldind.i4 az első érvénytelen címről (5) 8 byte-os data memory-ból —
    /// 5+4=9 > 8, InvalidMemoryAccess trap.
    /// <br />
    /// en: ldind.i4 from the first invalid address (5) in 8-byte data memory —
    /// 5+4=9 > 8, InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_FirstInvalidAddress_Traps()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        // ldc.i4 5; ldind.i4
        var program = new byte[] { 0x20, 0x05, 0x00, 0x00, 0x00, 0x4A };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: stind.i4 az utolsó érvényes címre (4) 8 byte-os data memory-ban —
    /// 4+4=8 ≤ 8, sikeres írás.
    /// <br />
    /// en: stind.i4 to the last valid address (4) in 8-byte data memory —
    /// 4+4=8 ≤ 8, succeeds.
    /// </summary>
    [Fact]
    public void Execute_StindI4_LastValidAddress_Succeeds()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        // ldc.i4 4 (address); ldc.i4 0x12345678 (value); stind.i4
        var program = new byte[]
        {
            0x20, 0x04, 0x00, 0x00, 0x00,
            0x20, 0x78, 0x56, 0x34, 0x12,
            0x54
        };

        cpu.Execute(program);

        Assert.Equal(0, cpu.StackDepth);
        Assert.Equal(0x78, data[4]);
        Assert.Equal(0x56, data[5]);
        Assert.Equal(0x34, data[6]);
        Assert.Equal(0x12, data[7]);
    }

    /// <summary>
    /// hu: stind.i4 az első érvénytelen címre (5) 8 byte-os data memory-ban —
    /// 5+4=9 > 8, InvalidMemoryAccess trap.
    /// <br />
    /// en: stind.i4 to the first invalid address (5) in 8-byte data memory —
    /// 5+4=9 > 8, InvalidMemoryAccess trap.
    /// </summary>
    [Fact]
    public void Execute_StindI4_FirstInvalidAddress_Traps()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        // ldc.i4 5 (address); ldc.i4 0 (value); stind.i4
        var program = new byte[]
        {
            0x20, 0x05, 0x00, 0x00, 0x00,
            0x16,
            0x54
        };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: ldind.i4 INT_MAX címmel 8 byte-os data memory-ból →
    /// InvalidMemoryAccess trap (messze a határokon kívül).
    /// <br />
    /// en: ldind.i4 with INT_MAX address from 8-byte data memory →
    /// InvalidMemoryAccess trap (far outside bounds).
    /// </summary>
    [Fact]
    public void Execute_LdindI4_AddressIntMax_Traps()
    {
        var data = new byte[8];
        var cpu = new TCpuNano(data);
        // ldc.i4 INT_MAX (0x7FFFFFFF); ldind.i4
        var program = new byte[] { 0x20, 0xFF, 0xFF, 0xFF, 0x7F, 0x4A };

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.InvalidMemoryAccess, trap.Reason);
    }

    /// <summary>
    /// hu: ldind.i4 a 0 címről 4 byte-os data memory-ból — az alsó határ
    /// érvényes, sikeres olvasás.
    /// <br />
    /// en: ldind.i4 from address 0 in 4-byte data memory — lower bound is
    /// valid, succeeds.
    /// </summary>
    [Fact]
    public void Execute_LdindI4_AddressZero_Succeeds()
    {
        var data = new byte[] { 0xAA, 0xBB, 0xCC, 0xDD };
        var cpu = new TCpuNano(data);
        // ldc.i4.0; ldind.i4
        var program = new byte[] { 0x16, 0x4A };

        cpu.Execute(program);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(unchecked((int)0xDDCCBBAA), cpu.Peek(0));
    }

    // ------------------------------------------------------------------
    // hu: Stack mélység határ tesztek
    // en: Stack depth boundary tests
    // ------------------------------------------------------------------

    /// <summary>
    /// hu: Pontosan 64 elem push-olása (MaxStackDepth) — nem dob trap-et.
    /// <br />
    /// en: Pushing exactly 64 items (MaxStackDepth) — no trap raised.
    /// </summary>
    [Fact]
    public void Execute_Push_AtDepth64_Succeeds()
    {
        var cpu = new TCpuNano();
        // 64 × ldc.i4.1 (0x17)
        var program = Enumerable.Repeat((byte)0x17, 64).ToArray();

        cpu.Execute(program);

        Assert.Equal(64, cpu.StackDepth);
    }

    /// <summary>
    /// hu: 65 elem push-olása (MaxStackDepth + 1) → StackOverflow trap.
    /// <br />
    /// en: Pushing 65 items (MaxStackDepth + 1) → StackOverflow trap.
    /// </summary>
    [Fact]
    public void Execute_Push_AtDepth65_TrapsStackOverflow()
    {
        var cpu = new TCpuNano();
        // 65 × ldc.i4.1 (0x17)
        var program = Enumerable.Repeat((byte)0x17, 65).ToArray();

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
    }

    /// <summary>
    /// hu: 63 elem push + dup → mélység 64, sikeres (MaxStackDepth határ).
    /// <br />
    /// en: 63 items pushed + dup → depth 64, succeeds (at MaxStackDepth).
    /// </summary>
    [Fact]
    public void Execute_Dup_AtDepth63_Succeeds()
    {
        var cpu = new TCpuNano();
        // 63 × ldc.i4.1 + dup
        var program = Enumerable.Repeat((byte)0x17, 63)
            .Append((byte)0x25)
            .ToArray();

        cpu.Execute(program);

        Assert.Equal(64, cpu.StackDepth);
    }

    /// <summary>
    /// hu: 64 elem push + dup → mélység 65, StackOverflow trap.
    /// <br />
    /// en: 64 items pushed + dup → depth would be 65, StackOverflow trap.
    /// </summary>
    [Fact]
    public void Execute_Dup_AtDepth64_TrapsStackOverflow()
    {
        var cpu = new TCpuNano();
        // 64 × ldc.i4.1 + dup
        var program = Enumerable.Repeat((byte)0x17, 64)
            .Append((byte)0x25)
            .ToArray();

        var trap = Assert.Throws<TTrapException>(() => cpu.Execute(program));

        Assert.Equal(TTrapReason.StackOverflow, trap.Reason);
    }
}
