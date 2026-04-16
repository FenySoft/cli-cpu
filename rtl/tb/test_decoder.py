# hu: CLI-CPU Decoder cocotb tesztek — a cilcpu_decoder.v kombinációs dekóder
#     verifikálása a C# TDecoder.cs Decode() metódusával szemben, bit-tökéletesen.
#     Minden CIL-T0 dekódolási eset lefedve: egybyte-os, 2-byte-os (unsigned és
#     signed), 5-byte-os, FE-prefix, érvénytelen opkód, truncated operandus.
#     Oracle: src/CilCpu.Sim/TDecoder.cs — a hardvernek ezt kell leutánoznia.
# en: CLI-CPU Decoder cocotb tests — bit-perfect verification of cilcpu_decoder.v
#     combinational decoder against C# TDecoder.cs Decode() method.
#     All CIL-T0 decoding cases covered: single-byte, 2-byte unsigned index,
#     2-byte signed, 5-byte, FE-prefix, invalid opcode, truncated operand.
#     Oracle: src/CilCpu.Sim/TDecoder.cs — hardware must replicate this exactly.

import cocotb
from cocotb.triggers import Timer

# ============================================================
# Opkód konstansok (TOpcode.cs értékek alapján)
# Opcode constants (from TOpcode.cs values)
# ============================================================

# -- Egybyte-os opkódok / Single-byte opcodes --
OP_NOP        = 0x00
OP_LDARG0     = 0x02
OP_LDARG1     = 0x03
OP_LDARG2     = 0x04
OP_LDARG3     = 0x05
OP_LDLOC0     = 0x06
OP_LDLOC1     = 0x07
OP_LDLOC2     = 0x08
OP_LDLOC3     = 0x09
OP_STLOC0     = 0x0A
OP_STLOC1     = 0x0B
OP_STLOC2     = 0x0C
OP_STLOC3     = 0x0D
OP_LDNULL     = 0x14
OP_LDC_I4_M1  = 0x15
OP_LDC_I4_0   = 0x16
OP_LDC_I4_1   = 0x17
OP_LDC_I4_2   = 0x18
OP_LDC_I4_3   = 0x19
OP_LDC_I4_4   = 0x1A
OP_LDC_I4_5   = 0x1B
OP_LDC_I4_6   = 0x1C
OP_LDC_I4_7   = 0x1D
OP_LDC_I4_8   = 0x1E
OP_DUP        = 0x25
OP_POP        = 0x26
OP_RET        = 0x2A
OP_LDIND_I4   = 0x4A
OP_STIND_I4   = 0x54
OP_ADD        = 0x58
OP_SUB        = 0x59
OP_MUL        = 0x5A
OP_DIV        = 0x5B
OP_REM        = 0x5D
OP_AND        = 0x5F
OP_OR         = 0x60
OP_XOR        = 0x61
OP_SHL        = 0x62
OP_SHR        = 0x63
OP_SHR_UN     = 0x64
OP_NEG        = 0x65
OP_NOT        = 0x66
OP_BREAK      = 0xDD

# -- 2-byte unsigned index opkódok / 2-byte unsigned index opcodes --
OP_LDARG_S    = 0x0E   # ldarg.s <ub>
OP_STARG_S    = 0x10   # starg.s <ub>
OP_LDLOC_S    = 0x11   # ldloc.s <ub>
OP_STLOC_S    = 0x13   # stloc.s <ub>

# -- 2-byte signed operandus opkódok / 2-byte signed operand opcodes --
OP_LDC_I4_S   = 0x1F   # ldc.i4.s <sb>
OP_BR_S       = 0x2B   # br.s <sb>
OP_BRFALSE_S  = 0x2C   # brfalse.s <sb>
OP_BRTRUE_S   = 0x2D   # brtrue.s <sb>
OP_BEQ_S      = 0x2E   # beq.s <sb>
OP_BGE_S      = 0x2F   # bge.s <sb>
OP_BGT_S      = 0x30   # bgt.s <sb>
OP_BLE_S      = 0x31   # ble.s <sb>
OP_BLT_S      = 0x32   # blt.s <sb>
OP_BNE_UN_S   = 0x33   # bne.un.s <sb>

# -- 5-byte opkódok / 5-byte opcodes --
OP_LDC_I4     = 0x20   # ldc.i4 <i4> — 4 byte LE immediate
OP_CALL       = 0x28   # call <rva4> — 4 byte LE absolute target

