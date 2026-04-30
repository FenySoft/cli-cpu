# F2.4 QSPI Controller — Contract and Port Specification

> Magyar verzió: [QSPI_CONTROLLER_SPEC-hu.md](QSPI_CONTROLLER_SPEC-hu.md)

> Internal work spec for the TDD cycle. Architectural context in `docs/architecture-hu.md`.
>
> **Scope:** Internal RTL work spec, not a public document.
>
> Version: 1.1

## Goal

Translates the CPU's internal SRAM-like read/write requests to QSPI protocol. Manages two external devices:
- **QSPI Flash** -- CODE and DATA segments (read-only)
- **QSPI PSRAM** -- STACK segment (read-write)

The module provides a CPU-side interface compatible with the stack cache `sram_*` master ports. The future I-cache and load/store unit will also access external memory through this interface (via bus arbiter).

**F2.4 scope:** Single-word (32-bit) transactions, no burst. Burst mode (I-cache line fill) is deferred to F5.

## Module: `cilcpu_qspi_controller`

### Ports

| Direction | Name | Width | Description |
|-----------|------|-------|-------------|
| in | `clk` | 1 | Main clock (50 MHz) |
| in | `rst_n` | 1 | Asynchronous active-low reset |
| **CPU-side** | | | |
| in | `cpu_addr` | 24 | Byte address -- upper nibble (`[23:20]`) is segment selector |
| in | `cpu_wdata` | 32 | Write data |
| out | `cpu_rdata` | 32 | Read data (registered, valid simultaneously with `cpu_ready`) |
| in | `cpu_re` | 1 | Read start (1-cycle pulse) |
| in | `cpu_we` | 1 | Write start (1-cycle pulse) |
| out | `cpu_ready` | 1 | Transaction complete (1-cycle pulse) |
| out | `cpu_busy` | 1 | Transaction in progress |
| **QSPI-side** | | | |
| out | `qspi_clk` | 1 | QSPI clock output (main_clk / 2 = 25 MHz) |
| out | `qspi_cs_flash_n` | 1 | Flash chip select (active-low) |
| out | `qspi_cs_psram_n` | 1 | PSRAM chip select (active-low) |
| out | `qspi_dq_out` | 4 | Data output DQ[3:0] |
| in | `qspi_dq_in` | 4 | Data input DQ[3:0] |
| out | `qspi_dq_oe` | 1 | Output enable (1 = controller drives DQ) |

**Note:** Verilator does not handle `inout` tri-state, so DQ lines are split into separate `dq_out/dq_in/dq_oe` ports for simulation. Synthesis wrapper uses `inout wire [3:0] qspi_dq`.

### Address Decoding

| `cpu_addr[23:20]` | Segment | Device | Writable? | QSPI command (read) | QSPI command (write) |
|--------------------|---------|--------|-----------|----------------------|----------------------|
| `4'h0` | CODE | Flash | No | `0x6B` (Quad Output Read) | -- (rejected) |
| `4'h1` | DATA | Flash | No | `0x6B` (Quad Output Read) | -- (rejected) |
| `4'h2` | STACK | PSRAM | Yes | `0xEB` (Fast Read QIO) | `0x38` (Quad Write) |
| other | -- | -- | -- | `cpu_ready=1` immediately, NOP | `cpu_ready=1` immediately, NOP |

**Flash write rejection:** If `cpu_we=1` and the address falls in the CODE or DATA segment, the controller asserts `cpu_ready=1` immediately, without a QSPI transaction. No trap -- the microcode/firmware is responsible for not writing to read-only segments.

### Internal State

- `r_state[3:0]` -- FSM state
- `r_bit_cnt[5:0]` -- bit/nibble counter within the phase
- `r_cmd[7:0]` -- current QSPI command byte
- `r_addr[23:0]` -- current QSPI address (lower 20 bits of cpu_addr, without segment prefix)
- `r_shift_out[31:0]` -- outgoing data shift register
- `r_shift_in[31:0]` -- incoming data shift register
- `r_clk_phase` -- QSPI clock phase (toggle flip-flop, /2 divider)
- `r_is_write` -- current transaction is a write
- `r_device` -- 0=Flash, 1=PSRAM

