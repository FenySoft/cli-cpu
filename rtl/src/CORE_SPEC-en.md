# F2.5a Top-level Nano Core — Contract and Port Spec

> Hungarian version: [CORE_SPEC-hu.md](CORE_SPEC-hu.md)

> Internal working spec for the TDD cycle. Golden reference: `TCpuNano` (`src/CilCpu.Sim/TCpuNano.cs`).
>
> **Scope:** Internal RTL working spec, not a public document. The public ISA spec is `docs/ISA-CIL-T0-{hu,en}.md`, the public architecture is `docs/architecture-en.md`.
>
> Version: 1.2

## Goal

Integrate the 5 submodules (`cilcpu_alu`, `cilcpu_decoder`, `cilcpu_microcode`, `cilcpu_stack_cache`, `cilcpu_qspi_controller`) into a single **Nano core**: fetch → decode → execute pipeline, PC management, frame manager, internal 16 KB SRAM, trap aggregator, halt FSM. The core reproduces the F1 `TCpuNano` behavior with the F2.4 RTL primitives.

**F2.5a scope** (what's in here):
- Internal 16 KB SRAM as `reg [31:0] sram[0:4095]` inferred BRAM (foundry SRAM macro deferred to F2.6)
- Simple byte-level fetch buffer with 5-byte minimum (I-cache deferred to F5+)
- Stack region **only in internal SRAM** — overflow → `TRAP_SRAM_OVERFLOW` (PSRAM spill deferred to F5+)
- No HEAP region (Nano core has none — F5 Rich)
- No MMIO (mailbox in F3, UART in F2.7)

**F2.5a does NOT include** (deferred to F2.5b):
- Golden vector harness (cocotb vs C# sim trace comparison)
- C# simulator `--trace` export

## Module: `cilcpu_core`

### Ports

| Dir | Name | Width | Description |
|-----|------|-------|-------------|
| **Clock / reset** | | | |
| in | `clk` | 1 | Main clock (50 MHz) |
| in | `rst_n` | 1 | Async active-low reset |
| **Boot config** | | | |
| in | `i_boot_pc` | 24 | Entry point byte offset within CODE segment (`TMethodHeader` RVA + `METHOD_HEADER_SIZE`) |
| in | `i_boot_arg_count` | 8 | Boot frame argument count (0..16) |
| in | `i_boot_local_count` | 8 | Boot frame local count (0..16) |
| in | `i_boot_start` | 1 | 1-cycle pulse to start execution (RESET → BOOT FSM branch) |
| in | `i_boot_arg_data` | 32 | Argument streaming input (delivers arg values during the boot sequence) |
| in | `i_boot_arg_valid` | 1 | `i_boot_arg_data` is valid (1-cycle pulse per arg) |
| out | `o_boot_arg_ready` | 1 | Core is ready to accept the next arg (during boot sequence) |
| **Status / observability** | | | |
| out | `o_halt` | 1 | Core halted (RET on root frame) — TOS value is the return value |
| out | `o_trap` | 1 | A trap occurred (1-cycle pulse, then halt-like state) |
| out | `o_trap_code` | 8 | `TTrapReason` byte (valid only on cycles where `o_trap=1`) |
| out | `o_pc` | 24 | Current PC (debug observability) |
| out | `o_return_value` | 32 | TOS value at halt (root frame return value) |
| **QSPI pins** | | | |
| out | `qspi_clk` | 1 | QSPI clock (clk / 2 = 25 MHz) |
| out | `qspi_cs_flash_n` | 1 | Flash chip select (active-low) |
| out | `qspi_cs_psram_n` | 1 | PSRAM chip select (active-low; F2.5a: always 1 — unused) |
| out | `qspi_dq_out` | 4 | DQ output |
| in | `qspi_dq_in` | 4 | DQ input |
| out | `qspi_dq_oe` | 1 | DQ output enable |

### Internal 16 KB SRAM

`reg [31:0] r_sram[0:4095]` (4096 × 32-bit = 16 KB) inside the core, Verilog inferred BRAM. **Not an external interface** — the Stack Cache `sram_*` master ports and the microcode SRAM accesses connect here through an internal 2:1 mux (see "Memory bus arbiter").

After reset the entire SRAM is zeroed — matches the C# `byte[] FSram = new byte[16384]` behavior.

### Internal state (beyond submodule registers)

| Register | Width | Description |
|----------|-------|-------------|
| `r_state` | 4 | Top-level FSM state |
| `r_pc` | 24 | Program counter (CODE segment byte offset) |
| `r_sp` | 14 | Stack pointer (SRAM byte address) |
| `r_fp` | 14 | Frame pointer (current frame base, SRAM byte address) |
| `r_call_depth` | 10 | Call depth counter (0..512) |
| `r_arg_count` | 5 | Current frame arg count (0..16) |
| `r_local_count` | 5 | Current frame local count (0..16) |
| `r_step` | 4 | Microcode micro-step counter |
| `r_opcode` | 16 | Current decoded opcode (microcode input) |
| `r_length` | 3 | Current instruction length (1..5) |
| `r_operand` | 32 | Current instruction operand |
| `r_fetch_buf` | 8×8 | 8-byte rolling fetch buffer (FIFO) |
| `r_fetch_count` | 4 | Valid byte count in buffer (0..8) |
| `r_fetch_pc` | 24 | PC of the buffer's first byte (always `≤ r_pc`) |
| `r_halt` | 1 | Halt latch |
| `r_trap` | 1 | Trap latch (1-cycle pulse, then 0) |
| `r_trap_code` | 8 | Trap code latch |
| `r_boot_args_remaining` | 5 | Remaining boot args (0..16) |

### Top-level FSM states

```
localparam [3:0] ST_RESET     = 4'd0;   // Post-reset init state
localparam [3:0] ST_BOOT      = 4'd1;   // Boot frame setup (header + args + locals)
localparam [3:0] ST_FETCH     = 4'd2;   // Fetch buffer fill (5 bytes guaranteed)
localparam [3:0] ST_DECODE    = 4'd3;   // 1 cycle: decoder result → r_opcode/r_length/r_operand
localparam [3:0] ST_EXECUTE   = 4'd4;   // Microcode sequencer runs (1..N cycles)
localparam [3:0] ST_MEM_WAIT  = 4'd5;   // Stack cache spill/fill OR QSPI fetch wait
localparam [3:0] ST_CALL      = 4'd6;   // Call frame setup (header + args copy)
localparam [3:0] ST_RET       = 4'd7;   // Ret: header read, frame teardown
localparam [3:0] ST_HALT      = 4'd8;   // Halt — final state
localparam [3:0] ST_TRAP      = 4'd9;   // Trap — final state (halt-like)
```

### Boot sequence (ST_RESET → ST_BOOT → ST_FETCH)

After reset, the core builds the **root frame** at the start of SRAM (`r_fp = 0`):

1. **ST_RESET** (after `rst_n`): `r_pc = 0`, `r_sp = 0`, `r_fp = 0`, `r_call_depth = 0`, all trap/halt = 0. `o_boot_arg_ready = 0`. Waits for `i_boot_start`.
2. **`i_boot_start = 1` pulse** → ST_BOOT, `r_arg_count <= i_boot_arg_count`, `r_local_count <= i_boot_local_count`, `r_boot_args_remaining <= i_boot_arg_count`.
3. **ST_BOOT** sub-states (sequenced):
   - **Header write** (3 SRAM writes): `[FP+0] <= -1` (ReturnPC), `[FP+4] <= -1` (PrevFrameBase), `[FP+8] <= {16'h0, local_count, arg_count}` (upper 16 bits reserved=0, matching the TCpuNano format)
   - **Args streaming**: on each `i_boot_arg_valid=1` cycle `[FP + 12 + idx*4] <= i_boot_arg_data`, `idx++`. Between args `o_boot_arg_ready=1` signals readiness for the next.
   - **Locals zeroing**: `r_local_count` writes, all 0
   - **Frame finalize**: `r_sp <= 12 + arg_count*4 + local_count*4`, `r_call_depth <= 1`, `r_pc <= i_boot_pc`. Stack cache `sp_load=1`, `sp_init = r_sp` (empty eval stack on this frame).
4. **→ ST_FETCH**: execution starts.

**Note:** This boot sequence form matches `TCpuNano.Execute(byte[] AProgram, int AArgCount, int ALocalCount, int[]? AInitialArgs)` — the test harness passes the same init parameters.

### Fetch unit (ST_FETCH)

**Goal:** guarantee that the Decoder always sees 5 bytes (`i_bytes_available = min(r_fetch_count, 5)`), except at end of CODE segment.

**Buffer:** 8-byte FIFO (the 4-byte QSPI burst makes anything narrower than 5 bytes unhelpful; 8 bytes adds slack after 5-byte instructions with the `0xFE` prefix).

**Logic:**
- If `r_fetch_count >= 5` → `→ ST_DECODE` (no fetch needed)
- If `r_fetch_count < 5` → QSPI controller `cpu_re=1`, `cpu_addr = {4'h0, r_pc + r_fetch_count[7:0]}` (CODE segment, 4-byte burst). Wait for `cpu_ready=1`.
- On `cpu_ready=1`: `r_fetch_buf[r_fetch_count +: 4] <= cpu_rdata` (4-byte append), `r_fetch_count += 4`.
- If `r_fetch_count >= 5` → `→ ST_DECODE`.

**On PC jump (branch/call/ret) the buffer is flushed:** `r_fetch_count <= 0`, `r_fetch_pc <= new_pc`, fetch restarts.

**FETCH and DECODE timing:** ST_DECODE takes 1 cycle (the decoder is combinational, the result is latched to a register). Then → ST_EXECUTE.

### Sequencer (ST_EXECUTE)

The microcode is combinational — `i_opcode = r_opcode`, `i_step = r_step`. On every cycle the `o_ctrl` control word is decoded and the enable signals expanded:

| Control field | Effect |
|---------------|--------|
| `UC_TRAP=1` | `r_trap <= 1`, `r_trap_code <= o_ctrl[UC_TRAP_CODE_HI:UC_TRAP_CODE_LO]`, `→ ST_TRAP` |
| `UC_HALT=1` | `r_halt <= 1`, `→ ST_HALT` |
| `UC_STACK_POP_HI:LO` | Stack Cache `pop_en=1`, N times (1 or 2) |
| `UC_STACK_PUSH=1` | Stack Cache `push_en=1`, `push_data = mux(UC_PUSH_SRC_*)` |
| `UC_ALU_EN=1` | ALU `i_op_a = stack_cache.tos1`, `i_op_b = stack_cache.tos`, `i_alu_op = UC_ALU_OP_*` |
| `UC_SRAM_RD=1` | Internal SRAM read, address = `addr_calc(UC_ADDR_SRC_*)` |
| `UC_SRAM_WR=1` | Internal SRAM write, address = `addr_calc(UC_ADDR_SRC_*)`, data = `pop_data` |
| `UC_PC_WR=1` | PC update, source = `UC_PC_SRC_*` |
| `UC_FRAME_PUSH=1` | `→ ST_CALL` (sequencer runs the call sequence multi-cycle) |
| `UC_FRAME_POP=1` | `→ ST_RET` |
| `UC_COND_EN=1` | Branch condition evaluation (see below) |
| `UC_DONE=1` | `r_step <= 0`, **the control word effects apply** in this cycle, then `→ ST_FETCH` |
| otherwise | `r_step += 1`, `→ ST_EXECUTE` (next microstep) |

**Push source mux:**
- `PUSH_SRC_ALU` → ALU `o_result`
- `PUSH_SRC_IMM` → `r_operand` (or `r_operand[7:0]` for 1-byte short forms — handled per-opcode in the microcode)
- `PUSH_SRC_SRAM` → SRAM `r_data` (latched at the end of the read cycle)
- `PUSH_SRC_TOS` → Stack Cache `tos`

**Address computation (`addr_calc`):**
- `ADDR_SRC_ARG`: `r_fp + 12 + r_operand[3:0] * 4`
- `ADDR_SRC_LOCAL`: `r_fp + 12 + r_arg_count * 4 + r_operand[3:0] * 4`
- `ADDR_SRC_FRAME`: `r_fp + r_operand[3:0]` (header fields, used by call/ret sequences)
- `ADDR_SRC_IND`: `stack_cache.tos[13:0]` (`ldind.i4` / `stind.i4`)

**Range checks:**
- `arg_index >= r_arg_count` → `TRAP_INVALID_ARG`
- `local_index >= r_local_count` → `TRAP_INVALID_LOCAL`
- `addr >= 16384` → `TRAP_INVALID_MEMORY` (only possible via indirect)

**Branch condition (`UC_COND_EN=1`):**
- `UC_PC_SRC_*` is `PC_SRC_BRANCH`, but the actual PC update **only happens** if the condition holds
- Condition: `cond_type` (EQ/NE/LT/GE), `cond_signed` (signed/unsigned), source: ALU result or stack TOS
- `UC_COND_POP=1` → always pops, regardless of condition (brfalse/brtrue): for single-operand branches
- Binary branch (beq, blt, …): pop2 + ALU + cond_check → no push, branch yes/no

### Memory bus arbiter (internal SRAM)

The 16 KB internal SRAM has **two potential masters**:
1. **Microcode SRAM read/write** (`UC_SRAM_RD/WR=1`)
2. **Stack Cache spill/fill** (`sram_we`/`sram_re` on `cilcpu_stack_cache`'s master port)

**Mutually exclusive use — simple mux:**
- If `(UC_SRAM_RD | UC_SRAM_WR) == 1` AND Stack Cache `busy == 0` → microcode side
- If Stack Cache `busy == 1` → Stack Cache spill/fill is running, microcode MUST WAIT → `→ ST_MEM_WAIT`
- The microcode guarantees that within a microstep either stack push/pop or SRAM rd/wr runs, but not both

The internal SRAM is **1-cycle latency, registered output**: address and we/re are registered, the read data is valid the next cycle (`sram_ready` is always 1 when not busy). The Stack Cache spec is compatible.

### QSPI controller integration

Only the **CODE fetch path** — `cpu_addr = {4'h0, r_pc + offset}`, `cpu_re = 1` for one cycle, wait for `cpu_ready`. Per F2.4 spec, one CODE fetch is ~30-40 main clocks (cmd 16 + addr 12 + dummy 16 + data 8 ≈ 52 cycles, unoptimized).

The fetch is this slow because of the small model, which is why the fetch buffer is critical: **ALU/stack ops "for free" once the buffer is filled**, the Decoder/Sequencer is 1-3 cycles per opcode.

### Frame manager (ST_CALL and ST_RET)

#### ST_CALL (after `UC_FRAME_PUSH=1`, in the context of the `call` opcode)

The `call` opcode operand is the new method header RVA. Sequence:

1. **Header read** from CODE per the `TMethodHeader` format (8 bytes, `src/CilCpu.Sim/TMethodHeader.cs`):

   ```
    Offset  Size  Field         Note
    +0      1     Magic = 0xFE  Validated
    +1      1     arg_count     0..16
    +2      1     local_count   0..16
    +3      1     max_stack     0..64 (F2.5a: not enforced; F5+ stack budget verifier)
    +4      2     code_size     LE u16, body length in bytes (F2.5a: unused; F5+ branch range)
    +6      2     reserved      0
   ```

   In F2.5a the HW only consumes bytes `+0..+2` (3 SRAM reads via the fetch buffer). Bytes `+3..+5` (max_stack and code_size) are **skipped** — they are emitted by the Linker and validated under F1; HW enforcement is deferred to F5+. **Validation:** magic ≠ `0xFE` → `TRAP_INVALID_CALL_TARGET`. The body's first byte is `RVA + 8`.
2. **CallDepth check:** `r_call_depth >= 512` → `TRAP_CALL_DEPTH_EXCEEDED`
3. **Frame size:** `frame_size = 12 + new_arg_count*4 + new_local_count*4`
4. **SRAM overflow check:** `r_sp + frame_size > 16384` → `TRAP_SRAM_OVERFLOW`
5. **Args pop from caller eval stack** (reverse order, since the stack is LIFO): `arg[N-1]` is on top, `arg[0]` deeper. The core pops `new_arg_count` times and writes the values into the new frame's `[FP_new + 12 + i*4]` slots.
6. **Header write into the new frame:** `[FP_new + 0] <= return_pc = r_pc + r_length`, `[FP_new + 4] <= r_fp`, `[FP_new + 8] <= {16'h0, new_local_count, new_arg_count}`
7. **Locals zeroing:** `new_local_count` writes to `[FP_new + 12 + new_arg_count*4 + i*4]`.
8. **Register update:** `r_fp <= FP_new`, `r_sp <= FP_new + frame_size`, `r_arg_count <= new_arg_count`, `r_local_count <= new_local_count`, `r_call_depth += 1`, `r_pc <= call_target_rva + 8`
9. **Stack cache reset for the new frame:** `sp_load=1`, `sp_init = r_sp` (empty eval stack). **The caller's eval stack remnants stay in SRAM**, because they belong to the caller frame's eval base — but the Stack Cache cache must be drained (cache_count <= 0). **F2.5a simplification:** the caller eval stack must be empty before the `call` opcode (the `call` microcode `o_nsteps = 2 + N` does not enforce this explicitly, but well-formed CIL-T0 programs satisfy it). If non-empty → those values live between `r_sp_caller` and the new `FP_new` and must be preserved. **In F2.5a we reset the Stack Cache cache for the callee and leave the caller leftovers in SRAM** — they get reloaded on ret.

#### ST_RET (after `UC_FRAME_POP=1`, in the context of the `ret` opcode)

1. **Return value pop:** if the current method has a return value (currently: every `ret` returns 1 value, except void — F2.5a: assumes one value on TOS before ret; if eval stack empty → return value = 0 default; void support deferred to F5+).
2. **Root frame check:** `r_call_depth == 1` → halt: `r_halt <= 1`, `o_return_value <= return_val`, `→ ST_HALT`
3. **Frame header read:** `return_pc = SRAM[r_fp + 0]`, `prev_fp = SRAM[r_fp + 4]`
4. **SP restore:** `r_sp <= r_fp` (callee SRAM is freed)
5. **Frame registers to caller:** `r_fp <= prev_fp`. To restore `r_arg_count` and `r_local_count` we **re-read the caller frame header**: `caller_arg_count = SRAM[prev_fp + 8][7:0]`, `caller_local_count = SRAM[prev_fp + 8][15:8]`.
6. **Stack cache to caller:** `sp_load=1`, `sp_init = caller_sp = prev_fp + 12 + caller_arg_count*4 + caller_local_count*4` + caller eval depth. **F2.5a simplification:** the caller eval depth before ret — storing it in SRAM is unnecessary because the Stack Cache `sp` register already had the caller's `sp` (but we overwrote it). **Solution:** before the `call`, save the current `r_sp` into the new frame's reserved header field (`[FP+10:11]`, 2 bytes) — in F2.5a the eval depth byte (max 64) fits. On ret, read it back.
7. **Return value push to the caller eval stack:** `push_data = return_val`, `push_en=1`
8. **PC update:** `r_pc <= return_pc`
9. **Call depth decrement:** `r_call_depth -= 1`
10. **→ ST_FETCH**

**Note on the frame header reserved field:** the TCpuNano `[FP+10:11]` 2 bytes are documented as reserved (alignment), but from a hardware perspective we use them to store the caller eval depth (max 64 → 7 bits). This is **a deviation from TCpuNano**, where the caller eval depth lives in the `FCallStack` record. **Golden reference deviation:** in F2.5a the hardware stores the caller eval depth in the frame header reserved field; the C# sim does not, it stores it in `FCallStack`. **The F2.5b golden vector harness's memory trace will not be byte-exact** on those 2 bytes. This is a deliberate F2.5a tradeoff (simpler hardware), to be resolved in F5 with a dedicated call-stack hardware unit.

### Trap aggregator

Trap source priority (top-down), at most one trap per cycle:

1. **Decoder** `o_trap_invalid` → `TRAP_INVALID_OPCODE`
2. **Microcode** `o_valid=0` → `TRAP_INVALID_OPCODE` (decoder accepted, but microcode doesn't recognize — F1 covers all 48)
3. **ALU** `o_trap_div_zero` → `TRAP_DIV_BY_ZERO`
4. **ALU** `o_trap_overflow` → `TRAP_OVERFLOW`
5. **Stack Cache** `trap=1` → `trap_code` (overflow/underflow)
6. **Microcode** `UC_TRAP=1` → `o_ctrl[UC_TRAP_CODE_*]`
7. **Frame manager** internal checks: `TRAP_CALL_DEPTH_EXCEEDED`, `TRAP_INVALID_CALL_TARGET`, `TRAP_SRAM_OVERFLOW`, `TRAP_INVALID_BRANCH`, `TRAP_INVALID_ARG`, `TRAP_INVALID_LOCAL`, `TRAP_INVALID_MEMORY`
8. **Microcode** `OP_BREAK` (`0xDD`) → `TRAP_DEBUG_BREAK`

**Trap semantics:**
- `o_trap` is **exactly a 1-cycle pulse** on the rising edge after the trap detection cycle, `o_trap_code` is valid then
- After a trap the core enters `ST_TRAP` from which **there is no return** without reset (`rst_n=0`)
- `o_halt` and `o_trap` are **never simultaneously active** (a run ends with halt or trap, not both)

### Halt semantics

- `o_halt = 1` until the end of a run (a new run requires reset)
- `o_return_value` is the TOS value at the halt cycle (or 0 if the eval stack was empty)
- `o_pc` holds the PC of the `ret` that caused halt (debug)

### PC update semantics (what `PC_SRC_*` means)

- **`PC_SRC_NEXT`**: `r_pc <= r_pc + r_length` (instruction length from the decoder)
- **`PC_SRC_BRANCH`**: `r_pc <= r_pc + r_length + signed_extend(r_operand[7:0])` for short (`*_S`) branches. `signed_extend` is 8→24 from 2's complement.
  - **Branch target validation:** if `target < 0` or `target >= code_size` → `TRAP_INVALID_BRANCH`. In F2.5a we don't know `code_size` → only the negative target is trapped; positive overflow is detected by the fetch unit (QSPI returns 0xFF bytes → `TRAP_INVALID_OPCODE` on the next decode).
- **`PC_SRC_CALL`**: `r_pc <= r_operand + 8` (RVA + METHOD_HEADER_SIZE)
- **`PC_SRC_RET`**: `r_pc <= sram[r_fp + 0]` (frame header ReturnPC field)

### Timing (one opcode execution)

| Event | Typical cycles |
|-------|----------------|
| Cold fetch (empty buffer, 4 bytes) | ~52 main clocks (QSPI) |
| Warm fetch (buffer >= 5 bytes) | 0 (immediate ST_DECODE) |
| Decode | 1 |
| Execute (simple ALU/const) | 1 |
| Execute (LDARG/STLOC) | 2 (1 microstep + 1 SRAM cycle) |
| Execute (CALL) | 5–20 (header read + N args + locals zero) |
| Execute (RET) | 4–6 |
| Execute (Stack Cache spill) | +1 cycle |

**Code density per fetch:** avg 1.5 bytes/opcode, 4-byte fetch → ~2.7 opcodes/fetch → cold-fetch amortized ~20 cycles/opcode. F5+ I-cache brings the warm path to ~1 cycle/opcode.

### Cocotb test groups (F2.5a TDD red)

The `rtl/tb/test_core.py` test suite must cover:

**1. Reset and boot smoke**
- `test_reset` — after `rst_n=0`, every register is 0, `o_halt=0`, `o_trap=0`
- `test_boot_no_args` — `i_boot_pc=0`, `i_boot_arg_count=0`, `i_boot_local_count=0`, `i_boot_start=1` → root frame set up (header in SRAM), `o_pc=0`, execution starts
- `test_boot_with_args` — 2 args streamed, args found at `[FP+12]`, `[FP+16]`

**2. Single instruction (LDC + RET)**
- `test_ldc_i4_5_ret` — program: `0x1B 0x2A` (LDC.I4_5, RET) → `o_halt=1`, `o_return_value=5`
- `test_ldc_i4_s_ret` — `0x1F 0x2A 0x2A` (LDC.I4.S 42, RET) → `o_return_value=42`
- `test_ldc_i4_ret` — `0x20 imm32 0x2A` → `o_return_value=imm32`

**3. Arithmetic (ADD/SUB/MUL/DIV)**
- `test_add_2_3` — LDC 2, LDC 3, ADD, RET → 5
- `test_sub_10_4` — 6
- `test_mul_7_8` — 56
- `test_div_20_5` — 4
- `test_div_zero_trap` — LDC 5, LDC 0, DIV, RET → `o_trap=1`, `o_trap_code=TRAP_DIV_BY_ZERO`

**4. Branch (BR_S, BRFALSE_S, BEQ_S, …)**
- `test_br_s_forward` — unconditional jump, target stmt runs
- `test_brtrue_s_taken` — condition = 1 → branch
- `test_brfalse_s_not_taken` — condition = 1 → fall-through
- `test_beq_s_taken` — two equal values
- `test_blt_s_signed` — -5 < 3 → taken

**5. Local variable**
- `test_ldloc_stloc_roundtrip` — STLOC.0 42, LDLOC.0, RET → 42
- `test_invalid_local_trap` — LDLOC.5 with local_count=2 → `TRAP_INVALID_LOCAL`

**6. Argument**
- `test_ldarg_0_ret` — boot args = [99], LDARG.0, RET → 99
- `test_ldarg_1_ret` — boot args = [10, 20], LDARG.1, RET → 20

**7. Call/Ret**
- `test_call_simple` — `Add(2, 3) → 5` (simple 2-arg static call)
- `test_call_recursive_fib_5` — Fibonacci(5) → 5

**8. Stack overflow / underflow**
- `test_stack_overflow_trap` — 65 LDC.I4.S → `TRAP_STACK_OVERFLOW`
- `test_stack_underflow_trap` — POP on empty stack → `TRAP_STACK_UNDERFLOW`

**9. Invalid opcode**
- `test_invalid_opcode_trap` — fetch buffer with 0xFF byte → `TRAP_INVALID_OPCODE`

**10. Halt and observability**
- `test_halt_after_root_ret` — root RET → `o_halt=1` rises in one cycle and stays
- `test_pc_observability` — `o_pc` follows execution (at least a few smoke cycles)

**Golden reference linkage:** every test compares `o_return_value` and/or `o_trap_code` against the same-program TCpuNano F1 simulator result. SRAM byte-trace comparison is part of the F2.5b golden harness.

### Verification minimum

When running `make test_core`:
- Every test group (1–10) has at least 1 case
- Every trap code (of the 13) is **triggered by at least one test**: TRAP_STACK_OVERFLOW, TRAP_STACK_UNDERFLOW, TRAP_INVALID_OPCODE, TRAP_INVALID_LOCAL, TRAP_INVALID_ARG, TRAP_INVALID_BRANCH, TRAP_INVALID_CALL_TARGET, TRAP_DIV_BY_ZERO, TRAP_OVERFLOW, TRAP_CALL_DEPTH_EXCEEDED, TRAP_DEBUG_BREAK, TRAP_INVALID_MEMORY, TRAP_SRAM_OVERFLOW
- Goal: 30+ cocotb tests green

### Simplifications / open questions (F2.5a deliberate tradeoffs)

1. **Eval stack preservation before `call`:** in F2.5a only args may sit on the caller eval stack before `call`. Anything else → undefined behavior (but does NOT corrupt the core). F5 will introduce dedicated hardware to resolve this.
2. **Frame header reserved field:** used to store caller eval depth (deviates from C# sim). The F2.5b golden harness tolerates these 2 bytes.
3. **PSRAM stack overflow:** in F2.5a, overflow of the 16 KB internal SRAM raises `TRAP_SRAM_OVERFLOW`. F5+ Stack Cache will spill to PSRAM.
4. **Inferred BRAM:** Verilog `reg [31:0] r_sram[0:4095]`, on FPGA Vivado/Yosys maps it to BRAM. On ASIC F2.6 will swap to a Sky130 SRAM macro.
5. **Power-on init:** SRAM is not guaranteed to be 0 after reset on FPGA/ASIC. **F2.5a behavior:** the boot sequence overwrites everything it uses, and reads only happen from previously-written addresses (invariant inherited from TCpuNano). No boot-time random-read trap: per F1 contract, none.

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.2 | 2026-05-04 | Sub-iteration status: Sub1 (skeleton, LDC+RET) ✅, Sub2 (arithmetic + ALU phase) ✅, Sub2.1 (`r_qspi_inflight`+`r_next_fetch_addr` Verilator NBA fetch addr fix) ✅, Sub2.2 (APPEND general count 0..4) ✅, Sub3 (LDARG/STARG/LDLOC/STLOC + 2-phase ST_MEM_WAIT + SRAM bus arbiter) ✅, Sub4 (BR_S/BRTRUE/BRFALSE/BEQ/BLT/BGE branch decision) ✅, Sub6 (Stack Cache trap aggregator) ✅. **Sub5 (CALL/RET non-root) — OPEN, deferred to next session.** Verilator gotchas documented: SRAM read 1-cycle latency requires ST_MEM_WAIT 2 cycles (X = r_sram_re=1, X+1 = `if (r_sram_re)` runs → r_sram_rdata_latched <= sram NBA, X+2 = fresh value visible). 41 cocotb tests green, 0 FAIL, 0 expect_fail, 0 Verilator warning. |
| 1.1 | 2026-05-04 | Devil's Advocate audit: TMethodHeader format clarified (4 fields: arg_count, local_count, max_stack, code_size). F2.5a HW only consumes the first 3 bytes; max_stack and code_size deferred to F5+. Confirmation that no fetch abort is needed mid-branch (branch only runs in ST_EXECUTE, when QSPI is IDLE). |
| 1.0 | 2026-05-04 | Initial F2.5a top-level Nano core spec — 5-submodule integration, fetch/decode/execute pipeline, frame manager, trap aggregator |
