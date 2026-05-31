# hu: CLI-CPU F2.8 #6.5a — cocotb tesztek a cilcpu_soc wrapperre. A wrapper a
#     core MMIO-master buszát dekódolja a mailbox/gpio/trace perifériákra
#     (architektúra B). Kézzel-bytecode programok (boot flash-ről) gyakorolják
#     a STIND→MMIO write és LDIND←MMIO read utakat, a fizikai periféria-pinek /
#     host-oldal megfigyelésével. A boot-harness a test_core-ból importált
#     (a soc boot/qspi/státusz portjai névazonosak a core-éval).
# en: CLI-CPU F2.8 #6.5a — cocotb tests for the cilcpu_soc wrapper. The wrapper
#     decodes the core's MMIO master bus to the mailbox/gpio/trace peripherals
#     (architecture B). Hand-bytecode programs (booted from flash) exercise the
#     STIND→MMIO write and LDIND←MMIO read paths, observing the physical
#     peripheral pins / host side. The boot harness is imported from test_core
#     (the soc's boot/qspi/status ports share the core's names).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from test_core import (
    boot_and_run, _ldc_i4, _ldc_s,
    OP_STIND_I4, OP_LDIND_I4, OP_RET, OP_POP,
)
from tb_uart import uart_tx_bytes
from test_qspi_controller import (
    TQSPIFlashModel, TQSPIPSRAMModel, qspi_slave_driver,
)

# hu: az e2e UART-load teszt baud-osztója (a Makefile -GUART_CLOCKS_PER_BAUD=8)
UART_CPB  = 8
CMD_WRITE = 0xC0
CMD_BOOT  = 0xB0
DEV_PSRAM = 0x01

# hu: MMIO-térkép — a wrapper dekódolja (addr[11:8]=periféria, addr[5:2]=reg).
# en: MMIO map — decoded by the wrapper (addr[11:8]=peripheral, addr[5:2]=reg).
IRQ_STATUS     = 0xF0000000   # aggregált IRQ-pending (RO): bit0 mailbox_in, bit1 mailbox_out
MAILBOX_INBOX  = 0xF0000100   # CPU read → pop inbox
MAILBOX_OUTBOX = 0xF0000104   # CPU write → push outbox
MAILBOX_STATUS = 0xF0000108
GPIO_IN        = 0xF0000200
GPIO_OUT       = 0xF0000204
GPIO_OE        = 0xF0000208
TRACE_CFG      = 0xF0000300


def _init_soc_inputs(dut):
    """hu: A soc-specifikus bemenetek alaphelyzetbe — a core boot-harness
        ezeket nem hajtja.
    en: Reset the soc-specific inputs — the core boot harness doesn't drive
        these."""
    dut.i_gpio_in.value          = 0
    dut.i_host_inbox_wdata.value = 0
    dut.i_host_inbox_push.value  = 0
    dut.i_host_outbox_pop.value  = 0
    dut.i_uart_rx.value          = 1   # hu: UART idle (nincs loader-aktivitás)


async def push_inbox_once(dut, value, after_cycles=8):
    """hu: A host egyetlen szót push-ol az inboxba, miután a reset feloldódott.
        A QSPI-fetch latencia miatt ez biztosan a program LDIND-je ELŐTT
        landol.
    en: Host pushes a single word into the inbox after reset deasserts. Due
        to QSPI fetch latency this lands safely BEFORE the program's LDIND."""
    while True:
        await RisingEdge(dut.clk)
        try:
            if int(dut.rst_n.value) == 1:
                break
        except ValueError:
            pass

    for _ in range(after_cycles):
        await RisingEdge(dut.clk)

    dut.i_host_inbox_wdata.value = value
    dut.i_host_inbox_push.value  = 1
    await RisingEdge(dut.clk)
    dut.i_host_inbox_push.value  = 0


# ============================================================
# GPIO
# ============================================================

