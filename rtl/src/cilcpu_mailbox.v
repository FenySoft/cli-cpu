// hu: CLI-CPU F2.8.3 — Mailbox: két 8-mély FIFO (inbox: host→CPU, outbox:
//     CPU→host) + MMIO slave interfész + IRQ. A CFPU üzenet-primitív
//     hardvere. A CPU MMIO-n keresztül olvas az inboxból (registered read,
//     1-ciklus latencia; az olvasás popol) és ír az outboxba (a write
//     push-ol). A host a túloldalt hajtja. IRQ: o_irq_in = inbox nem üres
//     (a CPU-nak van olvasnivalója), o_irq_out = outbox nem üres (a hostnak
//     van olvasnivalója). MMIO bázis: 0xF000_0100 (lásd cilcpu_defines.vh).
// en: CLI-CPU F2.8.3 — Mailbox: two 8-deep FIFOs (inbox: host→CPU, outbox:
//     CPU→host) + MMIO slave + IRQ. Hardware for the CFPU message primitive.
//     The CPU reads the inbox via MMIO (registered read, 1-cycle latency; the
//     read pops) and writes the outbox (the write pushes). The host drives
//     the other side. IRQ: o_irq_in = inbox not empty (CPU has mail),
//     o_irq_out = outbox not empty (host has mail). MMIO base: 0xF000_0100.

`default_nettype none

module cilcpu_mailbox #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 8
) (
    input  wire             clk,
    input  wire             rst_n,

    // hu: CPU MMIO slave (szó-offszet) / en: CPU MMIO slave (word offset)
    input  wire [3:0]       i_cpu_addr,
    input  wire [WIDTH-1:0] i_cpu_wdata,
    input  wire             i_cpu_we,
    input  wire             i_cpu_re,
    output reg  [WIDTH-1:0] o_cpu_rdata,

    // hu: Host oldal / en: Host side
    input  wire [WIDTH-1:0] i_host_inbox_wdata,
    input  wire             i_host_inbox_push,
    output wire [WIDTH-1:0] o_host_outbox_rdata,
    input  wire             i_host_outbox_pop,
    output wire             o_host_outbox_empty,
    output wire             o_host_inbox_full,

    // hu: Megszakítások / en: Interrupts
    output wire             o_irq_in,    // hu: inbox nem üres (CPU figyelem)
    output wire             o_irq_out    // hu: outbox nem üres (host figyelem)
);

    // hu: MMIO szó-offszetek / en: MMIO word offsets
    localparam [3:0] OFF_INBOX  = 4'd0;   // CPU read → pop inbox
    localparam [3:0] OFF_OUTBOX = 4'd1;   // CPU write → push outbox
    localparam [3:0] OFF_STATUS = 4'd2;   // CPU read → flags

    wire             w_inbox_empty,  w_inbox_full;
    wire             w_outbox_empty, w_outbox_full;
    wire [WIDTH-1:0] w_inbox_head,   w_outbox_head;

    // hu: a CPU az inbox-olvasáskor popol, az outbox-íráskor push-ol.
    // en: the CPU pops on inbox read, pushes on outbox write.
    wire w_cpu_pop_inbox   = i_cpu_re && (i_cpu_addr == OFF_INBOX)  && !w_inbox_empty;
    wire w_cpu_push_outbox = i_cpu_we && (i_cpu_addr == OFF_OUTBOX) && !w_outbox_full;

    // hu: inbox — host push, CPU pop
    cilcpu_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_inbox (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_wdata (i_host_inbox_wdata),
        .i_push  (i_host_inbox_push),
        .o_rdata (w_inbox_head),
        .i_pop   (w_cpu_pop_inbox),
        .o_empty (w_inbox_empty),
        .o_full  (w_inbox_full),
        .o_count ()
    );

    // hu: outbox — CPU push, host pop
    cilcpu_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_outbox (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_wdata (i_cpu_wdata),
        .i_push  (w_cpu_push_outbox),
        .o_rdata (w_outbox_head),
        .i_pop   (i_host_outbox_pop),
        .o_empty (w_outbox_empty),
        .o_full  (w_outbox_full),
        .o_count ()
    );

    assign o_host_outbox_rdata = w_outbox_head;
    assign o_host_outbox_empty = w_outbox_empty;
    assign o_host_inbox_full   = w_inbox_full;
    assign o_irq_in  = !w_inbox_empty;
    assign o_irq_out = !w_outbox_empty;

    // hu: STATUS szó — bit0 inbox_empty, bit1 inbox_full, bit2 outbox_empty,
    //     bit3 outbox_full.
    // en: STATUS word — bit0 inbox_empty, bit1 inbox_full, bit2 outbox_empty,
    //     bit3 outbox_full.
    wire [WIDTH-1:0] w_status = {
        {(WIDTH-4){1'b0}},
        w_outbox_full, w_outbox_empty, w_inbox_full, w_inbox_empty
    };

    // hu: registered read — az inbox FWFT feje (= a popolt érték) vagy STATUS.
    // en: registered read — the inbox FWFT head (= the popped value) or STATUS.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_cpu_rdata <= {WIDTH{1'b0}};
        end else if (i_cpu_re) begin
            case (i_cpu_addr)
                OFF_INBOX:  o_cpu_rdata <= w_inbox_head;
                OFF_STATUS: o_cpu_rdata <= w_status;
                default:    o_cpu_rdata <= {WIDTH{1'b0}};
            endcase
        end
    end

endmodule

`default_nettype wire
