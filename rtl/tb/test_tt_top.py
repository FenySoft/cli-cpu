# hu: CLI-CPU F2.8.6 — cocotb tesztek a cilcpu_tt_top wrapperre (Tiny Tapeout
#     tt_um ekvivalens). A tesztek a 24-pin leképezést verifikálják: UART RX a
#     ui_in[0]-on (loader), UART TX az uo_out[0]-on (eredmény-printer), QSPI a
#     uio pineken (DQ bidir + cs/clk), GPIO in/out + trace mux, status pinek.
#     A boot KIZÁRÓLAG UART-loaderen át megy (a külső boot-port tied-off), mint
#     a valós F3 chipen. A QSPI slave a SoC belső portjain (dut.u_soc.qspi_*)
#     keresztül hajtott, a uio_in[3:0]-t drive-olva (shim → qspi_slave_driver).
# en: CLI-CPU F2.8.6 — cocotb tests for the cilcpu_tt_top wrapper (Tiny Tapeout
#     tt_um equivalent). Verifies the 24-pin mapping: UART RX on ui_in[0]
#     (loader), UART TX on uo_out[0] (result printer), QSPI on the uio pins (DQ
#     bidir + cs/clk), GPIO in/out + trace mux, status pins. Boot is ONLY via
#     the UART loader (external boot port tied off), like the real F3 chip. The
#     QSPI slave is driven through the SoC's internal ports (dut.u_soc.qspi_*),
#     driving uio_in[3:0] (shim → qspi_slave_driver).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from test_core import _ldc_i4, _ldc_s, OP_STIND_I4, OP_LDIND_I4, OP_RET
from test_soc import _u16_be, _u24_be, GPIO_IN, GPIO_OUT, GPIO_OE
from tb_uart import uart_tx_bytes
from test_qspi_controller import TQSPIFlashModel, TQSPIPSRAMModel, qspi_slave_driver

UART_CPB  = 8          # a Makefile -GCLOCKS_PER_BAUD=8
CMD_WRITE = 0xC0
CMD_BOOT  = 0xB0
DEV_PSRAM = 0x01

# hu: Pin-bit indexek (a cilcpu_tt_top pin-mapja szerint)
# en: Pin-bit indices (per the cilcpu_tt_top pin map)
UO_UART_TX = 0
UO_HALT    = 1
UO_TRAP    = 2
UO_IRQ     = 3
# uo_out[7:4] + uio[7] = MUX(trace/gpio_out[4:0])
UIO_CS_FL  = 4
UIO_CS_PS  = 5
UIO_CLK    = 6
UIO_MUX4   = 7


class _SocQspiView:
    """hu: Shim — a qspi_slave_driver a SoC belső QSPI-portjain dolgozzon, és a
        DQ-bemenetet a uio_in[3:0] porton hajtsa. A driver dut.qspi_* neveket
        használ; ezt a view a hierarchikus jelekre képezi.
    en: Shim — lets qspi_slave_driver operate on the SoC's internal QSPI ports
        and drive the DQ input via uio_in[3:0]. The driver uses dut.qspi_*
        names; this view maps them to the hierarchical signals."""

    def __init__(self, dut):
        self.clk              = dut.clk
        self.qspi_clk         = dut.u_soc.qspi_clk
        self.qspi_cs_flash_n  = dut.u_soc.qspi_cs_flash_n
        self.qspi_cs_psram_n  = dut.u_soc.qspi_cs_psram_n
        self.qspi_dq_out      = dut.u_soc.qspi_dq_out
        # hu: a driver ide ír (DQ MISO) — a tt_top a uio_in[3:0]-t használja
        # en: the driver writes here (DQ MISO) — tt_top uses uio_in[3:0]
        self.qspi_dq_in       = dut.uio_in


def _bits(val, hi, lo):
    """hu: val[hi:lo] kivágása. / en: extract val[hi:lo]."""
    width = hi - lo + 1
    return (val >> lo) & ((1 << width) - 1)


async def _reset(dut):
    """hu: tt_top reset + idle bemenetek (UART idle=1 a ui_in[0]-on).
    en: tt_top reset + idle inputs (UART idle=1 on ui_in[0])."""
    dut.ui_in.value  = 0x01   # bit0 (UART RX) = 1 idle, GPIO in = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")


def _pad4(program):
    while len(program) % 4 != 0:
        program += bytes([0x00])
    return program


