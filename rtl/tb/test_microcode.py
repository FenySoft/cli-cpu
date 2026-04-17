# hu: CLI-CPU Microcode ROM cocotb tesztek — a cilcpu_microcode.v kombinációs
#     ROM verifikálása a C# TExecutor.cs végrehajtási logikájával szemben.
#     Minden CIL-T0 opkód mikrolépés-sorozata lefedve: egyszerű ALU, konstans,
#     stack manipuláció, branch, indirekt memória, call, ret.
#     Oracle: src/CilCpu.Sim/TExecutor.cs — a hardvernek ezt kell leutánoznia.
# en: CLI-CPU Microcode ROM cocotb tests — verification of cilcpu_microcode.v
#     combinational ROM against C# TExecutor.cs execution logic.
#     All CIL-T0 opcode micro-step sequences covered: simple ALU, constants,
#     stack manipulation, branch, indirect memory, call, ret.
#     Oracle: src/CilCpu.Sim/TExecutor.cs — hardware must replicate this exactly.

import cocotb
from cocotb.triggers import Timer

# ============================================================
# Vezérlőszó mezőpozíciók (cilcpu_defines.vh-ból)
# Control word field positions (from cilcpu_defines.vh)
# ============================================================

# Bit positions
UC_DONE         = 31
UC_TRAP         = 30
UC_TRAP_CODE_HI = 29
UC_TRAP_CODE_LO = 26
UC_STACK_POP_HI = 25
UC_STACK_POP_LO = 24
UC_STACK_PUSH   = 23
UC_PUSH_SRC_HI  = 22
UC_PUSH_SRC_LO  = 21
UC_ALU_EN       = 20
UC_ALU_OP_HI    = 19
UC_ALU_OP_LO    = 15
UC_SRAM_RD      = 14
UC_SRAM_WR      = 13
UC_ADDR_SRC_HI  = 12
UC_ADDR_SRC_LO  = 11
UC_PC_WR        = 10
UC_PC_SRC_HI    =  9
UC_PC_SRC_LO    =  8
UC_FRAME_PUSH   =  7
UC_FRAME_POP    =  6
UC_HALT         =  5
UC_COND_EN      =  4
UC_COND_TYPE_HI =  3
UC_COND_TYPE_LO =  2
UC_COND_SIGNED  =  1
UC_COND_POP     =  0  # feltételes pop (csak ha eval depth > 0)

# push_src values
PUSH_SRC_ALU  = 0
PUSH_SRC_IMM  = 1
PUSH_SRC_SRAM = 2
PUSH_SRC_TOS  = 3

# pc_src values
PC_SRC_NEXT   = 0
PC_SRC_BRANCH = 1
PC_SRC_CALL   = 2
PC_SRC_RET    = 3

# addr_src values
ADDR_SRC_ARG   = 0
ADDR_SRC_LOCAL = 1
ADDR_SRC_FRAME = 2
ADDR_SRC_IND   = 3

# cond_type values
COND_EQ = 0
COND_NE = 1
COND_LT = 2
COND_GE = 3

# ALU ops (cilcpu_defines.vh-ból)
ALU_ADD     = 0
ALU_SUB     = 1
ALU_MUL     = 2
ALU_DIV     = 3
ALU_REM     = 4
ALU_AND     = 5
ALU_OR      = 6
ALU_XOR     = 7
ALU_SHL     = 8
ALU_SHR     = 9
ALU_SHR_UN  = 10
ALU_NEG     = 11
ALU_NOT     = 12
ALU_CEQ     = 13
ALU_CGT     = 14
ALU_CGT_UN  = 15
ALU_CLT     = 16
ALU_CLT_UN  = 17

# Trap kódok
TRAP_DEBUG_BREAK = 0x0B

# ============================================================
# Opkód konstansok (cilcpu_defines.vh-ból)
# ============================================================

