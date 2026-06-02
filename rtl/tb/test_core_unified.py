# hu: CLI-CPU F3 — egységes on-chip SRAM (CODE+DATA+STACK) RED tesztek.
#     Az ADR (Vault/Decisions/2026-06-01-unified-onchip-sram) szerint a core a
#     programot a SAJÁT 4 KB on-chip SRAM-jából (r_sram) futtatja: a CODE-fetch
#     az on-chip SRAM-ból megy (~1-2 ciklus), NEM a külső o_xmem buszon (QSPI
#     flash/PSRAM ~58-98 ciklus). A QSPI a SoC-ban marad betöltés-idejű backing
#     store-ként, de a RUN fázisban a Core SOHA nem hajtja az o_xmem_re-t.
#
#     E tesztek a programot backdoor-poke-kal írják a core r_sram-jába (a valódi
#     betöltési út — UART-loader / flash→SRAM copy — mechanizmusától függetlenül),
#     boot-olnak, és ellenőrzik: (1) helyes eredmény az on-chip SRAM-ból futtatva,
#     (2) o_xmem_re VÉGIG 0. A jelenlegi (fetch-from-xmem) core-on BUKNAK:
#     a boot a frame-headert a 0. bájtra írja (felülírja a kódot) ÉS a fetch a
#     külső buszra megy → o_xmem_re felmegy. GREEN: STACK_BASE relokáció + fetch
#     az r_sram-ból.
#
# en: CLI-CPU F3 — unified on-chip SRAM (CODE+DATA+STACK) RED tests. Per ADR,
#     the core runs the program from its own 4 KB on-chip SRAM (r_sram): code
#     fetch comes from on-chip SRAM (~1-2 cycles), NOT the external o_xmem bus.
#     The QSPI stays at SoC level as a load-time backing store, but during RUN
#     the core must NEVER assert o_xmem_re. Programs are backdoor-poked into the
#     core's r_sram (independent of the real load path), booted, and checked for:
#     (1) correct result running from on-chip SRAM, (2) o_xmem_re stays 0
#     throughout. They FAIL on the current fetch-from-xmem core. GREEN: STACK_BASE
#     relocation + fetch from r_sram.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# ============================================================
# hu: CIL-T0 opcode bytes (cilcpu_defines.vh)
# ============================================================
OP_LDC_I4_1 = 0x17
OP_LDC_I4_S = 0x1F   # + 1 byte signed
OP_LDC_I4   = 0x20   # + 4 byte LE
OP_LDLOC_0  = 0x06
OP_STLOC_0  = 0x0A
OP_SUB      = 0x59
OP_DUP      = 0x25
OP_BRTRUE_S = 0x2D   # + 1 byte signed offset
OP_RET      = 0x2A


def _to_words_le(code_bytes):
    """hu: byte-lista → 32-bit LE szavak (r_sram[k] tartalma). A CODE byte
        pc=4k+i a w[k] [8i+7:8i] bitjein — ez az egységes on-chip SRAM
        byte-sorrend-kontraktusa (megegyezik a C# szim flat LE memóriájával).
    en: byte list → 32-bit LE words for r_sram[k]. CODE byte at pc=4k+i lives
        in w[k][8i+7:8i] — the on-chip SRAM byte-order contract (matches the C#
        sim's flat LE memory)."""
    pad = (-len(code_bytes)) % 4
    b = list(code_bytes) + [0x00] * pad
    words = []
    for k in range(0, len(b), 4):
        words.append(b[k] | (b[k + 1] << 8) | (b[k + 2] << 16) | (b[k + 3] << 24))
    return words


async def _reset(dut):
    """hu: reset + alap-bemenetek; QSPI flash slave-et NEM indítunk → a külső
        busz nem szolgáltat érvényes kódot (csak az on-chip SRAM-ból futhat
        helyesen)."""
    dut.rst_n.value              = 0
    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = 0
    dut.i_boot_start.value       = 0
    dut.i_boot_arg_data.value    = 0
    dut.i_boot_arg_valid.value   = 0
    dut.qspi_dq_in.value         = 0
    dut.i_mmio_rdata.value       = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