# -- 0xFE prefix opkódok (16-bit értékek) / FE-prefix opcodes (16-bit values) --
OP_CEQ        = 0xFE01
OP_CGT        = 0xFE02
OP_CGT_UN     = 0xFE03
OP_CLT        = 0xFE04
OP_CLT_UN     = 0xFE05

# -- Segéd konstansok / Helper constants --
INT_MIN = 0x80000000  # -2147483648 as u32
INT_MAX = 0x7FFFFFFF  # 2147483647
U32_MAX = 0xFFFFFFFF  # -1 as u32


def to_u32(val):
    """Signed int → unsigned 32-bit (Verilog representation)."""
    return val & 0xFFFFFFFF


def to_s32(val):
    """Unsigned 32-bit → signed int."""
    val = val & 0xFFFFFFFF
    if val >= 0x80000000:
        return val - 0x100000000
    return val


async def decode(dut, b0=0, b1=0, b2=0, b3=0, b4=0, avail=5):
    """
    hu: Beállítja a dekóder bemeneteit és vár 1 ns-t a kombinációs jelterjedésre.
    en: Sets decoder inputs and waits 1 ns for combinational propagation.
    """
    dut.i_byte0.value = b0 & 0xFF
    dut.i_byte1.value = b1 & 0xFF
    dut.i_byte2.value = b2 & 0xFF
    dut.i_byte3.value = b3 & 0xFF
    dut.i_byte4.value = b4 & 0xFF
    dut.i_bytes_available.value = avail & 0x7
    await Timer(1, units="ns")


async def check_ok(dut, exp_opcode, exp_length, exp_operand, msg=""):
    """
    hu: Sikeres dekódolást ellenőriz: o_trap_invalid==0, és az összes
        kimenet megegyezik a várt értékekkel.
    en: Asserts successful decode: o_trap_invalid==0 and all outputs
        match expected values.
    """
    assert int(dut.o_trap_invalid.value) == 0, \
        f"{msg}: unexpected trap (o_trap_invalid=1)"
    assert int(dut.o_opcode.value) == exp_opcode, \
        f"{msg}: opcode expected {exp_opcode:#06x}, got {int(dut.o_opcode.value):#06x}"
    assert int(dut.o_length.value) == exp_length, \
        f"{msg}: length expected {exp_length}, got {int(dut.o_length.value)}"
    assert int(dut.o_operand.value) == to_u32(exp_operand), \
        f"{msg}: operand expected {to_u32(exp_operand):#010x}, got {int(dut.o_operand.value):#010x}"


async def check_trap(dut, msg=""):
    """
    hu: Trap állapotot ellenőriz: o_trap_invalid==1, o_length==0,
        o_opcode==0, o_operand==0. Minden feltétel kötelező.
    en: Asserts trap state: o_trap_invalid==1, o_length==0,
        o_opcode==0, o_operand==0. All conditions are mandatory.
    """
    assert int(dut.o_trap_invalid.value) == 1, \
        f"{msg}: expected trap (o_trap_invalid=1) but got 0"
    assert int(dut.o_length.value) == 0, \
        f"{msg}: trap must yield o_length=0, got {int(dut.o_length.value)}"
    assert int(dut.o_opcode.value) == 0, \
        f"{msg}: trap must yield o_opcode=0, got {int(dut.o_opcode.value):#06x}"
    assert int(dut.o_operand.value) == 0, \
        f"{msg}: trap must yield o_operand=0, got {int(dut.o_operand.value):#010x}"


# ============================================================
# 1. Egybyte-os opkódok / Single-byte opcodes (43 darab / 43 items)
#    o_opcode = {0x00, byte}, o_length = 1, o_operand = 0, o_trap_invalid = 0
# ============================================================

