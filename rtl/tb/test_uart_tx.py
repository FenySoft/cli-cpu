# hu: CLI-CPU F2.7 Sub2 — uart_tx modul cocotb tesztek.
#     A modul önállóan tesztelhető: 8N1 keret, paraméterezhető baud-osztó.
#     Sim-ben CLOCKS_PER_BAUD=8 (a Makefile -G-vel) — gyors a verifikációnál.
# en: CLI-CPU F2.7 Sub2 — uart_tx module cocotb tests. The module is
#     standalone-testable: 8N1 frame, parameterizable baud divider.
#     CLOCKS_PER_BAUD=8 in sim (-G in Makefile) for fast verification.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_uart import uart_rx_byte


CLK_PERIOD_NS    = 20  # 50 MHz
CLOCKS_PER_BAUD  = 8   # sim-only (Makefile felülírja -GCLOCKS_PER_BAUD=8-cal)


async def _setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    dut.rst_n.value   = 0
    dut.i_data.value  = 0
    dut.i_start.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def _send_byte(dut, byte_value):
    dut.i_data.value  = byte_value
    dut.i_start.value = 1
    await RisingEdge(dut.clk)
    dut.i_start.value = 0


@cocotb.test()
async def test_01_idle_tx_high(dut):
    """hu: Reset után a TX vonal magas (idle).
    en: After reset, TX line is high (idle)."""
    await _setup(dut)
    assert int(dut.o_tx.value) == 1
    assert int(dut.o_busy.value) == 0


@cocotb.test()
async def test_02_send_0x55(dut):
    """hu: 0x55 = 01010101 minta — váltakozó bitek.
    en: 0x55 = 01010101 pattern — alternating bits."""
    await _setup(dut)
    await _send_byte(dut, 0x55)
    received = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received == 0x55, f"expected 0x55, got 0x{received:02X}"


@cocotb.test()
async def test_03_send_0xAA(dut):
    """hu: 0xAA = 10101010 minta — fordított váltakozás.
    en: 0xAA = 10101010 — opposite alternation."""
    await _setup(dut)
    await _send_byte(dut, 0xAA)
    received = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received == 0xAA, f"expected 0xAA, got 0x{received:02X}"


@cocotb.test()
async def test_04_send_0x00(dut):
    """hu: 0x00 — minden adat-bit alacsony, csak a stop bit magas.
    en: 0x00 — all data bits low, only stop bit high."""
    await _setup(dut)
    await _send_byte(dut, 0x00)
    received = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received == 0x00


@cocotb.test()
async def test_05_send_0xFF(dut):
    """hu: 0xFF — minden adat-bit magas, csak a start bit alacsony.
    en: 0xFF — all data bits high, only start bit low."""
    await _setup(dut)
    await _send_byte(dut, 0xFF)
    received = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received == 0xFF


@cocotb.test()
async def test_06_send_ascii_5(dut):
    """hu: ASCII '5' = 0x35 — Fibonacci(5) eredmény mintabyte.
    en: ASCII '5' = 0x35 — sample byte for Fibonacci(5) result."""
    await _setup(dut)
    await _send_byte(dut, 0x35)
    received = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received == 0x35


@cocotb.test()
async def test_07_busy_during_transmit(dut):
    """hu: Adás közben o_busy magas, a frame után visszamegy 0-ra.
    en: o_busy is high during transmission, returns to 0 after the frame."""
    await _setup(dut)
    await _send_byte(dut, 0x42)

    # hu: Néhány ciklus múlva a busy-nak magasnak kell lennie
    # en: A few cycles later busy must be high
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.o_busy.value) == 1, "busy not asserted during TX"

    # hu: 10 baud × CLOCKS_PER_BAUD ciklus után: idle
    # en: After 10 baud × CLOCKS_PER_BAUD cycles: idle
    for _ in range(10 * CLOCKS_PER_BAUD + 4):
        await RisingEdge(dut.clk)
    assert int(dut.o_busy.value) == 0, "busy still high after frame ended"


@cocotb.test()
async def test_08_back_to_back(dut):
    """hu: Egy byte adása után rögtön egy másik — a második kell, hogy
        helyes legyen, miután a busy leesett.
    en: One byte transmit then another back-to-back — the second must
        decode correctly after busy drops."""
    await _setup(dut)

    await _send_byte(dut, 0x31)   # '1'
    received1 = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received1 == 0x31

    # hu: várjuk meg, amíg busy=0
    # en: wait for busy=0
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.o_busy.value) == 0:
            break

    await _send_byte(dut, 0x32)   # '2'
    received2 = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
    assert received2 == 0x32
