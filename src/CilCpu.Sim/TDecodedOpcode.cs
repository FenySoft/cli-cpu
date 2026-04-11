namespace CilCpu.Sim;

/// <summary>
/// hu: Egy dekódolt CIL-T0 utasítás reprezentációja: az opkód azonosítója,
/// a teljes utasítás hossza bájtban (1..5), és az opkód operandusából kiolvasott
/// int32 érték. Az <see cref="Operand"/> mező jelentése opkód-függő:
/// <list type="bullet">
/// <item>operand nélküli opkódoknál: 0.</item>
/// <item><c>ldc.i4.s</c>, <c>br.s</c> és hasonló 2-bájtos signed opkódoknál: a sign-extended sbyte érték.</item>
/// <item><c>ldarg.s</c>, <c>stloc.s</c> és hasonló 2-bájtos unsigned index opkódoknál: az unsigned byte (0..255).</item>
/// <item><c>ldc.i4</c> (5-bájtos) opkódnál: a teljes 32-bites immediate érték.</item>
/// </list>
/// A struct célja, hogy a <see cref="TDecoder"/> és a végrehajtó között tiszta,
/// allocation-free szerződést biztosítson: minden, amit a végrehajtónak tudnia kell
/// az utasításról (azonosító, hossz, operandus), egyetlen érték-típusba zárva.
/// <br />
/// en: Represents a decoded CIL-T0 instruction: the opcode identifier, the total
/// instruction length in bytes (1..5), and the int32 value extracted from the
/// opcode's operand. The meaning of <see cref="Operand"/> depends on the opcode:
/// <list type="bullet">
/// <item>for opcodes with no operand: 0.</item>
/// <item>for 2-byte signed opcodes (<c>ldc.i4.s</c>, <c>br.s</c>, ...): the sign-extended sbyte value.</item>
/// <item>for 2-byte unsigned index opcodes (<c>ldarg.s</c>, <c>stloc.s</c>, ...): the unsigned byte (0..255).</item>
/// <item>for the 5-byte <c>ldc.i4</c>: the full 32-bit immediate value.</item>
/// </list>
/// This struct gives the <see cref="TDecoder"/> and the executor an allocation-free
/// contract carrying everything the executor needs (identifier, length, operand).
/// </summary>
/// <param name="Opcode">
/// hu: A dekódolt opkód azonosítója (<see cref="TOpcode"/>).
/// <br />
/// en: The decoded opcode identifier (<see cref="TOpcode"/>).
/// </param>
/// <param name="LengthInBytes">
/// hu: Az utasítás teljes hossza bájtban (opkód bytes + operandus bytes).
/// <br />
/// en: Total instruction length in bytes (opcode bytes + operand bytes).
/// </param>
/// <param name="Operand">
/// hu: Az opkód operandusa int32-ként értelmezve (lásd fent).
/// <br />
/// en: The opcode operand interpreted as int32 (see above).
/// </param>
public readonly record struct TDecodedOpcode(TOpcode Opcode, int LengthInBytes, int Operand);
