namespace CilCpu.Sim;

/// <summary>
/// hu: A CIL-T0 subset opkódjai logikai azonosítóként, a <c>docs/ISA-CIL-T0.md</c>
/// szerint. Az egybyte-os opkódok értéke a standard ECMA-335 bájt (pl. <c>nop = 0x00</c>);
/// a kétbyte-os (<c>0xFE</c> prefix) opkódok pedig a prefix + követő byte kombinált
/// 16-bites értéke, big-endian módon (pl. <c>ceq = 0xFE01</c>). Ez lehetővé teszi,
/// hogy a <see cref="TDecoder"/> egyetlen <c>TOpcode</c> értékkel azonosítson
/// minden utasítást, a switch-ek pedig olvashatóak és auditálhatóak maradjanak.
/// <br />
/// en: CIL-T0 subset opcodes as logical identifiers per <c>docs/ISA-CIL-T0.md</c>.
/// Single-byte opcodes use the standard ECMA-335 byte (e.g. <c>nop = 0x00</c>);
/// two-byte (<c>0xFE</c> prefix) opcodes use the combined 16-bit value of prefix
/// plus following byte, big-endian (e.g. <c>ceq = 0xFE01</c>). This lets
/// <see cref="TDecoder"/> identify every instruction with a single <c>TOpcode</c>
/// value while keeping switch tables readable and auditable.
/// </summary>
public enum TOpcode : ushort
{
    /// <summary>
    /// hu: <c>nop</c> (0x00) — nincs művelet.
    /// <br />
    /// en: <c>nop</c> (0x00) — no operation.
    /// </summary>
    Nop = 0x00,

    /// <summary>
    /// hu: <c>ldarg.0</c> (0x02) — argumentum 0 push.
    /// <br />
    /// en: <c>ldarg.0</c> (0x02) — push argument 0.
    /// </summary>
    Ldarg0 = 0x02,

    /// <summary>
    /// hu: <c>ldarg.1</c> (0x03) — argumentum 1 push.
    /// <br />
    /// en: <c>ldarg.1</c> (0x03) — push argument 1.
    /// </summary>
    Ldarg1 = 0x03,

    /// <summary>
    /// hu: <c>ldarg.2</c> (0x04) — argumentum 2 push.
    /// <br />
    /// en: <c>ldarg.2</c> (0x04) — push argument 2.
    /// </summary>
    Ldarg2 = 0x04,

    /// <summary>
    /// hu: <c>ldarg.3</c> (0x05) — argumentum 3 push.
    /// <br />
    /// en: <c>ldarg.3</c> (0x05) — push argument 3.
    /// </summary>
    Ldarg3 = 0x05,

    /// <summary>
    /// hu: <c>ldloc.0</c> (0x06) — lokális 0 push.
    /// <br />
    /// en: <c>ldloc.0</c> (0x06) — push local 0.
    /// </summary>
    Ldloc0 = 0x06,

    /// <summary>
    /// hu: <c>ldloc.1</c> (0x07) — lokális 1 push.
    /// <br />
    /// en: <c>ldloc.1</c> (0x07) — push local 1.
    /// </summary>
    Ldloc1 = 0x07,

    /// <summary>
    /// hu: <c>ldloc.2</c> (0x08) — lokális 2 push.
    /// <br />
    /// en: <c>ldloc.2</c> (0x08) — push local 2.
    /// </summary>
    Ldloc2 = 0x08,

    /// <summary>
    /// hu: <c>ldloc.3</c> (0x09) — lokális 3 push.
    /// <br />
    /// en: <c>ldloc.3</c> (0x09) — push local 3.
    /// </summary>
    Ldloc3 = 0x09,

    /// <summary>
    /// hu: <c>stloc.0</c> (0x0A) — TOS pop → lokális 0.
    /// <br />
    /// en: <c>stloc.0</c> (0x0A) — pop TOS → local 0.
    /// </summary>
    Stloc0 = 0x0A,

    /// <summary>
    /// hu: <c>stloc.1</c> (0x0B) — TOS pop → lokális 1.
    /// <br />
    /// en: <c>stloc.1</c> (0x0B) — pop TOS → local 1.
    /// </summary>
    Stloc1 = 0x0B,

