// hu: CLI-CPU F2.8 #6.5 — SoC wrapper (architektúra B). Egyetlen Nano core
//     (cilcpu_core) + az MMIO-perifériák (cilcpu_mailbox / cilcpu_gpio /
//     cilcpu_trace) integrációja a core MMIO-master buszára. A wrapper végzi
//     a periféria-dekódolást: a 0xF szegmensű (addr[31:28]==SEG_MMIO) LDIND/
//     STIND a core o_mmio_* buszán érkezik, a wrapper az addr[11:8] alapján
//     választ perifériát, és az addr[5:2] szó-offszetet adja a periféria
//     4-bit i_cpu_addr-jára. A read-mux a kiválasztott periféria registered
//     o_cpu_rdata-ját hajtja az i_mmio_rdata-ra (1-ciklus latency, a core
//     ST_MEM_WAIT 2-fázisú szekvenszerével illesztve).
//
//     MMIO-térkép (a core-program szemszögéből):
//       0xF000_0100  Mailbox   (inbox/outbox/status)
//       0xF000_0200  GPIO      (in/out/oe)
//       0xF000_0300  Trace     (cfg)
//
//     A boot/QSPI/státusz portok NÉVAZONOSAK a cilcpu_core-éval, hogy a
//     meglévő cocotb boot-harness (test_core.boot_and_run) változatlanul
//     vezérelje a SoC-ot is.
//
// en: CLI-CPU F2.8 #6.5 — SoC wrapper (architecture B). Integrates a single
//     Nano core (cilcpu_core) with the MMIO peripherals (cilcpu_mailbox /
//     cilcpu_gpio / cilcpu_trace) on the core's MMIO master bus. The wrapper
//     does the peripheral decode: 0xF-segment (addr[31:28]==SEG_MMIO) LDIND/
//     STIND arrive on the core's o_mmio_* bus; the wrapper selects the
//     peripheral by addr[11:8] and feeds the addr[5:2] word offset to the
//     peripheral's 4-bit i_cpu_addr. The read mux drives the selected
//     peripheral's registered o_cpu_rdata onto i_mmio_rdata (1-cycle latency,
//     matched to the core's 2-phase ST_MEM_WAIT sequencer).
//
//     MMIO map (from the core program's view):
//       0xF000_0100  Mailbox   (inbox/outbox/status)
//       0xF000_0200  GPIO      (in/out/oe)
//       0xF000_0300  Trace     (cfg)

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_soc #(
    parameter integer CODE_BASE_OFFSET = 0,
    parameter integer QE_INIT_ENABLE   = 0,
    parameter integer GPIO_WIDTH       = 8,
    parameter integer TRACE_WIDTH      = 8,
    parameter integer TRACE_NSRC       = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Boot konfiguráció (névazonos a cilcpu_core-ral)
    // en: Boot configuration (same names as cilcpu_core)
    input  wire [23:0] i_boot_pc,
    input  wire [7:0]  i_boot_arg_count,
    input  wire [7:0]  i_boot_local_count,
    input  wire        i_boot_start,
    input  wire [31:0] i_boot_arg_data,
    input  wire        i_boot_arg_valid,
    output wire        o_boot_arg_ready,

    // hu: Státusz / en: Status
    output wire        o_halt,
    output wire        o_trap,
    output wire [7:0]  o_trap_code,
    output wire [23:0] o_pc,
    output wire [31:0] o_return_value,

    // hu: QSPI pinek / en: QSPI pins
    output wire        qspi_clk,
    output wire        qspi_cs_flash_n,
    output wire        qspi_cs_psram_n,
    output wire [3:0]  qspi_dq_out,
    input  wire [3:0]  qspi_dq_in,
    output wire        qspi_dq_oe,

    // hu: GPIO fizikai pinek / en: GPIO physical pins
    input  wire [GPIO_WIDTH-1:0]  i_gpio_in,
    output wire [GPIO_WIDTH-1:0]  o_gpio_out,
    output wire [GPIO_WIDTH-1:0]  o_gpio_oe,

    // hu: Trace kimenet (logikai analizátor) / en: Trace output (logic analyzer)
    output wire [TRACE_WIDTH-1:0] o_trace,
    output wire                   o_trace_mode,

    // hu: Mailbox host oldal / en: Mailbox host side
    input  wire [31:0] i_host_inbox_wdata,
    input  wire        i_host_inbox_push,
    output wire [31:0] o_host_outbox_rdata,
    input  wire        i_host_outbox_pop,
    output wire        o_host_outbox_empty,
    output wire        o_host_inbox_full,

    // hu: Megszakítások (IRQ) — per-periféria + aggregált.
    //     A CIL-T0 NEM preemptív (poll/blocking-receive actor-modell): a core
    //     az IRQ-pending MMIO regisztert (0xF000_0000) olvassa polling-gal. Az
    //     o_irq aggregált pin a chip-szintű / inter-core jelzés (CPU-figyelem =
    //     van olvasatlan beérkező mail).
    // en: Interrupts (IRQ) — per-peripheral + aggregate. CIL-T0 is NOT
    //     preemptive (poll/blocking-receive actor model): the core polls the
    //     IRQ-pending MMIO register (0xF000_0000). The o_irq aggregate pin is
    //     the chip-level / inter-core signal (CPU-attention = unread inbox mail).
    output wire        o_irq_mailbox_in,
    output wire        o_irq_mailbox_out,
    output wire        o_irq
);

    // ============================================================
    // hu: Core MMIO-master busz / en: Core MMIO master bus
    // ============================================================
    wire [31:0] w_mmio_addr;
    wire [31:0] w_mmio_wdata;
    wire        w_mmio_we;
    wire        w_mmio_re;
    reg  [31:0] w_mmio_rdata;     // hu: read-mux (kombinációs)

    // ============================================================
    // hu: Periféria-dekódolás
    //     addr[11:8] = periféria-select (1=mailbox, 2=gpio, 3=trace),
    //     addr[5:2]  = szó-offszet a periféria 4-bit i_cpu_addr-jára.
    // en: Peripheral decode
    //     addr[11:8] = peripheral select (1=mailbox, 2=gpio, 3=trace),
    //     addr[5:2]  = word offset feeding the peripheral's 4-bit i_cpu_addr.
    // ============================================================
    localparam [3:0] PSEL_IRQ     = 4'd0;   // 0xF000_0000 — IRQ-pending (RO)
    localparam [3:0] PSEL_MAILBOX = 4'd1;
    localparam [3:0] PSEL_GPIO    = 4'd2;
    localparam [3:0] PSEL_TRACE   = 4'd3;

    wire [3:0] w_psel    = w_mmio_addr[11:8];
    wire [3:0] w_reg_off = w_mmio_addr[5:2];

    wire w_sel_irq     = (w_psel == PSEL_IRQ);
    wire w_sel_mailbox = (w_psel == PSEL_MAILBOX);
    wire w_sel_gpio    = (w_psel == PSEL_GPIO);
    wire w_sel_trace   = (w_psel == PSEL_TRACE);

    // hu: per-periféria we/re (csak a kiválasztottra)
    // en: per-peripheral we/re (only to the selected one)
    wire w_mb_we    = w_mmio_we & w_sel_mailbox;
    wire w_mb_re    = w_mmio_re & w_sel_mailbox;
    wire w_gpio_we  = w_mmio_we & w_sel_gpio;
    wire w_gpio_re  = w_mmio_re & w_sel_gpio;
    wire w_trace_we = w_mmio_we & w_sel_trace;
    wire w_trace_re = w_mmio_re & w_sel_trace;

    wire [31:0] w_mb_rdata;
    wire [31:0] w_gpio_rdata;
    wire [31:0] w_trace_rdata;

    // hu: read-mux — a kiválasztott periféria registered olvasása. A
    //     periféria-select a w_mmio_addr-ból jön, amit a core a read teljes
    //     idejére (o_mmio_re utáni ciklus is) tart → a mux helyesen választ.
    // en: read mux — the selected peripheral's registered read. The select
    //     comes from w_mmio_addr, which the core holds across the whole read
    //     (including the cycle after o_mmio_re) → the mux picks correctly.
    always @(*) begin
        case (w_psel)
            PSEL_IRQ:     w_mmio_rdata = r_irq_rdata;
            PSEL_MAILBOX: w_mmio_rdata = w_mb_rdata;
            PSEL_GPIO:    w_mmio_rdata = w_gpio_rdata;
            PSEL_TRACE:   w_mmio_rdata = w_trace_rdata;
            default:      w_mmio_rdata = 32'd0;
        endcase
    end

    // ============================================================
    // hu: IRQ-pending MMIO regiszter (0xF000_0000, read-only) — aggregálja
    //     a periféria-IRQ-kat egyetlen szóba, hogy a core EGY LDIND-del
    //     lekérdezhesse (poll-barát, CIL-T0 ISA-kompatibilis, nem preemptív).
    //     Bit0 = mailbox inbox nem üres (CPU-nak van mail), bit1 = outbox nem
    //     üres (host-figyelem). Registered read (1-ciklus latency), illeszkedik
    //     a core ST_MEM_WAIT 2-fázisú szekvenszeréhez. Az o_irq aggregált pin
    //     a CPU-figyelmet jelzi chip-szinten (bővíthető a többi periféria
    //     IRQ-jával az OR-ban).
    // en: IRQ-pending MMIO register (0xF000_0000, read-only) — aggregates the
    //     peripheral IRQs into one word so the core can poll with a single
    //     LDIND (poll-friendly, CIL-T0 ISA-compatible, non-preemptive).
    //     Bit0 = mailbox inbox not empty (CPU has mail), bit1 = outbox not
    //     empty (host attention). Registered read (1-cycle latency), matched to
    //     the core's 2-phase ST_MEM_WAIT sequencer. The o_irq aggregate pin
    //     signals CPU-attention at chip level (extensible by OR-ing further
    //     peripheral IRQs).
    // ============================================================
    wire        w_irq_re = w_mmio_re & w_sel_irq;
    wire [31:0] w_irq_status = {30'd0, o_irq_mailbox_out, o_irq_mailbox_in};
    reg  [31:0] r_irq_rdata;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_irq_rdata <= 32'd0;
        else if (w_irq_re)
            r_irq_rdata <= w_irq_status;
    end

    // hu: aggregált CPU-figyelem IRQ — egyelőre csak a mailbox inbox.
    // en: aggregate CPU-attention IRQ — currently the mailbox inbox only.
    assign o_irq = o_irq_mailbox_in;

    // ============================================================
    // hu: Nano core / en: Nano core
    // ============================================================
    cilcpu_core #(
        .CODE_BASE_OFFSET (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE   (QE_INIT_ENABLE)
    ) u_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_boot_pc          (i_boot_pc),
        .i_boot_arg_count   (i_boot_arg_count),
        .i_boot_local_count (i_boot_local_count),
        .i_boot_start       (i_boot_start),
        .i_boot_arg_data    (i_boot_arg_data),
        .i_boot_arg_valid   (i_boot_arg_valid),
        .o_boot_arg_ready   (o_boot_arg_ready),
        .o_halt             (o_halt),
        .o_trap             (o_trap),
        .o_trap_code        (o_trap_code),
        .o_pc               (o_pc),
        .o_return_value     (o_return_value),
        .qspi_clk           (qspi_clk),
        .qspi_cs_flash_n    (qspi_cs_flash_n),
        .qspi_cs_psram_n    (qspi_cs_psram_n),
        .qspi_dq_out        (qspi_dq_out),
        .qspi_dq_in         (qspi_dq_in),
        .qspi_dq_oe         (qspi_dq_oe),
        .o_mmio_addr        (w_mmio_addr),
        .o_mmio_wdata       (w_mmio_wdata),
        .o_mmio_we          (w_mmio_we),
        .o_mmio_re          (w_mmio_re),
        .i_mmio_rdata       (w_mmio_rdata)
    );

    // ============================================================
    // hu: Mailbox (0xF000_0100) / en: Mailbox (0xF000_0100)
    // ============================================================
    cilcpu_mailbox #(
        .WIDTH (32),
        .DEPTH (8)
    ) u_mailbox (
        .clk                 (clk),
        .rst_n               (rst_n),
        .i_cpu_addr          (w_reg_off),
        .i_cpu_wdata         (w_mmio_wdata),
        .i_cpu_we            (w_mb_we),
        .i_cpu_re            (w_mb_re),
        .o_cpu_rdata         (w_mb_rdata),
        .i_host_inbox_wdata  (i_host_inbox_wdata),
        .i_host_inbox_push   (i_host_inbox_push),
        .o_host_outbox_rdata (o_host_outbox_rdata),
        .i_host_outbox_pop   (i_host_outbox_pop),
        .o_host_outbox_empty (o_host_outbox_empty),
        .o_host_inbox_full   (o_host_inbox_full),
        .o_irq_in            (o_irq_mailbox_in),
        .o_irq_out           (o_irq_mailbox_out)
    );

    // ============================================================
    // hu: GPIO (0xF000_0200) / en: GPIO (0xF000_0200)
    // ============================================================
    cilcpu_gpio #(
        .WIDTH (GPIO_WIDTH)
    ) u_gpio (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_cpu_addr  (w_reg_off),
        .i_cpu_wdata (w_mmio_wdata),
        .i_cpu_we    (w_gpio_we),
        .i_cpu_re    (w_gpio_re),
        .o_cpu_rdata (w_gpio_rdata),
        .i_gpio_in   (i_gpio_in),
        .o_gpio_out  (o_gpio_out),
        .o_gpio_oe   (o_gpio_oe)
    );

    // ============================================================
    // hu: Trace MUX (0xF000_0300). A jelölt belső jelcsoportok a core
    //     státusz-jelei — ciklus-pontos megfigyelés logikai analizátorral
    //     (a „következtetések" cél fő eszköze). 8 forrás × 8 bit.
    // en: Trace MUX (0xF000_0300). The candidate internal signal groups are
    //     the core's status signals — cycle-accurate observability with a
    //     logic analyzer. 8 sources × 8 bits.
    // ============================================================
    wire [TRACE_NSRC*TRACE_WIDTH-1:0] w_trace_sources = {
        8'hA5,                       // src7: marker
        o_return_value[15:8],        // src6
        {6'b0, o_trap, o_halt},      // src5: státusz
        o_trap_code,                 // src4
        o_return_value[7:0],         // src3
        o_pc[23:16],                 // src2
        o_pc[15:8],                  // src1
        o_pc[7:0]                    // src0
    };

    cilcpu_trace #(
        .WIDTH (TRACE_WIDTH),
        .NSRC  (TRACE_NSRC)
    ) u_trace (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_cpu_addr  (w_reg_off),
        .i_cpu_wdata (w_mmio_wdata),
        .i_cpu_we    (w_trace_we),
        .i_cpu_re    (w_trace_re),
        .o_cpu_rdata (w_trace_rdata),
        .i_sources   (w_trace_sources),
        .o_trace     (o_trace),
        .o_trace_mode (o_trace_mode)
    );

endmodule

`default_nettype wire
