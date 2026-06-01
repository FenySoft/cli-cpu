# hu: CLI-CPU F2.8.6 — cocotb teszt a cilcpu_tt_board A7-Lite board-toptra
#     (a cilcpu_tt_top köré, board-pinekkel). A +define+CILCPU_SIM_BOARD split
#     debug portokra vált (a uio inout busz helyett). A teszt a board-szintű
#     boot e2e-t igazolja: i_uart_rx (U2) → loader → QSPI (a SoC belső portjain
#     át, MISO a i_uio_in_dbg-re szórva) → futás → eredmény az o_uart_tx-en (V2),
#     halt az o_led1_n-en (active-low). A reset a board 3-fokú sync-jén át (KEY1).
# en: CLI-CPU F2.8.6 — cocotb test for the cilcpu_tt_board A7-Lite board top
#     (around cilcpu_tt_top, with board pins). +define+CILCPU_SIM_BOARD switches
#     to split debug ports (instead of the uio inout bus). The test proves the
#     board-level boot e2e: i_uart_rx (U2) → loader → QSPI (via the SoC internal
#     ports, MISO scattered to i_uio_in_dbg) → run → result on o_uart_tx (V2),
#     halt on o_led1_n (active-low). Reset via the board's 3-stage sync (KEY1).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from test_core import _ldc_s, OP_RET
from test_soc import _u16_be, _u24_be
from tb_uart import uart_tx_bytes, uart_rx_string
from test_qspi_controller import TQSPIFlashModel, TQSPIPSRAMModel, qspi_slave_driver

UART_CPB  = 8
CMD_WRITE = 0xC0
CMD_BOOT  = 0xB0
DEV_PSRAM = 0x01

# hu: qspi-pmod DQ uio-pozíciók (SD0=uio1, SD1=uio2, SD2=uio4, SD3=uio5)
# en: qspi-pmod DQ uio positions
_DQ_BITS = (1, 2, 4, 5)


class _ScatterDQBoard:
    """hu: A 4-bit DQ nibble-t a board i_uio_in_dbg portjának qspi-pmod DQ
        pinjeire írja (uio 1,2,4,5). Csak írás (MISO).
    en: Writes the 4-bit DQ nibble to the qspi-pmod DQ pins of the board's
        i_uio_in_dbg port (uio 1,2,4,5). Write only (MISO)."""

    def __init__(self, dut):
        self._dut = dut

    @property
    def value(self):
        return 0

    @value.setter
    def value(self, nibble):
        n = int(nibble)
        v = 0
        for k, b in enumerate(_DQ_BITS):
            v |= ((n >> k) & 1) << b
        self._dut.i_uio_in_dbg.value = v


class _BoardQspiView:
    """hu: Shim — a qspi_slave_driver a tt_top SoC belső QSPI-portjain (mély
        hierarchia: u_top.u_soc) dolgozzon, a DQ-bemenetet a board sim debug
        portjára (i_uio_in_dbg) szórva.
    en: Shim — lets qspi_slave_driver operate on the tt_top SoC's internal QSPI
        ports (deep hierarchy: u_top.u_soc), scattering the DQ input to the
        board's sim debug port (i_uio_in_dbg)."""

    def __init__(self, dut):
        self.clk              = dut.i_clk_50m
        self.qspi_clk         = dut.u_top.u_soc.qspi_clk
        self.qspi_cs_flash_n  = dut.u_top.u_soc.qspi_cs_flash_n
        self.qspi_cs_psram_n  = dut.u_top.u_soc.qspi_cs_psram_n
        self.qspi_dq_out      = dut.u_top.u_soc.qspi_dq_out
        self.qspi_dq_in       = _ScatterDQBoard(dut)


def _bits(val, hi, lo):
    width = hi - lo + 1
    return (val >> lo) & ((1 << width) - 1)


