// hu: CLI-CPU F2.7 Sub2 — 32-bit signed integer → ASCII decimális → UART
//     printer. Belül egy `uart_tx` példányt vezérel: minden számjegyet
//     elhelyez egy belső 11-byte bufferbe (max '-2147483648' = 11 char),
//     majd byte-onként kiküldi UART-ra. Egy CR/LF (`\r\n`) zárja a sort.
// en: CLI-CPU F2.7 Sub2 — 32-bit signed integer → ASCII decimal → UART
//     printer. Internally drives a `uart_tx` instance: each digit is placed
//     into an 11-byte buffer (max '-2147483648' = 11 chars) and sent over
//     UART byte by byte. A CR/LF (`\r\n`) terminates the line.

`default_nettype none

module decimal_printer #(
    parameter integer CLOCKS_PER_BAUD = 434
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] i_value,    // hu: kiírandó érték / en: value to print
    input  wire        i_signed,   // hu: 1 = signed (negatív → '-'), 0 = unsigned hex-szerű (de decimális)
    input  wire        i_start,    // hu: 1-cycle pulse → indítás
    output reg         o_busy,     // hu: kiírás folyamatban
    output wire        o_tx        // hu: soros kimenet
);

    // hu: FSM állapotok / en: FSM states
    localparam [3:0] S_IDLE      = 4'd0;
    localparam [3:0] S_PREP      = 4'd1;   // hu: signed kezelés, abs érték
    localparam [3:0] S_DIVIDE    = 4'd2;   // hu: % 10 → digit, / 10 → következő
    localparam [3:0] S_PUSH_SIGN = 4'd3;   // hu: '-' beillesztése (signed esetén)
    localparam [3:0] S_SEND_REQ  = 4'd4;   // hu: i_start a uart_tx-re
    localparam [3:0] S_SEND_WAIT = 4'd5;   // hu: vár a uart_tx busy-jára
    localparam [3:0] S_SEND_CR   = 4'd6;
    localparam [3:0] S_SEND_LF   = 4'd7;
    localparam [3:0] S_DONE      = 4'd8;

    reg  [3:0]  r_state;
    reg  [31:0] r_abs;          // hu: |i_value| / en: |i_value|
    reg         r_negative;
    reg  [3:0]  r_digit_count;  // hu: 0..10 / en: 0..10

    // hu: 11 db ASCII karakter buffer ('-' + 10 digit a 2^31-hez)
    // en: 11-byte ASCII buffer ('-' + 10 digits for 2^31)
    reg  [7:0]  r_buf [0:10];
    reg  [3:0]  r_send_idx;
    reg  [3:0]  r_send_max;

    reg  [7:0]  r_tx_data;
    reg         r_tx_start;
    wire        w_tx_busy;

    uart_tx #(.CLOCKS_PER_BAUD(CLOCKS_PER_BAUD)) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_data  (r_tx_data),
        .i_start (r_tx_start),
        .o_busy  (w_tx_busy),
        .o_tx    (o_tx)
    );

    // hu: Egyszerű egylépéses divide-by-10 (kombinációs). Sim-ben elfogadott;
    //     Yosys/Vivado-n DSP-be vagy LUT-okba szintetizálódik (Sub5-ben
    //     mérjük a területet).
    // en: Simple one-step divide-by-10 (combinational). Accepted in sim;
    //     synthesized to DSP or LUTs by Yosys/Vivado (area measured in Sub5).
    wire [31:0] w_div10  = r_abs / 32'd10;
    wire [31:0] w_mod10  = r_abs - (w_div10 * 32'd10);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state       <= S_IDLE;
            r_abs         <= 32'd0;
            r_negative    <= 1'b0;
            r_digit_count <= 4'd0;
            r_send_idx    <= 4'd0;
            r_send_max    <= 4'd0;
            r_tx_data     <= 8'd0;
            r_tx_start    <= 1'b0;
            o_busy        <= 1'b0;
            for (i = 0; i < 11; i = i + 1)
                r_buf[i] <= 8'd0;
        end else begin
            r_tx_start <= 1'b0;

            case (r_state)
                S_IDLE: begin
                    o_busy <= 1'b0;
                    if (i_start) begin
                        o_busy        <= 1'b1;
                        r_negative    <= i_signed && i_value[31];
                        r_abs         <= (i_signed && i_value[31])
                                           ? (~i_value + 32'd1)
                                           : i_value;
                        r_digit_count <= 4'd0;
                        r_state       <= S_PREP;
                    end
                end

                S_PREP: begin
                    // hu: A 0 érték speciális — még a divide előtt kiadunk egy '0'-t
                    // en: Zero is special — push a single '0' before dividing
                    if (r_abs == 32'd0) begin
                        r_buf[0]      <= 8'h30;       // '0'
                        r_digit_count <= 4'd1;
                        r_state       <= S_PUSH_SIGN;
                    end else begin
                        r_state <= S_DIVIDE;
                    end
                end

                S_DIVIDE: begin
                    // hu: r_buf-ba LSB digit (jobbról balra építjük)
                    // en: write LSB digit into r_buf (right-to-left)
                    r_buf[r_digit_count] <= 8'h30 + w_mod10[7:0];   // ASCII '0'..'9'
                    r_abs                <= w_div10;
                    r_digit_count        <= r_digit_count + 4'd1;
                    if (w_div10 == 32'd0)
                        r_state <= S_PUSH_SIGN;
                end

                S_PUSH_SIGN: begin
                    // hu: Negatív → még egy '-' a digit_count utáni pozícióba
                    // en: Negative → push '-' at position digit_count
                    if (r_negative) begin
                        r_buf[r_digit_count] <= 8'h2D;             // '-'
                        r_send_max           <= r_digit_count;     // index of last digit
                        r_send_idx           <= r_digit_count;     // start with '-' (highest index)
                    end else begin
                        r_send_max <= r_digit_count - 4'd1;
                        r_send_idx <= r_digit_count - 4'd1;
                    end
                    r_state <= S_SEND_REQ;
                end

                S_SEND_REQ: begin
                    // hu: Aktuális karakter a TX-re
                    // en: Current char to TX
                    r_tx_data  <= r_buf[r_send_idx];
                    r_tx_start <= 1'b1;
                    r_state    <= S_SEND_WAIT;
                end

                S_SEND_WAIT: begin
                    // hu: Várjuk meg a TX busy felfutását, majd a leesést
                    // en: Wait for TX busy to rise, then fall
                    if (!w_tx_busy && !r_tx_start) begin
                        if (r_send_idx == 4'd0) begin
                            r_state <= S_SEND_CR;
                        end else begin
                            r_send_idx <= r_send_idx - 4'd1;
                            r_state    <= S_SEND_REQ;
                        end
                    end
                end

                S_SEND_CR: begin
                    r_tx_data  <= 8'h0D;     // '\r'
                    r_tx_start <= 1'b1;
                    r_state    <= S_SEND_LF;
                end

                S_SEND_LF: begin
                    if (!w_tx_busy && !r_tx_start) begin
                        r_tx_data  <= 8'h0A; // '\n'
                        r_tx_start <= 1'b1;
                        r_state    <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (!w_tx_busy && !r_tx_start) begin
                        o_busy  <= 1'b0;
                        r_state <= S_IDLE;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