### FSM States

```
localparam [3:0] ST_IDLE     = 4'd0;   // Wait for cpu_re/cpu_we
localparam [3:0] ST_CMD      = 4'd1;   // Send 8-bit command (SPI, 1-bit)
localparam [3:0] ST_ADDR     = 4'd2;   // Send 24-bit address (Quad, 4-bit)
localparam [3:0] ST_DUMMY    = 4'd3;   // Dummy cycles (DQ Hi-Z)
localparam [3:0] ST_DATA_RD  = 4'd4;   // Read 32-bit data (Quad, 4-bit)
localparam [3:0] ST_DATA_WR  = 4'd5;   // Write 32-bit data (Quad, 4-bit)
localparam [3:0] ST_DONE     = 4'd6;   // cpu_ready=1, CS# deassert, -> IDLE
```

### FSM Transitions

```
                     cpu_re=1 (read)
                    +----------------------------------------------+
                    |                                              |
ST_IDLE -> ST_CMD -> ST_ADDR -> ST_DUMMY -> ST_DATA_RD -> ST_DONE -> ST_IDLE
                    |                    |
                    |  cpu_we=1 (write)  +-> ST_DATA_WR -> ST_DONE -> ST_IDLE
                    |                        (no DUMMY)
                    +----------------------------------------------+
```

### Per-Phase Behavior

#### ST_IDLE
- `cpu_ready=0` (except for invalid address or Flash write -> immediate `cpu_ready=1`)
- `cpu_busy=0`
- `qspi_clk` gated (held at 0)
- `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1` (both inactive)
- `qspi_dq_oe=0` (Hi-Z)
- If `cpu_re=1` or `cpu_we=1`: latch address, select device, latch command, CS# assert -> ST_CMD
- If `cpu_re=1` AND `cpu_we=1` simultaneously: read takes priority

