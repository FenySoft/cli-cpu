# CLI-CPU FPGA integration (F2.7 — A7-Lite XC7A200T)

> Magyar verzió: [README-hu.md](README-hu.md)

> Version: 0.5.2 (Sub5.A + doc-sync)

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
| Sub5 | Vivado + OpenXC7 build + write_cfgmem + XDC timing + bring-up runbook | 🔧 Build-infra done (HW bring-up pending on the user) |

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

**Note:** The `iterative FibonacciIterative` is the accepted Sub3 demo —
it exercises the loop opcode coverage (`LDLOC/STLOC`, `ADD/SUB`,
`BLT_S/BR_S`) across the end-to-end toolchain.

**Recursive Math.Fibonacci — RESOLVED (F2.7.D, commit `762536b`):** The
Roslyn-linked **recursive** `Math.Fibonacci` (CALL self) used to trap
with `TRAP_STACK_UNDERFLOW` at depth ~5 when run via the wrapper boot
pattern (no caller frame, `boot_pc=8` directly into the Fib body). Root
cause: `RET_FINALIZE` reset the caller Stack Cache to the eval base,
discarding eval elements that must be preserved across the call.
3-module root-cause fix (`cilcpu_stack_cache.v` flush + sp_depth;
`cilcpu_core.v` ST_CALL/ST_RET frame-eval preservation). The recursive
Roslyn Fibonacci is now green with the wrapper boot pattern too:
`test_52c_recursive_fib10_roslyn_boot_no_caller` (Fib(10)=55). Vault:
`project_recursive_call_bug` (RESOLVED).

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

## Sub5 — Vivado + OpenXC7 build + bring-up

> **Important — scope boundary:** Synthesis, PnR, `write_bitstream`,
> `write_cfgmem`, 50 MHz timing closure and physical bring-up run **on
> the user's WSL machine and A7-Lite hardware** — they are NOT runnable
> in this session (no `vivado`/`yosys`/`nextpnr-xilinx`, no HW). Sub5
> acceptance is therefore: **build infrastructure + bring-up runbook
> done**; the actual HW verification (timing WNS ≥ 0, UART "6765\r\n")
> is pending on the user.

**Goal:** Compile the Sub4 board.v into a real bitstream on both
toolchains, embed the CIL-T0 application binary into the config flash,
and reproduce on hardware the "6765\r\n" pattern proven in the Sub3/Sub4
sim.

**New files:**

| File | Role |
|------|------|
| [`Vivado/create_project.tcl`](Vivado/create_project.tcl) | Full `cilcpu_a7lite_board` project: synth → impl → write_bitstream + timing report. Part `xc7a200tfbg484-2` |
| [`Vivado/write_cfgmem.tcl`](Vivado/write_cfgmem.tcl) | `.bit` + CIL-T0 `.t0` → one `.mcs` (SPIx4, 16 MB IS25L128F) |
| [`OpenXC7/Makefile`](OpenXC7/Makefile) | Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit, full source tree |
| [`OpenXC7/build.sh`](OpenXC7/build.sh) | WSL launcher (PATH, S: mount, `make`) |
| [`OpenXC7/cilcpu_a7lite.xdc`](OpenXC7/cilcpu_a7lite.xdc) | OpenXC7-format constraint (no `-dict`) |
| [`scripts/build_app_bin.sh`](scripts/build_app_bin.sh) | `dotnet build` → linker → `.t0` (parameterizable method/N) |

**Source-tree parity:** Both builds synthesize the **same** RTL source
tree as the `rtl/tb/Makefile` `test_a7lite_board_fib` `VERILOG_SOURCES`
list, **without** `sim_stubs/` — on FPGA, STARTUPE2 + IOBUF are the
Vivado 'unisims' / Yosys `synth_xilinx` built-in cells. `cilcpu_defines.vh`
is added as an include path.

**Flash-offset parity (sim ↔ cfgmem) — RESOLVED in Sub5.A:**

The `cilcpu_qspi_controller` maps the CODE segment
(`cpu_addr[23:20]=0x0`) to flash address
`CODE_BASE_OFFSET + {4'h0, cpu_addr[19:0]}`. `CODE_BASE_OFFSET` is a
parameterizable generic (Sub5.A), threaded through the full
instantiation chain (`cilcpu_qspi_controller` ← `cilcpu_core` ←
`cilcpu_a7lite_top` ← `cilcpu_a7lite_board`):

