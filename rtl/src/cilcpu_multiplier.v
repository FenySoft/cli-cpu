// hu: CLI-CPU szekvenciális 32-bites szorzó. A CIL-T0 MUL művelet hardvere.
//     A korábbi kombinációs szorzó (cilcpu_alu.v `i_op_a * i_op_b`) egy teljes
//     32×32 párhuzamos szorzót inferált — a datapath legnagyobb egyetlen
//     ALU-eleme. Ez a modul shift-add algoritmussal, korai kilépéssel számol
//     (legfeljebb 32 ciklus, kis operandusoknál jóval kevesebb), így a kombi-
//     nációs szorzó nagy területe megspórolható. Ez egyben az ISA spec-et is
//     követi (`docs/ISA-CIL-T0-hu.md`: „mul — iteratív shift-add").
//     Az eredmény az alsó 32 bit (wrapping, unchecked) — előjel-agnosztikus:
//     a kétkomplemens szorzat alsó 32 bitje azonos előjeles és előjel nélküli
//     értelmezésben, ezért nincs külön előjel-korrekció (a divider-rel
//     ellentétben).
// en: CLI-CPU sequential 32-bit multiplier — hardware for the CIL-T0 MUL
//     operation. The former combinational multiplier (cilcpu_alu.v
//     `i_op_a * i_op_b`) inferred a full 32×32 parallel multiplier — the
//     single largest ALU element in the datapath. This module uses a
//     shift-add algorithm with early exit (at most 32 cycles, far fewer for
//     small operands), saving the large area of the combinational multiplier.
//     It also aligns with the ISA spec ("mul — iterative shift-add").
//     The result is the lower 32 bits (wrapping, unchecked) — sign-agnostic:
//     the lower 32 bits of a two's-complement product are identical under
//     signed and unsigned interpretation, so no sign correction is needed
//     (unlike the divider).

module cilcpu_multiplier (
    input  wire        i_clk,
    input  wire        i_rst_n,         // hu: aktív alacsony reset

    // hu: Indítás — 1-ciklusos pulzus, az operandusok ekkor érvényesek.
    // en: Start — 1-cycle pulse; operands must be valid on this cycle.
    input  wire        i_start,
    input  wire [31:0] i_op_a,          // hu: multiplikandus (TOS-1)
    input  wire [31:0] i_op_b,          // hu: multiplikátor (TOS)

    output reg         o_busy,          // hu: 1 amíg számol
    output reg         o_done,          // hu: 1-ciklusos pulzus, eredmény kész
    output reg  [31:0] o_product        // hu: szorzat alsó 32 bit (wrapping)
);

    // ============================================================
    // hu: Állapotok / en: States
    // ============================================================
    localparam ST_IDLE   = 2'd0;
    localparam ST_CALC   = 2'd1;
    localparam ST_FINISH = 2'd2;

    reg [1:0]  r_state;

    // hu: Shift-add munka-regiszterek.
    //     r_acc    : akkumulátor (alsó 32 bit, wrapping).
    //     r_mcand  : multiplikandus, ciklusonként balra tolódik (32-bit wrap).
    //     r_mplier : multiplikátor, ciklusonként jobbra tolódik; a bit0 dönti
    //                el, hogy az aktuális (eltolt) multiplikandust hozzáadjuk-e.
    // en: Shift-add working registers.
    //     r_acc    : accumulator (lower 32 bits, wrapping).
    //     r_mcand  : multiplicand, shifted left each cycle (32-bit wrap).
    //     r_mplier : multiplier, shifted right each cycle; bit0 selects
    //                whether the current (shifted) multiplicand is added.
    reg [31:0] r_acc;
    reg [31:0] r_mcand;
    reg [31:0] r_mplier;

    // hu: Egy shift-add lépés kombinációs része. A korai kilépés a soron
    //     következő multiplikátor 0-ságát figyeli — ha a maradék minden bitje
    //     0, nincs több hozzájárulás (az aktuális bit add-ja már w_acc_next).
    // en: Combinational part of one shift-add step. Early exit watches the
    //     next multiplier for zero — if all remaining bits are 0 there is no
    //     further contribution (the current bit's add is already in w_acc_next).
    wire [31:0] w_acc_next    = r_mplier[0] ? (r_acc + r_mcand) : r_acc;
    wire [31:0] w_mplier_next = {1'b0, r_mplier[31:1]};

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state   <= ST_IDLE;
            o_busy    <= 1'b0;
            o_done    <= 1'b0;
            o_product <= 32'd0;
            r_acc     <= 32'd0;
            r_mcand   <= 32'd0;
            r_mplier  <= 32'd0;
        end else begin
            o_done <= 1'b0;   // hu: alapból 0; ST_FINISH 1 ciklusra emeli

            case (r_state)

                // ----------------------------------------------------
                ST_IDLE: begin
                    o_busy <= 1'b0;
                    if (i_start) begin
                        o_busy   <= 1'b1;
                        r_acc    <= 32'd0;
                        r_mcand  <= i_op_a;
                        r_mplier <= i_op_b;
                        // hu: ha a multiplikátor már 0, a szorzat 0 → FINISH
                        //     (nincs iteráció).
                        // en: if the multiplier is already 0, the product is 0
                        //     → FINISH (skip iteration).
                        if (i_op_b == 32'd0)
                            r_state <= ST_FINISH;
                        else
                            r_state <= ST_CALC;
                    end
                end

                // ----------------------------------------------------
                // hu: Egy shift-add lépés ciklusonként, korai kilépéssel.
                // en: One shift-add step per cycle, with early exit.
                ST_CALC: begin
                    o_busy   <= 1'b1;
                    r_acc    <= w_acc_next;
                    r_mcand  <= {r_mcand[30:0], 1'b0};
                    r_mplier <= w_mplier_next;

                    if (w_mplier_next == 32'd0)
                        r_state <= ST_FINISH;
                end

                // ----------------------------------------------------
                // hu: Kimenet. o_done 1 ciklusra. Nincs trap (a MUL wrapping,
                //     unchecked — sem div-by-zero, sem overflow nem értelmezett).
                // en: Output. o_done pulses for 1 cycle. No trap (MUL is
                //     wrapping/unchecked — neither div-by-zero nor overflow
                //     applies).
                ST_FINISH: begin
                    o_busy    <= 1'b0;
                    o_done    <= 1'b1;
                    o_product <= r_acc;
                    r_state   <= ST_IDLE;
                end

                default: r_state <= ST_IDLE;

            endcase
        end
    end

endmodule
