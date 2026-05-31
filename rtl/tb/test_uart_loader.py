# hu: CLI-CPU F2.8 #6.5b-F1b — cilcpu_uart_loader cocotb tesztjei. A loader az
#     uart_rx byte-stream kimenetét (i_byte/i_byte_valid) parse-olja a WRITE és
#     BOOT keretekre, és (a) memória-szó-írásokat ad ki a QSPI-master porton,
#     (b) boot-kérést pulzál a paraméterekkel. A teszt közvetlenül byte-okat
#     etet (az uart_rx deszerializációt nem kell utánozni).
# en: CLI-CPU F2.8 #6.5b-F1b — cocotb tests for cilcpu_uart_loader. The loader
#     parses the uart_rx byte stream (i_byte/i_byte_valid) into WRITE and BOOT
#     frames, then (a) emits memory word-writes on the QSPI master port, and
#     (b) pulses a boot request with params. The test feeds bytes directly.
#
#     Protokoll / Protocol:
#       WRITE: 0xC0 | dev(1) | addr[23:0](3, BE) | len[15:0](2, BE) | payload
#              dev: 0=flash, 1=PSRAM → o_mem_addr[23:20]=szegmens, [19:0]=offszet
#              payload → 32-bit LE szavak, len bájt (4 többszöröse)
#       BOOT:  0xB0 | code_src(1) | boot_pc[23:0](3, BE) | argc(1) | localc(1)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CMD_WRITE = 0xC0
CMD_BOOT  = 0xB0
SEG_STACK = 0x2   # PSRAM szegmens (dev=1)
SEG_CODE  = 0x0   # flash szegmens (dev=0)


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_byte.value       = 0
    dut.i_byte_valid.value = 0
    dut.i_mem_ready.value  = 0
    dut.rst_n.value        = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def send_byte(dut, b):
    """hu: Egy byte átadása a loadernek (1-ciklusos valid pulzus)."""
    dut.i_byte.value       = b & 0xFF
    dut.i_byte_valid.value = 1
    await RisingEdge(dut.clk)
    dut.i_byte_valid.value = 0
    await Timer(1, units="ns")


def capture_writes(dut, sink):
    """hu: Monitor — o_mem_we pulzusra (addr, wdata) rögzítése; i_mem_ready ack."""
    async def mon():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            try:
                if int(dut.o_mem_we.value) == 1:
                    sink.append((int(dut.o_mem_addr.value),
                                 int(dut.o_mem_wdata.value)))
                    # hu: a QSPI-írás kész — ack a következő ciklusban
                    dut.i_mem_ready.value = 1
                    await RisingEdge(dut.clk)
                    dut.i_mem_ready.value = 0
                    await Timer(1, units="ns")
            except (ValueError, AttributeError):
                pass
    return cocotb.start_soon(mon())


# ============================================================
# WRITE keret
# ============================================================

@cocotb.test()
async def test_01_write_psram_two_words(dut):
    """hu: WRITE dev=1 (PSRAM), addr=0x02000, len=8, payload 8 bájt → 2 szó-írás
        0x202000 és 0x202004 címre, BIG-ENDIAN szó-összeállítással (round-trip).
    en: WRITE dev=1 (PSRAM), addr=0x02000, len=8, 8-byte payload → 2 word writes
        at 0x202000 and 0x202004, big-endian word assembly (round-trip)."""
    await reset_dut(dut)
    sink = []
    capture_writes(dut, sink)

    payload = [0x11, 0x22, 0x33, 0x44,  0x55, 0x66, 0x77, 0x88]
    frame = ([CMD_WRITE, 0x01, 0x00, 0x20, 0x00, 0x00, 0x08] + payload)
    for b in frame:
        await send_byte(dut, b)
        # hu: a data-fázisban hagyunk időt az esetleges írás-handshake-re
        for _ in range(6):
            await RisingEdge(dut.clk)
    for _ in range(10):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert len(sink) == 2, f"2 szó-írás várt, kaptam {len(sink)}: {[hex(a) for a,_ in sink]}"
    addr0, w0 = sink[0]
    addr1, w1 = sink[1]
    assert addr0 == 0x202000, f"1. cím 0x{addr0:06X}, várt 0x202000 (SEG_STACK|0x02000)"
    assert w0 == 0x11223344, f"1. szó 0x{w0:08X}, várt 0x11223344 (BE)"
    assert addr1 == 0x202004, f"2. cím 0x{addr1:06X}, várt 0x202004"
    assert w1 == 0x55667788, f"2. szó 0x{w1:08X}, várt 0x55667788 (BE)"


