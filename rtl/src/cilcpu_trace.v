// hu: CLI-CPU F2.8.5 — Trace MUX. Konfigurálható multiplexer: a CFG
//     regiszter (MMIO 0xF000_0300) kiválasztja, melyik belső jelcsoport
//     (NSRC darab, egyenként WIDTH bit) jelenjen meg a trace kimeneten.
//     A mode-bit jelzi a wrappernek, hogy a trace-t a GPIO kimenet fölé
//     mux-olja (mód-megosztott pinek). Ciklus-pontos belső megfigyelés
//     logikai analizátorral.
//     CFG regiszter (offset 0): bit[SEL_W-1:0] = forrás-select, bit[8] = mód.
// en: CLI-CPU F2.8.5 — Trace MUX. Configurable multiplexer: the CFG register
//     (MMIO 0xF000_0300) selects which internal signal group (NSRC groups of
//     WIDTH bits each) appears on the trace output. The mode bit tells the
//     wrapper to mux trace over the GPIO output (mode-shared pins).
//     Cycle-accurate internal observability with a logic analyzer.
//     CFG register (offset 0): bit[SEL_W-1:0] = source select, bit[8] = mode.

`default_nettype none

module cilcpu_trace #(
    parameter integer WIDTH = 8,
    parameter integer NSRC  = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: CPU MMIO slave
    input  wire [3:0]  i_cpu_addr,
    input  wire [31:0] i_cpu_wdata,
    input  wire        i_cpu_we,
    input  wire        i_cpu_re,
    output reg  [31:0] o_cpu_rdata,

    // hu: jelölt belső jelcsoportok (lapított: NSRC × WIDTH bit)
    // en: candidate internal signal groups (flattened: NSRC × WIDTH bits)
    input  wire [NSRC*WIDTH-1:0] i_sources,

    output wire [WIDTH-1:0] o_trace,
    output wire             o_trace_mode   // hu: 1 = trace aktív (wrapper mux)
);

    localparam integer SEL_W   = $clog2(NSRC);
    localparam [3:0]   OFF_CFG = 4'd0;
    localparam integer MODE_POS = 8;

    reg [SEL_W-1:0] r_sel;
    reg             r_mode;

    // hu: kiválasztott jelcsoport (változó indexű part-select)
    // en: selected signal group (variable indexed part-select)
    assign o_trace      = i_sources[r_sel*WIDTH +: WIDTH];
    assign o_trace_mode = r_mode;

    // hu: CFG visszaolvasási szó — sel az alsó bitekben, mode a MODE_POS-on.
    // en: CFG readback word — sel in the low bits, mode at MODE_POS.
    wire [31:0] w_cfg_rb =
        ({{(32-SEL_W){1'b0}}, r_sel}) | ({31'd0, r_mode} << MODE_POS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_sel       <= {SEL_W{1'b0}};
            r_mode      <= 1'b0;
            o_cpu_rdata <= 32'd0;
        end else begin
            if (i_cpu_we && (i_cpu_addr == OFF_CFG)) begin
                r_sel  <= i_cpu_wdata[SEL_W-1:0];
                r_mode <= i_cpu_wdata[MODE_POS];
            end

            if (i_cpu_re && (i_cpu_addr == OFF_CFG)) begin
                o_cpu_rdata <= w_cfg_rb;
            end
        end
    end

endmodule

`default_nettype wire
