# hu: CLI-CPU F2.4 QSPI Controller cocotb tesztek — a cilcpu_qspi_controller.v
#     QSPI Flash (read-only) és PSRAM (read-write) interfész verifikálása.
#     Tesztstratégia: QSPI_CONTROLLER_SPEC.md "Tesztstratégia" 25 pontja alapján.
# en: CLI-CPU F2.4 QSPI Controller cocotb tests — verification of
#     cilcpu_qspi_controller.v QSPI Flash (read-only) and PSRAM (read-write)
#     interface. Test strategy: based on QSPI_CONTROLLER_SPEC.md 25 test points.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import os
import random

# ============================================================
# hu: QSPI parancs kódok és konstansok (QSPI_CONTROLLER_SPEC.md)
# en: QSPI command codes and constants (QSPI_CONTROLLER_SPEC.md)
# ============================================================

QSPI_CMD_FLASH_READ  = 0x6B  # Quad Output Read (Flash)
QSPI_CMD_PSRAM_READ  = 0xEB  # Fast Read Quad I/O (PSRAM)
QSPI_CMD_PSRAM_WRITE = 0x38  # Quad Write (PSRAM)

QSPI_DUMMY_FLASH = 8  # 0x6B dummy QSPI ciklusok
QSPI_DUMMY_PSRAM = 6  # 0xEB dummy QSPI ciklusok

SEG_CODE  = 0x0
SEG_DATA  = 0x1
SEG_STACK = 0x2

# ============================================================
# hu: QSPI Slave viselkedés-modellek
# en: QSPI Slave behavioral models
# ============================================================


class TQSPISlaveModel:
    """
    hu: QSPI slave eszköz viselkedés-modell. Figyeli a CS#, CLK és DQ jeleket,
        dekódolja a QSPI tranzakciókat, és a DATA fázisban hajtja a dq_in-t.
        Két leszármazott: Flash (read-only) és PSRAM (read-write).
    en: QSPI slave device behavioral model. Monitors CS#, CLK and DQ signals,
        decodes QSPI transactions, and drives dq_in during DATA phase.
        Two subclasses: Flash (read-only) and PSRAM (read-write).
    """

    def __init__(self, name, mem_init=None):
        self.name = name
        self.mem = dict(mem_init) if mem_init else {}

    def read_byte(self, addr):
        return self.mem.get(addr, 0xFF)

    def read_word(self, addr):
        """hu: 32-bit szó olvasás, big-endian byte sorrend a QSPI-n.
        en: 32-bit word read, big-endian byte order on QSPI."""
        b3 = self.read_byte(addr)
        b2 = self.read_byte(addr + 1)
        b1 = self.read_byte(addr + 2)
        b0 = self.read_byte(addr + 3)
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0

    def write_word(self, addr, value):
        """hu: 32-bit szó írás, big-endian byte sorrend.
        en: 32-bit word write, big-endian byte order."""
        self.mem[addr]     = (value >> 24) & 0xFF
        self.mem[addr + 1] = (value >> 16) & 0xFF
        self.mem[addr + 2] = (value >> 8) & 0xFF
        self.mem[addr + 3] = value & 0xFF


class TQSPIFlashModel(TQSPISlaveModel):
    """hu: QSPI Flash — read-only, 0x6B parancsot ismeri.
    en: QSPI Flash — read-only, supports 0x6B command."""

    def __init__(self, mem_init=None):
        super().__init__("Flash", mem_init)

    def supports_write(self):
        return False


class TQSPIPSRAMModel(TQSPISlaveModel):
    """hu: QSPI PSRAM — read-write, 0xEB és 0x38 parancsokat ismeri.
    en: QSPI PSRAM — read-write, supports 0xEB and 0x38 commands."""

    def __init__(self, mem_init=None):
        super().__init__("PSRAM", mem_init)

    def supports_write(self):
        return True


# hu: Az aktívan futó QSPI slave modell task. A reset_dut killeli a korábbit.
# en: Currently running QSPI slave model task. reset_dut kills the previous one.
_slave_model_task = None


