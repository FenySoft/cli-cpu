// hu: CLI-CPU F2.7 Sub2 — egyszerű UART transmitter (TX-only).
//     Konfigurálható baud-rate (CLOCKS_PER_BAUD), 8N1 keret (1 start + 8 data
//     + 1 stop). Egy byte-os interfész: i_data + i_start. A modul NEM
//     pufferel — magasabb szintű állapotgép adagolja a byte-okat.
// en: CLI-CPU F2.7 Sub2 — simple UART transmitter (TX-only). Configurable
//     baud rate (CLOCKS_PER_BAUD), 8N1 frame (1 start + 8 data + 1 stop).
//     Single-byte interface: i_data + i_start. The module does NOT buffer —
//     a higher-level FSM feeds bytes one at a time.

`default_nettype none

module uart_tx #(
    // hu: 50 MHz / 115200 baud = 434 (kerekítve). Sim-ben felülírható
    //     gyors verifikációhoz.
    // en: 50 MHz / 115200 baud = 434 (rounded). Sim may override for
    //     faster verification.
    parameter integer CLOCKS_PER_BAUD = 434
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  i_data,    // hu: küldendő byte / en: byte to transmit
    input  wire        i_start,   // hu: 1-cycle pulse → adás indul
    output wire        o_busy,    // hu: adás folyamatban
    output reg         o_tx       // hu: soros kimenet (idle = 1)
);

    // hu: FSM állapotok / en: FSM states
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_DATA  = 2'd2;
    localparam [1:0] S_STOP  = 2'd3;

    reg  [1:0]  r_state;
    reg  [15:0] r_baud_cnt;     // hu: a baud-osztó számláló / en: baud divider counter
    reg  [2:0]  r_bit_idx;      // hu: 0..7 az adat bitekhez / en: 0..7 for data bits
    reg  [7:0]  r_shift;        // hu: shift regiszter (LSB-first) / en: shift register

    wire baud_tick = (r_baud_cnt == 16'd0);

    assign o_busy = (r_state != S_IDLE) || i_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state    <= S_IDLE;
            r_baud_cnt <= 16'd0;
            r_bit_idx  <= 3'd0;
            r_shift    <= 8'd0;
            o_tx       <= 1'b1;     // hu: idle = magas / en: idle = high
        end else begin
            case (r_state)
                S_IDLE: begin
                    o_tx <= 1'b1;
                    if (i_start) begin
                        r_shift    <= i_data;
                        r_baud_cnt <= CLOCKS_PER_BAUD[15:0] - 16'd1;
                        r_bit_idx  <= 3'd0;
                        r_state    <= S_START;
                        o_tx       <= 1'b0;     // hu: start bit / en: start bit
                    end
                end

                S_START: begin
                    if (baud_tick) begin
                        r_baud_cnt <= CLOCKS_PER_BAUD[15:0] - 16'd1;
                        r_state    <= S_DATA;
                        o_tx       <= r_shift[0];
                    end else begin
                        r_baud_cnt <= r_baud_cnt - 16'd1;
                    end
                end

                S_DATA: begin
                    if (baud_tick) begin
                        r_baud_cnt <= CLOCKS_PER_BAUD[15:0] - 16'd1;
                        if (r_bit_idx == 3'd7) begin
                            r_state <= S_STOP;
                            o_tx    <= 1'b1;     // hu: stop bit / en: stop bit
                        end else begin
                            r_shift   <= {1'b0, r_shift[7:1]};
                            r_bit_idx <= r_bit_idx + 3'd1;
                            o_tx      <= r_shift[1];   // hu: a következő bit
                        end
                    end else begin
                        r_baud_cnt <= r_baud_cnt - 16'd1;
                    end
                end

                S_STOP: begin
                    if (baud_tick) begin
                        r_state <= S_IDLE;
                    end else begin
                        r_baud_cnt <= r_baud_cnt - 16'd1;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
