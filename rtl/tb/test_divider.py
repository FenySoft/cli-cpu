# hu: CLI-CPU F2.7 — cilcpu_divider.v szekvenciális előjeles osztó cocotb
#     tesztjei. A kombinációs ALU-divízió (cilcpu_alu.v ALU_DIV/ALU_REM)
#     a Vivado-szintézisben 287 CARRY4 / ~86 ns kritikus utat adott — a
#     gyökér-fix egy többciklusú (1 bit/ciklus restoring) osztó. Ez a teszt
#     a viselkedési szerződést rögzíti: a hányados/maradék C#-szemantika
#     (csonkítás 0 felé, a maradék előjele az osztandóé), a div-by-zero és
#     az INT_MIN/-1 overflow — azonos a korábbi test_alu DIV/REM esetekkel.
# en: CLI-CPU F2.7 — cocotb tests for the cilcpu_divider.v sequential
#     signed divider. The combinational ALU division produced a 287-CARRY4
#     / ~86 ns critical path in Vivado synthesis; the root fix is a
#     multi-cycle (1 bit/cycle restoring) divider. This test pins the
#     behavioral contract: quotient/remainder C# semantics (truncate
#     toward zero, remainder sign = dividend sign), div-by-zero and the
#     INT_MIN/-1 overflow — identical to the former test_alu DIV/REM cases.

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
    """hu: Divider reset + clock indítás / en: reset divider + start clock."""
    cocotb.start_soon(Clock(dut.i_clk, 10, units="ns").start())
    dut.i_start.value = 0
    dut.i_dividend.value = 0
    dut.i_divisor.value = 0
    dut.i_rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)


async def do_divide(dut, dividend, divisor, timeout=80):
    """hu: start-pulzus, várakozás o_done-ra, eredmény visszaadása.
    en: pulse start, wait for o_done, return the result dict."""
    dut.i_dividend.value = to_u32(dividend)
    dut.i_divisor.value = to_u32(divisor)
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    for _ in range(timeout):
        await RisingEdge(dut.i_clk)
        if int(dut.o_done.value) == 1:
            return {
                "quotient": int(dut.o_quotient.value),
                "remainder": int(dut.o_remainder.value),
                "div_zero": int(dut.o_trap_div_zero.value),
                "overflow": int(dut.o_trap_overflow.value),
            }
    raise AssertionError(f"divider timeout ({timeout} clk): {dividend}/{divisor}")


async def check_div(dut, a, b, exp_q, exp_r, msg=""):
    """hu: hányados + maradék ellenőrzés, trap nélkül.
    en: assert quotient + remainder, no trap expected."""
    r = await do_divide(dut, a, b)
    assert r["div_zero"] == 0, f"{msg}: váratlan div_zero"
    assert r["overflow"] == 0, f"{msg}: váratlan overflow"
    assert to_s32(r["quotient"]) == exp_q, \
        f"{msg}: hányados {to_s32(r['quotient'])} != {exp_q}"
    assert to_s32(r["remainder"]) == exp_r, \
        f"{msg}: maradék {to_s32(r['remainder'])} != {exp_r}"


# ============================================================
# Alap osztás / Basic division
# ============================================================

@cocotb.test()
async def test_div_basic(dut):
    await reset_dut(dut)
    await check_div(dut, 10, 3, 3, 1, "10/3")


@cocotb.test()
async def test_div_exact(dut):
    await reset_dut(dut)
    await check_div(dut, 42, 6, 7, 0, "42/6")


@cocotb.test()
async def test_div_by_one(dut):
    await reset_dut(dut)
    await check_div(dut, 12345, 1, 12345, 0, "12345/1")


@cocotb.test()
async def test_div_zero_dividend(dut):
    await reset_dut(dut)
    await check_div(dut, 0, 7, 0, 0, "0/7")


