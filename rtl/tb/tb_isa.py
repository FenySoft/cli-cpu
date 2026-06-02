# hu: CIL-T0 opcode és trap konstansok cocotb tesztekhez. Egy helyen,
#     hogy a top-level (cilcpu_tt_top) és minden további wrapper
#     teszt ugyanazt használhassa.
# en: CIL-T0 opcode and trap constants for cocotb tests. Centralized so
#     the top-level (cilcpu_tt_top) and any future wrapper test can
#     share them.

# ============================================================
# hu: Konstans opkódok (LDC) / en: Constant load opcodes (LDC)
# ============================================================
OP_NOP        = 0x00
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
OP_LDC_I4_S   = 0x1F  # + 1 byte signed operand
OP_LDC_I4     = 0x20  # + 4 byte LE operand

# ============================================================
# hu: Vezérlés / en: Control flow
# ============================================================
OP_RET        = 0x2A
OP_BR_S       = 0x2B
OP_BRFALSE_S  = 0x2C
OP_BRTRUE_S   = 0x2D
OP_BEQ_S      = 0x2E
OP_BGE_S      = 0x2F
OP_BGT_S      = 0x30
OP_BLE_S      = 0x31
OP_BLT_S      = 0x32
OP_BNE_UN_S   = 0x33
OP_CALL       = 0x28
OP_POP        = 0x26
OP_BREAK      = 0xDD

# ============================================================
# hu: ALU / en: ALU
# ============================================================
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

# ============================================================
# hu: Argument / local / en: Argument / local
# ============================================================
OP_LDARG_0    = 0x02
OP_LDARG_1    = 0x03
OP_LDARG_2    = 0x04
OP_LDARG_3    = 0x05
OP_LDARG_S    = 0x0E
OP_STARG_S    = 0x10
OP_LDLOC_0    = 0x06
OP_LDLOC_1    = 0x07
OP_LDLOC_2    = 0x08
OP_LDLOC_3    = 0x09
OP_LDLOC_S    = 0x11
OP_STLOC_0    = 0x0A
OP_STLOC_1    = 0x0B
OP_STLOC_2    = 0x0C
OP_STLOC_3    = 0x0D
OP_STLOC_S    = 0x13

# ============================================================
# hu: Trap kódok (cilcpu_defines.vh-ből)
# en: Trap codes (from cilcpu_defines.vh)
# ============================================================
TRAP_STACK_OVERFLOW       = 0x01
TRAP_STACK_UNDERFLOW      = 0x02
TRAP_INVALID_OPCODE       = 0x03
TRAP_INVALID_LOCAL        = 0x04
TRAP_INVALID_ARG          = 0x05
TRAP_INVALID_BRANCH       = 0x06
TRAP_INVALID_CALL_TARGET  = 0x07
TRAP_DIV_BY_ZERO          = 0x08
TRAP_OVERFLOW             = 0x09
TRAP_CALL_DEPTH_EXCEEDED  = 0x0A
TRAP_DEBUG_BREAK          = 0x0B


# ============================================================
# hu: Method header builder — a CIL-T0 method header bináris formátum:
#     [magic=0xFE | arg_count | local_count | reserved=0]  (4 byte)
#     [code_size LE]                                       (4 byte)
#     [body...]
#     A header méret (kódban): METHOD_HEADER_SIZE = 8 byte (a defines.vh-ben).
# en: Method header builder — CIL-T0 method header binary layout:
#     [magic=0xFE | arg_count | local_count | reserved=0]  (4 bytes)
#     [code_size LE]                                       (4 bytes)
#     [body...]
#     Header size (in code): METHOD_HEADER_SIZE = 8 bytes (from defines.vh).
# ============================================================

METHOD_HEADER_MAGIC = 0xFE
METHOD_HEADER_SIZE  = 8


def make_method(body, arg_count=0, local_count=0):
    """hu: Method header + body bytes.
    en: Method header + body bytes."""
    code_size = len(body)
    header = bytes([
        METHOD_HEADER_MAGIC,
        arg_count & 0xFF,
        local_count & 0xFF,
        0x00,
        code_size & 0xFF,
        (code_size >> 8) & 0xFF,
        (code_size >> 16) & 0xFF,
        (code_size >> 24) & 0xFF,
    ])
    return header + bytes(body)
