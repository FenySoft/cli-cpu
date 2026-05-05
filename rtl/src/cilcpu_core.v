// hu: CLI-CPU F2.5a Top-level Nano Core — az 5 részegység (cilcpu_alu,
//     cilcpu_decoder, cilcpu_microcode, cilcpu_stack_cache,
//     cilcpu_qspi_controller) integrációja. A spec a CORE_SPEC-{hu,en}.md.
//     Sub1 hatókör: reset, boot, fetch, decode, execute LDC + RET, halt.
//     Sub2+ hozza: aritmetika, branch, call, arg/local, stack overflow.
// en: CLI-CPU F2.5a Top-level Nano Core — integration of the 5 submodules.
//     Sub1 scope: reset, boot, fetch, decode, execute LDC + RET, halt.
//     Sub2+ adds: arithmetic, branch, call, arg/local, stack overflow.

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_core (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Boot konfiguráció / en: Boot configuration
    input  wire [23:0] i_boot_pc,
    input  wire [7:0]  i_boot_arg_count,
    input  wire [7:0]  i_boot_local_count,
    input  wire        i_boot_start,
    input  wire [31:0] i_boot_arg_data,
    input  wire        i_boot_arg_valid,
    output reg         o_boot_arg_ready,

    // hu: Státusz / en: Status
    output reg         o_halt,
    output reg         o_trap,
    output reg  [7:0]  o_trap_code,
    output reg  [23:0] o_pc,
    output reg  [31:0] o_return_value,

    // hu: QSPI pinek / en: QSPI pins
    output wire        qspi_clk,
    output wire        qspi_cs_flash_n,
    output wire        qspi_cs_psram_n,
    output wire [3:0]  qspi_dq_out,
    input  wire [3:0]  qspi_dq_in,
    output wire        qspi_dq_oe
);

    // ============================================================
    // hu: Top-level FSM állapotok
    // en: Top-level FSM states
    // ============================================================
    localparam [3:0] ST_RESET    = 4'd0;
    localparam [3:0] ST_BOOT     = 4'd1;
    localparam [3:0] ST_FETCH    = 4'd2;
    localparam [3:0] ST_DECODE   = 4'd3;
    localparam [3:0] ST_EXECUTE  = 4'd4;
    localparam [3:0] ST_MEM_WAIT = 4'd5;   // Sub3: SRAM read 1-ciklus latencia / Sub3: SRAM read 1-cycle latency
    localparam [3:0] ST_CALL     = 4'd6;   // Sub5: CALL frame manager
    localparam [3:0] ST_RET      = 4'd7;   // Sub5: RET frame manager
    localparam [3:0] ST_HALT     = 4'd8;
    localparam [3:0] ST_TRAP     = 4'd9;

    // hu: Sub5 — ST_CALL sub-states (frame push szekvencia)
    // en: Sub5 — ST_CALL sub-states (frame push sequence)
    localparam [3:0] CALL_HDR_REQ      = 4'd0;
    localparam [3:0] CALL_HDR_WAIT     = 4'd1;
    localparam [3:0] CALL_VALIDATE     = 4'd2;
    localparam [3:0] CALL_ARG_POP_REQ  = 4'd3;
    localparam [3:0] CALL_ARG_POP_WAIT = 4'd4;
    localparam [3:0] CALL_ARG_POP_WR   = 4'd5;
    localparam [3:0] CALL_HDR_WR_RPC   = 4'd6;
    localparam [3:0] CALL_HDR_WR_PFP   = 4'd7;
    localparam [3:0] CALL_HDR_WR_AL    = 4'd8;
    localparam [3:0] CALL_LOCAL_ZERO   = 4'd9;
    localparam [3:0] CALL_FINALIZE     = 4'd10;

    // hu: Sub5 — ST_RET sub-states (frame pop szekvencia)
    // en: Sub5 — ST_RET sub-states (frame pop sequence)
    localparam [3:0] RET_REQ_RPC    = 4'd0;
    localparam [3:0] RET_WAIT_RPC   = 4'd1;
    localparam [3:0] RET_LATCH_RPC  = 4'd2;
    localparam [3:0] RET_WAIT_PFP   = 4'd3;
    localparam [3:0] RET_LATCH_PFP  = 4'd4;
    localparam [3:0] RET_WAIT_AL    = 4'd5;
    localparam [3:0] RET_LATCH_AL   = 4'd6;
    localparam [3:0] RET_FINALIZE   = 4'd7;
    localparam [3:0] RET_PUSH_RV    = 4'd8;

    // hu: Boot szekvencia alállapotok
    // en: Boot sequence sub-states
    localparam [2:0] BOOT_HDR0   = 3'd0;  // [FP+0] = -1 (ReturnPC)
    localparam [2:0] BOOT_HDR1   = 3'd1;  // [FP+4] = -1 (PrevFrameBase)
    localparam [2:0] BOOT_HDR2   = 3'd2;  // [FP+8] = {0, locals, args}
    localparam [2:0] BOOT_ARGS   = 3'd3;  // streaming args
    localparam [2:0] BOOT_LOCALS = 3'd4;  // zeroing locals
    localparam [2:0] BOOT_FINAL  = 3'd5;  // SP/FP/CallDepth init

    reg  [3:0]  r_state;
    reg  [2:0]  r_boot_sub;

    // ============================================================
    // hu: Belső állapot
    // en: Internal state
    // ============================================================
    reg  [23:0] r_pc;
    reg  [13:0] r_sp;
    reg  [13:0] r_fp;
    reg  [9:0]  r_call_depth;
    reg  [4:0]  r_arg_count;
    reg  [4:0]  r_local_count;
    reg  [3:0]  r_step;
    reg  [4:0]  r_boot_arg_idx;
    reg  [4:0]  r_boot_local_idx;
    reg  [1:0]  r_alu_phase;       // 0 = latch+pop (binary), 1 = replace_top
    reg  [31:0] r_alu_result_latched;
    reg         r_mem_phase;       // Sub3: 0 = pop1, 1 = SRAM write a pop_data-val
    reg  [13:0] r_mem_addr_latched;

    // hu: Sub5 — frame manager regiszterek (ST_CALL és ST_RET használja)
    // en: Sub5 — frame manager registers (used by ST_CALL and ST_RET)
    reg  [3:0]  r_call_sub;            // CALL sub-state
    reg  [3:0]  r_ret_sub;             // RET sub-state
    reg  [23:0] r_call_target_rva;     // CALL operand: callee header RVA
    reg  [23:0] r_return_pc;           // CALL utáni PC (a caller folytatása)
    reg  [4:0]  r_new_arg_count;       // CALL header-ből
    reg  [4:0]  r_new_local_count;     // CALL header-ből
    reg  [13:0] r_new_fp;              // FP_new = caller r_sp a CALL pillanatában
    reg  [4:0]  r_arg_pop_idx;         // CALL: hányadik arg pop-jánál tartunk
    reg  [4:0]  r_local_zero_idx;      // CALL: hányadik local nullázásánál
    reg  [31:0] r_ret_value;           // RET: a step 0-ban pop-olt return value
    reg  [13:0] r_callee_old_fp;       // RET: a callee r_fp-je (felszabadításhoz)
    reg  [23:0] r_ret_return_pc;       // RET: visszatérési PC (header [FP+0]-ból)
    reg  [13:0] r_ret_prev_fp;         // RET: caller FP (header [FP+4]-ből)

    // hu: Fetch buffer (8 byte, packed FIFO). A packed register a Verilator
    //     non-blocking assignment-jén megbízhatóbb mint a reg array
    //     (`reg [7:0] arr [0:7]`), amivel a slide-during-multi-NBA esetén
    //     a forrás-byte-okat néha hibás (cycle-X+1) értékkel olvasta.
    // en: Fetch buffer (8 byte, packed FIFO). Packed register is more
    //     reliable in Verilator NBA than the reg array form, where slides
    //     across multiple NBAs sometimes saw the wrong (cycle-X+1) source
    //     bytes.
    reg  [63:0] r_fetch_buf;    // byte 0 = [7:0], byte 7 = [63:56]
    reg  [3:0]  r_fetch_count;
    reg  [23:0] r_fetch_pc;     // a buffer első byte-jának PC-je

    // hu: Belső 16 KB SRAM (4096 × 32-bit) — inferred BRAM
    reg  [31:0] r_sram [0:4095];

    // hu: Aktuális utasítás (decode után latched)
    reg  [15:0] r_opcode;
    reg  [2:0]  r_length;
    reg  [31:0] r_operand;

    // hu: SRAM bus signal-ek (boot fázisban a top-level írja, később
    //     a Stack Cache + microcode is használja).
    // en: SRAM bus signals (top-level writes in boot, later also
    //     Stack Cache + microcode).
    reg  [13:0] r_sram_addr;
    reg  [31:0] r_sram_wdata;
    reg         r_sram_we;
    reg         r_sram_re;
    reg  [31:0] r_sram_rdata_latched;

    // ============================================================
    // hu: QSPI controller bekötése
    // en: QSPI controller wiring
    // ============================================================
    reg  [23:0] r_qspi_addr;
    reg         r_qspi_re;
    wire [31:0] w_qspi_rdata;
    wire        w_qspi_ready;
    wire        w_qspi_busy;

    // hu: Fetch addresszálás Sub2.1-ben bevezetett regiszterek.
    //     r_qspi_inflight = 1, ha épp folyamatban van fetch tranzakció;
    //     r_next_fetch_addr = a következő fetch cél címe (független
    //     r_pc/r_fetch_count NBA scheduling-jétől). A korábbi
    //     `r_qspi_addr <= r_pc + r_fetch_count` képlet Verilator NBA-ban
    //     racy volt: az 1. APPEND után cycle X+1-ben r_fetch_count még
    //     0-n látszott egyes path-eken, ezért a 2. fetch addr=0-t kapott
    //     4 helyett. Itt explicit állapotot tartunk fenn.
    // en: Fetch addressing registers introduced in Sub2.1.
    //     r_qspi_inflight = 1 when a fetch transaction is currently in
    //     flight; r_next_fetch_addr = target address of the next fetch
    //     (independent of r_pc/r_fetch_count NBA scheduling). The earlier
    //     `r_qspi_addr <= r_pc + r_fetch_count` was racy on Verilator NBA:
    //     after the 1st APPEND, cycle X+1 sometimes still saw r_fetch_count
    //     as 0 on certain paths, so the 2nd fetch got addr=0 instead of 4.
    //     Here we keep explicit state.
    reg         r_qspi_inflight;
    reg  [23:0] r_next_fetch_addr;

    cilcpu_qspi_controller u_qspi (
        .clk             (clk),
        .rst_n           (rst_n),
        .cpu_addr        (r_qspi_addr),
        .cpu_wdata       (32'd0),
        .cpu_rdata       (w_qspi_rdata),
        .cpu_re          (r_qspi_re),
        .cpu_we          (1'b0),
        .cpu_ready       (w_qspi_ready),
        .cpu_busy        (w_qspi_busy),
        .qspi_clk        (qspi_clk),
        .qspi_cs_flash_n (qspi_cs_flash_n),
        .qspi_cs_psram_n (qspi_cs_psram_n),
        .qspi_dq_out     (qspi_dq_out),
        .qspi_dq_in      (qspi_dq_in),
        .qspi_dq_oe      (qspi_dq_oe)
    );

    // ============================================================
    // hu: Decoder bekötése (kombinációs)
    // en: Decoder wiring (combinational)
    // ============================================================
    wire [15:0] w_dec_opcode;
    wire [2:0]  w_dec_length;
    wire [31:0] w_dec_operand;
    wire        w_dec_trap;
    wire [2:0]  w_dec_bytes_avail = (r_fetch_count > 4'd5) ? 3'd5 :
                                    r_fetch_count[2:0];

    cilcpu_decoder u_decoder (
        .i_byte0           (r_fetch_buf[ 7: 0]),
        .i_byte1           (r_fetch_buf[15: 8]),
        .i_byte2           (r_fetch_buf[23:16]),
        .i_byte3           (r_fetch_buf[31:24]),
        .i_byte4           (r_fetch_buf[39:32]),
        .i_bytes_available (w_dec_bytes_avail),
        .o_opcode          (w_dec_opcode),
        .o_length          (w_dec_length),
        .o_operand         (w_dec_operand),
        .o_trap_invalid    (w_dec_trap)
    );

    // ============================================================
    // hu: Microcode bekötése (kombinációs)
    // en: Microcode wiring (combinational)
    // ============================================================
    wire [31:0] w_uc_ctrl;
    wire [3:0]  w_uc_nsteps;
    wire        w_uc_valid;

    cilcpu_microcode u_microcode (
        .i_opcode (r_opcode),
        .i_step   (r_step),
        .o_ctrl   (w_uc_ctrl),
        .o_nsteps (w_uc_nsteps),
        .o_valid  (w_uc_valid)
    );

    // hu: Vezérlőszó mező-kibontás
    // en: Control word field extraction
    wire        uc_done       = w_uc_ctrl[`UC_DONE];
    wire        uc_trap_en    = w_uc_ctrl[`UC_TRAP];
    wire [3:0]  uc_trap_code  = w_uc_ctrl[`UC_TRAP_CODE_HI:`UC_TRAP_CODE_LO];
    wire [1:0]  uc_stack_pop  = w_uc_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO];
    wire        uc_stack_push = w_uc_ctrl[`UC_STACK_PUSH];
    wire [1:0]  uc_push_src   = w_uc_ctrl[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO];
    wire        uc_alu_en     = w_uc_ctrl[`UC_ALU_EN];
    wire [4:0]  uc_alu_op     = w_uc_ctrl[`UC_ALU_OP_HI:`UC_ALU_OP_LO];
    wire        uc_sram_rd    = w_uc_ctrl[`UC_SRAM_RD];
    wire        uc_sram_wr    = w_uc_ctrl[`UC_SRAM_WR];
    wire [1:0]  uc_addr_src   = w_uc_ctrl[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO];
    wire        uc_pc_wr      = w_uc_ctrl[`UC_PC_WR];
    wire [1:0]  uc_pc_src     = w_uc_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO];
    wire        uc_frame_pop  = w_uc_ctrl[`UC_FRAME_POP];
    wire        uc_frame_push = w_uc_ctrl[`UC_FRAME_PUSH];
    wire        uc_halt_en    = w_uc_ctrl[`UC_HALT];
    wire        uc_cond_en    = w_uc_ctrl[`UC_COND_EN];
    wire [1:0]  uc_cond_type  = w_uc_ctrl[`UC_COND_TYPE_HI:`UC_COND_TYPE_LO];
    wire        uc_cond_pop   = w_uc_ctrl[`UC_COND_POP];

    // ============================================================
    // hu: Stack Cache bekötése
    // en: Stack Cache wiring
    // ============================================================
    reg         r_sc_sp_load;
    reg  [13:0] r_sc_sp_init;
    reg         r_sc_push_en;
    reg  [31:0] r_sc_push_data;
    reg         r_sc_pop_en;
    reg         r_sc_replace_top_en;
    reg  [31:0] r_sc_replace_top_data;
    wire [31:0] w_sc_tos;
    wire [31:0] w_sc_tos1;
    wire [31:0] w_sc_pop_data;
    wire [6:0]  w_sc_depth;
    wire        w_sc_busy;
    wire        w_sc_ready;
    wire        w_sc_trap;
    wire [7:0]  w_sc_trap_code;

    // hu: A Stack Cache SRAM master portjai Sub3-ban kapcsolódnak a belső
    //     16 KB SRAM-ra egy egyszerű prioritásos arbiter-en át (lásd
    //     lentebb). A microcode kontrakt szerint uc_sram_rd/wr csak akkor
    //     aktív, ha w_sc_busy=0 — ezért a busy-priority arbitrálás
    //     determinisztikus, race-mentes.
    // en: The Stack Cache SRAM master ports are wired to the internal
    //     16 KB SRAM in Sub3 via a simple priority arbiter (see below).
    //     Per microcode contract, uc_sram_rd/wr fires only when w_sc_busy=0
    //     — hence busy-priority arbitration is deterministic and race-free.
    wire [13:0] w_sc_sram_addr;
    wire [31:0] w_sc_sram_wdata;
    wire        w_sc_sram_we;
    wire        w_sc_sram_re;
    wire [31:0] w_sc_sram_rdata;
    wire        w_sc_sram_ready;

    cilcpu_stack_cache u_stack_cache (
        .clk              (clk),
        .rst_n            (rst_n),
        .sp_load          (r_sc_sp_load),
        .sp_init          (r_sc_sp_init),
        .push_en          (r_sc_push_en),
        .push_data        (r_sc_push_data),
        .pop_en           (r_sc_pop_en),
        .dup_en           (1'b0),
        .swap_en          (1'b0),
        .replace_top_en   (r_sc_replace_top_en),
        .replace_top_data (r_sc_replace_top_data),
        .peek_index       (2'd0),
        .peek_data        (),
        .tos              (w_sc_tos),
        .tos1             (w_sc_tos1),
        .pop_data         (w_sc_pop_data),
        .depth            (w_sc_depth),
        .cache_count      (),
        .busy             (w_sc_busy),
        .ready            (w_sc_ready),
        .trap             (w_sc_trap),
        .trap_code        (w_sc_trap_code),
        .sram_addr        (w_sc_sram_addr),
        .sram_wdata       (w_sc_sram_wdata),
        .sram_rdata       (w_sc_sram_rdata),
        .sram_we          (w_sc_sram_we),
        .sram_re          (w_sc_sram_re),
        .sram_ready       (w_sc_sram_ready)
    );

    // ============================================================
    // hu: ALU bekötése — i_op_a = TOS1, i_op_b = TOS (a CIL-T0 stack
    //     konvenciója: push a, push b, ALU(op_a=a, op_b=b)). Az ALU
    //     kombinációs, az eredmény azonnal érvényes.
    // en: ALU wiring — i_op_a = TOS1, i_op_b = TOS (CIL-T0 stack
    //     convention: push a, push b, ALU(op_a=a, op_b=b)). The ALU is
    //     combinational, result valid immediately.
    // ============================================================
    wire [31:0] w_alu_result;
    wire        w_alu_trap_div_zero;
    wire        w_alu_trap_overflow;

    // hu: ALU operandus mux — binary (pop=2): i_op_a=TOS1, i_op_b=TOS;
    //     unary (pop=1): i_op_a=TOS (a stack tetején lévő érték), i_op_b
    //     nem használt. A microcode `alu_unary` UC_STACK_POP=1, az ALU
    //     NEG/NOT az i_op_a-t veszi.
    // en: ALU operand mux — binary (pop=2): i_op_a=TOS1, i_op_b=TOS;
    //     unary (pop=1): i_op_a=TOS (the value on top), i_op_b unused.
    //     The `alu_unary` microcode has UC_STACK_POP=1; ALU NEG/NOT use
    //     i_op_a.
    wire [31:0] w_alu_op_a = (uc_stack_pop == 2'd1) ? w_sc_tos : w_sc_tos1;

    cilcpu_alu u_alu (
        .i_op_a          (w_alu_op_a),
        .i_op_b          (w_sc_tos),
        .i_alu_op        (uc_alu_op),
        .o_result        (w_alu_result),
        .o_trap_div_zero (w_alu_trap_div_zero),
        .o_trap_overflow (w_alu_trap_overflow)
    );

    // ============================================================
    // hu: Push data mux — a microcode UC_PUSH_SRC = IMM esetén az
    //     opcode-ból (rejtett konstansok) vagy a decoder operand-jából.
    // en: Push data mux — when microcode UC_PUSH_SRC = IMM, source is
    //     the opcode (hidden constants) or the decoder operand.
    // ============================================================
    reg [31:0] push_data_imm;

    always @(*) begin
        // hu: Az r_opcode alsó byte-ja az LDC.I4_* opcode
        case (r_opcode[7:0])
            `OP_LDC_I4_M1: push_data_imm = 32'hFFFF_FFFF;
            `OP_LDC_I4_0:  push_data_imm = 32'd0;
            `OP_LDC_I4_1:  push_data_imm = 32'd1;
            `OP_LDC_I4_2:  push_data_imm = 32'd2;
            `OP_LDC_I4_3:  push_data_imm = 32'd3;
            `OP_LDC_I4_4:  push_data_imm = 32'd4;
            `OP_LDC_I4_5:  push_data_imm = 32'd5;
            `OP_LDC_I4_6:  push_data_imm = 32'd6;
            `OP_LDC_I4_7:  push_data_imm = 32'd7;
            `OP_LDC_I4_8:  push_data_imm = 32'd8;
            `OP_LDNULL:    push_data_imm = 32'd0;
            default:       push_data_imm = r_operand;  // LDC.I4_S, LDC.I4
        endcase
    end

    // ============================================================
    // hu: PC update mux
    //     PC_SRC_BRANCH: rövid branch — operand[7:0] sign-extend a
    //       pc + length-hez. (A decoder már sign-extend-el 32 bitre.)
    // en: PC update mux
    //     PC_SRC_BRANCH: short branch — sign-extend operand[7:0] added
    //       to pc + length. (Decoder already sign-extends to 32 bits.)
    // ============================================================
    reg [23:0] pc_next;

    wire signed [23:0] branch_offset_ext = {{16{r_operand[7]}}, r_operand[7:0]};

    always @(*) begin
        case (uc_pc_src)
            `PC_SRC_NEXT:   pc_next = r_pc + {21'd0, r_length};
            `PC_SRC_BRANCH: pc_next = r_pc + {21'd0, r_length} + branch_offset_ext;
            `PC_SRC_RET:    pc_next = r_sram[r_fp[13:2]][23:0];
            default:        pc_next = r_pc;  // PC_SRC_CALL: Sub5
        endcase
    end

    // ============================================================
    // hu: Branch eldöntés — Sub4
    //     1-operand branches (BRFALSE_S / BRTRUE_S): a cond_type a TOS
    //       alapján:
    //         COND_EQ → branch ha TOS == 0 (BRFALSE)
    //         COND_NE → branch ha TOS != 0 (BRTRUE)
    //     2-operand branches (BEQ/BLT/BGE/BGT/BLE/BNE): az ALU eredménye
    //       (CEQ/CLT/CGT) 0/1, és a cond_type ezt fordítja vissza:
    //         COND_NE → branch ha alu_result != 0 (alapértelmezett)
    //         COND_EQ → branch ha alu_result == 0 (BGE = !CLT, BLE = !CGT)
    //     Az `r_alu_result_latched` a phase 0-ban beolvasott ALU eredmény.
    // en: Branch decision — Sub4
    //     1-operand branches: cond_type vs TOS;
    //     2-operand branches: ALU result via cond_type inversion.
    // ============================================================
    wire branch_taken_1op = uc_cond_en && (uc_stack_pop == 2'd1) && (
        (uc_cond_type == `COND_EQ && w_sc_tos == 32'd0) ||
        (uc_cond_type == `COND_NE && w_sc_tos != 32'd0)
    );

    wire branch_taken_2op_phase1 = uc_cond_en && uc_alu_en && (
        (uc_cond_type == `COND_NE && r_alu_result_latched != 32'd0) ||
        (uc_cond_type == `COND_EQ && r_alu_result_latched == 32'd0)
    );

    // hu: Sub4 hiánypótlás — Branch target validáció (TRAP_INVALID_BRANCH).
    //     A spec szerint a branch target `target < 0` esetén trap-elt.
    //     F2.5a egyszerűsítés: csak negatív cím (felső bit = 1) trap-elt;
    //     pozitív túlcsordulás (24-bit címterén túl) NEM detektálódik itt,
    //     hanem a következő ciklus fetch-én (0xFF byte → INVALID_OPCODE).
    //     Mivel `pc_next` 24-bit unsigned, a `branch_offset_ext` 24-bit
    //     signed → ha pc_next felső bitje 1, az -8M..-1 tartomány = negatív.
    //     Csak akkor érvényes a vizsgálat, ha PC_SRC_BRANCH (1-op vagy 2-op
    //     branch); call/ret nem ide tartozik (Sub5).
    // en: Sub4 hardening — Branch target validation (TRAP_INVALID_BRANCH).
    //     Per spec, the branch is invalid if `target < 0`. F2.5a simplifies
    //     to: only negative target (top bit set in 24-bit) traps; positive
    //     overflow (above 24-bit address space) is NOT detected here, but
    //     on next-cycle fetch (0xFF byte → INVALID_OPCODE).
    //     `pc_next` is 24-bit unsigned; `branch_offset_ext` is 24-bit
    //     signed → if pc_next's top bit is 1, the value is in -8M..-1.
    //     Only valid when PC_SRC_BRANCH (1-op or 2-op branch); call/ret
    //     are out of scope (Sub5).
    wire branch_target_invalid = (uc_pc_src == `PC_SRC_BRANCH) &&
                                  (pc_next[23] == 1'b1);

    // ============================================================
    // hu: SRAM rdata/ready wireing a Stack Cache felé.
    //     A regisztrált SRAM-olvasás eredménye a következő ciklus elején
    //     érvényes; a Stack Cache 1-ciklus latencia + sram_ready-vel
    //     szinkronizál. Az SRAM mindig 1-ciklus alatt válaszol →
    //     sram_ready statikusan 1.
    // en: SRAM rdata/ready wiring to Stack Cache.
    //     Registered SRAM read result is valid at the next cycle's start;
    //     the Stack Cache uses 1-cycle latency + sram_ready handshake.
    //     SRAM always responds in 1 cycle → sram_ready is static 1.
    // ============================================================
    assign w_sc_sram_rdata = r_sram_rdata_latched;
    assign w_sc_sram_ready = 1'b1;

    // ============================================================
    // hu: Sub3 — SRAM cím számítás (frame layout):
    //     ARG:   FP + 12 + idx*4
    //     LOCAL: FP + 12 + arg_count*4 + idx*4
    //     A range check a microcode-szervezésben már megelőzi az SRAM
    //     hozzáférést (lásd ST_EXECUTE → uc_sram_rd/wr ág).
    // en: Sub3 — SRAM address calculation (frame layout):
    //     ARG:   FP + 12 + idx*4
    //     LOCAL: FP + 12 + arg_count*4 + idx*4
    //     Range check precedes SRAM access in the sequencer.
    // ============================================================
    // hu: Hatásos arg/local index — az LDARG.0..3 / LDLOC.0..3 / STLOC.0..3
    //     opkódok az indexet az opcode byte-ban hordozzák (operand=0):
    //       0x02..0x05 LDARG.0..3 → idx = opcode - 0x02
    //       0x06..0x09 LDLOC.0..3 → idx = opcode - 0x06
    //       0x0A..0x0D STLOC.0..3 → idx = opcode - 0x0A
    //     Az LDARG.S/STARG.S/LDLOC.S/STLOC.S esetén az operandus tartalmazza
    //     az indexet (8-bit unsigned).
    // en: Effective arg/local index — short opcodes carry the index in the
    //     opcode byte itself (operand=0):
    //       0x02..0x05 LDARG.0..3 → idx = opcode - 0x02
    //       0x06..0x09 LDLOC.0..3 → idx = opcode - 0x06
    //       0x0A..0x0D STLOC.0..3 → idx = opcode - 0x0A
    //     The .S forms carry the index in the operand.
    wire [7:0]  eff_idx =
        (r_opcode[7:0] >= 8'h02 && r_opcode[7:0] <= 8'h05) ? (r_opcode[7:0] - 8'h02) :
        (r_opcode[7:0] >= 8'h06 && r_opcode[7:0] <= 8'h09) ? (r_opcode[7:0] - 8'h06) :
        (r_opcode[7:0] >= 8'h0A && r_opcode[7:0] <= 8'h0D) ? (r_opcode[7:0] - 8'h0A) :
        r_operand[7:0];

    function [13:0] addr_calc;
        input [1:0]  fc_addr_src;
        input [7:0]  fc_idx;
        reg [13:0] base;
        begin
            base = r_fp + 14'd12;
            case (fc_addr_src)
                `ADDR_SRC_ARG:   addr_calc = base + {4'd0, fc_idx, 2'd0};
                `ADDR_SRC_LOCAL: addr_calc = base + {7'd0, r_arg_count, 2'd0}
                                                   + {4'd0, fc_idx, 2'd0};
                `ADDR_SRC_FRAME: addr_calc = r_fp + {4'd0, fc_idx, 2'd0};
                default:         addr_calc = base;
            endcase
        end
    endfunction

    // ============================================================
    // hu: Fő FSM
    // en: Main FSM
    // ============================================================
    // hu: A buffer csúsztatás explicit case-szel megy — nem kell loop index.
    // en: Buffer slide uses explicit case — no loop index needed.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state          <= ST_RESET;
            r_boot_sub       <= BOOT_HDR0;
            r_pc             <= 24'd0;
            r_sp             <= 14'd0;
            r_fp             <= 14'd0;
            r_call_depth     <= 10'd0;
            r_arg_count      <= 5'd0;
            r_local_count    <= 5'd0;
            r_step           <= 4'd0;
            r_boot_arg_idx   <= 5'd0;
            r_boot_local_idx <= 5'd0;
            r_fetch_count    <= 4'd0;
            r_fetch_pc       <= 24'd0;
            r_fetch_buf      <= 64'd0;
            r_opcode         <= 16'd0;
            r_length         <= 3'd0;
            r_operand        <= 32'd0;
            r_qspi_addr      <= 24'd0;
            r_qspi_re        <= 1'b0;
            // hu: Sub2.1 — fetch addresszálás állapot reset
            // en: Sub2.1 — fetch addressing state reset
            r_qspi_inflight  <= 1'b0;
            r_next_fetch_addr <= 24'd0;
            r_sram_addr      <= 14'd0;
            r_sram_wdata     <= 32'd0;
            r_sram_we        <= 1'b0;
            r_sram_re        <= 1'b0;
            r_sram_rdata_latched <= 32'd0;
            r_sc_sp_load     <= 1'b0;
            r_sc_sp_init     <= 14'd0;
            r_sc_push_en     <= 1'b0;
            r_sc_push_data   <= 32'd0;
            r_sc_pop_en      <= 1'b0;
            r_sc_replace_top_en   <= 1'b0;
            r_sc_replace_top_data <= 32'd0;
            r_alu_phase           <= 2'd0;
            r_alu_result_latched  <= 32'd0;
            r_mem_phase           <= 1'b0;
            r_mem_addr_latched    <= 14'd0;
            // hu: Sub5 — frame manager regiszterek reset
            // en: Sub5 — frame manager registers reset
            r_call_sub            <= CALL_HDR_REQ;
            r_ret_sub             <= RET_REQ_RPC;
            r_call_target_rva     <= 24'd0;
            r_return_pc           <= 24'd0;
            r_new_arg_count       <= 5'd0;
            r_new_local_count     <= 5'd0;
            r_new_fp              <= 14'd0;
            r_arg_pop_idx         <= 5'd0;
            r_local_zero_idx      <= 5'd0;
            r_ret_value           <= 32'd0;
            r_callee_old_fp       <= 14'd0;
            r_ret_return_pc       <= 24'd0;
            r_ret_prev_fp         <= 14'd0;
            o_halt           <= 1'b0;
            o_trap           <= 1'b0;
            o_trap_code      <= 8'd0;
            o_pc             <= 24'd0;
            o_return_value   <= 32'd0;
            o_boot_arg_ready <= 1'b0;
            // hu: Az SRAM nem zerózódik reset-tel — szintézisben undefined.
            //     Az F2.5a viselkedés: a boot felülír, így nem olvasunk
            //     inicializálatlan címről.
        end else begin
            // hu: Default jelek minden ciklus elején
            r_qspi_re        <= 1'b0;
            r_sram_we        <= 1'b0;
            r_sram_re        <= 1'b0;
            r_sc_sp_load        <= 1'b0;
            r_sc_push_en        <= 1'b0;
            r_sc_pop_en         <= 1'b0;
            r_sc_replace_top_en <= 1'b0;
            o_boot_arg_ready    <= 1'b0;
            o_pc                <= r_pc;

            // hu: Sub6 — Stack Cache trap aggregátor: az SC pulzusos trap
            //     jele (overflow / underflow) bármelyik állapotban
            //     detektálható; átáll ST_TRAP-be, latch-eli a trap_code-ot.
            // en: Sub6 — Stack Cache trap aggregator: SC pulses trap on
            //     overflow / underflow, detectable from any state →
            //     ST_TRAP, latch trap_code.
            if (w_sc_trap && r_state != ST_TRAP && r_state != ST_HALT) begin
                o_trap      <= 1'b1;
                o_trap_code <= w_sc_trap_code;
                r_state     <= ST_TRAP;
            end

            // hu: SRAM bus arbiter — a Stack Cache spill/fill PRIORITÁS-T
            //     kap. A microcode kontrakt biztosítja, hogy uc_sram_rd/wr
            //     csak akkor fut le, amikor w_sc_busy=0 (a Stack Cache
            //     egyszerre csak egyfajta műveletet csinál). Tehát a busy-
            //     priority race-mentes és determinisztikus.
            //     SRAM olvasás 1-ciklus latency: r_sram_rdata_latched a
            //     következő ciklus elején érvényes.
            // en: SRAM bus arbiter — Stack Cache spill/fill takes PRIORITY.
            //     Per microcode contract, uc_sram_rd/wr fires only when
            //     w_sc_busy=0 (Stack Cache runs one op at a time), so
            //     busy-priority is race-free and deterministic.
            //     SRAM read 1-cycle latency: r_sram_rdata_latched valid at
            //     the next cycle's start.
            if (w_sc_busy) begin
                if (w_sc_sram_re) begin
                    r_sram_rdata_latched <= r_sram[w_sc_sram_addr[13:2]];
                end
                if (w_sc_sram_we) begin
                    r_sram[w_sc_sram_addr[13:2]] <= w_sc_sram_wdata;
                end
            end else begin
                if (r_sram_re) begin
                    r_sram_rdata_latched <= r_sram[r_sram_addr[13:2]];
                end
                if (r_sram_we) begin
                    r_sram[r_sram_addr[13:2]] <= r_sram_wdata;
                end
            end

            case (r_state)

            // ====================================================
            // ST_RESET — vár i_boot_start-ra
            // ====================================================
            ST_RESET: begin
                if (i_boot_start) begin
                    r_arg_count    <= i_boot_arg_count[4:0];
                    r_local_count  <= i_boot_local_count[4:0];
                    r_pc           <= i_boot_pc;
                    r_fp           <= 14'd0;
                    r_sp           <= 14'd0;
                    r_call_depth   <= 10'd1;
                    r_boot_arg_idx <= 5'd0;
                    r_boot_local_idx <= 5'd0;
                    r_state        <= ST_BOOT;
                    r_boot_sub     <= BOOT_HDR0;
                end
            end

            // ====================================================
            // ST_BOOT — root frame felépítése
            // ====================================================
            ST_BOOT: begin
                case (r_boot_sub)
                    BOOT_HDR0: begin
                        r_sram_addr  <= 14'd0;     // FP+0 = 0
                        r_sram_wdata <= 32'hFFFF_FFFF;  // ReturnPC = -1
                        r_sram_we    <= 1'b1;
                        r_boot_sub   <= BOOT_HDR1;
                    end
                    BOOT_HDR1: begin
                        r_sram_addr  <= 14'd4;     // FP+4
                        r_sram_wdata <= 32'hFFFF_FFFF;  // PrevFrameBase = -1
                        r_sram_we    <= 1'b1;
                        r_boot_sub   <= BOOT_HDR2;
                    end
                    BOOT_HDR2: begin
                        r_sram_addr  <= 14'd8;     // FP+8
                        r_sram_wdata <= {16'd0,
                                         3'd0, r_local_count,
                                         3'd0, r_arg_count};
                        r_sram_we    <= 1'b1;
                        if (r_arg_count > 5'd0) begin
                            r_boot_sub <= BOOT_ARGS;
                        end else if (r_local_count > 5'd0) begin
                            r_boot_sub <= BOOT_LOCALS;
                        end else begin
                            r_boot_sub <= BOOT_FINAL;
                        end
                    end
                    BOOT_ARGS: begin
                        // hu: Várjuk az i_boot_arg_valid pulzust
                        o_boot_arg_ready <= 1'b1;
                        if (i_boot_arg_valid) begin
                            r_sram_addr  <= 14'd12 + {7'd0, r_boot_arg_idx, 2'd0};
                            r_sram_wdata <= i_boot_arg_data;
                            r_sram_we    <= 1'b1;
                            r_boot_arg_idx <= r_boot_arg_idx + 5'd1;
                            o_boot_arg_ready <= 1'b0;
                            if (r_boot_arg_idx + 5'd1 >= r_arg_count) begin
                                if (r_local_count > 5'd0) begin
                                    r_boot_sub <= BOOT_LOCALS;
                                end else begin
                                    r_boot_sub <= BOOT_FINAL;
                                end
                            end
                        end
                    end
                    BOOT_LOCALS: begin
                        r_sram_addr  <= 14'd12
                                        + {7'd0, r_arg_count, 2'd0}
                                        + {7'd0, r_boot_local_idx, 2'd0};
                        r_sram_wdata <= 32'd0;
                        r_sram_we    <= 1'b1;
                        r_boot_local_idx <= r_boot_local_idx + 5'd1;
                        if (r_boot_local_idx + 5'd1 >= r_local_count) begin
                            r_boot_sub <= BOOT_FINAL;
                        end
                    end
                    BOOT_FINAL: begin
                        // hu: SP = 12 + arg_count*4 + local_count*4
                        r_sp <= 14'd12
                                + {7'd0, r_arg_count, 2'd0}
                                + {7'd0, r_local_count, 2'd0};
                        // hu: Stack Cache reset az új SP-re
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= 14'd12
                                        + {7'd0, r_arg_count, 2'd0}
                                        + {7'd0, r_local_count, 2'd0};
                        r_state    <= ST_FETCH;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc <= r_pc;
                        // hu: Sub2.1 — a fetch állapot inicializálása az
                        //     i_boot_pc-re; a soron következő ST_FETCH ettől
                        //     a címtől indítja az 1. tranzakciót.
                        // en: Sub2.1 — initialize fetch state to i_boot_pc;
                        //     the next ST_FETCH will start the 1st
                        //     transaction from this address.
                        r_next_fetch_addr <= i_boot_pc;
                        r_qspi_inflight   <= 1'b0;
                    end
                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // ST_FETCH — fetch buffer feltöltés
            // hu: A feltételek sorrendje fontos! Ha a controller éppen
            //     befejezte a fetch-et (cpu_ready=1, busy=0), az append
            //     ágnak ELSŐBBSÉGE van a fetch-indítás ágával szemben,
            //     különben az indítás "elmosná" az aktuális adatot.
            // en: Order of conditions matters! If the controller just
            //     completed (cpu_ready=1, busy=0), the append branch must
            //     win over the fetch-start branch, otherwise we'd lose the
            //     just-arrived data.
            // ====================================================
            ST_FETCH: begin
                if (r_fetch_count >= 4'd5) begin
                    r_state <= ST_DECODE;
                end else if (w_qspi_ready) begin
                    // hu: 4-byte append a packed buffer-be tetszőleges
                    //     r_fetch_count (0..4) értéknél. A korábbi 0/4-csak
                    //     verzió a Sub2.2 előtt: 5-byte LDC.I4 után
                    //     r_fetch_count=3 maradt (slide-down nem 4-byte
                    //     aligned), és a default ág eldobta a következő
                    //     fetch eredményét → timeout.
                    //     Sub2.2: explicit case minden cnt=0..4 értékre,
                    //     mindegyik a `cnt*8` bit ofszetre illeszti a
                    //     little-endian 4-byte word-öt. cnt>=5 esetén nem
                    //     indulhatott volna fetch (lásd ST_FETCH felső ág),
                    //     ezért default ágra nem futhatunk.
                    // en: 4-byte append to the packed buffer at any
                    //     r_fetch_count (0..4). The earlier 0/4-only form:
                    //     after 5-byte LDC.I4, r_fetch_count=3 (slide is
                    //     not 4-byte aligned) and the default arm dropped
                    //     the next fetch result → timeout.
                    //     Sub2.2: explicit case for every cnt=0..4, each
                    //     inserting the little-endian 4-byte word at the
                    //     `cnt*8` bit offset. cnt>=5 cannot start a fetch
                    //     (see top branch in ST_FETCH), so default cannot
                    //     fire.
                    case (r_fetch_count)
                        4'd0: r_fetch_buf[31: 0] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd1: r_fetch_buf[39: 8] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd2: r_fetch_buf[47:16] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd3: r_fetch_buf[55:24] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd4: r_fetch_buf[63:32] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        default: ;
                    endcase
                    r_fetch_count     <= r_fetch_count + 4'd4;
                    r_qspi_inflight   <= 1'b0;
                    r_next_fetch_addr <= r_next_fetch_addr + 24'd4;
                end else if (!r_qspi_inflight) begin
                    // hu: Új fetch indítása. A feltétel a Sub2.1 fix után
                    //     egyetlen állapot-bittől függ (r_qspi_inflight),
                    //     a w_qspi_busy redundáns volt és Verilator NBA
                    //     race-t okozott. A cím a r_next_fetch_addr-ból
                    //     jön — ezt a Boot finalize r_pc-re inicializálja,
                    //     APPEND után +4-gyel léptetjük, full-flush-nál
                    //     pedig pc_next-re állítjuk.
                    // en: Start a new fetch. After the Sub2.1 fix, the
                    //     condition depends on a single state bit
                    //     (r_qspi_inflight); w_qspi_busy was redundant
                    //     and caused a Verilator NBA race. The address
                    //     comes from r_next_fetch_addr — initialized to
                    //     r_pc on Boot finalize, advanced by +4 after
                    //     APPEND, and reset to pc_next on full flush.
                    r_qspi_addr     <= r_next_fetch_addr;
                    r_qspi_re       <= 1'b1;
                    r_qspi_inflight <= 1'b1;
                end
            end

            // ====================================================
            // ST_DECODE — 1 ciklus, decoder kombinációs eredmény latch
            // ====================================================
            ST_DECODE: begin
                if (w_dec_trap) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= `TRAP_INVALID_OPCODE;
                    r_state     <= ST_TRAP;
                end else begin
                    r_opcode  <= w_dec_opcode;
                    r_length  <= w_dec_length;
                    r_operand <= w_dec_operand;
                    r_step    <= 4'd0;
                    r_state   <= ST_EXECUTE;
                end
            end

            // ====================================================
            // ST_EXECUTE — microcode sequencer
            // hu: Az ALU opcode-okat 2 ciklusra bontjuk (binary) vagy
            //     1 ciklusra (unary), mert a Stack Cache nem támogatja
            //     a pop_en+push_en egyidejű kombinációt. Binary minta:
            //       phase 0: latch ALU(tos1, tos), pop_en=1
            //       phase 1: replace_top(r_alu_result_latched)
            //     Unary minta: phase 0 csak: replace_top(alu_result).
            // en: ALU opcodes split into 2 cycles (binary) or 1 cycle
            //     (unary), since the Stack Cache disallows simultaneous
            //     pop_en+push_en. Binary pattern:
            //       phase 0: latch ALU(tos1, tos), pop_en=1
            //       phase 1: replace_top(r_alu_result_latched)
            //     Unary pattern: phase 0 only: replace_top(alu_result).
            // ====================================================
            ST_EXECUTE: begin
                if (!w_uc_valid) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= `TRAP_INVALID_OPCODE;
                    r_state     <= ST_TRAP;
                end else if (uc_trap_en) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= {4'd0, uc_trap_code};
                    r_state     <= ST_TRAP;
                end else if (uc_alu_en && r_alu_phase == 2'd0) begin
                    // hu: ALU phase 0 — kombinációs ALU eredmény latch-elése
                    //     (TOS1, TOS még érvényes), trap-ek ellenőrzése.
                    // en: ALU phase 0 — latch combinational ALU result
                    //     (TOS1, TOS still valid), check traps.
                    if (w_alu_trap_div_zero) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_DIV_BY_ZERO;
                        r_state     <= ST_TRAP;
                    end else if (w_alu_trap_overflow) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_OVERFLOW;
                        r_state     <= ST_TRAP;
                    end else begin
                        r_alu_result_latched <= w_alu_result;
                        if (uc_stack_pop == 2'd2) begin
                            // hu: Binary — pop1 most, replace_top phase 1-ben
                            r_sc_pop_en <= 1'b1;
                            r_alu_phase <= 2'd1;
                            // hu: NEM uc_done — phase 1-be megyünk
                        end else begin
                            // hu: Unary — replace_top egyciklus alatt,
                            //     uc_done flow.
                            r_sc_replace_top_en   <= 1'b1;
                            r_sc_replace_top_data <= w_alu_result;
                            // hu: uc_done flow lefut alább
                            if (uc_pc_wr) begin
                                r_pc <= pc_next;
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                // hu: Sub2.1 — full-flush a fetch címet
                                //     pc_next-re állítja. Az esetlegesen
                                //     in-flight tranzakciót hagyjuk
                                //     befejeződni, az adat eldobódik
                                //     (a következő ST_FETCH a friss címet
                                //     fogja használni).
                                // en: Sub2.1 — full-flush sets the fetch
                                //     address to pc_next. Any in-flight
                                //     transaction is allowed to finish;
                                //     its data is discarded (the next
                                //     ST_FETCH uses the fresh address).
                                r_next_fetch_addr <= pc_next;
                            end
                            r_step  <= 4'd0;
                            r_state <= ST_FETCH;
                        end
                    end
                end else if (uc_alu_en && uc_cond_en && r_alu_phase == 2'd1) begin
                    // hu: 2-operand branch phase 1 (Sub4) — második pop,
                    //     branch eldöntés r_alu_result_latched alapján.
                    //     NEM replace_top, mert a stack-en már nincs
                    //     szükség az eredményre (az ALU comp BEQ/BLT/...
                    //     csak a feltételhez kellett).
                    //     Sub4 hiánypótlás: ha a branch teljesül és a
                    //     target negatív → TRAP_INVALID_BRANCH a PC update
                    //     előtt (a pop-ot már megengedjük, mert az állapot
                    //     ettől függetlenül halad).
                    // en: 2-operand branch phase 1 (Sub4) — second pop,
                    //     branch decision based on r_alu_result_latched.
                    //     No replace_top — the stack no longer needs the
                    //     comparison result.
                    //     Sub4 hardening: if branch is taken and target is
                    //     negative → TRAP_INVALID_BRANCH before PC update.
                    r_sc_pop_en <= 1'b1;
                    r_alu_phase <= 2'd0;
                    if (branch_taken_2op_phase1 && branch_target_invalid) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_BRANCH;
                        r_state     <= ST_TRAP;
                    end else if (branch_taken_2op_phase1) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                        r_step  <= 4'd0;
                        r_state <= ST_FETCH;
                    end else begin
                        r_pc          <= r_pc + {21'd0, r_length};
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_pc + {21'd0, r_length};
                        r_next_fetch_addr <= r_pc + {21'd0, r_length};
                        r_step  <= 4'd0;
                        r_state <= ST_FETCH;
                    end
                end else if (uc_alu_en && r_alu_phase == 2'd1) begin
                    // hu: ALU phase 1 (binary, NEM cond) — replace_top a
                    //     latch-elt eredménnyel, uc_done flow.
                    // en: ALU phase 1 (binary, non-cond) — replace_top
                    //     with latched result, uc_done flow.
                    r_sc_replace_top_en   <= 1'b1;
                    r_sc_replace_top_data <= r_alu_result_latched;
                    r_alu_phase           <= 2'd0;
                    if (uc_pc_wr) begin
                        r_pc <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        // hu: Sub2.1 — lásd unary ág kommentje.
                        // en: Sub2.1 — see unary branch comment.
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end else if (uc_sram_rd) begin
                    // hu: Sub3 — SRAM olvasás (LDARG / LDLOC).
                    //     1. Range check: ARG → idx < arg_count, LOCAL →
                    //        idx < local_count. Hibás esetén megfelelő trap.
                    //     2. SRAM read indítás (1-ciklus latency), átmenet
                    //        ST_MEM_WAIT-re — ott push_data <= rdata és
                    //        uc_done flow.
                    //     A hatásos indexet `eff_idx` szolgáltatja: az
                    //     LDARG.0..3 / LDLOC.0..3 az opcode byte alsó 2
                    //     bitjéből, az .S formák az r_operand[7:0]-ból.
                    // en: Sub3 — SRAM read (LDARG / LDLOC).
                    //     1. Range check: ARG → idx < arg_count, LOCAL →
                    //        idx < local_count; trap on mismatch.
                    //     2. Start SRAM read (1-cycle latency), transition
                    //        to ST_MEM_WAIT for push_data <= rdata + uc_done.
                    //     `eff_idx` derives the index: short opcodes from
                    //     opcode[1:0], .S forms from r_operand[7:0].
                    if (uc_addr_src == `ADDR_SRC_ARG &&
                        eff_idx >= {3'd0, r_arg_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_ARG;
                        r_state     <= ST_TRAP;
                    end else if (uc_addr_src == `ADDR_SRC_LOCAL &&
                                 eff_idx >= {3'd0, r_local_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_LOCAL;
                        r_state     <= ST_TRAP;
                    end else begin
                        r_sram_addr <= addr_calc(uc_addr_src, eff_idx);
                        r_sram_re   <= 1'b1;
                        r_state     <= ST_MEM_WAIT;
                    end
                end else if (uc_sram_wr && r_mem_phase == 1'b0) begin
                    // hu: Sub3 — SRAM írás (STARG / STLOC) phase 0:
                    //     range check (mint az olvasásnál), majd pop_en=1
                    //     és cím latch — phase 1-ben írunk.
                    //     A range check megelőzi a pop-ot az ISA spec
                    //     szerinti trap sorrendnek (lásd TExecutor.cs:
                    //     index check BEFORE pop).
                    // en: Sub3 — SRAM write (STARG / STLOC) phase 0:
                    //     range check (same as read), then pop_en=1 and
                    //     latch the address — phase 1 performs the write.
                    //     Range check precedes pop per ISA spec (see
                    //     TExecutor.cs: index check BEFORE pop).
                    if (uc_addr_src == `ADDR_SRC_ARG &&
                        eff_idx >= {3'd0, r_arg_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_ARG;
                        r_state     <= ST_TRAP;
                    end else if (uc_addr_src == `ADDR_SRC_LOCAL &&
                                 eff_idx >= {3'd0, r_local_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_LOCAL;
                        r_state     <= ST_TRAP;
                    end else begin
                        r_mem_addr_latched <= addr_calc(uc_addr_src, eff_idx);
                        r_sc_pop_en        <= 1'b1;
                        r_mem_phase        <= 1'b1;
                    end
                end else if (uc_sram_wr && r_mem_phase == 1'b1) begin
                    // hu: Sub3 — SRAM írás phase 1: a Stack Cache 1-ciklus
                    //     regisztrált pop_data-ját az SRAM-ba írjuk.
                    //     Ezután uc_done flow + ST_FETCH.
                    // en: Sub3 — SRAM write phase 1: write the Stack Cache's
                    //     1-cycle registered pop_data to SRAM. Then uc_done
                    //     flow + ST_FETCH.
                    r_sram_addr  <= r_mem_addr_latched;
                    r_sram_wdata <= w_sc_pop_data;
                    r_sram_we    <= 1'b1;
                    r_mem_phase  <= 1'b0;
                    if (uc_pc_wr) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end else begin
                    // hu: Stack műveletek a vezérlőszó alapján
                    if (uc_stack_pop > 2'd0) begin
                        r_sc_pop_en <= 1'b1;
                    end
                    if (uc_stack_push) begin
                        r_sc_push_en <= 1'b1;
                        case (uc_push_src)
                            `PUSH_SRC_IMM: r_sc_push_data <= push_data_imm;
                            `PUSH_SRC_TOS: r_sc_push_data <= w_sc_tos;
                            default:       r_sc_push_data <= 32'd0;
                        endcase
                    end

                    // hu: RET (UC_HALT=1, UC_FRAME_POP=1, UC_PC_SRC=PC_SRC_RET)
                    //     A microcode 2-step: step 0 = pop return value
                    //     (cond_pop), step 1 = halt/frame_pop (UC_DONE=1).
                    //     Step 1 ciklusban a w_sc_pop_data tartalmazza a
                    //     step 0-ban pop-olt return value-t (Stack Cache
                    //     1-ciklus regisztrált pop_data).
                    //     Sub1-ben: csak root frame (call_depth==1) → halt.
                    //     Nem-root call_depth Sub2-re marad.
                    // en: RET — microcode is 2-step: step 0 pops return
                    //     value (cond_pop), step 1 halts (UC_DONE=1).
                    //     On step 1, w_sc_pop_data holds the value popped
                    //     on step 0 (Stack Cache's 1-cycle registered
                    //     pop_data). Sub1: only root frame (call_depth==1)
                    //     halts; non-root call_depth deferred to Sub2.
                    if (uc_done && uc_halt_en && uc_frame_pop) begin
                        if (r_call_depth == 10'd1) begin
                            o_halt  <= 1'b1;
                            // hu: A return_value a step 0-ban pop-olt érték,
                            //     ami most a w_sc_pop_data-n érvényes.
                            //     Ha az eval stack üres volt step 0-ban,
                            //     a Stack Cache trap-pet ad — itt nem.
                            o_return_value <= w_sc_pop_data;
                            r_state <= ST_HALT;
                        end else begin
                            // hu: Sub5 — non-root frame pop → ST_RET szekvencia.
                            //     A return value a step 0-ban pop-olt érték
                            //     (w_sc_pop_data); elmentjük r_ret_value-be.
                            //     Az SRAM read indítása itt: [FP+0] = ReturnPC.
                            // en: Sub5 — non-root frame pop → ST_RET sequence.
                            //     Return value latched from step 0 pop_data.
                            //     Initiate SRAM read of [FP+0] = ReturnPC.
                            r_ret_value     <= w_sc_pop_data;
                            r_callee_old_fp <= r_fp;
                            r_sram_addr     <= r_fp;
                            r_sram_re       <= 1'b1;
                            r_ret_sub       <= RET_REQ_RPC;
                            r_state         <= ST_RET;
                        end
                    end else if (uc_frame_push) begin
                        // hu: Sub5 — CALL → ST_CALL szekvencia.
                        //     A microcode 1-step (UC_DONE + UC_FRAME_PUSH +
                        //     UC_PC_WR + UC_PC_SRC=PC_SRC_CALL). A teljes
                        //     frame felépítést a top-level végzi több
                        //     ciklus alatt: header read QSPI-ról, validáció,
                        //     args reverse-pop a Stack Cache-ből, header
                        //     write az új frame-be, locals nullázás,
                        //     regiszterek és Stack Cache reset.
                        //     A return_pc = r_pc + r_length (5 byte: 1 op
                        //     + 4 byte RVA). Az új FP = caller r_sp (a
                        //     caller frame vége, ami egyben a callee frame
                        //     kezdete).
                        // en: Sub5 — CALL → ST_CALL sequence.
                        //     Microcode is 1-step (UC_DONE + UC_FRAME_PUSH +
                        //     UC_PC_WR + UC_PC_SRC=PC_SRC_CALL). The full
                        //     frame setup runs in the top-level FSM across
                        //     multiple cycles: header read from QSPI,
                        //     validation, args reverse-pop from Stack Cache,
                        //     header write into the new frame, locals zero,
                        //     register and Stack Cache reset.
                        //     return_pc = r_pc + r_length (5 byte). New FP =
                        //     caller r_sp (caller frame end = callee frame
                        //     start).
                        r_call_target_rva <= r_operand[23:0];
                        r_return_pc       <= r_pc + {21'd0, r_length};
                        r_new_fp          <= r_sp;
                        r_arg_pop_idx     <= 5'd0;
                        r_local_zero_idx  <= 5'd0;
                        r_call_sub        <= CALL_HDR_REQ;
                        r_state           <= ST_CALL;
                    end else if (uc_done) begin
                        // hu: Normal opcode befejezés — PC update + buffer
                        //     csúsztatás (warm-path optimalizáció). Branch/call
                        //     esetén full flush. A csúsztatás explicit `case
                        //     (r_length)`-szel — a generic `for` loop +
                        //     dynamic index Verilator regiszter-array-en
                        //     nem viselkedik megbízhatóan.
                        //     Sub4 — 1-operand branch (BRFALSE/BRTRUE):
                        //     a fall-through esetén (cond_en=1, branch
                        //     nem teljesül) pc_next-et felülírjuk pc+len-re.
                        // en: Normal opcode end — PC update + buffer slide-down
                        //     (warm-path opt). On branch/call we full-flush.
                        //     Sub4 — 1-operand branch: on fall-through, override
                        //     pc_next with pc+len (no taken).
                        if (uc_pc_wr) begin
                            if (uc_cond_en && (uc_stack_pop == 2'd1) &&
                                !branch_taken_1op) begin
                                // hu: BRFALSE_S/BRTRUE_S nem teljesült feltétel
                                //     → fall-through, NEM branch.
                                // en: BRFALSE_S/BRTRUE_S condition false →
                                //     fall-through, no branch.
                                r_pc          <= r_pc + {21'd0, r_length};
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= r_pc + {21'd0, r_length};
                                r_next_fetch_addr <= r_pc + {21'd0, r_length};
                            end else if (branch_target_invalid) begin
                                // hu: Sub4 hiánypótlás — BR_S / BRFALSE_S /
                                //     BRTRUE_S taken ágban negatív cél
                                //     → TRAP_INVALID_BRANCH a PC update
                                //     előtt. (A 2-op branchet külön kezeljük
                                //     a phase 1 ágban.)
                                // en: Sub4 hardening — BR_S / BRFALSE_S /
                                //     BRTRUE_S taken with negative target
                                //     → TRAP_INVALID_BRANCH before PC update.
                                //     (2-op branch is handled in phase 1.)
                                o_trap      <= 1'b1;
                                o_trap_code <= `TRAP_INVALID_BRANCH;
                                r_state     <= ST_TRAP;
                            end else if (uc_pc_src != `PC_SRC_NEXT) begin
                                r_pc <= pc_next;
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                // hu: Sub2.1 — branch/call full-flush:
                                //     a következő fetch pc_next-ről indul.
                                // en: Sub2.1 — branch/call full-flush:
                                //     next fetch starts from pc_next.
                                r_next_fetch_addr <= pc_next;
                            end else if (r_fetch_count >= {1'b0, r_length}) begin
                                r_pc <= pc_next;
                                // hu: Packed buffer slide: lefelé (byte 0 a
                                //     legalsó), `r_length * 8` bit jobbra
                                //     shift, felülre 0. Verilator
                                //     megbízhatóan kezeli.
                                //     A warm-path slide NEM állítja
                                //     r_next_fetch_addr-t — az APPEND
                                //     +4-es léptetése független a slide-tól.
                                // en: Packed buffer slide: down-shift by
                                //     r_length*8 bits (byte 0 is LSB), zero
                                //     fill upper. Verilator handles reliably.
                                //     The warm-path slide does NOT touch
                                //     r_next_fetch_addr — APPEND's +4
                                //     bump is independent of slide.
                                case (r_length)
                                    3'd1: r_fetch_buf <= {8'h00,
                                                          r_fetch_buf[63:8]};
                                    3'd2: r_fetch_buf <= {16'h0000,
                                                          r_fetch_buf[63:16]};
                                    3'd3: r_fetch_buf <= {24'h0,
                                                          r_fetch_buf[63:24]};
                                    3'd4: r_fetch_buf <= {32'h0,
                                                          r_fetch_buf[63:32]};
                                    3'd5: r_fetch_buf <= {40'h0,
                                                          r_fetch_buf[63:40]};
                                    default: ;
                                endcase
                                r_fetch_count <=
                                    r_fetch_count - {1'b0, r_length};
                                r_fetch_pc <= r_fetch_pc
                                              + {21'd0, r_length};
                            end else begin
                                // hu: Sub2.1 — slide-vesztett full-flush.
                                // en: Sub2.1 — slide-fallback full-flush.
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                r_next_fetch_addr <= pc_next;
                            end
                        end
                        r_step <= 4'd0;
                        r_state <= ST_FETCH;
                    end else begin
                        // hu: Multi-step opcode — folytatás
                        r_step <= r_step + 4'd1;
                    end
                end
            end

            // ====================================================
            // ST_MEM_WAIT — Sub3: 2-fázisú SRAM read wait
            //   phase 0: r_sram_rdata_latched még előző érték (NBA).
            //            Ekkor csak phase++.
            //   phase 1: r_sram_rdata_latched már friss → push, PC update,
            //            ST_FETCH.
            //   Verilog NBA: r_sram_re <= 1 cycle X-ben → X+1 ciklus elején
            //   `if (r_sram_re)` lefut → X+2 ciklus elején r_sram_rdata_
            //   latched friss. Ezért 2 ciklus (phase 0 + phase 1) kell.
            // en: ST_MEM_WAIT — Sub3: 2-phase SRAM read wait
            //   phase 0: r_sram_rdata_latched is still old (NBA timing).
            //   phase 1: r_sram_rdata_latched is fresh → push + uc_done.
            // ====================================================
            ST_MEM_WAIT: begin
                if (r_mem_phase == 1'b0) begin
                    r_mem_phase <= 1'b1;
                end else begin
                    r_mem_phase    <= 1'b0;
                    r_sc_push_en   <= 1'b1;
                    r_sc_push_data <= r_sram_rdata_latched;
                    if (uc_pc_wr) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end
            end

            // ====================================================
            // ST_CALL — Sub5 frame manager (CALL szekvencia)
            // hu: Több ciklus alatt felépíti az új callee frame-et az
            //     SRAM-ban. Sub-states (r_call_sub):
            //     0 HDR_REQ      → call_depth check + QSPI read indítása
            //                       a callee header címére
            //     1 HDR_WAIT     → várja a w_qspi_ready-t, magic+arg+local
            //                       latch-elése
            //     2 VALIDATE     → SRAM overflow check (r_sp + frame_size)
            //     3 ARG_POP_REQ  → pop_en=1 (vagy átmenet HDR_WR-be ha 0 arg)
            //     4 ARG_POP_WAIT → várja !w_sc_busy állapotot
            //     5 ARG_POP_WR   → SRAM write a frame [FP+12+i*4] címre
            //     6 HDR_WR_RPC   → [FP+0] = return_pc
            //     7 HDR_WR_PFP   → [FP+4] = prev_fp (régi r_fp)
            //     8 HDR_WR_AL    → [FP+8] = {0, local_count, arg_count}
            //     9 LOCAL_ZERO   → 0 írása minden local slotra
            //    10 FINALIZE     → regiszterek + sc_sp_load + fetch flush
            // en: Builds the new callee frame in SRAM across several cycles.
            // ====================================================
            ST_CALL: begin
                case (r_call_sub)
                    CALL_HDR_REQ: begin
                        // hu: Call depth check (max 512). Itt trap-elünk,
                        //     mielőtt a header read-et kérnénk.
                        // en: Call depth check (max 512). Trap before
                        //     issuing the header read request.
                        if (r_call_depth >= 10'd512) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_CALL_DEPTH_EXCEEDED;
                            r_state     <= ST_TRAP;
                        end else if (!w_qspi_busy && !r_qspi_inflight) begin
                            // hu: QSPI szabad → új request a header címére
                            //     (4 byte word: magic + arg + local + max).
                            // en: QSPI idle → request header word
                            //     (4 bytes: magic + arg + local + max).
                            r_qspi_addr     <= r_call_target_rva;
                            r_qspi_re       <= 1'b1;
                            r_qspi_inflight <= 1'b1;
                            r_call_sub      <= CALL_HDR_WAIT;
                        end
                    end

                    CALL_HDR_WAIT: begin
                        if (w_qspi_ready) begin
                            r_qspi_inflight <= 1'b0;
                            // hu: w_qspi_rdata layout (lásd a fetch
                            //     byte-swapot): [31:24] = byte at addr
                            //     (magic), [23:16] = arg_count, [15:8] =
                            //     local_count, [7:0] = max_stack.
                            // en: See fetch byte-swap: [31:24] = magic,
                            //     [23:16] = arg_count, [15:8] = local_count,
                            //     [7:0] = max_stack.
                            if (w_qspi_rdata[31:24] != 8'hFE) begin
                                o_trap      <= 1'b1;
                                o_trap_code <= `TRAP_INVALID_CALL_TARGET;
                                r_state     <= ST_TRAP;
                            end else begin
                                r_new_arg_count   <= w_qspi_rdata[20:16];
                                r_new_local_count <= w_qspi_rdata[12:8];
                                r_call_sub        <= CALL_VALIDATE;
                            end
                        end
                    end

                    CALL_VALIDATE: begin
                        // hu: SRAM overflow check: r_sp + frame_size > 16384
                        //     A 15-bit unsigned compare 14-bit r_sp + max
                        //     frame_size (140 byte) eseteit kezeli.
                        // en: SRAM overflow check: r_sp + frame_size > 16384.
                        if ({1'b0, r_sp} +
                            {1'b0, 14'd12} +
                            {8'd0, r_new_arg_count, 2'd0} +
                            {8'd0, r_new_local_count, 2'd0} > 15'h4000) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_SRAM_OVERFLOW;
                            r_state     <= ST_TRAP;
                        end else begin
                            r_call_sub <= CALL_ARG_POP_REQ;
                        end
                    end

                    CALL_ARG_POP_REQ: begin
                        // hu: Args reverse-pop: első pop = TOS = arg[N-1],
                        //     második = arg[N-2], stb. Ha minden arg pop-olva,
                        //     a header write fázisra megyünk.
                        // en: Args reverse-pop: first pop = TOS = arg[N-1],
                        //     second = arg[N-2], etc.
                        if (r_arg_pop_idx >= r_new_arg_count) begin
                            r_call_sub <= CALL_HDR_WR_RPC;
                        end else if (!w_sc_busy) begin
                            r_sc_pop_en <= 1'b1;
                            r_call_sub  <= CALL_ARG_POP_WAIT;
                        end
                    end

                    CALL_ARG_POP_WAIT: begin
                        // hu: Stack Cache pop_data 1-cycle regisztrált.
                        //     A spill miatt busy lehet — várjuk a !busy-t,
                        //     aztán biztonságosan írhatunk az SRAM-ba.
                        // en: Stack Cache registered pop_data; wait for
                        //     !busy (potential spill) before SRAM write.
                        if (!w_sc_busy) begin
                            r_call_sub <= CALL_ARG_POP_WR;
                        end
                    end

                    CALL_ARG_POP_WR: begin
                        // hu: SRAM write a frame megfelelő arg slot-jára.
                        //     Cím = FP_new + 12 + (N-1-pop_idx)*4
                        // en: SRAM write to the frame's arg slot.
                        r_sram_addr  <= r_new_fp + 14'd12 +
                                        {7'd0,
                                         (r_new_arg_count - 5'd1 - r_arg_pop_idx),
                                         2'd0};
                        r_sram_wdata <= w_sc_pop_data;
                        r_sram_we    <= 1'b1;
                        r_arg_pop_idx <= r_arg_pop_idx + 5'd1;
                        r_call_sub    <= CALL_ARG_POP_REQ;
                    end

                    CALL_HDR_WR_RPC: begin
                        r_sram_addr  <= r_new_fp;            // [FP+0]
                        r_sram_wdata <= {8'd0, r_return_pc};
                        r_sram_we    <= 1'b1;
                        r_call_sub   <= CALL_HDR_WR_PFP;
                    end

                    CALL_HDR_WR_PFP: begin
                        r_sram_addr  <= r_new_fp + 14'd4;    // [FP+4]
                        r_sram_wdata <= {18'd0, r_fp};
                        r_sram_we    <= 1'b1;
                        r_call_sub   <= CALL_HDR_WR_AL;
                    end

                    CALL_HDR_WR_AL: begin
                        r_sram_addr  <= r_new_fp + 14'd8;    // [FP+8]
                        r_sram_wdata <= {16'd0,
                                         3'd0, r_new_local_count,
                                         3'd0, r_new_arg_count};
                        r_sram_we    <= 1'b1;
                        if (r_new_local_count > 5'd0) begin
                            r_local_zero_idx <= 5'd0;
                            r_call_sub <= CALL_LOCAL_ZERO;
                        end else begin
                            r_call_sub <= CALL_FINALIZE;
                        end
                    end

                    CALL_LOCAL_ZERO: begin
                        // hu: Locals nullázása: [FP_new + 12 + arg*4 + i*4]
                        // en: Zero locals: [FP_new + 12 + arg*4 + i*4]
                        r_sram_addr  <= r_new_fp + 14'd12 +
                                        {7'd0, r_new_arg_count, 2'd0} +
                                        {7'd0, r_local_zero_idx, 2'd0};
                        r_sram_wdata <= 32'd0;
                        r_sram_we    <= 1'b1;
                        r_local_zero_idx <= r_local_zero_idx + 5'd1;
                        if (r_local_zero_idx + 5'd1 >= r_new_local_count) begin
                            r_call_sub <= CALL_FINALIZE;
                        end
                    end

                    CALL_FINALIZE: begin
                        // hu: Regiszterek frissítése a callee context-re,
                        //     fetch flush, Stack Cache reset üres eval-re.
                        // en: Update registers to callee context, fetch flush,
                        //     Stack Cache reset to empty eval.
                        r_fp          <= r_new_fp;
                        r_sp          <= r_new_fp + 14'd12 +
                                         {7'd0, r_new_arg_count, 2'd0} +
                                         {7'd0, r_new_local_count, 2'd0};
                        r_arg_count   <= r_new_arg_count;
                        r_local_count <= r_new_local_count;
                        r_call_depth  <= r_call_depth + 10'd1;
                        r_pc          <= r_call_target_rva + 24'd8;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_call_target_rva + 24'd8;
                        r_next_fetch_addr <= r_call_target_rva + 24'd8;
                        r_qspi_inflight <= 1'b0;
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= r_new_fp + 14'd12 +
                                        {7'd0, r_new_arg_count, 2'd0} +
                                        {7'd0, r_new_local_count, 2'd0};
                        r_state <= ST_FETCH;
                    end

                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // ST_RET — Sub5 frame manager (RET szekvencia)
            // hu: Sub-states (r_ret_sub):
            //     0 REQ_RPC    → SRAM read már lefutott (ST_EXECUTE indította
            //                    [FP+0] = ReturnPC). Csak átmenet.
            //     1 WAIT_RPC   → 2-cycle SRAM latency: várjuk a friss adatot.
            //     2 LATCH_RPC  → r_ret_return_pc latch + [FP+4] read indítás.
            //     3 WAIT_PFP   → 2-cycle latency.
            //     4 LATCH_PFP  → r_ret_prev_fp latch + [prev_fp+8] read.
            //     5 WAIT_AL    → 2-cycle latency.
            //     6 LATCH_AL   → caller arg/local count latch.
            //     7 FINALIZE   → regiszterek caller-re + Stack Cache reset
            //                    a caller eval bázisra.
            //     8 PUSH_RV    → return value push a Stack Cache-be →
            //                    ST_FETCH (caller folytatása).
            // en: Frame pop sequence: 3× SRAM read (return_pc, prev_fp,
            //     caller arg/local), then register/SP updates, push return
            //     value back to caller eval stack.
            // ====================================================
            ST_RET: begin
                case (r_ret_sub)
                    RET_REQ_RPC: begin
                        // hu: ST_EXECUTE már r_sram_re=1-et adott a [FP+0]-re.
                        //     A 2-cycle latency miatt 1 cycle várás itt.
                        // en: ST_EXECUTE already issued the read; here we
                        //     just bridge the 1st of 2 cycles of latency.
                        r_ret_sub <= RET_WAIT_RPC;
                    end

                    RET_WAIT_RPC: begin
                        r_ret_sub <= RET_LATCH_RPC;
                    end

                    RET_LATCH_RPC: begin
                        r_ret_return_pc <= r_sram_rdata_latched[23:0];
                        r_sram_addr <= r_callee_old_fp + 14'd4;  // [FP+4]
                        r_sram_re   <= 1'b1;
                        r_ret_sub   <= RET_WAIT_PFP;
                    end

                    RET_WAIT_PFP: begin
                        r_ret_sub <= RET_LATCH_PFP;
                    end

                    RET_LATCH_PFP: begin
                        r_ret_prev_fp <= r_sram_rdata_latched[13:0];
                        // hu: Indítsuk a [prev_fp + 8] olvasást azonnal,
                        //     a friss r_sram_rdata_latched-ből nyerjük a
                        //     prev_fp-t (a regiszter NBA miatt 1 cycle
                        //     múlva érvényes, de a kombinációs cím
                        //     számítás itt érvényes).
                        // en: Start [prev_fp + 8] read using the freshly
                        //     latched value (combinational use is OK).
                        r_sram_addr <= r_sram_rdata_latched[13:0] + 14'd8;
                        r_sram_re   <= 1'b1;
                        r_ret_sub   <= RET_WAIT_AL;
                    end

                    RET_WAIT_AL: begin
                        r_ret_sub <= RET_LATCH_AL;
                    end

                    RET_LATCH_AL: begin
                        // hu: byte 0 = arg_count, byte 1 = local_count
                        //     ([FP+8] formátum: {0, local_count, arg_count}).
                        // en: byte 0 = arg_count, byte 1 = local_count.
                        r_arg_count   <= r_sram_rdata_latched[4:0];
                        r_local_count <= r_sram_rdata_latched[12:8];
                        r_ret_sub     <= RET_FINALIZE;
                    end

                    RET_FINALIZE: begin
                        // hu: Regiszterek caller context-re. A r_arg_count
                        //     és r_local_count NBA-zott — a RET_FINALIZE
                        //     ciklusában már a friss caller értékek.
                        //     A callee SRAM (r_callee_old_fp .. r_sp-ig)
                        //     felszabadul.
                        // en: Registers reset to caller context. r_arg_count
                        //     and r_local_count are NBA-fresh by this cycle.
                        //     Callee SRAM region freed.
                        r_pc          <= r_ret_return_pc;
                        r_fp          <= r_ret_prev_fp;
                        r_sp          <= r_callee_old_fp;
                        r_call_depth  <= r_call_depth - 10'd1;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_ret_return_pc;
                        r_next_fetch_addr <= r_ret_return_pc;
                        r_qspi_inflight <= 1'b0;
                        // hu: Stack Cache reset a caller eval bázisra. A
                        //     return value push-ja külön ciklusban (RET_PUSH_RV),
                        //     mert a sp_load és push_en egyszerre nem.
                        // en: Stack Cache reset to caller eval base. Return
                        //     value push runs in a separate cycle because
                        //     sp_load and push_en don't combine.
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= r_ret_prev_fp + 14'd12 +
                                        {7'd0, r_arg_count, 2'd0} +
                                        {7'd0, r_local_count, 2'd0};
                        r_ret_sub <= RET_PUSH_RV;
                    end

                    RET_PUSH_RV: begin
                        // hu: A return value push a Stack Cache-be a
                        //     caller eval stack-jére, és ST_FETCH-re megyünk.
                        // en: Push return value to Stack Cache (caller eval
                        //     stack), transition to ST_FETCH.
                        r_sc_push_en   <= 1'b1;
                        r_sc_push_data <= r_ret_value;
                        r_state        <= ST_FETCH;
                    end

                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // ST_HALT — végállapot, latch
            // ====================================================
            ST_HALT: begin
                o_halt <= 1'b1;
            end

            // ====================================================
            // ST_TRAP — végállapot, o_trap 1-ciklus pulzus után 0
            // ====================================================
            ST_TRAP: begin
                o_trap <= 1'b0;
                // hu: o_trap_code latch-ben marad
            end

            default: begin
                r_state <= ST_RESET;
            end
            endcase
        end
    end

endmodule

`default_nettype wire
