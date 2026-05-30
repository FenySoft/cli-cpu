# hu: CLI-CPU F2.8.4 — GPIO MMIO blokk (cilcpu_gpio) cocotb tesztjei.
#     A CIL-T0 aktor MMIO-n keresztül olvas bemeneti pineket (GPIO_IN) és
#     hajt kimeneteket (GPIO_OUT), az irányt az GPIO_OE szabja. A bemeneti
#     pinek 2-FF szinkronizeren mennek át (metastabilitás). MMIO bázis:
#     0xF000_0200. Ez teszi a chipet I/O-képes aktor-csomóponttá (Symphact
#     valós I/O teszt).
# en: CLI-CPU F2.8.4 — cocotb tests for the GPIO MMIO block (cilcpu_gpio).
#     The CIL-T0 actor reads input pins (GPIO_IN) and drives outputs
#     (GPIO_OUT) via MMIO, direction set by GPIO_OE. Input pins pass through
#     a 2-FF synchronizer (metastability). MMIO base: 0xF000_0200. Makes the
#     chip an I/O-capable actor node (Symphact real-I/O test).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

GPIO_IN  = 0
GPIO_OUT = 1
GPIO_OE  = 2


async def settle(dut):
    await Timer(1, units="ns")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_cpu_addr.value = 0
    dut.i_cpu_wdata.value = 0
    dut.i_cpu_we.value = 0
    dut.i_cpu_re.value = 0
    dut.i_gpio_in.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await settle(dut)


async def cpu_write(dut, addr, data):
    dut.i_cpu_addr.value = addr
    dut.i_cpu_wdata.value = data & 0xFFFFFFFF
    dut.i_cpu_we.value = 1
    await RisingEdge(dut.clk)
    dut.i_cpu_we.value = 0
    dut.i_cpu_wdata.value = 0
    await settle(dut)


async def cpu_read(dut, addr):
    dut.i_cpu_addr.value = addr
    dut.i_cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.i_cpu_re.value = 0
    await settle(dut)
    return int(dut.o_cpu_rdata.value)


# ============================================================
# Kimenet írása / output write
# ============================================================

@cocotb.test()
async def test_reset_outputs_zero(dut):
    await reset_dut(dut)
    assert int(dut.o_gpio_out.value) == 0, "reset: out=0"
    assert int(dut.o_gpio_oe.value) == 0, "reset: oe=0"


@cocotb.test()
async def test_write_output(dut):
    await reset_dut(dut)
    await cpu_write(dut, GPIO_OUT, 0xA5)
    assert int(dut.o_gpio_out.value) == 0xA5, "out = 0xA5"
    # readback
    assert (await cpu_read(dut, GPIO_OUT)) == 0xA5, "out readback"


@cocotb.test()
async def test_write_oe(dut):
    await reset_dut(dut)
    await cpu_write(dut, GPIO_OE, 0x0F)
    assert int(dut.o_gpio_oe.value) == 0x0F, "oe = 0x0F"
    assert (await cpu_read(dut, GPIO_OE)) == 0x0F, "oe readback"


# ============================================================
# Bemenet olvasása / input read (2-FF sync)
# ============================================================

@cocotb.test()
async def test_read_input(dut):
    await reset_dut(dut)
    dut.i_gpio_in.value = 0x3C
    # szinkronizer-késleltetés bevárása
    for _ in range(4):
        await RisingEdge(dut.clk)
    await settle(dut)
    assert (await cpu_read(dut, GPIO_IN)) == 0x3C, "in = 0x3C"

    dut.i_gpio_in.value = 0xC3
    for _ in range(4):
        await RisingEdge(dut.clk)
    await settle(dut)
    assert (await cpu_read(dut, GPIO_IN)) == 0xC3, "in = 0xC3"


# ============================================================
# Out és in függetlenek / out and in independent
# ============================================================

@cocotb.test()
async def test_out_in_independent(dut):
    await reset_dut(dut)
    await cpu_write(dut, GPIO_OUT, 0xF0)
    dut.i_gpio_in.value = 0x0F
    for _ in range(4):
        await RisingEdge(dut.clk)
    await settle(dut)
    assert int(dut.o_gpio_out.value) == 0xF0, "out marad 0xF0"
    assert (await cpu_read(dut, GPIO_IN)) == 0x0F, "in = 0x0F"