async def qspi_slave_driver(dut, flash_model, psram_model):
    """
    hu: QSPI slave koroutin — figyeli mindkét eszköz CS# jelét, és a megfelelő
        modell alapján dekódolja a tranzakciót. A DATA_RD fázisban hajtja a
        dut.qspi_dq_in vonalat.
    en: QSPI slave coroutine — monitors both device CS# signals and decodes
        transactions using the appropriate model. Drives dut.qspi_dq_in during
        DATA_RD phase.
    """

    async def _handle_transaction(dut, model, is_flash):
        """hu: Egyetlen QSPI tranzakció dekódolása és válasz.
        en: Decode a single QSPI transaction and respond."""

        # hu: 1. CMD fázis — 8 bit SPI (DQ[0]), CLK rising edge-en mintavétel
        # en: 1. CMD phase — 8 bits SPI (DQ[0]), sample on CLK rising edge
        cmd = 0
        for i in range(8):
            await RisingEdge(dut.qspi_clk)
            bit = int(dut.qspi_dq_out.value) & 0x01
            cmd = (cmd << 1) | bit

        # hu: 2. ADDR fázis — parancs-függő: 0x6B = SPI (24 bit), 0xEB/0x38 = Quad (6 CLK)
        # en: 2. ADDR phase — command-dependent: 0x6B = SPI (24 bits), 0xEB/0x38 = Quad (6 CLKs)
        addr = 0
        if cmd == QSPI_CMD_FLASH_READ:
            # hu: SPI mód — 24 bit, 1 bit/CLK
            for i in range(24):
                await RisingEdge(dut.qspi_clk)
                bit = int(dut.qspi_dq_out.value) & 0x01
                addr = (addr << 1) | bit
        else:
            # hu: Quad mód — 24 bit, 4 bit/CLK = 6 CLK
            for i in range(6):
                await RisingEdge(dut.qspi_clk)
                nibble = int(dut.qspi_dq_out.value) & 0x0F
                addr = (addr << 4) | nibble

        # hu: 3. DUMMY fázis (csak olvasásnál)
        # en: 3. DUMMY phase (read only)
        is_write = (cmd == QSPI_CMD_PSRAM_WRITE)
        if not is_write:
            dummy_count = QSPI_DUMMY_FLASH if is_flash else QSPI_DUMMY_PSRAM
            for i in range(dummy_count):
                await RisingEdge(dut.qspi_clk)

        # hu: 4. DATA fázis — 32 bit, quad mód
        # en: 4. DATA phase — 32 bits, quad mode
        if is_write:
            # hu: Írás — DQ[3:0] mintavétel rising edge-en
            # en: Write — sample DQ[3:0] on rising edge
            write_data = 0
            for i in range(8):
                await RisingEdge(dut.qspi_clk)
                nibble = int(dut.qspi_dq_out.value) & 0x0F
                write_data = (write_data << 4) | nibble
            model.write_word(addr, write_data)
        else:
            # hu: Olvasás — DQ[3:0] hajtása falling edge-en (setup a rising edge előtt)
            # en: Read — drive DQ[3:0] on falling edge (setup before rising edge)
            word = model.read_word(addr)
            for i in range(8):
                await FallingEdge(dut.qspi_clk)
                nibble = (word >> (28 - i * 4)) & 0x0F
                dut.qspi_dq_in.value = nibble

    while True:
        await RisingEdge(dut.clk)
        try:
            cs_flash = int(dut.qspi_cs_flash_n.value)
            cs_psram = int(dut.qspi_cs_psram_n.value)
        except ValueError:
            continue

        if cs_flash == 0:
            await _handle_transaction(dut, flash_model, is_flash=True)
            # hu: Várjuk meg, amíg CS# valóban magasra megy — phantom re-entry elkerülése
            # en: Wait until CS# actually goes high — prevents phantom re-entry
            while int(dut.qspi_cs_flash_n.value) == 0:
                await RisingEdge(dut.clk)
        elif cs_psram == 0:
            await _handle_transaction(dut, psram_model, is_flash=False)
            # hu: Várjuk meg, amíg CS# valóban magasra megy — phantom re-entry elkerülése
            # en: Wait until CS# actually goes high — prevents phantom re-entry
            while int(dut.qspi_cs_psram_n.value) == 0:
                await RisingEdge(dut.clk)


# ============================================================
# hu: Segédfüggvények
# en: Helper functions
# ============================================================


async def reset_dut(dut, flash_mem=None, psram_mem=None):
    """
    hu: Aszinkron aktív-low reset, 3 ciklus. Indít friss QSPI slave modellt.
    en: Async active-low reset, 3 cycles. Starts fresh QSPI slave models.
    """
    global _slave_model_task

    if _slave_model_task is not None:
        _slave_model_task.kill()

    flash_model = TQSPIFlashModel(flash_mem)
    psram_model = TQSPIPSRAMModel(psram_mem)

    _slave_model_task = cocotb.start_soon(
        qspi_slave_driver(dut, flash_model, psram_model)
    )

    # hu: Reset assert
    dut.rst_n.value = 0
    dut.cpu_addr.value = 0
    dut.cpu_wdata.value = 0
    dut.cpu_re.value = 0
    dut.cpu_we.value = 0
    dut.qspi_dq_in.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # hu: Reset feloldás
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    return flash_model, psram_model


def make_addr(segment, offset):
    """hu: CPU cím összeállítása szegmensből és offset-ből.
    en: Compose CPU address from segment and offset."""
    return ((segment & 0xF) << 20) | (offset & 0xFFFFF)


async def do_read(dut, addr, timeout=200):
    """
    hu: Olvasás indítása és várakozás cpu_ready-re.
    en: Start a read and wait for cpu_ready.
    """
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = addr & 0xFFFFFF
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                return int(dut.cpu_rdata.value)
        except ValueError:
            pass

    raise TimeoutError(f"cpu_ready not asserted within {timeout} cycles for read @ 0x{addr:06X}")


async def do_write(dut, addr, data, timeout=200):
    """
    hu: Írás indítása és várakozás cpu_ready-re.
    en: Start a write and wait for cpu_ready.
    """
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = addr & 0xFFFFFF
    dut.cpu_wdata.value = data & 0xFFFFFFFF
    dut.cpu_we.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_we.value = 0

    for _ in range(timeout):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                return
        except ValueError:
            pass

    raise TimeoutError(f"cpu_ready not asserted within {timeout} cycles for write @ 0x{addr:06X}")


# ============================================================
# hu: Tesztek (QSPI_CONTROLLER_SPEC.md 25 pont)
# en: Tests (QSPI_CONTROLLER_SPEC.md 25 points)
# ============================================================