OP_NOP        = 0x0000
OP_LDARG_0    = 0x0002
OP_LDARG_1    = 0x0003
OP_LDARG_2    = 0x0004
OP_LDARG_3    = 0x0005
OP_LDLOC_0    = 0x0006
OP_LDLOC_1    = 0x0007
OP_LDLOC_2    = 0x0008
OP_LDLOC_3    = 0x0009
OP_STLOC_0    = 0x000A
OP_STLOC_1    = 0x000B
OP_STLOC_2    = 0x000C
OP_STLOC_3    = 0x000D
OP_LDARG_S    = 0x000E
OP_STARG_S    = 0x0010
OP_LDLOC_S    = 0x0011
OP_STLOC_S    = 0x0013
OP_LDNULL     = 0x0014
OP_LDC_I4_M1  = 0x0015
OP_LDC_I4_0   = 0x0016
OP_LDC_I4_1   = 0x0017
OP_LDC_I4_2   = 0x0018
OP_LDC_I4_3   = 0x0019
OP_LDC_I4_4   = 0x001A
OP_LDC_I4_5   = 0x001B
OP_LDC_I4_6   = 0x001C
OP_LDC_I4_7   = 0x001D
OP_LDC_I4_8   = 0x001E
OP_LDC_I4_S   = 0x001F
OP_LDC_I4     = 0x0020
OP_DUP        = 0x0025
OP_POP        = 0x0026
OP_CALL       = 0x0028
OP_RET        = 0x002A
OP_BR_S       = 0x002B
OP_BRFALSE_S  = 0x002C
OP_BRTRUE_S   = 0x002D
OP_BEQ_S      = 0x002E
OP_BGE_S      = 0x002F
OP_BGT_S      = 0x0030
OP_BLE_S      = 0x0031
OP_BLT_S      = 0x0032
OP_BNE_UN_S   = 0x0033
OP_LDIND_I4   = 0x004A
OP_STIND_I4   = 0x0054
OP_ADD        = 0x0058
OP_SUB        = 0x0059
OP_MUL        = 0x005A
OP_DIV        = 0x005B
OP_REM        = 0x005D
OP_AND        = 0x005F
OP_OR         = 0x0060
OP_XOR        = 0x0061
OP_SHL        = 0x0062
OP_SHR        = 0x0063
OP_SHR_UN     = 0x0064
OP_NEG        = 0x0065
OP_NOT        = 0x0066
OP_BREAK      = 0x00DD
OP_CEQ        = 0xFE01
OP_CGT        = 0xFE02
OP_CGT_UN     = 0xFE03
OP_CLT        = 0xFE04
OP_CLT_UN     = 0xFE05


# ============================================================
# Segédfüggvények / Helper functions
# ============================================================

def bit(ctrl, pos):
    """hu: Adott bit kiolvasása a vezérlőszóból. en: Extract a single bit."""
    return (ctrl >> pos) & 1


def field(ctrl, hi, lo):
    """hu: Bitmező kiolvasása [hi:lo]. en: Extract a bit field [hi:lo]."""
    mask = (1 << (hi - lo + 1)) - 1
    return (ctrl >> lo) & mask


async def uc(dut, opcode, step=0):
    """
    hu: Beállítja a microcode ROM bemeneteit és vár 1 ns-t.
    en: Sets microcode ROM inputs and waits 1 ns for propagation.
    """
    dut.i_opcode.value = opcode
    dut.i_step.value = step
    await Timer(1, units="ns")
    return int(dut.o_ctrl.value)


async def check_valid(dut, opcode, msg=""):
    """hu: Ellenőrzi, hogy o_valid==1. en: Assert o_valid==1."""
    dut.i_opcode.value = opcode
    dut.i_step.value = 0
    await Timer(1, units="ns")
    assert int(dut.o_valid.value) == 1, f"{msg}: expected o_valid=1 for opcode {opcode:#06x}"


async def check_invalid(dut, opcode, msg=""):
    """hu: Ellenőrzi, hogy o_valid==0. en: Assert o_valid==0."""
    dut.i_opcode.value = opcode
    dut.i_step.value = 0
    await Timer(1, units="ns")
    assert int(dut.o_valid.value) == 0, f"{msg}: expected o_valid=0 for opcode {opcode:#06x}"


async def get_nsteps(dut, opcode):
    """hu: Lekérdezi az opkód lépésszámát. en: Query opcode step count."""
    dut.i_opcode.value = opcode
    dut.i_step.value = 0
    await Timer(1, units="ns")
    return int(dut.o_nsteps.value)


# ============================================================
# 1. Érvényesség / Validity — mind a 48 opkód ismert
# ============================================================

ALL_48_OPCODES = [
    OP_NOP,
    OP_LDARG_0, OP_LDARG_1, OP_LDARG_2, OP_LDARG_3, OP_LDARG_S,
    OP_STARG_S,
    OP_LDLOC_0, OP_LDLOC_1, OP_LDLOC_2, OP_LDLOC_3, OP_LDLOC_S,
    OP_STLOC_0, OP_STLOC_1, OP_STLOC_2, OP_STLOC_3, OP_STLOC_S,
    OP_LDNULL,
    OP_LDC_I4_M1, OP_LDC_I4_0, OP_LDC_I4_1, OP_LDC_I4_2, OP_LDC_I4_3,
    OP_LDC_I4_4, OP_LDC_I4_5, OP_LDC_I4_6, OP_LDC_I4_7, OP_LDC_I4_8,
    OP_LDC_I4_S, OP_LDC_I4,
    OP_DUP, OP_POP,
    OP_CALL, OP_RET,
    OP_BR_S, OP_BRFALSE_S, OP_BRTRUE_S,
    OP_BEQ_S, OP_BGE_S, OP_BGT_S, OP_BLE_S, OP_BLT_S, OP_BNE_UN_S,
    OP_LDIND_I4, OP_STIND_I4,
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_REM,
    OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR, OP_SHR_UN,
    OP_NEG, OP_NOT,
    OP_BREAK,
    OP_CEQ, OP_CGT, OP_CGT_UN, OP_CLT, OP_CLT_UN,
]


