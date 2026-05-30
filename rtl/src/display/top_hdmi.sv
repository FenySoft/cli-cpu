// HDMI Display Top-Level — MicroPhase A7-Lite (XC7A200T)
// 1080p@30Hz, 32-bit dupla framebuffer, DDR3 line buffer
//
// Vivado IP függőségek (generálni kell):
//   clk_wiz_0    : 50 MHz → 200 MHz (clk_out1), 74.25 MHz (clk_out2)
//   clk_wiz_1    : 74.25 MHz → 371.25 MHz (clk_out1)
//   mig_7series_0: DDR3 16-bit 800 Mbps natív interfész
//   xpm_memory   : Vivado XPM könyvtár (automatikusan elérhető)
//
// Project F modulok (lib/display/):
//   display_1080p.sv, tmds_encoder_dvi.sv
//   lib/display/xc7/: oserdes_10b.sv, tmds_out.sv

`default_nettype none
`timescale 1ns / 1ps

module top_hdmi (
    input  wire logic        clk_50m,       // 50 MHz rendszeróra (J19)
    input  wire logic        btn_rst_n,     // reset gomb, aktív alacsony

    // HDMI TMDS differenciális kimenetek
    output wire logic        tmds_clk_p,    // L19
    output wire logic        tmds_clk_n,    // L20
    output wire logic        tmds_ch0_p,    // K21  kék  / blue
    output wire logic        tmds_ch0_n,    // K22
    output wire logic        tmds_ch1_p,    // J20  zöld / green
    output wire logic        tmds_ch1_n,    // J21
    output wire logic        tmds_ch2_p,    // G17  piros / red
    output wire logic        tmds_ch2_n,    // G18

    // DDR3 fizikai lábak — MIG vezérli
    inout  wire logic [15:0] ddr3_dq,
    inout  wire logic  [1:0] ddr3_dqs_p,
    inout  wire logic  [1:0] ddr3_dqs_n,
    output wire logic [14:0] ddr3_addr,
    output wire logic  [2:0] ddr3_ba,
    output wire logic        ddr3_ras_n,
    output wire logic        ddr3_cas_n,
    output wire logic        ddr3_we_n,
    output wire logic        ddr3_reset_n,
    output wire logic  [0:0] ddr3_ck_p,
    output wire logic  [0:0] ddr3_ck_n,
    output wire logic  [0:0] ddr3_cke,
    output wire logic  [0:0] ddr3_cs_n,
    output wire logic  [1:0] ddr3_dm,
    output wire logic  [0:0] ddr3_odt
);

    // =========================================================================
    // Paraméterek
    // =========================================================================
    localparam int H_RES            = 1920;
    localparam int V_RES            = 1080;
    localparam int LINE_BYTES       = H_RES * 4;               // 7680 byte/sor (RGBA32)
    localparam int MIG_BURST_BYTES  = 16;                      // 128-bit = 16 byte/burst
    localparam int BURSTS_PER_LINE  = LINE_BYTES / MIG_BURST_BYTES; // 480

    // Framebuffer elrendezés a DDR3-ban
    localparam [28:0] BASE_FRONT = 29'h000_0000;   // front buffer: 0 MB
    localparam [28:0] BASE_BACK  = 29'h080_0000;   // back  buffer: 8 MB

    // =========================================================================
    // 1. Órajel generálás
    // =========================================================================
    logic clk_200m, clk_pix, clk_pix_5x;
    logic locked_0, locked_1;

    // clk_wiz_0: 50 MHz → 200 MHz (MIG referencia), 74.25 MHz (pixel)
    // Vivado clk_wiz konfiguráció:
    //   CLKFBOUT_MULT_F = 14.875, DIVCLK_DIVIDE = 1  → VCO = 743.75 MHz
    //   CLKOUT0_DIVIDE_F = 3.750  → 198.33 MHz (≈200 MHz, MIG elfogadja)
    //   CLKOUT1_DIVIDE_F = 10.0   → 74.375 MHz (≈74.25 MHz, monitorfüggő)
    clk_wiz_0 u_mmcm0 (
        .clk_in1  (clk_50m),
        .clk_out1 (clk_200m),
        .clk_out2 (clk_pix),
        .locked   (locked_0),
        .reset    (1'b0)
    );

    // clk_wiz_1: 74.25 MHz → 371.25 MHz (OSERDESE2 DDR ×5)
    // Vivado clk_wiz konfiguráció:
    //   CLKFBOUT_MULT_F = 5.0, DIVCLK_DIVIDE = 1  → VCO = 371.25 MHz
    //   CLKOUT0_DIVIDE_F = 1.0 → 371.25 MHz
    clk_wiz_1 u_mmcm1 (
        .clk_in1  (clk_pix),
        .clk_out1 (clk_pix_5x),
        .locked   (locked_1),
        .reset    (~locked_0)
    );

    wire rst_pix = ~(locked_0 & locked_1 & btn_rst_n);
    wire rst_mig = ~(locked_0 & btn_rst_n);

    // =========================================================================
    // 2. MIG DDR3 vezérlő
    // =========================================================================
    logic [28:0]  app_addr;
    logic  [2:0]  app_cmd;
    logic         app_en, app_rdy;
    logic [127:0] app_rd_data;
    logic         app_rd_data_valid;
    logic         ui_clk, ui_rst;
    logic         calib_done;

    mig_7series_0 u_mig (
        // DDR3 fizikai interfész
        .ddr3_dq          (ddr3_dq),
        .ddr3_dqs_p       (ddr3_dqs_p),
        .ddr3_dqs_n       (ddr3_dqs_n),
        .ddr3_addr        (ddr3_addr),
        .ddr3_ba          (ddr3_ba),
        .ddr3_ras_n       (ddr3_ras_n),
        .ddr3_cas_n       (ddr3_cas_n),
        .ddr3_we_n        (ddr3_we_n),
        .ddr3_reset_n     (ddr3_reset_n),
        .ddr3_ck_p        (ddr3_ck_p),
        .ddr3_ck_n        (ddr3_ck_n),
        .ddr3_cke         (ddr3_cke),
        .ddr3_cs_n        (ddr3_cs_n),
        .ddr3_dm          (ddr3_dm),
        .ddr3_odt         (ddr3_odt),
        // Natív alkalmazás interfész
        .app_addr          (app_addr),
        .app_cmd           (app_cmd),
        .app_en            (app_en),
        .app_rdy           (app_rdy),
        .app_rd_data       (app_rd_data),
        .app_rd_data_valid (app_rd_data_valid),
        .app_rd_data_end   (),
        // Írás letiltva — CPU interfész külön arbiter modul lesz
        .app_wdf_data      (128'b0),
        .app_wdf_wren      (1'b0),
        .app_wdf_end       (1'b0),
        .app_wdf_rdy       (),
        .app_wdf_mask      (16'hFFFF),
        .app_ref_req       (1'b0),
        .app_zq_req        (1'b0),
        // Órajel és reset
        .sys_clk_i         (clk_200m),
        .clk_ref_i         (clk_200m),
        .sys_rst           (rst_mig),
        .ui_clk            (ui_clk),
        .ui_clk_sync_rst   (ui_rst),
        .init_calib_complete(calib_done)
    );

    // =========================================================================
    // 3. Dupla framebuffer csere (clk_pix tartomány)
    //    fb_sel=0: CPU ír BASE_BACK,  display olvassa BASE_FRONT
    //    fb_sel=1: CPU ír BASE_FRONT, display olvassa BASE_BACK
    // =========================================================================
    logic fb_sel;
    logic frame;

    always_ff @(posedge clk_pix) begin
        if (rst_pix)    fb_sel <= 1'b0;
        else if (frame) fb_sel <= ~fb_sel;   // frame határán csere
    end

    // fb_sel CDC → ui_clk (2-FF szinkronizáló)
    logic fb_sel_s, fb_sel_mig;
    always_ff @(posedge ui_clk) {fb_sel_mig, fb_sel_s} <= {fb_sel_s, fb_sel};

    // =========================================================================
    // 4. Ping-pong line buffer: 2 × 1920 × 32-bit BRAM
    //    wr_half (ui_clk): DDR3 FSM írási cél — mindig az inaktív fél
    //    rd_half (clk_pix): display olvasási forrás = ~wr_half
    // =========================================================================
    logic        wr_half;          // ui_clk tartomány
    logic [10:0] lb_wr_addr;       // 0..1919
    logic [31:0] lb_wr_data;
    logic        lb_wr_en;
    logic [10:0] lb_rd_addr;       // 0..1919
    logic [31:0] lb_rd_data;

    // wr_half CDC → clk_pix
    logic wr_half_s, wr_half_pix;
    always_ff @(posedge clk_pix) {wr_half_pix, wr_half_s} <= {wr_half_s, wr_half};
    wire rd_half = ~wr_half_pix;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A       (12),
        .ADDR_WIDTH_B       (12),
        .BYTE_WRITE_WIDTH_A (32),       // 1-bites wea (szó-engedélyező)
        .WRITE_DATA_WIDTH_A (32),
        .READ_DATA_WIDTH_B  (32),
        .MEMORY_SIZE        (3840 * 32), // 2 × 1920 szó × 32-bit (bit)
        .CLOCKING_MODE      ("independent_clock"),
        .MEMORY_PRIMITIVE   ("block"),
        .READ_LATENCY_B     (1)
    ) u_line_buf (
        .clka   (ui_clk),
        .addra  ({wr_half,  lb_wr_addr}),
        .dina   (lb_wr_data),
        .wea    (lb_wr_en),
        .ena    (1'b1),
        .clkb   (clk_pix),
        .addrb  ({rd_half, lb_rd_addr}),
        .doutb  (lb_rd_data),
        .enb    (1'b1),
        .rstb   (rst_pix),
        .regceb (1'b1)
    );

    // =========================================================================
    // 5. DDR3 sor-olvasó FSM (ui_clk tartomány)
    //    Minden sor elején (line_req) előre olvassa a KÖVETKEZŐ sort DDR3-ból
    //    a ping-pong buffer inaktív felébe.
    // =========================================================================

    // 'line' szinkronizálása: clk_pix → ui_clk (3-FF, felmenő él)
    logic line_pix;
    logic line_s0, line_s1, line_s2;
    always_ff @(posedge ui_clk) begin
        line_s0 <= line_pix;
        line_s1 <= line_s0;
        line_s2 <= line_s1;
    end
    wire line_req = line_s1 & ~line_s2;

    // 'frame' szinkronizálása: clk_pix → ui_clk
    logic frame_s, frame_mig;
    always_ff @(posedge ui_clk) {frame_mig, frame_s} <= {frame_s, frame};

    // 'sy' szinkronizálása: clk_pix → ui_clk
    logic signed [15:0] sy_pix, sy_mig;
    always_ff @(posedge ui_clk) sy_mig <= sy_pix;

    // Sor-báziscím akkumulátor — elkerüli a szorzót
    // Értéke: a következő beolvasandó sor DDR3 báziscíme
    logic [28:0] next_line_base;

    typedef enum logic { S_IDLE, S_FETCH } t_state;
    t_state rd_state;

    logic  [9:0] cmd_cnt;    // kiadott MIG parancsok száma  (0..479)
    logic  [9:0] recv_cnt;   // fogadott burst-ok száma      (0..479)
    logic  [1:0] sub_w;      // 128-bit → 4×32-bit pixel index

    always_ff @(posedge ui_clk) begin
        app_en   <= 1'b0;
        lb_wr_en <= 1'b0;

        case (rd_state)

            S_IDLE: begin
                // Keret elején báziscím visszaállítás (BASE + LINE_BYTES = sor 1 előre)
                if (frame_mig)
                    next_line_base <= (fb_sel_mig ? BASE_BACK : BASE_FRONT)
                                    + LINE_BYTES[28:0];

                // Sor-olvasás indítása: aktív soroknál, ha kalibrálás kész
                if (line_req && calib_done && sy_mig >= 0) begin
                    wr_half  <= ~wr_half;
                    cmd_cnt  <= '0;
                    recv_cnt <= '0;
                    sub_w    <= '0;
                    rd_state <= S_FETCH;
                end
            end

            S_FETCH: begin
                // Parancs kiadás: minden kész MIG ciklusban egy burst olvasás
                if (app_rdy && cmd_cnt < BURSTS_PER_LINE[9:0]) begin
                    app_en   <= 1'b1;
                    app_cmd  <= 3'b001;    // MIG read
                    app_addr <= next_line_base + (29'(cmd_cnt) << 4);  // ×16 byte
                    cmd_cnt  <= cmd_cnt + 1;
                end

                // Adat fogadás: 128-bit → 4×32-bit pixel szétbontás
                if (app_rd_data_valid) begin
                    lb_wr_data <= app_rd_data[32*sub_w +: 32];
                    lb_wr_addr <= {recv_cnt[8:0], sub_w};  // recv*4 + sub_w
                    lb_wr_en   <= 1'b1;
                    sub_w      <= sub_w + 1;

                    if (sub_w == 2'b11) begin
                        if (recv_cnt == BURSTS_PER_LINE[9:0] - 1) begin
                            next_line_base <= next_line_base + LINE_BYTES[28:0];
                            rd_state       <= S_IDLE;
                        end else begin
                            recv_cnt <= recv_cnt + 1;
                        end
                    end
                end
            end

        endcase

        if (ui_rst) begin
            rd_state       <= S_IDLE;
            app_en         <= 1'b0;
            lb_wr_en       <= 1'b0;
            wr_half        <= 1'b0;
            cmd_cnt        <= '0;
            recv_cnt       <= '0;
            sub_w          <= '0;
            next_line_base <= BASE_FRONT + LINE_BYTES[28:0];
        end
    end

    // =========================================================================
    // 6. Display timing (clk_pix tartomány)
    //    display_1080p kimenet:
    //      sx: -280..1919  (negatív = blanking)
    //      sy: -45..1079   (negatív = blanking)
    //      frame: 1 ciklus, keret elején (sx=H_STA, sy=V_STA)
    //      line:  1 ciklus, sor elején  (sx=H_STA)
    //      de:    1 = aktív pixel terület
    // =========================================================================
    logic hsync, vsync, de, line;
    logic signed [15:0] sx, sy;

    display_1080p #(.CORDW(16)) u_timing (
        .clk_pix (clk_pix),
        .rst_pix (rst_pix),
        .hsync   (hsync),
        .vsync   (vsync),
        .de      (de),
        .frame   (frame),
        .line    (line),
        .sx      (sx),
        .sy      (sy)
    );

    assign line_pix = line;
    assign sy_pix   = sy;

    // =========================================================================
    // 7. Pixel kiolvasás a line buffer-ből (clk_pix)
    // =========================================================================
    assign lb_rd_addr = sx[10:0];   // aktív területen sx = 0..1919

    // de igazítása a BRAM 1-ciklus olvasási késleltetéséhez
    logic de_d;
    always_ff @(posedge clk_pix) de_d <= de;

    wire [7:0] red   = lb_rd_data[23:16];
    wire [7:0] green = lb_rd_data[15:8];
    wire [7:0] blue  = lb_rd_data[7:0];
    // [31:24] = alpha — HDMI-n nem szükséges

    // =========================================================================
    // 8. TMDS kódolás (clk_pix)
    //    CH0=kék  (hSync+vSync a ctrl csatornán)
    //    CH1=zöld, CH2=piros (ctrl=00)
    // =========================================================================
    logic [9:0] tmds_ch0, tmds_ch1, tmds_ch2;

    tmds_encoder_dvi u_enc_b (
        .clk_pix (clk_pix), .rst_pix (rst_pix),
        .data_in (blue),    .ctrl_in ({vsync, hsync}),
        .de      (de_d),    .tmds    (tmds_ch0)
    );
    tmds_encoder_dvi u_enc_g (
        .clk_pix (clk_pix), .rst_pix (rst_pix),
        .data_in (green),   .ctrl_in (2'b00),
        .de      (de_d),    .tmds    (tmds_ch1)
    );
    tmds_encoder_dvi u_enc_r (
        .clk_pix (clk_pix), .rst_pix (rst_pix),
        .data_in (red),     .ctrl_in (2'b00),
        .de      (de_d),    .tmds    (tmds_ch2)
    );

    // =========================================================================
    // 9. OSERDESE2 szerializálás (MASTER+SLAVE pár csatornánként)
    // =========================================================================
    logic s_ch0, s_ch1, s_ch2, s_clk;

    oserdes_10b u_ser0 (.clk(clk_pix), .clk_hs(clk_pix_5x), .rst(rst_pix),
                        .data_in(tmds_ch0),       .serial_out(s_ch0));
    oserdes_10b u_ser1 (.clk(clk_pix), .clk_hs(clk_pix_5x), .rst(rst_pix),
                        .data_in(tmds_ch1),       .serial_out(s_ch1));
    oserdes_10b u_ser2 (.clk(clk_pix), .clk_hs(clk_pix_5x), .rst(rst_pix),
                        .data_in(tmds_ch2),       .serial_out(s_ch2));
    oserdes_10b u_sclk (.clk(clk_pix), .clk_hs(clk_pix_5x), .rst(rst_pix),
                        .data_in(10'b0000011111), .serial_out(s_clk));

    // =========================================================================
    // 10. OBUFDS differenciális kimenet
    // =========================================================================
    tmds_out u_out0 (.tmds(s_ch0), .pin_p(tmds_ch0_p), .pin_n(tmds_ch0_n));
    tmds_out u_out1 (.tmds(s_ch1), .pin_p(tmds_ch1_p), .pin_n(tmds_ch1_n));
    tmds_out u_out2 (.tmds(s_ch2), .pin_p(tmds_ch2_p), .pin_n(tmds_ch2_n));
    tmds_out u_outc (.tmds(s_clk), .pin_p(tmds_clk_p), .pin_n(tmds_clk_n));

endmodule
