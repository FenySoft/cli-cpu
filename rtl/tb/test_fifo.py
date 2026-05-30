# hu: CLI-CPU F2.8.3a — generikus szinkron FIFO (cilcpu_fifo) cocotb
#     tesztjei. Körkörös puffer, paraméterezhető WIDTH/DEPTH. A Mailbox
#     (inbox + outbox) és potenciálisan a UART-loader építőeleme. A teszt a
#     viselkedési szerződést rögzíti: FIFO-sorrend, full/empty/count flag-ek,
#     egyidejű push+pop, wrap-around.
# en: CLI-CPU F2.8.3a — cocotb tests for the generic synchronous FIFO
#     (cilcpu_fifo). Circular buffer, parameterizable WIDTH/DEPTH. Building
#     block of the Mailbox (inbox + outbox) and potentially the UART loader.
#     Pins the behavioral contract: FIFO order, full/empty/count flags,
#     simultaneous push+pop, wrap-around.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

DEPTH = 8


async def settle(dut):
    # hu: kis késleltetés az él után, hogy a kombinációs kimenetek
    #     (o_count/o_empty/o_full/o_rdata) beálljanak a regiszter-frissítés
    #     utáni delta-ciklusban — robusztus olvasáshoz.
    await Timer(1, units="ns")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_wdata.value = 0
    dut.i_push.value = 0
    dut.i_pop.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await settle(dut)


async def push(dut, val):
    dut.i_wdata.value = val & 0xFFFFFFFF
    dut.i_push.value = 1
    await RisingEdge(dut.clk)
    dut.i_push.value = 0
    dut.i_wdata.value = 0
    await settle(dut)


async def pop(dut):
    # hu: o_rdata kombinációs (head); pop az élnél fogyaszt
    val = int(dut.o_rdata.value)
    dut.i_pop.value = 1
    await RisingEdge(dut.clk)
    dut.i_pop.value = 0
    await settle(dut)
    return val


# ============================================================
# Alap push/pop + FIFO sorrend
# ============================================================

@cocotb.test()
async def test_empty_after_reset(dut):
    await reset_dut(dut)
    assert int(dut.o_empty.value) == 1, "reset után empty"
    assert int(dut.o_full.value) == 0, "reset után nem full"
    assert int(dut.o_count.value) == 0, "reset után count=0"


@cocotb.test()
async def test_single_push_pop(dut):
    await reset_dut(dut)
    await push(dut, 0xDEADBEEF)
    assert int(dut.o_empty.value) == 0, "push után nem empty"
    assert int(dut.o_count.value) == 1, "count=1"
    assert int(dut.o_rdata.value) == 0xDEADBEEF, "head = pushed"
    v = await pop(dut)
    assert v == 0xDEADBEEF, f"pop {v:#x} != 0xDEADBEEF"
    assert int(dut.o_empty.value) == 1, "pop után empty"


@cocotb.test()
async def test_fifo_order(dut):
    await reset_dut(dut)
    vals = [0x11, 0x22, 0x33, 0x44]
    for v in vals:
        await push(dut, v)
    assert int(dut.o_count.value) == 4, "count=4"
    for exp in vals:
        got = await pop(dut)
        assert got == exp, f"FIFO sorrend: {got:#x} != {exp:#x}"


# ============================================================
# Full / empty határ
# ============================================================

@cocotb.test()
async def test_fill_to_full(dut):
    await reset_dut(dut)
    for i in range(DEPTH):
        await push(dut, 0x100 + i)
    assert int(dut.o_full.value) == 1, f"{DEPTH} push után full"
    assert int(dut.o_count.value) == DEPTH, f"count={DEPTH}"
    # full-ben a push-t a FIFO figyelmen kívül hagyja (nincs overflow)
    await push(dut, 0xBAD)
    assert int(dut.o_count.value) == DEPTH, "full push nem növel"
    # ürítés sorrendben
    for i in range(DEPTH):
        got = await pop(dut)
        assert got == 0x100 + i, f"full-drain sorrend: {got:#x} != {0x100+i:#x}"
    assert int(dut.o_empty.value) == 1, "drain után empty"


@cocotb.test()
async def test_pop_empty_safe(dut):
    await reset_dut(dut)
    # empty pop nem ronthatja el az állapotot
    dut.i_pop.value = 1
    await RisingEdge(dut.clk)
    dut.i_pop.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.o_empty.value) == 1, "empty pop után is empty"
    assert int(dut.o_count.value) == 0, "count marad 0"


# ============================================================
# Egyidejű push+pop + wrap-around
# ============================================================

@cocotb.test()
async def test_simultaneous_push_pop(dut):
    await reset_dut(dut)
    await push(dut, 0xA1)
    await push(dut, 0xA2)
    # egyszerre push + pop: count változatlan, head fogy, új a végére
    dut.i_wdata.value = 0xA3
    dut.i_push.value = 1
    dut.i_pop.value = 1
    head = int(dut.o_rdata.value)
    await RisingEdge(dut.clk)
    dut.i_push.value = 0
    dut.i_pop.value = 0
    dut.i_wdata.value = 0
    await settle(dut)
    assert head == 0xA1, f"egyidejű: head {head:#x} != 0xA1"
    assert int(dut.o_count.value) == 2, "egyidejű push+pop: count változatlan"
    assert (await pop(dut)) == 0xA2, "maradék sorrend 1"
    assert (await pop(dut)) == 0xA3, "maradék sorrend 2"


@cocotb.test()
async def test_wraparound(dut):
    await reset_dut(dut)
    # rd/wr pointer körbefordítás: tölts félig, üríts, tölts újra
    for i in range(6):
        await push(dut, 0x200 + i)
    for i in range(6):
        assert (await pop(dut)) == 0x200 + i, "1. kör"
    for i in range(DEPTH):
        await push(dut, 0x300 + i)
    assert int(dut.o_full.value) == 1, "wrap után full"
    for i in range(DEPTH):
        assert (await pop(dut)) == 0x300 + i, "wrap-kör sorrend"
