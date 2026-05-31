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
    parameter integer CODE_BASE_OFFSET      = 0,
    parameter integer QE_INIT_ENABLE        = 0,
    parameter integer GPIO_WIDTH            = 8,
    parameter integer TRACE_WIDTH           = 8,
    parameter integer TRACE_NSRC            = 8,
    parameter integer UART_CLOCKS_PER_BAUD  = 434,
    parameter integer BOOT_AUTODETECT       = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Boot konfiguráció — KÜLSŐ forrás (a meglévő flash-boot tesztekhez).
    //     UART-boot esetén a belső loader felülírja (boot-mux, lásd lentebb).
    // en: Boot configuration — EXTERNAL source (for the existing flash-boot
    //     tests). On UART boot the internal loader overrides it (boot mux below).
    input  wire [23:0] i_boot_pc,
    input  wire [7:0]  i_boot_arg_count,
    input  wire [7:0]  i_boot_local_count,
    input  wire        i_boot_start,
    input  wire [31:0] i_boot_arg_data,
    input  wire        i_boot_arg_valid,
    output wire        o_boot_arg_ready,

    // hu: Boot-over-UART loader soros bemenete (idle = 1). F2.8 #6.5b-F1b.
    // en: Boot-over-UART loader serial input (idle = 1). F2.8 #6.5b-F1b.
    input  wire        i_uart_rx,

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
    // hu: Core külső-memória-master busza (a fázis-MUX-on át a QSPI-re).
    // en: Core external-memory master bus (through the phase MUX to the QSPI).
    wire [23:0] w_xmem_addr;
    wire        w_xmem_re;

    // ============================================================
    // hu: F1b — Boot-over-UART loader: uart_rx → cilcpu_uart_loader.
    // en: F1b — Boot-over-UART loader: uart_rx → cilcpu_uart_loader.
    // ============================================================
    wire [7:0]  w_ld_byte;
    wire        w_ld_byte_valid;
    wire [23:0] w_ld_mem_addr;
    wire [31:0] w_ld_mem_wdata;
    wire        w_ld_mem_we;
    wire        w_ld_boot_req;
    wire [23:0] w_ld_boot_pc;
    wire [7:0]  w_ld_boot_argc;
    wire [7:0]  w_ld_boot_localc;
    wire        w_ld_boot_code_src;
    wire        w_ld_busy;

    uart_rx #(
        .CLOCKS_PER_BAUD (UART_CLOCKS_PER_BAUD)
    ) u_uart_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_rx        (i_uart_rx),
        .o_data      (w_ld_byte),
        .o_valid     (w_ld_byte_valid),
        .o_frame_err ()
    );

    // hu: QSPI cpu_* visszacsatolás (a fázis-MUX mindkét mestere ezt látja).
    // en: QSPI cpu_* feedback (both phase-MUX masters see these).
    wire [31:0] w_qspi_cpu_rdata;
    wire        w_qspi_cpu_ready;
    wire        w_qspi_cpu_busy;

    cilcpu_uart_loader u_loader (
        .clk             (clk),
        .rst_n           (rst_n),
        .i_byte          (w_ld_byte),
        .i_byte_valid    (w_ld_byte_valid),
        .o_mem_addr      (w_ld_mem_addr),
        .o_mem_wdata     (w_ld_mem_wdata),
        .o_mem_we        (w_ld_mem_we),
        .i_mem_ready     (w_qspi_cpu_ready),
        .o_boot_req      (w_ld_boot_req),
        .o_boot_pc       (w_ld_boot_pc),
        .o_boot_argc     (w_ld_boot_argc),
        .o_boot_localc   (w_ld_boot_localc),
        .o_boot_code_src (w_ld_boot_code_src),
        .o_busy          (w_ld_busy)
    );

    // ============================================================
    // hu: F1c — flash auto-detect boot controller (BOOT_AUTODETECT-tel gated).
    //     Reset után (ha BOOT_AUTODETECT=1) beolvassa a flash header-szót és
    //     autonóm flash-boot-ot indít érvényes magic esetén. A QSPI-t a
    //     detect-fázisban birtokolja (w_bc_detect_active).
    // en: F1c — flash auto-detect boot controller (gated by BOOT_AUTODETECT).
    //     After reset (if BOOT_AUTODETECT=1) it reads the flash header word and
    //     starts an autonomous flash boot on valid magic. Owns the QSPI during
    //     the detect phase (w_bc_detect_active).
    // ============================================================
    wire [23:0] w_bc_mem_addr;
    wire        w_bc_mem_re;
    wire        w_bc_detect_active;
    wire        w_bc_boot_req;
    wire [23:0] w_bc_boot_pc;
    wire [7:0]  w_bc_boot_argc;
    wire [7:0]  w_bc_boot_localc;

    cilcpu_boot_ctrl #(
        .AUTODETECT (BOOT_AUTODETECT)
    ) u_boot_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .o_mem_addr      (w_bc_mem_addr),
        .o_mem_re        (w_bc_mem_re),
        .i_mem_rdata     (w_qspi_cpu_rdata),
        .i_mem_ready     (w_qspi_cpu_ready),
        .o_detect_active (w_bc_detect_active),
        .o_boot_req      (w_bc_boot_req),
        .o_boot_pc       (w_bc_boot_pc),
        .o_boot_argc     (w_bc_boot_argc),
        .o_boot_localc   (w_bc_boot_localc)
    );

    // ============================================================
    // hu: Fázis-MUX vezérlés. r_load_mode: a loader-aktivitásra (o_busy) 1, a
    //     BOOT-ra 0 (default 0 → a meglévő flash-boot tesztek érintetlenek).
    //     FONTOS: az o_busy a keret ELEJÉN (az első o_mem_we ELŐTT) megy magasra,
    //     így a fázis-MUX már az első írás-pulzusnál load-módban van (az o_mem_we
    //     1-ciklusos pulzusát nem kapuzná ki egy egy-ciklussal késő latch).
    //     r_code_src: a BOOT-kor latch-elt fetch-forrás (0=flash/SEG_CODE,
    //     1=PSRAM/SEG_STACK).
    // en: Phase-MUX control. r_load_mode: 1 on loader activity (o_busy), 0 on
    //     BOOT (default 0 → existing flash-boot tests unaffected). IMPORTANT:
    //     o_busy rises at the START of a frame (BEFORE the first o_mem_we), so
    //     the phase MUX is already in load mode for the first write pulse (a
    //     latch set one cycle late by o_mem_we would gate out the 1-cycle pulse).
    //     r_code_src: fetch source latched at BOOT (0=flash/SEG_CODE,
    //     1=PSRAM/SEG_STACK).
    // ============================================================
    reg  r_load_mode;
    reg  r_code_src;

    // hu: Belső boot-paraméterek latch-elése. A Core az i_boot_pc-t KÉTSZER
    //     olvassa (ST_RESET → r_pc, majd ST_BOOT → r_next_fetch_addr a
    //     következő ciklusban), ezért a boot-paramétereket STABILAN kell
    //     tartani, nem csak a 1-ciklusos boot_req pulzus alatt. Megoldás: a
    //     belső boot forrás (boot_ctrl / loader) paramétereit latch-eljük
    //     (r_lat_*) és a core boot-start-ját egy ciklussal eltoljuk
    //     (r_int_boot_start), hogy a start a stabil latch után pulzáljon. A
    //     külső i_boot_* utat (a meglévő tesztek) a r_int_boot_pending=0 ág
    //     hagyja érintetlenül.
    // en: Internal boot-parameter latching. The Core reads i_boot_pc TWICE
    //     (ST_RESET → r_pc, then ST_BOOT → r_next_fetch_addr in the next
    //     cycle), so the boot params must be held STABLE, not only during the
    //     1-cycle boot_req pulse. Solution: latch the internal boot source's
    //     (boot_ctrl / loader) params (r_lat_*) and shift the core boot-start
    //     by one cycle (r_int_boot_start) so start pulses after the stable
    //     latch. The external i_boot_* path (existing tests) is untouched via
    //     the r_int_boot_pending=0 branch.
    reg        r_int_boot_pending;
    reg        r_int_boot_start;
    reg [23:0] r_lat_pc;
    reg [7:0]  r_lat_argc;
    reg [7:0]  r_lat_localc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_load_mode        <= 1'b0;
            r_code_src         <= 1'b0;
            r_int_boot_pending <= 1'b0;
            r_int_boot_start   <= 1'b0;
            r_lat_pc           <= 24'd0;
            r_lat_argc         <= 8'd0;
            r_lat_localc       <= 8'd0;
        end else begin
            r_int_boot_start <= 1'b0;   // hu: eltolt start pulzus alaphelyzet

            if (w_bc_boot_req) begin
                // hu: autonóm flash-boot → code_src = flash (SEG_CODE)
                r_load_mode        <= 1'b0;
                r_code_src         <= 1'b0;
                r_lat_pc           <= w_bc_boot_pc;
                r_lat_argc         <= w_bc_boot_argc;
                r_lat_localc       <= w_bc_boot_localc;
                r_int_boot_pending <= 1'b1;
                r_int_boot_start   <= 1'b1;   // hu: a KÖVETKEZŐ ciklusban pulzál
            end else if (w_ld_boot_req) begin
                r_load_mode        <= 1'b0;
                r_code_src         <= w_ld_boot_code_src;
                r_lat_pc           <= w_ld_boot_pc;
                r_lat_argc         <= w_ld_boot_argc;
                r_lat_localc       <= w_ld_boot_localc;
                r_int_boot_pending <= 1'b1;
                r_int_boot_start   <= 1'b1;
            end else if (w_ld_busy) begin
                r_load_mode <= 1'b1;
            end
        end
    end

    // hu: Run-fázis cím-szegmens remap a code_src szerint — a Core eszköz-
    //     agnosztikus [19:0] CODE-címteret használ; a SoC teszi rá a szegmenst.
    // en: Run-phase address segment remap by code_src — the Core uses a device-
    //     agnostic [19:0] CODE space; the SoC applies the segment.
    wire [3:0] w_core_seg = r_code_src ? `SEG_STACK : `SEG_CODE;

    // hu: 3-way fázis-MUX a QSPI cpu_* bemenetein. Prioritás:
    //     detect (boot_ctrl header-olvasás) > load (loader PSRAM-írás) > run (core).
    // en: 3-way phase MUX on the QSPI cpu_* inputs. Priority:
    //     detect (boot_ctrl header read) > load (loader PSRAM write) > run (core).
    wire [23:0] w_qspi_cpu_addr  = w_bc_detect_active ? w_bc_mem_addr  :
                                   r_load_mode        ? w_ld_mem_addr  :
                                       {w_core_seg, w_xmem_addr[19:0]};
    wire [31:0] w_qspi_cpu_wdata = r_load_mode ? w_ld_mem_wdata : 32'd0;
    wire        w_qspi_cpu_we    = (!w_bc_detect_active && r_load_mode) ? w_ld_mem_we : 1'b0;
    wire        w_qspi_cpu_re    = w_bc_detect_active ? w_bc_mem_re :
                                   r_load_mode        ? 1'b0        :
                                                        w_xmem_re;

    // hu: Boot-mux — belső boot (r_int_boot_pending: boot_ctrl/loader, latch-elt
    //     és STABIL paraméterek) VAGY külső i_boot_* (a meglévő tesztek). A start
    //     belül a latch utáni eltolt pulzus (r_int_boot_start), kívül i_boot_start.
    //     Az arg-streaming a külső portokról jön (belső boot argc a latch-ből,
    //     args nem streamelt → argc=0 elvárt belső bootnál).
    // en: Boot mux — internal boot (r_int_boot_pending: boot_ctrl/loader, latched
    //     and STABLE params) OR external i_boot_* (existing tests). Internal
    //     start is the post-latch shifted pulse (r_int_boot_start), external is
    //     i_boot_start. Arg streaming comes from the external ports (internal
    //     boot argc from the latch, args not streamed → argc=0 expected).
    wire [23:0] w_core_boot_pc    = r_int_boot_pending ? r_lat_pc     : i_boot_pc;
    wire [7:0]  w_core_boot_argc  = r_int_boot_pending ? r_lat_argc   : i_boot_arg_count;
    wire [7:0]  w_core_boot_lcnt  = r_int_boot_pending ? r_lat_localc : i_boot_local_count;
    wire        w_core_boot_start = i_boot_start | r_int_boot_start;

    cilcpu_core u_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_boot_pc          (w_core_boot_pc),
        .i_boot_arg_count   (w_core_boot_argc),
        .i_boot_local_count (w_core_boot_lcnt),
        .i_boot_start       (w_core_boot_start),
        .i_boot_arg_data    (i_boot_arg_data),
        .i_boot_arg_valid   (i_boot_arg_valid),
        .o_boot_arg_ready   (o_boot_arg_ready),
        .o_halt             (o_halt),
        .o_trap             (o_trap),
        .o_trap_code        (o_trap_code),
        .o_pc               (o_pc),
        .o_return_value     (o_return_value),
        .o_xmem_addr        (w_xmem_addr),
        .o_xmem_re          (w_xmem_re),
        .i_xmem_rdata       (w_qspi_cpu_rdata),
        .i_xmem_ready       (w_qspi_cpu_ready),
        .i_xmem_busy        (w_qspi_cpu_busy),
        .o_mmio_addr        (w_mmio_addr),
        .o_mmio_wdata       (w_mmio_wdata),
        .o_mmio_we          (w_mmio_we),
        .o_mmio_re          (w_mmio_re),
        .i_mmio_rdata       (w_mmio_rdata)
    );

    // hu: SoC-szintű QSPI controller — a fázis-MUX-on át a loader (write, load)
    //     vagy a Core (read, run) hajtja.
    // en: SoC-level QSPI controller — driven via the phase MUX by the loader
    //     (write, load) or the Core (read, run).
    cilcpu_qspi_controller #(
        .CODE_BASE_OFFSET (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE   (QE_INIT_ENABLE)
    ) u_qspi (
        .clk             (clk),
        .rst_n           (rst_n),
        .cpu_addr        (w_qspi_cpu_addr),
        .cpu_wdata       (w_qspi_cpu_wdata),
        .cpu_rdata       (w_qspi_cpu_rdata),
        .cpu_re          (w_qspi_cpu_re),
        .cpu_we          (w_qspi_cpu_we),
        .cpu_ready       (w_qspi_cpu_ready),
        .cpu_busy        (w_qspi_cpu_busy),
        .qspi_clk        (qspi_clk),
        .qspi_cs_flash_n (qspi_cs_flash_n),
        .qspi_cs_psram_n (qspi_cs_psram_n),
        .qspi_dq_out     (qspi_dq_out),
        .qspi_dq_in      (qspi_dq_in),
        .qspi_dq_oe      (qspi_dq_oe)
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
