// hu: CLI-CPU F2.7 Sub4 — MicroPhase A7-Lite XC7A200T BOARD top-level.
//     Ez a Vivado/OpenXC7 fordításnak adott szintetizálható top modul.
//     Két dolgot ad hozzá a sim-friendly `cilcpu_a7lite_top` köré:
//       1) STARTUPE2 primitív, hogy a QSPI flash CLK-ját user módban
//          tudjuk hajtani (a CCLK fizikai pin a dedikált config bankban
//          van, közvetlenül nem köthető user GPIO-ra).
//       2) Négy darab IOBUF, hogy a `cilcpu_a7lite_top` split DQ portjait
//          (qspi_dq_out / qspi_dq_in / qspi_dq_oe) a tényleges board szintű
//          `inout wire [3:0] io_qspi_dq` busz-szal kösse össze.
//
//     A QSPI flash a board IS25L128F (128 Mbit) — a Xilinx config bank
//     dedikált pinjein (FCS_B, D00..D03), pin assignment a
//     `cilcpu_a7lite.xdc`-ben. A QSPI PSRAM-kimenetet nem használjuk
//     (a board-on nincs PSRAM); a vonalat lebegve hagyjuk.
//
//     A Verilator-os szimulációhoz `+define+CILCPU_SIM_BOARD` váltja át a
//     port-interfészt split DQ-ra (debug megfigyelhetőség, inout multi-
//     driver konfliktus elkerülése). FPGA buildkor a makró nincs definiálva.
//
// en: CLI-CPU F2.7 Sub4 — MicroPhase A7-Lite XC7A200T BOARD top-level.
//     This is the synthesizable top module handed to Vivado/OpenXC7.
//     It adds two things around the sim-friendly `cilcpu_a7lite_top`:
//       1) STARTUPE2 primitive to drive the QSPI flash CLK in user mode
//          (the CCLK physical pin sits in the dedicated config bank and
//          cannot be wired as a regular user GPIO).
//       2) Four IOBUFs to wire the `cilcpu_a7lite_top` split DQ ports
//          (qspi_dq_out / qspi_dq_in / qspi_dq_oe) to the real board-level
//          `inout wire [3:0] io_qspi_dq` bus.
//
//     The board QSPI flash is IS25L128F (128 Mbit) on the Xilinx config
//     bank dedicated pins (FCS_B, D00..D03); pin assignment in
//     `cilcpu_a7lite.xdc`. The QSPI PSRAM output is unused (no PSRAM on
//     the board); the line is left floating.
//
//     The Verilator simulation switches the port interface to split DQ
//     via `+define+CILCPU_SIM_BOARD` (debug observability, avoids inout
//     multi-driver conflicts). The macro is undefined for FPGA build.

`default_nettype none

module cilcpu_a7lite_board #(
    // hu: A paraméterek áthajtódnak a belső `cilcpu_a7lite_top`-ra.
    //     `BOOT_ARG_VALUE = 20` → Fibonacci(20) demó alapértelmezettként.
    // en: The parameters pass through to the inner `cilcpu_a7lite_top`.
    //     `BOOT_ARG_VALUE = 20` → Fibonacci(20) demo by default.
    parameter integer BOOT_PC          = 32'h00000008,
    parameter integer BOOT_ARG_COUNT   = 32'd1,
    parameter integer BOOT_LOCAL_COUNT = 32'd4,
    parameter integer BOOT_ARG_VALUE   = 32'd20,
    parameter integer DEBOUNCE_BITS    = 22,
    parameter integer CLOCKS_PER_BAUD  = 434
) (
    // hu: Board-szintű I/O / en: Board-level I/O
    input  wire        i_clk_50m,        // J19 — 50 MHz aktív oszcillátor
    input  wire        i_rst_btn_n,      // KEY1 (AA1) — active low reset
    input  wire        i_start_btn_n,    // KEY2 (W1)  — active low start

    output wire        o_led1_n,         // D6 (M18) — halt indikátor
    output wire        o_led2_n,         // D5 (N18) — trap indikátor
    output wire        o_uart_tx,        // V2 — UART TX a CH340 felé

    output wire        o_qspi_cs_n       // FCS_B (T19)
`ifdef CILCPU_SIM_BOARD
    ,
    // hu: Sim-only debug portok — a `cilcpu_a7lite_top` belső split DQ
    //     vonalait és a STARTUPE2 USRCCLKO-jét vezetjük ki, hogy a cocotb
    //     flash slave közvetlenül vezérelhesse őket. FPGA buildkor ezek
    //     a portok nincsenek (a makró undef), helyettük a board szintű
    //     inout busz és STARTUPE2 + IOBUF instanciák veszik át.
    // en: Sim-only debug ports — exposes the `cilcpu_a7lite_top` internal
    //     split DQ lines and the STARTUPE2 USRCCLKO so the cocotb flash
    //     slave can drive them directly. For FPGA build the macro is
    //     undefined; the board-level inout bus and STARTUPE2 + IOBUF
    //     instances take over.
    output wire        o_qspi_clk_dbg,
    output wire [3:0]  o_qspi_dq_out_dbg,
    input  wire [3:0]  i_qspi_dq_in_dbg,
    output wire        o_qspi_dq_oe_dbg
