# hu: CLI-CPU F2.5a Top-level Nano Core cocotb tesztek — Sub1 hatókör:
#     reset, boot, LDC + RET smoke. Aranypélda: TCpuNano (src/CilCpu.Sim).
#     Spec: rtl/src/CORE_SPEC-{hu,en}.md.
# en: CLI-CPU F2.5a Top-level Nano Core cocotb tests — Sub1 scope:
#     reset, boot, LDC + RET smoke. Golden reference: TCpuNano (src/CilCpu.Sim).
#     Spec: rtl/src/CORE_SPEC-{hu,en}.md.

import os
import subprocess
import tempfile

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

# ============================================================
# hu: CIL-T0 opcode bytes (cilcpu_defines.vh-ből)
# en: CIL-T0 opcode bytes (from cilcpu_defines.vh)
# ============================================================

OP_NOP        = 0x00
OP_LDC_I4_M1  = 0x15
OP_LDC_I4_0   = 0x16
OP_LDC_I4_1   = 0x17
OP_LDC_I4_2   = 0x18
OP_LDC_I4_3   = 0x19
OP_LDC_I4_4   = 0x1A
OP_LDC_I4_5   = 0x1B
OP_LDC_I4_6   = 0x1C
OP_LDC_I4_7   = 0x1D
OP_LDC_I4_8   = 0x1E
OP_LDC_I4_S   = 0x1F  # + 1 byte signed operand
OP_LDC_I4     = 0x20  # + 4 byte LE operand
OP_RET        = 0x2A
OP_ADD        = 0x58
OP_SUB        = 0x59
OP_MUL        = 0x5A
OP_DIV        = 0x5B
OP_REM        = 0x5D
OP_AND        = 0x5F
OP_OR         = 0x60
OP_XOR        = 0x61
OP_SHL        = 0x62
OP_SHR        = 0x63
OP_SHR_UN     = 0x64
OP_NEG        = 0x65
OP_NOT        = 0x66

# hu: Branch opcodes (Sub4) — mind 2-byte: opcode + signed offset
# en: Branch opcodes (Sub4) — all 2-byte: opcode + signed offset
OP_BR_S       = 0x2B
OP_BRFALSE_S  = 0x2C
OP_BRTRUE_S   = 0x2D
OP_BEQ_S      = 0x2E
OP_BGE_S      = 0x2F
OP_BGT_S      = 0x30
OP_BLE_S      = 0x31
OP_BLT_S      = 0x32
OP_BNE_UN_S   = 0x33

# hu: Speciális opkódok / en: Special opcodes
OP_BREAK      = 0xDD
OP_POP        = 0x26
OP_CALL       = 0x28
TRAP_INVALID_CALL_TARGET = 0x07
TRAP_CALL_DEPTH_EXCEEDED = 0x0A

# hu: Argument / local opcodes (Sub3) / en: Argument / local opcodes (Sub3)
OP_LDARG_0    = 0x02
OP_LDARG_1    = 0x03
OP_LDARG_2    = 0x04
OP_LDARG_3    = 0x05
OP_LDARG_S    = 0x0E
OP_STARG_S    = 0x10
OP_LDLOC_0    = 0x06
OP_LDLOC_1    = 0x07
OP_LDLOC_2    = 0x08
OP_LDLOC_3    = 0x09
OP_LDLOC_S    = 0x11
OP_STLOC_0    = 0x0A
OP_STLOC_1    = 0x0B
OP_STLOC_2    = 0x0C
OP_STLOC_3    = 0x0D
OP_STLOC_S    = 0x13

# hu: Trap kódok / en: Trap codes
TRAP_STACK_OVERFLOW      = 0x01
TRAP_STACK_UNDERFLOW     = 0x02
TRAP_INVALID_OPCODE      = 0x03
TRAP_INVALID_LOCAL       = 0x04
TRAP_INVALID_ARG         = 0x05
TRAP_INVALID_BRANCH      = 0x06
TRAP_DIV_BY_ZERO         = 0x08
TRAP_OVERFLOW            = 0x09
TRAP_DEBUG_BREAK         = 0x0B
TRAP_SRAM_OVERFLOW       = 0x0D

# ============================================================
# hu: QSPI Flash slave modell — a CODE szegmens betöltése
# en: QSPI Flash slave model — loads the CODE segment
# ============================================================

QSPI_CMD_FLASH_READ  = 0x6B
QSPI_CMD_PSRAM_READ  = 0xEB
QSPI_CMD_PSRAM_WRITE = 0x38
QSPI_DUMMY_FLASH     = 8
QSPI_DUMMY_PSRAM     = 6


class TQSPIFlashModel:
    """hu: QSPI Flash — read-only, a CODE bytes-ot tárolja byte-címen.
    en: QSPI Flash — read-only, stores CODE bytes by byte address."""

    def __init__(self, code_bytes=None):
        self.mem = {}
        if code_bytes:
            for offset, b in enumerate(code_bytes):
                self.mem[offset] = b

    def read_word(self, addr):
        """hu: 32-bit szó olvasás, big-endian byte sorrend a QSPI-n.
        en: 32-bit word read, big-endian byte order on QSPI.
        Megj.: a QSPI flash big-endian a wire-on, de a CIL-T0 little-endian
        a memóriában — a HW erre fordít."""
        b3 = self.mem.get(addr,     0xFF)
        b2 = self.mem.get(addr + 1, 0xFF)
        b1 = self.mem.get(addr + 2, 0xFF)
        b0 = self.mem.get(addr + 3, 0xFF)
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0


_slave_task = None


async def qspi_flash_driver(dut, flash):
    """hu: QSPI Flash slave coroutine — figyeli a CS#, CLK, DQ jeleket,
        és a 0x6B Flash Read parancsra válaszol.
    en: QSPI Flash slave coroutine — watches CS#, CLK, DQ signals
        and responds to the 0x6B Flash Read command."""

    while True:
        await RisingEdge(dut.clk)
        try:
            cs_flash = int(dut.qspi_cs_flash_n.value)
        except ValueError:
            continue

        if cs_flash != 0:
            continue

        # hu: 1. CMD fázis — 8 bit SPI
        cmd = 0
        for i in range(8):
            await RisingEdge(dut.qspi_clk)
            bit = int(dut.qspi_dq_out.value) & 0x01
            cmd = (cmd << 1) | bit

        if cmd != QSPI_CMD_FLASH_READ:
            # hu: A Sub1-ben csak 0x6B-t várunk
            while int(dut.qspi_cs_flash_n.value) == 0:
                await RisingEdge(dut.clk)
            continue

        # hu: 2. ADDR fázis — 24 bit SPI (1 bit/CLK)
        addr = 0
        for i in range(24):
            await RisingEdge(dut.qspi_clk)
            bit = int(dut.qspi_dq_out.value) & 0x01
            addr = (addr << 1) | bit

        # hu: 3. DUMMY fázis — 8 QSPI ciklus
        for i in range(QSPI_DUMMY_FLASH):
            await RisingEdge(dut.qspi_clk)

        # hu: 4. DATA fázis — 32 bit, quad mód, falling edge-en hajt
        word = flash.read_word(addr)
        for i in range(8):
            await FallingEdge(dut.qspi_clk)
            nibble = (word >> (28 - i * 4)) & 0x0F
            dut.qspi_dq_in.value = nibble

        # hu: Várjuk meg, amíg CS# magasra megy
        while int(dut.qspi_cs_flash_n.value) == 0:
            await RisingEdge(dut.clk)