    /// <summary>
    /// hu: <c>stloc.2</c> (0x0C) — TOS pop → lokális 2.
    /// <br />
    /// en: <c>stloc.2</c> (0x0C) — pop TOS → local 2.
    /// </summary>
    Stloc2 = 0x0C,

    /// <summary>
    /// hu: <c>stloc.3</c> (0x0D) — TOS pop → lokális 3.
    /// <br />
    /// en: <c>stloc.3</c> (0x0D) — pop TOS → local 3.
    /// </summary>
    Stloc3 = 0x0D,

    /// <summary>
    /// hu: <c>ldarg.s &lt;ub&gt;</c> (0x0E) — argumentum push adott indexről.
    /// <br />
    /// en: <c>ldarg.s &lt;ub&gt;</c> (0x0E) — push argument at given index.
    /// </summary>
    LdargS = 0x0E,

    /// <summary>
    /// hu: <c>starg.s &lt;ub&gt;</c> (0x10) — TOS pop → argumentum adott indexre.
    /// <br />
    /// en: <c>starg.s &lt;ub&gt;</c> (0x10) — pop TOS → argument at given index.
    /// </summary>
    StargS = 0x10,

    /// <summary>
    /// hu: <c>ldloc.s &lt;ub&gt;</c> (0x11) — lokális push adott indexről.
    /// <br />
    /// en: <c>ldloc.s &lt;ub&gt;</c> (0x11) — push local at given index.
    /// </summary>
    LdlocS = 0x11,

    /// <summary>
    /// hu: <c>stloc.s &lt;ub&gt;</c> (0x13) — TOS pop → lokális adott indexre.
    /// <br />
    /// en: <c>stloc.s &lt;ub&gt;</c> (0x13) — pop TOS → local at given index.
    /// </summary>
    StlocS = 0x13,

    /// <summary>
    /// hu: <c>ldnull</c> (0x14) — 0 push (null mint I4).
    /// <br />
    /// en: <c>ldnull</c> (0x14) — push 0 (null as I4).
    /// </summary>
    Ldnull = 0x14,

    /// <summary>
    /// hu: <c>ldc.i4.m1</c> (0x15) — −1 push.
    /// <br />
    /// en: <c>ldc.i4.m1</c> (0x15) — push −1.
    /// </summary>
    LdcI4M1 = 0x15,

    /// <summary>
    /// hu: <c>ldc.i4.0</c> (0x16) — 0 push.
    /// <br />
    /// en: <c>ldc.i4.0</c> (0x16) — push 0.
    /// </summary>
    LdcI40 = 0x16,

    /// <summary>
    /// hu: <c>ldc.i4.1</c> (0x17) — 1 push.
    /// <br />
    /// en: <c>ldc.i4.1</c> (0x17) — push 1.
    /// </summary>
    LdcI41 = 0x17,

    /// <summary>
    /// hu: <c>ldc.i4.2</c> (0x18) — 2 push.
    /// <br />
    /// en: <c>ldc.i4.2</c> (0x18) — push 2.
    /// </summary>
    LdcI42 = 0x18,

    /// <summary>
    /// hu: <c>ldc.i4.3</c> (0x19) — 3 push.
    /// <br />
    /// en: <c>ldc.i4.3</c> (0x19) — push 3.
    /// </summary>
    LdcI43 = 0x19,

    /// <summary>
    /// hu: <c>ldc.i4.4</c> (0x1A) — 4 push.
    /// <br />
    /// en: <c>ldc.i4.4</c> (0x1A) — push 4.
    /// </summary>
    LdcI44 = 0x1A,

    /// <summary>
    /// hu: <c>ldc.i4.5</c> (0x1B) — 5 push.
    /// <br />
    /// en: <c>ldc.i4.5</c> (0x1B) — push 5.
    /// </summary>
    LdcI45 = 0x1B,

    /// <summary>
    /// hu: <c>ldc.i4.6</c> (0x1C) — 6 push.
    /// <br />
    /// en: <c>ldc.i4.6</c> (0x1C) — push 6.
    /// </summary>
    LdcI46 = 0x1C,