@cocotb.test()
async def test_div_by_self(dut):
    await reset_dut(dut)
    await check_div(dut, 7, 7, 1, 0, "7/7")


@cocotb.test()
async def test_div_smaller_dividend(dut):
    # hu: |osztandó| < |osztó| → hányados 0, maradék = osztandó
    await reset_dut(dut)
    await check_div(dut, 3, 10, 0, 3, "3/10")


# ============================================================
# Előjel-kombinációk / Sign combinations
#   C#/ECMA-335: hányados 0 felé csonkít, a maradék előjele az osztandóé.
# ============================================================

@cocotb.test()
async def test_div_neg_dividend(dut):
    await reset_dut(dut)
    await check_div(dut, -10, 3, -3, -1, "-10/3")


@cocotb.test()
async def test_div_neg_divisor(dut):
    await reset_dut(dut)
    await check_div(dut, 10, -3, -3, 1, "10/-3")


@cocotb.test()
async def test_div_both_negative(dut):
    await reset_dut(dut)
    await check_div(dut, -10, -3, 3, -1, "-10/-3")


@cocotb.test()
async def test_div_int_max(dut):
    await reset_dut(dut)
    await check_div(dut, INT_MAX, 2, INT_MAX // 2, 1, "INT_MAX/2")


@cocotb.test()
async def test_div_int_min_even(dut):
    # hu: INT_MIN/2 — nem overflow (az eredmény elfér int32-ben)
    await reset_dut(dut)
    await check_div(dut, to_s32(INT_MIN), 2, -1073741824, 0, "INT_MIN/2")


# ============================================================
# Trap-esetek / Trap cases
# ============================================================

@cocotb.test()
async def test_div_by_zero(dut):
    await reset_dut(dut)
    r = await do_divide(dut, 10, 0)
    assert r["div_zero"] == 1, "10/0: div_zero trap várt"


@cocotb.test()
async def test_div_zero_by_zero(dut):
    await reset_dut(dut)
    r = await do_divide(dut, 0, 0)
    assert r["div_zero"] == 1, "0/0: div_zero trap várt"


@cocotb.test()
async def test_div_int_min_by_minus_one(dut):
    # hu: INT_MIN/-1 → overflow flag; a maradék 0 (REM-hez NEM trap).
    # en: INT_MIN/-1 → overflow flag; remainder is 0 (NOT a trap for REM).
    await reset_dut(dut)
    r = await do_divide(dut, to_s32(INT_MIN), -1)
    assert r["overflow"] == 1, "INT_MIN/-1: overflow flag várt"
    assert r["div_zero"] == 0, "INT_MIN/-1: nem div_zero"
    assert to_s32(r["remainder"]) == 0, \
        f"INT_MIN%-1 = 0 várt, got {to_s32(r['remainder'])}"


# ============================================================
# Handshake / időzítés
# ============================================================

@cocotb.test()
async def test_busy_then_done(dut):
    # hu: start után o_busy magas, majd pontosan 1 ciklusig o_done.
    await reset_dut(dut)
    dut.i_dividend.value = to_u32(100)
    dut.i_divisor.value = to_u32(7)
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
            assert to_s32(int(dut.o_quotient.value)) == 14, "100/7 hányados"
            assert to_s32(int(dut.o_remainder.value)) == 2, "100%7 maradék"
            await RisingEdge(dut.i_clk)
            assert int(dut.o_done.value) == 0, "o_done csak 1 ciklus pulzus"
            break
    assert done_cycles == 1, "o_done pontosan egyszer pulzált"
    assert int(dut.o_busy.value) == 0, "befejezés után o_busy alacsony"


@cocotb.test()
async def test_back_to_back(dut):
    # hu: két egymást követő osztás — a divider újraindítható.
    await reset_dut(dut)
    await check_div(dut, 100, 9, 11, 1, "1. osztás 100/9")
    await check_div(dut, -55, 4, -13, -3, "2. osztás -55/4")
