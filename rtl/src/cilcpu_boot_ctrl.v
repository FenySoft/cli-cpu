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

    // hu: Boot-vezérlés a core felé (a SoC boot-mux-án át). Az o_boot_nwords a
    //     F3 copy-engine-nek a másolandó szavak száma = ceil((HEADER_SIZE+csize)/4),
    //     a 2. header-szó csize mezőjéből ([4:5] bájt).
    // en: Boot drive to the core (through the SoC boot mux). o_boot_nwords gives
    //     the F3 copy engine the word count to copy = ceil((HEADER_SIZE+csize)/4),
    //     from the 2nd header word's csize field (bytes [4:5]).
    output reg         o_boot_req,
    output reg  [23:0] o_boot_pc,
    output reg  [7:0]  o_boot_argc,
    output reg  [7:0]  o_boot_localc,
    output reg  [11:0] o_boot_nwords
);

    localparam [7:0] MAGIC = 8'hFE;

    localparam [2:0] S_REQ    = 3'd0;   // 1. header-szó (magic/argc/localc) kérés
    localparam [2:0] S_WAIT   = 3'd1;   // i_mem_ready-re vár, magic-ellenőrzés
    localparam [2:0] S_REQ2   = 3'd2;   // 2. header-szó (csize) kérés
    localparam [2:0] S_WAIT2  = 3'd3;   // csize latch + nwords + boot_req
    localparam [2:0] S_DECIDE = 3'd4;   // 1-ciklus a boot_req után
    localparam [2:0] S_DONE   = 3'd5;   // terminál (auto-boot megtörtént / idle)

    reg [2:0]  r_state;

    // hu: copy-szószám = ceil((HEADER_SIZE + csize) / 4). csize = a 2. header-szó
    //     [4:5] bájtja = {bájt5, bájt4} = {i_mem_rdata[23:16], i_mem_rdata[31:24]}.
    //     A +11 = HEADER_SIZE(8, a linker MethodHeaderSize protokoll-konstans) + 3
    //     (felfelé-kerekítés), majd a [13:2] szelet = >>2 (12-bit szószám).
    // en: copy word count = ceil((HEADER_SIZE + csize) / 4). csize from the 2nd
    //     header word's [4:5] bytes; +11 = HEADER_SIZE(8) + 3 round-up; [13:2] = >>2.
    wire [15:0] w_total_bytes = {i_mem_rdata[23:16], i_mem_rdata[31:24]} + 16'd11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_mem_addr      <= 24'd0;
            o_mem_re        <= 1'b0;
            o_detect_active <= (AUTODETECT != 0) ? 1'b1 : 1'b0;
            o_boot_req      <= 1'b0;
            o_boot_pc       <= 24'd0;
            o_boot_argc     <= 8'd0;
            o_boot_localc   <= 8'd0;
            o_boot_nwords   <= 12'd0;
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
                        // hu: flash CODE-bázis (SEG_CODE, offset 0) 1. header-szó
                        o_mem_addr <= {`SEG_CODE, 20'd0};
                        o_mem_re   <= 1'b1;
                        r_state    <= S_WAIT;
                    end

                    S_WAIT: begin
                        if (i_mem_ready) begin
                            if (i_mem_rdata[31:24] == MAGIC) begin
                                // hu: érvényes magic → argc/localc latch, majd a
                                //     2. header-szó (csize) olvasása a copy-hosszhoz.
                                o_boot_pc     <= HEADER_SIZE[23:0];
                                o_boot_argc   <= i_mem_rdata[23:16];
                                o_boot_localc <= i_mem_rdata[15:8];
                                r_state       <= S_REQ2;
                            end else begin
                                // hu: üres flash → nincs auto-boot, busz felszabadul
                                o_detect_active <= 1'b0;
                                r_state         <= S_DONE;
                            end
                        end
                    end

                    S_REQ2: begin
                        // hu: 2. header-szó (SEG_CODE, offset 4): csize bájt [4:5]
                        o_mem_addr <= {`SEG_CODE, 20'd4};
                        o_mem_re   <= 1'b1;
                        r_state    <= S_WAIT2;
                    end

                    S_WAIT2: begin
                        if (i_mem_ready) begin
                            // hu: nwords = (HEADER_SIZE + csize + 3) >> 2 → a
                            //     16-bites w_total_bytes [13:2] szelete (12-bit).
                            // en: nwords = w_total_bytes[13:2] (12-bit).
                            o_boot_nwords   <= w_total_bytes[13:2];
                            o_boot_req      <= 1'b1;   // autonóm flash-boot
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
