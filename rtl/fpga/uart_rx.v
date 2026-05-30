// hu: CLI-CPU F2.8.1 — egyszerű UART receiver (RX-only). Konfigurálható
//     baud-rate (CLOCKS_PER_BAUD), 8N1 keret (1 start + 8 data LSB-first +
//     1 stop). A start-bit lefutó élének detektálása után fél-baud-dal a
//     bit-középre igazít, majd baud-onként mintavételezi a 8 adatbitet és a
//     stop-bitet. Az aszinkron i_rx-et 2-FF szinkronizer viszi a clk
//     domainbe (metastabilitás-védelem). Egy-byte-os kimenet: o_data +
//     o_valid (1-ciklusos pulzus); o_frame_err ha a stop-bit nem 1.
//     A modul NEM pufferel — magasabb szintű FSM (loader) olvassa a byte-okat.
// en: CLI-CPU F2.8.1 — simple UART receiver (RX-only). Configurable baud
//     rate (CLOCKS_PER_BAUD), 8N1 frame (1 start + 8 data LSB-first + 1
//     stop). After detecting the start-bit falling edge, aligns to bit
//     center with a half-baud delay, then samples the 8 data bits and the
//     stop bit at each baud. The async i_rx is brought into the clk domain
//     by a 2-FF synchronizer (metastability protection). Single-byte output:
//     o_data + o_valid (1-cycle pulse); o_frame_err if the stop bit is not 1.
//     The module does NOT buffer — a higher-level FSM (loader) reads bytes.

`default_nettype none

module uart_rx #(
    // hu: 50 MHz / 115200 baud = 434 (kerekítve). Sim-ben felülírható.
    // en: 50 MHz / 115200 baud = 434 (rounded). Sim may override.
    parameter integer CLOCKS_PER_BAUD = 434
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       i_rx,         // hu: soros bemenet (idle = 1)
    output reg  [7:0] o_data,       // hu: vett byte
    output reg        o_valid,      // hu: 1-ciklusos pulzus, byte kész
    output reg        o_frame_err   // hu: stop-bit != 1 (a vett byte mellett)
);

    // hu: FSM állapotok / en: FSM states
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_DATA  = 2'd2;
    localparam [1:0] S_STOP  = 2'd3;

    // hu: 2-FF szinkronizer az aszinkron i_rx-re.
    // en: 2-FF synchronizer for the async i_rx.
    reg r_rx_meta;
    reg r_rx_sync;

    reg [1:0]  r_state;
    reg [15:0] r_baud_cnt;     // hu: baud-osztó számláló
    reg [2:0]  r_bit_idx;      // hu: 0..7 adatbit index
    reg [7:0]  r_shift;        // hu: shift regiszter (LSB-first)

    wire baud_tick = (r_baud_cnt == 16'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_rx_meta   <= 1'b1;
            r_rx_sync   <= 1'b1;
            r_state     <= S_IDLE;
            r_baud_cnt  <= 16'd0;
            r_bit_idx   <= 3'd0;
            r_shift     <= 8'd0;
            o_data      <= 8'd0;
            o_valid     <= 1'b0;
            o_frame_err <= 1'b0;
        end else begin
            // hu: szinkronizer-lánc / en: synchronizer chain
            r_rx_meta <= i_rx;
            r_rx_sync <= r_rx_meta;

            o_valid <= 1'b0;   // hu: alapból 0; S_STOP 1 ciklusra emeli

            case (r_state)

                // ----------------------------------------------------
                // hu: Idle — start-bit (lefutó él) detektálása.
                // en: Idle — detect start bit (falling edge).
                S_IDLE: begin
                    if (r_rx_sync == 1'b0) begin
                        // hu: fél-baud a start-bit közepére igazításhoz
                        // en: half-baud to align to start-bit center
                        r_baud_cnt <= (CLOCKS_PER_BAUD[15:0] >> 1) - 16'd1;
                        r_state    <= S_START;
                    end
                end

                // ----------------------------------------------------
                // hu: Start-bit közepén ellenőrzés (glitch-szűrés).
                // en: Verify at start-bit center (glitch filter).
                S_START: begin
                    if (baud_tick) begin
                        if (r_rx_sync == 1'b0) begin
                            // hu: valódi start → 1. data bit egy teljes baud múlva
                            r_baud_cnt <= CLOCKS_PER_BAUD[15:0] - 16'd1;
                            r_bit_idx  <= 3'd0;
                            r_state    <= S_DATA;
                        end else begin
                            r_state <= S_IDLE;   // hu: glitch → vissza
                        end
                    end else begin
                        r_baud_cnt <= r_baud_cnt - 16'd1;
                    end
                end

                // ----------------------------------------------------
                // hu: 8 adatbit mintavétele bit-középen, LSB-first.
                // en: Sample 8 data bits at bit center, LSB-first.
                S_DATA: begin
                    if (baud_tick) begin
                        r_shift[r_bit_idx] <= r_rx_sync;
                        r_baud_cnt <= CLOCKS_PER_BAUD[15:0] - 16'd1;
                        if (r_bit_idx == 3'd7)
                            r_state <= S_STOP;
                        else
                            r_bit_idx <= r_bit_idx + 3'd1;
                    end else begin
                        r_baud_cnt <= r_baud_cnt - 16'd1;
                    end
                end

                // ----------------------------------------------------
                // hu: Stop-bit mintavétel + kimenet. o_valid 1 ciklusra.
                // en: Sample stop bit + output. o_valid pulses 1 cycle.
                S_STOP: begin
                    if (baud_tick) begin
                        o_data      <= r_shift;
                        o_frame_err <= ~r_rx_sync;   // hu: stop != 1 → hiba
                        o_valid     <= 1'b1;
                        r_state     <= S_IDLE;
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
