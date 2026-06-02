# hu: CLI-CPU F2.7 Sub3 — A7-Lite wrapper end-to-end Fibonacci demó.
#     A teszt build-time hívja a CilCpu.Sim.Runner-t a `Math.Fibonacci`
#     metódus CIL-T0 binárissá linkelésére, betölti a flash slave-be,
#     megnyomja a KEY2-t, és UART-on várja a "<eredmény>\r\n" stringet.
# en: CLI-CPU F2.7 Sub3 — A7-Lite wrapper end-to-end Fibonacci demo.
#     The test invokes CilCpu.Sim.Runner at runtime to link the
#     `Math.Fibonacci` method into a CIL-T0 binary, loads it into the
#     flash slave, presses KEY2, then waits for "<result>\r\n" on UART.

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
BOOT_ARG_VALUE   = 20              # hu: Sub3 demó — FibonacciIterative(20) = 6765
EXPECTED_RESULT  = 6765

CLK_PERIOD_NS    = 20  # 50 MHz


# ============================================================
# hu: A Fibonacci.t0 bináris előállítása a Runner-rel.
# en: Build the Fibonacci.t0 binary via the Runner.
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


def _build_fibonacci_t0(method_name="FibonacciIterative"):
    """hu: A `Math.<method_name>` C# metódust a Runner link parancsával
        CIL-T0 bináris formátumba fordítja. A FibonacciIterative variánst
        használjuk, mert a rekurzív CALL/RET egy ismert mély-mélységi
        bug-ot trigger-el a Sub5 frame manager-ben (lásd Bug-Debug-Log).
    en: Links the `Math.<method_name>` C# method to a CIL-T0 binary via
        the Runner. The FibonacciIterative variant is used because the
        recursive CALL/RET hits a known deep-recursion bug in the Sub5
        frame manager (see Bug-Debug-Log)."""
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
        "--method", method_name,
        "-o", out_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(
            f"Runner link failed (exit={result.returncode}):\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    with open(out_path, "rb") as f:
        code_bytes = f.read()

    os.unlink(out_path)
    return code_bytes


# ============================================================
# hu: Segédfüggvények — közös a wrapper teszttel.
# en: Helpers — shared with the wrapper test.
# ============================================================

async def _setup(dut, code_bytes):
    cocotb.start_soon(Clock(dut.i_clk_50m, CLK_PERIOD_NS, units="ns").start())
    flash = TQSPIFlashModel(code_bytes)
    cocotb.start_soon(qspi_flash_driver(dut, flash))

    dut.i_rst_btn_n.value   = 0
    dut.i_start_btn_n.value = 1
    dut.qspi_dq_in.value    = 0
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

async def _wait_halt_or_trap_diag(dut, max_cycles=2_000_000):
    """hu: A trap/halt eseményt várjuk, és visszaadjuk az állapotot a
        diagnosztikához.
    en: Wait for halt/trap and report the diagnostic state."""
    for cycle in range(max_cycles):
        await RisingEdge(dut.i_clk_50m)
        try:
            halted  = int(dut.u_core.o_halt.value)
            trapped = int(dut.u_core.o_trap.value)
        except ValueError:
            continue
        if halted or trapped:
            return {
                "halted": halted,
                "trapped": trapped,
                "trap_code": int(dut.u_core.o_trap_code.value),
                "pc": int(dut.u_core.o_pc.value),
                "sp": int(dut.u_core.r_sp.value),
                "fp": int(dut.u_core.r_fp.value),
                "call_depth": int(dut.u_core.r_call_depth.value),
                "return_value": int(dut.u_core.o_return_value.value),
                "cycle": cycle,
            }
    raise TimeoutError(f"no halt/trap within {max_cycles} cycles")


@cocotb.test(skip=True)  # F3: legacy a7lite_top (direct core+QSPI, nincs loader/copy) → on-chip SRAM nem tölthető; SoC-alapú tt_board váltja ki
async def test_01_fibonacci_iterative_e2e(dut):
    """hu: End-to-end FibonacciIterative(20) = 6765 — KEY2 lenyomásra a
        wrapper elindítja a Roslyn-fordított CIL-T0 binárist, push-olja
        az N=20 argumentumot, és UART-on kiírja "6765\\r\\n"-t. Ez a Sub3
        fő demója: a teljes toolchain (C# → Roslyn → linker → core →
        wrapper → UART) valós CIL-T0 programmal.
    en: End-to-end FibonacciIterative(20) = 6765 — on KEY2 the wrapper
        starts the Roslyn-compiled CIL-T0 binary, pushes N=20, prints
        "6765\\r\\n" on UART. Sub3's main demo: full toolchain
        (C# → Roslyn → linker → core → wrapper → UART) on a real CIL-T0
        program."""
    code_bytes = _build_fibonacci_t0("FibonacciIterative")
    await _setup(dut, code_bytes)

    await _press_start(dut)
    line = await _read_uart_line(dut, max_bytes=16)
    expected = f"{EXPECTED_RESULT}\r\n".encode("ascii")
    assert line == expected, f"expected {expected!r}, got {line!r}"

    assert int(dut.r_halted.value) == 1, "halt latch should be set"
    assert int(dut.r_trapped.value) == 0, "trap latch should be clear"
    assert int(dut.o_led1_n.value) == 0, "halt LED should be active"
    assert int(dut.o_led2_n.value) == 1, "trap LED should be inactive"
