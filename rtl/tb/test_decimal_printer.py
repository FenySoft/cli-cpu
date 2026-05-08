# hu: CLI-CPU F2.7 Sub2 — decimal_printer modul cocotb tesztek.
#     A printer egy 32-bit signed/unsigned értéket küld ki ASCII decimális
#     karakterláncként a UART-on \r\n terminátorral. Sim: CLOCKS_PER_BAUD=8.
# en: CLI-CPU F2.7 Sub2 — decimal_printer module cocotb tests. The printer
#     sends a 32-bit signed/unsigned value as ASCII decimal over UART
#     terminated with \r\n. Sim: CLOCKS_PER_BAUD=8.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_uart import uart_rx_byte


CLK_PERIOD_NS    = 20
CLOCKS_PER_BAUD  = 8


async def _setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    dut.rst_n.value    = 0
    dut.i_value.value  = 0
    dut.i_signed.value = 0
    dut.i_start.value  = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def _trigger(dut, value, signed):
    dut.i_value.value  = value & 0xFFFFFFFF
    dut.i_signed.value = 1 if signed else 0
    dut.i_start.value  = 1
    await RisingEdge(dut.clk)
    dut.i_start.value  = 0


async def _read_until_lf(dut, max_bytes=16):
    """hu: Olvasás, amíg \n-t nem kapunk vagy max_bytes el nem fogy.
    en: Read until \n or max_bytes."""
    out = bytearray()
    for _ in range(max_bytes):
        b = await uart_rx_byte(dut, dut.o_tx, CLOCKS_PER_BAUD)
        out.append(b)
        if b == 0x0A:
            break
    return bytes(out)


async def _expect_print(dut, value, signed, expected_str):
    await _trigger(dut, value, signed)
    line = await _read_until_lf(dut)
    expected = expected_str.encode("ascii") + b"\r\n"
    assert line == expected, \
        f"value={value} signed={signed}: expected {expected!r}, got {line!r}"


@cocotb.test()
async def test_01_print_zero(dut):
    """hu: 0 → '0\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 0, signed=False, expected_str="0")


@cocotb.test()
async def test_02_print_single_digit(dut):
    """hu: 5 → '5\\r\\n' (Fibonacci(5) eredmény-formátum)."""
    await _setup(dut)
    await _expect_print(dut, 5, signed=False, expected_str="5")


@cocotb.test()
async def test_03_print_two_digits(dut):
    """hu: 42 → '42\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 42, signed=False, expected_str="42")


@cocotb.test()
async def test_04_print_fib20(dut):
    """hu: 6765 (= Fibonacci(20)) → '6765\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 6765, signed=False, expected_str="6765")


@cocotb.test()
async def test_05_print_negative(dut):
    """hu: -1 signed → '-1\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 0xFFFFFFFF, signed=True, expected_str="-1")


@cocotb.test()
async def test_06_print_negative_large(dut):
    """hu: -2147483648 (INT32_MIN) signed → '-2147483648\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 0x80000000, signed=True, expected_str="-2147483648")


@cocotb.test()
async def test_07_print_max_positive(dut):
    """hu: 2147483647 (INT32_MAX) signed → '2147483647\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 0x7FFFFFFF, signed=True, expected_str="2147483647")


@cocotb.test()
async def test_08_print_unsigned_max(dut):
    """hu: 0xFFFFFFFF unsigned → '4294967295\\r\\n'."""
    await _setup(dut)
    await _expect_print(dut, 0xFFFFFFFF, signed=False, expected_str="4294967295")


@cocotb.test()
async def test_09_busy_during_print(dut):
    """hu: i_start után o_busy magas, kiírás végén leesik.
    en: o_busy high after i_start, falls when printing completes."""
    await _setup(dut)
    await _trigger(dut, 7, signed=False)
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.o_busy.value) == 1

    line = await _read_until_lf(dut)
    assert line == b"7\r\n"

    # hu: Néhány ciklus múlva busy=0
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.o_busy.value) == 0:
            break
    assert int(dut.o_busy.value) == 0


@cocotb.test()
async def test_10_back_to_back(dut):
    """hu: Két egymás utáni érték — a második is helyes.
    en: Two values back-to-back — second one is also correct."""
    await _setup(dut)

    await _expect_print(dut, 11, signed=False, expected_str="11")

    # hu: várjuk meg, hogy busy=0 és a uart_tx is csendes
    for _ in range(40):
        await RisingEdge(dut.clk)
        if int(dut.o_busy.value) == 0:
            break

    await _expect_print(dut, 22, signed=False, expected_str="22")
