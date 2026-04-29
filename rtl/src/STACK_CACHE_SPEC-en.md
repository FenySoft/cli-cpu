# F2.3 Stack Cache — Contract and Port Specification

> Magyar verzió: [STACK_CACHE_SPEC-hu.md](STACK_CACHE_SPEC-hu.md)

> Internal work spec for the TDD cycle. Golden example: `TCpuNano.EvalPush/EvalPop/EvalPeek` (`src/CilCpu.Sim/TCpuNano.cs`).
>
> **Scope:** Internal RTL work spec, not a public document. The public ISA spec is `docs/ISA-CIL-T0-{hu,en}.md`.
>
> Version: 1.1

## Goal

Physical 4-element Top-of-Stack cache + spill/fill to the SRAM stack region (`0x2000_0000`). Transparent to the upper microcode -- controllable via `push_en`, `pop_en`, `dup_en`, `swap_en`, `replace_top_en` signals. Total eval stack max depth is 64 (`MAX_STACK_DEPTH`).

## Module: `cilcpu_stack_cache`

### Ports

| Direction | Name | Width | Description |
|-----------|------|-------|-------------|
| in | `clk` | 1 | Clock |
| in | `rst_n` | 1 | Asynchronous active-low reset |
| in | `sp_load` | 1 | SP register load enable |
| in | `sp_init` | 14 | Initial SP value (from frame setup) |
| in | `push_en` | 1 | Push operation -- `push_data` onto stack top |
| in | `push_data` | 32 | Push data |
| in | `pop_en` | 1 | Pop operation -- `pop_data` is the old TOS |
| in | `dup_en` | 1 | Duplicate -- TOS push (push TOS) |
| in | `swap_en` | 1 | TOS <-> TOS-1 swap |
| in | `replace_top_en` | 1 | TOS overwrite (ALU result, write after peek) |
| in | `replace_top_data` | 32 | New TOS value |
| in | `peek_index` | 2 | Read offset (0=TOS, 1=TOS-1, 2=TOS-2, 3=TOS-3) |
| out | `peek_data` | 32 | Read value (combinational) |
| out | `tos` | 32 | TOS value (combinational, fast path) |
| out | `tos1` | 32 | TOS-1 value (combinational) |
| out | `pop_data` | 32 | Pop result (registered) |
| out | `depth` | 7 | Total eval stack depth (0..64) |
| out | `cache_count` | 3 | Elements in cache (0..4) |
| out | `busy` | 1 | Spill/fill in progress -- new operations PROHIBITED |
| out | `ready` | 1 | Operation completed, result valid |
| out | `trap` | 1 | Trap pulse |
| out | `trap_code` | 8 | `TRAP_STACK_OVERFLOW` (0x01) or `TRAP_STACK_UNDERFLOW` (0x02) |
| out | `sram_addr` | 14 | SRAM address (master) |
| out | `sram_wdata` | 32 | SRAM write data |
| in | `sram_rdata` | 32 | SRAM read data |
| out | `sram_we` | 1 | SRAM write enable |
| out | `sram_re` | 1 | SRAM read enable |
| in | `sram_ready` | 1 | SRAM ready signal (can be 1'b1 for 1-cycle SRAM) |

### Internal State

- 4x32-bit TOS registers: `t[0..3]`, where `t[0]` = TOS, `t[3]` = TOS-3
- `sp[13:0]` -- pointer to the next free SRAM slot (relative to stack region base or absolute, F1-compatible)
- `cache_count[2:0]` -- 0..4
- `state[1:0]` -- `IDLE`, `SPILL`, `FILL`

### Behavior

#### Reset
- `rst_n=0` -> `cache_count=0`, `state=IDLE`, `sp` undefined (sp_load + sp_init needed before first use)
- `trap=0`, `busy=0`, `ready=1`

#### Push (`push_en=1` in IDLE)
- If `depth >= 64` -> `trap=1`, `trap_code=TRAP_STACK_OVERFLOW` (1-cycle pulse), state unchanged
- If `cache_count < 4`: T shift (`t[3]<=t[2]`, `t[2]<=t[1]`, `t[1]<=t[0]`, `t[0]<=push_data`), `cache_count++`. 1 cycle, `ready=1`
- If `cache_count == 4`: SPILL state -- `state=SPILL`, `busy=1`, `ready=0`. Then `sram_we=1`, `sram_addr=sp`, `sram_wdata=t[3]`. After SRAM ack: `sp+=4`, T shift + push_data, `cache_count` stays 4, back to `IDLE`, `ready=1` (at least 2 cycles)

#### Pop (`pop_en=1` in IDLE)
- If `depth == 0` -> `trap=1`, `trap_code=TRAP_STACK_UNDERFLOW`, state unchanged
- If `cache_count > 0`: `pop_data <= t[0]`, T shift (`t[0]<=t[1]`, `t[1]<=t[2]`, `t[2]<=t[3]`, `t[3]` = X), `cache_count--`. 1 cycle
- If `cache_count == 0` and `depth > 0`: FILL -- `state=FILL`, `busy=1`. `sp-=4`, `sram_re=1`, `sram_addr=sp`. After SRAM ack: `pop_data <= sram_rdata`, back to `IDLE`. (Note: in the `depth==0 && cache_count==0` case, underflow must be handled -- if `depth>=1` but `cache_count==0`, there is at least 1 element in SRAM.)

#### Dup (`dup_en=1`)
- Equivalent to a push where `push_data` is the current value of `t[0]`
- If `cache_count==0` and `depth==0` -> `TRAP_STACK_UNDERFLOW` (nothing to duplicate)
- If `cache_count==0` and `depth>0` -> FILL needed first -- multi-cycle: FILL then SPILL/PUSH

#### Swap (`swap_en=1`)
- `t[0] <-> t[1]`
- If `cache_count<2` and `depth>=2` -> FILL first so that `cache_count>=2`
- If `depth<2` -> `TRAP_STACK_UNDERFLOW`

#### Replace top (`replace_top_en=1`)
- `t[0] <= replace_top_data`
- If `cache_count==0` and `depth==0` -> `TRAP_STACK_UNDERFLOW`
- If `cache_count==0` and `depth>0` -> FILL first

#### Multiple signals simultaneously
- Only 1 operation per cycle is allowed (microcode guarantees this). If multiple fire simultaneously -- behavior is undefined, but tests verify that it does NOT crash (`trap=1` and `cache_count` is not corrupted).

### `depth` Definition

`depth = cache_count + sram_count`, where `sram_count = (sp - sp_init) / 4`. During spill/fill, `depth` must remain unchanged (only the placement changes between cache vs. SRAM).

### Trap Semantics

- Trap is an **exactly 1 clock cycle pulse** on the `trap` and `trap_code` signals, edge-aligned: appears on the rising edge following the preceding `*_en` cycle, and `trap=0` on the next rising edge
- During trap, state is **unchanged** (nothing is written, nothing is shifted)
- During trap, **`sram_we==0` and `sram_re==0` for the ENTIRE cycle** -- overflow/underflow trap CANNOT cause OOB SRAM access
- The upper microcode is responsible for trap propagation and CPU halt

### `pop_data` Validity Window

- `pop_data` is registered and becomes valid simultaneously with the `ready=1` signal (on the same rising edge)
- Single-cycle pop: settles 1 clock after the `pop_en` cycle
- FILL pop: while `busy=1`, `pop_data` is undefined; settles on the `ready=1` rising edge
- The value is held stable until the next operation's `*_en` signal rising edge (no "1-cycle self-clear")

### `peek_data` Semantics

- Defined only when `cache_count > peek_index`
- If `peek_index >= cache_count`: `peek_data = 32'h0` (deterministic 0, NOT X) -- saturating behavior
- The microcode is responsible for not calling `peek` with an OOB index; the stack cache does not trap on this (this is not an ISA-level error)
- `peek` NEVER initiates a FILL -- reads exclusively from cache registers

### `sram_ready` Handshake (MANDATORY)

- SPILL and FILL states **always wait** for `sram_ready=1`
- While `sram_ready=0` during SPILL/FILL, the Verilog must: keep `busy=1`, `sp` unchanged, cache registers unchanged, `sram_we`/`sram_re` held high (pulse stretching, NOT 1-cycle)
- Tests verify with various `sram_ready` delays (0, 1, 2, 3 cycles)
- Sky130 PDK SRAM is 1-cycle, so `sram_ready=1'b1` constantly is acceptable -- but the Verilog MUST NOT rely on this, because F2.4 QSPI-PSRAM is 2-3 cycles

### `*_en` Signals During `busy`

- Any `*_en` signal during `busy=1` is **silently ignored**, NOT registered, NOT queued, NOT trapped
- The microcode is responsible for not activating new operations during `busy`
- Tests directly verify both the push signals during busy and the SPILL's internal `sram_wdata` integrity simultaneously

### Concurrent `*_en` Signal Priority

Simultaneous signal activation indicates an illegal microcode error, but the HW must behave **deterministically and safely**. Priority encoder, top to bottom:

1. `pop_en` (highest)
2. `push_en`
3. `dup_en`
4. `swap_en`
5. `replace_top_en` (lowest)

When more than one signal is active simultaneously, only the highest-priority one executes; the rest are ignored. Trap does not activate (this is a microcode error, not an ISA-level error).

### `sp_init` Alignment

- `sp_init` is **word-aligned** (lower 2 bits are 0) -- the HW does NOT check and does NOT trap
- The microcode/firmware is responsible for passing the correct `sp_init`
- `sp_load` during reset is ignored

### `sram_addr` in IDLE

- In IDLE state (`busy=0`) the `sram_addr` value is **don't-care**, but the Verilog designer **must hold it stable** (no floating, no X) -- recommended to drive the current `sp` value, yielding 0 pre-glitch at SPILL/FILL start
- `sram_we`/`sram_re` are mandatory `0` in IDLE -- therefore the `sram_addr` value has no physical effect on memory

### Reset Semantics (Extended)

- `rst_n=0` asynchronously clears: `cache_count=0`, `state=IDLE`, `trap=0`, `busy=0`, `ready=1`
- `sp` is undefined (X) during reset -- the microcode must perform an `sp_load` cycle before the first push
- `*_en`/`sp_load`/`push_data` signals arriving DURING reset assert are ignored (FF not writable)
- After `rst_n=1` rising edge, `*_en` signals are ineffective for **at least 1 cycle** (re-sync window)

## Test Strategy (TDD)

Test order (in task 2):

1. **Reset and initialization** -- `cache_count=0`, `depth=0`, `ready=1` after reset
2. **Simple push** -- 1 push, `tos == push_data`, `cache_count==1`, `depth==1`
3. **4 pushes into cache** -- `cache_count==4`, `depth==4`, no SRAM access
4. **5th push with spill** -- SRAM write observed for t[3], `depth==5`, `cache_count==4`
5. **Pop in reverse with spill-fill** -- removes 5 elements one by one, fill from SRAM
6. **Dup** -- from `cache_count==1` dup -> 2, both the same
7. **Swap** -- two values, swap, verify order
8. **Replace top** -- TOS overwrite
9. **64-deep overflow trap** -- 65th push -> `trap_code=0x01`, `cache_count` unchanged
10. **Empty pop underflow trap** -- `trap_code=0x02`
11. **Behavior during spill** -- `busy==1`, new operation does not execute
12. **Random sequence** -- 1000 random push/pop sequence, verify against Python reference stack
13. **Peek** -- all possible peek indices 0..3 verified
14. **Spill-fill round-trip determinism** -- same value comes back

### Tests Added After Devil's Advocate Review #1

15. **`dup` with FILL** -- dup from `cache_count=0, depth=2` state; FILL atomicity, correct `t[0]/t[1]` and `sram_re` address order
16. **`swap` with FILL** -- swap from `cache_count=1, depth=3` state; correct `t[0]/t[1]` swap after FILL
17. **`replace_top` with FILL** -- replace_top from `cache_count=0, depth=1` state; old SRAM-resident TOS is NOT written back
18. **`pop_data` cycle-precise timing** -- which rising edge after `pop_en` makes `pop_data` valid; cycle counter based
19. **Trap pulse width** -- in overflow + underflow cases, `trap=1` for EXACTLY 1 cycle, no more, no less
20. **No SRAM write during overflow cycle** -- during 65th push, `sram_we==0` for the entire cycle
21. **No SRAM read during underflow cycle** -- during empty pop, `sram_re==0`
22. **`sram_ready` handshake** -- `sram_ready=0` for 1, 2, 3 cycles during spill; `busy` held, `sp` and `t[3]` unchanged, write only after `ready=1`
23. **Push during busy does not corrupt spill** -- push_en+push_data toggling during busy, `sram_wdata` remains the original `t[3]`
24. **Concurrent signals priority** -- every pair (push+pop, dup+swap, push+dup, ...) tested per priority encoder; `cache_count` and `depth` remain consistent
25. **`peek_index` OOB** -- `peek_index >= cache_count` yields `peek_data == 0`, and does NOT initiate FILL (`sram_re==0`)

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.1 | 2026-04-27 | After Devil's Advocate review: precise trap pulse timing, pop_data validity window, peek OOB saturating 0, sram_ready handshake, *_en ignored during busy, concurrent priority encoder, sp_init word-aligned, extended reset, sram_addr don't-care in IDLE; +11 tests (test_15..test_25) |
| 1.0 | 2026-04-27 | First version -- 4-element TOS cache, SPILL/FILL, 14 test points |