SINGLE_BYTE_OPCODES = [
    (OP_NOP,       "Nop       0x00"),
    (OP_LDARG0,    "Ldarg0    0x02"),
    (OP_LDARG1,    "Ldarg1    0x03"),
    (OP_LDARG2,    "Ldarg2    0x04"),
    (OP_LDARG3,    "Ldarg3    0x05"),
    (OP_LDLOC0,    "Ldloc0    0x06"),
    (OP_LDLOC1,    "Ldloc1    0x07"),
    (OP_LDLOC2,    "Ldloc2    0x08"),
    (OP_LDLOC3,    "Ldloc3    0x09"),
    (OP_STLOC0,    "Stloc0    0x0A"),
    (OP_STLOC1,    "Stloc1    0x0B"),
    (OP_STLOC2,    "Stloc2    0x0C"),
    (OP_STLOC3,    "Stloc3    0x0D"),
    (OP_LDNULL,    "Ldnull    0x14"),
    (OP_LDC_I4_M1, "LdcI4M1   0x15"),
    (OP_LDC_I4_0,  "LdcI40    0x16"),
    (OP_LDC_I4_1,  "LdcI41    0x17"),
    (OP_LDC_I4_2,  "LdcI42    0x18"),
    (OP_LDC_I4_3,  "LdcI43    0x19"),
    (OP_LDC_I4_4,  "LdcI44    0x1A"),
    (OP_LDC_I4_5,  "LdcI45    0x1B"),
    (OP_LDC_I4_6,  "LdcI46    0x1C"),
    (OP_LDC_I4_7,  "LdcI47    0x1D"),
    (OP_LDC_I4_8,  "LdcI48    0x1E"),
    (OP_DUP,       "Dup       0x25"),
    (OP_POP,       "Pop       0x26"),
    (OP_RET,       "Ret       0x2A"),
    (OP_LDIND_I4,  "LdindI4   0x4A"),
    (OP_STIND_I4,  "StindI4   0x54"),
    (OP_ADD,       "Add       0x58"),
    (OP_SUB,       "Sub       0x59"),
    (OP_MUL,       "Mul       0x5A"),
    (OP_DIV,       "Div       0x5B"),
    (OP_REM,       "Rem       0x5D"),
    (OP_AND,       "And       0x5F"),
    (OP_OR,        "Or        0x60"),
    (OP_XOR,       "Xor       0x61"),
    (OP_SHL,       "Shl       0x62"),
    (OP_SHR,       "Shr       0x63"),
    (OP_SHR_UN,    "ShrUn     0x64"),
    (OP_NEG,       "Neg       0x65"),
    (OP_NOT,       "Not       0x66"),
    (OP_BREAK,     "Break     0xDD"),
]


@cocotb.test()
async def test_single_byte_all(dut):
    """
    hu: Az összes 43 egybyte-os opkód dekódolása.
        Elvárás: o_opcode={0x00, byte}, o_length=1, o_operand=0, o_trap_invalid=0.
        A b1..b4 bemenetek véletlenszerű (0xAA..0xDD) értékre vannak állítva,
        hogy ellenőrizzük, hogy a dekóder nem veszi figyelembe őket.
    en: Decode all 43 single-byte opcodes.
        Expect: o_opcode={0x00, byte}, o_length=1, o_operand=0, o_trap_invalid=0.
        b1..b4 are set to garbage (0xAA..0xDD) to verify decoder ignores them.
    """
    for (op, name) in SINGLE_BYTE_OPCODES:
        await decode(dut, b0=op, b1=0xAA, b2=0xBB, b3=0xCC, b4=0xDD, avail=5)
        await check_ok(dut, exp_opcode=op, exp_length=1, exp_operand=0,
                       msg=f"single-byte {name}")


# ============================================================
# 2. 2-byte unsigned index (LdargS, StargS, LdlocS, StlocS)
#    Operandus: zero-extended byte (0..255)
# ============================================================

@cocotb.test()
async def test_ldarg_s_index_0(dut):
    """hu: LdargS 0x0E + index=0x00 → operand=0. en: LdargS + index=0."""
    await decode(dut, b0=OP_LDARG_S, b1=0x00, avail=2)
    await check_ok(dut, exp_opcode=OP_LDARG_S, exp_length=2, exp_operand=0,
                   msg="LdargS index=0x00")


@cocotb.test()
async def test_ldarg_s_index_ff(dut):
    """hu: LdargS 0x0E + index=0xFF → operand=255 (unsigned). en: LdargS + index=0xFF."""
    await decode(dut, b0=OP_LDARG_S, b1=0xFF, avail=2)
    await check_ok(dut, exp_opcode=OP_LDARG_S, exp_length=2, exp_operand=255,
                   msg="LdargS index=0xFF")


@cocotb.test()
async def test_starg_s_index_0(dut):
    """hu: StargS 0x10 + index=0x00 → operand=0. en: StargS + index=0."""
    await decode(dut, b0=OP_STARG_S, b1=0x00, avail=2)
    await check_ok(dut, exp_opcode=OP_STARG_S, exp_length=2, exp_operand=0,
                   msg="StargS index=0x00")