# ============================================================
# hu: Segédfüggvények
# en: Helpers
# ============================================================


# hu: F3 egységes on-chip SRAM — STACK_BASE (cilcpu_defines.vh) szóban: a CODE
#     régió [0, STACK_BASE) az on-chip SRAM-ban, fölötte a STACK. A CODE-ot
#     backdoor-poke-kal töltjük (a core onnan fetch-el; a QSPI nem érintett).
# en: F3 unified on-chip SRAM — STACK_BASE (cilcpu_defines.vh) in words: CODE
#     region [0, STACK_BASE) in the on-chip SRAM, STACK above. CODE is loaded by
#     backdoor poke (the core fetches from there; the QSPI is untouched).
STACK_BASE = 0x0800
_CODE_WORDS = STACK_BASE // 4


def _preload_core_sram(dut, code_bytes):
    """hu: a programot az on-chip r_sram CODE-régiójába írja (LE szavak). A CODE
        régiót előbb 0xFF-fel tölti (a régi flash-default reprodukciója: olvasatlan
        cím → INVALID_OPCODE, ha a végrehajtás túlfut)."""
    for k in range(_CODE_WORDS):
        dut.u_core.r_sram[k].value = 0xFFFFFFFF
    b = list(code_bytes or [])
    while len(b) % 4 != 0:
        b.append(0x00)
    for k in range(0, len(b), 4):
        word = b[k] | (b[k + 1] << 8) | (b[k + 2] << 16) | (b[k + 3] << 24)
        dut.u_core.r_sram[k // 4].value = word


async def reset_dut(dut, code_bytes=None):
    """hu: 3-ciklusú reset. F3: a CODE-ot az on-chip SRAM-ba backdoor-poke-oljuk
        (a core onnan fetch-el). A QSPI flash slave változatlanul indul, de a core
        már nem hajtja a külső buszt → tétlen marad (kompatibilitás).
    en: 3-cycle reset. F3: CODE is backdoor-poked into the on-chip SRAM (the core
        fetches from there). The QSPI flash slave still starts but the core no
        longer drives the external bus → it stays idle (compatibility)."""
    global _slave_task

    if _slave_task is not None and not _slave_task.done():
        _slave_task.cancel()
        try:
            await _slave_task
        except BaseException:
            pass
    _slave_task = None

    flash = TQSPIFlashModel(code_bytes)
    _slave_task = cocotb.start_soon(qspi_flash_driver(dut, flash))

    dut.rst_n.value             = 0
    dut.i_boot_pc.value         = 0
    dut.i_boot_arg_count.value  = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value      = 0
    dut.i_boot_arg_data.value   = 0
    dut.i_boot_arg_valid.value  = 0
    dut.qspi_dq_in.value        = 0

    for _ in range(3):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)

    # hu: F3 — CODE betöltése az on-chip SRAM-ba (reset után, a memória nem
    #     resetelődik). Boot előtt kell, hogy az 1. fetch már a kódot lássa.
    if code_bytes is not None:
        _preload_core_sram(dut, code_bytes)

    return flash


async def boot_and_run(dut, code_bytes, boot_pc=0, args=None, locals_count=0,
                       max_cycles=2000):
    """hu: Kompletten boot + futtatás. Visszatér a halt-kor érvényes
        (return_value, trap_code, halt, trap, pc) tuple-lel.
    en: Full boot + run. Returns (return_value, trap_code, halt, trap, pc)
        tuple at halt/trap."""
    args = args or []

    await reset_dut(dut, code_bytes)

    # hu: Boot indítás
    dut.i_boot_pc.value          = boot_pc
    dut.i_boot_arg_count.value   = len(args)
    dut.i_boot_local_count.value = locals_count
    dut.i_boot_start.value       = 1
    await RisingEdge(dut.clk)
    dut.i_boot_start.value       = 0

    # hu: Args streaming — vár o_boot_arg_ready=1-re, akkor érvényes
    for arg_val in args:
        # hu: Várjuk a ready jelet
        for _ in range(100):
            await RisingEdge(dut.clk)
            try:
                if int(dut.o_boot_arg_ready.value) == 1:
                    break
            except ValueError:
                pass
        else:
            raise TimeoutError("o_boot_arg_ready never asserted")

        dut.i_boot_arg_data.value  = arg_val & 0xFFFFFFFF
        dut.i_boot_arg_valid.value = 1
        await RisingEdge(dut.clk)
        dut.i_boot_arg_valid.value = 0

    # hu: Futás — várjuk a halt vagy trap jelet
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        try:
            halt = int(dut.o_halt.value)
            trap = int(dut.o_trap.value)
        except ValueError:
            halt = 0
            trap = 0

        if halt or trap:
            return (
                int(dut.o_return_value.value) if halt else 0,
                int(dut.o_trap_code.value) if trap else 0,
                halt,
                trap,
                int(dut.o_pc.value),
            )

    raise TimeoutError(
        f"core didn't halt or trap within {max_cycles} cycles"
    )


# ============================================================
# hu: Tesztek — Sub1 hatókör (reset/boot/LDC+RET)
# en: Tests — Sub1 scope (reset/boot/LDC+RET)
# ============================================================


@cocotb.test()
async def test_01_reset_state(dut):
    """hu: Reset állapot — minden output reg 0.
    en: Reset state — all output regs are 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    assert int(dut.o_halt.value) == 0, "o_halt should be 0 after reset"
    assert int(dut.o_trap.value) == 0, "o_trap should be 0 after reset"
    assert int(dut.o_trap_code.value) == 0, "o_trap_code should be 0 after reset"
    assert int(dut.o_pc.value) == 0, "o_pc should be 0 after reset"
    assert int(dut.o_return_value.value) == 0, \
        "o_return_value should be 0 after reset"


@cocotb.test()
async def test_02_idle_no_boot(dut):
    """hu: Reset után, boot nélkül a core nem halt-ol és nem trap-el.
    en: After reset, no boot, the core does not halt or trap."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    for _ in range(50):
        await RisingEdge(dut.clk)
        assert int(dut.o_halt.value) == 0, "o_halt rose without boot"
        assert int(dut.o_trap.value) == 0, "o_trap rose without boot"