@cocotb.test()
async def test_all_48_opcodes_valid(dut):
    """
    hu: Mind a 48 CIL-T0 opkód step=0-ra o_valid==1.
    en: All 48 CIL-T0 opcodes yield o_valid==1 at step=0.
    """
    for op in ALL_48_OPCODES:
        await check_valid(dut, op, msg=f"opcode {op:#06x}")


@cocotb.test()
async def test_invalid_opcodes(dut):
    """
    hu: Nem definiált opkódok → o_valid==0.
    en: Undefined opcodes → o_valid==0.
    """
    invalid_opcodes = [0x0001, 0x000F, 0x0012, 0x0021, 0x0034, 0x0067, 0x00FF, 0xFE00, 0xFE06]
    for op in invalid_opcodes:
        await check_invalid(dut, op, msg=f"invalid opcode {op:#06x}")


# ============================================================
# 2. Lépésszám konzisztencia / Step count consistency
# ============================================================

@cocotb.test()
async def test_done_bit_on_last_step(dut):
    """
    hu: Minden opkódra: a step==nsteps-1 lépésnél done==1,
        és step==0 esetén (ha nsteps==1) szintén done==1.
    en: For every opcode: done==1 at step==nsteps-1,
        and also at step==0 when nsteps==1.
    """
    for op in ALL_48_OPCODES:
        nsteps = await get_nsteps(dut, op)
        assert nsteps >= 1, f"opcode {op:#06x}: nsteps must be >= 1, got {nsteps}"

        last_step = nsteps - 1
        ctrl = await uc(dut, op, step=last_step)
        assert bit(ctrl, UC_DONE) == 1, \
            f"opcode {op:#06x}: done bit must be 1 at step={last_step} (nsteps={nsteps})"


@cocotb.test()
async def test_done_bit_not_premature(dut):
    """
    hu: Több-lépéses opkódoknál: done==0 a köztes lépésekben.
    en: For multi-step opcodes: done==0 at intermediate steps.
    """
    for op in ALL_48_OPCODES:
        nsteps = await get_nsteps(dut, op)

        if nsteps > 1:
            for s in range(nsteps - 1):
                ctrl = await uc(dut, op, step=s)
                assert bit(ctrl, UC_DONE) == 0, \
                    f"opcode {op:#06x}: done must be 0 at step={s} (nsteps={nsteps})"


# ============================================================
# 3. Egyszerű ALU opkódok (binary: pop2 → ALU → push)
# ============================================================

BINARY_ALU_OPS = [
    (OP_ADD,    ALU_ADD,    "Add"),
    (OP_SUB,    ALU_SUB,    "Sub"),
    (OP_MUL,    ALU_MUL,    "Mul"),
    (OP_DIV,    ALU_DIV,    "Div"),
    (OP_REM,    ALU_REM,    "Rem"),
    (OP_AND,    ALU_AND,    "And"),
    (OP_OR,     ALU_OR,     "Or"),
    (OP_XOR,    ALU_XOR,    "Xor"),
    (OP_SHL,    ALU_SHL,    "Shl"),
    (OP_SHR,    ALU_SHR,    "Shr"),
    (OP_SHR_UN, ALU_SHR_UN, "ShrUn"),
    (OP_CEQ,    ALU_CEQ,    "Ceq"),
    (OP_CGT,    ALU_CGT,    "Cgt"),
    (OP_CGT_UN, ALU_CGT_UN, "CgtUn"),
    (OP_CLT,    ALU_CLT,    "Clt"),
    (OP_CLT_UN, ALU_CLT_UN, "CltUn"),
]


@cocotb.test()
async def test_binary_alu_ops(dut):
    """
    hu: Bináris ALU opkódok: 1 lépés, pop2, ALU engedélyezve, push(ALU),
        PC+=len, done.
    en: Binary ALU opcodes: 1 step, pop2, ALU enabled, push(ALU),
        PC=next, done.
    """
    for (opcode, alu_op, name) in BINARY_ALU_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)

        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 2, f"{name}: pop2"
        assert bit(ctrl, UC_STACK_PUSH) == 1, f"{name}: push"
        assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_ALU, f"{name}: push_src=ALU"
        assert bit(ctrl, UC_ALU_EN) == 1, f"{name}: alu_en"
        assert field(ctrl, UC_ALU_OP_HI, UC_ALU_OP_LO) == alu_op, f"{name}: alu_op={alu_op}"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"
        assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, f"{name}: pc_src=next"


# ============================================================
# 4. Unáris ALU opkódok (pop1 → ALU → push)
# ============================================================

UNARY_ALU_OPS = [
    (OP_NEG, ALU_NEG, "Neg"),
    (OP_NOT, ALU_NOT, "Not"),
]


