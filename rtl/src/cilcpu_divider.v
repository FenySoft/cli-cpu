// hu: CLI-CPU szekvenciális 32-bites előjeles osztó. A CIL-T0 DIV/REM
//     műveletek hardvere. A korábbi kombinációs osztó (cilcpu_alu.v
//     `s_a / s_b`) a Vivado-szintézisben 287 CARRY4 / ~86 ns kritikus
//     utat adott — 50 MHz-en nem zárt. Ez a modul 1 bit/ciklus restoring
//     algoritmussal 32 ciklus alatt számol, így a kritikus út rövid.
//     A hányados és a maradék egyszerre áll elő (egy osztás mindkettőt
//     megadja); a hívó DIV-nél a hányadost, REM-nél a maradékot veszi.
//     Előjel: az abszolútértékeken osztunk, majd korrigálunk —
//     C#/ECMA-335 szemantika: a hányados 0 felé csonkít, a maradék
//     előjele az osztandóé.
// en: CLI-CPU sequential 32-bit signed divider — hardware for the CIL-T0
//     DIV/REM operations. The former combinational divider (cilcpu_alu.v
//     `s_a / s_b`) produced a 287-CARRY4 / ~86 ns critical path in Vivado
//     synthesis and did not close at 50 MHz. This module uses a
//     1-bit/cycle restoring algorithm (32 cycles), keeping the critical
//     path short. Quotient and remainder are produced together (one
//     division yields both); the caller takes the quotient for DIV, the
//     remainder for REM. Sign handling: divide the magnitudes, then
//     correct — C#/ECMA-335 semantics: quotient truncates toward zero,
//     remainder sign equals the dividend sign.

