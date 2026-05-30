// hu: CLI-CPU 32-bit ALU — a CIL-T0 aritmetikai, logikai és összehasonlító
//     műveletek hardveres megvalósítása. Tiszta kombinációs logika (nincs
//     órajel), a TExecutor.cs megfelelő switch ágainak pontos másolata.
// en: CLI-CPU 32-bit ALU — hardware implementation of CIL-T0 arithmetic,
//     logical and comparison operations. Pure combinational logic (no clock),
//     an exact copy of the corresponding switch branches in TExecutor.cs.

`include "cilcpu_defines.vh"

module cilcpu_alu (
    input  wire [31:0] i_op_a,       // TOS-1 (vagy egyetlen operandus neg/not-hoz)
    input  wire [31:0] i_op_b,       // TOS
    input  wire [4:0]  i_alu_op,     // ALU művelet kód (ALU_ADD, ALU_SUB, stb.)
    output reg  [31:0] o_result      // Eredmény
);

    // hu: Signed interpretáció a signed összehasonlításokhoz és osztáshoz.
    // en: Signed interpretation for signed comparisons and division.
    wire signed [31:0] s_a = $signed(i_op_a);
    wire signed [31:0] s_b = $signed(i_op_b);

    always @(*) begin
        o_result = 32'd0;

        case (i_alu_op)

            // ── Aritmetika (wrapping, unchecked) ──

            `ALU_ADD: o_result = i_op_a + i_op_b;

            `ALU_SUB: o_result = i_op_a - i_op_b;

            // hu: ALU_MUL: a szekvenciális `cilcpu_multiplier.v` kezeli
            //     (F2.6-prep — a kombinációs `i_op_a * i_op_b` egy teljes
            //     32×32 párhuzamos szorzót inferált, a datapath legnagyobb
            //     ALU-eleme). A core a MUL opkódot ST_MUL_WAIT-en át routolja
            //     a multiplier-re; az ALU erre nem aktív, o_result a default
            //     0 marad (a core a multiplier o_product kimenetét használja).
            // en: ALU_MUL: handled by the sequential `cilcpu_multiplier.v`
            //     (F2.6-prep — the combinational `i_op_a * i_op_b` inferred a
            //     full 32×32 parallel multiplier, the largest ALU element).
            //     The core routes the MUL opcode via ST_MUL_WAIT to the
            //     multiplier; the ALU does not process it, o_result stays at
            //     the default 0 (the core uses the multiplier's o_product).

            // hu: ALU_DIV / ALU_REM: a szekvenciális `cilcpu_divider.v`
            //     kezeli (F2.7 Sub5 timing-fix — a kombinációs osztó 86 ns
            //     kritikus utat adott, 50 MHz-en nem zárt). A core a DIV/REM
            //     opkódot ST_DIV_WAIT-en át routolja a divider-re; az ALU
            //     ezekre nem aktív, o_result a default 0 marad (a core a
            //     divider o_quotient / o_remainder kimenetét használja).
            //     A trap-detektálás (div_zero, INT_MIN/-1 overflow) is a
            //     divider-ben van.
            // en: ALU_DIV / ALU_REM: handled by the sequential
            //     `cilcpu_divider.v` (F2.7 Sub5 timing fix — the
            //     combinational divider produced an 86 ns critical path and
            //     could not close at 50 MHz). The core routes DIV/REM
            //     opcodes via ST_DIV_WAIT to the divider; the ALU does not
            //     process them, and o_result stays at the default 0 (the
            //     core uses the divider's o_quotient / o_remainder outputs).
            //     Trap detection (div_zero, INT_MIN/-1 overflow) is also
            //     in the divider.

            // ── Bitwise logika ──

            `ALU_AND: o_result = i_op_a & i_op_b;

            `ALU_OR:  o_result = i_op_a | i_op_b;

            `ALU_XOR: o_result = i_op_a ^ i_op_b;

            `ALU_SHL: o_result = i_op_a << (i_op_b[4:0]);  // shift 0..31

            `ALU_SHR: o_result = $signed(s_a >>> (i_op_b[4:0]));  // arithmetic shift right

            `ALU_SHR_UN: o_result = i_op_a >> (i_op_b[4:0]);  // logical shift right

            // ── Unáris ──

            `ALU_NEG: o_result = -i_op_a;  // = 0 - i_op_a (wrapping)

            `ALU_NOT: o_result = ~i_op_a;  // bitwise NOT

            // ── Összehasonlítás (eredmény: 1 vagy 0) ──

            `ALU_CEQ: o_result = (i_op_a == i_op_b) ? 32'd1 : 32'd0;

            `ALU_CGT: o_result = (s_a > s_b) ? 32'd1 : 32'd0;

            `ALU_CGT_UN: o_result = (i_op_a > i_op_b) ? 32'd1 : 32'd0;

            `ALU_CLT: o_result = (s_a < s_b) ? 32'd1 : 32'd0;

            `ALU_CLT_UN: o_result = (i_op_a < i_op_b) ? 32'd1 : 32'd0;

            default: o_result = 32'd0;

        endcase
    end

endmodule
