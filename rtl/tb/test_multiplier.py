# hu: CLI-CPU F2.6-prep — cilcpu_multiplier.v szekvenciális szorzó cocotb
#     tesztjei. A kombinációs ALU-szorzás (cilcpu_alu.v ALU_MUL `i_op_a *
#     i_op_b`) egy teljes 32×32 párhuzamos szorzót inferált — a datapath
#     legnagyobb egyetlen ALU-eleme. A gyökér-fix egy többciklusú
#     (shift-add, korai kilépés) szorzó, ami egyben az ISA spec-et is
#     követi (`ISA-CIL-T0-hu.md`: „mul — iteratív shift-add, 3–7 ciklus").
#     Ez a teszt a viselkedési szerződést rögzíti: a szorzat az alsó 32 bit
#     (wrapping, előjel-agnosztikus kétkomplemens) — azonos a korábbi
#     test_alu MUL esetekkel, a divider-precedenst (test_divider.py) követve.
# en: CLI-CPU F2.6-prep — cocotb tests for the cilcpu_multiplier.v
#     sequential multiplier. The combinational ALU multiply (cilcpu_alu.v
#     ALU_MUL `i_op_a * i_op_b`) inferred a full 32×32 parallel multiplier —
#     the single largest ALU element in the datapath. The root fix is a
#     multi-cycle (shift-add, early-exit) multiplier, which also aligns with
#     the ISA spec ("mul — iterative shift-add, 3–7 cycles"). This test
#     pins the behavioral contract: the product is the lower 32 bits
#     (wrapping, sign-agnostic two's complement) — identical to the former
#     test_alu MUL cases, mirroring the divider precedent (test_divider.py).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

INT_MIN = 0x80000000   # -2147483648
INT_MAX = 0x7FFFFFFF   #  2147483647


def to_u32(val):
    """hu: előjeles int → 32-bit unsigned / en: signed int → u32."""
    return val & 0xFFFFFFFF


def to_s32(val):
    """hu: 32-bit unsigned → előjeles int / en: u32 → signed int."""
    val &= 0xFFFFFFFF
    return val - 0x100000000 if val >= 0x80000000 else val


async def reset_dut(dut):
    """hu: Multiplier reset + clock indítás / en: reset multiplier + start clock."""
    cocotb.start_soon(Clock(dut.i_clk, 10, units="ns").start())
    dut.i_start.value = 0
    dut.i_op_a.value = 0
    dut.i_op_b.value = 0
    dut.i_rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)


async def do_mul(dut, a, b, timeout=80):
    """hu: start-pulzus, várakozás o_done-ra, szorzat visszaadása.
    en: pulse start, wait for o_done, return the product (u32)."""
    dut.i_op_a.value = to_u32(a)
    dut.i_op_b.value = to_u32(b)
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    for _ in range(timeout):
        await RisingEdge(dut.i_clk)
        if int(dut.o_done.value) == 1:
            return int(dut.o_product.value)
    raise AssertionError(f"multiplier timeout ({timeout} clk): {a}*{b}")


async def check_mul(dut, a, b, exp, msg=""):
    """hu: szorzat ellenőrzés (alsó 32 bit, wrapping).
    en: assert product (lower 32 bits, wrapping)."""
    p = await do_mul(dut, a, b)
    exp_u = to_u32(exp)
    assert p == exp_u, \
        f"{msg}: szorzat {p:#010x} != {exp_u:#010x} (a={to_u32(a):#010x}, b={to_u32(b):#010x})"


# ============================================================
# Alap szorzás / Basic multiply (a régi test_alu MUL esetei)
# ============================================================

@cocotb.test()
async def test_mul_basic(dut):
    await reset_dut(dut)
    await check_mul(dut, 6, 7, 42, "6*7")


@cocotb.test()
async def test_mul_negative(dut):
    # hu: -3*4 = -12 = 0xFFFFFFF4 — alsó 32 bit előjel-agnosztikus
    await reset_dut(dut)
    await check_mul(dut, -3, 4, -12, "-3*4")


