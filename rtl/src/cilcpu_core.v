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
    localparam [3:0] ST_HALT     = 4'd8;
    localparam [3:0] ST_TRAP     = 4'd9;

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
    wire        uc_pc_wr      = w_uc_ctrl[`UC_PC_WR];
    wire [1:0]  uc_pc_src     = w_uc_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO];
    wire        uc_frame_pop  = w_uc_ctrl[`UC_FRAME_POP];
    wire        uc_halt_en    = w_uc_ctrl[`UC_HALT];
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

    // hu: A Stack Cache SRAM master portja Sub1-ben még NEM csatlakozik
    //     a belső SRAM-ra — a cache nem tölti meg, a programok < 4 elem
    //     mélyek. Sub3-ban dedikált bus mux köti össze.
    // en: The Stack Cache SRAM master port is NOT connected to the
    //     internal SRAM in Sub1 — the cache won't overflow on <4 element
    //     programs. A dedicated bus mux wires it up in Sub3.
    wire [13:0] w_sc_sram_addr;
    wire [31:0] w_sc_sram_wdata;
    wire        w_sc_sram_we;
    wire        w_sc_sram_re;

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
        .sram_rdata       (32'd0),
        .sram_we          (w_sc_sram_we),
        .sram_re          (w_sc_sram_re),
        .sram_ready       (1'b1)
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
    // en: PC update mux
    // ============================================================
    reg [23:0] pc_next;

    always @(*) begin
        case (uc_pc_src)
            `PC_SRC_NEXT:   pc_next = r_pc + {21'd0, r_length};
            `PC_SRC_RET:    pc_next = r_sram[r_fp[13:2]][23:0];
            default:        pc_next = r_pc;  // PC_SRC_BRANCH, PC_SRC_CALL: Sub2+
        endcase
    end

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

            // hu: SRAM olvasás (1-ciklus latencia regisztrálva)
            if (r_sram_re) begin
                r_sram_rdata_latched <= r_sram[r_sram_addr[13:2]];
            end

            // hu: SRAM írás
            if (r_sram_we) begin
                r_sram[r_sram_addr[13:2]] <= r_sram_wdata;
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
                    // hu: 4-byte append a packed buffer-be. cnt=0 → byte
                    //     0..3, cnt=4 → byte 4..7. Az r_fetch_count ÚJ
                    //     értékét explicit konstanssal írjuk (4 vagy 8),
                    //     nem self-referenciával — Verilator NBA self-ref
                    //     egy bug-ot okozott.
                    // en: 4-byte append to packed buffer. cnt=0 → byte
                    //     0..3, cnt=4 → byte 4..7. Write r_fetch_count's
                    //     new value via an explicit constant (4 or 8),
                    //     not self-reference — Verilator NBA self-ref
                    //     was causing a bug.
                    case (r_fetch_count)
                        4'd0: begin
                            r_fetch_buf[31:0] <= {
                                w_qspi_rdata[7:0],
                                w_qspi_rdata[15:8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                            r_fetch_count <= 4'd4;
                        end
                        4'd4: begin
                            r_fetch_buf[63:32] <= {
                                w_qspi_rdata[7:0],
                                w_qspi_rdata[15:8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                            r_fetch_count <= 4'd8;
                        end
                        default: ;
                    endcase
                end else if (!w_qspi_busy && !r_qspi_re) begin
                    // hu: Új fetch indítása (csak ha nincs ready és nincs
                    //     folyamatban lévő tranzakció).
                    r_qspi_addr <= 24'h00_0000
                                   + r_pc
                                   + {20'd0, r_fetch_count};
                    r_qspi_re   <= 1'b1;
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
                            end
                            r_step  <= 4'd0;
                            r_state <= ST_FETCH;
                        end
                    end
                end else if (uc_alu_en && r_alu_phase == 2'd1) begin
                    // hu: ALU phase 1 (binary) — replace_top a latch-elt
                    //     eredménnyel, uc_done flow.
                    r_sc_replace_top_en   <= 1'b1;
                    r_sc_replace_top_data <= r_alu_result_latched;
                    r_alu_phase           <= 2'd0;
                    if (uc_pc_wr) begin
                        r_pc <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
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
                            // hu: Sub2+: frame pop, PC=ReturnPC, call_depth--
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_INVALID_OPCODE;
                            r_state     <= ST_TRAP;
                        end
                    end else if (uc_done) begin
                        // hu: Normal opcode befejezés — PC update + buffer
                        //     csúsztatás (warm-path optimalizáció). Branch/call
                        //     esetén full flush. A csúsztatás explicit `case
                        //     (r_length)`-szel — a generic `for` loop +
                        //     dynamic index Verilator regiszter-array-en
                        //     nem viselkedik megbízhatóan.
                        // en: Normal opcode end — PC update + buffer slide-down
                        //     (warm-path opt). On branch/call we full-flush.
                        //     Slide is explicit `case (r_length)` — the
                        //     generic `for` loop with dynamic index does
                        //     not behave reliably on Verilator reg arrays.
                        if (uc_pc_wr) begin
                            r_pc <= pc_next;
                            if (uc_pc_src != `PC_SRC_NEXT) begin
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                            end else if (r_fetch_count >= {1'b0, r_length}) begin
                                // hu: Packed buffer slide: lefelé (byte 0 a
                                //     legalsó), `r_length * 8` bit jobbra
                                //     shift, felülre 0. Verilator
                                //     megbízhatóan kezeli.
                                // en: Packed buffer slide: down-shift by
                                //     r_length*8 bits (byte 0 is LSB), zero
                                //     fill upper. Verilator handles reliably.
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
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
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