`else
    ,
    inout  wire [3:0]  io_qspi_dq        // D00..D03 (P22, R22, P21, R21)
`endif
);

    // ============================================================
    // hu: Belső jelek a `cilcpu_a7lite_top` köré
    // en: Internal nets around `cilcpu_a7lite_top`
    // ============================================================
    wire        w_qspi_clk_user;     // CCLK to be driven via STARTUPE2
    wire        w_qspi_cs_flash_n;
    wire        w_qspi_cs_psram_n;   // unused (no PSRAM on board)
    wire [3:0]  w_qspi_dq_out;
    wire [3:0]  w_qspi_dq_in;
    wire        w_qspi_dq_oe;

    // ============================================================
    // hu: A sim-friendly top példányosítása
    // en: Instantiate the sim-friendly top
    // ============================================================
    cilcpu_a7lite_top #(
        .BOOT_PC          (BOOT_PC),
        .BOOT_ARG_COUNT   (BOOT_ARG_COUNT),
        .BOOT_LOCAL_COUNT (BOOT_LOCAL_COUNT),
        .BOOT_ARG_VALUE   (BOOT_ARG_VALUE),
        .DEBOUNCE_BITS    (DEBOUNCE_BITS),
        .CLOCKS_PER_BAUD  (CLOCKS_PER_BAUD)
    ) u_top (
        .i_clk_50m       (i_clk_50m),
        .i_rst_btn_n     (i_rst_btn_n),
        .i_start_btn_n   (i_start_btn_n),
        .o_led1_n        (o_led1_n),
        .o_led2_n        (o_led2_n),
        .o_uart_tx       (o_uart_tx),
        .qspi_clk        (w_qspi_clk_user),
        .qspi_cs_flash_n (w_qspi_cs_flash_n),
        .qspi_cs_psram_n (w_qspi_cs_psram_n),
        .qspi_dq_out     (w_qspi_dq_out),
        .qspi_dq_in      (w_qspi_dq_in),
        .qspi_dq_oe      (w_qspi_dq_oe)
    );

    // ============================================================
    // hu: CCLK pin — STARTUPE2-n keresztül (mindkét módban). Sim-ben a
    //     `sim_stubs/xilinx_primitives_sim.v` behavioral STARTUPE2 stubja
    //     fordul le; FPGA buildkor a Xilinx 'unisims' valódi primitív.
    // en: CCLK pin — driven via STARTUPE2 in both modes. In sim, the
    //     behavioral stub from `sim_stubs/xilinx_primitives_sim.v` is
    //     compiled; in FPGA build, the real Xilinx 'unisims' primitive.
    // ============================================================
    STARTUPE2 #(
        .PROG_USR      ("FALSE"),
        .SIM_CCLK_FREQ (0.0)
    ) u_startupe2 (
        .CFGCLK    (),
        .CFGMCLK   (),
        .EOS       (),
        .PREQ      (),
        .CLK       (1'b0),
        .GSR       (1'b0),
        .GTS       (1'b0),
        .KEYCLEARB (1'b1),
        .PACK      (1'b0),
        .USRCCLKO  (w_qspi_clk_user),
        .USRCCLKTS (1'b0),
        .USRDONEO  (1'b1),
        .USRDONETS (1'b1)
    );

    // ============================================================
    // hu: QSPI CS# — sima user pin (T19), nincs STARTUPE2-re kötés.
    // en: QSPI CS# — regular user pin (T19), no STARTUPE2 routing.
    // ============================================================
    assign o_qspi_cs_n = w_qspi_cs_flash_n;

    // hu: A PSRAM CS# vonalat szándékosan eldobjuk — UNUSED ack a linthez.
    // en: PSRAM CS# is intentionally dropped here — UNUSED ack for lint.
    wire _unused_psram_cs = w_qspi_cs_psram_n;

`ifdef CILCPU_SIM_BOARD
    // ============================================================
    // hu: Sim mód — split debug portok közvetlenül a `cilcpu_a7lite_top`
    //     belső QSPI net-jeire. Az IOBUF-okat kihagyjuk; az inout busz a
    //     verilátorban multi-driver konfliktushoz vezetne.
    // en: Sim mode — split debug ports straight to the `cilcpu_a7lite_top`
    //     internal QSPI nets. IOBUFs omitted; an inout bus would cause a
    //     multi-driver conflict under Verilator.
    // ============================================================
    assign o_qspi_clk_dbg    = w_qspi_clk_user;
    assign o_qspi_dq_out_dbg = w_qspi_dq_out;
    assign w_qspi_dq_in      = i_qspi_dq_in_dbg;
    assign o_qspi_dq_oe_dbg  = w_qspi_dq_oe;
`else
    // ============================================================
    // hu: FPGA mód — DQ[3:0] IOBUF-ok. `w_qspi_dq_oe` közös output-enable:
    //     '1' = a master hajt (CMD/ADDR), '0' = a flash hajt (DATA fázis).
    //     Az IOBUF T bemenete tri-state enable, tehát T = ~oe.
    // en: FPGA mode — DQ[3:0] IOBUFs. `w_qspi_dq_oe` is the shared output
    //     enable: '1' = master drives (CMD/ADDR), '0' = flash drives
    //     (DATA phase). The IOBUF T pin is the tri-state enable, so T = ~oe.
    // ============================================================
    wire w_qspi_dq_tri_n = ~w_qspi_dq_oe;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_qspi_dq_iobuf
            IOBUF #(
                .DRIVE      (8),
                .IOSTANDARD ("LVCMOS33"),
                .SLEW       ("FAST")
            ) u_iobuf (
                .O  (w_qspi_dq_in[gi]),
                .IO (io_qspi_dq[gi]),
                .I  (w_qspi_dq_out[gi]),
                .T  (w_qspi_dq_tri_n)
            );
        end
    endgenerate
`endif

endmodule

`default_nettype wire
