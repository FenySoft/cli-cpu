// Display Timing Generator — runtime konfigurálható
// display_1080p.sv alapján, de timing konstansok helyett regiszter bemenetek
//
// Bemenetként kapja a display_mmio_regs kimeneteit.
// blank=1 esetén: de=0, frame/line=0, sx/sy=0 (stabil állapot monitor re-sync-hez)

`default_nettype none
`timescale 1ns / 1ps

module display_timing_dyn (
    input  wire logic        clk_pix,
    input  wire logic        rst_pix,

    // Timing paraméterek (display_mmio_regs kimeneteiből)
    input  wire logic [11:0] i_h_res,
    input  wire logic [11:0] i_h_fp,
    input  wire logic [11:0] i_h_sync,
    input  wire logic [11:0] i_h_bp,
    input  wire logic [10:0] i_v_res,
    input  wire logic [10:0] i_v_fp,
    input  wire logic [10:0] i_v_sync,
    input  wire logic [10:0] i_v_bp,
    input  wire logic        i_h_pol,
    input  wire logic        i_v_pol,
    input  wire logic        i_blank,          // 1 = kimenet tiltva (mód-váltáshoz)

    // Szinkron jelek és vezérlők
    output      logic        hsync,
    output      logic        vsync,
    output      logic        de,               // data enable: 1 = aktív pixel
    output      logic        frame,            // 1 ciklus: keret eleje
    output      logic        line,             // 1 ciklus: sor eleje (H blanking start)

    // Pixel koordináták (aktív területen: 0..h_res-1, 0..v_res-1)
    output      logic [11:0] sx,
    output      logic [10:0] sy
);

    // =========================================================================
    // Timing határok kiszámítása (regiszterekből, kombinációs)
    // Képlet ugyanaz mint display_1080p.sv localparamjei — de itt registered
    // =========================================================================

    // Negatív tartomány: blanking idő (front porch + sync + back porch)
    // H_STA = -(H_FP + H_SYNC + H_BP)
    logic signed [12:0] h_sta, hs_sta, hs_end, ha_end;
    logic signed [11:0] v_sta, vs_sta, vs_end, va_end;

    always_comb begin
        h_sta  = -$signed({1'b0, i_h_fp}) - $signed({1'b0, i_h_sync})
                                           - $signed({1'b0, i_h_bp});
        hs_sta = h_sta  + $signed({1'b0, i_h_fp});
        hs_end = hs_sta + $signed({1'b0, i_h_sync});
        ha_end = $signed({1'b0, i_h_res}) - 1;

        v_sta  = -$signed({1'b0, i_v_fp}) - $signed({1'b0, i_v_sync})
                                           - $signed({1'b0, i_v_bp});
        vs_sta = v_sta  + $signed({1'b0, i_v_fp});
        vs_end = vs_sta + $signed({1'b0, i_v_sync});
        va_end = $signed({1'b0, i_v_res}) - 1;
    end

    // =========================================================================
    // X/Y számlálók
    // =========================================================================
    logic signed [12:0] x;
    logic signed [11:0] y;

    always_ff @(posedge clk_pix) begin
        if (rst_pix || i_blank) begin
            x <= h_sta;
            y <= v_sta;
        end else begin
            if (x == ha_end) begin
                x <= h_sta;
                y <= (y == va_end) ? v_sta : y + 1;
            end else begin
                x <= x + 1;
            end
        end
    end

    // =========================================================================
    // Szinkron jelek (polaritás-vezérelt)
    // =========================================================================
    always_ff @(posedge clk_pix) begin
        if (rst_pix || i_blank) begin
            hsync <= ~i_h_pol;
            vsync <= ~i_v_pol;
        end else begin
            hsync <= i_h_pol
                   ? (x >= hs_sta && x < hs_end)
                   : ~(x >= hs_sta && x < hs_end);
            vsync <= i_v_pol
                   ? (y >= vs_sta && y < vs_end)
                   : ~(y >= vs_sta && y < vs_end);
        end
    end

    // =========================================================================
    // Vezérlő jelek
    // =========================================================================
    always_ff @(posedge clk_pix) begin
        if (rst_pix || i_blank) begin
            de    <= 1'b0;
            frame <= 1'b0;
            line  <= 1'b0;
        end else begin
            de    <= (y >= 0) && (x >= 0);
            frame <= (x == h_sta) && (y == v_sta);
            line  <= (x == h_sta);
        end
    end

    // =========================================================================
    // Koordináta kimenet (1 ciklus késleltetés, szinkronban de/sync jelekkel)
    // =========================================================================
    always_ff @(posedge clk_pix) begin
        if (rst_pix || i_blank) begin
            sx <= '0;
            sy <= '0;
        end else begin
            sx <= x[11:0];
            sy <= y[10:0];
        end
    end

endmodule