@cocotb.test()
async def test_mul_zero(dut):
    await reset_dut(dut)
    await check_mul(dut, 12345, 0, 0, "x*0")


@cocotb.test()
async def test_mul_zero_lhs(dut):
    await reset_dut(dut)
    await check_mul(dut, 0, 12345, 0, "0*x")


@cocotb.test()
async def test_mul_wrap(dut):
    # hu: 0x10000 * 0x10000 = 0x100000000 → alsó 32 bit = 0
    await reset_dut(dut)
    await check_mul(dut, 0x10000, 0x10000, 0, "overflow wraps")


# ============================================================
# Előjel-kombinációk / Sign combinations (lower-32 wrapping)
# ============================================================

@cocotb.test()
async def test_mul_both_negative(dut):
    # hu: -3 * -4 = 12
    await reset_dut(dut)
    await check_mul(dut, -3, -4, 12, "-3*-4")


@cocotb.test()
async def test_mul_neg_rhs(dut):
    await reset_dut(dut)
    await check_mul(dut, 7, -8, -56, "7*-8")


@cocotb.test()
async def test_mul_by_one(dut):
    await reset_dut(dut)
    await check_mul(dut, 123456, 1, 123456, "x*1")


@cocotb.test()
async def test_mul_by_minus_one(dut):
    await reset_dut(dut)
    await check_mul(dut, 123456, -1, -123456, "x*-1")


@cocotb.test()
async def test_mul_high_bit(dut):
    # hu: bit31 operandus — a multiplikandus shiftje 32-bitre wrap-el
    await reset_dut(dut)
    await check_mul(dut, to_s32(INT_MIN), 1, to_s32(INT_MIN), "INT_MIN*1")


@cocotb.test()
async def test_mul_int_min_by_two(dut):
    # hu: INT_MIN * 2 = 0x100000000 → alsó 32 bit = 0
    await reset_dut(dut)
    await check_mul(dut, to_s32(INT_MIN), 2, 0, "INT_MIN*2")


@cocotb.test()
async def test_mul_large(dut):
    # hu: 0x12345 * 0x6789 = 0x... alsó 32 bit
    await reset_dut(dut)
    await check_mul(dut, 0x12345, 0x6789, (0x12345 * 0x6789) & 0xFFFFFFFF, "0x12345*0x6789")


@cocotb.test()
async def test_mul_both_high(dut):
    # hu: két nagy érték — teljes wrapping
    await reset_dut(dut)
    a, b = 0xDEADBEEF, 0x1234
    await check_mul(dut, a, b, (a * b) & 0xFFFFFFFF, "0xDEADBEEF*0x1234")


# ============================================================
# Handshake / időzítés
# ============================================================

@cocotb.test()
async def test_busy_then_done(dut):
    # hu: start után o_busy magas, majd pontosan 1 ciklusig o_done.
    await reset_dut(dut)
    dut.i_op_a.value = to_u32(6)
    dut.i_op_b.value = to_u32(7)
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    await RisingEdge(dut.i_clk)
    assert int(dut.o_busy.value) == 1, "start után o_busy magas várt"

    done_cycles = 0
    for _ in range(80):
        await RisingEdge(dut.i_clk)
        if int(dut.o_done.value) == 1:
            done_cycles += 1
            assert int(dut.o_product.value) == 42, "6*7 szorzat"
            await RisingEdge(dut.i_clk)
            assert int(dut.o_done.value) == 0, "o_done csak 1 ciklus pulzus"
            break
    assert done_cycles == 1, "o_done pontosan egyszer pulzált"
    assert int(dut.o_busy.value) == 0, "befejezés után o_busy alacsony"


@cocotb.test()
async def test_back_to_back(dut):
    # hu: két egymást követő szorzás — a szorzó újraindítható.
    await reset_dut(dut)
    await check_mul(dut, 100, 9, 900, "1. szorzás 100*9")
    await check_mul(dut, -55, 4, -220, "2. szorzás -55*4")
