# hu: CLI-CPU F2.8 #6.5b-F1c.2 — cilcpu_soc autonóm flash-boot e2e teszt
#     (BOOT_AUTODETECT=1). A flash a CODE-bázison egy érvényes method-header-t
#     (magic 0xFE) + belépési IL-t tartalmaz. Reset után a boot_ctrl beolvassa a
#     header-t, érvényes magic → autonóm flash-boot (host/UART NÉLKÜL), a core
#     a flash-ből fetch-el (code_src=0) és lefuttatja a programot.
# en: CLI-CPU F2.8 #6.5b-F1c.2 — cilcpu_soc autonomous flash-boot e2e test
#     (BOOT_AUTODETECT=1). Flash holds a valid method header (magic 0xFE) + entry
#     IL at the CODE base. After reset the boot_ctrl reads the header, valid
#     magic → autonomous flash boot (NO host/UART), the core fetches from flash
#     (code_src=0) and runs the program.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from test_core import _ldc_i4, OP_RET
from tb_qspi import TQSPIFlashModel, qspi_flash_driver


def _init(dut):
    dut.i_gpio_in.value          = 0
    dut.i_host_inbox_wdata.value = 0
    dut.i_host_inbox_push.value  = 0
    dut.i_host_outbox_pop.value  = 0
    dut.i_uart_rx.value          = 1
    # hu: NINCS külső boot — az auto-detect indít
    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value       = 0
    dut.i_boot_arg_data.value    = 0
    dut.i_boot_arg_valid.value   = 0


@cocotb.test()
async def test_01_autoboot_from_flash(dut):
    """hu: A flash CODE-bázisán [header(magic 0xFE, argc=0, localc=0) + IL
        (LDC.I4 0x1234, RET)]. Reset után — host/UART/external-boot NÉLKÜL — a
        boot_ctrl auto-boot-ol, a core flash-ből futtatja → o_return_value=0x1234.
    en: At the flash CODE base [header(magic 0xFE, argc=0, localc=0) + IL
        (LDC.I4 0x1234, RET)]. After reset — with NO host/UART/external boot —
        the boot_ctrl auto-boots, the core runs from flash → return 0x1234."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init(dut)

    il = _ldc_i4(0x1234) + bytes([OP_RET])
    # hu: 8-bájtos method-header: [magic, argc, localc, max, csize_lo, csize_hi, 0, 0]
    header = [0xFE, 0x00, 0x00, 0x08, len(il) & 0xFF, (len(il) >> 8) & 0xFF, 0, 0]
    image = header + list(il)
    flash = TQSPIFlashModel(bytes(image))
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    dut.rst_n.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    halted = False
    for _ in range(4000):
        await RisingEdge(dut.clk)
        try:
            if int(dut.o_halt.value) == 1 or int(dut.o_trap.value) == 1:
                halted = True
                break
        except ValueError:
            pass

    assert halted, "autonóm flash-boot: a core nem haltolt/trap-elt"
    assert int(dut.o_trap.value) == 0, \
        f"trap 0x{int(dut.o_trap_code.value):02X} (header/boot_ctrl/fetch hiba?)"
    assert int(dut.o_return_value.value) == 0x1234, \
        f"return_value 0x{int(dut.o_return_value.value):08X}, várt 0x1234"


@cocotb.test()
async def test_02_blank_flash_no_autoboot(dut):
    """hu: Üres flash (0xFF) → a boot_ctrl NEM boot-ol; a core idle marad
        (nincs halt, nincs trap) — a rendszer a UART loaderre várna.
    en: Blank flash (0xFF) → the boot_ctrl does NOT boot; the core stays idle
        (no halt, no trap) — the system would wait for the UART loader."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _init(dut)

    flash = TQSPIFlashModel()    # üres → minden bájt 0xFF
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    dut.rst_n.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    booted = False
    for _ in range(800):
        await RisingEdge(dut.clk)
        try:
            if int(dut.o_halt.value) == 1 or int(dut.o_trap.value) == 1:
                booted = True
                break
        except ValueError:
            pass

    assert not booted, \
        "üres flash → nem szabadna auto-boot-olni (halt/trap történt)"