    /// <summary>
    /// hu: <c>ldc.i4.7</c> (0x1D) — 7 push.
    /// <br />
    /// en: <c>ldc.i4.7</c> (0x1D) — push 7.
    /// </summary>
    LdcI47 = 0x1D,

    /// <summary>
    /// hu: <c>ldc.i4.8</c> (0x1E) — 8 push.
    /// <br />
    /// en: <c>ldc.i4.8</c> (0x1E) — push 8.
    /// </summary>
    LdcI48 = 0x1E,

    /// <summary>
    /// hu: <c>ldc.i4.s &lt;sb&gt;</c> (0x1F) — 8-bit immediate sign-extend push.
    /// <br />
    /// en: <c>ldc.i4.s &lt;sb&gt;</c> (0x1F) — sign-extended 8-bit immediate push.
    /// </summary>
    LdcI4S = 0x1F,

    /// <summary>
    /// hu: <c>ldc.i4 &lt;i4&gt;</c> (0x20) — 32-bit immediate push (little-endian).
    /// <br />
    /// en: <c>ldc.i4 &lt;i4&gt;</c> (0x20) — 32-bit immediate push (little-endian).
    /// </summary>
    LdcI4 = 0x20,

    /// <summary>
    /// hu: <c>dup</c> (0x25) — TOS duplikálása.
    /// <br />
    /// en: <c>dup</c> (0x25) — duplicate TOS.
    /// </summary>
    Dup = 0x25,

    /// <summary>
    /// hu: <c>pop</c> (0x26) — TOS eldobása.
    /// <br />
    /// en: <c>pop</c> (0x26) — discard TOS.
    /// </summary>
    Pop = 0x26,

    /// <summary>
    /// hu: <c>br.s &lt;sb&gt;</c> (0x2B) — unconditional rövid branch.
    /// <br />
    /// en: <c>br.s &lt;sb&gt;</c> (0x2B) — unconditional short branch.
    /// </summary>
    BrS = 0x2B,

    /// <summary>
    /// hu: <c>brfalse.s &lt;sb&gt;</c> (0x2C) — TOS==0 esetén branch.
    /// <br />
    /// en: <c>brfalse.s &lt;sb&gt;</c> (0x2C) — branch if TOS == 0.
    /// </summary>
    BrfalseS = 0x2C,

    /// <summary>
    /// hu: <c>brtrue.s &lt;sb&gt;</c> (0x2D) — TOS!=0 esetén branch.
    /// <br />
    /// en: <c>brtrue.s &lt;sb&gt;</c> (0x2D) — branch if TOS != 0.
    /// </summary>
    BrtrueS = 0x2D,

    /// <summary>
    /// hu: <c>beq.s &lt;sb&gt;</c> (0x2E) — TOS-1 == TOS esetén branch.
    /// <br />
    /// en: <c>beq.s &lt;sb&gt;</c> (0x2E) — branch if TOS-1 == TOS.
    /// </summary>
    BeqS = 0x2E,

    /// <summary>
    /// hu: <c>bge.s &lt;sb&gt;</c> (0x2F) — TOS-1 ≥ TOS (signed) esetén branch.
    /// <br />
    /// en: <c>bge.s &lt;sb&gt;</c> (0x2F) — branch if TOS-1 ≥ TOS (signed).
    /// </summary>
    BgeS = 0x2F,

    /// <summary>
    /// hu: <c>bgt.s &lt;sb&gt;</c> (0x30) — TOS-1 &gt; TOS (signed) esetén branch.
    /// <br />
    /// en: <c>bgt.s &lt;sb&gt;</c> (0x30) — branch if TOS-1 &gt; TOS (signed).
    /// </summary>
    BgtS = 0x30,

    /// <summary>
    /// hu: <c>ble.s &lt;sb&gt;</c> (0x31) — TOS-1 ≤ TOS (signed) esetén branch.
    /// <br />
    /// en: <c>ble.s &lt;sb&gt;</c> (0x31) — branch if TOS-1 ≤ TOS (signed).
    /// </summary>
    BleS = 0x31,