- **SIM:** default `0` → the cocotb `TQSPIFlashModel` stores `.t0[i]`
  at flash address `i` → **bit-identical sim parity**, every existing
  test stays green (`BOOT_PC=0x08`).
- **FPGA:** Vivado `create_project.tcl`
  `set_property generic CODE_BASE_OFFSET=32'hC00000` (12 MB), OpenXC7
  `Makefile` `chparam -set CODE_BASE_OFFSET 12582912`, and
  `write_cfgmem.tcl` embeds the `.t0` at EXACTLY `0x00C00000`. The
  config-flash loads `.bit` from 0x0 (SPIx4 master config); the app
  sits **ABOVE the ~9.9 MB XC7A200T bitstream** → **no collision** on
  the IS25L128F (16 MB; app window 1 MB: `0xC00000..0xCFFFFF`).

> **SINGLE SOURCE:** the `CODE_BASE_OFFSET` generic, the
> `write_cfgmem.tcl` `CODE_BASE_OFFSET_HEX` and the OpenXC7
> `CODE_BASE_OFFSET` must ALWAYS match (all three = 12 MB). The 2nd
> `write_cfgmem.tcl` arg only overrides it if you set the generic to
> the same value. Source: `rtl/src/cilcpu_qspi_controller.v` ST_IDLE
> `SEG_CODE` branch (`CODE_BASE_OFFSET`) +
> `rtl/tb/test_qspi_controller.py` test_30/31.
>
> Note: `SEG_DATA` (flash `{4'h1, cpu_addr[19:0]}` = 0x100000) was
> **intentionally NOT offset** — current int-only CIL-T0 programs
> (PureMath) use no static DATA flash region, sim parity (test_08)
> relies on this offset-less mapping, and offsetting it with no
> test/use-case would be over-engineering. If DATA becomes flash-backed,
> a separate task + test is required (see `todo.md`).

**XDC timing tightening (`cilcpu_a7lite.xdc`):**

- `create_clock -period 20.000` on `i_clk_50m` (J19) — explicit 50 MHz
  primary constraint (unchanged, present since Sub1).
- `qspi_sck` `create_generated_clock` = sys_clk / 2 = 25 MHz (unchanged).
- `set_input_delay` / `set_output_delay` tightened with IS25L128F
  (ISSI) datasheet 0x6B Quad Output Read values: tCLQV max 7.0 ns,
  tCLQX min 1.5 ns, tDVCH/tCHDX min 2.0 ns, CS# tSLCH/tCHSH min 5.0 ns,
  estimated FBG484+PCB trace skew ~0.5 ns. Input window widened by the
  skew (−min 1.0 / −max 7.5), output by flash s/h (−2.5 / +2.5).

**OpenXC7 STARTUPE2 — supported upstream, to be verified here:**

`IOBUF` **is supported** in the nextpnr-xilinx/prjxray flow (DQ[3:0]
bus fine). **STARTUPE2** (config-bank startup block, user CCLK via
`USRCCLKO`): the `openXC7/nextpnr-xilinx` issue **#13** ("Prioritize
BSCANE2 + STARTUPE2") was **closed, completed 2024-02** → it **became
supported** in the upstream toolchain. The project-specific artix7
`USRCCLKO` path is **not yet empirically verified in this project** —
the first WSL build will decide. So **OpenXC7 is a first-class Sub5
target for the grant "fully open" deliverable; the empirically
verified path is so far Vivado.** Per the single-layer-trust /
no-compromise principle we **state the actual status** (supported
upstream, unverified here) — neither working around it with a fake
stub nor over-claiming: if nextpnr-xilinx still fails on STARTUPE2 it
is a documented, to-be-verified risk, not an RTL/XDC bug. (Note: the
smoke-test LED-blink passed on OpenXC7 on 2026-04-24 without STARTUPE2
— STARTUPE2 is a new requirement introduced by board.v.)

App binary on the OpenXC7 path: after `xc7frames2bit`, separate
flash-image concatenation or `openFPGALoader` (`--external-flash`,
`-o <offset>`) — the exact step is in the bring-up runbook.