module cilcpu_divider (
    input  wire        i_clk,
    input  wire        i_rst_n,         // hu: aktív alacsony reset

    // hu: Indítás — 1-ciklusos pulzus, az operandusok ekkor érvényesek.
    // en: Start — 1-cycle pulse; operands must be valid on this cycle.
    input  wire        i_start,
    input  wire [31:0] i_dividend,      // hu: osztandó (előjeles)
    input  wire [31:0] i_divisor,       // hu: osztó (előjeles)

    output reg         o_busy,          // hu: 1 amíg számol
    output reg         o_done,          // hu: 1-ciklusos pulzus, eredmény kész
    output reg  [31:0] o_quotient,      // hu: hányados (előjeles)
    output reg  [31:0] o_remainder,     // hu: maradék (előjeles)
    output reg         o_trap_div_zero, // hu: osztó == 0
    output reg         o_trap_overflow  // hu: INT_MIN / -1 (DIV-overflow)
);

    // hu: A 0 felé csonkító előjeles osztáshoz az abszolútértékeken
    //     dolgozunk. INT_MIN abszolútértéke 2^31 — 32-bit unsigned-ban
    //     elfér (0x8000_0000), a ~x+1 kétkomplemens-negálás erre is helyes.
    // en: Truncate-toward-zero signed division works on the magnitudes.
    //     |INT_MIN| = 2^31 fits in 32-bit unsigned (0x8000_0000); the
    //     ~x+1 two's-complement negation is correct for it too.
    wire        w_dividend_neg = i_dividend[31];
    wire        w_divisor_neg  = i_divisor[31];
    wire [31:0] w_dvd_abs = w_dividend_neg ? (~i_dividend + 32'd1) : i_dividend;
    wire [31:0] w_dvr_abs = w_divisor_neg  ? (~i_divisor  + 32'd1) : i_divisor;

    // hu: Speciális esetek (kombinációsan, az i_start ciklusában).
    // en: Special cases (combinational, evaluated on the i_start cycle).
    wire w_is_div_zero = (i_divisor == 32'd0);
    wire w_is_overflow = (i_dividend == 32'h8000_0000)
                         && (i_divisor == 32'hFFFF_FFFF);

    // ============================================================
    // hu: Állapotok / en: States
    // ============================================================
    localparam ST_IDLE   = 2'd0;
    localparam ST_CALC   = 2'd1;
    localparam ST_FINISH = 2'd2;

    reg [1:0]  r_state;

    // hu: Restoring osztás munka-regiszterei.
    // en: Restoring division working registers.
    reg [32:0] r_rem;        // hu: maradék-akkumulátor (33-bit a shift miatt)
    reg [31:0] r_quot;       // hu: épülő hányados
    reg [31:0] r_dvd;        // hu: fogyó osztandó (MSB-től)
    reg [31:0] r_dvr_abs;    // hu: osztó abszolútértéke (latch-elt)
    reg [5:0]  r_count;      // hu: hátralévő iterációk (32..0)
    reg        r_dividend_neg;
    reg        r_divisor_neg;
    reg        r_special_dz;
    reg        r_special_ovf;

    // hu: Egy restoring lépés kombinációs része: a maradékot balra
    //     toljuk és bevisszük az osztandó következő (MSB) bitjét, majd
    //     kivonjuk az osztót. Ha nincs alulcsordulás (a bit 32 = 0), az
    //     osztó belefért → hányados-bit 1, a maradék a különbség.
    // en: Combinational part of one restoring step: shift the remainder
    //     left, bring in the next (MSB) dividend bit, subtract the
    //     divisor. No borrow (bit 32 == 0) → divisor fit → quotient bit 1.
    wire [32:0] w_rem_shl = {r_rem[31:0], r_dvd[31]};
    wire [32:0] w_rem_sub = w_rem_shl - {1'b0, r_dvr_abs};
    wire        w_q_bit   = ~w_rem_sub[32];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state         <= ST_IDLE;
            o_busy          <= 1'b0;
            o_done          <= 1'b0;
            o_quotient      <= 32'd0;
            o_remainder     <= 32'd0;
            o_trap_div_zero <= 1'b0;
            o_trap_overflow <= 1'b0;
            r_rem           <= 33'd0;
            r_quot          <= 32'd0;
            r_dvd           <= 32'd0;
            r_dvr_abs       <= 32'd0;
            r_count         <= 6'd0;
            r_dividend_neg  <= 1'b0;
            r_divisor_neg   <= 1'b0;
            r_special_dz    <= 1'b0;
            r_special_ovf   <= 1'b0;
        end else begin
            o_done <= 1'b0;   // hu: alapból 0; ST_FINISH 1 ciklusra emeli

            case (r_state)

                // ----------------------------------------------------
                ST_IDLE: begin
                    o_busy <= 1'b0;
                    if (i_start) begin
                        o_busy          <= 1'b1;
                        r_dividend_neg  <= w_dividend_neg;
                        r_divisor_neg   <= w_divisor_neg;
                        r_dvr_abs       <= w_dvr_abs;
                        r_dvd           <= w_dvd_abs;
                        r_rem           <= 33'd0;
                        r_quot          <= 32'd0;
                        r_count         <= 6'd32;
                        r_special_dz    <= w_is_div_zero;
                        r_special_ovf   <= w_is_overflow;
                        // hu: div-by-zero és INT_MIN/-1 → nincs iteráció.
                        // en: div-by-zero and INT_MIN/-1 → skip iteration.
                        if (w_is_div_zero || w_is_overflow)
                            r_state <= ST_FINISH;
                        else
                            r_state <= ST_CALC;
                    end
                end

                // ----------------------------------------------------
                // hu: Egy restoring lépés ciklusonként, 32-szer.
                // en: One restoring step per cycle, 32 times.
                ST_CALC: begin
                    o_busy <= 1'b1;
                    r_rem  <= w_q_bit ? w_rem_sub : w_rem_shl;
                    r_quot <= {r_quot[30:0], w_q_bit};
                    r_dvd  <= {r_dvd[30:0], 1'b0};
                    r_count <= r_count - 6'd1;

                    if (r_count == 6'd1)
                        r_state <= ST_FINISH;
                end

                // ----------------------------------------------------
                // hu: Előjel-korrekció + kimenet. o_done 1 ciklusra.
                // en: Sign correction + output. o_done pulses for 1 cycle.
                ST_FINISH: begin
                    o_busy          <= 1'b0;
                    o_done          <= 1'b1;
                    o_trap_div_zero <= r_special_dz;
                    o_trap_overflow <= r_special_ovf;

                    if (r_special_dz) begin
                        o_quotient  <= 32'd0;
                        o_remainder <= 32'd0;
                    end else if (r_special_ovf) begin
                        // hu: INT_MIN/-1: a hányados nem fér el int32-ben
                        //     (DIV-trap). A maradék 0 — REM-nél ez a
                        //     helyes eredmény (INT_MIN % -1 = 0).
                        // en: INT_MIN/-1: quotient overflows int32 (DIV
                        //     traps). Remainder is 0 — the correct REM
                        //     result (INT_MIN % -1 = 0).
                        o_quotient  <= 32'h8000_0000;
                        o_remainder <= 32'd0;
                    end else begin
                        // hu: hányados negatív, ha az előjelek eltérnek;
                        //     a maradék előjele az osztandóé.
                        // en: quotient negative when signs differ;
                        //     remainder sign equals the dividend sign.
                        o_quotient  <= (r_dividend_neg ^ r_divisor_neg)
                                       ? (~r_quot + 32'd1) : r_quot;
                        o_remainder <= r_dividend_neg
                                       ? (~r_rem[31:0] + 32'd1) : r_rem[31:0];
                    end

                    r_state <= ST_IDLE;
                end

                default: r_state <= ST_IDLE;

            endcase
        end
    end

endmodule