@cocotb.test()
async def test_unary_alu_ops(dut):
    """
    hu: Unáris ALU opkódok: 1 lépés, pop1, ALU, push(ALU), PC+=len.
    en: Unary ALU opcodes: 1 step, pop1, ALU, push(ALU), PC=next.
    """
    for (opcode, alu_op, name) in UNARY_ALU_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)

        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, f"{name}: pop1"
        assert bit(ctrl, UC_STACK_PUSH) == 1, f"{name}: push"
        assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_ALU, f"{name}: push_src=ALU"
        assert bit(ctrl, UC_ALU_EN) == 1, f"{name}: alu_en"
        assert field(ctrl, UC_ALU_OP_HI, UC_ALU_OP_LO) == alu_op, f"{name}: alu_op={alu_op}"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"
        assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, f"{name}: pc_src=next"


# ============================================================
# 5. Konstans load opkódok (push immediate, PC+=len)
# ============================================================

CONST_LOAD_OPS = [
    OP_LDNULL, OP_LDC_I4_M1, OP_LDC_I4_0, OP_LDC_I4_1, OP_LDC_I4_2,
    OP_LDC_I4_3, OP_LDC_I4_4, OP_LDC_I4_5, OP_LDC_I4_6, OP_LDC_I4_7,
    OP_LDC_I4_8, OP_LDC_I4_S, OP_LDC_I4,
]


@cocotb.test()
async def test_const_load_ops(dut):
    """
    hu: Konstans load: 1 lépés, push(immediate), PC+=len, done.
    en: Constant load: 1 step, push(immediate), PC=next, done.
    """
    for opcode in CONST_LOAD_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"opcode {opcode:#06x}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)

        assert bit(ctrl, UC_DONE) == 1, f"opcode {opcode:#06x}: done"
        assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 0, f"opcode {opcode:#06x}: no pop"
        assert bit(ctrl, UC_STACK_PUSH) == 1, f"opcode {opcode:#06x}: push"
        assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_IMM, \
            f"opcode {opcode:#06x}: push_src=IMM"
        assert bit(ctrl, UC_ALU_EN) == 0, f"opcode {opcode:#06x}: alu_en=0"
        assert bit(ctrl, UC_PC_WR) == 1, f"opcode {opcode:#06x}: pc_wr"
        assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, \
            f"opcode {opcode:#06x}: pc_src=next"


# ============================================================
# 6. Nop, Dup, Pop
# ============================================================

@cocotb.test()
async def test_nop(dut):
    """hu: Nop: 1 lépés, semmi, PC+=len, done. en: Nop: 1 step, nothing, PC=next, done."""
    nsteps = await get_nsteps(dut, OP_NOP)
    assert nsteps == 1, f"Nop: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_NOP, step=0)
    assert bit(ctrl, UC_DONE) == 1, "Nop: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 0, "Nop: no pop"
    assert bit(ctrl, UC_STACK_PUSH) == 0, "Nop: no push"
    assert bit(ctrl, UC_ALU_EN) == 0, "Nop: no ALU"
    assert bit(ctrl, UC_PC_WR) == 1, "Nop: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, "Nop: pc_src=next"


@cocotb.test()
async def test_dup(dut):
    """hu: Dup: 1 lépés, push(TOS), PC+=len, done. en: Dup: 1 step, push(TOS), done."""
    nsteps = await get_nsteps(dut, OP_DUP)
    assert nsteps == 1, f"Dup: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_DUP, step=0)
    assert bit(ctrl, UC_DONE) == 1, "Dup: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 0, "Dup: no pop"
    assert bit(ctrl, UC_STACK_PUSH) == 1, "Dup: push"
    assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_TOS, "Dup: push_src=TOS"
    assert bit(ctrl, UC_PC_WR) == 1, "Dup: pc_wr"


@cocotb.test()
async def test_pop(dut):
    """hu: Pop: 1 lépés, pop1, PC+=len, done. en: Pop: 1 step, pop1, PC=next, done."""
    nsteps = await get_nsteps(dut, OP_POP)
    assert nsteps == 1, f"Pop: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_POP, step=0)
    assert bit(ctrl, UC_DONE) == 1, "Pop: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "Pop: pop1"
    assert bit(ctrl, UC_STACK_PUSH) == 0, "Pop: no push"
    assert bit(ctrl, UC_PC_WR) == 1, "Pop: pc_wr"


# ============================================================
# 7. Ldarg / Ldloc (SRAM read → push)
# ============================================================

LDARG_OPS = [
    (OP_LDARG_0, "Ldarg0"), (OP_LDARG_1, "Ldarg1"),
    (OP_LDARG_2, "Ldarg2"), (OP_LDARG_3, "Ldarg3"),
    (OP_LDARG_S, "LdargS"),
]

LDLOC_OPS = [
    (OP_LDLOC_0, "Ldloc0"), (OP_LDLOC_1, "Ldloc1"),
    (OP_LDLOC_2, "Ldloc2"), (OP_LDLOC_3, "Ldloc3"),
    (OP_LDLOC_S, "LdlocS"),
]