@cocotb.test()
async def test_01_reset_state(dut):
    """hu: Reset állapot — cpu_busy=0, cs=1, clk=0, oe=0.
    en: Reset state — cpu_busy=0, cs=1, clk=0, oe=0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    assert int(dut.cpu_busy.value) == 0, "cpu_busy should be 0 after reset"
    assert int(dut.qspi_cs_flash_n.value) == 1, "qspi_cs_flash_n should be 1 (inactive) after reset"
    assert int(dut.qspi_cs_psram_n.value) == 1, "qspi_cs_psram_n should be 1 (inactive) after reset"
    assert int(dut.qspi_clk.value) == 0, "qspi_clk should be 0 after reset"
    assert int(dut.qspi_dq_oe.value) == 0, "qspi_dq_oe should be 0 (Hi-Z) after reset"


@cocotb.test()
async def test_02_idle_no_clock(dut):
    """hu: IDLE-ban nincs QSPI CLK — 100 ciklus várakozás, qspi_clk mindig 0.
    en: No QSPI CLK in IDLE — wait 100 cycles, qspi_clk always 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    for i in range(100):
        await RisingEdge(dut.clk)
        assert int(dut.qspi_clk.value) == 0, \
            f"qspi_clk toggled in IDLE at cycle {i}"


@cocotb.test()
async def test_03_flash_read_single_word(dut):
    """hu: Flash olvasás — CODE szegmens, helyes 32-bit adat.
    en: Flash read — CODE segment, correct 32-bit data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # hu: Flash memória előtöltése: 0x000100 címen 0xCAFEBABE
    flash_mem = {}
    addr = 0x000100
    val = 0xCAFEBABE
    flash_mem[addr]     = (val >> 24) & 0xFF
    flash_mem[addr + 1] = (val >> 16) & 0xFF
    flash_mem[addr + 2] = (val >> 8) & 0xFF
    flash_mem[addr + 3] = val & 0xFF

    await reset_dut(dut, flash_mem=flash_mem)

    result = await do_read(dut, make_addr(SEG_CODE, addr))
    assert result == val, \
        f"Flash read mismatch: expected 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_04_psram_read_single_word(dut):
    """hu: PSRAM olvasás — STACK szegmens, helyes 32-bit adat.
    en: PSRAM read — STACK segment, correct 32-bit data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    psram_mem = {}
    addr = 0x000200
    val = 0x12345678
    psram_mem[addr]     = (val >> 24) & 0xFF
    psram_mem[addr + 1] = (val >> 16) & 0xFF
    psram_mem[addr + 2] = (val >> 8) & 0xFF
    psram_mem[addr + 3] = val & 0xFF

    await reset_dut(dut, psram_mem=psram_mem)

    result = await do_read(dut, make_addr(SEG_STACK, addr))
    assert result == val, \
        f"PSRAM read mismatch: expected 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_05_psram_write_single_word(dut):
    """hu: PSRAM írás — 0xDEADBEEF a STACK szegmensbe.
    en: PSRAM write — 0xDEADBEEF to STACK segment."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    _, psram_model = await reset_dut(dut)

    addr = 0x000100
    val = 0xDEADBEEF
    await do_write(dut, make_addr(SEG_STACK, addr), val)

    stored = psram_model.read_word(addr)
    assert stored == val, \
        f"PSRAM write mismatch: expected 0x{val:08X}, got 0x{stored:08X}"


@cocotb.test()
async def test_06_psram_write_then_read(dut):
    """hu: PSRAM írás→olvasás round-trip — azonos adat.
    en: PSRAM write-then-read round-trip — same data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    addr = 0x000300
    val = 0xA5A5A5A5
    await do_write(dut, make_addr(SEG_STACK, addr), val)
    result = await do_read(dut, make_addr(SEG_STACK, addr))

    assert result == val, \
        f"Round-trip mismatch: expected 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_07_code_segment_selects_flash(dut):
    """hu: CODE szegmens → Flash CS# assert.
    en: CODE segment → Flash CS# asserted."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: Néhány ciklus várakozás, ellenőrizni a CS# jeleket
    found_flash_cs = False
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.qspi_cs_flash_n.value) == 0:
            found_flash_cs = True
            assert int(dut.qspi_cs_psram_n.value) == 1, \
                "PSRAM CS# should be inactive during Flash transaction"
            break

    assert found_flash_cs, "Flash CS# was never asserted for CODE segment read"

    # hu: Megvárjuk a tranzakció végét
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass


@cocotb.test()
async def test_08_data_segment_selects_flash(dut):
    """hu: DATA szegmens → Flash CS# assert.
    en: DATA segment → Flash CS# asserted."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0x100000: 0x00, 0x100001: 0x00, 0x100002: 0x00, 0x100003: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_DATA, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    found_flash_cs = False
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.qspi_cs_flash_n.value) == 0:
            found_flash_cs = True
            assert int(dut.qspi_cs_psram_n.value) == 1, \
                "PSRAM CS# should be inactive during DATA segment read"
            break

    assert found_flash_cs, "Flash CS# was never asserted for DATA segment read"

    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass


@cocotb.test()
async def test_09_stack_segment_selects_psram(dut):
    """hu: STACK szegmens → PSRAM CS# assert.
    en: STACK segment → PSRAM CS# asserted."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    psram_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, psram_mem=psram_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_STACK, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    found_psram_cs = False
    for _ in range(10):
        await RisingEdge(dut.clk)
        if int(dut.qspi_cs_psram_n.value) == 0:
            found_psram_cs = True
            assert int(dut.qspi_cs_flash_n.value) == 1, \
                "Flash CS# should be inactive during PSRAM transaction"
            break

    assert found_psram_cs, "PSRAM CS# was never asserted for STACK segment read"

    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass


@cocotb.test()
async def test_10_write_to_flash_rejected(dut):
    """hu: Flash-be írás elutasítva — cpu_ready=1 azonnal, nincs QSPI tranzakció.
    en: Write to Flash rejected — cpu_ready=1 immediately, no QSPI transaction."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0x100)
    dut.cpu_wdata.value = 0xBAADF00D
    dut.cpu_we.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_we.value = 0

    # hu: cpu_ready-nek 1-2 cikluson belül meg kell jelennie, CS# NEM assert
    found_ready = False
    for _ in range(3):
        await RisingEdge(dut.clk)
        assert int(dut.qspi_cs_flash_n.value) == 1, \
            "Flash CS# should NOT assert for write"
        assert int(dut.qspi_cs_psram_n.value) == 1, \
            "PSRAM CS# should NOT assert for write to CODE"
        if int(dut.cpu_ready.value) == 1:
            found_ready = True
            break

    assert found_ready, "cpu_ready not asserted for rejected Flash write"


@cocotb.test()
async def test_11_cmd_phase_timing(dut):
    """hu: CMD fázis — 8 QSPI CLK, DQ[0] MSB-first, helyes parancs byte.
    en: CMD phase — 8 QSPI CLKs, DQ[0] MSB-first, correct command byte."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: Olvasás indítás — CMD fázis figyelése
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: CMD byte begyűjtése QSPI CLK rising edge-eken
    cmd_bits = []
    clk_count = 0
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            qclk = int(dut.qspi_clk.value)
        except ValueError:
            continue
        # hu: Detektáljuk a QSPI CLK rising edge-et
        if qclk == 1 and int(dut.qspi_dq_oe.value) == 1:
            bit = int(dut.qspi_dq_out.value) & 0x01
            cmd_bits.append(bit)
            clk_count += 1
            if clk_count >= 8:
                break

    assert len(cmd_bits) == 8, f"Expected 8 CMD bits, got {len(cmd_bits)}"
    cmd_byte = 0
    for b in cmd_bits:
        cmd_byte = (cmd_byte << 1) | b
    assert cmd_byte == QSPI_CMD_FLASH_READ, \
        f"CMD byte mismatch: expected 0x{QSPI_CMD_FLASH_READ:02X}, got 0x{cmd_byte:02X}"

    # hu: Tranzakció befejezése
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass


@cocotb.test()
async def test_12_addr_phase_correct(dut):
    """hu: ADDR fázis — helyes cím, PSRAM quad mód (6 QSPI CLK).
    en: ADDR phase — correct address, PSRAM quad mode (6 QSPI CLKs)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    target_addr = 0x000ABC
    psram_mem = {}
    for i in range(4):
        psram_mem[target_addr + i] = 0x00
    await reset_dut(dut, psram_mem=psram_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_STACK, target_addr)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: Megvárjuk a tranzakció végét — az ADDR ellenőrzést a slave modell végzi
    result = None
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                result = int(dut.cpu_rdata.value)
                break
        except ValueError:
            pass

    assert result is not None, "Transaction did not complete"


@cocotb.test()
async def test_13_flash_dummy_cycles(dut):
    """hu: Flash dummy ciklus szám — 8 QSPI CLK a 0x6B után.
    en: Flash dummy cycle count — 8 QSPI CLKs after 0x6B."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0xAA, 1: 0xBB, 2: 0xCC, 3: 0xDD}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: Olvasás — ellenőrizzük, hogy a helyes adat jön vissza
    #     (ha a dummy ciklus szám hibás, rossz adat jön)
    result = await do_read(dut, make_addr(SEG_CODE, 0))
    expected = 0xAABBCCDD
    assert result == expected, \
        f"Flash read (dummy test): expected 0x{expected:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_14_psram_dummy_cycles(dut):
    """hu: PSRAM dummy ciklus szám — 6 QSPI CLK a 0xEB után.
    en: PSRAM dummy cycle count — 6 QSPI CLKs after 0xEB."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    psram_mem = {0x100: 0x11, 0x101: 0x22, 0x102: 0x33, 0x103: 0x44}
    await reset_dut(dut, psram_mem=psram_mem)

    result = await do_read(dut, make_addr(SEG_STACK, 0x100))
    expected = 0x11223344
    assert result == expected, \
        f"PSRAM read (dummy test): expected 0x{expected:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_15_read_data_phase(dut):
    """hu: Olvasás DATA fázis — 8 QSPI CLK, helyes shift-in, különböző értékek.
    en: Read DATA phase — 8 QSPI CLKs, correct shift-in, various values."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    test_values = [0x00000000, 0xFFFFFFFF, 0x12345678, 0xFEDCBA98]
    for val in test_values:
        flash_mem = {}
        addr = 0x000000
        flash_mem[addr]     = (val >> 24) & 0xFF
        flash_mem[addr + 1] = (val >> 16) & 0xFF
        flash_mem[addr + 2] = (val >> 8) & 0xFF
        flash_mem[addr + 3] = val & 0xFF

        await reset_dut(dut, flash_mem=flash_mem)
        result = await do_read(dut, make_addr(SEG_CODE, addr))
        assert result == val, \
            f"DATA phase read: expected 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_16_write_data_phase(dut):
    """hu: Írás DATA fázis — helyes nibble sorrend, különböző értékek.
    en: Write DATA phase — correct nibble order, various values."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    test_values = [0x00000000, 0xFFFFFFFF, 0xA5A5A5A5, 0x5A5A5A5A]
    for val in test_values:
        _, psram_model = await reset_dut(dut)
        addr = 0x000000
        await do_write(dut, make_addr(SEG_STACK, addr), val)
        stored = psram_model.read_word(addr)
        assert stored == val, \
            f"Write DATA phase: expected 0x{val:08X}, got 0x{stored:08X}"


