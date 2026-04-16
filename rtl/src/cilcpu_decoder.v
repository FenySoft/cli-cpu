// hu: CLI-CPU CIL-T0 Dekóder — a TDecoder.cs Decode() metódusának bit-tökéletes
//     hardveres megvalósítása. Tiszta kombinációs logika (nincs órajel, nincs
//     flip-flop). Az utasítás az i_byte0..4 bemenetek és az i_bytes_available
//     (0..5) alapján dekódolódik egyetlen kombinációs passz alatt.
//     Ismeretlen opkód vagy truncated operandus esetén o_trap_invalid=1,
//     és az összes többi kimenet 0.
// en: CLI-CPU CIL-T0 Decoder — bit-perfect hardware implementation of the
//     TDecoder.cs Decode() method. Pure combinational logic (no clock, no
//     flip-flops). The instruction is decoded from i_byte0..4 inputs and
//     i_bytes_available (0..5) within a single combinational pass.
//     Unknown opcode or truncated operand yields o_trap_invalid=1,
//     all other outputs are driven to 0.

`include "cilcpu_defines.vh"

module cilcpu_decoder (
    input  wire [7:0]  i_byte0,
    input  wire [7:0]  i_byte1,
    input  wire [7:0]  i_byte2,
    input  wire [7:0]  i_byte3,
    input  wire [7:0]  i_byte4,
    input  wire [2:0]  i_bytes_available,  // 0..5 (korlátozott / capped at 5)
    output reg  [15:0] o_opcode,
    output reg  [2:0]  o_length,
    output reg  [31:0] o_operand,
    output reg         o_trap_invalid
);

    always @(*) begin
        // hu: Alapértelmezett: semmit sem állítunk be (latch-mentes alap).
        //     Trap esetén ezek az értékek maradnak (0).
        // en: Defaults: nothing set (latch-free base).
        //     These values remain in trap cases (all zero).
        o_opcode       = 16'd0;
        o_length       = 3'd0;
        o_operand      = 32'd0;
        o_trap_invalid = 1'b0;

        // hu: 0. eset: nincs elérhető byte → truncated trap
        // en: Case 0: no bytes available → truncated trap
        if (i_bytes_available == 3'd0) begin
            o_trap_invalid = 1'b1;

        // hu: 0xFE prefix → kétbyte-os prefix opkód (Ceq/Cgt/CgtUn/Clt/CltUn)
        // en: 0xFE prefix → two-byte prefixed opcode (Ceq/Cgt/CgtUn/Clt/CltUn)
        end else if (i_byte0 == `OP_PREFIX) begin
            if (i_bytes_available < 3'd2) begin
                // hu: Truncated FE prefix — a második byte hiányzik
                // en: Truncated FE prefix — second byte is missing
                o_trap_invalid = 1'b1;
            end else begin
                case (i_byte1)
                    `OP_FE_CEQ: begin
                        o_opcode = {8'hFE, `OP_FE_CEQ};
                        o_length = 3'd2;
                        o_operand = 32'd0;
                    end
                    `OP_FE_CGT: begin
                        o_opcode = {8'hFE, `OP_FE_CGT};
                        o_length = 3'd2;
                        o_operand = 32'd0;
                    end
                    `OP_FE_CGT_UN: begin
                        o_opcode = {8'hFE, `OP_FE_CGT_UN};
                        o_length = 3'd2;
                        o_operand = 32'd0;
                    end
                    `OP_FE_CLT: begin
                        o_opcode = {8'hFE, `OP_FE_CLT};
                        o_length = 3'd2;
                        o_operand = 32'd0;
                    end
                    `OP_FE_CLT_UN: begin
                        o_opcode = {8'hFE, `OP_FE_CLT_UN};
                        o_length = 3'd2;
                        o_operand = 32'd0;
                    end
                    default: begin
                        // hu: Ismeretlen FE second-byte → trap
                        // en: Unknown FE second-byte → trap
                        o_trap_invalid = 1'b1;
                    end
                endcase
            end

        end else begin
            // hu: Egybyte-os és multi-byte-os opkódok dekódolása
            // en: Single-byte and multi-byte opcode decoding
            case (i_byte0)

                // ── Egybyte-os opkódok (operandus nélkül) ──
                // ── Single-byte opcodes (no operand) ──

                `OP_NOP,
                `OP_LDARG_0, `OP_LDARG_1, `OP_LDARG_2, `OP_LDARG_3,
                `OP_LDLOC_0, `OP_LDLOC_1, `OP_LDLOC_2, `OP_LDLOC_3,
                `OP_STLOC_0, `OP_STLOC_1, `OP_STLOC_2, `OP_STLOC_3,
                `OP_LDNULL,
                `OP_LDC_I4_M1, `OP_LDC_I4_0, `OP_LDC_I4_1, `OP_LDC_I4_2,
                `OP_LDC_I4_3,  `OP_LDC_I4_4, `OP_LDC_I4_5, `OP_LDC_I4_6,
                `OP_LDC_I4_7,  `OP_LDC_I4_8,
                `OP_DUP, `OP_POP, `OP_RET,
                `OP_LDIND_I4, `OP_STIND_I4,
                `OP_ADD, `OP_SUB, `OP_MUL, `OP_DIV, `OP_REM,
                `OP_AND, `OP_OR, `OP_XOR,
                `OP_SHL, `OP_SHR, `OP_SHR_UN,
                `OP_NEG, `OP_NOT,
                `OP_BREAK: begin
                    o_opcode  = {8'h00, i_byte0};
                    o_length  = 3'd1;
                    o_operand = 32'd0;
                end

                // ── 2-byte: unsigned index operandus (zero-extend) ──
                // ── 2-byte: unsigned index operand (zero-extend) ──

                `OP_LDARG_S, `OP_STARG_S, `OP_LDLOC_S, `OP_STLOC_S: begin
                    if (i_bytes_available < 3'd2) begin
                        o_trap_invalid = 1'b1;
                    end else begin
                        o_opcode  = {8'h00, i_byte0};
                        o_length  = 3'd2;
                        o_operand = {24'b0, i_byte1};  // zero-extend
                    end
                end

                // ── 2-byte: signed 8-bit operandus (sign-extend to 32-bit) ──
                // ── 2-byte: signed 8-bit operand (sign-extend to 32-bit) ──

                `OP_LDC_I4_S,
                `OP_BR_S, `OP_BRFALSE_S, `OP_BRTRUE_S,
                `OP_BEQ_S, `OP_BGE_S, `OP_BGT_S, `OP_BLE_S, `OP_BLT_S,
                `OP_BNE_UN_S: begin
                    if (i_bytes_available < 3'd2) begin
                        o_trap_invalid = 1'b1;
                    end else begin
                        o_opcode  = {8'h00, i_byte0};
                        o_length  = 3'd2;
                        o_operand = {{24{i_byte1[7]}}, i_byte1};  // sign-extend
                    end
                end

                // ── 5-byte: ldc.i4 — 32-bit little-endian immediate ──
                // ── 5-byte: ldc.i4 — 32-bit little-endian immediate ──

                `OP_LDC_I4: begin
                    if (i_bytes_available < 3'd5) begin
                        o_trap_invalid = 1'b1;
                    end else begin
                        o_opcode  = {8'h00, `OP_LDC_I4};
                        o_length  = 3'd5;
                        o_operand = {i_byte4, i_byte3, i_byte2, i_byte1};  // LE 32-bit
                    end
                end

                // ── 5-byte: call <rva4> — 4-byte little-endian absolute target ──
                // ── 5-byte: call <rva4> — 4-byte little-endian absolute target ──

                `OP_CALL: begin
                    if (i_bytes_available < 3'd5) begin
                        o_trap_invalid = 1'b1;
                    end else begin
                        o_opcode  = {8'h00, `OP_CALL};
                        o_length  = 3'd5;
                        o_operand = {i_byte4, i_byte3, i_byte2, i_byte1};  // LE 32-bit
                    end
                end

                // ── Ismeretlen opkód → trap ──
                // ── Unknown opcode → trap ──

                default: begin
                    o_trap_invalid = 1'b1;
                end

            endcase
        end
    end

endmodule
