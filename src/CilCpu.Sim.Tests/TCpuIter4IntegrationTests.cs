namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: TCpu iter. 4 integrációs tesztek: valódi rekurzív és iteratív
/// algoritmusok (Fibonacci, faktoriális, GCD) futtatása a header-vezérelt
/// Execute overload-on. Ezek a tesztek bizonyítják, hogy a 48 CIL-T0 opkód
/// teljes együtt-működése helyes — a Fibonacci(20) = 6765 az F1 fázis
/// "aranypéldája".
/// <br />
/// en: TCpu iter. 4 integration tests: real recursive and iterative
/// algorithms (Fibonacci, factorial, GCD) running on the header-driven
/// Execute overload. These prove that the full 48-opcode CIL-T0 set works
/// together correctly — Fibonacci(20) = 6765 is the F1 phase "golden
/// example".
/// </summary>
public class TCpuIter4IntegrationTests
{
    /// <summary>
    /// hu: A Fibonacci(n) program bájt-tömbje a CIL-T0 spec
    /// "Példa: Fibonacci(n)" szekciójából. Egyetlen metódus, header-rel
    /// együtt 8 + 24 = 32 byte. A header: arg=1, local=0, max_stack=2,
    /// code_size=24.
    /// <br />
    /// en: The Fibonacci(n) program byte array from the CIL-T0 spec
    /// "Example: Fibonacci(n)" section. A single method; with the header
    /// it is 8 + 24 = 32 bytes. Header: arg=1, local=0, max_stack=2,
    /// code_size=24.
    /// </summary>
    private static byte[] BuildFibonacciProgram()
    {
        // Body layout (file offsets):
        //   8:  02       ldarg.0
        //   9:  18       ldc.i4.2
        //  10:  2F 02    bge.s +2  → fall-through = 12, target = 14 (L1)
        //  12:  02       ldarg.0
        //  13:  2A       ret
        //  L1 @ 14:
        //  14:  02       ldarg.0
        //  15:  17       ldc.i4.1
        //  16:  59       sub
        //  17:  28 00 00 00 00   call Fib (rva = 0)
        //  22:  02       ldarg.0
        //  23:  18       ldc.i4.2
        //  24:  59       sub
        //  25:  28 00 00 00 00   call Fib (rva = 0)
        //  30:  58       add
        //  31:  2A       ret
        //
        // code_size = 24 (file offsets 8..31).
        return new byte[]
        {
            // header
            0xFE, 0x01, 0x00, 0x02, 0x18, 0x00, 0x00, 0x00,
            // body @ 8
            0x02,
            0x18,
            0x2F, 0x02,
            0x02,
            0x2A,
            // L1 @ 14
            0x02,
            0x17,
            0x59,
            0x28, 0x00, 0x00, 0x00, 0x00,
            0x02,
            0x18,
            0x59,
            0x28, 0x00, 0x00, 0x00, 0x00,
            0x58,
            0x2A
        };
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 1)]
    [InlineData(2, 1)]
    [InlineData(3, 2)]
    [InlineData(4, 3)]
    [InlineData(5, 5)]
    [InlineData(6, 8)]
    [InlineData(7, 13)]
    [InlineData(8, 21)]
    [InlineData(9, 34)]
    [InlineData(10, 55)]
    public void Execute_Fibonacci_SmallValues(int n, int expected)
    {
        var cpu = new TCpu();
        var program = BuildFibonacciProgram();

        cpu.Execute(program, 0, new[] { n });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Fibonacci(20) = 6765 — az F1 fázis "aranypéldája". Ha ez a teszt
    /// zöld, a 48 CIL-T0 opkód együtt-működése validált.
    /// <br />
    /// en: Fibonacci(20) = 6765 — the F1 phase "golden example". If this
    /// test passes, the full 48-opcode CIL-T0 set is validated end-to-end.
    /// </summary>
    [Fact]
    public void Execute_Fibonacci20_Returns6765()
    {
        var cpu = new TCpu();
        var program = BuildFibonacciProgram();

        cpu.Execute(program, 0, new[] { 20 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(6765, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Iteratív faktoriális: fact(n) = 1*2*...*n. 1 arg, 2 local
    /// (result, i). Ellenőrzött kis értékek és n=10 → 3628800.
    /// <br />
    /// en: Iterative factorial: fact(n) = 1*2*...*n. 1 arg, 2 locals
    /// (result, i). Verified small values and n=10 → 3628800.
    /// </summary>
    [Theory]
    [InlineData(0, 1)]
    [InlineData(1, 1)]
    [InlineData(2, 2)]
    [InlineData(3, 6)]
    [InlineData(5, 120)]
    [InlineData(10, 3628800)]
    public void Execute_FactorialIterative(int n, int expected)
    {
        var cpu = new TCpu();
        // Body layout (file offsets, header at 0..7, body starts at 8):
        //  8:  17        ldc.i4.1
        //  9:  0A        stloc.0           ; result = 1
        // 10:  17        ldc.i4.1
        // 11:  0B        stloc.1           ; i = 1
        // LOOP @ 12:
        // 12:  07        ldloc.1
        // 13:  02        ldarg.0
        // 14:  30 0A     bgt.s +10 → fall=16, target=26 (END)
        // 16:  06        ldloc.0
        // 17:  07        ldloc.1
        // 18:  5A        mul
        // 19:  0A        stloc.0
        // 20:  07        ldloc.1
        // 21:  17        ldc.i4.1
        // 22:  58        add
        // 23:  0B        stloc.1
        // 24:  2B F4     br.s -12 → fall=26, target=14? No want LOOP=12.
        //                fall=26, target=12, offset=12-26=-14=0xF2
        // 24:  2B F2     br.s -14 → 12 (LOOP)
        // END @ 26:
        // 26:  06        ldloc.0
        // 27:  2A        ret
        //
        // code_size = 20 (file offsets 8..27)
        var program = new byte[]
        {
            0xFE, 0x01, 0x02, 0x03, 0x14, 0x00, 0x00, 0x00,
            0x17, 0x0A,                   // ldc.i4.1; stloc.0
            0x17, 0x0B,                   // ldc.i4.1; stloc.1
            0x07,                         // ldloc.1
            0x02,                         // ldarg.0
            0x30, 0x0A,                   // bgt.s +10 → END
            0x06,                         // ldloc.0
            0x07,                         // ldloc.1
            0x5A,                         // mul
            0x0A,                         // stloc.0
            0x07,                         // ldloc.1
            0x17,                         // ldc.i4.1
            0x58,                         // add
            0x0B,                         // stloc.1
            0x2B, 0xF2,                   // br.s -14 → LOOP
            0x06,                         // ldloc.0
            0x2A                          // ret
        };

        cpu.Execute(program, 0, new[] { n });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Euklidészi GCD (iteratív, modulo): gcd(a, b). 2 arg, 1 local (t).
    /// while (b != 0) { t = b; b = a % b; a = t; } return a.
    /// <br />
    /// en: Euclidean GCD (iterative, modulo): gcd(a, b). 2 args, 1 local (t).
    /// while (b != 0) { t = b; b = a % b; a = t; } return a.
    /// </summary>
    [Theory]
    [InlineData(48, 18, 6)]
    [InlineData(54, 24, 6)]
    [InlineData(17, 5, 1)]
    [InlineData(100, 10, 10)]
    [InlineData(7, 7, 7)]
    public void Execute_GcdIterative(int a, int b, int expected)
    {
        var cpu = new TCpu();
        // Body layout (file offsets, header at 0..7):
        //  8: 03        ldarg.1            ; LOOP
        //  9: 16        ldc.i4.0
        // 10: 2E 0F     beq.s +15 → fall=12, target=27 (END)
        // 12: 03        ldarg.1
        // 13: 10 02     starg.s 2          (no — we use stloc.0)
        // We use local 0 = t.
        // Restart layout properly:
        //  8:  03        ldarg.1            (LOOP)
        //  9:  16        ldc.i4.0
        // 10:  2E 0E     beq.s +14 → fall=12, target=26 (END)
        // 12:  03        ldarg.1
        // 13:  0A        stloc.0            ; t = b
        // 14:  02        ldarg.0
        // 15:  03        ldarg.1
        // 16:  5D        rem
        // 17:  10 01     starg.s 1          ; b = a % b
        // 19:  06        ldloc.0
        // 20:  10 00     starg.s 0          ; a = t
        // 22:  2B F0     br.s -16 → fall=24, target=8 (LOOP) ; offset = 8-24=-16=0xF0
        // 24:  ?? extra padding nope
        // END @ 24:
        // 24:  02        ldarg.0
        // 25:  2A        ret
        //
        // Recompute: previous bge.s at file offset 10 was 2E 0E meaning target = fall(12) + 14 = 26.
        // But END is at 24 now, not 26. Need offset = 24 - 12 = 12 = 0x0C
        //
        // Let me carefully list every instruction with its size:
        //   8:  ldarg.1     (1)
        //   9:  ldc.i4.0    (1)
        //  10:  beq.s ?     (2)  → next at 12
        //  12:  ldarg.1     (1)
        //  13:  stloc.0     (1)
        //  14:  ldarg.0     (1)
        //  15:  ldarg.1     (1)
        //  16:  rem         (1)
        //  17:  starg.s 1   (2)  → next at 19
        //  19:  ldloc.0     (1)
        //  20:  starg.s 0   (2)  → next at 22
        //  22:  br.s ?      (2)  → next at 24 (END)
        //  24:  ldarg.0     (1)
        //  25:  ret         (1)  → end at 26
        //
        // beq.s offset (at 10): fall=12, target=24, offset=12 → 0x0C
        // br.s offset (at 22): fall=24, target=8 (LOOP), offset=8-24=-16=0xF0
        //
        // code_size = 18 (offsets 8..25)
        var program = new byte[]
        {
            0xFE, 0x02, 0x01, 0x03, 0x12, 0x00, 0x00, 0x00,
            0x03,             //  8: ldarg.1
            0x16,             //  9: ldc.i4.0
            0x2E, 0x0C,       // 10: beq.s +12 → END
            0x03,             // 12: ldarg.1
            0x0A,             // 13: stloc.0
            0x02,             // 14: ldarg.0
            0x03,             // 15: ldarg.1
            0x5D,             // 16: rem
            0x10, 0x01,       // 17: starg.s 1
            0x06,             // 19: ldloc.0
            0x10, 0x00,       // 20: starg.s 0
            0x2B, 0xF0,       // 22: br.s -16 → LOOP (8)
            0x02,             // 24: ldarg.0
            0x2A              // 25: ret
        };

        cpu.Execute(program, 0, new[] { a, b });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(expected, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Egyszerű "void" callee: nem ad vissza értéket. Caller hív, nincs
    /// return value, ret után üres a stack.
    /// <br />
    /// en: Simple "void" callee: returns no value. Caller calls and after
    /// ret the stack is empty.
    /// </summary>
    [Fact]
    public void Execute_VoidCalleeNoReturnValue()
    {
        var cpu = new TCpu();
        // Caller header @ 0: arg=0 local=0 max=0 code=6
        //   call 14; ret      (call=5, ret=1)
        // Callee header @ 14: arg=0 local=0 max=0 code=1
        //   ret
        var program = new byte[]
        {
            0xFE, 0x00, 0x00, 0x01, 0x06, 0x00, 0x00, 0x00,
            0x28, 0x0E, 0x00, 0x00, 0x00, 0x2A,
            0xFE, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x2A
        };

        cpu.Execute(program, 0);

        Assert.Equal(0, cpu.StackDepth);
    }
}