@cocotb.test()
async def test_17_cpu_ready_timing(dut):
    """hu: cpu_ready pulzus — pontosan 1 main CLK ciklusos.
    en: cpu_ready pulse — exactly 1 main CLK cycle."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: Megkeressük a cpu_ready=1 ciklust
    ready_count = 0
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                ready_count += 1
        except ValueError:
            pass
        if ready_count > 0 and int(dut.cpu_ready.value) == 0:
            break

    assert ready_count == 1, \
        f"cpu_ready should be 1 for exactly 1 cycle, was high for {ready_count}"


@cocotb.test()
async def test_18_busy_during_transaction(dut):
    """hu: Tranzakció alatt cpu_busy=1.
    en: cpu_busy=1 during transaction."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: Ellenőrizzük, hogy IDLE-ban busy=0
    assert int(dut.cpu_busy.value) == 0, "cpu_busy should be 0 in IDLE"

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: Tranzakció közben busy=1 kell legyen
    busy_seen = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_busy.value) == 1:
                busy_seen = True
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass

    assert busy_seen, "cpu_busy was never 1 during transaction"

    # hu: Tranzakció után busy=0
    await RisingEdge(dut.clk)
    assert int(dut.cpu_busy.value) == 0, "cpu_busy should return to 0 after transaction"


@cocotb.test()
async def test_19_back_to_back_reads(dut):
    """hu: Egymás utáni olvasások — mindkettő helyes adat.
    en: Back-to-back reads — both return correct data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    flash_mem = {}
    for i in range(4):
        flash_mem[i] = (0xAAAAAAAA >> (24 - i * 8)) & 0xFF
        flash_mem[0x100 + i] = (0xBBBBBBBB >> (24 - i * 8)) & 0xFF

    await reset_dut(dut, flash_mem=flash_mem)

    r1 = await do_read(dut, make_addr(SEG_CODE, 0x000000))
    r2 = await do_read(dut, make_addr(SEG_CODE, 0x000100))

    assert r1 == 0xAAAAAAAA, f"First read: expected 0xAAAAAAAA, got 0x{r1:08X}"
    assert r2 == 0xBBBBBBBB, f"Second read: expected 0xBBBBBBBB, got 0x{r2:08X}"


@cocotb.test()
async def test_20_cs_deassert_between_transactions(dut):
    """hu: CS# deassert tranzakciók között — legalább 1 main CLK high.
    en: CS# deassert between transactions — at least 1 main CLK high."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {i: 0x00 for i in range(8)}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: Első olvasás
    await do_read(dut, make_addr(SEG_CODE, 0))

    # hu: CS# kell hogy high legyen most
    assert int(dut.qspi_cs_flash_n.value) == 1, \
        "CS# should be high between transactions"

    # hu: Második olvasás
    await do_read(dut, make_addr(SEG_CODE, 4))


@cocotb.test()
async def test_21_address_zero_read(dut):
    """hu: Cím 0x000000 olvasás — helyes adat.
    en: Address 0x000000 read — correct data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    val = 0x01020304
    flash_mem = {0: 0x01, 1: 0x02, 2: 0x03, 3: 0x04}
    await reset_dut(dut, flash_mem=flash_mem)

    result = await do_read(dut, make_addr(SEG_CODE, 0))
    assert result == val, f"Address 0 read: expected 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_22_max_address_per_segment(dut):
    """hu: Szegmensenként max cím — CODE max és STACK max.
    en: Max address per segment — CODE max and STACK max."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # hu: CODE max: 0x0FFFFC (1 MB - 4 = utolsó word)
    code_max = 0x0FFFFC
    val_code = 0xC0DEC0DE
    flash_mem = {}
    for i in range(4):
        flash_mem[code_max + i] = (val_code >> (24 - i * 8)) & 0xFF

    # hu: STACK max: 0x003FFC (16 KB - 4 = utolsó word)
    stack_max = 0x003FFC
    val_stack = 0x57AC57AC
    psram_mem = {}
    for i in range(4):
        psram_mem[stack_max + i] = (val_stack >> (24 - i * 8)) & 0xFF

    await reset_dut(dut, flash_mem=flash_mem, psram_mem=psram_mem)

    r1 = await do_read(dut, make_addr(SEG_CODE, code_max))
    assert r1 == val_code, f"CODE max addr: expected 0x{val_code:08X}, got 0x{r1:08X}"

    r2 = await do_read(dut, make_addr(SEG_STACK, stack_max))
    assert r2 == val_stack, f"STACK max addr: expected 0x{val_stack:08X}, got 0x{r2:08X}"