@cocotb.test()
async def test_starg_s_index_ff(dut):
    """hu: StargS 0x10 + index=0xFF → operand=255 (unsigned). en: StargS + index=0xFF."""
    await decode(dut, b0=OP_STARG_S, b1=0xFF, avail=2)
    await check_ok(dut, exp_opcode=OP_STARG_S, exp_length=2, exp_operand=255,
                   msg="StargS index=0xFF")


@cocotb.test()
async def test_ldloc_s_index_0(dut):
    """hu: LdlocS 0x11 + index=0x00 → operand=0. en: LdlocS + index=0."""
    await decode(dut, b0=OP_LDLOC_S, b1=0x00, avail=2)
    await check_ok(dut, exp_opcode=OP_LDLOC_S, exp_length=2, exp_operand=0,
                   msg="LdlocS index=0x00")


@cocotb.test()
async def test_ldloc_s_index_ff(dut):
    """hu: LdlocS 0x11 + index=0xFF → operand=255 (unsigned). en: LdlocS + index=0xFF."""
    await decode(dut, b0=OP_LDLOC_S, b1=0xFF, avail=2)
    await check_ok(dut, exp_opcode=OP_LDLOC_S, exp_length=2, exp_operand=255,
                   msg="LdlocS index=0xFF")


@cocotb.test()
async def test_stloc_s_index_0(dut):
    """hu: StlocS 0x13 + index=0x00 → operand=0. en: StlocS + index=0."""
    await decode(dut, b0=OP_STLOC_S, b1=0x00, avail=2)
    await check_ok(dut, exp_opcode=OP_STLOC_S, exp_length=2, exp_operand=0,
                   msg="StlocS index=0x00")


@cocotb.test()
async def test_stloc_s_index_ff(dut):
    """hu: StlocS 0x13 + index=0xFF → operand=255 (unsigned). en: StlocS + index=0xFF."""
    await decode(dut, b0=OP_STLOC_S, b1=0xFF, avail=2)
    await check_ok(dut, exp_opcode=OP_STLOC_S, exp_length=2, exp_operand=255,
                   msg="StlocS index=0xFF")


# ============================================================
# 3. 2-byte signed operandus (LdcI4S, BrS, BrfalseS, BrtrueS,
#    BeqS, BgeS, BgtS, BleS, BltS, BneUnS)
#    Operandus: sign-extended sbyte → int32
# ============================================================

SIGNED_2BYTE_OPCODES = [
    (OP_LDC_I4_S,  "LdcI4S  0x1F"),
    (OP_BR_S,      "BrS     0x2B"),
    (OP_BRFALSE_S, "BrfalseS 0x2C"),
    (OP_BRTRUE_S,  "BrtrueS  0x2D"),
    (OP_BEQ_S,     "BeqS    0x2E"),
    (OP_BGE_S,     "BgeS    0x2F"),
    (OP_BGT_S,     "BgtS    0x30"),
    (OP_BLE_S,     "BleS    0x31"),
    (OP_BLT_S,     "BltS    0x32"),
    (OP_BNE_UN_S,  "BneUnS  0x33"),
]


@cocotb.test()
async def test_signed_2byte_all(dut):
    """
    hu: Az összes 10 kétbyte-os signed opkód 4 tipikus operandussal.
        0x7F → +127 (max pozitív sbyte)
        0x80 → -128 (min negatív sbyte)
        0xFF → -1   (sign-extended)
        0x00 →  0   (nulla)
    en: All 10 two-byte signed opcodes with 4 typical operand values.
        0x7F → +127 (max positive sbyte)
        0x80 → -128 (min negative sbyte)
        0xFF → -1   (sign-extended)
        0x00 →  0   (zero)
    """
    test_cases = [
        (0x7F, 127,  "0x7F (+127)"),
        (0x80, -128, "0x80 (-128)"),
        (0xFF, -1,   "0xFF (-1)"),
        (0x00, 0,    "0x00 (0)"),
    ]
    for (op, name) in SIGNED_2BYTE_OPCODES:
        for (byte_val, expected_operand, val_name) in test_cases:
            await decode(dut, b0=op, b1=byte_val, avail=2)
            await check_ok(dut, exp_opcode=op, exp_length=2,
                           exp_operand=expected_operand,
                           msg=f"{name} operand={val_name}")


# ============================================================
# 4. 5-byte LdcI4 (0x20) + 4 byte little-endian immediate
#    o_operand = b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
# ============================================================