@cocotb.test()
async def test_03_ldc_i4_5_ret(dut):
    """hu: LDC.I4.5 + RET → halt, return_value=5. A legalapvetőbb futás.
    en: LDC.I4.5 + RET → halt, return_value=5. The most basic run."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_5, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert trap == 0, f"unexpected trap 0x{tc:02X} at pc=0x{pc:06X}"
    assert rv == 5, f"return_value = {rv}, expected 5"


@cocotb.test()
async def test_04_ldc_i4_0_ret(dut):
    """hu: LDC.I4.0 + RET → 0.
    en: LDC.I4.0 + RET → 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_0, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 0, f"return_value = {rv}, expected 0"


@cocotb.test()
async def test_05_ldc_i4_m1_ret(dut):
    """hu: LDC.I4.M1 + RET → -1 (0xFFFFFFFF).
    en: LDC.I4.M1 + RET → -1 (0xFFFFFFFF)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_M1, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 0xFFFFFFFF, f"return_value = 0x{rv:08X}, expected 0xFFFFFFFF"


@cocotb.test()
async def test_06_ldc_i4_s_42_ret(dut):
    """hu: LDC.I4.S 42 + RET → 42 (1-byte signed immediate).
    en: LDC.I4.S 42 + RET → 42 (1-byte signed immediate)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_S, 42, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_07_ldc_i4_s_negative(dut):
    """hu: LDC.I4.S -3 + RET → 0xFFFFFFFD (signed extension).
    en: LDC.I4.S -3 + RET → 0xFFFFFFFD (signed extension)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_S, 0xFD, OP_RET])  # -3
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 0xFFFFFFFD, f"return_value = 0x{rv:08X}, expected 0xFFFFFFFD"


@cocotb.test()
async def test_08_ldc_i4_full(dut):
    """hu: LDC.I4 0xDEADBEEF + RET → 0xDEADBEEF (4-byte LE immediate).
        Sub2.2: az APPEND általánosított minden r_fetch_count értékre
        (0..4), így az 5-byte slide utáni cnt=3-ra is felülír 4-byte
        ablakot.
    en: LDC.I4 0xDEADBEEF + RET → 0xDEADBEEF (4-byte LE immediate).
        Sub2.2: APPEND is generalized for any r_fetch_count (0..4),
        so cnt=3 (after a 5-byte slide) accepts the next 4-byte word."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([
        OP_LDC_I4,
        0xEF, 0xBE, 0xAD, 0xDE,  # LE
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 0xDEADBEEF, f"return_value = 0x{rv:08X}, expected 0xDEADBEEF"


@cocotb.test()
async def test_08b_ldc_i4_with_slide(dut):
    """hu: Két LDC.I4 egymás után — kifejezetten az APPEND general count
        utat triggereli. Az 1. LDC.I4 (5 byte) elfogyasztásával cnt=3
        marad, a 2. LDC.I4 dekódolásához +4 byte appendelendő cnt=3 → 7
        eredménnyel. Sub2.1 ezt nem tudná, Sub2.2 igen.
    en: Two LDC.I4 in a row — specifically triggers the APPEND
        general-count path. The first LDC.I4 (5 bytes) leaves cnt=3,
        the second LDC.I4 needs +4 bytes appended at cnt=3 → 7."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([
        OP_LDC_I4, 0x01, 0x00, 0x00, 0x00,  # push 1
        OP_LDC_I4, 0x02, 0x00, 0x00, 0x00,  # push 2
        OP_ADD,                              # 1 + 2
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 3, f"return_value = {rv}, expected 3"


@cocotb.test()
async def test_09_halt_latched(dut):
    """hu: Halt után az o_halt 1-en marad.
    en: After halt, o_halt stays at 1."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4_5, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, "core didn't halt"

    for _ in range(20):
        await RisingEdge(dut.clk)
        assert int(dut.o_halt.value) == 1, "o_halt dropped after halt"
        assert int(dut.o_return_value.value) == 5, \
            "return_value changed after halt"


# ============================================================
# hu: Sub2.1 — Fetch addresszálás reprodukciós teszt (TDD piros)
# en: Sub2.1 — Fetch addressing reproduction test (TDD red)
# ============================================================


@cocotb.test()
async def test_2x_two_fetch_correct_addressing(dut):
    """hu: Két fetch egymás után — a 2. addr-nek 4-nek kell lennie, nem 0.
        A program 8 byte: LDC.I4.S 2 + LDC.I4.S 3 + RET + 3x NOP filler.
        A teszt sikeres ha 2 LDC + RET fut le helyes return_value-val (3).
        Ez a Sub2.1 fetch addresszálás bug minimális reprodukciója.
    en: Two consecutive fetches — 2nd addr must be 4, not 0. Program is
        8 bytes: LDC.I4.S 2 + LDC.I4.S 3 + RET + 3x NOP filler.
        Passes if 2 LDC + RET runs with return_value=3.
        Minimal reproduction for Sub2.1 fetch addressing bug."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_S, 2,     # 2 byte
        OP_LDC_I4_S, 3,     # 2 byte
        OP_RET,             # 1 byte (visszaad TOS=3)
        OP_NOP, OP_NOP, OP_NOP,  # filler hogy 8 byte legyen
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 3, f"return_value = {rv}, expected 3 (TOS=3 RET-kor)"


# ============================================================
# hu: Sub2 — Aritmetikai tesztek
# en: Sub2 — Arithmetic tests
# ============================================================


def _ldc_s(value):
    """hu: LDC.I4.S byte sorozat egy 8-bit signed konstansra.
    en: LDC.I4.S byte sequence for an 8-bit signed constant."""
    return bytes([OP_LDC_I4_S, value & 0xFF])


async def _run_binary_op(dut, op_code, a, b, expected_rv,
                          expected_trap_code=None):
    """hu: LDC.I4.S a, LDC.I4.S b, OP, RET program futtatása.
    en: Run LDC.I4.S a, LDC.I4.S b, OP, RET program."""
    program = _ldc_s(a) + _ldc_s(b) + bytes([op_code, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    if expected_trap_code is not None:
        assert trap == 1, \
            f"expected trap 0x{expected_trap_code:02X}, got halt={halt}"
        assert tc == expected_trap_code, \
            f"trap_code = 0x{tc:02X}, expected 0x{expected_trap_code:02X}"
    else:
        assert halt == 1, \
            f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
        assert rv == (expected_rv & 0xFFFFFFFF), \
            f"return_value = 0x{rv:08X}, expected 0x{expected_rv & 0xFFFFFFFF:08X}"


async def _run_unary_op(dut, op_code, a, expected_rv):
    """hu: LDC.I4.S a, OP, RET futtatása.
    en: Run LDC.I4.S a, OP, RET."""
    program = _ldc_s(a) + bytes([op_code, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == (expected_rv & 0xFFFFFFFF), \
        f"return_value = 0x{rv:08X}, expected 0x{expected_rv & 0xFFFFFFFF:08X}"


@cocotb.test()
async def test_11_add_2_3(dut):
    """hu: 2 + 3 = 5. Sub2.1 fix után megbízhatóan zöld.
    en: 2 + 3 = 5. Reliably green after Sub2.1 fix."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_ADD, 2, 3, 5)


