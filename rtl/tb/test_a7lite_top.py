# hu: CLI-CPU F2.7 Sub1 — MicroPhase A7-Lite top-level wrapper cocotb tesztek.
#     Verifikálja a `cilcpu_a7lite_top.v` FSM-jét: KEY1 reset, KEY2 start
#     gomb (debouncer-rel), boot szekvenszer, LED státusz. A core
#     funkcionalitása már fedett a test_core.py-ban (172 xUnit + 51 cocotb),
#     ide csak wrapper-szintű smoke tesztek.
# en: CLI-CPU F2.7 Sub1 — MicroPhase A7-Lite top-level wrapper cocotb tests.
#     Verifies the `cilcpu_a7lite_top.v` FSM: KEY1 reset, KEY2 start button
#     (with debouncer), boot sequencer, LED status. Core functionality is
#     already covered by test_core.py (172 xUnit + 51 cocotb), this file
#     adds only wrapper-level smoke tests.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_qspi import TQSPIFlashModel, qspi_flash_driver
from tb_isa import (
    OP_LDARG_0,
    OP_LDC_I4_3,
    OP_LDC_I4_5,
    OP_LDC_I4_S,
    OP_ADD,
    OP_RET,
    TRAP_INVALID_OPCODE,
    make_method,
)


# ============================================================
# hu: Wrapper paraméterek (a Makefile -GDEBOUNCE_BITS=4 felülírja a
#     wrapper default 22 bites debouncert sim-időre).
# en: Wrapper parameters (Makefile passes -GDEBOUNCE_BITS=4 to override the
#     wrapper's default 22-bit debouncer for sim).
# ============================================================
DEBOUNCE_BITS    = 4
DEBOUNCE_CYCLES  = (1 << DEBOUNCE_BITS) + 4   # ~max counter + ráhagyás
BOOT_ARG_VALUE   = 5                          # cilcpu_a7lite_top default

CLK_PERIOD_NS    = 20  # 50 MHz


# ============================================================
# hu: Segédfüggvények
# en: Helpers
# ============================================================

async def _start_clock(dut):
    """hu: 50 MHz órajel indítása a wrapper bemeneten.
    en: Start the 50 MHz clock on the wrapper input."""
    cocotb.start_soon(Clock(dut.i_clk_50m, CLK_PERIOD_NS, units="ns").start())


async def _reset(dut):
    """hu: KEY1 reset szekvencia — i_rst_btn_n = 0 → 1, néhány stabilizáló ciklus.
    en: KEY1 reset sequence — i_rst_btn_n = 0 → 1, a few settle cycles."""
    dut.i_rst_btn_n.value   = 0
    dut.i_start_btn_n.value = 1
    dut.qspi_dq_in.value    = 0
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)
    dut.i_rst_btn_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)


async def _press_start(dut):
    """hu: KEY2 start gomb lenyomása + elengedése (debouncer-en átmenés).
    en: KEY2 start button press + release (passes through debouncer)."""
    dut.i_start_btn_n.value = 0
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)
    dut.i_start_btn_n.value = 1
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)


async def _wait_for_done(dut, max_cycles=4000):
    """hu: Vár, amíg a wrapper `S_DONE` állapotba ér (halt vagy trap latched).
        Visszatér: (halted, trapped, return_value, trap_code, pc).
    en: Wait until the wrapper enters `S_DONE` (halt or trap latched).
        Returns: (halted, trapped, return_value, trap_code, pc)."""
    for _ in range(max_cycles):
        await RisingEdge(dut.i_clk_50m)
        try:
            halted  = int(dut.r_halted.value)
            trapped = int(dut.r_trapped.value)
        except ValueError:
            continue
        if halted or trapped:
            # hu: Még néhány ciklus, hogy a S_DONE állapot stabilizálódjon
            for _ in range(2):
                await RisingEdge(dut.i_clk_50m)
            return (
                int(dut.r_halted.value),
                int(dut.r_trapped.value),
                int(dut.u_core.o_return_value.value),
                int(dut.u_core.o_trap_code.value),
                int(dut.u_core.o_pc.value),
            )
    raise TimeoutError(
        f"wrapper didn't reach S_DONE within {max_cycles} cycles"
    )


async def _setup(dut, code_bytes):
    """hu: Standard setup — clock, flash slave, reset.
    en: Standard setup — clock, flash slave, reset."""
    await _start_clock(dut)
    flash = TQSPIFlashModel(code_bytes)
    cocotb.start_soon(qspi_flash_driver(dut, flash))
    await _reset(dut)
    return flash


# ============================================================
# hu: Tesztek
# en: Tests
# ============================================================

