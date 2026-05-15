# hu: CLI-CPU F2.7 Sub4 — board-szintű wrapper (`cilcpu_a7lite_board.v`)
#     cocotb tesztek. A board.v a `cilcpu_a7lite_top` köré rakja a Xilinx
#     STARTUPE2 primitívet (CCLK driver) és a négy IOBUF-ot (DQ inout).
#     Sim-ben a `+define+CILCPU_SIM_BOARD` makró exposálja a belső split
#     QSPI vonalakat, a flash slave ezeket figyeli.
# en: CLI-CPU F2.7 Sub4 — board-level wrapper (`cilcpu_a7lite_board.v`)
#     cocotb tests. board.v wraps the Xilinx STARTUPE2 primitive (CCLK
#     driver) and four IOBUFs (DQ inout) around `cilcpu_a7lite_top`.
#     In sim the `+define+CILCPU_SIM_BOARD` macro exposes the internal
#     split QSPI nets so the flash slave can observe them.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_qspi import TQSPIFlashModel, qspi_flash_driver
from tb_isa import (
    OP_LDARG_0,
    OP_LDC_I4_3,
    OP_ADD,
    OP_RET,
    TRAP_INVALID_OPCODE,
    make_method,
)
from tb_uart import uart_rx_byte


# ============================================================
# hu: Wrapper sim paraméterek (Makefile -G-vel egyezően)
# en: Wrapper sim parameters (must match Makefile -G overrides)
# ============================================================
DEBOUNCE_BITS    = 4
DEBOUNCE_CYCLES  = (1 << DEBOUNCE_BITS) + 4
CLOCKS_PER_BAUD  = 8
BOOT_ARG_VALUE   = 5                    # default — Sub4.4 smoke tesztekhez
CLK_PERIOD_NS    = 20                   # 50 MHz


# ============================================================
# hu: A board.v sim-only debug portjai (lásd `+define+CILCPU_SIM_BOARD`):
#       o_qspi_clk_dbg     — STARTUPE2 USRCCLKO probe
#       o_qspi_cs_n        — flash CS# (board szintű kimenet)
#       o_qspi_dq_out_dbg  — master → flash DQ
#       i_qspi_dq_in_dbg   — flash → master DQ (cocotb hajtja)
#       o_qspi_dq_oe_dbg   — DQ output enable (csak referenciának)
# en: board.v sim-only debug ports (see `+define+CILCPU_SIM_BOARD`):
#       o_qspi_clk_dbg     — STARTUPE2 USRCCLKO probe
#       o_qspi_cs_n        — flash CS# (board-level output)
#       o_qspi_dq_out_dbg  — master → flash DQ
#       i_qspi_dq_in_dbg   — flash → master DQ (driven by cocotb)
#       o_qspi_dq_oe_dbg   — DQ output enable (reference only)
# ============================================================


# ============================================================
# hu: Segédfüggvények
# en: Helpers
# ============================================================

async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.i_clk_50m, CLK_PERIOD_NS, units="ns").start())


async def _reset(dut):
    """hu: KEY1 reset szekvencia.
    en: KEY1 reset sequence."""
    dut.i_rst_btn_n.value      = 0
    dut.i_start_btn_n.value    = 1
    dut.i_qspi_dq_in_dbg.value = 0
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)
    dut.i_rst_btn_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)


async def _press_start(dut):
    dut.i_start_btn_n.value = 0
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)
    dut.i_start_btn_n.value = 1
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)


async def _wait_for_halt_or_trap(dut, max_cycles=4000):
    """hu: A board belsejében (u_top) figyeljük a halt/trap latch-eket.
    en: Watch the halt/trap latches inside the board wrapper (u_top)."""
    for _ in range(max_cycles):
        await RisingEdge(dut.i_clk_50m)
        try:
            halted  = int(dut.u_top.r_halted.value)
            trapped = int(dut.u_top.r_trapped.value)
        except (ValueError, AttributeError):
            continue
        if halted or trapped:
            for _ in range(2):
                await RisingEdge(dut.i_clk_50m)
            return (
                int(dut.u_top.r_halted.value),
                int(dut.u_top.r_trapped.value),
                int(dut.u_top.u_core.o_return_value.value),
                int(dut.u_top.u_core.o_trap_code.value),
                int(dut.u_top.u_core.o_pc.value),
            )
    raise TimeoutError(
        f"wrapper didn't reach halt/trap within {max_cycles} cycles"
    )


async def _read_uart_line(dut, max_bytes=16):
    out = bytearray()
    for _ in range(max_bytes):
        b = await uart_rx_byte(dut, dut.o_uart_tx, CLOCKS_PER_BAUD)
        out.append(b)
        if b == 0x0A:
            break
    return bytes(out)


