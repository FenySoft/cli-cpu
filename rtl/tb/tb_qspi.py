# hu: CLI-CPU cocotb közös QSPI flash slave modell. Kiemelve a test_core.py
#     mintájából, hogy a wrapper (cilcpu_tt_top) és minden további
#     top-level cocotb teszt ugyanazt a flash slave-et használhassa.
# en: CLI-CPU cocotb shared QSPI flash slave model. Extracted from the
#     test_core.py pattern so that the wrapper (cilcpu_tt_top) and any
#     future top-level cocotb test can reuse the same flash slave.

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge


# ============================================================
# hu: QSPI parancsok és dummy ciklusok (a cilcpu_qspi_controller.v szerint)
# en: QSPI commands and dummy cycles (per cilcpu_qspi_controller.v)
# ============================================================

QSPI_CMD_FLASH_READ  = 0x6B
QSPI_CMD_PSRAM_READ  = 0xEB
QSPI_CMD_PSRAM_WRITE = 0x38
QSPI_DUMMY_FLASH     = 8
QSPI_DUMMY_PSRAM     = 6


class TQSPIFlashModel:
    """hu: Read-only QSPI Flash modell — a CODE bytes-ot tárolja byte-címen.
    en: Read-only QSPI Flash model — stores CODE bytes by byte address."""

    def __init__(self, code_bytes=None):
        self.mem = {}
        if code_bytes:
            for offset, b in enumerate(code_bytes):
                self.mem[offset] = b

    def read_word(self, addr):
        """hu: 32-bit szó olvasás, big-endian byte-sorrend a QSPI vonalon.
        en: 32-bit word read, big-endian byte order on the QSPI wire."""
        b3 = self.mem.get(addr,     0xFF)
        b2 = self.mem.get(addr + 1, 0xFF)
        b1 = self.mem.get(addr + 2, 0xFF)
        b0 = self.mem.get(addr + 3, 0xFF)
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0


async def qspi_flash_driver(dut, flash, clk_signal=None, cs_signal=None,
                            dq_in_signal=None, dq_out_signal=None):
    """hu: QSPI Flash slave coroutine — figyeli a CS#, CLK, DQ jeleket,
        és a 0x6B Flash Read parancsra válaszol. A jelnevek a top-level
        DUT-ról azonosak, de paraméterezhetők, ha a wrapper más nevet ad.
    en: QSPI Flash slave coroutine — watches CS#, CLK, DQ signals and
        responds to the 0x6B Flash Read command. Signal names match the
        top-level DUT by default, but can be overridden when a wrapper
        renames them."""

    if clk_signal is None:
        clk_signal = dut.qspi_clk
    if cs_signal is None:
        cs_signal = dut.qspi_cs_flash_n
    if dq_in_signal is None:
        dq_in_signal = dut.qspi_dq_in
    if dq_out_signal is None:
        dq_out_signal = dut.qspi_dq_out

    while True:
        await RisingEdge(dut.clk if hasattr(dut, "clk") else dut.i_clk_50m)
        try:
            cs_flash = int(cs_signal.value)
        except ValueError:
            continue

        if cs_flash != 0:
            continue

        # hu: 1. CMD fázis — 8 bit SPI / en: CMD phase — 8-bit SPI
        cmd = 0
        for _ in range(8):
            await RisingEdge(clk_signal)
            bit = int(dq_out_signal.value) & 0x01
            cmd = (cmd << 1) | bit

        if cmd != QSPI_CMD_FLASH_READ:
            while int(cs_signal.value) == 0:
                await RisingEdge(dut.clk if hasattr(dut, "clk") else dut.i_clk_50m)
            continue

        # hu: 2. ADDR fázis — 24 bit SPI / en: ADDR phase — 24-bit SPI
        addr = 0
        for _ in range(24):
            await RisingEdge(clk_signal)
            bit = int(dq_out_signal.value) & 0x01
            addr = (addr << 1) | bit

        # hu: 3. DUMMY fázis — 8 QSPI ciklus / en: DUMMY phase — 8 QSPI cycles
        for _ in range(QSPI_DUMMY_FLASH):
            await RisingEdge(clk_signal)

        # hu: 4. DATA fázis — 32 bit, quad mód, falling edge-en hajt
        # en: DATA phase — 32 bits, quad mode, drives on falling edge
        word = flash.read_word(addr)
        for i in range(8):
            await FallingEdge(clk_signal)
            nibble = (word >> (28 - i * 4)) & 0x0F
            dq_in_signal.value = nibble

        # hu: Várjuk meg, amíg CS# magasra megy
        # en: Wait for CS# to go high
        while int(cs_signal.value) == 0:
            await RisingEdge(dut.clk if hasattr(dut, "clk") else dut.i_clk_50m)