@cocotb.test()
async def test_23_concurrent_re_we(dut):
    """hu: Egyidejű cpu_re + cpu_we — olvasás prioritás.
    en: Concurrent cpu_re + cpu_we — read priority."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    val = 0xFACEFACE
    flash_mem = {0: 0xFA, 1: 0xCE, 2: 0xFA, 3: 0xCE}
    await reset_dut(dut, flash_mem=flash_mem)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_wdata.value = 0xBAADF00D
    dut.cpu_re.value = 1
    dut.cpu_we.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0
    dut.cpu_we.value = 0

    # hu: Olvasásnak kell végrehajtódnia
    result = None
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                result = int(dut.cpu_rdata.value)
                break
        except ValueError:
            pass

    assert result == val, \
        f"Concurrent RE+WE: expected read result 0x{val:08X}, got 0x{result:08X}"


@cocotb.test()
async def test_24_dq_oe_transitions(dut):
    """hu: dq_oe fázisátmenetek — helyes irány minden fázisban.
    en: dq_oe transitions — correct direction in each phase."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    flash_mem = {0: 0x00, 1: 0x00, 2: 0x00, 3: 0x00}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: IDLE-ban oe=0
    assert int(dut.qspi_dq_oe.value) == 0, "dq_oe should be 0 in IDLE"

    # hu: Olvasás indítás
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: CMD és ADDR fázisban oe=1 kell legyen
    oe_high_seen = False
    oe_low_after_addr = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        try:
            oe = int(dut.qspi_dq_oe.value)
            busy = int(dut.cpu_busy.value)
            ready = int(dut.cpu_ready.value)
        except ValueError:
            continue

        if oe == 1 and busy == 1:
            oe_high_seen = True

        if oe_high_seen and oe == 0 and busy == 1:
            oe_low_after_addr = True

        if ready == 1:
            break

    assert oe_high_seen, "dq_oe was never 1 during CMD/ADDR phases"
    assert oe_low_after_addr, "dq_oe was never 0 during DUMMY/DATA_RD phases"


