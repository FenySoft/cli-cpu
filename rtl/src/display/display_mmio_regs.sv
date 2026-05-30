// Display MMIO Register File
// MicroPhase A7-Lite — CFPU display alrendszer
//
// Cím tartomány: 0xF001_0000 .. 0xF001_003F (64 byte, 16 × 32-bit regiszter)
//
// Mód-váltás protokoll (CPU oldalról):
//   1. CTRL.blank = 1         → kép feketítés
//   2. MODE_PRESET írás       → automatikus timing betöltés (opcionális)
//      VAGY egyedi H_*/V_* regiszterek írása
//   3. CTRL.mode_sel frissítés (pixel clock kiválasztás)
//   4. CTRL.blank = 0         → megjelenítés visszaállítás
//
// Előre definiált módok (MODE_PRESET):
//   0 = 640×480  @ 60 Hz  — pixel clock: 25 MHz   (BUFGMUX select = 0)
//   1 = 1280×720 @ 60 Hz  — pixel clock: 74.25 MHz (BUFGMUX select = 1)
//   2 = 1920×1080@ 30 Hz  — pixel clock: 74.25 MHz (BUFGMUX select = 1)

`default_nettype none
`timescale 1ns / 1ps

module display_mmio_regs (
    input  wire logic        clk,              // ui_clk vagy clk_pix (szinkron írás)
    input  wire logic        rst,

    // CPU MMIO write/read interfész (word-cím, [7:2] = offset/4)
    input  wire logic        wr_en,
    input  wire logic  [3:0] wr_addr,          // 0..15, = byte_offset[5:2]
    input  wire logic [31:0] wr_data,
    input  wire logic  [3:0] rd_addr,
    output      logic [31:0] rd_data,

    // Státusz bemenetek (read-only regiszterbe tükrözve)
    input  wire logic        pll_locked,
    input  wire logic        calib_done,

    // Timing kimenet → display_timing_dyn
    output      logic [11:0] o_h_res,
    output      logic [11:0] o_h_fp,
    output      logic [11:0] o_h_sync,
    output      logic [11:0] o_h_bp,
    output      logic [10:0] o_v_res,
    output      logic [10:0] o_v_fp,
    output      logic [10:0] o_v_sync,
    output      logic [10:0] o_v_bp,
    output      logic        o_h_pol,          // 1 = pozitív szinkron
    output      logic        o_v_pol,

    // Vezérlő kimenetek → top_hdmi
    output      logic        o_blank,          // 1 = kép feketítés + display hold
    output      logic        o_mode_sel        // BUFGMUX: 0=25MHz, 1=74.25MHz
);

    // =========================================================================
    // Regiszter térkép
    // =========================================================================
    // Offset  Név          Leírás
    // 0x00    CTRL         [0]=blank, [1]=mode_sel
    // 0x04    MODE_PRESET  [1:0] íráskor preset betöltés (öntörlő)
    // 0x08    H_RES        [11:0] vízszintes felbontás
    // 0x0C    H_FP         [11:0] vízszintes front porch
    // 0x10    H_SYNC       [11:0] vízszintes sync szélesség
    // 0x14    H_BP         [11:0] vízszintes back porch
    // 0x18    V_RES        [10:0] függőleges felbontás
    // 0x1C    V_FP         [10:0] függőleges front porch
    // 0x20    V_SYNC       [10:0] függőleges sync szélesség
    // 0x24    V_BP         [10:0] függőleges back porch
    // 0x28    POLARITY     [0]=h_pol, [1]=v_pol
    // 0x2C    STATUS       [0]=pll_locked, [1]=calib_done  (csak olvasható)
    // 0x30..0x3C  (fenntartott)

    localparam [3:0]
        A_CTRL     = 4'd0,
        A_PRESET   = 4'd1,
        A_H_RES    = 4'd2,
        A_H_FP     = 4'd3,
        A_H_SYNC   = 4'd4,
        A_H_BP     = 4'd5,
        A_V_RES    = 4'd6,
        A_V_FP     = 4'd7,
        A_V_SYNC   = 4'd8,
        A_V_BP     = 4'd9,
        A_POLARITY = 4'd10,
        A_STATUS   = 4'd11;

    // =========================================================================
    // Regiszterek
    // =========================================================================
    logic        r_blank, r_mode_sel;
    logic [11:0] r_h_res, r_h_fp, r_h_sync, r_h_bp;
    logic [10:0] r_v_res, r_v_fp, r_v_sync, r_v_bp;
    logic        r_h_pol, r_v_pol;

    // =========================================================================
    // Preset értékek (konstans táblázat)
    // =========================================================================
    function automatic void load_preset(
        input logic [1:0] mode,
        output logic [11:0] h_res, h_fp, h_sync, h_bp,
        output logic [10:0] v_res, v_fp, v_sync, v_bp,
        output logic        h_pol, v_pol,
        output logic        mode_sel
    );
        case (mode)
            2'd0: begin  // 640×480 @ 60 Hz — pixel clock 25.175 MHz
                h_res = 12'd640;  h_fp = 12'd16;  h_sync = 12'd96;  h_bp = 12'd48;
                v_res = 11'd480;  v_fp = 11'd10;  v_sync = 11'd2;   v_bp = 11'd33;
                h_pol = 1'b0;  v_pol = 1'b0;  mode_sel = 1'b0;
            end
            2'd1: begin  // 1280×720 @ 60 Hz — pixel clock 74.25 MHz
                h_res = 12'd1280; h_fp = 12'd110; h_sync = 12'd40;  h_bp = 12'd220;
                v_res = 11'd720;  v_fp = 11'd5;   v_sync = 11'd5;   v_bp = 11'd20;
                h_pol = 1'b1;  v_pol = 1'b1;  mode_sel = 1'b1;
            end
            default: begin  // 1920×1080 @ 30 Hz — pixel clock 74.25 MHz
                h_res = 12'd1920; h_fp = 12'd88;  h_sync = 12'd44;  h_bp = 12'd148;
                v_res = 11'd1080; v_fp = 11'd4;   v_sync = 11'd5;   v_bp = 11'd36;
                h_pol = 1'b1;  v_pol = 1'b1;  mode_sel = 1'b1;
            end
        endcase
    endfunction

    // =========================================================================
    // Írási logika
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset: 1080p@30Hz preset betöltés
            r_blank    <= 1'b1;    // reset alatt blank
            r_mode_sel <= 1'b1;
            r_h_res    <= 12'd1920; r_h_fp  <= 12'd88;
            r_h_sync   <= 12'd44;  r_h_bp  <= 12'd148;
            r_v_res    <= 11'd1080; r_v_fp  <= 11'd4;
            r_v_sync   <= 11'd5;   r_v_bp  <= 11'd36;
            r_h_pol    <= 1'b1;    r_v_pol <= 1'b1;
        end else if (wr_en) begin
            case (wr_addr)
                A_CTRL: begin
                    r_blank    <= wr_data[0];
                    r_mode_sel <= wr_data[1];
                end
                A_PRESET: begin
                    // Preset betöltés — felülírja az összes timing regisztert
                    logic [11:0] p_h_res, p_h_fp, p_h_sync, p_h_bp;
                    logic [10:0] p_v_res, p_v_fp, p_v_sync, p_v_bp;
                    logic        p_h_pol, p_v_pol, p_mode_sel;
                    load_preset(wr_data[1:0],
                        p_h_res, p_h_fp, p_h_sync, p_h_bp,
                        p_v_res, p_v_fp, p_v_sync, p_v_bp,
                        p_h_pol, p_v_pol, p_mode_sel);
                    r_h_res    <= p_h_res;    r_h_fp   <= p_h_fp;
                    r_h_sync   <= p_h_sync;   r_h_bp   <= p_h_bp;
                    r_v_res    <= p_v_res;    r_v_fp   <= p_v_fp;
                    r_v_sync   <= p_v_sync;   r_v_bp   <= p_v_bp;
                    r_h_pol    <= p_h_pol;    r_v_pol  <= p_v_pol;
                    r_mode_sel <= p_mode_sel;
                end
                A_H_RES:    r_h_res  <= wr_data[11:0];
                A_H_FP:     r_h_fp   <= wr_data[11:0];
                A_H_SYNC:   r_h_sync <= wr_data[11:0];
                A_H_BP:     r_h_bp   <= wr_data[11:0];
                A_V_RES:    r_v_res  <= wr_data[10:0];
                A_V_FP:     r_v_fp   <= wr_data[10:0];
                A_V_SYNC:   r_v_sync <= wr_data[10:0];
                A_V_BP:     r_v_bp   <= wr_data[10:0];
                A_POLARITY: {r_v_pol, r_h_pol} <= wr_data[1:0];
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Olvasási logika (kombinációs, 1 ciklus késleltetés nélkül)
    // =========================================================================
    always_comb begin
        case (rd_addr)
            A_CTRL:     rd_data = {30'b0, r_mode_sel, r_blank};
            A_H_RES:    rd_data = {20'b0, r_h_res};
            A_H_FP:     rd_data = {20'b0, r_h_fp};
            A_H_SYNC:   rd_data = {20'b0, r_h_sync};
            A_H_BP:     rd_data = {20'b0, r_h_bp};
            A_V_RES:    rd_data = {21'b0, r_v_res};
            A_V_FP:     rd_data = {21'b0, r_v_fp};
            A_V_SYNC:   rd_data = {21'b0, r_v_sync};
            A_V_BP:     rd_data = {21'b0, r_v_bp};
            A_POLARITY: rd_data = {30'b0, r_v_pol, r_h_pol};
            A_STATUS:   rd_data = {30'b0, calib_done, pll_locked};
            default:    rd_data = 32'hDEAD_BEEF;
        endcase
    end

    // =========================================================================
    // Kimenetek
    // =========================================================================
    assign o_blank    = r_blank;
    assign o_mode_sel = r_mode_sel;
    assign o_h_res    = r_h_res;    assign o_h_fp   = r_h_fp;
    assign o_h_sync   = r_h_sync;   assign o_h_bp   = r_h_bp;
    assign o_v_res    = r_v_res;    assign o_v_fp   = r_v_fp;
    assign o_v_sync   = r_v_sync;   assign o_v_bp   = r_v_bp;
    assign o_h_pol    = r_h_pol;    assign o_v_pol  = r_v_pol;

endmodule
