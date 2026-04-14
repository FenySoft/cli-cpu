# hu: CLI-CPU ALU cocotb tesztek — a cilcpu_alu.v kombinációs ALU
#     verifikálása a C# TExecutor.cs aritmetikai/logikai/összehasonlító
#     ágaival szemben. Minden CIL-T0 ALU művelet lefedve.
# en: CLI-CPU ALU cocotb tests — verification of cilcpu_alu.v
#     combinational ALU against C# TExecutor.cs arithmetic/logical/
#     comparison branches. All CIL-T0 ALU operations covered.

import cocotb
from cocotb.triggers import Timer

# ALU op codes (cilcpu_defines.vh-ból)
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

async def alu_op(dut, a, b, op):
    """Set ALU inputs and wait for combinational propagation."""
    dut.i_op_a.value = to_u32(a)
    dut.i_op_b.value = to_u32(b)
    dut.i_alu_op.value = op
    await Timer(1, units="ns")
    return {
        "result": int(dut.o_result.value),
        "div_zero": int(dut.o_trap_div_zero.value),
        "overflow": int(dut.o_trap_overflow.value),
    }

async def check(dut, a, b, op, expected, msg=""):
    """Assert ALU result matches expected value."""
    r = await alu_op(dut, a, b, op)
    actual = r["result"]
    exp_u32 = to_u32(expected)
    assert actual == exp_u32, f"{msg}: expected {exp_u32:#010x}, got {actual:#010x} (a={to_u32(a):#010x}, b={to_u32(b):#010x}, op={op})"

async def check_trap(dut, a, b, op, trap_name, msg=""):
    """Assert ALU raises the specified trap flag."""
    r = await alu_op(dut, a, b, op)
    if trap_name == "div_zero":
        assert r["div_zero"] == 1, f"{msg}: expected div_zero trap"
    elif trap_name == "overflow":
        assert r["overflow"] == 1, f"{msg}: expected overflow trap"

# ============================================================
# ADD tesztek
# ============================================================

@cocotb.test()
async def test_add_basic(dut):
    await check(dut, 2, 3, ALU_ADD, 5, "2+3")

@cocotb.test()
async def test_add_zero(dut):
    await check(dut, 0, 0, ALU_ADD, 0, "0+0")

@cocotb.test()
async def test_add_negative(dut):
    await check(dut, -1, -1, ALU_ADD, -2, "-1+-1")

@cocotb.test()
async def test_add_wrap(dut):
    await check(dut, INT_MAX, 1, ALU_ADD, INT_MIN, "INT_MAX+1 wraps to INT_MIN")

# ============================================================
# SUB tesztek
# ============================================================

@cocotb.test()
async def test_sub_basic(dut):
    await check(dut, 5, 3, ALU_SUB, 2, "5-3")

@cocotb.test()
async def test_sub_negative_result(dut):
    await check(dut, 3, 5, ALU_SUB, -2, "3-5")

@cocotb.test()
async def test_sub_wrap(dut):
    await check(dut, INT_MIN, 1, ALU_SUB, INT_MAX, "INT_MIN-1 wraps")

# ============================================================
# MUL tesztek
# ============================================================

@cocotb.test()
async def test_mul_basic(dut):
    await check(dut, 6, 7, ALU_MUL, 42, "6*7")

@cocotb.test()
async def test_mul_negative(dut):
    await check(dut, -3, 4, ALU_MUL, -12, "-3*4")

@cocotb.test()
async def test_mul_zero(dut):
    await check(dut, 12345, 0, ALU_MUL, 0, "x*0")

@cocotb.test()
async def test_mul_wrap(dut):
    # 0x10000 * 0x10000 = 0x100000000 → lower 32 bits = 0
    await check(dut, 0x10000, 0x10000, ALU_MUL, 0, "overflow wraps")

# ============================================================
# DIV tesztek
# ============================================================

@cocotb.test()
async def test_div_basic(dut):
    await check(dut, 10, 3, ALU_DIV, 3, "10/3")

@cocotb.test()
async def test_div_negative(dut):
    await check(dut, -10, 3, ALU_DIV, -3, "-10/3")

@cocotb.test()
async def test_div_by_zero(dut):
    await check_trap(dut, 10, 0, ALU_DIV, "div_zero", "div by zero")

@cocotb.test()
async def test_div_int_min_by_minus_one(dut):
    await check_trap(dut, INT_MIN, -1, ALU_DIV, "overflow", "INT_MIN/-1")

@cocotb.test()
async def test_div_exact(dut):
    await check(dut, 42, 6, ALU_DIV, 7, "42/6")

# ============================================================
# REM tesztek
# ============================================================

@cocotb.test()
async def test_rem_basic(dut):
    await check(dut, 10, 3, ALU_REM, 1, "10%3")