@cocotb.test()
async def test_01_gpio_out_and_oe_write(dut):
    """hu: STIND a GPIO_OUT és GPIO_OE MMIO-címekre → a fizikai gpio pinek
        hajtva (o_gpio_out=42, o_gpio_oe=0xFF).
    en: STIND to GPIO_OUT and GPIO_OE → physical gpio pins driven."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)

    program = (_ldc_i4(GPIO_OUT) + _ldc_s(42)   + bytes([OP_STIND_I4])
               + _ldc_i4(GPIO_OE) + _ldc_i4(0xFF) + bytes([OP_STIND_I4])
               + _ldc_s(0) + bytes([OP_RET]))
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    await Timer(1, units="ns")
    assert int(dut.o_gpio_out.value) == 42, \
        f"o_gpio_out = {int(dut.o_gpio_out.value)}, várt 42"
    assert int(dut.o_gpio_oe.value) == 0xFF, \
        f"o_gpio_oe = 0x{int(dut.o_gpio_oe.value):02X}, várt 0xFF"


@cocotb.test()
async def test_02_gpio_in_read(dut):
    """hu: Külső gpio bemenet (0x5A) → LDIND a GPIO_IN-ről → visszaadja
        (2-FF szinkronizeren át).
    en: External gpio input (0x5A) → LDIND from GPIO_IN → returns it (through
        the 2-FF synchronizer)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    dut.i_gpio_in.value = 0x5A

    program = _ldc_i4(GPIO_IN) + bytes([OP_LDIND_I4, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 0x5A, f"GPIO_IN visszaolvasás = 0x{rv:02X}, várt 0x5A"


# ============================================================
# Mailbox
# ============================================================

@cocotb.test()
async def test_03_mailbox_outbox_write(dut):
    """hu: STIND a MAILBOX_OUTBOX-ra → a host az outboxból olvassa (nem üres,
        a fej a beírt érték).
    en: STIND to MAILBOX_OUTBOX → host reads it from the outbox (not empty,
        head = written value)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)

    program = (_ldc_i4(MAILBOX_OUTBOX) + _ldc_i4(0x0000CAFE)
               + bytes([OP_STIND_I4]) + _ldc_s(0) + bytes([OP_RET]))
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    await Timer(1, units="ns")
    assert int(dut.o_host_outbox_empty.value) == 0, \
        "outbox üres maradt a CPU write után"
    assert int(dut.o_host_outbox_rdata.value) == 0x0000CAFE, \
        f"outbox fej = 0x{int(dut.o_host_outbox_rdata.value):08X}, várt 0xCAFE"


@cocotb.test()
async def test_04_mailbox_inbox_read(dut):
    """hu: A host push-ol egy szót (0x12345678) az inboxba, majd a program
        LDIND-del olvassa a MAILBOX_INBOX-ról → visszaadja.
    en: Host pushes a word (0x12345678) into the inbox, the program LDINDs
        from MAILBOX_INBOX → returns it."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    cocotb.start_soon(push_inbox_once(dut, 0x12345678))

    program = _ldc_i4(MAILBOX_INBOX) + bytes([OP_LDIND_I4, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 0x12345678, \
        f"inbox olvasás = 0x{rv:08X}, várt 0x12345678"


# ============================================================
# Trace — a dekódolás bizonyítéka (STIND CFG + LDIND CFG readback)
# ============================================================

@cocotb.test()
async def test_05_trace_cfg_write_readback(dut):
    """hu: STIND a TRACE_CFG-be (sel=3), majd LDIND a TRACE_CFG-ből → a
        readback sel-mezője 3. Bizonyítja, hogy a STIND→trace és LDIND←trace
        is helyesen routolódik a buszon.
    en: STIND TRACE_CFG (sel=3), then LDIND TRACE_CFG → readback sel field is
        3. Proves both STIND→trace and LDIND←trace route correctly."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)

    program = (_ldc_i4(TRACE_CFG) + _ldc_s(3) + bytes([OP_STIND_I4])
               + _ldc_i4(TRACE_CFG) + bytes([OP_LDIND_I4, OP_RET]))
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert (rv & 0x7) == 3, \
        f"trace CFG readback sel = {rv & 0x7}, várt 3 (teljes rv=0x{rv:08X})"


# ============================================================
# IRQ — aggregált IRQ-pending MMIO regiszter (0xF000_0000) + SoC o_irq pin
# ============================================================

@cocotb.test()
async def test_06_irq_pending_after_inbox_push(dut):
    """hu: A host push-ol az inboxba, majd a program LDIND-del olvassa az
        IRQ_STATUS regisztert → bit0 (mailbox_in) be van állítva. A SoC
        aggregált o_irq pin is magas (mail a CPU-nak).
    en: Host pushes into the inbox, the program LDINDs the IRQ_STATUS
        register → bit0 (mailbox_in) set. The aggregate SoC o_irq pin is
        high too (mail for the CPU)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    cocotb.start_soon(push_inbox_once(dut, 0x000000AA))

    program = _ldc_i4(IRQ_STATUS) + bytes([OP_LDIND_I4, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert (rv & 0x1) == 1, \
        f"IRQ_STATUS bit0 (mailbox_in) = {rv & 0x1}, várt 1 (push után)"
    await Timer(1, units="ns")
    assert int(dut.o_irq.value) == 1, \
        "aggregált o_irq pin alacsony, holott van olvasatlan mail"


@cocotb.test()
async def test_07_irq_clears_after_inbox_read(dut):
    """hu: Push után a program kiolvassa (popolja) az inboxot, majd az
        IRQ_STATUS-t olvassa → bit0 már 0 (az inbox üres). A SoC o_irq pin
        is alacsony.
    en: After the push, the program reads (pops) the inbox, then reads
        IRQ_STATUS → bit0 is now 0 (inbox empty). The SoC o_irq pin is low
        too."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    cocotb.start_soon(push_inbox_once(dut, 0x000000BB))

    program = (_ldc_i4(MAILBOX_INBOX) + bytes([OP_LDIND_I4, OP_POP])
               + _ldc_i4(IRQ_STATUS) + bytes([OP_LDIND_I4, OP_RET]))
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert (rv & 0x1) == 0, \
        f"IRQ_STATUS bit0 = {rv & 0x1}, várt 0 (inbox-olvasás után törlődik)"
    await Timer(1, units="ns")
    assert int(dut.o_irq.value) == 0, \
        "aggregált o_irq pin magas, holott az inbox már üres"


# ============================================================
# F1b.2 — End-to-end: UART-load .t0 PSRAM-ba → BOOT → futás
# ============================================================

def _u16_be(v):
    return [(v >> 8) & 0xFF, v & 0xFF]


def _u24_be(v):
    return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]


@cocotb.test()
async def test_08_uart_load_psram_and_run(dut):
    """hu: A host UART-on betölt egy kis .t0 programot PSRAM-ba (WRITE keret),
        majd BOOT keret (code_src=1) elindítja → a core PSRAM-ból fetch-el,
        lefuttatja, és visszaadja az eredményt (0x1234). Ez bizonyítja a teljes
        boot-over-UART utat: uart_rx → loader → fázis-MUX → QSPI PSRAM-írás →
        boot-mux → core PSRAM-fetch (code_src remap).
    en: The host UART-loads a small .t0 program into PSRAM (WRITE frame), then a
        BOOT frame (code_src=1) starts it → the core fetches from PSRAM, runs it,
        and returns 0x1234. Proves the full boot-over-UART path."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value       = 0
    dut.i_boot_arg_data.value    = 0
    dut.i_boot_arg_valid.value   = 0

    # hu: QSPI slave (flash üres, PSRAM read-write)
    flash = TQSPIFlashModel()
    psram = TQSPIPSRAMModel()
    cocotb.start_soon(qspi_slave_driver(dut, flash, psram))

    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    # hu: program — LDC.I4 0x1234, RET; 8 bájtra paddolva (4 többszöröse)
    program = _ldc_i4(0x1234) + bytes([OP_RET])
    while len(program) % 4 != 0:
        program += bytes([0x00])
    plen = len(program)

    write_frame = ([CMD_WRITE, DEV_PSRAM] + _u24_be(0x00000) + _u16_be(plen)
                   + list(program))
    boot_frame  = [CMD_BOOT, 0x01] + _u24_be(0x000000) + [0x00, 0x00]

    await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, write_frame)
    for _ in range(40):
        await RisingEdge(dut.clk)
    await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, boot_frame)

    halted = False
    for _ in range(4000):
        await RisingEdge(dut.clk)
        try:
            if int(dut.o_halt.value) == 1 or int(dut.o_trap.value) == 1:
                halted = True
                break
        except ValueError:
            pass

    assert halted, "a core nem haltolt/trap-elt a UART-load+boot után"
    assert int(dut.o_trap.value) == 0, \
        f"trap 0x{int(dut.o_trap_code.value):02X} (PSRAM-fetch / byte-order hiba?)"
    assert int(dut.o_return_value.value) == 0x1234, \
        f"return_value 0x{int(dut.o_return_value.value):08X}, várt 0x1234"
