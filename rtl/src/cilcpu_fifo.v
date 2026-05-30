// hu: CLI-CPU F2.8.3a — generikus szinkron FIFO (körkörös puffer).
//     Paraméterezhető WIDTH és DEPTH (DEPTH kettő-hatvány). Egyórajeles,
//     first-word-fall-through olvasás (o_rdata = a sor feje, kombinációs).
//     Egyidejű push+pop megengedett (count változatlan). A Mailbox inbox és
//     outbox FIFO-ja ebből épül; a UART-loader is használhatja.
// en: CLI-CPU F2.8.3a — generic synchronous FIFO (circular buffer).
//     Parameterizable WIDTH and DEPTH (DEPTH a power of two). Single clock,
//     first-word-fall-through read (o_rdata = queue head, combinational).
//     Simultaneous push+pop allowed (count unchanged). The Mailbox inbox and
//     outbox FIFOs are built from this; the UART loader may use it too.

`default_nettype none

module cilcpu_fifo #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 8        // hu: kettő-hatvány / en: power of two
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire [WIDTH-1:0] i_wdata,
    input  wire             i_push,    // hu: push (csak ha !full)
    output wire [WIDTH-1:0] o_rdata,   // hu: a sor feje (érvényes ha !empty)
    input  wire             i_pop,     // hu: pop (csak ha !empty)

    output wire                    o_empty,
    output wire                    o_full,
    output wire [$clog2(DEPTH):0]  o_count
);

    localparam integer PTR_W = $clog2(DEPTH);

    reg [WIDTH-1:0] r_mem [0:DEPTH-1];
    reg [PTR_W-1:0] r_wr_ptr;
    reg [PTR_W-1:0] r_rd_ptr;
    reg [PTR_W:0]   r_count;

    assign o_empty = (r_count == {(PTR_W+1){1'b0}});
    assign o_full  = (r_count == DEPTH[PTR_W:0]);
    assign o_count = r_count;
    assign o_rdata = r_mem[r_rd_ptr];

    // hu: tényleges műveletek — full-ben push, empty-ben pop tiltva.
    // en: effective ops — push blocked when full, pop blocked when empty.
    wire w_do_push = i_push && !o_full;
    wire w_do_pop  = i_pop  && !o_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_wr_ptr <= {PTR_W{1'b0}};
            r_rd_ptr <= {PTR_W{1'b0}};
            r_count  <= {(PTR_W+1){1'b0}};
            // hu: r_mem nem reset-elt (BRAM-szerű); a count védi az olvasást.
        end else begin
            if (w_do_push) begin
                r_mem[r_wr_ptr] <= i_wdata;
                r_wr_ptr <= r_wr_ptr + 1'b1;
            end

            if (w_do_pop) begin
                r_rd_ptr <= r_rd_ptr + 1'b1;
            end

            // hu: count — egyidejű push+pop esetén változatlan.
            // en: count — unchanged on simultaneous push+pop.
            case ({w_do_push, w_do_pop})
                2'b10:   r_count <= r_count + 1'b1;
                2'b01:   r_count <= r_count - 1'b1;
                default: r_count <= r_count;
            endcase
        end
    end

endmodule

`default_nettype wire
