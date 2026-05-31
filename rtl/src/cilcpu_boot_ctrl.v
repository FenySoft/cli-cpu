// hu: CLI-CPU F2.8 #6.5b-F1c — flash auto-detect boot controller. Reset után
//     (ha AUTODETECT=1) beolvassa a flash CODE-bázison (SEG_CODE, offset 0) a
//     belépési metódus 8-bájtos header-szavát, és ellenőrzi a magic-et:
//       header[0] = 0xFE (magic), [1] = arg_count, [2] = local_count
//     A QSPI big-endian olvasás miatt a beolvasott szóban:
//       i_mem_rdata[31:24] = magic, [23:16] = arg_count, [15:8] = local_count
//     Ha a magic érvényes → autonóm flash-boot: o_boot_req pulzus, boot_pc =
//     HEADER_SIZE (a header mögötti első utasítás), argc/localc a header-ből.
//     Ha üres flash (magic != 0xFE, jellemzően 0xFF) → idle: nincs auto-boot,
//     a rendszer a UART loader BOOT keretére vár.
//     AUTODETECT=0 → a controller inaktív (o_detect_active=0, o_boot_req=0) —
//     a meglévő külső-boot (i_boot_*) és UART-boot út változatlan.
// en: CLI-CPU F2.8 #6.5b-F1c — flash auto-detect boot controller. After reset
//     (if AUTODETECT=1) it reads the entry method's 8-byte header word at the
//     flash CODE base (SEG_CODE, offset 0) and checks the magic:
//       header[0] = 0xFE (magic), [1] = arg_count, [2] = local_count
//     Due to QSPI big-endian read, the fetched word has:
//       i_mem_rdata[31:24] = magic, [23:16] = arg_count, [15:8] = local_count
//     Valid magic → autonomous flash boot: o_boot_req pulse, boot_pc =
//     HEADER_SIZE (first instruction past the header), argc/localc from header.
//     Blank flash (magic != 0xFE, typically 0xFF) → idle: no auto-boot, the
//     system waits for the UART loader's BOOT frame.
//     AUTODETECT=0 → controller inert (o_detect_active=0, o_boot_req=0) — the
//     existing external boot (i_boot_*) and UART-boot path are unchanged.

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_boot_ctrl #(
    parameter integer AUTODETECT  = 0,
    parameter integer HEADER_SIZE = 8    // hu: linker MethodHeaderSize
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: QSPI read-master (a SoC fázis-MUX-án át a flash-re). Csak a
    //     detect-fázisban aktív (o_detect_active=1).
    // en: QSPI read master (through the SoC phase MUX to flash). Active only
    //     during the detect phase (o_detect_active=1).
    output reg  [23:0] o_mem_addr,
    output reg         o_mem_re,
    input  wire [31:0] i_mem_rdata,
    input  wire        i_mem_ready,
    output reg         o_detect_active,

    // hu: Boot-vezérlés a core felé (a SoC boot-mux-án át)
    // en: Boot drive to the core (through the SoC boot mux)
    output reg         o_boot_req,
    output reg  [23:0] o_boot_pc,
    output reg  [7:0]  o_boot_argc,
    output reg  [7:0]  o_boot_localc
);

    localparam [7:0] MAGIC = 8'hFE;

    localparam [1:0] S_REQ    = 2'd0;   // header-olvasás kérés
    localparam [1:0] S_WAIT   = 2'd1;   // i_mem_ready-re vár
    localparam [1:0] S_DECIDE = 2'd2;   // magic-ellenőrzés + boot vagy idle
    localparam [1:0] S_DONE   = 2'd3;   // terminál (auto-boot megtörtént / idle)

    reg [1:0] r_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_mem_addr      <= 24'd0;
            o_mem_re        <= 1'b0;
            o_detect_active <= (AUTODETECT != 0) ? 1'b1 : 1'b0;
            o_boot_req      <= 1'b0;
            o_boot_pc       <= 24'd0;
            o_boot_argc     <= 8'd0;
            o_boot_localc   <= 8'd0;
            r_state         <= S_REQ;
        end else begin
            o_mem_re   <= 1'b0;   // hu: read-enable pulzus alaphelyzet
            o_boot_req <= 1'b0;   // hu: boot-req pulzus alaphelyzet

            if (AUTODETECT == 0) begin
                // hu: inaktív — soha nem vesz részt a buszon / boot-ban
                o_detect_active <= 1'b0;
            end else begin
                case (r_state)
                    S_REQ: begin
                        // hu: flash CODE-bázis (SEG_CODE, offset 0) header-szó
                        o_mem_addr <= {`SEG_CODE, 20'd0};
                        o_mem_re   <= 1'b1;
                        r_state    <= S_WAIT;
                    end

                    S_WAIT: begin
                        if (i_mem_ready) begin
                            if (i_mem_rdata[31:24] == MAGIC) begin
                                // hu: érvényes program → autonóm flash-boot
                                o_boot_req    <= 1'b1;
                                o_boot_pc     <= HEADER_SIZE[23:0];
                                o_boot_argc   <= i_mem_rdata[23:16];
                                o_boot_localc <= i_mem_rdata[15:8];
                            end
                            // hu: akár boot, akár üres flash → a busz felszabadul
                            o_detect_active <= 1'b0;
                            r_state         <= S_DECIDE;
                        end
                    end

                    S_DECIDE: begin
                        // hu: 1-ciklus a boot_req pulzus után → terminál
                        r_state <= S_DONE;
                    end

                    default: begin   // S_DONE
                        o_detect_active <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