#### ST_CMD -- Command Send
- SPI mode: only DQ[0] (MOSI) used, `qspi_dq_oe=1`
- DQ[1]=1 (MISO -- must be driven high, as Flash expects high in idle state)
- DQ[2]=1, DQ[3]=1 (WP# and HOLD# inactive)
- Command byte MSB-first, 1 bit per QSPI CLK rising edge
- 8 QSPI CLK = 16 main CLK cycles
- `r_bit_cnt`: 7->0, shifts on every QSPI CLK falling edge
- When `r_bit_cnt==0` and falling edge -> ST_ADDR

#### ST_ADDR -- Address Send
- Quad mode: all DQ[3:0] used, `qspi_dq_oe=1`
- 24-bit address, MSB-first, 4 bits (1 nibble) per QSPI CLK
- 6 QSPI CLK = 12 main CLK cycles
- `r_bit_cnt`: 5->0
- When `r_bit_cnt==0` and falling edge -> for read: ST_DUMMY; for write: ST_DATA_WR

#### ST_DUMMY -- Dummy Cycles
- `qspi_dq_oe=0` (Hi-Z) -- bus turnaround
- Flash (0x6B): 8 QSPI CLK dummy
- PSRAM (0xEB): 6 QSPI CLK dummy
- `r_bit_cnt`: (dummy_count-1)->0
- When `r_bit_cnt==0` and falling edge -> ST_DATA_RD

#### ST_DATA_RD -- Data Read
- Quad mode: DQ[3:0] input, `qspi_dq_oe=0`
- 32 bits, MSB-first nibbles, 4 bits sampled per QSPI CLK rising edge
- 8 QSPI CLK = 16 main CLK cycles
- `r_shift_in` shifts left, writes `qspi_dq_in` into lower 4 bits
- When `r_bit_cnt==0` -> ST_DONE

#### ST_DATA_WR -- Data Write
- Quad mode: DQ[3:0] output, `qspi_dq_oe=1`
- 32 bits, MSB-first nibbles
- 8 QSPI CLK = 16 main CLK cycles
- Upper 4 bits of `r_shift_out` -> DQ[3:0], shift left
- When `r_bit_cnt==0` -> ST_DONE

#### ST_DONE -- Completion
- CS# deassert (both high)
- `cpu_ready=1` (1-cycle pulse)
- `cpu_rdata = r_shift_in` (for reads)
- `qspi_clk` gated
- Next main CLK rising edge -> ST_IDLE

### QSPI Clock Generation

- Toggle flip-flop: `r_clk_phase` inverts on every main CLK rising edge while transaction is active
- `qspi_clk = r_clk_phase & clk_en` -- gated, 0 in IDLE
- Data setup: the controller sets DQ outputs on the **falling edge** (r_clk_phase 1->0)
- Data sampling: reads on the **rising edge** (r_clk_phase 0->1)
- `r_bit_cnt` decrements on the QSPI CLK falling edge

### Cycle Counts (main CLK @ 50 MHz, QSPI CLK @ 25 MHz)

| Operation | Command | CMD | ADDR | DUMMY | DATA | DONE | Total QSPI CLK | Total main CLK |
|-----------|---------|-----|------|-------|------|------|----------------|----------------|
| Flash Read | 0x6B | 8 | 6 | 8 | 8 | 1 | 31 | 62 |
| PSRAM Read | 0xEB | 8 | 6 | 6 | 8 | 1 | 29 | 58 |
| PSRAM Write | 0x38 | 8 | 6 | 0 | 8 | 1 | 23 | 46 |

**Note:** For the 0x6B command, the ADDR phase also runs in SPI mode (1-bit), not quad. This means 24 QSPI CLK in the ADDR phase. Total Flash Read: 8+24+8+8+1 = 49 QSPI CLK = 98 main CLK. Alternative: 0xEB (quad ADDR), which is 8+6+6+8+1 = 29. **Decision:** F2.4 implements **0x6B** (simpler, wider chip compatibility). The 0xEB option is a future optimization.

**Corrected cycle counts (0x6B, SPI ADDR):**

| Operation | Command | CMD (SPI) | ADDR (SPI) | DUMMY | DATA (Quad) | DONE | Total QSPI CLK | Total main CLK |
|-----------|---------|-----------|------------|-------|-------------|------|----------------|----------------|
| Flash Read | 0x6B | 8 | 24 | 8 | 8 | 1 | 49 | 98 |
| PSRAM Read | 0xEB | 8 | 6 | 6 | 8 | 1 | 29 | 58 |
| PSRAM Write | 0x38 | 8 | 6 | 0 | 8 | 1 | 23 | 46 |

### Reset Behavior

- `rst_n=0` -> `r_state=ST_IDLE`, all registers cleared
- `cpu_ready=0`, `cpu_busy=0`
- `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1`
- `qspi_clk=0`, `qspi_dq_oe=0`, `qspi_dq_out=4'hF`
- `cpu_re`/`cpu_we` during reset are ignored

**HW interlock requirement:** Reset assertion is only allowed while `cpu_busy=0`. A reset arriving mid-transaction may leave the external QSPI device (PSRAM) with a partially written word — the CPU-side bus arbiter must enforce this.

### `cpu_re`/`cpu_we` During `cpu_busy`

- Any request during `cpu_busy=1` is **silently ignored**
- The CPU-side upper logic (microcode, bus arbiter) is responsible for not starting new transactions during busy

## QSPI Command Codes (`cilcpu_defines.vh`)

```verilog
`define QSPI_CMD_FLASH_READ    8'h6B   // Quad Output Read (cmd+addr SPI, data Quad)
`define QSPI_CMD_PSRAM_READ    8'hEB   // Fast Read Quad I/O (cmd SPI, addr+data Quad)
`define QSPI_CMD_PSRAM_WRITE   8'h38   // Quad Write (cmd SPI, addr+data Quad)
`define QSPI_DUMMY_FLASH       6'd8    // 0x6B: 8 dummy QSPI cycles
`define QSPI_DUMMY_PSRAM       6'd6    // 0xEB: 6 dummy QSPI cycles
`define SEG_CODE               4'h0    // CODE segment identifier
`define SEG_DATA               4'h1    // DATA segment identifier
`define SEG_STACK              4'h2    // STACK segment identifier
```

## Test Strategy (TDD)

### QSPI Slave Behavioral Model

Python cocotb coroutine simulating a QSPI slave device:
- **QSPIFlashModel**: dict-based memory, read-only, recognizes 0x6B command
- **QSPIPSRAMModel**: dict-based memory, read-write, recognizes 0xEB and 0x38 commands
- The model monitors CS#, CLK rising edges, DQ inputs
- During reads, after the DUMMY phase, the model drives the `qspi_dq_in` line

### Test List (25 tests)

**Basic (1-2):**
1. **Reset state** -- `cpu_busy=0`, `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1`, `qspi_clk=0`, `qspi_dq_oe=0`
2. **No QSPI CLK in IDLE** -- 100 main CLK wait, `qspi_clk` always 0

**Read (3-4):**
3. **Flash read** -- CODE segment address, correct 32-bit data from Flash model
4. **PSRAM read** -- STACK segment address, correct 32-bit data from PSRAM model

**Write (5-6):**
5. **PSRAM write** -- write 0xDEADBEEF to STACK address, PSRAM model receives it
6. **PSRAM write->read round-trip** -- write then read, same data

**Address decoding (7-10):**
7. **CODE->Flash CS#** -- `qspi_cs_flash_n=0` assert, `qspi_cs_psram_n=1`
8. **DATA->Flash CS#** -- `cpu_addr[23:20]=1`, Flash CS# assert
9. **STACK->PSRAM CS#** -- `qspi_cs_psram_n=0` assert, `qspi_cs_flash_n=1`
10. **Flash write rejected** -- `cpu_we=1` to CODE address -> `cpu_ready=1` immediately, no QSPI transaction

**Protocol (11-16):**
11. **CMD phase timing** -- 8 QSPI CLK, DQ[0] MSB-first, correct command byte bits
12. **ADDR phase** -- correct address nibbles/bits, MSB-first, correct QSPI CLK count
13. **Flash dummy cycle count** -- 8 QSPI CLK dummy after 0x6B
14. **PSRAM dummy cycle count** -- 6 QSPI CLK dummy after 0xEB
15. **Read DATA phase** -- 8 QSPI CLK, 4-bit nibbles, MSB-first, correct shift-in
16. **Write DATA phase** -- 8 QSPI CLK, correct nibble order on DQ[3:0]

**Timing (17-18):**
17. **cpu_ready pulse** -- exactly 1 main CLK cycle pulse at transaction end
18. **cpu_busy during transaction** -- `cpu_busy=1` throughout QSPI transaction, `cpu_busy=0` in IDLE

**Edge cases (19-24):**
19. **Back-to-back reads** -- two consecutive Flash reads, both return correct data
20. **CS# deassert between transactions** -- CS# high for at least 1 main CLK between transactions
21. **Address 0x000000 read** -- zero address, correct data
22. **Max address per segment** -- CODE max (0x0FFFFF), STACK max (0x23FFF)
23. **Simultaneous cpu_re + cpu_we** -- read takes priority, write ignored
24. **dq_oe phase transitions** -- CMD: oe=1, ADDR: oe=1, DUMMY: oe=0, DATA_RD: oe=0, DATA_WR: oe=1

**Stress (25):**
25. **200 random R/W** -- seeded RNG, Python reference dict vs. PSRAM model, all data matches

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-28 | First version -- QSPI Flash + PSRAM controller, 0x6B/0xEB/0x38, 25 test points |
| 1.1 | 2026-04-30 | HW interlock requirement for reset during transactions; CS# deassert strictly in ST_DONE |
