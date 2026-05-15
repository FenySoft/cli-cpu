# CLI-CPU FPGA integration (F2.7 — A7-Lite XC7A200T)

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 0.1 (Sub1)

This directory holds the CLI-CPU Nano core FPGA integration for the
**MicroPhase A7-Lite XC7A200T** reference board. The goal is to validate the
core on real silicon **before** the F3 Tiny Tapeout submission.

## Sub-iterations

| Sub | Scope | Status |
|-----|-------|--------|
| Sub1 | Top-level wrapper + cocotb integration test | ✅ DONE |
| Sub2 | UART TX + 32-bit decimal printer | ✅ DONE |
| Sub3 | Fibonacci demo program + parameterized boot | ✅ DONE |
| Sub4 | QSPI flash binding (IS25L128F + STARTUPE2 + IOBUF) | ✅ DONE |
| Sub5 | Vivado + OpenXC7 build, 50 MHz timing closure | ⬜ Planned |

## Sub1 — Top-level wrapper

**Files:**

| File | Role |
|------|------|
| [`cilcpu_a7lite_top.v`](cilcpu_a7lite_top.v) | Top-level wrapper around `cilcpu_core` |
| [`cilcpu_a7lite.xdc`](cilcpu_a7lite.xdc) | Vivado XDC pin assignment (clock + KEYs + LEDs) |

**Wrapper building blocks:**

1. **Reset synchronizer** — async assert / sync deassert, 3-stage. Driven by
   KEY1 (AA1), active low.
2. **Start button (KEY2, W1)** — 2-stage CDC synchronizer + parameterized
   debouncer (`DEBOUNCE_BITS`, default 22 = ~84 ms @ 50 MHz, reduced to 4 in
   sim) + falling-edge detector.
3. **Boot sequencer FSM** — 6 states: IDLE → INIT → ARG_WAIT → ARG_DRV
   → RUN → DONE. On KEY2 press, starts the core, pushes arguments
   (`o_boot_arg_ready` handshake), then watches `o_halt` / `o_trap` in RUN.
4. **Halt / trap latch** — `r_halted` and `r_trapped` registers held until
   next reset, giving visible LED output.
5. **LED outputs** — `o_led1_n` (M18) = halt indicator, `o_led2_n` (N18) =
   trap indicator. Active low (anode on VCC, cathode on pin).