# hu: F2.8 #6 — indirekt memória opkódok (a wrapper-integráció előfeltétele).
# en: F2.8 #6 — indirect memory opcodes (prerequisite for wrapper integration).
OP_LDIND_I4 = 0x4A
OP_STIND_I4 = 0x54


@cocotb.test()
async def test_50_stind_ldind_indirect_addressing(dut):
    """hu: LDIND/STIND TOS-cím használat. A hibát úgy exponáljuk, hogy KÉT
        KÜLÖNBÖZŐ címre írunk (100, 104), majd az ELSŐT (100) olvassuk vissza.
        Helyes IND-címzésnél a két cím független → mem[100]=42 marad.
        Törött címzésnél (addr_calc IND → FP+12) mindkét write a FP+12-re megy,
        a 2. (99) felülírja az 1.-t → a visszaolvasás 99 lenne (RED).
    en: LDIND/STIND TOS-address use. Expose the bug by writing TWO DISTINCT
        addresses (100, 104) then reading back the FIRST (100). With correct
        indirect addressing the two are independent → mem[100]=42 survives.
        With broken addressing (addr_calc IND → FP+12) both writes hit FP+12,
        the 2nd (99) overwrites the 1st → readback would be 99 (RED)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        _ldc_s(100) + _ldc_s(42) + bytes([OP_STIND_I4])   # mem[100] = 42
        + _ldc_s(104) + _ldc_s(99) + bytes([OP_STIND_I4]) # mem[104] = 99
        + _ldc_s(100) + bytes([OP_LDIND_I4, OP_RET])      # return mem[100]
    )
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 42, \
        f"mem[100] visszaolvasás = {rv} (0x{rv:08X}), várt 42 — IND-címzés hibás?"


def _ldc_i4(value):
    """hu: LDC.I4 (0x20) + 4 byte LE immediate — teljes 32-bit konstans.
    en: LDC.I4 (0x20) + 4-byte LE immediate — full 32-bit constant."""
    v = value & 0xFFFFFFFF
    return bytes([OP_LDC_I4, v & 0xFF, (v >> 8) & 0xFF,
                  (v >> 16) & 0xFF, (v >> 24) & 0xFF])


# hu: F2.8 #6.2 — szegmens-dekódolás: a 0xF szegmensű (MMIO) cím a core
#     külső MMIO-master buszára kerül (architektúra B), nem az SRAM-ra.
#     A perifériát a wrapper dekódolja; a core csak a buszt hajtja.
# en: F2.8 #6.2 — segment decode: the 0xF (MMIO) segment goes to the core's
#     external MMIO master bus (architecture B), not to SRAM. The wrapper
#     decodes the peripheral; the core only drives the bus.
MMIO_MAILBOX = 0xF0000100
MMIO_GPIO    = 0xF0000200


@cocotb.test()
async def test_55_stind_mmio_write_drives_master_bus(dut):
    """hu: STIND egy 0xF szegmensű címre → MMIO master busz write pulzus
        (o_mmio_we / o_mmio_addr / o_mmio_wdata), NEM SRAM-írás. Egy monitor
        koroutin elkapja az 1-ciklusos pulzust futás közben.
    en: STIND to a 0xF-segment address → MMIO master bus write pulse
        (o_mmio_we / o_mmio_addr / o_mmio_wdata), NOT an SRAM write. A
        monitor coroutine catches the 1-cycle pulse during the run."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    captured = []

    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            try:
                if int(dut.o_mmio_we.value) == 1:
                    captured.append((int(dut.o_mmio_addr.value),
                                     int(dut.o_mmio_wdata.value)))
            except (ValueError, AttributeError):
                pass

    cocotb.start_soon(monitor())

    # hu: LDC cím, LDC 42, STIND → MMIO write; majd LDC 7, RET (return 7).
    program = (_ldc_i4(MMIO_MAILBOX) + _ldc_s(42) + bytes([OP_STIND_I4])
               + _ldc_s(7) + bytes([OP_RET]))
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 7, f"return_value = {rv}, várt 7"
    assert len(captured) == 1, \
        f"pontosan 1 MMIO write pulzus várt, kaptam {len(captured)}"
    addr, wdata = captured[0]
    assert addr == MMIO_MAILBOX, \
        f"o_mmio_addr = 0x{addr:08X}, várt 0x{MMIO_MAILBOX:08X}"
    assert wdata == 42, f"o_mmio_wdata = {wdata}, várt 42"


@cocotb.test()
async def test_56_ldind_mmio_read_from_master_bus(dut):
    """hu: LDIND egy 0xF szegmensű címről → o_mmio_re pulzus + a slave
        i_mmio_rdata értékének push-ja (NEM SRAM-olvasás).
    en: LDIND from a 0xF-segment address → o_mmio_re pulse + push of the
        slave's i_mmio_rdata value (NOT an SRAM read)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # hu: a "periféria" konstans értéket ad vissza a buszon
    dut.i_mmio_rdata.value = 0x0BADF00D

    program = _ldc_i4(MMIO_GPIO) + bytes([OP_LDIND_I4, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)

    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 0x0BADF00D, \
        f"return_value = 0x{rv:08X}, várt 0x0BADF00D (MMIO read)"


@cocotb.test()
async def test_12_sub_10_4(dut):
    """hu: 10 - 4 = 6. en: 10 - 4 = 6."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_SUB, 10, 4, 6)


@cocotb.test()
async def test_13_mul_7_8(dut):
    """hu: 7 * 8 = 56. en: 7 * 8 = 56."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_MUL, 7, 8, 56)


@cocotb.test()
async def test_14_div_20_5(dut):
    """hu: 20 / 5 = 4. en: 20 / 5 = 4."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_DIV, 20, 5, 4)


@cocotb.test()
async def test_15_div_zero_trap(dut):
    """hu: 5 / 0 → TRAP_DIV_BY_ZERO. en: 5 / 0 → TRAP_DIV_BY_ZERO."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_DIV, 5, 0, 0,
                          expected_trap_code=TRAP_DIV_BY_ZERO)


@cocotb.test()
async def test_16_rem_17_5(dut):
    """hu: 17 % 5 = 2. en: 17 % 5 = 2."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_REM, 17, 5, 2)