async def _reset_board(dut):
    """hu: Board reset a KEY1-en (active-low) át, idle bemenetek.
    en: Board reset via KEY1 (active-low), idle inputs."""
    dut.i_uart_rx.value    = 1   # UART idle
    dut.i_uio_in_dbg.value = 0
    dut.i_rst_btn_n.value  = 0
    for _ in range(8):
        await RisingEdge(dut.i_clk_50m)
    dut.i_rst_btn_n.value = 1
    # hu: a 3-fokú reset-sync deassert + néhány ciklus
    # en: 3-stage reset-sync deassert + a few cycles
    for _ in range(8):
        await RisingEdge(dut.i_clk_50m)
    await Timer(1, units="ns")


async def _uart_load_and_boot(dut, program):
    while len(program) % 4 != 0:
        program += bytes([0x00])
    plen = len(program)
    write_frame = [CMD_WRITE, DEV_PSRAM] + _u24_be(0x00000) + _u16_be(plen) + list(program)
    boot_frame  = [CMD_BOOT, 0x01] + _u24_be(0x000000) + [0x00, 0x00]
    await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, write_frame)
    for _ in range(40):
        await RisingEdge(dut.i_clk_50m)
    await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, boot_frame)


@cocotb.test()
async def test_01_reset_uio_oe(dut):
    """hu: Reset után a sim uio_oe debug a qspi-pmod mintát mutatja: a CS/SCK
        pinek (uio 0,3,6,7) kimenetek, a DQ (uio 1,2,4,5) IDLE-ban bemenet.
        Az LED-ek inaktívak (active-low → 1).
    en: After reset the sim uio_oe debug shows the qspi-pmod pattern: CS/SCK
        pins (uio 0,3,6,7) outputs, DQ (uio 1,2,4,5) inputs in IDLE. LEDs
        inactive (active-low → 1)."""
    cocotb.start_soon(Clock(dut.i_clk_50m, 10, units="ns").start())
    await _reset_board(dut)

    oe = int(dut.o_uio_oe_dbg.value)
    for b in (0, 3, 6, 7):
        assert _bits(oe, b, b) == 1, f"uio_oe[{b}] (CS/SCK) nem kimenet"
    for b in _DQ_BITS:
        assert _bits(oe, b, b) == 0, f"uio_oe[{b}] (DQ) nem 0 IDLE-ban"

    assert int(dut.o_led1_n.value) == 1, "o_led1_n (halt) nem inaktív (1) reset után"
    assert int(dut.o_led2_n.value) == 1, "o_led2_n (trap) nem inaktív (1) reset után"
    assert int(dut.o_uart_tx.value) == 1, "o_uart_tx nem idle (1) reset után"


@cocotb.test()
async def test_02_boot_e2e_board(dut):
    """hu: Board-szintű boot e2e: i_uart_rx (U2) WRITE+BOOT → PSRAM-ból futás →
        eredmény (42) az o_uart_tx-en (V2), és a halt felgyújtja az o_led1_n-t
        (active-low → 0).
    en: Board-level boot e2e: i_uart_rx (U2) WRITE+BOOT → run from PSRAM →
        result (42) on o_uart_tx (V2), and halt lights o_led1_n (active-low → 0)."""
    cocotb.start_soon(Clock(dut.i_clk_50m, 10, units="ns").start())
    await _reset_board(dut)

    flash = TQSPIFlashModel()
    psram = TQSPIPSRAMModel()
    cocotb.start_soon(qspi_slave_driver(_BoardQspiView(dut), flash, psram))

    program = _ldc_s(42) + bytes([OP_RET])
    await _uart_load_and_boot(dut, program)

    result = await uart_rx_string(dut, dut.o_uart_tx, UART_CPB,
                                  terminator=ord('\n'), max_bytes=8)
    text = result.decode("ascii", errors="replace").strip()
    assert text == "42", f"o_uart_tx eredmény = {text!r}, várt '42'"

    # hu: halt → o_led1_n aktív (0)
    assert int(dut.o_led1_n.value) == 0, "o_led1_n nem aktív (0) a halt után"
    assert int(dut.o_led2_n.value) == 1, "o_led2_n (trap) tévesen aktív"
