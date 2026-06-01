// hu: CLI-CPU F2.8.6 — Tiny Tapeout `tt_um` ekvivalens top-level wrapper.
//     A `cilcpu_soc`-ot (Nano core + UART loader/boot_ctrl + mailbox/gpio/trace
//     + QSPI) köti a TT szabványos 24-pines interfészére (8 dedikált bemenet +
//     8 dedikált kimenet + 8 bidirekcionális), és hozzáad egy decimális
//     eredmény-printert (UART TX) a halt/trap érték kiírásához. Ez az F3
//     tape-out wrapper funkcionális precursor-a — az F3 ezt minimális átírással
//     csomagolja a `tt_um_<név>` modulba.
//
//     Pin-map (megerősített, ADR 2026-06-01):
//       ui_in[0]    UART RX (host → loader)
//       ui_in[7:1]  GPIO_IN[6:0]
//       uo_out[0]   UART TX (eredmény-printer)
//       uo_out[1]   halt
//       uo_out[2]   trap
//       uo_out[3]   IRQ (aggregált)
//       uo_out[7:4] MUX: trace_mode ? trace[3:0] : gpio_out[3:0]
//       uio[3:0]    QSPI DQ[3:0]   (bidir, oe = qspi_dq_oe)
//       uio[4]      QSPI cs_flash_n (out)
//       uio[5]      QSPI cs_psram_n (out)
//       uio[6]      QSPI clk        (out)
//       uio[7]      MUX: trace_mode ? trace[4] : gpio_out[4] (out)
//     A mailbox host-oldal NINCS pin — az F3 chip-en UART-protokollon érhető el
//     (a loader-keret bővítése; külön taszk). Itt belül tied-off / open.
//
// en: CLI-CPU F2.8.6 — Tiny Tapeout `tt_um` equivalent top-level wrapper.
//     Binds `cilcpu_soc` (Nano core + UART loader/boot_ctrl + mailbox/gpio/trace
//     + QSPI) to the TT standard 24-pin interface (8 dedicated inputs + 8
//     dedicated outputs + 8 bidirectional), and adds a decimal result printer
//     (UART TX) to emit the halt/trap value. This is the functional precursor
//     of the F3 tape-out wrapper — F3 wraps it into `tt_um_<name>` with minimal
//     rewrite. Pin map as documented above. The mailbox host side is NOT pinned
//     (reached via UART protocol on the F3 chip; separate task) — tied off here.

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_tt_top #(
    // hu: A paramétereket áthajtjuk a SoC-ba / a printerbe. Méret-nélküli
    //     `integer` a command-line `-Gname=value` override-hoz (WIDTHTRUNC nélkül).
    // en: Parameters forwarded to the SoC / printer. Untyped `integer` for the
    //     command-line `-Gname=value` override (no WIDTHTRUNC).
    parameter integer CODE_BASE_OFFSET = 0,
    parameter integer QE_INIT_ENABLE   = 0,
    parameter integer CLOCKS_PER_BAUD  = 434,  // 50 MHz / 115200 (sim: 8)
    parameter integer BOOT_AUTODETECT  = 0     // FPGA: 1 (flash auto-detect)
) (
    // hu: Tiny Tapeout szabványos interfész (24 pin + clk/rst_n/ena)
    // en: Tiny Tapeout standard interface (24 pins + clk/rst_n/ena)
    input  wire [7:0] ui_in,     // dedikált bemenetek / dedicated inputs
    output wire [7:0] uo_out,    // dedikált kimenetek / dedicated outputs
    input  wire [7:0] uio_in,    // bidir bemeneti út / bidir input path
    output wire [7:0] uio_out,   // bidir kimeneti út / bidir output path
    output wire [7:0] uio_oe,    // bidir engedélyezés (1=kimenet) / bidir enable
    input  wire       ena,       // 1 ha a design tápfeszültség alatt van
    input  wire       clk,
    input  wire       rst_n
);

    // hu: `ena` a TT-n a power-gate jelzés; egyszerű design-nál nem használjuk.
    // en: `ena` is the TT power-gate signal; unused for a simple design.
    wire _unused_ena = ena;

    // ============================================================
    // hu: Reset szinkronizer — async assert, sync deassert (3-stage).
    //     A TT rst_n tiszta, de a szinkronizer biztonsági gyakorlat.
    // en: Reset synchronizer — async assert, sync deassert (3-stage).
    //     The TT rst_n is clean, but the synchronizer is good practice.
    // ============================================================
    reg [2:0] r_rst_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_rst_sync <= 3'b000;
        else
            r_rst_sync <= {r_rst_sync[1:0], 1'b1};
    end
    wire soc_rst_n = r_rst_sync[2];

    // ============================================================
    // hu: Bemeneti pin-leképezés
    // en: Input pin mapping
    // ============================================================
    localparam integer GPIO_WIDTH  = 8;
    localparam integer TRACE_WIDTH = 8;

    wire        w_uart_rx = ui_in[0];
    // hu: 7-bit GPIO bemenet az ui_in[7:1]-ből; a felső bit (in[7]) 0.
    // en: 7-bit GPIO input from ui_in[7:1]; the top bit (in[7]) is 0.
    wire [GPIO_WIDTH-1:0] w_gpio_in = {1'b0, ui_in[7:1]};

    // ============================================================
    // hu: SoC belső jelek
    // en: SoC internal signals
    // ============================================================
    wire        w_qspi_clk;
    wire        w_qspi_cs_flash_n;
    wire        w_qspi_cs_psram_n;
    wire [3:0]  w_qspi_dq_out;
    wire        w_qspi_dq_oe;
    wire [3:0]  w_qspi_dq_in = uio_in[3:0];

    wire [GPIO_WIDTH-1:0]  w_gpio_out;
    wire [GPIO_WIDTH-1:0]  w_gpio_oe;   // hu: belső GPIO-irány; a TT pin-irány a pin-mapból jön
    wire [TRACE_WIDTH-1:0] w_trace;
    wire                   w_trace_mode;

    wire        w_halt;
    wire        w_trap;
    wire [7:0]  w_trap_code;
    wire [23:0] w_pc;
    wire [31:0] w_return_value;
    wire        w_irq;

    // ============================================================
    // hu: SoC példányosítás — a boot belül történik (UART loader / flash
    //     auto-detect), ezért a külső i_boot_* port tied-off. A mailbox
    //     host-oldal nincs pin (F3: UART-protokoll) → tied-off.
    // en: SoC instantiation — boot happens internally (UART loader / flash
    //     auto-detect), so the external i_boot_* ports are tied off. The
    //     mailbox host side is not pinned (F3: UART protocol) → tied off.
    // ============================================================
    cilcpu_soc #(
        .CODE_BASE_OFFSET     (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE       (QE_INIT_ENABLE),
        .GPIO_WIDTH           (GPIO_WIDTH),
        .TRACE_WIDTH          (TRACE_WIDTH),
        .TRACE_NSRC           (8),
        .UART_CLOCKS_PER_BAUD (CLOCKS_PER_BAUD),
        .BOOT_AUTODETECT      (BOOT_AUTODETECT)
    ) u_soc (
        .clk                 (clk),
        .rst_n               (soc_rst_n),

        // hu: Külső boot tied-off — belül a loader/boot_ctrl vezérel
        // en: External boot tied off — the internal loader/boot_ctrl drives boot
        .i_boot_pc           (24'd0),
        .i_boot_arg_count    (8'd0),
        .i_boot_local_count  (8'd0),
        .i_boot_start        (1'b0),
        .i_boot_arg_data     (32'd0),
        .i_boot_arg_valid    (1'b0),
        .o_boot_arg_ready    (),

        .i_uart_rx           (w_uart_rx),

        .o_halt              (w_halt),
        .o_trap              (w_trap),
        .o_trap_code         (w_trap_code),
        .o_pc                (w_pc),
        .o_return_value      (w_return_value),

        .qspi_clk            (w_qspi_clk),
        .qspi_cs_flash_n     (w_qspi_cs_flash_n),
        .qspi_cs_psram_n     (w_qspi_cs_psram_n),
        .qspi_dq_out         (w_qspi_dq_out),
        .qspi_dq_in          (w_qspi_dq_in),
        .qspi_dq_oe          (w_qspi_dq_oe),

        .i_gpio_in           (w_gpio_in),
        .o_gpio_out          (w_gpio_out),
        .o_gpio_oe           (w_gpio_oe),

        .o_trace             (w_trace),
        .o_trace_mode        (w_trace_mode),

        // hu: Mailbox host-oldal nincs pin → tied-off
        // en: Mailbox host side not pinned → tied off
        .i_host_inbox_wdata  (32'd0),
        .i_host_inbox_push   (1'b0),
        .o_host_outbox_rdata (),
        .i_host_outbox_pop   (1'b0),
        .o_host_outbox_empty (),
        .o_host_inbox_full   (),

        .o_irq_mailbox_in    (),
        .o_irq_mailbox_out   (),
        .o_irq               (w_irq)
    );

    // ============================================================
    // hu: Eredmény-printer FSM — a core halt-ra a return_value-t (signed),
    //     trap-ra a trap_code-ot (unsigned) küldi ki decimálisan UART-on.
    //     Egyszeri (latch-elt): a kiírás után S_DONE-ban marad (reset oldja).
    // en: Result printer FSM — on halt emits return_value (signed), on trap
    //     emits trap_code (unsigned) as decimal over UART. One-shot (latched):
    //     stays in S_DONE after printing (reset clears).
    // ============================================================
    localparam [1:0] S_RUN        = 2'd0;
    localparam [1:0] S_PRINT_REQ  = 2'd1;
    localparam [1:0] S_PRINT_WAIT = 2'd2;
    localparam [1:0] S_DONE       = 2'd3;

    reg  [1:0]  r_print_state;
    reg  [31:0] r_print_value;
    reg         r_print_signed;
    reg         r_print_start;
    wire        w_print_busy;
    wire        w_uart_tx;

    always @(posedge clk or negedge soc_rst_n) begin
        if (!soc_rst_n) begin
            r_print_state  <= S_RUN;
            r_print_value  <= 32'd0;
            r_print_signed <= 1'b0;
            r_print_start  <= 1'b0;
        end else begin
            r_print_start <= 1'b0;   // hu: pulzus alaphelyzet / pulse default

            case (r_print_state)
                S_RUN: begin
                    if (w_halt) begin
                        r_print_value  <= w_return_value;
                        r_print_signed <= 1'b1;
                        r_print_state  <= S_PRINT_REQ;
                    end else if (w_trap) begin
                        r_print_value  <= {24'd0, w_trap_code};
                        r_print_signed <= 1'b0;
                        r_print_state  <= S_PRINT_REQ;
                    end
                end
                S_PRINT_REQ: begin
                    r_print_start <= 1'b1;
                    r_print_state <= S_PRINT_WAIT;
                end
                S_PRINT_WAIT: begin
                    if (!w_print_busy && !r_print_start)
                        r_print_state <= S_DONE;
                end
                S_DONE: begin
                    // hu: Latch — reset oldja fel / latched — cleared by reset
                end
                default: r_print_state <= S_RUN;
            endcase
        end
    end

    decimal_printer #(
        .CLOCKS_PER_BAUD (CLOCKS_PER_BAUD)
    ) u_printer (
        .clk     (clk),
        .rst_n   (soc_rst_n),
        .i_value (r_print_value),
        .i_signed(r_print_signed),
        .i_start (r_print_start),
        .o_busy  (w_print_busy),
        .o_tx    (w_uart_tx)
    );

    // ============================================================
    // hu: Kimeneti pin-leképezés
    // en: Output pin mapping
    // ============================================================
    // hu: 5-bit muxolt csoport — trace VAGY gpio-out (o_trace_mode dönt).
    //     {uio[7], uo_out[7:4]} = trace_mode ? trace[4:0] : gpio_out[4:0].
    // en: 5-bit muxed group — trace OR gpio-out (selected by o_trace_mode).
    wire [4:0] w_mux = w_trace_mode ? w_trace[4:0] : w_gpio_out[4:0];

    assign uo_out[0]   = w_uart_tx;     // UART TX (printer)
    assign uo_out[1]   = w_halt;
    assign uo_out[2]   = w_trap;
    assign uo_out[3]   = w_irq;
    assign uo_out[7:4] = w_mux[3:0];

    // hu: QSPI a bidi pineken. A DQ[3:0] iránya a controller oe-je; a
    //     cs/clk/mux pinek mindig kimenetek (oe=1).
    // en: QSPI on the bidir pins. DQ[3:0] direction follows the controller oe;
    //     the cs/clk/mux pins are always outputs (oe=1).
    assign uio_out[3:0] = w_qspi_dq_out;
    assign uio_out[4]   = w_qspi_cs_flash_n;
    assign uio_out[5]   = w_qspi_cs_psram_n;
    assign uio_out[6]   = w_qspi_clk;
    assign uio_out[7]   = w_mux[4];

    assign uio_oe[3:0] = {4{w_qspi_dq_oe}};
    assign uio_oe[4]   = 1'b1;
    assign uio_oe[5]   = 1'b1;
    assign uio_oe[6]   = 1'b1;
    assign uio_oe[7]   = 1'b1;

    // hu: Fel nem használt belső jelek (lint-csend)
    // en: Unused internal signals (lint silence)
    wire _unused = &{1'b0, w_pc, w_gpio_out[GPIO_WIDTH-1:5], w_gpio_oe,
                     w_trace[TRACE_WIDTH-1:5], 1'b0};

endmodule

`default_nettype wire