@cocotb.test()
async def test_17_and_0xC_0xA(dut):
    """hu: 0xC AND 0xA = 0x8. en: 0xC AND 0xA = 0x8."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_AND, 0x0C, 0x0A, 0x08)


@cocotb.test()
async def test_18_or_0xC_0xA(dut):
    """hu: 0xC OR 0xA = 0xE. en: 0xC OR 0xA = 0xE."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_OR, 0x0C, 0x0A, 0x0E)


@cocotb.test()
async def test_19_xor_0xC_0xA(dut):
    """hu: 0xC XOR 0xA = 0x6. en: 0xC XOR 0xA = 0x6."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_XOR, 0x0C, 0x0A, 0x06)


@cocotb.test()
async def test_20_shl_1_4(dut):
    """hu: 1 << 4 = 16. en: 1 << 4 = 16."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_binary_op(dut, OP_SHL, 1, 4, 16)


@cocotb.test()
async def test_21_neg_5(dut):
    """hu: -5 → 0xFFFFFFFB (unary).
    en: -5 → 0xFFFFFFFB (unary)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_unary_op(dut, OP_NEG, 5, 0xFFFFFFFB)


@cocotb.test()
async def test_22_not_0(dut):
    """hu: ~0 = 0xFFFFFFFF (unary).
    en: ~0 = 0xFFFFFFFF (unary)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _run_unary_op(dut, OP_NOT, 0, 0xFFFFFFFF)


@cocotb.test()
async def test_25_div_overflow(dut):
    """hu: INT_MIN / -1 = overflow trap (0x80000000 / 0xFFFFFFFF).
        Az ALU detektálja az aritmetikai overflow-t, és TRAP_OVERFLOW-t emel.
    en: INT_MIN / -1 = overflow trap (0x80000000 / 0xFFFFFFFF).
        ALU catches the arithmetic overflow and raises TRAP_OVERFLOW."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4, 0x00, 0x00, 0x00, 0x80,  # LDC.I4 INT_MIN (0x80000000, LE)
        OP_LDC_I4_M1,                        # LDC.I4_M1 = -1
        OP_DIV,
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert trap == 1, f"expected overflow trap, got halt={halt}"
    assert tc == TRAP_OVERFLOW, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_OVERFLOW:02X} (OVERFLOW)"


# ============================================================
# hu: Boot args streaming (Sub3-ra vár LDARG impl)
# en: Boot args streaming (waits for Sub3 LDARG impl)
# ============================================================


@cocotb.test()
async def test_10_boot_args_streaming_no_deadlock(dut):
    """hu: 2 arg boot — Sub1 csak az args streaming nem-deadlock-jét
        ellenőrzi. A LDARG.0 + RET lefutása Sub3-ban érkezik. Itt
        elfogadjuk az invalid-opcode trap-et is, mert LDARG még nincs
        implementálva — a fontos, hogy a boot lezárul és a core fetch-elni
        kezd (timeout NEM).
    en: 2-arg boot — Sub1 only checks the args-streaming has no deadlock.
        The LDARG.0 + RET path comes in Sub3. We accept invalid-opcode
        trap here, since LDARG isn't implemented yet — the key is that
        boot completes and the core starts fetching (timeout is the only
        unacceptable outcome)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([0x02, OP_RET])  # LDARG.0, RET
    try:
        rv, tc, halt, trap, pc = await boot_and_run(
            dut, program, args=[99, 88], max_cycles=3000
        )
    except TimeoutError as ex:
        raise AssertionError(
            f"boot deadlock: {ex} — args streaming did not progress"
        )

    # hu: Sub1: halt VAGY trap elfogadott. Sub3: csak halt + rv==99.
    # en: Sub1: halt OR trap accepted. Sub3: halt + rv==99 only.
    assert halt == 1 or trap == 1, "neither halt nor trap"


# ============================================================
# hu: Sub3 — LDARG / STARG / LDLOC / STLOC + range trap
# en: Sub3 — LDARG / STARG / LDLOC / STLOC + range trap
# ============================================================


@cocotb.test()
async def test_30_ldarg_0_returns(dut):
    """hu: boot args=[99], LDARG.0 + RET → 99.
    en: boot args=[99], LDARG.0 + RET → 99."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDARG_0, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program, args=[99])
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 99, f"return_value = {rv}, expected 99"


@cocotb.test()
async def test_31_ldarg_3_returns(dut):
    """hu: boot args=[10,20,30,40], LDARG.3 + RET → 40.
    en: boot args=[10,20,30,40], LDARG.3 + RET → 40."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDARG_3, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, args=[10, 20, 30, 40]
    )
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 40, f"return_value = {rv}, expected 40"


@cocotb.test()
async def test_32_ldarg_s_returns(dut):
    """hu: boot args=[0..15], LDARG.S 15 + RET → 15.
    en: boot args=[0..15], LDARG.S 15 + RET → 15."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDARG_S, 15, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, args=list(range(16))
    )
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 15, f"return_value = {rv}, expected 15"


@cocotb.test()
async def test_33_starg_s_then_ldarg(dut):
    """hu: STARG.S 0 felülírja args[0]-t 7-tel, aztán LDARG.0 visszaolvas.
    en: STARG.S 0 overwrites args[0] with 7, then LDARG.0 reads back."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_S, 7,  # push 7
        OP_STARG_S, 0,   # args[0] = 7
        OP_LDARG_0,      # push args[0]
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program, args=[5])
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 7, f"return_value = {rv}, expected 7"


@cocotb.test()
async def test_34_stloc_ldloc_roundtrip(dut):
    """hu: STLOC.0 42, LDLOC.0, RET → 42.
    en: STLOC.0 42, LDLOC.0, RET → 42."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_S, 42,  # push 42
        OP_STLOC_0,       # locals[0] = 42
        OP_LDLOC_0,       # push locals[0]
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, locals_count=1
    )
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_35_invalid_arg_trap(dut):
    """hu: LDARG.S 5 amikor arg_count=2 → TRAP_INVALID_ARG (0x05).
    en: LDARG.S 5 with arg_count=2 → TRAP_INVALID_ARG (0x05)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDARG_S, 5, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program, args=[1, 2])
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_INVALID_ARG, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_INVALID_ARG:02X}"


