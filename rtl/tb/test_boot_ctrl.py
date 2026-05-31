# hu: CLI-CPU F2.8 #6.5b-F1c — cilcpu_boot_ctrl cocotb tesztjei (AUTODETECT=1).
#     A boot_ctrl reset után beolvassa a flash CODE-bázis header-szavát egy
#     mem-read modellen át, és a magic alapján vagy autonóm flash-boot-ot indít
#     (o_boot_req + paraméterek), vagy idle marad (üres flash → UART-ra vár).
# en: CLI-CPU F2.8 #6.5b-F1c — cocotb tests for cilcpu_boot_ctrl (AUTODETECT=1).
#     After reset the boot_ctrl reads the flash CODE-base header word via a
#     mem-read model and either starts an autonomous flash boot (o_boot_req +
#     params) on valid magic, or stays idle (blank flash → waits for UART).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def mem_read_model(dut, word):
    """hu: A flash-olvasás modellje — az o_mem_re pulzusra a `word`-öt adja
        vissza i_mem_rdata-n, i_mem_ready 1-ciklusos pulzussal (1 ciklus
        latencia, mint a QSPI controller).
    en: Flash-read model — on the o_mem_re pulse returns `word` on i_mem_rdata
        with a 1-cycle i_mem_ready pulse (1-cycle latency, like the QSPI ctrl)."""
    dut.i_mem_rdata.value = 0
    dut.i_mem_ready.value = 0
    while True:
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        try:
            if int(dut.o_mem_re.value) == 1:
                await RisingEdge(dut.clk)
                dut.i_mem_rdata.value = word & 0xFFFFFFFF
                dut.i_mem_ready.value = 1
                await RisingEdge(dut.clk)
                dut.i_mem_ready.value = 0
        except (ValueError, AttributeError):
            pass


async def run_detect(dut, header_word):
    """hu: Reset + a header-szó beállítása a mem-modellben; visszaadja a
        rögzített boot-eseményt (vagy None, ha nem volt boot)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.i_mem_rdata.value = 0
    dut.i_mem_ready.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(mem_read_model(dut, header_word))

    captured = {"boot": 0, "pc": None, "argc": None, "localc": None,
                "detect_high": 0}

    async def mon():
        while True:
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            try:
                if int(dut.o_detect_active.value) == 1:
                    captured["detect_high"] += 1
                if int(dut.o_boot_req.value) == 1:
                    captured["boot"] += 1
                    captured["pc"]     = int(dut.o_boot_pc.value)
                    captured["argc"]   = int(dut.o_boot_argc.value)
                    captured["localc"] = int(dut.o_boot_localc.value)
            except (ValueError, AttributeError):
                pass
    cocotb.start_soon(mon())

    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(20):
        await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    return captured


@cocotb.test()
async def test_01_valid_header_autoboots(dut):
    """hu: Érvényes header (magic 0xFE, arg=2, local=3) → autonóm flash-boot:
        o_boot_req, boot_pc=8 (HEADER_SIZE), argc=2, localc=3.
    en: Valid header (magic 0xFE, arg=2, local=3) → autonomous flash boot:
        o_boot_req, boot_pc=8, argc=2, localc=3."""
    # hu: header bájtok [0xFE, 0x02, 0x03, 0x00] → BE szó 0xFE020300
    cap = await run_detect(dut, 0xFE020300)

    assert cap["boot"] == 1, f"egy auto-boot pulzus várt, kaptam {cap['boot']}"
    assert cap["pc"] == 8, f"boot_pc {cap['pc']}, várt 8 (HEADER_SIZE)"
    assert cap["argc"] == 2, f"argc {cap['argc']}, várt 2"
    assert cap["localc"] == 3, f"localc {cap['localc']}, várt 3"
    assert cap["detect_high"] >= 1, "o_detect_active sosem volt magas a detect alatt"


@cocotb.test()
async def test_02_blank_flash_waits(dut):
    """hu: Üres flash (0xFFFFFFFF, magic != 0xFE) → nincs auto-boot; a
        detect után o_detect_active leesik (a busz felszabadul a UART-loadernek).
    en: Blank flash (0xFFFFFFFF, magic != 0xFE) → no auto-boot; after detect
        o_detect_active drops (bus released for the UART loader)."""
    cap = await run_detect(dut, 0xFFFFFFFF)

    assert cap["boot"] == 0, f"üres flash → nincs auto-boot, de {cap['boot']} pulzus volt"
    assert int(dut.o_detect_active.value) == 0, \
        "o_detect_active magas maradt üres flash után (a busz nem szabadult fel)"


@cocotb.test()
async def test_03_detect_releases_bus_after_boot(dut):
    """hu: Érvényes header után is leesik az o_detect_active (a core veheti át
        a QSPI-t a futáshoz).
    en: After a valid header o_detect_active also drops (the core can take over
        the QSPI for running)."""
    cap = await run_detect(dut, 0xFE000000)   # magic ok, arg=0, local=0
    assert cap["boot"] == 1, "auto-boot várt érvényes magic-re"
    assert int(dut.o_detect_active.value) == 0, \
        "o_detect_active magas maradt boot után"