@cocotb.test()
async def test_rem_negative(dut):
    await check(dut, -10, 3, ALU_REM, -1, "-10%3")

@cocotb.test()
async def test_rem_by_zero(dut):
    await check_trap(dut, 10, 0, ALU_REM, "div_zero", "rem by zero")

@cocotb.test()
async def test_rem_int_min_by_minus_one(dut):
    # INT_MIN % -1 = 0 (NOT overflow, per ECMA-335)
    await check(dut, INT_MIN, -1, ALU_REM, 0, "INT_MIN%-1=0")

# ============================================================
# Bitwise logika tesztek
# ============================================================

@cocotb.test()
async def test_and(dut):
    await check(dut, 0xFF00FF00, 0x0F0F0F0F, ALU_AND, 0x0F000F00, "AND")

@cocotb.test()
async def test_or(dut):
    await check(dut, 0xFF00FF00, 0x0F0F0F0F, ALU_OR, 0xFF0FFF0F, "OR")

@cocotb.test()
async def test_xor(dut):
    await check(dut, 0xFF00FF00, 0x0F0F0F0F, ALU_XOR, 0xF00FF00F, "XOR")

# ============================================================
# Shift tesztek
# ============================================================

@cocotb.test()
async def test_shl(dut):
    await check(dut, 1, 10, ALU_SHL, 1024, "1<<10")

@cocotb.test()
async def test_shl_mask(dut):
    # shift amount masked to 0..31
    await check(dut, 1, 32, ALU_SHL, 1, "1<<32 = 1<<0 (masked)")

@cocotb.test()
async def test_shr_signed(dut):
    await check(dut, -8, 2, ALU_SHR, -2, "-8>>2 arithmetic")

@cocotb.test()
async def test_shr_un(dut):
    await check(dut, 0x80000000, 1, ALU_SHR_UN, 0x40000000, "unsigned >>1")

# ============================================================
# Unáris tesztek
# ============================================================

@cocotb.test()
async def test_neg(dut):
    await check(dut, 5, 0, ALU_NEG, -5, "neg 5")

@cocotb.test()
async def test_neg_zero(dut):
    await check(dut, 0, 0, ALU_NEG, 0, "neg 0")

@cocotb.test()
async def test_neg_int_min(dut):
    # -INT_MIN wraps to INT_MIN (two's complement)
    await check(dut, INT_MIN, 0, ALU_NEG, INT_MIN, "neg INT_MIN wraps")

@cocotb.test()
async def test_not(dut):
    await check(dut, 0, 0, ALU_NOT, U32_MAX, "not 0 = all ones")

@cocotb.test()
async def test_not_pattern(dut):
    await check(dut, 0xAAAAAAAA, 0, ALU_NOT, 0x55555555, "not pattern")

# ============================================================
# Összehasonlítás tesztek
# ============================================================

@cocotb.test()
async def test_ceq_equal(dut):
    await check(dut, 42, 42, ALU_CEQ, 1, "42==42")

@cocotb.test()
async def test_ceq_not_equal(dut):
    await check(dut, 42, 43, ALU_CEQ, 0, "42!=43")

@cocotb.test()
async def test_cgt_signed(dut):
    await check(dut, 5, 3, ALU_CGT, 1, "5>3 signed")
    await check(dut, 3, 5, ALU_CGT, 0, "3>5 signed")
    await check(dut, -1, 1, ALU_CGT, 0, "-1>1 signed = false")
    await check(dut, 1, -1, ALU_CGT, 1, "1>-1 signed = true")

@cocotb.test()
async def test_cgt_un(dut):
    # unsigned: 0xFFFFFFFF > 1
    await check(dut, U32_MAX, 1, ALU_CGT_UN, 1, "UINT_MAX>1 unsigned")
    await check(dut, 1, U32_MAX, ALU_CGT_UN, 0, "1>UINT_MAX unsigned = false")

@cocotb.test()
async def test_clt_signed(dut):
    await check(dut, 3, 5, ALU_CLT, 1, "3<5 signed")
    await check(dut, 5, 3, ALU_CLT, 0, "5<3 signed")
    await check(dut, -1, 1, ALU_CLT, 1, "-1<1 signed = true")

@cocotb.test()
async def test_clt_un(dut):
    await check(dut, 1, U32_MAX, ALU_CLT_UN, 1, "1<UINT_MAX unsigned")
    await check(dut, U32_MAX, 1, ALU_CLT_UN, 0, "UINT_MAX<1 unsigned = false")

@cocotb.test()
async def test_ceq_zero(dut):
    await check(dut, 0, 0, ALU_CEQ, 1, "0==0")

@cocotb.test()
async def test_cgt_equal(dut):
    await check(dut, 5, 5, ALU_CGT, 0, "5>5 = false")

@cocotb.test()
async def test_clt_equal(dut):
    await check(dut, 5, 5, ALU_CLT, 0, "5<5 = false")