async def _uart_load_and_boot(dut, program):
    """hu: A programot UART-on PSRAM-ba tölti (WRITE dev=1), majd BOOT
        (code_src=1) elindítja. A ui_in-t hajtja (bit0 = soros, GPIO in = 0).
    en: UART-loads the program into PSRAM (WRITE dev=1), then BOOT (code_src=1)
        starts it. Drives ui_in (bit0 = serial, GPIO in = 0)."""
    program = _pad4(program)
    plen = len(program)
    write_frame = [CMD_WRITE, DEV_PSRAM] + _u24_be(0x00000) + _u16_be(plen) + list(program)
    boot_frame  = [CMD_BOOT, 0x01] + _u24_be(0x000000) + [0x00, 0x00]

    await uart_tx_bytes(dut, dut.ui_in, UART_CPB, write_frame)
    for _ in range(40):
        await RisingEdge(dut.clk)
    await uart_tx_bytes(dut, dut.ui_in, UART_CPB, boot_frame)


async def _uart_rx_line_from_bit(dut, vec_signal, bit, cpb, max_bytes=8):
    """hu: 8N1 sor dekódolása egy PACKED vektor egyetlen bitjéről (a Verilator
        nem engedi a `dut.uo_out[0]` bit-indexelést, ezért a teljes vektort
        olvassuk és maszkoljuk). A `\n`-ig vagy max_bytes-ig olvas.
    en: Decode an 8N1 line from a single bit of a PACKED vector (Verilator
        forbids `dut.uo_out[0]` bit-indexing, so we read the whole vector and
        mask). Reads until `\n` or max_bytes."""

    def rd():
        return (int(vec_signal.value) >> bit) & 1

    out = bytearray()
    for _ in range(max_bytes):
        # hu: start él (1→0) / en: start edge (1→0)
        while rd() == 1:
            await RisingEdge(dut.clk)
        for _ in range(cpb // 2):
            await RisingEdge(dut.clk)
        # hu: 8 data bit, LSB-first, bit-közép mintavétel
        # en: 8 data bits, LSB-first, mid-bit sample
        val = 0
        for i in range(8):
            for _ in range(cpb):
                await RisingEdge(dut.clk)
            val |= (rd() & 1) << i
        # hu: stop bit / en: stop bit
        for _ in range(cpb):
            await RisingEdge(dut.clk)
        out.append(val)
        if val == ord('\n'):
            break
    return bytes(out)


async def _wait_halt(dut, timeout=6000):
    """hu: Vár a core halt/trap-jára az uo_out status pineken.
    en: Wait for core halt/trap on the uo_out status pins."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        try:
            uo = int(dut.uo_out.value)
        except ValueError:
            continue
        if _bits(uo, UO_HALT, UO_HALT) or _bits(uo, UO_TRAP, UO_TRAP):
            return uo
    raise TimeoutError("core did not halt/trap within timeout")


# ============================================================
# hu: Tesztek
# ============================================================


@cocotb.test()
async def test_01_reset_pin_state(dut):
    """hu: Reset után a pin-irányok és status pinek alaphelyzetben. A QSPI
        cs/clk/mux pinek kimenetek (uio_oe[7:4]=1), a DQ irány a controller
        oe-je (IDLE-ban 0 → uio_oe[3:0]=0). A status pinek (halt/trap/irq) 0.
    en: After reset the pin directions and status pins are at their defaults.
        The QSPI cs/clk/mux pins are outputs (uio_oe[7:4]=1), DQ direction is
        the controller oe (0 in IDLE → uio_oe[3:0]=0). Status pins are 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    oe = int(dut.uio_oe.value)
    assert _bits(oe, 7, 4) == 0xF, \
        f"uio_oe[7:4] (cs/clk/mux) = 0x{_bits(oe,7,4):X}, várt 0xF (mind kimenet)"
    assert _bits(oe, 3, 0) == 0x0, \
        f"uio_oe[3:0] (DQ) = 0x{_bits(oe,3,0):X}, várt 0x0 (IDLE: controller oe=0)"

    uo = int(dut.uo_out.value)
    assert _bits(uo, UO_HALT, UO_HALT) == 0, "halt pin nem 0 reset után"
    assert _bits(uo, UO_TRAP, UO_TRAP) == 0, "trap pin nem 0 reset után"
    assert _bits(uo, UO_IRQ, UO_IRQ) == 0, "irq pin nem 0 reset után"
    # hu: UART TX idle = 1 (uo_out[0])
    assert _bits(uo, UO_UART_TX, UO_UART_TX) == 1, "UART TX nem idle (1) reset után"


@cocotb.test()
async def test_02_boot_e2e_uart_to_uart(dut):
    """hu: Teljes tt_um út: UART WRITE+BOOT a ui_in[0]-on → PSRAM-ból futás →
        az eredmény (42) az uo_out[0] UART TX-en, decimálisan. Bizonyítja a
        UART RX + QSPI(uio) + UART TX pin-leképezést egyben.
    en: Full tt_um path: UART WRITE+BOOT on ui_in[0] → run from PSRAM → result
        (42) on the uo_out[0] UART TX, decimal. Proves UART RX + QSPI(uio) +
        UART TX pin mapping together."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    flash = TQSPIFlashModel()
    psram = TQSPIPSRAMModel()
    cocotb.start_soon(qspi_slave_driver(_SocQspiView(dut), flash, psram))

    # hu: program — LDC.I4.S 42, RET
    program = _ldc_s(42) + bytes([OP_RET])
    await _uart_load_and_boot(dut, program)

    # hu: az eredmény-printer az uo_out[0]-ra küldi: "42\r\n"
    result = await _uart_rx_line_from_bit(dut, dut.uo_out, UO_UART_TX, UART_CPB)
    text = result.decode("ascii", errors="replace").strip()
    assert text == "42", f"UART TX eredmény = {text!r}, várt '42'"

    # hu: a halt pin (uo_out[1]) magas a futás vége után
    assert _bits(int(dut.uo_out.value), UO_HALT, UO_HALT) == 1, \
        "halt pin nem magas a halt után"


@cocotb.test()
async def test_03_gpio_out_and_trace_mux(dut):
    """hu: A program a GPIO_OE-t és GPIO_OUT-ot írja (STIND). trace_mode=0
        (default) → a muxolt pinek a gpio_out[4:0]-t mutatják:
        {uio[7], uo_out[7:4]} == gpio_out[4:0]. A gpio_out[4:0]=0x15 (10101).
    en: The program writes GPIO_OE and GPIO_OUT (STIND). With trace_mode=0
        (default) the muxed pins show gpio_out[4:0]:
        {uio[7], uo_out[7:4]} == gpio_out[4:0]. gpio_out[4:0]=0x15 (10101)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    flash = TQSPIFlashModel()
    psram = TQSPIPSRAMModel()
    cocotb.start_soon(qspi_slave_driver(_SocQspiView(dut), flash, psram))

    gpio_val = 0x15   # alsó 5 bit: 1 0101
    program = (_ldc_i4(GPIO_OE)  + _ldc_i4(0x1F) + bytes([OP_STIND_I4])
               + _ldc_i4(GPIO_OUT) + _ldc_s(gpio_val) + bytes([OP_STIND_I4])
               + _ldc_s(0) + bytes([OP_RET]))
    await _uart_load_and_boot(dut, program)
    await _wait_halt(dut)
    await Timer(1, units="ns")

    uo  = int(dut.uo_out.value)
    uio = int(dut.uio_out.value)
    # hu: muxolt érték: uo_out[7:4] = gpio_out[3:0], uio[7] = gpio_out[4]
    mux = (_bits(uio, UIO_MUX4, UIO_MUX4) << 4) | _bits(uo, 7, 4)
    assert mux == gpio_val, \
        f"muxolt GPIO-out = 0x{mux:02X}, várt 0x{gpio_val:02X} (trace_mode=0)"

    # hu: a uio_oe[7] (mux pin) mindig kimenet
    assert _bits(int(dut.uio_oe.value), UIO_MUX4, UIO_MUX4) == 1, \
        "uio[7] (mux) nem kimenet"


@cocotb.test()
async def test_04_gpio_in_routing(dut):
    """hu: A külső GPIO bemenet a ui_in[7:1]-en érkezik (7-bit). A program
        LDIND-del olvassa a GPIO_IN-t és visszaadja. Az érték 0x2A (a 7-bit
        ablakba fér), a ui_in[7:1]-re téve a BOOT után. Eredmény az uo_out[0]-n.
    en: External GPIO input arrives on ui_in[7:1] (7-bit). The program LDINDs
        GPIO_IN and returns it. Value 0x2A (fits the 7-bit window), placed on
        ui_in[7:1] after BOOT. Result on uo_out[0]."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await _reset(dut)

    flash = TQSPIFlashModel()
    psram = TQSPIPSRAMModel()
    cocotb.start_soon(qspi_slave_driver(_SocQspiView(dut), flash, psram))

    gpio_in_val = 0x2A   # 7-bit (< 0x80)
    program = _ldc_i4(GPIO_IN) + bytes([OP_LDIND_I4, OP_RET])
    await _uart_load_and_boot(dut, program)

    # hu: a BOOT után állítjuk a GPIO bemenetet: ui_in[7:1]=gpio_in_val,
    #     ui_in[0]=1 (UART idle). A program LDIND-je a BOOT után pár ciklussal fut.
    # en: After BOOT set the GPIO input: ui_in[7:1]=gpio_in_val, ui_in[0]=1
    #     (UART idle). The program's LDIND runs a few cycles past BOOT.
    dut.ui_in.value = ((gpio_in_val & 0x7F) << 1) | 0x01

    result = await _uart_rx_line_from_bit(dut, dut.uo_out, UO_UART_TX, UART_CPB)
    text = result.decode("ascii", errors="replace").strip()
    assert text == str(gpio_in_val), \
        f"GPIO_IN visszaolvasás (UART) = {text!r}, várt '{gpio_in_val}'"
