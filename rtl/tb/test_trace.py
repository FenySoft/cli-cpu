# hu: CLI-CPU F2.8.5 — Trace MUX (cilcpu_trace) cocotb tesztjei.
#     Konfigurálható MUX: a CFG regiszter (MMIO 0xF000_0300) kiválasztja,
#     melyik belső jelcsoport (PC, FSM-állapot, stack-mélység, ALU-eredmény,
#     mailbox-állapot…) jelenjen meg a trace kimeneti pineken. A mode-bit
#     jelzi a wrappernek, hogy a trace-t mux-olja a GPIO fölé. Ciklus-pontos
#     belső megfigyelés logikai analizátorral — a „következtetések" cél fő
#     eszköze.
# en: CLI-CPU F2.8.5 — cocotb tests for the Trace MUX (cilcpu_trace).
#     Configurable MUX: the CFG register (MMIO 0xF000_0300) selects which
#     internal signal group (PC, FSM state, stack depth, ALU result, mailbox
#     state…) appears on the trace output pins. The mode bit tells the
#     wrapper to mux trace over GPIO. Cycle-accurate internal observability
#     with a logic analyzer — the main tool for the "draw conclusions" goal.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CFG = 0
MODE_BIT = 1 << 8
WIDTH = 8
NSRC = 8


async def settle(dut):
    await Timer(1, units="ns")


def pack_sources():
    """hu: NSRC csoport, k. csoport = 0x10+k a k*WIDTH ofszeten."""
    v = 0
    for k in range(NSRC):
        v |= ((0x10 + k) & 0xFF) << (k * WIDTH)
    return v


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_cpu_addr.value = 0
    dut.i_cpu_wdata.value = 0
    dut.i_cpu_we.value = 0
    dut.i_cpu_re.value = 0
    dut.i_sources.value = pack_sources()
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
    await settle(dut)


async def cpu_read(dut, addr):
    dut.i_cpu_addr.value = addr
    dut.i_cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.i_cpu_re.value = 0
    await settle(dut)
    return int(dut.o_cpu_rdata.value)


# ============================================================
# Forrás-kiválasztás / source select
# ============================================================

@cocotb.test()
async def test_reset_select_zero(dut):
    await reset_dut(dut)
    # reset után sel=0 → 0. csoport (0x10)
    assert int(dut.o_trace.value) == 0x10, f"reset sel=0 → 0x10, got {int(dut.o_trace.value):#x}"
    assert int(dut.o_trace_mode.value) == 0, "reset: mode 0"


@cocotb.test()
async def test_select_each_source(dut):
    await reset_dut(dut)
    for sel in range(NSRC):
        await cpu_write(dut, CFG, sel)
        exp = 0x10 + sel
        assert int(dut.o_trace.value) == exp, \
            f"sel={sel} → {exp:#x}, got {int(dut.o_trace.value):#x}"


# ============================================================
# Mode bit
# ============================================================

@cocotb.test()
async def test_mode_bit(dut):
    await reset_dut(dut)
    await cpu_write(dut, CFG, MODE_BIT | 3)   # mode + sel=3
    assert int(dut.o_trace_mode.value) == 1, "mode_en → trace_mode 1"
    assert int(dut.o_trace.value) == 0x13, "sel=3 → 0x13"
    await cpu_write(dut, CFG, 2)              # mode ki, sel=2
    assert int(dut.o_trace_mode.value) == 0, "mode ki → 0"
    assert int(dut.o_trace.value) == 0x12, "sel=2 → 0x12"


# ============================================================
# CFG readback
# ============================================================

@cocotb.test()
async def test_cfg_readback(dut):
    await reset_dut(dut)
    await cpu_write(dut, CFG, MODE_BIT | 5)
    rb = await cpu_read(dut, CFG)
    assert (rb & 0x7) == 5, f"sel readback 5, got {rb & 0x7}"
    assert (rb & MODE_BIT) != 0, "mode readback"