@cocotb.test()
async def test_ldarg_ops(dut):
    """
    hu: Ldarg opkódok: 1 lépés, SRAM read (addr_src=arg), push(SRAM), PC+=len.
    en: Ldarg opcodes: 1 step, SRAM read (addr_src=arg), push(SRAM), PC=next.
    """
    for (opcode, name) in LDARG_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)
        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert bit(ctrl, UC_SRAM_RD) == 1, f"{name}: sram_rd"
        assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_ARG, \
            f"{name}: addr_src=arg"
        assert bit(ctrl, UC_STACK_PUSH) == 1, f"{name}: push"
        assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_SRAM, \
            f"{name}: push_src=SRAM"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"


@cocotb.test()
async def test_ldloc_ops(dut):
    """
    hu: Ldloc opkódok: 1 lépés, SRAM read (addr_src=local), push(SRAM), PC+=len.
    en: Ldloc opcodes: 1 step, SRAM read (addr_src=local), push(SRAM), PC=next.
    """
    for (opcode, name) in LDLOC_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)
        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert bit(ctrl, UC_SRAM_RD) == 1, f"{name}: sram_rd"
        assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_LOCAL, \
            f"{name}: addr_src=local"
        assert bit(ctrl, UC_STACK_PUSH) == 1, f"{name}: push"
        assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_SRAM, \
            f"{name}: push_src=SRAM"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"


# ============================================================
# 8. Starg / Stloc (pop → SRAM write)
# ============================================================

STLOC_OPS = [
    (OP_STLOC_0, "Stloc0"), (OP_STLOC_1, "Stloc1"),
    (OP_STLOC_2, "Stloc2"), (OP_STLOC_3, "Stloc3"),
    (OP_STLOC_S, "StlocS"),
]


@cocotb.test()
async def test_starg_s(dut):
    """
    hu: StargS: 1 lépés, pop1, SRAM write (addr_src=arg), PC+=len.
    en: StargS: 1 step, pop1, SRAM write (addr_src=arg), PC=next.
    """
    nsteps = await get_nsteps(dut, OP_STARG_S)
    assert nsteps == 1, f"StargS: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_STARG_S, step=0)
    assert bit(ctrl, UC_DONE) == 1, "StargS: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "StargS: pop1"
    assert bit(ctrl, UC_SRAM_WR) == 1, "StargS: sram_wr"
    assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_ARG, "StargS: addr_src=arg"
    assert bit(ctrl, UC_PC_WR) == 1, "StargS: pc_wr"


@cocotb.test()
async def test_stloc_ops(dut):
    """
    hu: Stloc opkódok: 1 lépés, pop1, SRAM write (addr_src=local), PC+=len.
    en: Stloc opcodes: 1 step, pop1, SRAM write (addr_src=local), PC=next.
    """
    for (opcode, name) in STLOC_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)
        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, f"{name}: pop1"
        assert bit(ctrl, UC_SRAM_WR) == 1, f"{name}: sram_wr"
        assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_LOCAL, \
            f"{name}: addr_src=local"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"


# ============================================================
# 9. Branch — feltétel nélküli (br.s)
# ============================================================

@cocotb.test()
async def test_br_s(dut):
    """
    hu: br.s: 1 lépés, PC=branch target, done.
    en: br.s: 1 step, PC=branch target, done.
    """
    nsteps = await get_nsteps(dut, OP_BR_S)
    assert nsteps == 1, f"br.s: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_BR_S, step=0)
    assert bit(ctrl, UC_DONE) == 1, "br.s: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 0, "br.s: no pop"
    assert bit(ctrl, UC_PC_WR) == 1, "br.s: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_BRANCH, "br.s: pc_src=branch"


# ============================================================
# 10. Branch — egyértékű feltételes (brfalse.s, brtrue.s)
# ============================================================

@cocotb.test()
async def test_brfalse_s(dut):
    """
    hu: brfalse.s: 1 lépés, pop1, cond_en, cond_type=EQ (TOS==0 → branch), PC.
    en: brfalse.s: 1 step, pop1, cond_en, cond_type=EQ (TOS==0 → branch), PC.
    """
    nsteps = await get_nsteps(dut, OP_BRFALSE_S)
    assert nsteps == 1, f"brfalse.s: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_BRFALSE_S, step=0)
    assert bit(ctrl, UC_DONE) == 1, "brfalse.s: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "brfalse.s: pop1"
    assert bit(ctrl, UC_PC_WR) == 1, "brfalse.s: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_BRANCH, "brfalse.s: pc_src=branch"
    assert bit(ctrl, UC_COND_EN) == 1, "brfalse.s: cond_en"
    assert field(ctrl, UC_COND_TYPE_HI, UC_COND_TYPE_LO) == COND_EQ, "brfalse.s: cond_type=EQ"