@cocotb.test()
async def test_36_invalid_local_trap(dut):
    """hu: LDLOC.S 5 amikor local_count=2 → TRAP_INVALID_LOCAL (0x04).
    en: LDLOC.S 5 with local_count=2 → TRAP_INVALID_LOCAL (0x04)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDLOC_S, 5, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, locals_count=2
    )
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_INVALID_LOCAL, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_INVALID_LOCAL:02X}"


# ============================================================
# hu: Sub4 — Branch (BR_S / BRFALSE_S / BRTRUE_S / BEQ_S / BLT_S / BGE_S)
# en: Sub4 — Branch (BR_S / BRFALSE_S / BRTRUE_S / BEQ_S / BLT_S / BGE_S)
# ============================================================


@cocotb.test()
async def test_40_br_s_forward(dut):
    """hu: BR_S +3 átugorja a 3 byte-ot (LDC.I4_S 99 + RET), majd LDC 42.
        Layout:
          @0: BR_S +3       (offset = 3 byte = +3 a következő utasítástól)
          @2: LDC.I4_S 99   (3 byte átugorva: ezt nem éri el)
          @4: RET           (... és ezt sem)
          @5: LDC.I4_S 42   (ide ugrik)
          @7: RET           (és ez ad vissza 42-t)
    en: BR_S +3 skips 3 bytes (LDC.I4_S 99 + RET), executes LDC 42."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_BR_S, 3,            # @0: branch +3 (target @5)
        OP_LDC_I4_S, 99,       # @2: skipped
        OP_RET,                # @4: skipped
        OP_LDC_I4_S, 42,       # @5: target
        OP_RET,                # @7
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_41_brtrue_taken(dut):
    """hu: LDC.I4_1 + BRTRUE_S +2 → branch (1 != 0).
    en: LDC.I4_1 + BRTRUE_S +2 → branch (1 != 0)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_1,           # @0: push 1
        OP_BRTRUE_S, 2,        # @1: branch +2 (target @5)
        OP_LDC_I4_S, 99,       # @3: skipped
        OP_LDC_I4_S, 42,       # @5: target
        OP_RET,                # @7
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_42_brfalse_not_taken(dut):
    """hu: LDC.I4_1 + BRFALSE_S +2 → fall-through (1 != 0).
    en: LDC.I4_1 + BRFALSE_S +2 → fall-through (1 != 0)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_1,           # @0: push 1
        OP_BRFALSE_S, 2,       # @1: NOT taken
        OP_LDC_I4_S, 42,       # @3: fall-through
        OP_RET,                # @5
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_43_beq_s_taken(dut):
    """hu: LDC.I4_5 + LDC.I4_5 + BEQ_S +2 → branch (5==5).
    en: LDC.I4_5 + LDC.I4_5 + BEQ_S +2 → branch (5==5)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_5,           # @0: push 5
        OP_LDC_I4_5,           # @1: push 5
        OP_BEQ_S, 2,           # @2: a==b → branch +2 (target @6)
        OP_LDC_I4_S, 99,       # @4: skipped
        OP_LDC_I4_S, 42,       # @6: target
        OP_RET,                # @8
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_44_blt_s_signed(dut):
    """hu: -1 < 1 → branch. LDC.I4_M1 + LDC.I4_1 + BLT_S +2.
    en: -1 < 1 → branch. LDC.I4_M1 + LDC.I4_1 + BLT_S +2."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_M1,          # @0: push -1
        OP_LDC_I4_1,           # @1: push 1
        OP_BLT_S, 2,           # @2: -1 < 1 → branch
        OP_LDC_I4_S, 99,       # @4: skipped
        OP_LDC_I4_S, 42,       # @6: target
        OP_RET,                # @8
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_45_bge_s_signed(dut):
    """hu: 5 >= 5 → branch. LDC.I4_5 + LDC.I4_5 + BGE_S +2.
    en: 5 >= 5 → branch. LDC.I4_5 + LDC.I4_5 + BGE_S +2."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_LDC_I4_5,           # @0: push 5
        OP_LDC_I4_5,           # @1: push 5
        OP_BGE_S, 2,           # @2: 5 >= 5 → branch
        OP_LDC_I4_S, 99,       # @4: skipped
        OP_LDC_I4_S, 42,       # @6: target
        OP_RET,                # @8
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert halt == 1, f"core didn't halt (trap={trap}, code=0x{tc:02X})"
    assert rv == 42, f"return_value = {rv}, expected 42"


@cocotb.test()
async def test_46_branch_negative_target(dut):
    """hu: BR_S -100 (PC=0+2-100 = negatív) → TRAP_INVALID_BRANCH.
        F2.5a egyszerűsítés: csak negatív branch target trap-elt;
        pozitív túlcsordulás a következő ciklus fetch-én detektálódik
        (0xFF byte → TRAP_INVALID_OPCODE).
    en: BR_S -100 (PC=0+2-100 = negative) → TRAP_INVALID_BRANCH.
        F2.5a simplification: only negative branch target traps;
        positive overflow detected on next-cycle fetch (0xFF byte →
        TRAP_INVALID_OPCODE)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([
        OP_BR_S, 0x9C,  # BR_S -100 (signed: 0x9C = -100)
        OP_RET,
    ])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_INVALID_BRANCH, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_INVALID_BRANCH:02X} (INVALID_BRANCH)"


# ============================================================
# hu: Sub6 — Trap aggregátor + speciális trap-ek
# en: Sub6 — Trap aggregator + special traps
# ============================================================


@cocotb.test()
async def test_60_stack_overflow(dut):
    """hu: 65 db LDC.I4_0 → TRAP_STACK_OVERFLOW (a max eval mélység 64).
    en: 65 LDC.I4_0 → TRAP_STACK_OVERFLOW (max eval depth 64)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_LDC_I4_0] * 65 + [OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program, max_cycles=5000)
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_STACK_OVERFLOW, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_STACK_OVERFLOW:02X}"


@cocotb.test()
async def test_61_stack_underflow(dut):
    """hu: POP üres stack-en → TRAP_STACK_UNDERFLOW.
    en: POP on empty stack → TRAP_STACK_UNDERFLOW."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_POP, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_STACK_UNDERFLOW, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_STACK_UNDERFLOW:02X}"


@cocotb.test()
async def test_62_op_break(dut):
    """hu: OP_BREAK (0xDD) → TRAP_DEBUG_BREAK (0x0B).
    en: OP_BREAK (0xDD) → TRAP_DEBUG_BREAK (0x0B)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([OP_BREAK, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_DEBUG_BREAK, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_DEBUG_BREAK:02X}"


@cocotb.test()
async def test_63_invalid_opcode(dut):
    """hu: 0xFF byte → TRAP_INVALID_OPCODE (0x03).
    en: 0xFF byte → TRAP_INVALID_OPCODE (0x03)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    program = bytes([0xFF, OP_RET])
    rv, tc, halt, trap, pc = await boot_and_run(dut, program)
    assert trap == 1, f"expected trap, got halt={halt}"
    assert tc == TRAP_INVALID_OPCODE, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_INVALID_OPCODE:02X}"


