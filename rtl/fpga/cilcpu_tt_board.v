// hu: CLI-CPU F2.8.6 — A7-Lite BOARD top a `cilcpu_tt_top` (Tiny Tapeout tt_um
//     ekvivalens) köré. Ez a Vivado/OpenXC7 fordításnak adott szintetizálható
//     top. A QSPI a `mole99/qspi-pmod`-ra megy a JP1 PMOD-headeren át (sima
//     IOBUF I/O) — NEM az onboard config-flash-re, ezért NINCS STARTUPE2.
//
//     A tt_top 24-pin interfészének board-leképezése (megerősített, a JP1
//     weboldali pinout + a felhasználó adapter-mappingje szerint):
//       clk        ← i_clk_50m (J19)
//       rst_n      ← KEY1 (AA1), 3-fokú reset-sync
//       ui_in[0]   ← i_uart_rx (U2, CH340 RX)         | ui_in[7:1] = 0 (GPIO-in
//                                                       | nincs bekötve v1-ben)
//       uo_out[0]  → o_uart_tx (V2, CH340 TX)
//       uo_out[1]  → o_led1_n (M18, halt, active-low)
//       uo_out[2]  → o_led2_n (N18, trap, active-low)
//       uo_out[3], uo_out[7:4] (irq, gpio/trace mux) — v1-ben nincs kivezetve
//       uio[7:0]   ↔ io_qspi[7:0] → JP1 GPIO1_0..3 P/N (IOBUF a DQ-ra):
//         uio[0] CS0 cs_flash  = GPIO1_0P F13   uio[4] SD2 DQ2 = GPIO1_0N F14
//         uio[1] SD0 DQ0       = GPIO1_1P E13   uio[5] SD3 DQ3 = GPIO1_1N E14
//         uio[2] SD1 DQ1       = GPIO1_2P D14   uio[6] CS1 cs_psram = GPIO1_2N D15
//         uio[3] SCK clk       = GPIO1_3P E16   uio[7] CS2 RAM B    = GPIO1_3N D16
//
//     A Verilator-szimulációhoz `+define+CILCPU_SIM_BOARD` split debug portokra
//     vált (a uio inout busz helyett), hogy a cocotb QSPI slave vezérelhesse.
//
// en: CLI-CPU F2.8.6 — A7-Lite BOARD top around `cilcpu_tt_top` (Tiny Tapeout
//     tt_um equivalent). Synthesizable top for Vivado/OpenXC7. The QSPI goes to
//     the `mole99/qspi-pmod` via the JP1 PMOD header (plain IOBUF I/O) — NOT the
//     onboard config flash, so there is NO STARTUPE2. Board mapping of the
//     tt_top 24-pin interface as documented above (confirmed JP1 pinout +
//     user's adapter mapping). `+define+CILCPU_SIM_BOARD` switches to split
//     debug ports (instead of the uio inout bus) for the cocotb QSPI slave.

`default_nettype none

module cilcpu_tt_board #(
    parameter integer CODE_BASE_OFFSET = 0,
    parameter integer QE_INIT_ENABLE   = 0,
    parameter integer CLOCKS_PER_BAUD  = 434,  // 50 MHz / 115200 (sim: 8)
    parameter integer BOOT_AUTODETECT  = 0     // FPGA: 1 (flash auto-detect)
) (
    input  wire        i_clk_50m,    // J19 — 50 MHz aktív oszcillátor
    input  wire        i_rst_btn_n,  // KEY1 (AA1) — active low reset
    input  wire        i_uart_rx,    // U2 — CH340 USB-UART RX (host → loader)
    output wire        o_uart_tx,    // V2 — CH340 USB-UART TX (eredmény)
    output wire        o_led1_n,     // M18 — halt indikátor (active low)
    output wire        o_led2_n      // N18 — trap indikátor (active low)
`ifdef CILCPU_SIM_BOARD
    ,
    // hu: Sim-only split debug portok a uio inout busz helyett — a cocotb
    //     QSPI slave a tt_top uio_out/uio_oe-jét olvassa és a uio_in-t hajtja.
    // en: Sim-only split debug ports instead of the uio inout bus — the cocotb
    //     QSPI slave reads tt_top uio_out/uio_oe and drives uio_in.
    output wire [7:0]  o_uio_out_dbg,
    output wire [7:0]  o_uio_oe_dbg,
    input  wire [7:0]  i_uio_in_dbg