@cocotb.test()
async def test_ldc_i4_positive(dut):
    """
    hu: LdcI4 0x20 + LE bytes 0x78,0x56,0x34,0x12 → operand=0x12345678.
    en: LdcI4 0x20 + LE bytes 0x78,0x56,0x34,0x12 → operand=0x12345678.
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=5)
    await check_ok(dut, exp_opcode=OP_LDC_I4, exp_length=5,
                   exp_operand=0x12345678, msg="LdcI4 0x12345678")


@cocotb.test()
async def test_ldc_i4_minus_one(dut):
    """
    hu: LdcI4 0x20 + 0xFF,0xFF,0xFF,0xFF → operand=-1 (0xFFFFFFFF).
    en: LdcI4 0x20 + 0xFF,0xFF,0xFF,0xFF → operand=-1 (0xFFFFFFFF).
    """
    await decode(dut, b0=OP_LDC_I4, b1=0xFF, b2=0xFF, b3=0xFF, b4=0xFF, avail=5)
    await check_ok(dut, exp_opcode=OP_LDC_I4, exp_length=5,
                   exp_operand=-1, msg="LdcI4 -1")


@cocotb.test()
async def test_ldc_i4_int_max(dut):
    """
    hu: LdcI4 0x20 + 0xFF,0xFF,0xFF,0x7F → operand=2147483647 (INT_MAX).
    en: LdcI4 0x20 + 0xFF,0xFF,0xFF,0x7F → operand=2147483647 (INT_MAX).
    """
    await decode(dut, b0=OP_LDC_I4, b1=0xFF, b2=0xFF, b3=0xFF, b4=0x7F, avail=5)
    await check_ok(dut, exp_opcode=OP_LDC_I4, exp_length=5,
                   exp_operand=0x7FFFFFFF, msg="LdcI4 INT_MAX")


@cocotb.test()
async def test_ldc_i4_int_min(dut):
    """
    hu: LdcI4 0x20 + 0x00,0x00,0x00,0x80 → operand=-2147483648 (INT_MIN).
    en: LdcI4 0x20 + 0x00,0x00,0x00,0x80 → operand=-2147483648 (INT_MIN).
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x00, b2=0x00, b3=0x00, b4=0x80, avail=5)
    await check_ok(dut, exp_opcode=OP_LDC_I4, exp_length=5,
                   exp_operand=-2147483648, msg="LdcI4 INT_MIN")


