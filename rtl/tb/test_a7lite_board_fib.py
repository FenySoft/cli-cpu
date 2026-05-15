# hu: CLI-CPU F2.7 Sub4 — board-szintű (`cilcpu_a7lite_board.v`) Fibonacci(20)
#     end-to-end teszt. A `test_a7lite_fib.py` (top.v) párja, de a teljes
#     board wrapper-en keresztül megy: STARTUPE2 (CCLK) + IOBUF (DQ) stubbed
#     primitivek a flash slave és a master közé ékelve.
# en: CLI-CPU F2.7 Sub4 — board-level (`cilcpu_a7lite_board.v`) Fibonacci(20)
#     end-to-end test. Counterpart of `test_a7lite_fib.py` (top.v) but
#     routed through the full board wrapper: STARTUPE2 (CCLK) + IOBUF (DQ)
#     stubbed primitives sit between the flash slave and the master.

import os
import subprocess
import tempfile

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tb_qspi import TQSPIFlashModel, qspi_flash_driver
from tb_uart import uart_rx_byte


# ============================================================
# hu: Wrapper sim paraméterek (Makefile -G-vel egyezően)
# en: Wrapper sim parameters (must match Makefile -G overrides)
# ============================================================
DEBOUNCE_BITS    = 4
DEBOUNCE_CYCLES  = (1 << DEBOUNCE_BITS) + 4
CLOCKS_PER_BAUD  = 8
BOOT_ARG_VALUE   = 20
EXPECTED_RESULT  = 6765

CLK_PERIOD_NS    = 20  # 50 MHz


# ============================================================
# hu: A FibonacciIterative.t0 bináris előállítása a Runner-rel.
# en: Build the FibonacciIterative.t0 binary via the Runner.
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


def _build_fibonacci_iter_t0():
    if not os.path.exists(_RUNNER_DLL):
        raise FileNotFoundError(
            f"Runner DLL not found: {_RUNNER_DLL}\n"
            "Run 'dotnet build' first."
        )
    if not os.path.exists(_PUREMATH_DLL):
        raise FileNotFoundError(
            f"PureMath DLL not found: {_PUREMATH_DLL}\n"
            "Run 'dotnet build samples/PureMath/PureMath.csproj' first."
        )

    out_fd, out_path = tempfile.mkstemp(suffix=".t0")
    os.close(out_fd)
    cmd = [
        "dotnet", _RUNNER_DLL, "link",
        _PUREMATH_DLL,
        "--class", "Math",
        "--method", "FibonacciIterative",
        "-o", out_path,
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
    return code_bytes


# ============================================================
# hu: Segédfüggvények
# en: Helpers
# ============================================================

async def _setup(dut, code_bytes):
    cocotb.start_soon(Clock(dut.i_clk_50m, CLK_PERIOD_NS, units="ns").start())
    flash = TQSPIFlashModel(code_bytes)
    cocotb.start_soon(qspi_flash_driver(
        dut, flash,
        clk_signal   = dut.o_qspi_clk_dbg,
        cs_signal    = dut.o_qspi_cs_n,
        dq_in_signal = dut.i_qspi_dq_in_dbg,
        dq_out_signal= dut.o_qspi_dq_out_dbg,
    ))

    dut.i_rst_btn_n.value      = 0
    dut.i_start_btn_n.value    = 1
    dut.i_qspi_dq_in_dbg.value = 0
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)
    dut.i_rst_btn_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.i_clk_50m)


async def _press_start(dut):
    dut.i_start_btn_n.value = 0
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)
    dut.i_start_btn_n.value = 1
    for _ in range(DEBOUNCE_CYCLES):
        await RisingEdge(dut.i_clk_50m)


async def _read_uart_line(dut, max_bytes=16):
    out = bytearray()
    for _ in range(max_bytes):
        b = await uart_rx_byte(dut, dut.o_uart_tx, CLOCKS_PER_BAUD)
        out.append(b)
        if b == 0x0A:
            break
    return bytes(out)


# ============================================================
# hu: Tesztek
# en: Tests
# ============================================================

@cocotb.test()
async def test_01_fibonacci_iterative_e2e_board(dut):
    """hu: End-to-end FibonacciIterative(20) = 6765 a board.v szintjén.
        Bizonyítja, hogy a teljes toolchain (C# → Roslyn → linker → core
        → top.v → board.v + STARTUPE2/IOBUF stub → flash slave) zárul.
    en: End-to-end FibonacciIterative(20) = 6765 at the board.v level.
        Proves the full toolchain closes: C# → Roslyn → linker → core →
        top.v → board.v + STARTUPE2/IOBUF stubs → flash slave."""
    code_bytes = _build_fibonacci_iter_t0()
    await _setup(dut, code_bytes)

    await _press_start(dut)
    line = await _read_uart_line(dut, max_bytes=16)
    expected = f"{EXPECTED_RESULT}\r\n".encode("ascii")
    assert line == expected, f"expected {expected!r}, got {line!r}"

    assert int(dut.u_top.r_halted.value)  == 1, "halt latch should be set"
    assert int(dut.u_top.r_trapped.value) == 0, "trap latch should be clear"
    assert int(dut.o_led1_n.value) == 0, "halt LED should be active"
    assert int(dut.o_led2_n.value) == 1, "trap LED should be inactive"