@cocotb.test()
async def test_02_write_flash_segment(dut):
    """hu: WRITE dev=0 (flash) → o_mem_addr[23:20]=SEG_CODE (0x0). Az írás
        cím-leképezését ellenőrzi (a flash-program HW F2; itt csak a cím).
    en: WRITE dev=0 (flash) → o_mem_addr[23:20]=SEG_CODE. Checks the address
        mapping (flash-program HW is F2; here only the address)."""
    await reset_dut(dut)
    sink = []
    capture_writes(dut, sink)

    payload = [0xDE, 0xAD, 0xBE, 0xEF]
    frame = ([CMD_WRITE, 0x00, 0x00, 0x10, 0x00, 0x00, 0x04] + payload)
    for b in frame:
        await send_byte(dut, b)
        for _ in range(6):
            await RisingEdge(dut.clk)
    for _ in range(10):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert len(sink) == 1, f"1 szó-írás várt, kaptam {len(sink)}"
    addr0, w0 = sink[0]
    assert addr0 == 0x001000, f"cím 0x{addr0:06X}, várt 0x001000 (SEG_CODE|0x01000)"
    assert w0 == 0xDEADBEEF, f"szó 0x{w0:08X}, várt 0xDEADBEEF (BE)"


# ============================================================
# BOOT keret
# ============================================================

@cocotb.test()
async def test_03_boot_request(dut):
    """hu: BOOT code_src=1, pc=0x000005, argc=2, localc=3 → o_boot_req pulzus a
        helyes paraméterekkel.
    en: BOOT code_src=1, pc=0x000005, argc=2, localc=3 → o_boot_req pulse with
        the correct params."""
    await reset_dut(dut)

    captured = {}

    async def boot_mon():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            try:
                if int(dut.o_boot_req.value) == 1:
                    captured["pc"]       = int(dut.o_boot_pc.value)
                    captured["argc"]     = int(dut.o_boot_argc.value)
                    captured["localc"]   = int(dut.o_boot_localc.value)
                    captured["code_src"] = int(dut.o_boot_code_src.value)
            except (ValueError, AttributeError):
                pass
    cocotb.start_soon(boot_mon())

    frame = [CMD_BOOT, 0x01, 0x00, 0x00, 0x05, 0x02, 0x03]
    for b in frame:
        await send_byte(dut, b)
        await RisingEdge(dut.clk)
    for _ in range(6):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert captured, "o_boot_req soha nem pulzált"
    assert captured["pc"] == 0x000005, f"boot_pc 0x{captured['pc']:06X}, várt 0x000005"
    assert captured["argc"] == 2, f"argc {captured['argc']}, várt 2"
    assert captured["localc"] == 3, f"localc {captured['localc']}, várt 3"
    assert captured["code_src"] == 1, f"code_src {captured['code_src']}, várt 1"


@cocotb.test()
async def test_04_unknown_cmd_ignored(dut):
    """hu: Ismeretlen parancs-byte → no-op (nincs write, nincs boot), majd egy
        érvényes BOOT keret még feldolgozódik (a parser nem ragad be).
    en: Unknown command byte → no-op, then a valid BOOT frame is still parsed
        (the parser does not get stuck)."""
    await reset_dut(dut)

    boot_seen = []

    async def boot_mon():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            try:
                if int(dut.o_boot_req.value) == 1:
                    boot_seen.append(int(dut.o_boot_pc.value))
            except (ValueError, AttributeError):
                pass
    cocotb.start_soon(boot_mon())

    for b in [0x00, 0x7F, 0xFF]:   # ismeretlen parancs-byte-ok
        await send_byte(dut, b)
        await RisingEdge(dut.clk)

    frame = [CMD_BOOT, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00]
    for b in frame:
        await send_byte(dut, b)
        await RisingEdge(dut.clk)
    for _ in range(6):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert boot_seen == [0x000009], f"egy BOOT(pc=9) várt, kaptam {[hex(x) for x in boot_seen]}"