@cocotb.test()
async def test_ldc_i4_zero(dut):
    """
    hu: LdcI4 0x20 + 0x00,0x00,0x00,0x00 → operand=0.
    en: LdcI4 0x20 + 0x00,0x00,0x00,0x00 → operand=0.
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x00, b2=0x00, b3=0x00, b4=0x00, avail=5)
    await check_ok(dut, exp_opcode=OP_LDC_I4, exp_length=5,
                   exp_operand=0, msg="LdcI4 0")


# ============================================================
# 5. 5-byte Call (0x28) + 4 byte little-endian RVA target
#    o_operand = b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
# ============================================================

@cocotb.test()
async def test_call_basic(dut):
    """
    hu: Call 0x28 + 0x34,0x12,0x00,0x00 → operand=0x00001234.
    en: Call 0x28 + 0x34,0x12,0x00,0x00 → operand=0x00001234.
    """
    await decode(dut, b0=OP_CALL, b1=0x34, b2=0x12, b3=0x00, b4=0x00, avail=5)
    await check_ok(dut, exp_opcode=OP_CALL, exp_length=5,
                   exp_operand=0x00001234, msg="Call RVA=0x1234")


@cocotb.test()
async def test_call_large_rva(dut):
    """
    hu: Call 0x28 + 0x78,0x56,0x34,0x12 → operand=0x12345678.
    en: Call 0x28 + 0x78,0x56,0x34,0x12 → operand=0x12345678.
    """
    await decode(dut, b0=OP_CALL, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=5)
    await check_ok(dut, exp_opcode=OP_CALL, exp_length=5,
                   exp_operand=0x12345678, msg="Call RVA=0x12345678")


@cocotb.test()
async def test_call_zero_rva(dut):
    """
    hu: Call 0x28 + 0x00,0x00,0x00,0x00 → operand=0.
    en: Call 0x28 + 0x00,0x00,0x00,0x00 → operand=0.
    """
    await decode(dut, b0=OP_CALL, b1=0x00, b2=0x00, b3=0x00, b4=0x00, avail=5)
    await check_ok(dut, exp_opcode=OP_CALL, exp_length=5,
                   exp_operand=0, msg="Call RVA=0")


@cocotb.test()
async def test_call_int_max_rva(dut):
    """
    hu: Call 0x28 + 0xFF,0xFF,0xFF,0x7F → operand=INT_MAX=2147483647.
    en: Call 0x28 + 0xFF,0xFF,0xFF,0x7F → operand=INT_MAX=2147483647.
    """
    await decode(dut, b0=OP_CALL, b1=0xFF, b2=0xFF, b3=0xFF, b4=0x7F, avail=5)
    await check_ok(dut, exp_opcode=OP_CALL, exp_length=5,
                   exp_operand=0x7FFFFFFF, msg="Call RVA=INT_MAX")


# ============================================================
# 6. FE prefix: érvényes (Ceq/Cgt/CgtUn/Clt/CltUn) + érvénytelen
#    Valid (Ceq/Cgt/CgtUn/Clt/CltUn) + invalid FE second bytes
# ============================================================

@cocotb.test()
async def test_fe_ceq(dut):
    """hu: 0xFE 0x01 → Ceq (o_opcode=0xFE01), length=2, operand=0. en: FE 01 → Ceq."""
    await decode(dut, b0=0xFE, b1=0x01, avail=2)
    await check_ok(dut, exp_opcode=OP_CEQ, exp_length=2, exp_operand=0,
                   msg="FE 01 = Ceq (0xFE01)")


@cocotb.test()
async def test_fe_cgt(dut):
    """hu: 0xFE 0x02 → Cgt (o_opcode=0xFE02), length=2, operand=0. en: FE 02 → Cgt."""
    await decode(dut, b0=0xFE, b1=0x02, avail=2)
    await check_ok(dut, exp_opcode=OP_CGT, exp_length=2, exp_operand=0,
                   msg="FE 02 = Cgt (0xFE02)")


@cocotb.test()
async def test_fe_cgt_un(dut):
    """hu: 0xFE 0x03 → CgtUn (o_opcode=0xFE03), length=2, operand=0. en: FE 03 → CgtUn."""
    await decode(dut, b0=0xFE, b1=0x03, avail=2)
    await check_ok(dut, exp_opcode=OP_CGT_UN, exp_length=2, exp_operand=0,
                   msg="FE 03 = CgtUn (0xFE03)")


@cocotb.test()
async def test_fe_clt(dut):
    """hu: 0xFE 0x04 → Clt (o_opcode=0xFE04), length=2, operand=0. en: FE 04 → Clt."""
    await decode(dut, b0=0xFE, b1=0x04, avail=2)
    await check_ok(dut, exp_opcode=OP_CLT, exp_length=2, exp_operand=0,
                   msg="FE 04 = Clt (0xFE04)")


@cocotb.test()
async def test_fe_clt_un(dut):
    """hu: 0xFE 0x05 → CltUn (o_opcode=0xFE05), length=2, operand=0. en: FE 05 → CltUn."""
    await decode(dut, b0=0xFE, b1=0x05, avail=2)
    await check_ok(dut, exp_opcode=OP_CLT_UN, exp_length=2, exp_operand=0,
                   msg="FE 05 = CltUn (0xFE05)")


@cocotb.test()
async def test_fe_invalid_00(dut):
    """hu: 0xFE 0x00 → érvénytelen FE opkód → trap. en: FE 00 → invalid FE opcode → trap."""
    await decode(dut, b0=0xFE, b1=0x00, avail=2)
    await check_trap(dut, msg="FE 00 invalid")


@cocotb.test()
async def test_fe_invalid_06(dut):
    """hu: 0xFE 0x06 → érvénytelen FE opkód → trap. en: FE 06 → invalid FE opcode → trap."""
    await decode(dut, b0=0xFE, b1=0x06, avail=2)
    await check_trap(dut, msg="FE 06 invalid")


@cocotb.test()
async def test_fe_invalid_ff(dut):
    """hu: 0xFE 0xFF → érvénytelen FE opkód → trap. en: FE FF → invalid FE opcode → trap."""
    await decode(dut, b0=0xFE, b1=0xFF, avail=2)
    await check_trap(dut, msg="FE FF invalid")


# ============================================================
# 7. Érvénytelen egybyte opkódok / Invalid single-byte opcodes
#    Ezek nem definiált CIL-T0 opkódok — trap-et várunk.
#    These are undefined CIL-T0 opcodes — expect trap.
# ============================================================

INVALID_SINGLE_BYTES = [
    0x01,  # undefined (0x00=nop, 0x02=ldarg.0)
    0x0F,  # undefined (0x0E=ldarg.s, 0x10=starg.s)
    0x12,  # undefined (0x11=ldloc.s, 0x13=stloc.s)
    0x21,  # undefined (0x20=ldc.i4, 0x25=dup)
    0x22,  # undefined
    0x23,  # undefined
    0x24,  # undefined
    0x27,  # undefined (0x26=pop, 0x28=call)
    0x29,  # undefined (0x28=call, 0x2A=ret)
    0x34,  # undefined (0x33=bne.un.s, 0x58=add)
    0x49,  # undefined (0x4A=ldind.i4)
    0x4B,  # undefined (0x4A=ldind.i4)
    0x4C,  # undefined
    0x4D,  # undefined
    0x5C,  # undefined (0x5B=div, 0x5D=rem)
    0x5E,  # undefined (0x5D=rem, 0x5F=and)
    0x67,  # undefined (0x66=not)
    0xDC,  # undefined (0xDD=break)
    0xDE,  # undefined (0xDD=break)
    0xFD,  # undefined (not a valid prefix)
    0xFF,  # undefined
]


@cocotb.test()
async def test_invalid_single_byte_all(dut):
    """
    hu: Az összes érvénytelen egybyte opkód → trap.
        Ezek nem szerepelnek a TDecoder.cs switch-esetei között.
    en: All invalid single-byte opcodes → trap.
        These are not handled in TDecoder.cs switch cases.
    """
    for op in INVALID_SINGLE_BYTES:
        await decode(dut, b0=op, b1=0x00, b2=0x00, b3=0x00, b4=0x00, avail=5)
        await check_trap(dut, msg=f"invalid opcode 0x{op:02X}")


# ============================================================
# 8. Truncated operandus / Truncated operand
#    Ha az i_bytes_available kisebb a szükségesnél → trap.
#    If i_bytes_available < required for opcode → trap.
# ============================================================

@cocotb.test()
async def test_truncated_avail_zero(dut):
    """
    hu: i_bytes_available=0 → trap, nincs mit dekódolni (Nop tesztelve).
    en: i_bytes_available=0 → trap, nothing to decode (tested with Nop).
    """
    await decode(dut, b0=OP_NOP, b1=0x00, b2=0x00, b3=0x00, b4=0x00, avail=0)
    await check_trap(dut, msg="avail=0 (Nop, semmi sem érhető el / nothing available)")


@cocotb.test()
async def test_truncated_ldarg_s_avail_1(dut):
    """
    hu: LdargS (2-byte opkód) + avail=1 → trap (az operandus byte hiányzik).
    en: LdargS (2-byte opcode) + avail=1 → trap (operand byte missing).
    """
    await decode(dut, b0=OP_LDARG_S, b1=0x05, b2=0x00, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="LdargS avail=1 truncated")


@cocotb.test()
async def test_truncated_starg_s_avail_1(dut):
    """
    hu: StargS (2-byte opkód) + avail=1 → trap.
    en: StargS (2-byte opcode) + avail=1 → trap.
    """
    await decode(dut, b0=OP_STARG_S, b1=0x05, b2=0x00, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="StargS avail=1 truncated")


@cocotb.test()
async def test_truncated_ldc_i4_s_avail_1(dut):
    """
    hu: LdcI4S (2-byte signed opkód) + avail=1 → trap.
    en: LdcI4S (2-byte signed opcode) + avail=1 → trap.
    """
    await decode(dut, b0=OP_LDC_I4_S, b1=0xFF, b2=0x00, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="LdcI4S avail=1 truncated")


@cocotb.test()
async def test_truncated_br_s_avail_1(dut):
    """
    hu: BrS (2-byte signed branch) + avail=1 → trap.
    en: BrS (2-byte signed branch) + avail=1 → trap.
    """
    await decode(dut, b0=OP_BR_S, b1=0x10, b2=0x00, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="BrS avail=1 truncated")


@cocotb.test()
async def test_truncated_ldc_i4_avail_1(dut):
    """
    hu: LdcI4 (5-byte opkód) + avail=1 → trap (4 operandus byte hiányzik).
    en: LdcI4 (5-byte opcode) + avail=1 → trap (4 operand bytes missing).
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=1)
    await check_trap(dut, msg="LdcI4 avail=1 truncated")