`else
    ,
    // hu: QSPI uio busz → JP1 GPIO1_0..3 P/N (a qspi-pmod 8 jel-pinje)
    // en: QSPI uio bus → JP1 GPIO1_0..3 P/N (the qspi-pmod's 8 signal pins)
    inout  wire [7:0]  io_qspi
`endif
);

    // ============================================================
    // hu: Reset szinkronizer — async assert, sync deassert (3-fokú)
    // en: Reset synchronizer — async assert, sync deassert (3-stage)
    // ============================================================
    reg [2:0] r_rst_sync;
    always @(posedge i_clk_50m or negedge i_rst_btn_n) begin
        if (!i_rst_btn_n)
            r_rst_sync <= 3'b000;
        else
            r_rst_sync <= {r_rst_sync[1:0], 1'b1};
    end
    wire w_rst_n = r_rst_sync[2];

    // ============================================================
    // hu: tt_top belső jelei
    // en: tt_top internal nets
    // ============================================================
    wire [7:0] w_ui_in;
    wire [7:0] w_uo_out;
    wire [7:0] w_uio_in;
    wire [7:0] w_uio_out;
    wire [7:0] w_uio_oe;

    // hu: ui_in[0] = UART RX; ui_in[7:1] = GPIO-in (v1: lekötve 0)
    // en: ui_in[0] = UART RX; ui_in[7:1] = GPIO-in (v1: tied to 0)
    assign w_ui_in = {7'b000_0000, i_uart_rx};

    cilcpu_tt_top #(
        .CODE_BASE_OFFSET (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE   (QE_INIT_ENABLE),
        .CLOCKS_PER_BAUD  (CLOCKS_PER_BAUD),
        .BOOT_AUTODETECT  (BOOT_AUTODETECT)
    ) u_top (
        .ui_in   (w_ui_in),
        .uo_out  (w_uo_out),
        .uio_in  (w_uio_in),
        .uio_out (w_uio_out),
        .uio_oe  (w_uio_oe),
        .ena     (1'b1),
        .clk     (i_clk_50m),
        .rst_n   (w_rst_n)
    );

    // ============================================================
    // hu: Dedikált kimenetek board-pinekre
    // en: Dedicated outputs to board pins
    // ============================================================
    assign o_uart_tx = w_uo_out[0];                 // UART TX
    assign o_led1_n  = ~w_uo_out[1];                // halt → LED1 (active low)
    assign o_led2_n  = ~w_uo_out[2];                // trap → LED2 (active low)

    // hu: uo_out[3] (irq) és uo_out[7:4] (gpio/trace mux) v1-ben nincs
    //     kivezetve → lint-ack.
    // en: uo_out[3] (irq) and uo_out[7:4] (gpio/trace mux) are not wired in v1
    //     → lint ack.
    wire _unused_uo = &{1'b0, w_uo_out[7:3], 1'b0};

`ifdef CILCPU_SIM_BOARD
    // ============================================================
    // hu: Sim mód — split debug portok közvetlenül a tt_top uio jeleire.
    // en: Sim mode — split debug ports straight to the tt_top uio signals.
    // ============================================================
    assign o_uio_out_dbg = w_uio_out;
    assign o_uio_oe_dbg  = w_uio_oe;
    assign w_uio_in      = i_uio_in_dbg;
`else
    // ============================================================
    // hu: FPGA mód — 8× IOBUF a uio buszra (a JP1 GPIO1_0..3 P/N pinekre).
    //     A DQ pinek (uio 1,2,4,5) iránya a tt_top uio_oe-je; a CS/SCK pinek
    //     (uio 0,3,6,7) mindig kimenetek (uio_oe=1 → T=0). Az IOBUF T = ~oe.
    // en: FPGA mode — 8× IOBUF on the uio bus (to the JP1 GPIO1_0..3 P/N pins).
    //     DQ pin direction (uio 1,2,4,5) follows tt_top uio_oe; CS/SCK pins
    //     (uio 0,3,6,7) are always outputs (uio_oe=1 → T=0). IOBUF T = ~oe.
    // ============================================================
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_uio_iobuf
            IOBUF #(
                .DRIVE      (8),
                .IOSTANDARD ("LVCMOS33"),
                .SLEW       ("FAST")
            ) u_iobuf (
                .O  (w_uio_in[gi]),
                .IO (io_qspi[gi]),
                .I  (w_uio_out[gi]),
                .T  (~w_uio_oe[gi])
            );
        end
    endgenerate
`endif

endmodule

`default_nettype wire
