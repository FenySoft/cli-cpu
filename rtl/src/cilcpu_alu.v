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
    output reg  [31:0] o_result,     // Eredmény
    output reg         o_trap_div_zero,  // DIV/REM: osztó == 0
    output reg         o_trap_overflow   // DIV: INT_MIN / -1
);

    // hu: Signed interpretáció a signed összehasonlításokhoz és osztáshoz.
    // en: Signed interpretation for signed comparisons and division.
    wire signed [31:0] s_a = $signed(i_op_a);
    wire signed [31:0] s_b = $signed(i_op_b);

    always @(*) begin
        o_result         = 32'd0;
        o_trap_div_zero  = 1'b0;
        o_trap_overflow  = 1'b0;

        case (i_alu_op)

            // ── Aritmetika (wrapping, unchecked) ──

            `ALU_ADD: o_result = i_op_a + i_op_b;

            `ALU_SUB: o_result = i_op_a - i_op_b;

            `ALU_MUL: o_result = i_op_a * i_op_b;  // alsó 32 bit (wrapping)

            `ALU_DIV: begin
                if (i_op_b == 32'd0) begin
                    o_trap_div_zero = 1'b1;
                end else if (i_op_a == 32'h8000_0000 && i_op_b == 32'hFFFF_FFFF) begin
                    // hu: INT_MIN / -1 = overflow (az eredmény nem fér el int32-ben)
                    // en: INT_MIN / -1 = overflow (result doesn't fit in int32)
                    o_trap_overflow = 1'b1;
                end else begin
                    o_result = $signed(s_a / s_b);
                end
            end

            `ALU_REM: begin
                if (i_op_b == 32'd0) begin
                    o_trap_div_zero = 1'b1;
                end else begin
                    // hu: INT_MIN % -1 = 0 (NEM overflow, a spec szerint)
                    // en: INT_MIN % -1 = 0 (NOT overflow, per spec)
                    o_result = $signed(s_a % s_b);
                end
            end

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