@cocotb.test()
async def test_truncated_ldc_i4_avail_2(dut):
    """
    hu: LdcI4 (5-byte opkód) + avail=2 → trap.
    en: LdcI4 (5-byte opcode) + avail=2 → trap.
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=2)
    await check_trap(dut, msg="LdcI4 avail=2 truncated")


@cocotb.test()
async def test_truncated_ldc_i4_avail_3(dut):
    """
    hu: LdcI4 (5-byte opkód) + avail=3 → trap.
    en: LdcI4 (5-byte opcode) + avail=3 → trap.
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=3)
    await check_trap(dut, msg="LdcI4 avail=3 truncated")


@cocotb.test()
async def test_truncated_ldc_i4_avail_4(dut):
    """
    hu: LdcI4 (5-byte opkód) + avail=4 → trap (az utolsó byte hiányzik).
    en: LdcI4 (5-byte opcode) + avail=4 → trap (last byte missing).
    """
    await decode(dut, b0=OP_LDC_I4, b1=0x78, b2=0x56, b3=0x34, b4=0x12, avail=4)
    await check_trap(dut, msg="LdcI4 avail=4 truncated")


@cocotb.test()
async def test_truncated_call_avail_1(dut):
    """
    hu: Call (5-byte opkód) + avail=1 → trap.
    en: Call (5-byte opcode) + avail=1 → trap.
    """
    await decode(dut, b0=OP_CALL, b1=0x34, b2=0x12, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="Call avail=1 truncated")