6. **Core instantiation** — every `cilcpu_core` port wired to wrapper signals.
   QSPI ports pass through to top-level (finalized in Sub4 to bind to the
   board's IS25L128F flash).

**Sub1 parameters:**

```verilog
parameter [23:0] BOOT_PC          = 24'h000008;  // 8 bytes after header
parameter [7:0]  BOOT_ARG_COUNT   = 8'd1;
parameter [7:0]  BOOT_LOCAL_COUNT = 8'd0;
parameter [31:0] BOOT_ARG_VALUE   = 32'd5;
parameter integer DEBOUNCE_BITS   = 22;          // sim: 4
```

**cocotb tests (`rtl/tb/test_a7lite_top.py`):**

| Test | Scope |
|------|-------|
| `test_01_reset_state` | LEDs inactive after reset |
| `test_02_idle_no_start` | Core does not start without start button |
| `test_03_ldarg_ret_smoke` | KEY2 → push 5 → LDARG_0 + RET → return = 5, halt LED |
| `test_04_ldarg_add_smoke` | KEY2 → push 5 → LDARG_0 + LDC.I4_3 + ADD + RET → 8 |
| `test_05_invalid_opcode_trap` | 0xFF opcode → trap, trap LED |
| `test_06_short_press_ignored` | Sub-debounce-limit pulse rejected |

**Run:**

```bash
cd rtl/tb
make test_a7lite_top
```

**Result:** TESTS=6 PASS=6 FAIL=0 (~40 µs sim time @ 50 MHz, ~0.05s wall).

## What Sub1 does NOT cover

- Core functionality (LDC, ALU, branch, CALL, RET, trap aggregator) is
  already fully covered by 48 `test_core.py` cocotb tests (F2.5a/b), so the
  wrapper test is smoke-level only. After Sub1 the existing test_core
  regression remains **48/48 green**.
- No UART → halt / trap result is only visible on LEDs and (in Vivado)
  via ILA probes. UART TX comes in Sub2.
- The QSPI ports surface to the wrapper top, but the XDC binding is deferred
  to Sub4.

## Shared cocotb modules

Sub1 introduces two shared modules so the wrapper test and future top-level
tests don't duplicate code:

- [`rtl/tb/tb_qspi.py`](../tb/tb_qspi.py) — `TQSPIFlashModel` + `qspi_flash_driver`
- [`rtl/tb/tb_isa.py`](../tb/tb_isa.py) — opcode / trap constants + `make_method` header builder

The existing `test_core.py` is unchanged (kept self-contained because it's
already stable).

## Sub2 — UART TX + decimal printer

**New files:**

| File | Role |
|------|------|
| [`uart_tx.v`](uart_tx.v) | 8N1 UART transmitter, parameterizable `CLOCKS_PER_BAUD` |
| [`decimal_printer.v`](decimal_printer.v) | 32-bit signed/unsigned int → ASCII decimal → UART, terminated with `\r\n` |

**Wrapper extension:**

- New top-level port: `o_uart_tx` (V2, CH340 USB-UART bridge)
- New parameter: `CLOCKS_PER_BAUD` (FPGA: 434 = 50 MHz / 115200; sim: 8)
- Boot FSM extended: `S_PRINT_REQ` → `S_PRINT_WAIT` → `S_DONE`. On halt the
  wrapper passes the value as signed; on trap as unsigned.
- Internal `decimal_printer` instance, which itself drives a `uart_tx`.

**XDC extension:** `o_uart_tx` → V2 (LVCMOS33, DRIVE 8).

**cocotb tests:**

| Test | Scope | Result |
|------|-------|--------|
| `test_uart_tx.py` (8 tests) | Standalone UART TX (idle, byte patterns, busy, back-to-back) | 8/8 PASS |
| `test_decimal_printer.py` (10 tests) | Standalone printer (0, single/multi digit, INT32 MIN/MAX, 6765 = Fibonacci(20), back-to-back) | 10/10 PASS |
| `test_a7lite_top.py` Sub2 additions | `test_07`: halt → UART "5\r\n", `test_08`: trap → UART "3\r\n" | 2/2 PASS |

**New shared cocotb module:** [`tb_uart.py`](../tb/tb_uart.py) — `uart_rx_byte`
and `uart_rx_string` 8N1 decoders for wrapper UART output verification.

**Run:**

```bash
cd rtl/tb
make test_uart_tx          # 8/8 PASS
make test_decimal_printer  # 10/10 PASS
make test_a7lite_top       # 8/8 PASS (6 Sub1 + 2 Sub2)
```

**Synthesis preview:** The printer's `r_abs / 32'd10` (32-bit / 10) is
synthesized by both Yosys and Vivado — actual LUT/DSP area will be measured
in the Sub5 build. In sim it is accepted as a combinational path,
~3 cycles/digit, ~24 cycles for an 8-digit number.

## Sub3 — Fibonacci(20) end-to-end demo

**Goal:** Verify the full toolchain (C# → Roslyn → CIL-T0 linker → core →
wrapper → UART) on the wrapper with a real CIL-T0 binary.

**New C# method** (`samples/PureMath/Math.cs`):
```csharp
public static int FibonacciIterative(int n)
{
    if (n < 2) return n;
    int a = 0;
    int b = 1;
    for (int i = 2; i <= n; i++)
    {
        int c = a + b;
        a = b;
        b = c;
    }
    return b;
}
```

The linker emits a 40-byte `.t0` binary (8 bytes header + 32 bytes body)
using `LDLOC/STLOC`, `ADD/SUB`, `BLT_S/BR_S` opcodes — all 100% covered
in the `cilcpu_core` Sub3/Sub4 implementation.

**Wrapper parameter change:** `BOOT_PC`, `BOOT_ARG_COUNT`,
`BOOT_LOCAL_COUNT`, `BOOT_ARG_VALUE` are now declared `parameter integer`
(32-bit) so the Verilator `-G<name>=<value>` command-line override does not
raise WIDTHTRUNC. The wrapper slices each parameter to the right width
internally. This makes the sim build parameterizable:

```bash
make test_a7lite_fib  # -GBOOT_ARG_VALUE=20 -GBOOT_LOCAL_COUNT=4
```

**New cocotb test** (`test_a7lite_fib.py`):
- Calls `dotnet $RUNNER_DLL link ... --method FibonacciIterative` at runtime
- Loads the `.t0` bytes into the flash slave
- KEY2 press → wrapper boots with N=20 → core runs → halt → UART
- Expected: `"6765\r\n"` (= Fib(20))
- **Result: 1/1 PASS** (~1.13ms sim time, ~1.35s wall time)

**Known bug — recursive Math.Fibonacci:** The Roslyn-linked **recursive**
`Math.Fibonacci` (CALL self) traps with `TRAP_STACK_UNDERFLOW` at depth ~5
when run via the wrapper boot pattern (no caller frame, `boot_pc=8` directly
into the Fib body). The hand-coded `test_52_call_recursive_fib_5` (with a
caller frame) is green; the `TCpuNano` C# sim also returns Fib(10)=55
correctly with the same binary. The bug lives in the `cilcpu_core.v` Sub5
frame manager teardown logic when the "root frame" was not created by a
CALL. **Sub3 workaround: iterative variant** (loop, same result, exercises
fewer opcodes). Fix deferred to a separate debug sprint — see Vault entry
`project_recursive_call_bug`.

**Run:**

```bash
# Prereq:
dotnet build CLI-CPU.sln -c Debug

cd rtl/tb
make test_a7lite_fib  # 1/1 PASS — UART "6765\r\n"
```

## Sub4 — QSPI flash binding (IS25L128F)

**Goal:** A board-level wrapper around `cilcpu_a7lite_top` that drives the
flash CCLK via the Xilinx 7-series **STARTUPE2** primitive (CCLK lives in
the dedicated config bank and cannot be reached as a regular GPIO in user
mode), and uses four **IOBUF** primitives for the DQ[3:0] inout bus. The
IS25L128F (128 Mbit) QSPI flash is the board's configuration flash —
after bitstream load, the core also reads its CIL-T0 program from there
in user mode.

**New files:**

| File | Role |
|------|------|
| [`cilcpu_a7lite_board.v`](cilcpu_a7lite_board.v) | Board-level (FPGA) top wrapper. `cilcpu_a7lite_top` + STARTUPE2 + 4 IOBUFs |
| [`sim_stubs/xilinx_primitives_sim.v`](sim_stubs/xilinx_primitives_sim.v) | Behavioral STARTUPE2 + IOBUF stub for Verilator (instead of Xilinx 'unisims' in sim) |

**Architecture decision:**

board.v has two modes via the `+define+CILCPU_SIM_BOARD` macro:

- **FPGA build** (Vivado/OpenXC7, macro undefined): port interface is
  `output o_qspi_cs_n` + `inout wire [3:0] io_qspi_dq`, the four IOBUFs
  separate master-driven (CMD/ADDR) and flash-driven (DATA) phases.
- **Sim build** (Verilator + cocotb, `+define+CILCPU_SIM_BOARD`): IOBUFs
  omitted (Verilator would emit a multi-driver conflict on `assign IO =
  T ? 'bz : I` racing against an external driver), replaced by split
  debug ports (`o_qspi_dq_out_dbg`, `i_qspi_dq_in_dbg`, `o_qspi_dq_oe_dbg`,
  `o_qspi_clk_dbg`) wired straight to the internal nets.

STARTUPE2 is instantiated in both modes: real Xilinx 'unisims' primitive
in FPGA, behavioral stub in sim (USRCCLKO is transparent — observable on
the board.v internal `w_qspi_clk_user` net for the flash slave).

**XDC update** (`cilcpu_a7lite.xdc`):

- Top module switch: `cilcpu_a7lite_top` → `cilcpu_a7lite_board`
- `o_qspi_cs_n` (T19), `io_qspi_dq[0..3]` (P22, R22, P21, R21) pin assignment
- CCLK NOT in `set_property PACKAGE_PIN` — STARTUPE2 drives it
- `create_generated_clock` on the STARTUPE2 USRCCLKO path: `qspi_sck` =
  sys_clk / 2 = 25 MHz
- `set_input_delay` / `set_output_delay` from the IS25L128F datasheet
  (tV max 7 ns, tIS / tIH 2 ns; tightened in Sub5)

**cocotb tests:**

| Test | Scope | Result |
|------|-------|--------|
| [`test_a7lite_board.py`](../tb/test_a7lite_board.py) | Reset + LDARG/RET + LDARG+ADD + INVALID_OPCODE trap, UART "5\r\n" / "3\r\n" | 4/4 PASS |
| [`test_a7lite_board_fib.py`](../tb/test_a7lite_board_fib.py) | FibonacciIterative(20) = 6765 through board.v | 1/1 PASS |

Both tests route the flash slave ↔ master traffic through STARTUPE2 +
(in sim, no-op) IOBUFs — proves the new board.v layer is not a
regression vs. the Sub3 demo.

**Run:**

```bash
cd rtl/tb
make test_a7lite_board       # 4/4 PASS
make test_a7lite_board_fib   # 1/1 PASS — UART "6765\r\n" via board.v
```

**Deferred to Sub5:**

- Vivado / OpenXC7 build with board.v actually targeting IS25L128F
- Bitstream `write_cfgmem` flow (app binary embedded in the config flash
  or as a separate JEDEC/MCS sector)
- 50 MHz timing closure (refining the `qspi_sck` constraint from real
  measurement)
- Real A7-Lite bring-up — UART terminal over CH340

## Smoke test (LED blink)

Separate folder: [`smoke_test/`](smoke_test/) — board bring-up LED blink on
two toolchains (Vivado and OpenXC7). Verified on real hardware on
2026-04-24. Not part of F2.7, but proves the flow is operational.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 0.1 | 2026-05-08 | Sub1 — top-level wrapper skeleton + 6 cocotb tests green |
| 0.2 | 2026-05-08 | Sub2 — UART TX + decimal printer (8+10+2 cocotb tests green); halt/trap on UART |
| 0.3 | 2026-05-10 | Sub3 — FibonacciIterative(20) end-to-end UART "6765\r\n"; recursive bug deferred |
| 0.4 | 2026-05-14 | Sub4 — board.v wrapper STARTUPE2 + IOBUF; XDC with QSPI pins; 4+1 new cocotb tests green |
