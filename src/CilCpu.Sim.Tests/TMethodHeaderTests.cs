namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TMethodHeader record unit tesztjei. A CIL-T0 metódus fejléc 8 bájt
/// hosszú: magic 0xFE, arg_count, local_count, max_stack, code_size (LE u16),
/// reserved (2 byte). A Parse metódus validálja a magic-et és a tartomány-
/// ellenőrzést.
/// <br />
/// en: Unit tests for the TMethodHeader record. The CIL-T0 method header is
/// 8 bytes long: magic 0xFE, arg_count, local_count, max_stack, code_size
/// (LE u16), reserved (2 bytes). The Parse method validates the magic and
/// performs bounds checking.
/// </summary>
public class TMethodHeaderTests
{
    /// <summary>
    /// hu: Happy path — érvényes 8 bájtos header pontosan a megadott
    /// mezőértékekkel parsolódik.
    /// <br />
    /// en: Happy path — a valid 8-byte header parses with exactly the given
    /// field values.
    /// </summary>
    [Fact]
    public void Parse_ValidHeader_ReturnsAllFields()
    {
        var program = new byte[]
        {
            0xFE, // magic
            0x02, // arg_count = 2
            0x03, // local_count = 3
            0x05, // max_stack = 5
            0x10, 0x00, // code_size = 16 (LE)
            0x00, 0x00  // reserved
        };

        var header = TMethodHeader.Parse(program, 0);

        Assert.Equal((byte)0xFE, header.Magic);
        Assert.Equal((byte)2, header.ArgCount);
        Assert.Equal((byte)3, header.LocalCount);
        Assert.Equal((byte)5, header.MaxStack);
        Assert.Equal((ushort)16, header.CodeSize);
    }

    /// <summary>
    /// hu: Header parse-olás nem 0 offszetről is működik.
    /// <br />
    /// en: Header parsing also works at non-zero offsets.
    /// </summary>
    [Fact]
    public void Parse_HeaderAtNonZeroOffset_ParsesCorrectly()
    {
        var program = new byte[20];
        program[5] = 0xFE;
        program[6] = 0x01;
        program[7] = 0x00;
        program[8] = 0x03;
        program[9] = 0x20; // code_size LSB
        program[10] = 0x01; // code_size MSB → 0x0120 = 288
        program[11] = 0x00;
        program[12] = 0x00;

        var header = TMethodHeader.Parse(program, 5);

        Assert.Equal((byte)0xFE, header.Magic);
        Assert.Equal((byte)1, header.ArgCount);
        Assert.Equal((byte)0, header.LocalCount);
        Assert.Equal((byte)3, header.MaxStack);
        Assert.Equal((ushort)288, header.CodeSize);
    }

    /// <summary>
    /// hu: Érvénytelen magic (nem 0xFE) ArgumentException-t dob.
    /// <br />
    /// en: An invalid magic byte (not 0xFE) throws ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_InvalidMagic_ThrowsArgumentException()
    {
        var program = new byte[8];
        program[0] = 0x00; // not 0xFE

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, 0));
    }

    /// <summary>
    /// hu: A header offszet a program végén túlnyúlik → ArgumentException.
    /// <br />
    /// en: A header offset reaching past the end of the program throws
    /// ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_OffsetOutOfBounds_ThrowsArgumentException()
    {
        var program = new byte[5]; // too small for an 8-byte header
        program[0] = 0xFE;

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, 0));
    }

    /// <summary>
    /// hu: Negatív offszet ArgumentException-t dob.
    /// <br />
    /// en: A negative offset throws ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_NegativeOffset_ThrowsArgumentException()
    {
        var program = new byte[16];

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, -1));
    }

    /// <summary>
    /// hu: Null program ArgumentNullException-t dob.
    /// <br />
    /// en: A null program throws ArgumentNullException.
    /// </summary>
    [Fact]
    public void Parse_NullProgram_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() => TMethodHeader.Parse(null!, 0));
    }

    /// <summary>
    /// hu: arg_count > 16 (CIL-T0 maximum) → ArgumentException.
    /// <br />
    /// en: arg_count &gt; 16 (CIL-T0 maximum) → ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_ArgCountExceedsMaximum_ThrowsArgumentException()
    {
        var program = new byte[]
        {
            0xFE,
            0x11, // arg_count = 17 → érvénytelen
            0x00,
            0x00,
            0x00, 0x00,
            0x00, 0x00
        };

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, 0));
    }

    /// <summary>
    /// hu: local_count > 16 (CIL-T0 maximum) → ArgumentException.
    /// <br />
    /// en: local_count &gt; 16 (CIL-T0 maximum) → ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_LocalCountExceedsMaximum_ThrowsArgumentException()
    {
        var program = new byte[]
        {
            0xFE,
            0x00,
            0x11, // local_count = 17 → érvénytelen
            0x00,
            0x00, 0x00,
            0x00, 0x00
        };

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, 0));
    }

    /// <summary>
    /// hu: max_stack > 64 (CIL-T0 maximum) → ArgumentException.
    /// <br />
    /// en: max_stack &gt; 64 (CIL-T0 maximum) → ArgumentException.
    /// </summary>
    [Fact]
    public void Parse_MaxStackExceedsMaximum_ThrowsArgumentException()
    {
        var program = new byte[]
        {
            0xFE,
            0x00,
            0x00,
            0x41, // max_stack = 65 → érvénytelen
            0x00, 0x00,
            0x00, 0x00
        };

        Assert.Throws<ArgumentException>(() => TMethodHeader.Parse(program, 0));
    }

    /// <summary>
    /// hu: arg_count == 16 és local_count == 16 (épp a határon) érvényes.
    /// <br />
    /// en: arg_count == 16 and local_count == 16 (exactly at the limit)
    /// is valid.
    /// </summary>
    [Fact]
    public void Parse_BoundaryArgAndLocalCounts_AreValid()
    {
        var program = new byte[]
        {
            0xFE,
            0x10, // arg_count = 16
            0x10, // local_count = 16
            0x40, // max_stack = 64
            0x00, 0x00,
            0x00, 0x00
        };

        var header = TMethodHeader.Parse(program, 0);

        Assert.Equal((byte)16, header.ArgCount);
        Assert.Equal((byte)16, header.LocalCount);
        Assert.Equal((byte)64, header.MaxStack);
    }
}
