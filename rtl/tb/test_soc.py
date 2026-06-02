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
DEV_FLASH = 0x00
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
    # hu: F3 boot-mód strap — H (mód B): a loader QSPI-ra ír, boot-kor a
    #     copy-engine QSPI→on-chip SRAM-ba másol (ezek a tesztek QSPI-n töltenek).
    # en: F3 boot-mode strap — H (mode B): loader writes QSPI, copy engine copies
    #     QSPI→on-chip SRAM at boot (these tests load via QSPI).
    dut.i_boot_mode.value        = 1


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


@cocotb.test()
async def test_09_uart_load_flash_and_run(dut):
    """hu: F2 — perzisztens dev=flash betöltés. A host UART-on betölt egy kis
        .t0 programot a FLASH-be (WRITE keret, dev=0), ami a QSPI controller
        F2 erase+program szekvenciáját gyakorolja (WREN→sector-erase→WIP-poll→
        WREN→page-program→WIP-poll). Ezután BOOT keret (code_src=0) elindítja →
        a core FLASH-ből fetch-el, lefuttatja, és visszaadja az eredményt
        (0x0ACE). Ez a teljes dev=flash út: uart_rx → loader → fázis-MUX →
        QSPI flash erase+program → boot-mux → core flash-fetch.
    en: F2 — persistent dev=flash loading. The host UART-loads a small .t0
        program into FLASH (WRITE frame, dev=0), exercising the QSPI controller's
        F2 erase+program sequence. A BOOT frame (code_src=0) then starts it → the
        core fetches from flash, runs, and returns 0x0ACE. Full dev=flash path:
        uart_rx → loader → phase MUX → QSPI flash erase+program → boot-mux →
        core flash-fetch."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value       = 0
    dut.i_boot_arg_data.value    = 0
    dut.i_boot_arg_valid.value   = 0

    # hu: QSPI slave — a flash most read-write (F2 erase+program)
    # en: QSPI slave — flash is now read-write (F2 erase+program)
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

    # hu: program — LDC.I4 0x0ACE, RET; 4-szeresre paddolva
    program = _ldc_i4(0x0ACE) + bytes([OP_RET])
    while len(program) % 4 != 0:
        program += bytes([0x00])
    plen = len(program)

    n_words = plen // 4
    header = [CMD_WRITE, DEV_FLASH] + _u24_be(0x00000) + _u16_be(plen)
    boot_frame = [CMD_BOOT, 0x00] + _u24_be(0x000000) + [0x00, 0x00]

    # hu: A WRITE fejléc nem indít flash-írást → fast stream.
    # en: The WRITE header triggers no flash write → fast stream.
    await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, header)

    # hu: Throttle-öző host: a flash erase+program szavanként SOK ciklus (valós
    #     HW-en a sector erase ~45 ms ≫ egy UART byte ~434 ciklus @ 115200),
    #     ezért a host szavanként küld, és megvárja az adott szó kiírását,
    #     mielőtt a következő szó bájtjait küldi. Buffer-mentes loader esetén ez
    #     KÖTELEZŐ — különben a flash-írás közben érkező bájtok elvesznének.
    # en: Throttling host: flash erase+program is MANY cycles per word (on real
    #     HW the sector erase ~45 ms ≫ one UART byte ~434 cycles @ 115200), so
    #     the host sends word by word and waits for each word to be written
    #     before sending the next word's bytes. With a buffer-less loader this
    #     is REQUIRED — otherwise bytes arriving mid-write would be lost.
    for wi in range(n_words):
        word_bytes = list(program[wi * 4:(wi + 1) * 4])
        await uart_tx_bytes(dut, dut.i_uart_rx, UART_CPB, word_bytes)
        written = False
        for _ in range(8000):
            await RisingEdge(dut.clk)
            if flash.program_count >= wi + 1:
                written = True
                break
        assert written, f"a(z) {wi}. szó flash-írása nem fejeződött be időben"
        # hu: a program_count az írás KÖZBEN (PROGRAM tranzakció) nő; megvárjuk a
        #     WIP-poll farkát + cpu_ready-t + a loader S_WWAIT→S_WDATA léptetését,
        #     mielőtt a következő szó bájtjait küldjük (különben elvesznének).
        # en: program_count rises DURING the write (PROGRAM transaction); wait for
        #     the WIP-poll tail + cpu_ready + the loader's S_WWAIT→S_WDATA advance
        #     before sending the next word's bytes (else they'd be lost).
        for _ in range(400):
            await RisingEdge(dut.clk)

    # hu: a program tényleg a flash-be került (perzisztens betöltés bizonyítéka)
    # en: the program actually landed in flash (proof of persistent loading)
    assert flash.program_count == n_words, \
        f"a loader nem írta ki mind a {n_words} szót (program_count={flash.program_count})"
    assert flash.erase_count == 1, \
        f"egy szektoron belül pontosan 1 erase várt (erase_count={flash.erase_count})"

    # hu: néhány ciklus, hogy a loader teljesen IDLE-be (r_load_mode=0) kerüljön
    # en: a few cycles so the loader fully returns to IDLE (r_load_mode=0)
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

    assert halted, "a core nem haltolt/trap-elt a UART-flash-load+boot után"
    assert int(dut.o_trap.value) == 0, \
        f"trap 0x{int(dut.o_trap_code.value):02X} (flash-fetch / byte-order hiba?)"
    assert int(dut.o_return_value.value) == 0x0ACE, \
        f"return_value 0x{int(dut.o_return_value.value):08X}, várt 0x0ACE"


# ============================================================
# F3 — Mód A: UART → on-chip SRAM DIREKT (i_boot_mode=0), QSPI tétlen
# ============================================================

@cocotb.test()
async def test_10_mode_a_uart_to_sram_direct(dut):
    """hu: Mód A (i_boot_mode=0): a host UART-on betölt egy kis programot, amit a
        loader KÖZVETLENÜL az on-chip SRAM-ba ír (nem a QSPI-re), majd BOOT →
        a core on-chipről fut, eredmény 0x1234. Invariáns: a QSPI busz VÉGIG
        tétlen (cs_flash_n és cs_psram_n magas) — sem betöltés, sem fetch.
    en: Mode A (i_boot_mode=0): the host UART-loads a small program that the
        loader writes DIRECTLY into the on-chip SRAM (not QSPI), then BOOT → the
        core runs on-chip, result 0x1234. Invariant: the QSPI bus stays idle
        throughout (cs_flash_n and cs_psram_n high) — neither load nor fetch."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init_soc_inputs(dut)
    dut.i_boot_mode.value        = 0   # hu: mód A — direkt UART→SRAM
    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value       = 0
    dut.i_boot_arg_data.value    = 0
    dut.i_boot_arg_valid.value   = 0

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

    program = _ldc_i4(0x1234) + bytes([OP_RET])
    while len(program) % 4 != 0:
        program += bytes([0x00])
    plen = len(program)

    # hu: a dev-bájt mód A-ban közömbös (a loader az on-chip SRAM-ba ír)
    write_frame = ([CMD_WRITE, DEV_PSRAM] + _u24_be(0x00000) + _u16_be(plen)
                   + list(program))
    boot_frame  = [CMD_BOOT, 0x00] + _u24_be(0x000000) + [0x00, 0x00]

    # hu: QSPI-tétlen monitor — ha bármelyik CS leesik, mód A sérül
    qspi_active = False

    async def _qspi_idle_monitor():
        nonlocal qspi_active
        while True:
            await RisingEdge(dut.clk)
            try:
                if int(dut.qspi_cs_flash_n.value) == 0 or \
                   int(dut.qspi_cs_psram_n.value) == 0:
                    qspi_active = True
            except ValueError:
                pass

    cocotb.start_soon(_qspi_idle_monitor())

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

    assert halted, "a core nem haltolt/trap-elt a mód-A UART-load+boot után"
    assert int(dut.o_trap.value) == 0, \
        f"trap 0x{int(dut.o_trap_code.value):02X} (mód-A direkt SRAM hiba?)"
    assert int(dut.o_return_value.value) == 0x1234, \
        f"return_value 0x{int(dut.o_return_value.value):08X}, várt 0x1234"
    assert not qspi_active, \
        "a QSPI busz aktiválódott mód A-ban (a betöltésnek/fetch-nek on-chip kellene lennie)"
