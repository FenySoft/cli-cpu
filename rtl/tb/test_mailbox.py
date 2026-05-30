# hu: CLI-CPU F2.8.3 — Mailbox (cilcpu_mailbox) cocotb tesztjei. Két 8-mély
#     FIFO (inbox: host→CPU, outbox: CPU→host) + MMIO slave interfész + IRQ.
#     A CPU MMIO-n keresztül olvas az inboxból (registered read, 1-ciklus
#     latencia, olvasás popol) és ír az outboxba (write push-ol). A host a
#     másik oldalt hajtja. IRQ: o_irq_in = inbox nem üres, o_irq_out = outbox
#     nem üres. Ez a CFPU üzenet-primitív — a Symphact host↔chip protokoll
#     alapja.
# en: CLI-CPU F2.8.3 — cocotb tests for the Mailbox (cilcpu_mailbox). Two
#     8-deep FIFOs (inbox: host→CPU, outbox: CPU→host) + MMIO slave + IRQ.
#     The CPU reads the inbox via MMIO (registered read, 1-cycle latency,
#     read pops) and writes the outbox (write pushes). The host drives the
#     other side. IRQ: o_irq_in = inbox not empty, o_irq_out = outbox not
#     empty. The CFPU message primitive — basis of the Symphact host↔chip
#     protocol.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# hu: MMIO szó-offszetek / en: MMIO word offsets
INBOX_DATA  = 0   # CPU read → pop inbox
OUTBOX_DATA = 1   # CPU write → push outbox
STATUS      = 2   # CPU read → flags

# STATUS bitek
ST_INBOX_EMPTY  = 1 << 0
ST_INBOX_FULL   = 1 << 1
ST_OUTBOX_EMPTY = 1 << 2
ST_OUTBOX_FULL  = 1 << 3


async def settle(dut):
    await Timer(1, units="ns")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_cpu_addr.value = 0
    dut.i_cpu_wdata.value = 0
    dut.i_cpu_we.value = 0
    dut.i_cpu_re.value = 0
    dut.i_host_inbox_wdata.value = 0
    dut.i_host_inbox_push.value = 0
    dut.i_host_outbox_pop.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await settle(dut)


# ---- CPU oldal (MMIO) ----

async def cpu_write(dut, addr, data):
    dut.i_cpu_addr.value = addr
    dut.i_cpu_wdata.value = data & 0xFFFFFFFF
    dut.i_cpu_we.value = 1
    await RisingEdge(dut.clk)
    dut.i_cpu_we.value = 0
    dut.i_cpu_wdata.value = 0
    await settle(dut)


async def cpu_read(dut, addr):
    # hu: registered read — re él, az adat a következő ciklusban érvényes
    dut.i_cpu_addr.value = addr
    dut.i_cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.i_cpu_re.value = 0
    await settle(dut)
    return int(dut.o_cpu_rdata.value)


# ---- Host oldal ----

async def host_push_inbox(dut, data):
    dut.i_host_inbox_wdata.value = data & 0xFFFFFFFF
    dut.i_host_inbox_push.value = 1
    await RisingEdge(dut.clk)
    dut.i_host_inbox_push.value = 0
    dut.i_host_inbox_wdata.value = 0
    await settle(dut)


async def host_pop_outbox(dut):
    val = int(dut.o_host_outbox_rdata.value)
    dut.i_host_outbox_pop.value = 1
    await RisingEdge(dut.clk)
    dut.i_host_outbox_pop.value = 0
    await settle(dut)
    return val


# ============================================================
# Outbox: CPU ír → host olvas (FIFO sorrend)
# ============================================================

@cocotb.test()
async def test_outbox_cpu_to_host(dut):
    await reset_dut(dut)
    vals = [0x1111, 0x2222, 0x3333]
    for v in vals:
        await cpu_write(dut, OUTBOX_DATA, v)
    assert int(dut.o_host_outbox_empty.value) == 0, "outbox nem empty"
    for exp in vals:
        got = await host_pop_outbox(dut)
        assert got == exp, f"outbox FIFO: {got:#x} != {exp:#x}"
    assert int(dut.o_host_outbox_empty.value) == 1, "ürítés után empty"


# ============================================================
# Inbox: host ír → CPU olvas (FIFO sorrend)
# ============================================================

@cocotb.test()
async def test_inbox_host_to_cpu(dut):
    await reset_dut(dut)
    vals = [0xAAAA, 0xBBBB, 0xCCCC]
    for v in vals:
        await host_push_inbox(dut, v)
    for exp in vals:
        got = await cpu_read(dut, INBOX_DATA)
        assert got == exp, f"inbox FIFO: {got:#x} != {exp:#x}"


# ============================================================
# STATUS flag-ek
# ============================================================

@cocotb.test()
async def test_status_flags(dut):
    await reset_dut(dut)
    s = await cpu_read(dut, STATUS)
    assert s & ST_INBOX_EMPTY, "reset: inbox empty"
    assert s & ST_OUTBOX_EMPTY, "reset: outbox empty"
    assert not (s & ST_OUTBOX_FULL), "reset: outbox nem full"

    # outbox feltöltése full-ig (8)
    for i in range(8):
        await cpu_write(dut, OUTBOX_DATA, 0x10 + i)
    s = await cpu_read(dut, STATUS)
    assert s & ST_OUTBOX_FULL, "8 write után outbox full"
    assert not (s & ST_OUTBOX_EMPTY), "full → nem empty"


# ============================================================
# IRQ jelzések
# ============================================================

@cocotb.test()
async def test_irq_out(dut):
    await reset_dut(dut)
    assert int(dut.o_irq_out.value) == 0, "reset: irq_out 0"
    await cpu_write(dut, OUTBOX_DATA, 0x99)
    assert int(dut.o_irq_out.value) == 1, "outbox push → irq_out 1"
    await host_pop_outbox(dut)
    assert int(dut.o_irq_out.value) == 0, "outbox ürül → irq_out 0"


@cocotb.test()
async def test_irq_in(dut):
    await reset_dut(dut)
    assert int(dut.o_irq_in.value) == 0, "reset: irq_in 0"
    await host_push_inbox(dut, 0x77)
    assert int(dut.o_irq_in.value) == 1, "inbox push → irq_in 1"
    await cpu_read(dut, INBOX_DATA)
    assert int(dut.o_irq_in.value) == 0, "inbox ürül → irq_in 0"


# ============================================================
# Full védelem (outbox overflow nincs)
# ============================================================

@cocotb.test()
async def test_outbox_full_no_overflow(dut):
    await reset_dut(dut)
    for i in range(8):
        await cpu_write(dut, OUTBOX_DATA, 0x20 + i)
    # 9. write full-ben → eldobva, a sorrend sértetlen
    await cpu_write(dut, OUTBOX_DATA, 0xDEAD)
    for i in range(8):
        got = await host_pop_outbox(dut)
        assert got == 0x20 + i, f"full-overflow védelem: {got:#x} != {0x20+i:#x}"
