namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: TCpuNano iter. 3 integrációs tesztek: olyan kis CIL-T0 programok,
/// amelyek több opkód-kategóriát összekapcsolnak — egy számláló cikluson
/// keresztül összegzés (Sum 1..10), és egy max(a,b) elágazás. Ezek a
/// tesztek bizonyítják, hogy az aritmetika, az összehasonlítás és a
/// branch opkódok együttesen, valódi programszerű forgatókönyvekben is
/// helyesen működnek.
/// <br />
/// en: TCpuNano iter. 3 integration tests: small CIL-T0 programs combining
/// several opcode categories — summation through a counter loop (Sum 1..10)
/// and a max(a, b) branch. These tests prove that arithmetic, comparison
/// and branch opcodes work together correctly in realistic, program-like
/// scenarios.
/// </summary>
public class TCpuIter3IntegrationTests
{
    /// <summary>
    /// hu: Sum 1..10 = 55 számláló ciklussal:
    /// <code>
    /// s = 0; i = 1
    /// LOOP:
    ///   if (i &gt; 10) goto END
    ///   s = s + i
    ///   i = i + 1
    ///   goto LOOP
    /// END:
    ///   push s
    /// </code>
    /// A program a végén a stack tetején tartja az 55-öt.
    /// <br />
    /// en: Sum 1..10 = 55 with a counter loop. The program leaves 55 on
    /// the top of the stack.
    /// </summary>
    [Fact]
    public void Execute_Sum1To10_Returns55()
    {
        var cpu = new TCpuNano();
        // local 0 = s (sum), local 1 = i (counter)
        // 0:  ldc.i4.0       (push 0)
        // 1:  stloc.0        (s = 0)
        // 2:  ldc.i4.1       (push 1)
        // 3:  stloc.1        (i = 1)
        // 4:  ldloc.1        (push i)                 ← LOOP (PC=4)
        // 5:  ldc.i4.s 10
        // 7:  bgt.s +12 → target = 7+2+12 = 21        (END)
        // 9:  ldloc.0
        // 10: ldloc.1
        // 11: add
        // 12: stloc.0        (s = s + i)
        // 13: ldloc.1
        // 14: ldc.i4.1
        // 15: add
        // 16: stloc.1        (i = i + 1)
        // 17: br.s -15 → target = 17+2-15 = 4         (LOOP)
        // 19: nop            (padding for clarity, never reached)
        // 20: nop
        // 21: ldloc.0        (push s)                  ← END
        // 22: end
        var program = new byte[]
        {
            0x16,             // 0:  ldc.i4.0
            0x0A,             // 1:  stloc.0
            0x17,             // 2:  ldc.i4.1
            0x0B,             // 3:  stloc.1
            0x07,             // 4:  ldloc.1            (LOOP)
            0x1F, 0x0A,       // 5:  ldc.i4.s 10
            0x30, 0x0C,       // 7:  bgt.s +12 → 21 (END)
            0x06,             // 9:  ldloc.0
            0x07,             // 10: ldloc.1
            0x58,             // 11: add
            0x0A,             // 12: stloc.0
            0x07,             // 13: ldloc.1
            0x17,             // 14: ldc.i4.1
            0x58,             // 15: add
            0x0B,             // 16: stloc.1
            0x2B, 0xF1,       // 17: br.s -15 → 4 (LOOP)
            0x00,             // 19: nop (padding)
            0x00,             // 20: nop (padding)
            0x06              // 21: ldloc.0           (END)
        };

        cpu.Execute(program, 0, 2);

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(55, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Max(a, b): két argumentum közül a nagyobbat hagyja a stack tetején.
    /// <code>
    /// ldarg.0 ldarg.1 bgt.s L1
    /// ldarg.1 br.s END
    /// L1: ldarg.0
    /// END:
    /// </code>
    /// Bemenet: a = 7, b = 12 → várva 12.
    /// <br />
    /// en: Max(a, b): leaves the larger of two arguments on the stack top.
    /// Input a = 7, b = 12 → expected 12.
    /// </summary>
    [Fact]
    public void Execute_MaxAB_FirstSmaller_ReturnsB()
    {
        var cpu = new TCpuNano();
        // 0: ldarg.0
        // 1: ldarg.1
        // 2: bgt.s +3 → target = 2+2+3 = 7  (L1)
        // 4: ldarg.1
        // 5: br.s +1 → target = 5+2+1 = 8   (END)
        // 7: ldarg.0                         (L1)
        // 8: end                             (END)
        var program = new byte[]
        {
            0x02,       // 0: ldarg.0
            0x03,       // 1: ldarg.1
            0x30, 0x03, // 2: bgt.s +3 → 7
            0x03,       // 4: ldarg.1
            0x2B, 0x01, // 5: br.s +1 → 8
            0x02        // 7: ldarg.0
        };

        cpu.Execute(program, 2, 0, new[] { 7, 12 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(12, cpu.Peek(0));
    }

    /// <summary>
    /// hu: Max(a, b) második esete: a = 20, b = 5 → várva 20.
    /// <br />
    /// en: Max(a, b) second case: a = 20, b = 5 → expected 20.
    /// </summary>
    [Fact]
    public void Execute_MaxAB_FirstLarger_ReturnsA()
    {
        var cpu = new TCpuNano();
        var program = new byte[]
        {
            0x02,       // 0: ldarg.0
            0x03,       // 1: ldarg.1
            0x30, 0x03, // 2: bgt.s +3 → 7
            0x03,       // 4: ldarg.1
            0x2B, 0x01, // 5: br.s +1 → 8
            0x02        // 7: ldarg.0
        };

        cpu.Execute(program, 2, 0, new[] { 20, 5 });

        Assert.Equal(1, cpu.StackDepth);
        Assert.Equal(20, cpu.Peek(0));
    }
}