# ============================================================
# hu: Sub5 — CALL / RET non-root frame manager
#     Az F1 aranypéldát követjük (TExecutor.cs ExecuteCall/ExecuteRet,
#     TCpuNano.PushCallFrame/PopCallFrame). A callee header layout
#     8 byte: magic(1) + arg_count(1) + local_count(1) + max_stack(1) +
#     code_size(2 LE) + reserved(2). A HW az első 3 byte-ot dolgozza
#     (magic, arg_count, local_count); max_stack és code_size F5+-re
#     marad.
# en: Sub5 — CALL / RET non-root frame manager
#     Following the F1 golden reference (TExecutor.cs ExecuteCall/Ret,
#     TCpuNano.Push/PopCallFrame). Callee 8-byte header: magic(1) +
#     arg_count(1) + local_count(1) + max_stack(1) + code_size(2 LE) +
#     reserved(2). The HW only consumes the first 3 bytes; max_stack
#     and code_size are deferred to F5+.
# ============================================================


def _method_header(arg_count, local_count, max_stack=4, code_size=0):
    """hu: 8-byte CIL-T0 method header (TMethodHeader formátum).
    en: 8-byte CIL-T0 method header (TMethodHeader format)."""
    return bytes([
        0xFE,                                  # magic
        arg_count & 0xFF,
        local_count & 0xFF,
        max_stack & 0xFF,
        code_size & 0xFF, (code_size >> 8) & 0xFF,  # LE u16
        0x00, 0x00,                            # reserved
    ])


def _call_op(rva):
    """hu: OP_CALL + 4-byte LE RVA operand.
    en: OP_CALL + 4-byte LE RVA operand."""
    return bytes([
        OP_CALL,
        rva & 0xFF, (rva >> 8) & 0xFF, (rva >> 16) & 0xFF, (rva >> 24) & 0xFF,
    ])


@cocotb.test()
async def test_50_call_simple_add_2_3(dut):
    """hu: Add(a, b) hívás 2 arg-gal — Add(2, 3) = 5.
        Layout:
          @0..7:   add header (arg_count=2, local_count=0, code_size=4)
          @8..11:  add body: LDARG.0, LDARG.1, ADD, RET
          @12..19: caller (boot_pc=12, no args, no locals)
                   LDC.I4_2, LDC.I4_3, CALL 0, RET
    en: Add(a, b) call with 2 args — Add(2, 3) = 5."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        # @0..7: add() header
        _method_header(arg_count=2, local_count=0, max_stack=2, code_size=4)
        # @8..11: add body
        + bytes([OP_LDARG_0, OP_LDARG_1, OP_ADD, OP_RET])
        # @12..19: caller (boot_pc=12)
        + bytes([OP_LDC_I4_2, OP_LDC_I4_3])
        + _call_op(0)
        + bytes([OP_RET])
    )
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, boot_pc=12, max_cycles=10000
    )
    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 5, f"return_value = {rv}, expected 5 (Add(2,3))"


@cocotb.test()
async def test_51_call_returns_then_continues(dut):
    """hu: Caller folytatja a CALL után — Add(2,3)+5 = 10.
        A return value pop-ja a callee Stack Cache-ből, push a caller
        eval stack-jére. A caller még egy LDC.I4_5 + ADD-t végrehajt.
    en: Caller continues after CALL — Add(2,3) + 5 = 10."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        _method_header(arg_count=2, local_count=0, max_stack=2, code_size=4)
        + bytes([OP_LDARG_0, OP_LDARG_1, OP_ADD, OP_RET])
        # Caller (boot_pc=12): push 2, push 3, CALL add (RVA=0),
        # push 5, ADD, RET
        + bytes([OP_LDC_I4_2, OP_LDC_I4_3])
        + _call_op(0)
        + bytes([OP_LDC_I4_5, OP_ADD, OP_RET])
    )
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, boot_pc=12, max_cycles=10000
    )
    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 10, f"return_value = {rv}, expected 10 (Add(2,3) + 5)"


