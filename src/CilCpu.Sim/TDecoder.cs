namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 bájtkód dekóder. A <see cref="Decode"/> metódus a megadott
/// program bájttömb adott PC-jén álló utasítást dekódolja egyetlen
/// <see cref="TDecodedOpcode"/> értékké. A dekóder két szempontból biztosít
/// teljes lefedettséget a hardveres F2 RTL felé: (1) ismeretlen opkódra
/// <see cref="TTrapReason.InvalidOpcode"/> trap, (2) truncated operandra
/// (ha az operandus a program végén túlnyúlik) szintén
/// <see cref="TTrapReason.InvalidOpcode"/> trap a hibás utasítás PC-jén.
/// A 0xFE prefixet is kezeli: ha az első bájt 0xFE, a dekóder a következő
/// bájtot olvassa, és a <see cref="TOpcode"/> prefixes értékét adja vissza.
/// <br />
/// en: CIL-T0 bytecode decoder. The <see cref="Decode"/> method decodes the
/// instruction at the given PC inside the program byte array into a single
/// <see cref="TDecodedOpcode"/> value. The decoder provides full coverage
/// for the F2 RTL in two ways: (1) unknown opcodes raise a
/// <see cref="TTrapReason.InvalidOpcode"/> trap, (2) truncated operands
/// (when the operand extends past the end of the program) also raise a
/// <see cref="TTrapReason.InvalidOpcode"/> trap at the offending instruction's
/// PC. The 0xFE prefix is handled: if the first byte is 0xFE, the decoder
/// reads the following byte and returns the prefixed <see cref="TOpcode"/>
/// value.
/// </summary>
public static class TDecoder
{
    /// <summary>
    /// hu: A megadott program bájttömb <paramref name="APc"/> pozícióján álló
    /// utasítás dekódolása. Érvénytelen opkódra vagy truncated operandra
    /// <see cref="TTrapException"/>-t dob <see cref="TTrapReason.InvalidOpcode"/>
    /// okkal és a hibás utasítás PC-jével.
    /// <br />
    /// en: Decodes the instruction at position <paramref name="APc"/> in the
    /// given program byte array. Raises a <see cref="TTrapException"/> with
    /// <see cref="TTrapReason.InvalidOpcode"/> and the offending PC for
    /// unknown opcodes or truncated operands.
    /// </summary>
    /// <param name="AProgram">
    /// hu: A CIL-T0 byte-program.
    /// <br />
    /// en: The CIL-T0 byte program.
    /// </param>
    /// <param name="APc">
    /// hu: A dekódolandó utasítás kezdő offszete a programban.
    /// <br />
    /// en: Start offset of the instruction to decode inside the program.
    /// </param>
    public static TDecodedOpcode Decode(byte[] AProgram, int APc)
    {
        ArgumentNullException.ThrowIfNull(AProgram);

        if (APc < 0 || APc >= AProgram.Length)
            throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                $"Program counter 0x{APc:X4} out of range [0, 0x{AProgram.Length:X4}).");

        var firstByte = AProgram[APc];

        // hu: 0xFE prefix — két bájtos opkód
        // en: 0xFE prefix — two-byte opcode
        if (firstByte == 0xFE)
        {
            if (APc + 1 >= AProgram.Length)
                throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                    $"Truncated 0xFE prefix at PC=0x{APc:X4}.");

            var secondByte = AProgram[APc + 1];
            var combined = (ushort)((0xFE << 8) | secondByte);