    /// <summary>
    /// hu: <c>blt.s &lt;sb&gt;</c> (0x32) — TOS-1 &lt; TOS (signed) esetén branch.
    /// <br />
    /// en: <c>blt.s &lt;sb&gt;</c> (0x32) — branch if TOS-1 &lt; TOS (signed).
    /// </summary>
    BltS = 0x32,

    /// <summary>
    /// hu: <c>bne.un.s &lt;sb&gt;</c> (0x33) — TOS-1 != TOS esetén branch.
    /// <br />
    /// en: <c>bne.un.s &lt;sb&gt;</c> (0x33) — branch if TOS-1 != TOS.
    /// </summary>
    BneUnS = 0x33,

    /// <summary>
    /// hu: <c>add</c> (0x58) — TOS-1 + TOS, wrap.
    /// <br />
    /// en: <c>add</c> (0x58) — TOS-1 + TOS, wrapping.
    /// </summary>
    Add = 0x58,

    /// <summary>
    /// hu: <c>sub</c> (0x59) — TOS-1 − TOS, wrap.
    /// <br />
    /// en: <c>sub</c> (0x59) — TOS-1 − TOS, wrapping.
    /// </summary>
    Sub = 0x59,

    /// <summary>
    /// hu: <c>mul</c> (0x5A) — TOS-1 × TOS, wrap.
    /// <br />
    /// en: <c>mul</c> (0x5A) — TOS-1 × TOS, wrapping.
    /// </summary>
    Mul = 0x5A,

    /// <summary>
    /// hu: <c>div</c> (0x5B) — TOS-1 / TOS signed.
    /// <br />
    /// en: <c>div</c> (0x5B) — TOS-1 / TOS signed.
    /// </summary>
    Div = 0x5B,

    /// <summary>
    /// hu: <c>rem</c> (0x5D) — TOS-1 % TOS signed.
    /// <br />
    /// en: <c>rem</c> (0x5D) — TOS-1 % TOS signed.
    /// </summary>
    Rem = 0x5D,

    /// <summary>
    /// hu: <c>and</c> (0x5F) — TOS-1 AND TOS.
    /// <br />
    /// en: <c>and</c> (0x5F) — TOS-1 AND TOS.
    /// </summary>
    And = 0x5F,

    /// <summary>
    /// hu: <c>or</c> (0x60) — TOS-1 OR TOS.
    /// <br />
    /// en: <c>or</c> (0x60) — TOS-1 OR TOS.
    /// </summary>
    Or = 0x60,

    /// <summary>
    /// hu: <c>xor</c> (0x61) — TOS-1 XOR TOS.
    /// <br />
    /// en: <c>xor</c> (0x61) — TOS-1 XOR TOS.
    /// </summary>
    Xor = 0x61,

    /// <summary>
    /// hu: <c>shl</c> (0x62) — TOS-1 &lt;&lt; (TOS &amp; 31).
    /// <br />
    /// en: <c>shl</c> (0x62) — TOS-1 &lt;&lt; (TOS &amp; 31).
    /// </summary>
    Shl = 0x62,

    /// <summary>
    /// hu: <c>shr</c> (0x63) — TOS-1 &gt;&gt; (TOS &amp; 31) arithmetic.
    /// <br />
    /// en: <c>shr</c> (0x63) — TOS-1 &gt;&gt; (TOS &amp; 31) arithmetic.
    /// </summary>
    Shr = 0x63,

    /// <summary>
    /// hu: <c>shr.un</c> (0x64) — TOS-1 &gt;&gt; (TOS &amp; 31) logical.
    /// <br />
    /// en: <c>shr.un</c> (0x64) — TOS-1 &gt;&gt; (TOS &amp; 31) logical.
    /// </summary>
    ShrUn = 0x64,

    /// <summary>
    /// hu: <c>neg</c> (0x65) — −TOS.
    /// <br />
    /// en: <c>neg</c> (0x65) — negate TOS.
    /// </summary>
    Neg = 0x65,

    /// <summary>
    /// hu: <c>not</c> (0x66) — bitwise NOT TOS.
    /// <br />
    /// en: <c>not</c> (0x66) — bitwise NOT TOS.
    /// </summary>
    Not = 0x66,