@cocotb.test()
async def test_52_call_recursive_fib_5(dut):
    """hu: Rekurzív Fibonacci(5) = 5.
        fib(n): if n<2 return n; else return fib(n-1)+fib(n-2)
        Layout:
          @0..7:   fib header (arg_count=1, local_count=0, code_size=24)
          @8..29:  fib body (rekurzív ágak + ADD + RET)
          @30..31: base case (LDARG.0, RET) — BLT_S target
          @32..38: caller (boot_pc=32): LDC.I4_5, CALL fib, RET
    en: Recursive Fibonacci(5) = 5."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        # @0..7: fib header
        _method_header(arg_count=1, local_count=0, max_stack=4, code_size=24)
        # @8..11: BLT_S branch eldönti: n < 2 → return n
        + bytes([
            OP_LDARG_0,                   # @8: push n
            OP_LDC_I4_2,                  # @9: push 2
            OP_BLT_S, 18,                 # @10..11: if n<2 → @12+18=@30
        ])
        # @12..19: recursive call 1: fib(n-1)
        + bytes([
            OP_LDARG_0,                   # @12: push n
            OP_LDC_I4_1,                  # @13: push 1
            OP_SUB,                       # @14: n-1
        ])
        + _call_op(0)                     # @15..19: CALL fib (RVA=0)
        # @20..27: recursive call 2: fib(n-2)
        + bytes([
            OP_LDARG_0,                   # @20: push n
            OP_LDC_I4_2,                  # @21: push 2
            OP_SUB,                       # @22: n-2
        ])
        + _call_op(0)                     # @23..27: CALL fib
        # @28..29: combine + return
        + bytes([OP_ADD, OP_RET])
        # @30..31: base case
        + bytes([OP_LDARG_0, OP_RET])
        # @32..38: caller (boot_pc=32)
        + bytes([OP_LDC_I4_5])
        + _call_op(0)
        + bytes([OP_RET])
    )
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, boot_pc=32, max_cycles=200000
    )
    assert halt == 1, \
        f"core didn't halt (trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X})"
    assert rv == 5, f"return_value = {rv}, expected 5 (fib(5))"


# ============================================================
# hu: F2.7.D regressziós teszt — Roslyn-linkelt REKURZÍV
#     Math.Fibonacci a wrapper boot-mintájával (caller frame nélkül,
#     boot_pc = method body). Korábban (project_recursive_call_bug)
#     TRAP_STACK_UNDERFLOW-val bukott, mert a Sub5 frame manager nem
#     őrizte meg a caller eval depth-jét CALL/RET között. A gyökér-fix
#     (flush SRAM-ba + eval depth a header reserved mezőjében + RET
#     SPFILL cache-újratöltés) után helyesen Fib(10) = 55.
# en: F2.7.D regression test — Roslyn-linked RECURSIVE Math.Fibonacci
#     with the wrapper boot pattern. Previously trapped (caller eval
#     depth not preserved across CALL/RET); after the root fix it
#     correctly returns Fib(10) = 55.
# ============================================================

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.abspath(os.path.join(_THIS_DIR, "..", ".."))
_RUNNER_DLL = os.path.join(
    _REPO_ROOT, "src", "CilCpu.Sim.Runner", "bin", "Debug", "net10.0",
    "CilCpu.Sim.Runner.dll",
)
_PUREMATH_DLL = os.path.join(
    _REPO_ROOT, "samples", "PureMath", "bin", "Debug", "net10.0",
    "PureMath.dll",
)


def _link_math_method(method_name):
    """hu: A `Math.<method_name>` C# metódust CIL-T0 binárissá linkeli
        a Runner-rel, és visszaadja (code_bytes, arg_count, local_count)-ot
        a 8-byte fejlécből kiolvasva.
    en: Links `Math.<method_name>` to a CIL-T0 binary via the Runner,
        returns (code_bytes, arg_count, local_count) parsed from the
        8-byte header."""
    if not os.path.exists(_RUNNER_DLL):
        raise FileNotFoundError(
            f"Runner DLL not found: {_RUNNER_DLL}\nRun 'dotnet build' first."
        )
    if not os.path.exists(_PUREMATH_DLL):
        raise FileNotFoundError(
            f"PureMath DLL not found: {_PUREMATH_DLL}\n"
            "Run 'dotnet build samples/PureMath/PureMath.csproj' first."
        )

    out_fd, out_path = tempfile.mkstemp(suffix=".t0")
    os.close(out_fd)
    cmd = [
        "dotnet", _RUNNER_DLL, "link", _PUREMATH_DLL,
        "--class", "Math", "--method", method_name, "-o", out_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        os.unlink(out_path)
        raise RuntimeError(
            f"Runner link failed (exit={result.returncode}):\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    with open(out_path, "rb") as f:
        code_bytes = f.read()
    os.unlink(out_path)

    assert code_bytes[0] == 0xFE, \
        f"bad method header magic: 0x{code_bytes[0]:02X} (expected 0xFE)"
    arg_count = code_bytes[1]
    local_count = code_bytes[2]
    return code_bytes, arg_count, local_count


@cocotb.test()
async def test_52c_recursive_fib10_roslyn_boot_no_caller(dut):
    """hu: F2.7.D regresszió — a Roslyn-fordított REKURZÍV
        `Math.Fibonacci(10)` a wrapper boot-mintájával futtatva
        (boot_pc=8, a Fib body közvetlenül; NINCS caller frame).
        Fib(10) = 55, halt. A caller eval depth megőrzése CALL/RET
        között (flush + header reserved + SPFILL) biztosítja a
        helyes rekurzív kombinációt.
    en: F2.7.D regression — Roslyn-compiled RECURSIVE
        `Math.Fibonacci(10)` with the wrapper boot pattern
        (boot_pc=8, Fib body directly; NO caller frame).
        Fib(10) = 55, halt — caller eval depth preserved across
        CALL/RET (flush + header reserved + SPFILL)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    code_bytes, arg_count, local_count = _link_math_method("Fibonacci")
    assert arg_count == 1, f"expected arg_count=1, got {arg_count}"

    rv, tc, halt, trap, pc = await boot_and_run(
        dut, code_bytes, boot_pc=8, args=[10],
        locals_count=local_count, max_cycles=2_000_000,
    )
    assert halt == 1, (
        f"core didn't halt — trap={trap}, code=0x{tc:02X}, pc=0x{pc:06X} "
        f"(project_recursive_call_bug: Sub5 teardown a boot-kontextusú "
        f"root frame-en)"
    )
    assert rv == 55, f"return_value = {rv}, expected 55 (Fibonacci(10))"


@cocotb.test()
async def test_53_invalid_call_target(dut):
    """hu: CALL egy olyan címre, ahol nincs 0xFE magic
        → TRAP_INVALID_CALL_TARGET (0x07).
    en: CALL to address without 0xFE magic
        → TRAP_INVALID_CALL_TARGET (0x07)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        # @0..7: NEM header (random), magic byte 0x00 ≠ 0xFE
        bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        # @8..13: caller — CALL 0 (RVA=0, ott 0x00 magic, invalid)
        + _call_op(0)
        + bytes([OP_RET])
    )
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, boot_pc=8, max_cycles=10000
    )
    assert trap == 1, \
        f"expected trap, got halt={halt}, rv={rv}"
    assert tc == TRAP_INVALID_CALL_TARGET, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_INVALID_CALL_TARGET:02X} (INVALID_CALL_TARGET)"


@cocotb.test()
async def test_54_call_depth_exceeded(dut):
    """hu: Végtelen rekurzió önhívással. F3 (4 KB egységes on-chip SRAM): a
        rekurzív frame-ek a 2 KB stack-régiót (STACK_BASE..4096) töltik meg
        ~128 mélységnél → TRAP_SRAM_OVERFLOW (0x0D) — ami a 512-es call-depth
        cap (CALL_DEPTH_EXCEEDED, 0x0A) ELŐTT következik be, mert 512 frame nem
        fér a 4 KB SRAM-ba. A CALL_VALIDATE SRAM-overflow őre tisztán trap-el
        (nem hagyja a frame-eket túlcímezni → aliasing/korrupció).
        Layout:
          @0..7:   recursive header (arg_count=0, local_count=0)
          @8..13:  CALL 0 (önmagát hívja) + RET (sosem fut le)
          @14..20: caller (boot_pc=14): CALL recursive_fn, RET
    en: Infinite self-recursion. F3 (4 KB unified on-chip SRAM): the recursive
        frames fill the 2 KB stack region at ~depth 128 → TRAP_SRAM_OVERFLOW
        (0x0D), which occurs BEFORE the 512 call-depth cap (512 frames don't fit
        in 4 KB). The CALL_VALIDATE SRAM-overflow guard traps cleanly."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = (
        # @0..7: recursive_fn header (no args, no locals)
        _method_header(arg_count=0, local_count=0, max_stack=1, code_size=6)
        # @8..13: recursive_fn body — CALL self, RET
        + _call_op(0)
        + bytes([OP_RET])
        # @14..20: caller (boot_pc=14)
        + _call_op(0)
        + bytes([OP_RET])
    )
    rv, tc, halt, trap, pc = await boot_and_run(
        dut, program, boot_pc=14, max_cycles=500000
    )
    assert trap == 1, \
        f"expected trap, got halt={halt}, rv={rv}"
    # hu: F3 — a 4 KB SRAM-limit (SRAM_OVERFLOW) ér el a 512-es call-depth cap előtt.
    assert tc == TRAP_SRAM_OVERFLOW, \
        f"trap_code = 0x{tc:02X}, expected 0x{TRAP_SRAM_OVERFLOW:02X} (SRAM_OVERFLOW, F3 4 KB)"