async def _setup(dut, code_bytes):
    """hu: Közös setup — clock, flash slave a board sim-debug portjaihoz, reset.
    en: Common setup — clock, flash slave bound to board sim-debug ports, reset."""
    await _start_clock(dut)
    flash = TQSPIFlashModel(code_bytes)
    cocotb.start_soon(qspi_flash_driver(
        dut, flash,
        clk_signal   = dut.o_qspi_clk_dbg,
        cs_signal    = dut.o_qspi_cs_n,
        dq_in_signal = dut.i_qspi_dq_in_dbg,
        dq_out_signal= dut.o_qspi_dq_out_dbg,
    ))
    await _reset(dut)
    return flash


# ============================================================
# hu: Tesztek
# en: Tests
# ============================================================

@cocotb.test()
async def test_01_reset_state(dut):
    """hu: Reset után a board szintű LED-ek inaktívak (active low).
    en: After reset, board-level LEDs are inactive (active low)."""
    await _setup(dut, code_bytes=None)

    assert int(dut.o_led1_n.value) == 1, "halt LED active after pure reset"
    assert int(dut.o_led2_n.value) == 1, "trap LED active after pure reset"
    assert int(dut.o_qspi_cs_n.value) == 1, "CS# should be deasserted in idle"


@cocotb.test()
async def test_02_ldarg_ret_halt_uart(dut):
    """hu: KEY2 → push 5 → LDARG_0 + RET → halt, UART "5\\r\\n".
        Ez egy teljes round-trip a board wrapper-en keresztül, beleértve
        a STARTUPE2 CCLK útvonalat és a flash slave-et.
    en: KEY2 → push 5 → LDARG_0 + RET → halt, UART "5\\r\\n".
        Full round-trip through the board wrapper, including the
        STARTUPE2 CCLK path and the flash slave."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_RET],
        arg_count=1,
    ))

    await _press_start(dut)
    line = await _read_uart_line(dut)
    assert line == b"5\r\n", f"expected b'5\\r\\n', got {line!r}"

    assert int(dut.u_top.r_halted.value)  == 1
    assert int(dut.u_top.r_trapped.value) == 0
    assert int(dut.o_led1_n.value) == 0, "halt LED should be active"
    assert int(dut.o_led2_n.value) == 1, "trap LED should be inactive"


@cocotb.test()
async def test_03_ldarg_add_halt(dut):
    """hu: LDARG_0 + LDC.I4_3 + ADD + RET → return = arg + 3 = 8.
        Bizonyítja, hogy az ALU út is működik a board.v-en át.
    en: LDARG_0 + LDC.I4_3 + ADD + RET → return = arg + 3 = 8.
        Verifies the ALU path also works through board.v."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, OP_LDC_I4_3, OP_ADD, OP_RET],
        arg_count=1,
    ))

    await _press_start(dut)
    halted, trapped, ret, trap_code, _pc = await _wait_for_halt_or_trap(dut)

    assert halted == 1, f"expected halt, got halted={halted} trapped={trapped}"
    assert trapped == 0, f"unexpected trap, code=0x{trap_code:02X}"
    assert ret == BOOT_ARG_VALUE + 3, \
        f"expected {BOOT_ARG_VALUE + 3}, got {ret}"


@cocotb.test()
async def test_04_invalid_opcode_trap_uart(dut):
    """hu: 0xFF opkód → trap, UART "3\\r\\n" (TRAP_INVALID_OPCODE = 3).
    en: 0xFF opcode → trap, UART "3\\r\\n" (TRAP_INVALID_OPCODE = 3)."""
    await _setup(dut, code_bytes=make_method(
        body=[OP_LDARG_0, 0xFF, OP_RET],
        arg_count=1,
    ))

    await _press_start(dut)
    line = await _read_uart_line(dut)
    expected = f"{TRAP_INVALID_OPCODE}\r\n".encode("ascii")
    assert line == expected, f"expected {expected!r}, got {line!r}"

    assert int(dut.u_top.r_trapped.value) == 1
    assert int(dut.u_top.r_halted.value)  == 0
    assert int(dut.o_led2_n.value) == 0, "trap LED should be active"
    assert int(dut.o_led1_n.value) == 1, "halt LED should be inactive"


# hu: Az end-to-end Fibonacci(20)=6765 demó külön fájlban él:
#     `test_a7lite_board_fib.py`, mert eltérő BOOT_ARG_VALUE-t (=20) igényel.
# en: The end-to-end Fibonacci(20)=6765 demo lives in a separate file:
#     `test_a7lite_board_fib.py` since it needs BOOT_ARG_VALUE=20.
