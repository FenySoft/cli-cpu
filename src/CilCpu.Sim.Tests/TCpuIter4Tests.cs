namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpu iter. 4 opkód-szintű tesztjei: call, ret, ldind.i4, stind.i4,
/// break. Ezek a tesztek izolált, kis programokon ellenőrzik az iter. 4
/// opkódok szemantikáját és a hozzájuk tartozó trapeket
/// (InvalidCallTarget, CallDepthExceeded, DebugBreak).
/// <br />
/// en: TCpu iter. 4 opcode-level tests: call, ret, ldind.i4, stind.i4, break.
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu();
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu();
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu(data);
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
        var cpu = new TCpu();
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
}