@cocotb.test()
async def test_truncated_call_avail_2(dut):
    """
    hu: Call (5-byte opkód) + avail=2 → trap.
    en: Call (5-byte opcode) + avail=2 → trap.
    """
    await decode(dut, b0=OP_CALL, b1=0x34, b2=0x12, b3=0x00, b4=0x00, avail=2)
    await check_trap(dut, msg="Call avail=2 truncated")


@cocotb.test()
async def test_truncated_call_avail_3(dut):
    """
    hu: Call (5-byte opkód) + avail=3 → trap.
    en: Call (5-byte opcode) + avail=3 → trap.
    """
    await decode(dut, b0=OP_CALL, b1=0x34, b2=0x12, b3=0x00, b4=0x00, avail=3)
    await check_trap(dut, msg="Call avail=3 truncated")


@cocotb.test()
async def test_truncated_call_avail_4(dut):
    """
    hu: Call (5-byte opkód) + avail=4 → trap (az utolsó byte hiányzik).
    en: Call (5-byte opcode) + avail=4 → trap (last byte missing).
    """
    await decode(dut, b0=OP_CALL, b1=0x34, b2=0x12, b3=0x00, b4=0x00, avail=4)
    await check_trap(dut, msg="Call avail=4 truncated")


@cocotb.test()
async def test_truncated_fe_avail_1(dut):
    """
    hu: 0xFE prefix + avail=1 → trap (a második byte hiányzik).
        A Ceq byte-értéke (0x01) be van töltve b1-be, de avail=1 miatt
        a dekóder nem láthatja.
    en: 0xFE prefix + avail=1 → trap (second byte missing).
        Ceq byte (0x01) is loaded into b1 but decoder must not see it.
    """
    await decode(dut, b0=0xFE, b1=0x01, b2=0x00, b3=0x00, b4=0x00, avail=1)
    await check_trap(dut, msg="FE prefix avail=1 truncated")


# ============================================================
# EXPECTED RED (TDD phase 1) / VÁRT PIROS (TDD 1. fázis)
#
# hu: Ezek a tesztek PIROSAK (buknak), amíg az implementer el nem készíti
#     a cilcpu_decoder.v Verilog modult. Ez a TDD első fázisa — a tesztek
#     az elvárást rögzítik a hardver felé, nem az implementációt.
#     Futtasd a teszteket `make test_decoder` paranccsal a rtl/tb/ könyvtárban.
#     Az összes teszt pirosra kell buknia, amíg a .v fájl nem létezik.
#
# en: These tests are RED (failing) until the implementer creates the
#     cilcpu_decoder.v Verilog module. This is TDD phase 1 — the tests
#     capture the requirements for the hardware, not the implementation.
#     Run tests with `make test_decoder` in the rtl/tb/ directory.
#     All tests must fail (red) as long as the .v file does not exist.
# ============================================================
