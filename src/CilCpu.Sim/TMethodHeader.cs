namespace CilCpu.Sim;

/// <summary>
/// hu: Egy CIL-T0 metódus 8 bájtos fejléce a <c>docs/ISA-CIL-T0.md</c>
/// "CIL-T0 bináris formátum" szekciója szerint:
/// <code>
/// Offset  Méret  Mező
/// 0x00    1      Magic 0xFE
/// 0x01    1      arg_count
/// 0x02    1      local_count
/// 0x03    1      max_stack
/// 0x04    2      code_size (LE u16)
/// 0x06    2      reserved
/// </code>
/// A header közvetlenül a metódus kódjának elején helyezkedik el a CODE
/// régióban; a <c>call</c> opkód operandusa erre a magic byte-ra mutat.
/// <br />
/// en: 8-byte CIL-T0 method header per the "CIL-T0 binary format" section
/// of <c>docs/ISA-CIL-T0.md</c>. The header is located at the beginning of
/// the method code in the CODE region; the <c>call</c> opcode operand
/// points to this magic byte.
/// </summary>
/// <param name="Magic">
/// hu: Magic bájt — mindig 0xFE.
/// <br />
/// en: Magic byte — always 0xFE.
/// </param>
/// <param name="ArgCount">
/// hu: Az argumentumok száma (0..16).
/// <br />
/// en: Argument count (0..16).
/// </param>
/// <param name="LocalCount">
/// hu: A lokális változók száma (0..16).
/// <br />
/// en: Local variable count (0..16).
/// </param>
/// <param name="MaxStack">
/// hu: Az evaluation stack maximális mélysége a metódusban (0..64).
/// <br />
/// en: Maximum evaluation stack depth in this method (0..64).
/// </param>
/// <param name="CodeSize">
/// hu: A metódus kódjának hossza bájtban a header után.
/// <br />
/// en: Length of the method code in bytes after the header.
/// </param>
public readonly record struct TMethodHeader(
    byte Magic,
    byte ArgCount,
    byte LocalCount,
    byte MaxStack,
    ushort CodeSize)
{
    /// <summary>
    /// hu: A header mérete bájtban (8).
    /// <br />
    /// en: Size of the header in bytes (8).
    /// </summary>
    public const int HeaderSize = 8;

    /// <summary>
    /// hu: A header magic byte értéke (0xFE). Megegyezik a standard CIL
    /// "fat" header jelzőjével, de a CIL-T0-ban kizárólag itt fordul elő —
    /// a 0xFE prefix opkód-bájt csak a metódus body-ban szerepelhet, soha
    /// nem a header első bájtján, mert a dekóder csak a header után indul.
    /// <br />
    /// en: Header magic byte value (0xFE). Matches the standard CIL "fat"
    /// header marker, but in CIL-T0 it occurs only here — the 0xFE prefix
    /// opcode byte may only appear inside the method body, never at the
    /// header's first byte, because the decoder only starts after the header.
    /// </summary>
    public const byte MagicValue = 0xFE;

    /// <summary>
    /// hu: A megadott program byte-tömbből parse-olja a header-t a megadott
    /// offszeten. Ellenőrzi a magic-et és a határokat. Hibás adatra
    /// <see cref="ArgumentException"/>-t dob (NEM CIL trap-et — a Parse
    /// API-nem a runtime executor; a runtime külön ellenőrzi a header-t és
    /// dob <see cref="TTrapReason.InvalidCallTarget"/>-et call esetén).
    /// <br />
    /// en: Parses the header from the given program byte array at the given
    /// offset. Validates the magic and bounds. On invalid data raises
    /// <see cref="ArgumentException"/> (NOT a CIL trap — Parse is an API,
    /// not the runtime executor; the runtime separately validates the header
    /// and raises <see cref="TTrapReason.InvalidCallTarget"/> for call).
    /// </summary>
    /// <param name="AProgram">
    /// hu: A teljes program byte-tömb (CODE régió tartalma).
    /// <br />
    /// en: The full program byte array (CODE region contents).
    /// </param>
    /// <param name="AHeaderRva">
    /// hu: A header első bájtjának offszetje a programban.
    /// <br />
    /// en: Offset of the header's first byte inside the program.
    /// </param>
    public static TMethodHeader Parse(byte[] AProgram, int AHeaderRva)
    {
        ArgumentNullException.ThrowIfNull(AProgram);

        if (AHeaderRva < 0 || AHeaderRva + HeaderSize > AProgram.Length)
            throw new ArgumentException(
                $"Header offset 0x{AHeaderRva:X4} out of range for program length {AProgram.Length}.",
                nameof(AHeaderRva));

        var magic = AProgram[AHeaderRva + 0];

        if (magic != MagicValue)
            throw new ArgumentException(
                $"Invalid method header magic 0x{magic:X2} at offset 0x{AHeaderRva:X4} (expected 0x{MagicValue:X2}).",
                nameof(AProgram));

        var argCount = AProgram[AHeaderRva + 1];
        var localCount = AProgram[AHeaderRva + 2];
        var maxStack = AProgram[AHeaderRva + 3];
        var codeSize = (ushort)(AProgram[AHeaderRva + 4] | (AProgram[AHeaderRva + 5] << 8));

        if (argCount > TFrame.MaxArgs)
            throw new ArgumentException(
                $"Method header arg_count {argCount} exceeds CIL-T0 maximum {TFrame.MaxArgs} at offset 0x{AHeaderRva:X4}.",
                nameof(AProgram));

        if (localCount > TFrame.MaxLocals)
            throw new ArgumentException(
                $"Method header local_count {localCount} exceeds CIL-T0 maximum {TFrame.MaxLocals} at offset 0x{AHeaderRva:X4}.",
                nameof(AProgram));

        if (maxStack > TEvaluationStack.MaxDepth)
            throw new ArgumentException(
                $"Method header max_stack {maxStack} exceeds CIL-T0 maximum {TEvaluationStack.MaxDepth} at offset 0x{AHeaderRva:X4}.",
                nameof(AProgram));

        return new TMethodHeader(magic, argCount, localCount, maxStack, codeSize);
    }
}