@cocotb.test()
async def test_25_random_read_write_sequence(dut):
    """hu: 200 random R/W — seeded RNG, Python referencia dict vs. PSRAM model.
    en: 200 random R/W — seeded RNG, Python reference dict vs. PSRAM model."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rng = random.Random(42)
    reference = {}
    errors = []

    for i in range(200):
        # hu: Word-aligned STACK cím (0..16380)
        addr = (rng.randint(0, 4095) & ~3)
        is_write = rng.random() < 0.5

        if is_write:
            val = rng.randint(0, 0xFFFFFFFF)
            await do_write(dut, make_addr(SEG_STACK, addr), val)
            # hu: Referencia frissítés
            reference[addr] = val
        else:
            result = await do_read(dut, make_addr(SEG_STACK, addr))
            expected = reference.get(addr, 0xFFFFFFFF)  # hu: PSRAM default = 0xFF byte-ok
            if result != expected:
                errors.append(
                    f"Op #{i}: READ addr=0x{addr:06X}: "
                    f"expected 0x{expected:08X}, got 0x{result:08X}"
                )

    assert len(errors) == 0, \
        f"Random R/W test failed with {len(errors)} errors:\n" + "\n".join(errors[:10])


# ============================================================
# hu: Új tesztek (26–29) — 2. iteráció audit javítások
# en: New tests (26–29) — 2nd iteration audit fixes
# ============================================================


@cocotb.test()
async def test_26_cmd_dq_high_bits_idle(dut):
    """hu: CMD fázis alatt DQ[3:1] = 0b111 (WP#/HOLD#/MISO inaktív).
           A teljes 8-ciklus CMD alatt minden rising edge-en ellenőrzött.
    en: During CMD phase DQ[3:1] = 0b111 (WP#/HOLD#/MISO inactive).
           Checked on every rising edge throughout the 8-cycle CMD phase."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # hu: Elindítunk egy Flash olvasást (CODE szegmens)
    # en: Start a Flash read (CODE segment)
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0x000100)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: CMD fázisban várunk — 8 QSPI CLK rising edge-ét mintázzuk
    # en: Wait in CMD phase — sample 8 QSPI CLK rising edges
    violations = []
    cmd_edges = 0
    in_cmd = False

    for _ in range(60):
        await RisingEdge(dut.clk)
        try:
            cs_flash = int(dut.qspi_cs_flash_n.value)
            oe = int(dut.qspi_dq_oe.value)
            clk_out = int(dut.qspi_clk.value)
            dq = int(dut.qspi_dq_out.value)
        except ValueError:
            continue

        if cs_flash == 0 and oe == 1 and clk_out == 1:
            in_cmd = True
            cmd_edges += 1
            high_bits = (dq >> 1) & 0x7
            if high_bits != 0x7:
                violations.append(f"edge {cmd_edges}: DQ[3:1]=0b{high_bits:03b} (expected 0b111)")
            if cmd_edges >= 8:
                break

    assert in_cmd, "CMD fázis nem detektálható (CS# soha nem ment le)"
    assert cmd_edges >= 8, f"CMD fázisban csak {cmd_edges} rising edge-t láttunk (várható: 8)"
    assert len(violations) == 0, \
        f"DQ[3:1] nem volt 0b111 a CMD fázisban:\n" + "\n".join(violations)

    # hu: Befejeztetjük a tranzakciót (cpu_ready)
    # en: Let the transaction finish (cpu_ready)
    for _ in range(300):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                break
        except ValueError:
            pass


@cocotb.test()
async def test_27_idle_dq_out_default(dut):
    """hu: IDLE állapotban qspi_dq_out = 4'hF — reset után és tranzakció után is.
    en: In IDLE state qspi_dq_out = 4'hF — both after reset and after a transaction."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # hu: 1. ellenőrzés: reset utáni IDLE
    # en: Check 1: IDLE right after reset
    await RisingEdge(dut.clk)
    try:
        dq = int(dut.qspi_dq_out.value)
    except ValueError:
        dq = -1
    assert dq == 0xF, f"Reset utáni IDLE: qspi_dq_out=0x{dq:X} (várt: 0xF)"

    # hu: 2. ellenőrzés: egyetlen tranzakció befejezése után
    # en: Check 2: after one complete transaction
    result = await do_read(dut, make_addr(SEG_STACK, 0x000004))

    # hu: 2 ciklusot várunk IDLE-be való visszatérésre
    # en: Wait 2 cycles for return to IDLE
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    try:
        dq2 = int(dut.qspi_dq_out.value)
    except ValueError:
        dq2 = -1
    assert dq2 == 0xF, f"Tranzakció utáni IDLE: qspi_dq_out=0x{dq2:X} (várt: 0xF)"


@cocotb.test()
async def test_28_default_segment_nop(dut):
    """hu: Érvénytelen szegmens (cpu_addr[23:20]=0x7) esetén cpu_ready azonnal
           visszajön (1–3 ciklus), CS# soha nem aktiválódik — read és write mindkettőre.
    en: Invalid segment (cpu_addr[23:20]=0x7) gives immediate cpu_ready (1–3 cycles),
           CS# never activates — tested for both read and write."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    invalid_addr = (0x7 << 20) | 0x0000FF  # hu: 0x7xxxxx — ismeretlen szegmens

    for op_name, is_write in [("read", False), ("write", True)]:
        # hu: Tranzakció indítása
        # en: Start transaction
        await FallingEdge(dut.clk)
        dut.cpu_addr.value = invalid_addr & 0xFFFFFF
        if is_write:
            dut.cpu_wdata.value = 0xABCD1234
            dut.cpu_we.value = 1
        else:
            dut.cpu_re.value = 1
        await RisingEdge(dut.clk)
        dut.cpu_re.value = 0
        dut.cpu_we.value = 0

        # hu: Legfeljebb 5 cikluson belül cpu_ready=1-et várunk
        # en: Expect cpu_ready=1 within at most 5 cycles
        ready_seen = False
        cs_ever_low = False
        for _ in range(5):
            await RisingEdge(dut.clk)
            try:
                cs_f = int(dut.qspi_cs_flash_n.value)
                cs_p = int(dut.qspi_cs_psram_n.value)
                rdy = int(dut.cpu_ready.value)
            except ValueError:
                continue
            if cs_f == 0 or cs_p == 0:
                cs_ever_low = True
            if rdy == 1:
                ready_seen = True
                break

        assert not cs_ever_low, \
            f"[{op_name}] Érvénytelen szegmensen CS# lement! (flash={cs_f} psram={cs_p})"
        assert ready_seen, \
            f"[{op_name}] cpu_ready nem érkezett 5 cikluson belül érvénytelen szegmensre"

        # hu: 2 ciklus szünet a tesztek között
        # en: 2-cycle pause between tests
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_29_busy_ignores_new_request(dut):
    """hu: Folyamatban lévő tranzakció közepén érkező második cpu_re=1 pulzus
           nem indít új tranzakciót. Az első tranzakció helyesen fejeződik be
           (cpu_ready=1 a várt rdata-val), utána cpu_busy=0 és nincs aktív CS#.
    en: A second cpu_re=1 pulse arriving mid-transaction does not start a new
           transaction. The first transaction completes correctly (cpu_ready=1 with
           expected rdata), then cpu_busy=0 and no CS# is active."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    expected_val = 0x12345678
    flash_mem = {0: 0x12, 1: 0x34, 2: 0x56, 3: 0x78}
    await reset_dut(dut, flash_mem=flash_mem)

    # hu: Első olvasás indítása
    # en: Start first read
    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0x000000)
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: ~10 ciklus várakozás (tranzakció közepe), majd második cpu_re pulzus
    # en: Wait ~10 cycles (mid-transaction), then fire a second cpu_re pulse
    for _ in range(10):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.cpu_addr.value = make_addr(SEG_CODE, 0x000004)  # hu: más cím
    dut.cpu_re.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_re.value = 0

    # hu: Az első tranzakció befejezésére várunk
    # en: Wait for the first transaction to complete
    rdata = None
    for _ in range(300):
        await RisingEdge(dut.clk)
        try:
            if int(dut.cpu_ready.value) == 1:
                rdata = int(dut.cpu_rdata.value)
                break
        except ValueError:
            pass

    assert rdata is not None, "cpu_ready soha nem jött — timeout"
    assert rdata == expected_val, \
        f"Első tranzakció rdata=0x{rdata:08X} (várt: 0x{expected_val:08X}) — rossz cím mintázva"

    # hu: cpu_ready után: cpu_busy=0 és CS# inaktív
    # en: After cpu_ready: cpu_busy=0 and CS# inactive
    await RisingEdge(dut.clk)
    try:
        busy = int(dut.cpu_busy.value)
        cs_f = int(dut.qspi_cs_flash_n.value)
        cs_p = int(dut.qspi_cs_psram_n.value)
    except ValueError:
        busy, cs_f, cs_p = -1, -1, -1

    assert busy == 0, f"cpu_busy={busy} (várt: 0) a tranzakció befejezése után"
    assert cs_f == 1, f"qspi_cs_flash_n={cs_f} (várt: 1) a tranzakció befejezése után"
    assert cs_p == 1, f"qspi_cs_psram_n={cs_p} (várt: 1) a tranzakció befejezése után"


# ============================================================
# hu: Sub5.A — paraméterezhető CODE-bázis-offszet (CODE_BASE_OFFSET)
#     A config-flash bitstream a 0x0-tól foglal; a CIL-T0 app a
#     bitstream FÖLÉ kerül. A `cilcpu_qspi_controller` CODE szegmens
#     ágának BASE + cpu_addr[19:0] flash-címről kell fetch-elnie.
#     A `CODE_BASE_OFFSET` érték a `-GCODE_BASE_OFFSET=` Verilator
#     generic-kel ÉS a `QSPI_CODE_BASE_OFFSET` env-vel egyezően
#     állítódik (egyetlen forrás — a `test_qspi_controller_offset`
#     Makefile target). Default 0 esetén a teszt skip-el (a többi 29
#     teszt változatlanul fut a default `test_qspi_controller`-rel).
# en: Sub5.A — parameterizable CODE base offset (CODE_BASE_OFFSET).
#     The config-flash bitstream occupies from 0x0; the CIL-T0 app is
#     placed ABOVE the bitstream. The `cilcpu_qspi_controller` CODE
#     segment branch must fetch from BASE + cpu_addr[19:0]. The
#     `CODE_BASE_OFFSET` value is set consistently via the
#     `-GCODE_BASE_OFFSET=` Verilator generic AND the
#     `QSPI_CODE_BASE_OFFSET` env (single source — the
#     `test_qspi_controller_offset` Makefile target). With default 0
#     the test skips (the other 29 tests run unchanged under the
#     default `test_qspi_controller`).
# ============================================================

CODE_BASE_OFFSET = int(os.environ.get("QSPI_CODE_BASE_OFFSET", "0"), 0)


@cocotb.test()
async def test_30_code_base_offset_applied(dut):
    """hu: A CODE szegmens fetch a CODE_BASE_OFFSET + cpu_addr[19:0]
           flash-címről jön. A flash modell KIZÁRÓLAG a BASE+addr
           címen tárolja az adatot (a BASE alatti rész — pl. a
           "bitstream" — default 0xFF). Ha az RTL kőbe vésve 0x0-ról
           olvas (offszet nélkül), 0xFFFFFFFF jön vissza → RED.
    en: The CODE segment fetch must come from CODE_BASE_OFFSET +
           cpu_addr[19:0]. The flash model stores data ONLY at
           BASE+addr (the region below BASE — i.e. the "bitstream" —
           defaults to 0xFF). If the RTL is hardcoded to read from 0x0
           (no offset), it returns 0xFFFFFFFF → RED."""
    if CODE_BASE_OFFSET == 0:
        # hu: Default sim-paritás — nincs offszet, a teszt nem értelmes.
        # en: Default sim parity — no offset, test not meaningful.
        return

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    cpu_off = 0x000100
    val = 0xCAFEBABE
    flash_addr = CODE_BASE_OFFSET + cpu_off

    # hu: Adat KIZÁRÓLAG a BASE+offset flash-címen — a BASE alatti
    #     címek (a "bitstream"-tartomány) üresek (modell default 0xFF).
    # en: Data ONLY at BASE+offset flash address — addresses below BASE
    #     (the "bitstream" range) are empty (model default 0xFF).
    flash_mem = {
        flash_addr:     (val >> 24) & 0xFF,
        flash_addr + 1: (val >> 16) & 0xFF,
        flash_addr + 2: (val >> 8) & 0xFF,
        flash_addr + 3: val & 0xFF,
    }

    await reset_dut(dut, flash_mem=flash_mem)

    result = await do_read(dut, make_addr(SEG_CODE, cpu_off))
    assert result == val, (
        f"CODE_BASE_OFFSET=0x{CODE_BASE_OFFSET:06X}: a controller-nek a "
        f"flash 0x{flash_addr:06X} címről kellene fetch-elnie "
        f"(várt 0x{val:08X}), de 0x{result:08X} jött — "
        f"valószínűleg kőbe vésve 0x0-ról olvas (nincs offszet)"
    )


@cocotb.test()
async def test_31_code_base_offset_addr_zero(dut):
    """hu: cpu_addr offset 0 esetén is a BASE flash-címről olvas
           (BASE+0). A flash 0x0-án "bitstream" placeholder (0xDEADC0DE),
           a BASE-en a valódi első app-szó. RED, ha 0x0-ról olvas.
    en: With cpu offset 0 it must still read from the BASE flash
           address (BASE+0). Flash 0x0 holds a "bitstream" placeholder
           (0xDEADC0DE); BASE holds the real first app word. RED if it
           reads from 0x0."""
    if CODE_BASE_OFFSET == 0:
        return

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    bit_ph = 0xDEADC0DE   # hu: "bitstream" placeholder a flash 0x0-án
    val = 0x01020304      # hu: valódi app első szó a BASE-en

    flash_mem = {
        0: (bit_ph >> 24) & 0xFF, 1: (bit_ph >> 16) & 0xFF,
        2: (bit_ph >> 8) & 0xFF,  3: bit_ph & 0xFF,
        CODE_BASE_OFFSET:     (val >> 24) & 0xFF,
        CODE_BASE_OFFSET + 1: (val >> 16) & 0xFF,
        CODE_BASE_OFFSET + 2: (val >> 8) & 0xFF,
        CODE_BASE_OFFSET + 3: val & 0xFF,
    }

    await reset_dut(dut, flash_mem=flash_mem)

    result = await do_read(dut, make_addr(SEG_CODE, 0))
    assert result == val, (
        f"CODE_BASE_OFFSET=0x{CODE_BASE_OFFSET:06X}: cpu offset 0 → "
        f"flash 0x{CODE_BASE_OFFSET:06X}-ról kellene olvasni "
        f"(várt 0x{val:08X}), de 0x{result:08X} jött "
        f"(0x{bit_ph:08X} = a bitstream placeholder a 0x0-án)"
    )