@cocotb.test()
async def test_brtrue_s(dut):
    """
    hu: brtrue.s: 1 lépés, pop1, cond_en, cond_type=NE (TOS!=0 → branch), PC.
    en: brtrue.s: 1 step, pop1, cond_en, cond_type=NE (TOS!=0 → branch), PC.
    """
    nsteps = await get_nsteps(dut, OP_BRTRUE_S)
    assert nsteps == 1, f"brtrue.s: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_BRTRUE_S, step=0)
    assert bit(ctrl, UC_DONE) == 1, "brtrue.s: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "brtrue.s: pop1"
    assert bit(ctrl, UC_PC_WR) == 1, "brtrue.s: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_BRANCH, "brtrue.s: pc_src=branch"
    assert bit(ctrl, UC_COND_EN) == 1, "brtrue.s: cond_en"
    assert field(ctrl, UC_COND_TYPE_HI, UC_COND_TYPE_LO) == COND_NE, "brtrue.s: cond_type=NE"


# ============================================================
# 11. Branch — kétértékű feltételes (beq.s .. bne.un.s)
#     pop2 + ALU összehasonlítás + feltételes branch
# ============================================================

CMP_BRANCH_OPS = [
    (OP_BEQ_S,    ALU_CEQ,    COND_NE, 0, "beq.s"),    # branch if CEQ result != 0 (i.e. equal)
    (OP_BGE_S,    ALU_CLT,    COND_EQ, 1, "bge.s"),     # branch if CLT result == 0 (i.e. not less)
    (OP_BGT_S,    ALU_CGT,    COND_NE, 1, "bgt.s"),     # branch if CGT result != 0 (i.e. greater)
    (OP_BLE_S,    ALU_CGT,    COND_EQ, 1, "ble.s"),     # branch if CGT result == 0 (i.e. not greater)
    (OP_BLT_S,    ALU_CLT,    COND_NE, 1, "blt.s"),     # branch if CLT result != 0 (i.e. less)
    (OP_BNE_UN_S, ALU_CEQ,    COND_EQ, 0, "bne.un.s"),  # branch if CEQ result == 0 (i.e. not equal)
]


@cocotb.test()
async def test_cmp_branch_ops(dut):
    """
    hu: Összehasonlító branch opkódok: 1 lépés, pop2, ALU összehasonlítás,
        cond_en, feltételes PC frissítés.
    en: Comparison branch opcodes: 1 step, pop2, ALU compare,
        cond_en, conditional PC update.
    """
    for (opcode, alu_op, cond_type, cond_signed, name) in CMP_BRANCH_OPS:
        nsteps = await get_nsteps(dut, opcode)
        assert nsteps == 1, f"{name}: expected 1 step, got {nsteps}"

        ctrl = await uc(dut, opcode, step=0)
        assert bit(ctrl, UC_DONE) == 1, f"{name}: done"
        assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 2, f"{name}: pop2"
        assert bit(ctrl, UC_ALU_EN) == 1, f"{name}: alu_en"
        assert field(ctrl, UC_ALU_OP_HI, UC_ALU_OP_LO) == alu_op, f"{name}: alu_op"
        assert bit(ctrl, UC_PC_WR) == 1, f"{name}: pc_wr"
        assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_BRANCH, f"{name}: pc_src=branch"
        assert bit(ctrl, UC_COND_EN) == 1, f"{name}: cond_en"
        assert field(ctrl, UC_COND_TYPE_HI, UC_COND_TYPE_LO) == cond_type, f"{name}: cond_type"
        assert bit(ctrl, UC_COND_SIGNED) == cond_signed, f"{name}: cond_signed"


# ============================================================
# 12. Indirect memória — ldind.i4
# ============================================================

@cocotb.test()
async def test_ldind_i4(dut):
    """
    hu: ldind.i4: 1 lépés, pop1(addr), SRAM read (addr_src=indirect),
        push(SRAM), PC+=len, done.
    en: ldind.i4: 1 step, pop1(addr), SRAM read (addr_src=indirect),
        push(SRAM), PC=next, done.
    """
    nsteps = await get_nsteps(dut, OP_LDIND_I4)
    assert nsteps == 1, f"ldind.i4: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_LDIND_I4, step=0)
    assert bit(ctrl, UC_DONE) == 1, "ldind.i4: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "ldind.i4: pop1"
    assert bit(ctrl, UC_SRAM_RD) == 1, "ldind.i4: sram_rd"
    assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_IND, "ldind.i4: addr_src=indirect"
    assert bit(ctrl, UC_STACK_PUSH) == 1, "ldind.i4: push"
    assert field(ctrl, UC_PUSH_SRC_HI, UC_PUSH_SRC_LO) == PUSH_SRC_SRAM, "ldind.i4: push_src=SRAM"
    assert bit(ctrl, UC_PC_WR) == 1, "ldind.i4: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, "ldind.i4: pc_src=next"


# ============================================================
# 13. Indirect memória — stind.i4
# ============================================================