@cocotb.test()
async def test_01_reset_state(dut):
    """hu: Reset után LED-ek inaktívak (active low: kimenet = 1).
    en: After reset both LEDs are inactive (active low: output = 1)."""
    await _setup(dut, code_bytes=None)

    assert int(dut.o_led1_n.value) == 1, "halt LED active after pure reset"
    assert int(dut.o_led2_n.value) == 1, "trap LED active after pure reset"
    assert int(dut.r_halted.value)  == 0
    assert int(dut.r_trapped.value) == 0


@cocotb.test()
async def test_02_idle_no_start(dut):
    """hu: KEY2 gomb nélkül a core nem indul el — LED-ek nem világítanak.
    en: Without KEY2 press, the core never starts — LEDs stay off."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_RET],
        arg_count=1,
    ))

    for _ in range(200):
        await RisingEdge(dut.i_clk_50m)
        assert int(dut.o_led1_n.value) == 1, "halt LED rose without start"
        assert int(dut.o_led2_n.value) == 1, "trap LED rose without start"


@cocotb.test()
async def test_03_ldarg_ret_smoke(dut):
    """hu: KEY2-re a wrapper push-olja a default arg-ot (5), a core
        LDARG_0 + RET-re ezt visszaadja. Halt LED felgyullad.
    en: On KEY2 press the wrapper pushes the default arg (5), the core
        returns it via LDARG_0 + RET. Halt LED lights."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_RET],
        arg_count=1,
    ))

    await _press_start(dut)
    halted, trapped, ret, trap_code, _pc = await _wait_for_done(dut)

    assert halted  == 1, f"expected halt, got halted={halted} trapped={trapped}"
    assert trapped == 0, f"unexpected trap, code=0x{trap_code:02X}"
    assert ret == BOOT_ARG_VALUE, \
        f"expected return_value={BOOT_ARG_VALUE}, got {ret}"
    assert int(dut.o_led1_n.value) == 0, "halt LED should be active (low)"
    assert int(dut.o_led2_n.value) == 1, "trap LED should be inactive (high)"


@cocotb.test()
async def test_04_ldarg_add_smoke(dut):
    """hu: Program: LDARG_0 + LDC.I4_3 + ADD + RET → eredmény = arg + 3.
    en: Program: LDARG_0 + LDC.I4_3 + ADD + RET → result = arg + 3."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_LDC_I4_3, OP_ADD, OP_RET],
        arg_count=1,
    ))

    await _press_start(dut)
    halted, trapped, ret, trap_code, _pc = await _wait_for_done(dut)

    assert halted  == 1, f"expected halt, got halted={halted} trapped={trapped}"
    assert trapped == 0, f"unexpected trap, code=0x{trap_code:02X}"
    assert ret == BOOT_ARG_VALUE + 3, \
        f"expected {BOOT_ARG_VALUE + 3}, got {ret}"


@cocotb.test()
async def test_05_invalid_opcode_trap(dut):
    """hu: Érvénytelen opkód → trap, trap LED felgyullad, halt LED nem.
    en: Invalid opcode → trap, trap LED lights, halt LED does not."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, 0xFF, OP_RET],   # 0xFF = invalid opcode
        arg_count=1,
    ))

    await _press_start(dut)
    halted, trapped, _ret, trap_code, _pc = await _wait_for_done(dut)

    assert trapped == 1, f"expected trap, got halted={halted} trapped={trapped}"
    assert halted  == 0, "halt should not assert on trap"
    assert trap_code == TRAP_INVALID_OPCODE, \
        f"expected trap_code=0x{TRAP_INVALID_OPCODE:02X}, got 0x{trap_code:02X}"
    assert int(dut.o_led1_n.value) == 1, "halt LED should be inactive"
    assert int(dut.o_led2_n.value) == 0, "trap LED should be active (low)"


@cocotb.test()
async def test_06_short_press_ignored(dut):
    """hu: Túl rövid (debounce limit alatti) gomb-impulzust a wrapper figyelmen
        kívül hagy — a core nem indul el.
    en: A press shorter than the debounce limit is ignored by the wrapper —
        the core does not start."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_RET],
        arg_count=1,
    ))

    # hu: Pár ciklus a debounce limit alatt (DEBOUNCE_CYCLES // 2-nél kevesebb)
    # en: A few cycles below the debounce limit
    dut.i_start_btn_n.value = 0
    for _ in range(2):
        await RisingEdge(dut.i_clk_50m)
    dut.i_start_btn_n.value = 1
    for _ in range(200):
        await RisingEdge(dut.i_clk_50m)
        assert int(dut.r_halted.value)  == 0, "core started on bouncy press"
        assert int(dut.r_trapped.value) == 0