def _preload(dut, code_bytes, base_word=0):
    """hu: program backdoor-írása a core on-chip SRAM-jába (CODE régió)."""
    for i, w in enumerate(_to_words_le(code_bytes)):
        dut.u_core.r_sram[base_word + i].value = w


async def _run_unified(dut, code_bytes, locals_count=0, max_cycles=800):
    """hu: preload az on-chip SRAM-ba → boot pc=0 → futás. Közben az o_xmem_re-t
        figyeli: ha BÁRMIKOR felmegy, az sérti az egységes-SRAM invariánst.
        Visszatér: (return_value, trap_code, halt, trap, xmem_re_seen)."""
    await _reset(dut)
    _preload(dut, code_bytes)

    dut.i_boot_pc.value          = 0
    dut.i_boot_arg_count.value   = 0
    dut.i_boot_local_count.value = locals_count
    dut.i_boot_start.value       = 1
    await RisingEdge(dut.clk)
    dut.i_boot_start.value       = 0

    xmem_re_seen = False
    halt = trap = 0
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        try:
            if int(dut.u_core.o_xmem_re.value) == 1:
                xmem_re_seen = True
        except ValueError:
            pass
        try:
            halt = int(dut.o_halt.value)
            trap = int(dut.o_trap.value)
        except ValueError:
            halt = trap = 0
        if halt or trap:
            break

    return (
        int(dut.o_return_value.value) if halt else 0,
        int(dut.o_trap_code.value) if trap else 0,
        halt,
        trap,
        xmem_re_seen,
    )


@cocotb.test()
async def test_01_run_from_onchip_sram_simple(dut):
    """hu: LDC.I4 0x1234 + RET az on-chip SRAM-ból futtatva → halt, rv=0x1234,
        és o_xmem_re VÉGIG 0 (a core nem nyúl a külső buszhoz).
    en: LDC.I4 0x1234 + RET run from on-chip SRAM → halt, rv=0x1234, and
        o_xmem_re stays 0 throughout."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([OP_LDC_I4, 0x34, 0x12, 0x00, 0x00, OP_RET])
    rv, tc, halt, trap, xmem = await _run_unified(dut, program)

    assert not xmem, \
        "o_xmem_re felment → a core a külső buszról fetch-elt (nem az on-chip SRAM-ból)"
    assert halt == 1, f"nem haltolt (trap={trap}, code=0x{tc:02X})"
    assert trap == 0, f"váratlan trap 0x{tc:02X}"
    assert rv == 0x1234, f"return_value=0x{rv:08X}, várt 0x1234"


@cocotb.test()
async def test_02_run_from_onchip_sram_loop(dut):
    """hu: 3-iterációs visszafelé-branch loop (LDLOC/SUB/DUP/STLOC/BRTRUE) az
        on-chip SRAM-ból → rv=0xBEEF. Bizonyítja az ismételt SRAM-fetch-et
        (branch-re visszatöltött fetch-buffer), o_xmem_re VÉGIG 0.
    en: 3-iteration backward-branch loop run from on-chip SRAM → rv=0xBEEF.
        Proves repeated SRAM fetch (buffer refilled on branch), o_xmem_re 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    program = bytes([
        OP_LDC_I4_S, 0x03,          # 0:  loc-init = 3
        OP_STLOC_0,                 # 2:  loc0 = 3
        OP_LDLOC_0,                 # 3:  <- loop target
        OP_LDC_I4_1,                # 4:
        OP_SUB,                     # 5:  loc0 - 1
        OP_DUP,                     # 6:
        OP_STLOC_0,                 # 7:  loc0 = loc0-1
        OP_BRTRUE_S, 0xF9,          # 8:  if !=0 -> pc=3 (offset -7)
        OP_LDC_I4, 0xEF, 0xBE, 0x00, 0x00,  # 10: push 0xBEEF
        OP_RET,                     # 15:
    ])
    rv, tc, halt, trap, xmem = await _run_unified(dut, program, locals_count=1)

    assert not xmem, \
        "o_xmem_re felment → a core a külső buszról fetch-elt (nem az on-chip SRAM-ból)"
    assert halt == 1, f"nem haltolt (trap={trap}, code=0x{tc:02X})"
    assert trap == 0, f"váratlan trap 0x{tc:02X}"
    assert rv == 0xBEEF, f"return_value=0x{rv:08X}, várt 0xBEEF"