    /// <summary>
    /// hu: <c>ceq</c> (0xFE 0x01) — TOS-1 == TOS → 1, else 0.
    /// <br />
    /// en: <c>ceq</c> (0xFE 0x01) — TOS-1 == TOS → 1, else 0.
    /// </summary>
    Ceq = 0xFE01,

    /// <summary>
    /// hu: <c>cgt</c> (0xFE 0x02) — TOS-1 &gt; TOS (signed) → 1, else 0.
    /// <br />
    /// en: <c>cgt</c> (0xFE 0x02) — TOS-1 &gt; TOS (signed) → 1, else 0.
    /// </summary>
    Cgt = 0xFE02,

    /// <summary>
    /// hu: <c>cgt.un</c> (0xFE 0x03) — TOS-1 &gt; TOS (unsigned) → 1, else 0.
    /// <br />
    /// en: <c>cgt.un</c> (0xFE 0x03) — TOS-1 &gt; TOS (unsigned) → 1, else 0.
    /// </summary>
    CgtUn = 0xFE03,

    /// <summary>
    /// hu: <c>clt</c> (0xFE 0x04) — TOS-1 &lt; TOS (signed) → 1, else 0.
    /// <br />
    /// en: <c>clt</c> (0xFE 0x04) — TOS-1 &lt; TOS (signed) → 1, else 0.
    /// </summary>
    Clt = 0xFE04,

    /// <summary>
    /// hu: <c>clt.un</c> (0xFE 0x05) — TOS-1 &lt; TOS (unsigned) → 1, else 0.
    /// <br />
    /// en: <c>clt.un</c> (0xFE 0x05) — TOS-1 &lt; TOS (unsigned) → 1, else 0.
    /// </summary>
    CltUn = 0xFE05,

    /// <summary>
    /// hu: <c>call &lt;rva4&gt;</c> (0x28) — statikus metódus hívás.
    /// A 4 bájtos operandus a callee metódus header-jének abszolút offszete
    /// a programban (CIL-T0 előre-linkelt RVA).
    /// <br />
    /// en: <c>call &lt;rva4&gt;</c> (0x28) — static method call. The 4-byte
    /// operand is the absolute offset of the callee method header in the
    /// program (CIL-T0 pre-linked RVA).
    /// </summary>
    Call = 0x28,

    /// <summary>
    /// hu: <c>ret</c> (0x2A) — visszatérés a hívóhoz. Ha a callee eval
    /// stackjén egy érték van, az lesz a return value és átkerül a caller
    /// eval stackjére.
    /// <br />
    /// en: <c>ret</c> (0x2A) — return to caller. If the callee's eval stack
    /// holds one value, it becomes the return value and is moved onto the
    /// caller's eval stack.
    /// </summary>
    Ret = 0x2A,

    /// <summary>
    /// hu: <c>ldind.i4</c> (0x4A) — TOS = cím; pop, olvas egy 32-bit
    /// little-endian int-et a data memory adott címéről, push az eredményt.
    /// Érték az ECMA-335 Partition III §3.42 szerint.
    /// <br />
    /// en: <c>ldind.i4</c> (0x4A) — TOS = address; pop, read a 32-bit
    /// little-endian int from data memory at that address, push the result.
    /// Value per ECMA-335 Partition III §3.42.
    /// </summary>
    LdindI4 = 0x4A,

    /// <summary>
    /// hu: <c>stind.i4</c> (0x54) — pop érték, pop cím, ír egy 32-bit
    /// little-endian int-et a data memory adott címére. Érték az
    /// ECMA-335 Partition III §3.64 szerint.
    /// <br />
    /// en: <c>stind.i4</c> (0x54) — pop value, pop address, write a 32-bit
    /// little-endian int to data memory at that address. Value per
    /// ECMA-335 Partition III §3.64.
    /// </summary>
    StindI4 = 0x54,

    /// <summary>
    /// hu: <c>break</c> (0xDD) — debug trap. Mindig DebugBreak trap-et dob.
    /// <br />
    /// en: <c>break</c> (0xDD) — debug trap. Always raises a DebugBreak trap.
    /// </summary>
    Break = 0xDD
}
