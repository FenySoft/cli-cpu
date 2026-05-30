# hu: CLI-CPU F2.8.1 — UART receiver (uart_rx) cocotb tesztjei. 8N1 keret
#     (1 start + 8 data LSB-first + 1 stop), konfigurálható baud
#     (CLOCKS_PER_BAUD). A modul a bit-közepén mintavételez (fél-baud
#     igazítás a start után), 2-FF szinkronizerrel az aszinkron i_rx-re.
#     o_valid 1-ciklusos pulzus a vett byte-ra, o_frame_err ha a stop-bit
#     nem 1. A teszt a host→chip betöltési út alapja (boot-over-UART loader).
# en: CLI-CPU F2.8.1 — cocotb tests for the UART receiver (uart_rx). 8N1
#     frame (1 start + 8 data LSB-first + 1 stop), configurable baud
#     (CLOCKS_PER_BAUD). The module samples at bit-center (half-baud
#     alignment after start), with a 2-FF synchronizer on the async i_rx.
#     o_valid pulses 1 cycle per received byte, o_frame_err if the stop bit
#     is not 1. This is the basis of the host→chip load path
#     (boot-over-UART loader).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

BAUD = 8  # hu: egyeznie kell a -GCLOCKS_PER_BAUD=8 compile arg-gal


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_rx.value = 1          # hu: idle = magas
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_byte(dut, byte, stop=1):
    """hu: 8N1 keret kiadása az i_rx-re, baud-onként BAUD ciklus."""
    # start bit
    dut.i_rx.value = 0
    for _ in range(BAUD):
        await RisingEdge(dut.clk)
    # 8 data bit, LSB-first
    for i in range(8):
        dut.i_rx.value = (byte >> i) & 1
        for _ in range(BAUD):
            await RisingEdge(dut.clk)
    # stop bit
    dut.i_rx.value = stop
    for _ in range(BAUD):
        await RisingEdge(dut.clk)
    dut.i_rx.value = 1          # vissza idle-re


async def recv_byte(dut, timeout=400):
    """hu: o_valid pulzusra vár, visszaadja a data + frame_err értéket."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.o_valid.value) == 1:
            return {
                "data": int(dut.o_data.value),
                "frame_err": int(dut.o_frame_err.value),
            }
    raise AssertionError("uart_rx timeout: nincs o_valid")


async def check_rx(dut, byte, msg=""):
    send = cocotb.start_soon(send_byte(dut, byte))
    r = await recv_byte(dut)
    await send
    assert r["frame_err"] == 0, f"{msg}: váratlan frame_err"
    assert r["data"] == byte, f"{msg}: data {r['data']:#04x} != {byte:#04x}"


# ============================================================
# Alap vétel / Basic receive
# ============================================================

@cocotb.test()
async def test_rx_0x55(dut):
    await reset_dut(dut)
    await check_rx(dut, 0x55, "0x55")


@cocotb.test()
async def test_rx_0xaa(dut):
    await reset_dut(dut)
    await check_rx(dut, 0xAA, "0xAA")


@cocotb.test()
async def test_rx_0x00(dut):
    await reset_dut(dut)
    await check_rx(dut, 0x00, "0x00")


@cocotb.test()
async def test_rx_0xff(dut):
    await reset_dut(dut)
    await check_rx(dut, 0xFF, "0xFF")


@cocotb.test()
async def test_rx_arbitrary(dut):
    await reset_dut(dut)
    await check_rx(dut, 0x3C, "0x3C")
    await check_rx(dut, 0x81, "0x81")


# ============================================================
# o_valid pulzus / valid is a 1-cycle pulse
# ============================================================

@cocotb.test()
async def test_valid_is_pulse(dut):
    await reset_dut(dut)
    send = cocotb.start_soon(send_byte(dut, 0x42))
    # várjuk az első o_valid-ot
    seen = 0
    for _ in range(400):
        await RisingEdge(dut.clk)
        if int(dut.o_valid.value) == 1:
            seen += 1
            assert int(dut.o_data.value) == 0x42, "0x42 data"
            await RisingEdge(dut.clk)
            assert int(dut.o_valid.value) == 0, "o_valid csak 1 ciklus"
            break
    await send
    assert seen == 1, "o_valid pontosan egyszer"


# ============================================================
# Framing error / keret-hiba (stop bit = 0)
# ============================================================

@cocotb.test()
async def test_frame_error(dut):
    await reset_dut(dut)
    send = cocotb.start_soon(send_byte(dut, 0x7E, stop=0))
    r = await recv_byte(dut)
    await send
    assert r["frame_err"] == 1, "stop=0 → frame_err várt"


# ============================================================
# Back-to-back vétel / két egymást követő byte
# ============================================================

@cocotb.test()
async def test_back_to_back(dut):
    await reset_dut(dut)
    await check_rx(dut, 0x12, "1. byte 0x12")
    await check_rx(dut, 0xED, "2. byte 0xED")