**Run (on the user's WSL machine):**

```bash
# 1. App binary (CIL-T0 .t0) — same linker command as the sim
rtl/fpga/scripts/build_app_bin.sh           # FibonacciIterative, N=20

# 2a. Vivado (primary path)
cd rtl/fpga/Vivado
vivado -mode batch -source create_project.tcl
vivado -mode batch -source write_cfgmem.tcl -tclargs build/app.t0

# 2b. OpenXC7 (first-class target; artix7 STARTUPE2/USRCCLKO to verify here)
cd rtl/fpga/OpenXC7
bash build.sh check-env
bash build.sh chipdb        # one-time, ~5-10 min
bash build.sh all
```

**Bring-up runbook (on the user's A7-Lite hardware):**

1. **JTAG bitstream upload (quick smoke):** Vivado Hardware Manager →
   Open target → Auto Connect → Program Device →
   `cilcpu_a7lite_board.bit`. (RAM-only, no flash — quick function check.)
2. **Config flash programming:** Hardware Manager → Add Configuration
   Memory Device → `is25lp128f` (IS25L128F-compatible, 128 Mbit) →
   Program Configuration Memory Device → `build/cilcpu_a7lite.mcs`.
   (Loads bitstream + the `.t0` app binary.) On OpenXC7:
   `openFPGALoader -b <board> --write-flash cilcpu_a7lite.bit`, the app
   image at a separate offset.
3. **UART terminal:** CH340 USB-serial, **115200 baud, 8N1**, no flow
   control. (Linux: `screen /dev/ttyUSB0 115200`; Windows: PuTTY /
   TeraTerm.)
4. **Power-cycle / KEY1 reset:** the FPGA configures from flash, then in
   user mode the core reads the CIL-T0 from the QSPI flash.
5. **Press KEY2 (W1):** the boot FSM starts the core with N =
   `BOOT_ARG_VALUE` (=20).
6. **Expected output:** on the UART terminal **`6765\r\n`** (= Fib(20)),
   the **D6 LED (M18) lit** (halt latch), D5 (trap) **dark**. On a trap,
   D5 lights and the UART prints the trap code in decimal.

**What is left to the user (explicit):** the actual synthesis/PnR run,
producing the `write_bitstream`/`write_cfgmem`, **verifying 50 MHz
timing closure** (sys_clk WNS ≥ 0 from `timing_summary.rpt`), observing
the actual OpenXC7 STARTUPE2 failure, and the hardware bring-up (UART
"6765\r\n"). Sub5 acceptance is the build infra + runbook; HW
verification on these deliverables remains open.

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
| 0.4.1 | 2026-05-17 | F2.7.D recursive CALL/RET root-cause fix propagated (commit 762536b); Sub3 "Known bug" resolved, test_52c green |
| 0.5 | 2026-05-17 | Sub5 build infra — Vivado `create_project.tcl` + `write_cfgmem.tcl`, OpenXC7 `Makefile`/`build.sh`/XDC, `scripts/build_app_bin.sh`, XDC timing tightening (IS25L128F datasheet). Flash-offset parity 0x000000 (sim ↔ cfgmem); OpenXC7 STARTUPE2 limitation openly documented; bring-up runbook. Synthesis/timing/bring-up pending on the user (not HW-verified) |
| 0.5.1 | 2026-05-17 | Sub5.A — parameterizable `CODE_BASE_OFFSET` generic (qspi_controller ← core ← a7lite_top ← board). Flash-collision "open question" → RESOLVED: sim default 0 (bit-identical parity), FPGA 0xC00000 (12 MB, above the ~9.9 MB bitstream). Single source: generic = write_cfgmem `CODE_BASE_OFFSET_HEX` = OpenXC7 chparam. 2 new cocotb tests (test_30/31) + 7 regression targets green; SEG_DATA intentionally not offset (rationale in the Sub5 section) |
| 0.5.2 | 2026-05-17 | Doc-sync (`cascade-changes`): OpenXC7 README flash-offset "open question" → brought to Sub5.A RESOLVED; STARTUPE2 status corrected across all READMEs (`openXC7/nextpnr-xilinx #13` closed 2024-02 → supported upstream, project-specific artix7 USRCCLKO to be empirically verified here), "best-effort" → first-class Sub5 target for the grant ("fully open" NLnet) |