            return combined switch
            {
                (ushort)TOpcode.Ceq => new TDecodedOpcode(TOpcode.Ceq, 2, 0),
                (ushort)TOpcode.Cgt => new TDecodedOpcode(TOpcode.Cgt, 2, 0),
                (ushort)TOpcode.CgtUn => new TDecodedOpcode(TOpcode.CgtUn, 2, 0),
                (ushort)TOpcode.Clt => new TDecodedOpcode(TOpcode.Clt, 2, 0),
                (ushort)TOpcode.CltUn => new TDecodedOpcode(TOpcode.CltUn, 2, 0),
                _ => throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                    $"Invalid opcode 0xFE 0x{secondByte:X2} at PC=0x{APc:X4}.")
            };
        }

        // hu: Egybyte-os opkódok, operandus nélkül.
        // en: Single-byte opcodes without operand.
        switch (firstByte)
        {
            case (byte)TOpcode.Nop:
            case (byte)TOpcode.Ldarg0:
            case (byte)TOpcode.Ldarg1:
            case (byte)TOpcode.Ldarg2:
            case (byte)TOpcode.Ldarg3:
            case (byte)TOpcode.Ldloc0:
            case (byte)TOpcode.Ldloc1:
            case (byte)TOpcode.Ldloc2:
            case (byte)TOpcode.Ldloc3:
            case (byte)TOpcode.Stloc0:
            case (byte)TOpcode.Stloc1:
            case (byte)TOpcode.Stloc2:
            case (byte)TOpcode.Stloc3:
            case (byte)TOpcode.Ldnull:
            case (byte)TOpcode.LdcI4M1:
            case (byte)TOpcode.LdcI40:
            case (byte)TOpcode.LdcI41:
            case (byte)TOpcode.LdcI42:
            case (byte)TOpcode.LdcI43:
            case (byte)TOpcode.LdcI44:
            case (byte)TOpcode.LdcI45:
            case (byte)TOpcode.LdcI46:
            case (byte)TOpcode.LdcI47:
            case (byte)TOpcode.LdcI48:
            case (byte)TOpcode.Dup:
            case (byte)TOpcode.Pop:
            case (byte)TOpcode.Add:
            case (byte)TOpcode.Sub:
            case (byte)TOpcode.Mul:
            case (byte)TOpcode.Div:
            case (byte)TOpcode.Rem:
            case (byte)TOpcode.And:
            case (byte)TOpcode.Or:
            case (byte)TOpcode.Xor:
            case (byte)TOpcode.Shl:
            case (byte)TOpcode.Shr:
            case (byte)TOpcode.ShrUn:
            case (byte)TOpcode.Neg:
            case (byte)TOpcode.Not:
            case (byte)TOpcode.Ret:
            case (byte)TOpcode.LdindI4:
            case (byte)TOpcode.StindI4:
            case (byte)TOpcode.Break:
                return new TDecodedOpcode((TOpcode)firstByte, 1, 0);
        }

        // hu: Két bájtos opkódok unsigned index operandussal (ldarg.s, ldloc.s, starg.s, stloc.s)
        // en: Two-byte opcodes with unsigned index operand (ldarg.s, ldloc.s, starg.s, stloc.s)
        switch (firstByte)
        {
            case (byte)TOpcode.LdargS:
            case (byte)TOpcode.StargS:
            case (byte)TOpcode.LdlocS:
            case (byte)TOpcode.StlocS:
            {
                if (APc + 1 >= AProgram.Length)
                    throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                        $"Truncated operand for opcode 0x{firstByte:X2} at PC=0x{APc:X4}.");

                var index = AProgram[APc + 1];

                return new TDecodedOpcode((TOpcode)firstByte, 2, index);
            }
        }

        // hu: Két bájtos opkódok signed 8-bit operandussal (ldc.i4.s, br.s, brfalse.s, stb.)
        // en: Two-byte opcodes with signed 8-bit operand (ldc.i4.s, br.s, brfalse.s, ...)
        switch (firstByte)
        {
            case (byte)TOpcode.LdcI4S:
            case (byte)TOpcode.BrS:
            case (byte)TOpcode.BrfalseS:
            case (byte)TOpcode.BrtrueS:
            case (byte)TOpcode.BeqS:
            case (byte)TOpcode.BgeS:
            case (byte)TOpcode.BgtS:
            case (byte)TOpcode.BleS:
            case (byte)TOpcode.BltS:
            case (byte)TOpcode.BneUnS:
            {
                if (APc + 1 >= AProgram.Length)
                    throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                        $"Truncated operand for opcode 0x{firstByte:X2} at PC=0x{APc:X4}.");

                var signedByte = (sbyte)AProgram[APc + 1];

                return new TDecodedOpcode((TOpcode)firstByte, 2, signedByte);
            }
        }

        // hu: 5 byte opkód — ldc.i4 32-bit immediate
        // en: 5-byte opcode — ldc.i4 32-bit immediate
        if (firstByte == (byte)TOpcode.LdcI4)
        {
            if (APc + 4 >= AProgram.Length)
                throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                    $"Truncated ldc.i4 operand at PC=0x{APc:X4}.");

            var b0 = AProgram[APc + 1];
            var b1 = AProgram[APc + 2];
            var b2 = AProgram[APc + 3];
            var b3 = AProgram[APc + 4];
            var immediate = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);

            return new TDecodedOpcode(TOpcode.LdcI4, 5, immediate);
        }

        // hu: 5 byte opkód — call <rva4> (4 bájt absolute target offszet)
        // en: 5-byte opcode — call <rva4> (4-byte absolute target offset)
        if (firstByte == (byte)TOpcode.Call)
        {
            if (APc + 4 >= AProgram.Length)
                throw new TTrapException(TTrapReason.InvalidOpcode, APc,
                    $"Truncated call operand at PC=0x{APc:X4}.");

            var b0 = AProgram[APc + 1];
            var b1 = AProgram[APc + 2];
            var b2 = AProgram[APc + 3];
            var b3 = AProgram[APc + 4];
            var rva = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);

            return new TDecodedOpcode(TOpcode.Call, 5, rva);
        }

        // hu: Ismeretlen opkód — trap.
        // en: Unknown opcode — trap.
        throw new TTrapException(TTrapReason.InvalidOpcode, APc,
            $"Invalid opcode 0x{firstByte:X2} at PC=0x{APc:X4}.");
    }
}
