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
| Sub2 | UART TX + 32-bit decimal printer | ⬜ Planned |
| Sub3 | Fibonacci(20) demo program + parameterized boot | ⬜ Planned |
| Sub4 | QSPI flash binding (IS25L128F) | ⬜ Planned |
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

## Smoke test (LED blink)

Separate folder: [`smoke_test/`](smoke_test/) — board bring-up LED blink on
two toolchains (Vivado and OpenXC7). Verified on real hardware on
2026-04-24. Not part of F2.7, but proves the flow is operational.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 0.1 | 2026-05-08 | Sub1 — top-level wrapper skeleton + 6 cocotb tests green |
