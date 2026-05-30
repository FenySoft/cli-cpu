// hu: CLI-CPU F2.8.4 — GPIO MMIO blokk. A CIL-T0 aktor MMIO-n keresztül
//     olvas bemeneti pineket és hajt kimeneteket; az irányt az OE regiszter
//     szabja (1 = kimenet hajtva). A bemeneti pinek 2-FF szinkronizeren
//     mennek át (aszinkron külső jelek metastabilitás-védelme). Registered
//     read (1-ciklus latencia). MMIO bázis: 0xF000_0200.
//     Regiszterek (szó-offszet): 0 = GPIO_IN (RO, szinkronizált bemenet),
//     1 = GPIO_OUT (RW, kimeneti érték), 2 = GPIO_OE (RW, irány/oe).
// en: CLI-CPU F2.8.4 — GPIO MMIO block. The CIL-T0 actor reads input pins
//     and drives outputs via MMIO; direction set by the OE register (1 =
//     output driven). Input pins pass through a 2-FF synchronizer (async
//     external signal metastability protection). Registered read (1-cycle
//     latency). MMIO base: 0xF000_0200.
//     Registers (word offset): 0 = GPIO_IN (RO, synchronized input),
//     1 = GPIO_OUT (RW, output value), 2 = GPIO_OE (RW, direction/oe).

`default_nettype none

module cilcpu_gpio #(
    parameter integer WIDTH = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: CPU MMIO slave (szó-offszet)
    input  wire [3:0]  i_cpu_addr,
    input  wire [31:0] i_cpu_wdata,
    input  wire        i_cpu_we,
    input  wire        i_cpu_re,
    output reg  [31:0] o_cpu_rdata,

    // hu: Fizikai pinek / en: Physical pins
    input  wire [WIDTH-1:0] i_gpio_in,
    output wire [WIDTH-1:0] o_gpio_out,
    output wire [WIDTH-1:0] o_gpio_oe
);

    localparam [3:0] OFF_IN  = 4'd0;
    localparam [3:0] OFF_OUT = 4'd1;
    localparam [3:0] OFF_OE  = 4'd2;

    reg [WIDTH-1:0] r_out;
    reg [WIDTH-1:0] r_oe;

    // hu: 2-FF szinkronizer a bemeneti pinekre / en: 2-FF input synchronizer
    reg [WIDTH-1:0] r_in_meta;
    reg [WIDTH-1:0] r_in_sync;

    assign o_gpio_out = r_out;
    assign o_gpio_oe  = r_oe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_out       <= {WIDTH{1'b0}};
            r_oe        <= {WIDTH{1'b0}};
            r_in_meta   <= {WIDTH{1'b0}};
            r_in_sync   <= {WIDTH{1'b0}};
            o_cpu_rdata <= 32'd0;
        end else begin
            // hu: szinkronizer-lánc
            r_in_meta <= i_gpio_in;
            r_in_sync <= r_in_meta;

            // hu: MMIO írás
            if (i_cpu_we) begin
                case (i_cpu_addr)
                    OFF_OUT: r_out <= i_cpu_wdata[WIDTH-1:0];
                    OFF_OE:  r_oe  <= i_cpu_wdata[WIDTH-1:0];
                    default: ;   // GPIO_IN írása no-op
                endcase
            end

            // hu: MMIO registered read
            if (i_cpu_re) begin
                case (i_cpu_addr)
                    OFF_IN:  o_cpu_rdata <= {{(32-WIDTH){1'b0}}, r_in_sync};
                    OFF_OUT: o_cpu_rdata <= {{(32-WIDTH){1'b0}}, r_out};
                    OFF_OE:  o_cpu_rdata <= {{(32-WIDTH){1'b0}}, r_oe};
                    default: o_cpu_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
