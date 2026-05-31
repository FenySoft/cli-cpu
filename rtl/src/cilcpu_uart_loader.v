// hu: CLI-CPU F2.8 #6.5b-F1b — UART boot-loader FSM. Az uart_rx byte-stream
//     kimenetét (i_byte/i_byte_valid) parse-olja keretekre:
//       WRITE: 0xC0 | dev(1) | addr[23:0](3, BE) | len[15:0](2, BE) | payload
//              dev: 0=flash (SEG_CODE), 1=PSRAM (SEG_STACK) → o_mem_addr[23:20]
//              payload → 32-bit LITTLE-ENDIAN szavak, len bájt (4 többszöröse)
//       BOOT:  0xB0 | code_src(1) | boot_pc[23:0](3, BE) | argc(1) | localc(1)
//     A WRITE 32-bit szavakat ír ki az o_mem master porton (a SoC fázis-MUX-án
//     át a QSPI controllerre); o_mem_we 1-ciklusos pulzus, a tranzakció végét az
//     i_mem_ready jelzi. A BOOT egy o_boot_req pulzust ad a boot-paraméterekkel.
// en: CLI-CPU F2.8 #6.5b-F1b — UART boot-loader FSM. Parses the uart_rx byte
//     stream (i_byte/i_byte_valid) into frames (WRITE/BOOT, see above). WRITE
//     emits 32-bit little-endian words on the o_mem master port (through the SoC
//     phase MUX to the QSPI controller); o_mem_we is a 1-cycle pulse, the
//     transaction end is signalled by i_mem_ready. BOOT pulses o_boot_req with
//     the boot params.

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_uart_loader (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Byte-stream az uart_rx-ből / en: byte stream from uart_rx
    input  wire [7:0]  i_byte,
    input  wire        i_byte_valid,

    // hu: Memória-írás master (→ fázis-MUX → QSPI controller)
    // en: memory-write master (→ phase MUX → QSPI controller)
    output reg  [23:0] o_mem_addr,
    output reg  [31:0] o_mem_wdata,
    output reg         o_mem_we,
    input  wire        i_mem_ready,

    // hu: Boot-kérés (→ boot_ctrl / core) / en: boot request
    output reg         o_boot_req,
    output reg  [23:0] o_boot_pc,
    output reg  [7:0]  o_boot_argc,
    output reg  [7:0]  o_boot_localc,
    output reg         o_boot_code_src,

    // hu: 1 = keret-feldolgozás folyamatban / en: 1 = parsing a frame
    output wire        o_busy
);

    localparam [7:0] CMD_WRITE = 8'hC0;
    localparam [7:0] CMD_BOOT  = 8'hB0;

    localparam [2:0] S_CMD   = 3'd0;
    localparam [2:0] S_WHDR  = 3'd1;   // WRITE fejléc (6 bájt)
    localparam [2:0] S_WDATA = 3'd2;   // payload-bájtok szóba gyűjtése
    localparam [2:0] S_WWAIT = 3'd3;   // QSPI-írás handshake (i_mem_ready)
    localparam [2:0] S_BHDR  = 3'd4;   // BOOT fejléc (6 bájt)
    localparam [2:0] S_BOOT  = 3'd5;   // o_boot_req pulzus

    reg [2:0]  r_state;
    reg [2:0]  r_fcnt;        // fejléc-bájt számláló (0..5)

    // WRITE mezők
    reg        r_dev;
    reg [15:0] r_len;         // payload bájt-szám
    reg [15:0] r_recv;        // eddig vett payload bájt
    reg [31:0] r_word;        // szó-akkumulátor (LE)
    reg [1:0]  r_byteidx;     // 0..3 a szón belül

    // BOOT mezők
    reg        r_code_src;
    reg [23:0] r_bpc;
    reg [7:0]  r_bargc;
    reg [7:0]  r_blocalc;

    assign o_busy = (r_state != S_CMD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state         <= S_CMD;
            r_fcnt          <= 3'd0;
            r_dev           <= 1'b0;
            r_len           <= 16'd0;
            r_recv          <= 16'd0;
            r_word          <= 32'd0;
            r_byteidx       <= 2'd0;
            r_code_src      <= 1'b0;
            r_bpc           <= 24'd0;
            r_bargc         <= 8'd0;
            r_blocalc       <= 8'd0;
            o_mem_addr      <= 24'd0;
            o_mem_wdata     <= 32'd0;
            o_mem_we        <= 1'b0;
            o_boot_req      <= 1'b0;
            o_boot_pc       <= 24'd0;
            o_boot_argc     <= 8'd0;
            o_boot_localc   <= 8'd0;
            o_boot_code_src <= 1'b0;
        end else begin
            // hu: pulzus-jelek alaphelyzete minden ciklusban
            // en: pulse signals default-cleared each cycle
            o_mem_we   <= 1'b0;
            o_boot_req <= 1'b0;

            case (r_state)

                // --------------------------------------------------
                // hu: parancs-byte várása
                // --------------------------------------------------
                S_CMD: begin
                    if (i_byte_valid) begin
                        r_fcnt <= 3'd0;
                        if (i_byte == CMD_WRITE)
                            r_state <= S_WHDR;
                        else if (i_byte == CMD_BOOT)
                            r_state <= S_BHDR;
                        // hu: ismeretlen parancs → no-op (S_CMD-ben marad)
                    end
                end

                // --------------------------------------------------
                // hu: WRITE fejléc — dev, addr[23:0] (BE), len[15:0] (BE)
                // --------------------------------------------------
                S_WHDR: begin
                    if (i_byte_valid) begin
                        case (r_fcnt)
                            3'd0: r_dev          <= i_byte[0];
                            3'd1: o_mem_addr[23:16] <= i_byte;
                            3'd2: o_mem_addr[15:8]  <= i_byte;
                            3'd3: o_mem_addr[7:0]   <= i_byte;
                            3'd4: r_len[15:8]    <= i_byte;
                            default: r_len[7:0]  <= i_byte;   // 3'd5
                        endcase

                        if (r_fcnt == 3'd5) begin
                            // hu: szegmens a dev alapján az addr[23:20]-ba
                            // en: segment from dev into addr[23:20]
                            o_mem_addr[23:20] <= (r_dev == 1'b1)
                                                 ? `SEG_STACK : `SEG_CODE;
                            r_recv    <= 16'd0;
                            r_byteidx <= 2'd0;
                            r_state   <= S_WDATA;
                        end else begin
                            r_fcnt <= r_fcnt + 3'd1;
                        end
                    end
                end

                // --------------------------------------------------
                // hu: payload-bájtok 32-bit LE szóba gyűjtése
                // --------------------------------------------------
                S_WDATA: begin
                    if (i_byte_valid) begin
                        // hu: BIG-ENDIAN szó-összeállítás — az első payload bájt
                        //     (legalacsonyabb cím) a [31:24]-be. Ez illeszkedik a
                        //     QSPI write→PSRAM→read→fetch round-trip-hez: a
                        //     controller írás cpu_wdata=X-ből psram.mem[addr]=
                        //     X[31:24]-t tárol (BE), és a fetch a flash-
                        //     konvencióval (mem[offset]=program-bájt) működik.
                        // en: BIG-ENDIAN word assembly — first payload byte
                        //     (lowest address) into [31:24]. Matches the QSPI
                        //     write→PSRAM→read→fetch round-trip: a write of
                        //     cpu_wdata=X stores psram.mem[addr]=X[31:24] (BE),
                        //     and fetch uses the flash convention (mem[offset]=
                        //     program byte).
                        case (r_byteidx)
                            2'd0: r_word[31:24] <= i_byte;
                            2'd1: r_word[23:16] <= i_byte;
                            2'd2: r_word[15:8]  <= i_byte;
                            default: r_word[7:0] <= i_byte;
                        endcase
                        r_recv <= r_recv + 16'd1;

                        if (r_byteidx == 2'd3) begin
                            // hu: szó kész — írás kiadása (1-ciklus o_mem_we
                            //     pulzus a következő, S_WWAIT ciklusban).
                            o_mem_wdata[31:8] <= r_word[31:8];
                            o_mem_wdata[7:0]  <= i_byte;     // a 4. (legalsó) bájt
                            o_mem_we          <= 1'b1;
                            r_byteidx         <= 2'd0;
                            r_state           <= S_WWAIT;
                        end else begin
                            r_byteidx <= r_byteidx + 2'd1;
                        end
                    end
                end

                // --------------------------------------------------
                // hu: QSPI-írás handshake — vár i_mem_ready-re, majd cím+=4
                // --------------------------------------------------
                S_WWAIT: begin
                    if (i_mem_ready) begin
                        o_mem_addr <= o_mem_addr + 24'd4;
                        if (r_recv >= r_len)
                            r_state <= S_CMD;
                        else
                            r_state <= S_WDATA;
                    end
                end

                // --------------------------------------------------
                // hu: BOOT fejléc — code_src, pc[23:0] (BE), argc, localc
                // --------------------------------------------------
                S_BHDR: begin
                    if (i_byte_valid) begin
                        case (r_fcnt)
                            3'd0: r_code_src     <= i_byte[0];
                            3'd1: r_bpc[23:16]   <= i_byte;
                            3'd2: r_bpc[15:8]    <= i_byte;
                            3'd3: r_bpc[7:0]     <= i_byte;
                            3'd4: r_bargc        <= i_byte;
                            default: r_blocalc   <= i_byte;   // 3'd5
                        endcase

                        if (r_fcnt == 3'd5)
                            r_state <= S_BOOT;
                        else
                            r_fcnt <= r_fcnt + 3'd1;
                    end
                end

                // --------------------------------------------------
                // hu: BOOT pulzus — a paraméterek a r_b* regiszterekből
                // --------------------------------------------------
                S_BOOT: begin
                    o_boot_req      <= 1'b1;
                    o_boot_pc       <= r_bpc;
                    o_boot_argc     <= r_bargc;
                    o_boot_localc   <= r_blocalc;
                    o_boot_code_src <= r_code_src;
                    r_state         <= S_CMD;
                end

                default: r_state <= S_CMD;

            endcase
        end
    end

endmodule

`default_nettype wire
