# hu: CLI-CPU F2.7 Sub5 — QSPI Controller QE-init sequence verifikáció.
#     A `QE_INIT_ENABLE=1` paraméterrel a controller reset után WREN (0x06)
#     és WRSR (0x01) + 0x40 SPI sequence-t küld a flash-nek (a Status
#     Register QE bitjének perzisztens beállításához), mielőtt CPU-kérést
#     fogadna. HW-en KÖTELEZŐ: a board MODE pinjei nem SPIx4 boot-ra
#     vannak konfigurálva, így az FPGA startup ROM nem állítja be a QE-t
#     → a core 0x6B Quad Output Read parancsa garbage-t kapna.
# en: CLI-CPU F2.7 Sub5 — QSPI Controller QE-init sequence verification.
#     With `QE_INIT_ENABLE=1`, the controller emits WREN (0x06) and WRSR
#     (0x01) + 0x40 SPI sequence to the flash after reset (to persistently
#     set the Status Register QE bit), before accepting CPU requests.
#     REQUIRED on real HW: the board's MODE pins are not configured for
#     SPIx4 boot, so the FPGA startup ROM does not set QE → the core's
#     0x6B Quad Output Read would return garbage.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_qspi import TQSPIFlashModel, qspi_flash_driver


async def reset_dut(dut):
    """hu: Standard reset + clock indítás.
    en: Standard reset + clock start."""
    cocotb.start_soon(Clock(dut.clk, 20, units='ns').start())
    dut.cpu_re.value = 0
    dut.cpu_we.value = 0
    dut.cpu_addr.value = 0
    dut.cpu_wdata.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def capture_cmds(dut, cmds, max_cmds=4, timeout_cycles=200):
    """hu: A flash bus-on érkező SPI CMD-ket gyűjti egy listába.
        Minden CS# low → 8 bit beolvasás (DQ[0] rising-edge mintán) → cmd
        a listához, várjuk CS# magas.
    en: Collects SPI CMD bytes seen on the flash bus into a list. On each
        CS# low edge, samples 8 bits (DQ[0] on rising edge) → cmd to list,
        then waits for CS# high."""
    cycles = 0
    while len(cmds) < max_cmds and cycles < timeout_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        try:
            cs = int(dut.qspi_cs_flash_n.value)
        except ValueError:
            continue
        if cs != 0:
            continue

        # hu: CS# alacsony — 8 bit CMD olvasás a qspi_clk rising edge-eken
        # en: CS# low — read 8 bits CMD on qspi_clk rising edges
        cmd = 0
        for _ in range(8):
            await RisingEdge(dut.qspi_clk)
            bit = int(dut.qspi_dq_out.value) & 0x01
            cmd = (cmd << 1) | bit
        cmds.append(cmd)

        # hu: Várjuk CS# magasra (közben CMD-utáni adatfázisok futnak)
        # en: Wait for CS# high (data phases may run in the meantime)
        while int(dut.qspi_cs_flash_n.value) == 0:
            await RisingEdge(dut.clk)


@cocotb.test()
async def test_qe_init_sequence_appears_after_reset(dut):
    """hu: Reset után CS#/CLK/DQ-n megjelenik a WREN (0x06) és WRSR (0x01).
    en: After reset, WREN (0x06) and WRSR (0x01) appear on CS#/CLK/DQ."""
    flash = TQSPIFlashModel([0xDE, 0xAD, 0xBE, 0xEF])
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    cmds = []
    cmd_capture = cocotb.start_soon(capture_cmds(dut, cmds, max_cmds=2))

    await reset_dut(dut)
    await cmd_capture

    assert len(cmds) >= 2, f"Várt legalább 2 CMD a bus-on, kapott: {cmds}"
    assert cmds[0] == 0x06, f"Első CMD WREN (0x06) várt, kapott: 0x{cmds[0]:02X}"
    assert cmds[1] == 0x01, f"Második CMD WRSR (0x01) várt, kapott: 0x{cmds[1]:02X}"


@cocotb.test()
async def test_normal_read_works_after_qe_init(dut):
    """hu: A QE-init után normál SEG_CODE flash read működik.
    en: After QE-init, a normal SEG_CODE flash read works."""
    flash = TQSPIFlashModel([0xDE, 0xAD, 0xBE, 0xEF])
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    await reset_dut(dut)

    # hu: Várjuk meg, hogy az init lefusson (cpu_busy 0-ra esik)
    # en: Wait for init to complete (cpu_busy goes low)
    init_done_at = None
    for cycle in range(200):
        await RisingEdge(dut.clk)
        if int(dut.cpu_busy.value) == 0:
            init_done_at = cycle
            break
    assert init_done_at is not None, "QE-init nem fejeződött be 200 ciklus alatt"

    # hu: A CPU kéri a CODE szegmens 0. szavát
    # en: CPU requests word 0 of CODE segment
    dut.cpu_addr.value = 0  # SEG_CODE = 0, offset = 0
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)

    # hu: Várjuk cpu_ready-t
    # en: Wait for cpu_ready
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.cpu_ready.value) == 1:
            break
    else:
        assert False, "cpu_ready nem érkezett 200 ciklus alatt"

    dut.cpu_re.value = 0

    expected = (0xDE << 24) | (0xAD << 16) | (0xBE << 8) | 0xEF
    actual = int(dut.cpu_rdata.value)
    assert actual == expected, \
        f"Olvasás hiba: várt 0x{expected:08X}, kapott 0x{actual:08X}"


@cocotb.test()
async def test_cpu_request_during_init_is_held(dut):
    """hu: Init közben kiadott cpu_re nem hajtódik végre azonnal;
        a controller csak az init befejezése után kezdi feldolgozni.
    en: A cpu_re asserted during init is not handled immediately; the
        controller processes it only after init completes."""
    flash = TQSPIFlashModel([0xCA, 0xFE, 0xBA, 0xBE])
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    await reset_dut(dut)

    # hu: Azonnal kiadunk egy CPU read kérést — még az init alatt
    # en: Issue a CPU read request immediately — still during init
    dut.cpu_addr.value = 0
    dut.cpu_re.value = 1

    # hu: Várjuk cpu_ready-t — az init+read után érkezik
    # en: Wait for cpu_ready — arrives after init+read
    ready_at = None
    for cycle in range(400):
        await RisingEdge(dut.clk)
        if int(dut.cpu_ready.value) == 1:
            ready_at = cycle
            break
    assert ready_at is not None, "cpu_ready sosem érkezett"

    dut.cpu_re.value = 0

    expected = (0xCA << 24) | (0xFE << 16) | (0xBA << 8) | 0xBE
    actual = int(dut.cpu_rdata.value)
    assert actual == expected, \
        f"Olvasás hiba: várt 0x{expected:08X}, kapott 0x{actual:08X}"