@cocotb.test()
async def test_stind_i4(dut):
    """
    hu: stind.i4: 1 lépés, pop2 (TOS=value, TOS-1=addr), SRAM write
        (addr_src=indirect), PC+=len, done.
    en: stind.i4: 1 step, pop2 (TOS=value, TOS-1=addr), SRAM write
        (addr_src=indirect), PC=next, done.
    """
    nsteps = await get_nsteps(dut, OP_STIND_I4)
    assert nsteps == 1, f"stind.i4: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_STIND_I4, step=0)
    assert bit(ctrl, UC_DONE) == 1, "stind.i4: done"
    assert field(ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 2, "stind.i4: pop2"
    assert bit(ctrl, UC_SRAM_WR) == 1, "stind.i4: sram_wr"
    assert field(ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_IND, "stind.i4: addr_src=indirect"
    assert bit(ctrl, UC_PC_WR) == 1, "stind.i4: pc_wr"
    assert field(ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_NEXT, "stind.i4: pc_src=next"


# ============================================================
# 14. Break — debug trap
# ============================================================

@cocotb.test()
async def test_break(dut):
    """
    hu: break: 1 lépés, trap(DebugBreak), done.
    en: break: 1 step, trap(DebugBreak), done.
    """
    nsteps = await get_nsteps(dut, OP_BREAK)
    assert nsteps == 1, f"break: expected 1 step, got {nsteps}"

    ctrl = await uc(dut, OP_BREAK, step=0)
    assert bit(ctrl, UC_DONE) == 1, "break: done"
    assert bit(ctrl, UC_TRAP) == 1, "break: trap"
    assert field(ctrl, UC_TRAP_CODE_HI, UC_TRAP_CODE_LO) == TRAP_DEBUG_BREAK, \
        "break: trap_code=DebugBreak"


# ============================================================
# 15. Call — multi-step
# ============================================================

@cocotb.test()
async def test_call(dut):
    """
    hu: call: több lépéses sorozat. Az utolsó lépésnél frame_push, PC=call_target.
    en: call: multi-step sequence. Final step: frame_push, PC=call_target.
    """
    nsteps = await get_nsteps(dut, OP_CALL)
    assert nsteps >= 2, f"call: expected >=2 steps, got {nsteps}"

    # hu: Step 0: SRAM read (header validáció).
    # en: Step 0: SRAM read (header validation).
    step0_ctrl = await uc(dut, OP_CALL, step=0)
    assert bit(step0_ctrl, UC_SRAM_RD) == 1, "call step0: sram_rd"
    assert field(step0_ctrl, UC_ADDR_SRC_HI, UC_ADDR_SRC_LO) == ADDR_SRC_FRAME, \
        "call step0: addr_src=frame"
    assert bit(step0_ctrl, UC_DONE) == 0, "call step0: not done"

    # hu: Az utolsó lépésben: frame_push=1, pc_wr=1, pc_src=CALL.
    # en: Last step must have: frame_push=1, pc_wr=1, pc_src=CALL.
    last_ctrl = await uc(dut, OP_CALL, step=nsteps - 1)
    assert bit(last_ctrl, UC_DONE) == 1, "call last step: done"
    assert bit(last_ctrl, UC_FRAME_PUSH) == 1, "call last step: frame_push"
    assert bit(last_ctrl, UC_PC_WR) == 1, "call last step: pc_wr"
    assert field(last_ctrl, UC_PC_SRC_HI, UC_PC_SRC_LO) == PC_SRC_CALL, \
        "call last step: pc_src=call"


# ============================================================
# 16. Ret — multi-step
# ============================================================

@cocotb.test()
async def test_ret(dut):
    """
    hu: ret: több lépéses sorozat. Az utolsó lépésnél frame_pop vagy halt.
    en: ret: multi-step sequence. Final step: frame_pop or halt.
    """
    nsteps = await get_nsteps(dut, OP_RET)
    assert nsteps >= 2, f"ret: expected >=2 steps, got {nsteps}"

    # hu: Step 0: feltételes pop (cond_pop=1, pop1).
    # en: Step 0: conditional pop (cond_pop=1, pop1).
    step0_ctrl = await uc(dut, OP_RET, step=0)
    assert field(step0_ctrl, UC_STACK_POP_HI, UC_STACK_POP_LO) == 1, "ret step0: pop1"
    assert bit(step0_ctrl, UC_COND_POP) == 1, "ret step0: cond_pop=1 (only pop if eval depth >= 1)"
    assert bit(step0_ctrl, UC_DONE) == 0, "ret step0: not done"

    # hu: Az utolsó lépésben: frame_pop=1, pc_src=RET (vagy halt).
    # en: Last step: frame_pop=1, pc_src=RET (or halt).
    last_ctrl = await uc(dut, OP_RET, step=nsteps - 1)
    assert bit(last_ctrl, UC_DONE) == 1, "ret last step: done"

    # hu: frame_pop VAGY halt kell legyen az utolsó lépésben.
    # en: Either frame_pop or halt must be set in the last step.
    has_frame_pop = bit(last_ctrl, UC_FRAME_POP) == 1
    has_halt = bit(last_ctrl, UC_HALT) == 1
    assert has_frame_pop or has_halt, "ret last step: frame_pop or halt"


# ============================================================
# 17. Stílusellenőrzés — sram_rd és sram_wr soha nem egyidejű
# ============================================================

@cocotb.test()
async def test_no_simultaneous_sram_rd_wr(dut):
    """
    hu: Egyetlen (opkód, lépés) pár sem állíthat egyszerre sram_rd=1 és sram_wr=1.
    en: No (opcode, step) pair may assert both sram_rd=1 and sram_wr=1.
    """
    for op in ALL_48_OPCODES:
        nsteps = await get_nsteps(dut, op)

        for s in range(nsteps):
            ctrl = await uc(dut, op, step=s)
            rd = bit(ctrl, UC_SRAM_RD)
            wr = bit(ctrl, UC_SRAM_WR)
            assert not (rd == 1 and wr == 1), \
                f"opcode {op:#06x} step={s}: sram_rd and sram_wr both asserted"


# ============================================================
# 18. Órajelciklus (μstep) verifikáció — minden opkódra explicit
#     Clock cycle (μstep) verification — explicit for every opcode
# ============================================================

# hu: Elvárás: minden opkód μstep értéke pontosan megegyezik az ISA doc-ban
#     dokumentált értékkel. Ez a táblázat a cilcpu_microcode.v fejléc kommentjéből
#     és az ISA-CIL-T0 doc-ból származik.
# en: Expected: every opcode's μstep count matches the ISA doc exactly.
#     This table comes from the cilcpu_microcode.v header comment and the ISA doc.

EXPECTED_NSTEPS = {
    # Konstansok — 1 μstep
    OP_LDNULL: 1, OP_LDC_I4_M1: 1, OP_LDC_I4_0: 1, OP_LDC_I4_1: 1,
    OP_LDC_I4_2: 1, OP_LDC_I4_3: 1, OP_LDC_I4_4: 1, OP_LDC_I4_5: 1,
    OP_LDC_I4_6: 1, OP_LDC_I4_7: 1, OP_LDC_I4_8: 1, OP_LDC_I4_S: 1,
    OP_LDC_I4: 1,
    # Lokálisok — 1 μstep
    OP_LDLOC_0: 1, OP_LDLOC_1: 1, OP_LDLOC_2: 1, OP_LDLOC_3: 1, OP_LDLOC_S: 1,
    OP_STLOC_0: 1, OP_STLOC_1: 1, OP_STLOC_2: 1, OP_STLOC_3: 1, OP_STLOC_S: 1,
    # Argumentumok — 1 μstep
    OP_LDARG_0: 1, OP_LDARG_1: 1, OP_LDARG_2: 1, OP_LDARG_3: 1, OP_LDARG_S: 1,
    OP_STARG_S: 1,
    # Stack manipuláció — 1 μstep
    OP_NOP: 1, OP_DUP: 1, OP_POP: 1,
    # ALU bináris — 1 μstep (ALU latencia a sequencer-ben kezelt)
    OP_ADD: 1, OP_SUB: 1, OP_MUL: 1, OP_DIV: 1, OP_REM: 1,
    OP_AND: 1, OP_OR: 1, OP_XOR: 1, OP_SHL: 1, OP_SHR: 1, OP_SHR_UN: 1,
    # ALU unáris — 1 μstep
    OP_NEG: 1, OP_NOT: 1,
    # Összehasonlítás (FE prefix) — 1 μstep
    OP_CEQ: 1, OP_CGT: 1, OP_CGT_UN: 1, OP_CLT: 1, OP_CLT_UN: 1,
    # Branch — 1 μstep (pipeline flush a sequencer-ben)
    OP_BR_S: 1, OP_BRFALSE_S: 1, OP_BRTRUE_S: 1,
    OP_BEQ_S: 1, OP_BGE_S: 1, OP_BGT_S: 1, OP_BLE_S: 1, OP_BLT_S: 1, OP_BNE_UN_S: 1,
    # Indirekt memória — 1 μstep
    OP_LDIND_I4: 1, OP_STIND_I4: 1,
    # Call / Ret — 2 μstep
    OP_CALL: 2, OP_RET: 2,
    # Debug — 1 μstep
    OP_BREAK: 1,
}


@cocotb.test()
async def test_nsteps_matches_isa_doc(dut):
    """
    hu: Minden opkód μstep értéke pontosan megegyezik az ISA doc-ban
        és a cilcpu_microcode.v fejlécében dokumentált értékkel.
    en: Every opcode's μstep count matches the ISA doc and the
        cilcpu_microcode.v header comment exactly.
    """
    for opcode, expected in EXPECTED_NSTEPS.items():
        actual = await get_nsteps(dut, opcode)
        assert actual == expected, \
            f"opcode {opcode:#06x}: expected nsteps={expected}, got {actual}"


# ============================================================
# EXPECTED RED (TDD phase 1) / VÁRT PIROS (TDD 1. fázis)
#
# hu: Ezek a tesztek PIROSAK (buknak), amíg a cilcpu_microcode.v nincs
#     elkészítve. Ez a TDD első fázisa.
# en: These tests are RED (failing) until cilcpu_microcode.v is implemented.
#     This is TDD phase 1.
# ============================================================
