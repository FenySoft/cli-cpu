// hu: CLI-CPU F2.4 QSPI Controller — CPU belső SRAM-szerű kéréseket fordít
//     QSPI protokollra. QSPI Flash (CODE/DATA, read-only, 0x6B) és QSPI PSRAM
//     (STACK, read-write, 0xEB/0x38) kezelése. Single-word (32-bit) tranzakciók.
//     DQ vonalak split portokra bontva (dq_out/dq_in/dq_oe) — inout nélkül.
//     Aszinkron aktív-low reset. main_clk=50 MHz, qspi_clk=25 MHz.
//
// en: CLI-CPU F2.4 QSPI Controller — translates CPU SRAM-like requests
//     to QSPI protocol. Flash (CODE/DATA, read-only, 0x6B) and PSRAM
//     (STACK, read-write, 0xEB/0x38). Single-word (32-bit) transactions.
//     DQ split into dq_out/dq_in/dq_oe ports — no inout.
//     Async active-low reset. main_clk=50 MHz, qspi_clk=25 MHz.
//
// Spec: rtl/src/QSPI_CONTROLLER_SPEC-hu.md

`include "cilcpu_defines.vh"

module cilcpu_qspi_controller #(
    // hu: Sub5.A — CODE szegmens flash-bázis offszet. A config-flash
    //     a 0x0-tól a bitstream-et tárolja; a CIL-T0 app a bitstream
    //     FÖLÉ kerül (FPGA: 0xC00000). Default 0 → sim-paritás (a
    //     cocotb flash modell és minden meglévő teszt változatlan).
    //     A CODE szegmens flash-címe = CODE_BASE_OFFSET[23:0] + cpu_addr[19:0].
    //     Méret-nélküli `integer`-ként deklarálva, hogy a parancssori
    //     `-GCODE_BASE_OFFSET=<value>` (Verilator) / `set_property generic`
    //     (Vivado) override ne dobjon WIDTHTRUNC-ot; a használat helyén
    //     [23:0]-ra slice-eljük (a wrapper-paraméter konvencióval egyezően).
    // en: Sub5.A — CODE segment flash base offset. The config-flash
    //     stores the bitstream from 0x0; the CIL-T0 app is placed
    //     ABOVE the bitstream (FPGA: 0xC00000). Default 0 → sim parity
    //     (cocotb flash model and all existing tests unchanged).
    //     CODE segment flash address = CODE_BASE_OFFSET[23:0] + cpu_addr[19:0].
    //     Declared as untyped `integer` so the command-line
    //     `-GCODE_BASE_OFFSET=<value>` (Verilator) / `set_property generic`
    //     (Vivado) override does not raise WIDTHTRUNC; sliced to [23:0] at
    //     the use site (matching the wrapper-parameter convention).
    parameter integer CODE_BASE_OFFSET = 0,

    // hu: F2.7 Sub5 — flash QE-bit init engedélyezése reset után. HW-en
    //     KÖTELEZŐ (a board MODE pinjei SPI x1 boot-ra konfiguráltak, így
    //     az FPGA startup ROM nem állítja be a flash QE-jét → a core 0x6B
    //     Quad Output Read parancsa garbage-t kapna). Sim-ben default 0,
    //     hogy a meglévő unit-tesztek (test_qspi_controller, test_core)
    //     változatlan reset-utáni viselkedést kapjanak; a
    //     dedikált test_qspi_qe_init expliciten 1-re állítja.
    //     Vivado FPGA build: set_property generic QE_INIT_ENABLE=1.
    // en: F2.7 Sub5 — enable flash QE-bit init after reset. REQUIRED on
    //     real HW (the board's MODE pins are configured for SPI x1 boot,
    //     so the FPGA startup ROM does not set the flash QE → the core's
    //     0x6B Quad Output Read would return garbage). Default 0 in sim
    //     so existing unit tests (test_qspi_controller, test_core)
    //     see unchanged post-reset behaviour; the
    //     dedicated test_qspi_qe_init sets it to 1 explicitly.
    //     Vivado FPGA build: set_property generic QE_INIT_ENABLE=1.
    parameter integer QE_INIT_ENABLE = 0
) (
    // hu: Órajel és reset
    // en: Clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // hu: CPU-oldali portok
    // en: CPU-side ports
    input  wire [23:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,
    input  wire        cpu_re,
    input  wire        cpu_we,
    output reg         cpu_ready,
    output wire        cpu_busy,

    // hu: QSPI-oldali portok
    // en: QSPI-side ports
    output wire        qspi_clk,
    output reg         qspi_cs_flash_n,
    output reg         qspi_cs_psram_n,
    output reg  [3:0]  qspi_dq_out,
    input  wire [3:0]  qspi_dq_in,
    output reg         qspi_dq_oe
);

// ============================================================
// hu: FSM állapot kódok
// en: FSM state codes
// ============================================================

localparam [3:0] ST_IDLE    = 4'd0;
localparam [3:0] ST_CMD     = 4'd1;
localparam [3:0] ST_ADDR    = 4'd2;
localparam [3:0] ST_DUMMY   = 4'd3;
localparam [3:0] ST_DATA_RD = 4'd4;
localparam [3:0] ST_DATA_WR = 4'd5;
localparam [3:0] ST_DONE    = 4'd6;
// hu: F2.7 Sub5 — flash QE-init állapotok. Reset után a controller először
//     egy WREN (0x06) + WRSR (0x01) 0x40 sekvenciát küld a flash-nek, hogy
//     a Status Register QE bitje (bit 6) = 1 legyen. Enélkül HW-en a
//     0x6B Quad Output Read garbage-t adna (a board MODE-pinjei nem SPIx4
//     boot-ra vannak konfigurálva → FPGA startup ROM nem állítja be a QE-t).
//     Sim: a TQSPIFlashModel transzparensen átengedi az ismeretlen CMD-ket
//     (CS# magasig vár), így a meglévő tesztek változatlanul futnak.
// en: F2.7 Sub5 — flash QE-init states. After reset the controller first
//     issues WREN (0x06) + WRSR (0x01) 0x40 to set the flash Status
//     Register QE bit (bit 6). Without this, on real HW the 0x6B Quad
//     Output Read returns garbage (the board's MODE pins are not set for
//     SPIx4 boot → the FPGA startup ROM does not configure QE).
//     Sim: TQSPIFlashModel transparently absorbs unknown CMDs (waits for
//     CS# high), so existing tests run unchanged.
localparam [3:0] ST_INIT_CS_HI    = 4'd7;
localparam [3:0] ST_INIT_DATA_SPI = 4'd8;

// hu: F2 — flash erase+program FSM állapotok. Egy szó-írás a flash-be a
//     WREN → Sector Erase → WIP-poll → WREN → Page Program → WIP-poll
//     szekvenciát futtatja (több, CS#-szel elválasztott SPI tranzakció).
//     A lépéseket az r_fw_step al-szekvenszer vezérli; a közös SPI-fázisok
//     (CMD/ADDR/DATA/RDSR/CS-spacing) az alábbi állapotokban futnak.
// en: F2 — flash erase+program FSM states. A word write to flash runs the
//     WREN → Sector Erase → WIP-poll → WREN → Page Program → WIP-poll
//     sequence (multiple CS#-separated SPI transactions). The steps are
//     driven by the r_fw_step sub-sequencer; the shared SPI phases
//     (CMD/ADDR/DATA/RDSR/CS-spacing) run in the states below.
localparam [3:0] ST_FW_CMD     = 4'd9;    // 8-bit CMD küldés SPI módban
localparam [3:0] ST_FW_ADDR    = 4'd10;   // 24-bit cím küldés SPI módban
localparam [3:0] ST_FW_DATA    = 4'd11;   // 32-bit adat küldés SPI módban (program)
localparam [3:0] ST_FW_RDSR_RD = 4'd12;   // 8-bit status olvasás MISO-n (DQ[1])
localparam [3:0] ST_FW_CS_HI   = 4'd13;   // CS# spacing + al-szekvenszer léptetés

localparam [1:0] INIT_WREN     = 2'd0;
localparam [1:0] INIT_WRSR_CMD = 2'd1;
localparam [1:0] INIT_WRSR_DAT = 2'd2;
localparam [1:0] INIT_DONE     = 2'd3;

// hu: Flash-write al-szekvenszer lépések (r_fw_step)
// en: Flash-write sub-sequencer steps (r_fw_step)
localparam [2:0] FW_WREN_E  = 3'd0;   // WREN az erase előtt
localparam [2:0] FW_ERASE   = 3'd1;   // 0x20 Sector Erase + cím
localparam [2:0] FW_POLL_E  = 3'd2;   // RDSR amíg WIP=0 (erase vége)
localparam [2:0] FW_WREN_P  = 3'd3;   // WREN a program előtt
localparam [2:0] FW_PROGRAM = 3'd4;   // 0x02 Page Program + cím + adat
localparam [2:0] FW_POLL_P  = 3'd5;   // RDSR amíg WIP=0 (program vége)

// ============================================================
// hu: Belső regiszterek
// en: Internal registers
// ============================================================

reg  [3:0]  r_state;
reg  [5:0]  r_bit_cnt;
reg  [7:0]  r_cmd;
reg  [23:0] r_addr;
reg  [31:0] r_shift_out;
reg  [31:0] r_shift_in;
reg         r_clk_phase;   // hu: QSPI CLK toggle (0→1→0→1...), /2 osztó
reg         r_is_write;    // hu: 1=írás, 0=olvasás
reg         r_device;      // hu: 0=Flash, 1=PSRAM
reg         r_clk_en;      // hu: CLK gating: 1 ha aktív tranzakció

// hu: F2.7 Sub5 — flash QE-init állapot
// en: F2.7 Sub5 — flash QE-init state
reg  [1:0]  r_init_phase;  // aktuális init fázis (WREN/WRSR_CMD/WRSR_DAT/DONE)
reg         r_init_done;   // 1 = QE-init lefutott, normál üzem engedélyezve

// hu: F2 — flash erase+program állapot
// en: F2 — flash erase+program state
reg  [2:0]  r_fw_step;            // aktuális al-szekvenszer lépés (FW_*)
reg  [7:0]  r_status;             // RDSR-ből beolvasott status byte (WIP=bit0)
reg  [11:0] r_last_erased_sector; // utoljára törölt szektor (flash_addr[23:12])
reg         r_have_erased;        // 1 = reset óta legalább egy szektor törölve

// hu: Kombinációs flash-write cím — a CODE szegmens a CODE_BASE_OFFSET fölé
//     tolva (mint olvasásnál), a DATA szegmens {4'h1, addr[19:0]}. A szektor-
//     azonosító (4 KB) a törlés-szükségesség eldöntéséhez.
// en: Combinational flash-write address — CODE segment shifted above
//     CODE_BASE_OFFSET (as for reads), DATA segment {4'h1, addr[19:0]}. The
//     sector id (4 KB) decides whether an erase is needed.
wire [23:0] w_flash_waddr = (cpu_addr[23:20] == `SEG_CODE)
                            ? (CODE_BASE_OFFSET[23:0] + {4'h0, cpu_addr[19:0]})
                            : {4'h1, cpu_addr[19:0]};
wire [11:0] w_wsector     = w_flash_waddr[`QSPI_FLASH_SECTOR_HI:`QSPI_FLASH_SECTOR_LO];
wire        w_need_erase  = (!r_have_erased) || (w_wsector != r_last_erased_sector);

// hu: Flash SPI parancs indítása — CS# low, CMD MSB előre, CLK aktív, → ST_FW_CMD.
//     Minden flash-write parancs (0x06/0x05/0x20/0x02) MSB-je 0 → DQ[0]=0.
// en: Launch a flash SPI command — CS# low, CMD MSB first, CLK active, → ST_FW_CMD.
//     Every flash-write command (0x06/0x05/0x20/0x02) has MSB 0 → DQ[0]=0.
task launch_flash_cmd(input [7:0] cmd_byte);
begin
    r_cmd           <= cmd_byte;
    qspi_cs_flash_n <= 1'b0;
    r_bit_cnt       <= 6'd7;
    r_clk_en        <= 1'b1;
    r_clk_phase     <= 1'b0;
    qspi_dq_oe      <= 1'b1;
    qspi_dq_out     <= {3'b111, cmd_byte[7]};
    r_state         <= ST_FW_CMD;
end
endtask

// ============================================================
// hu: QSPI CLK kimenet — kombinációs, gated
// en: QSPI CLK output — combinational, gated
// ============================================================

assign qspi_clk = r_clk_phase & r_clk_en;

// ============================================================
// hu: cpu_busy — tranzakció aktív, ha nem IDLE és nem DONE
// en: cpu_busy — transaction active when not IDLE and not DONE
// ============================================================

assign cpu_busy = (r_state != ST_IDLE) & (r_state != ST_DONE);

// ============================================================
// hu: FSM + regiszter logika — aszinkron reset
// en: FSM + register logic — async reset
// ============================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // hu: Reset — minden regiszter törlése. Ha QE_INIT_ENABLE=1, a
        //     reset után közvetlenül indul a WREN 0x06 CMD (a flash QE-bit
        //     beállításához). Ha 0 (sim default), klasszikus IDLE-állapot.
        // en: Reset — clear all registers. If QE_INIT_ENABLE=1, the WREN
        //     0x06 CMD starts immediately after reset (to set the flash
        //     QE bit). If 0 (sim default), classic IDLE state.
        r_addr           <= 24'd0;
        r_shift_out      <= 32'd0;
        r_shift_in       <= 32'd0;
        r_clk_phase      <= 1'b0;
        r_is_write       <= 1'b0;
        r_device         <= 1'b0;
        cpu_ready        <= 1'b0;
        cpu_rdata        <= 32'd0;
        qspi_cs_psram_n  <= 1'b1;

        // hu: F2 — flash-write állapot törlése (reset → még nincs törölt szektor)
        // en: F2 — clear flash-write state (reset → no sector erased yet)
        r_fw_step             <= FW_WREN_E;
        r_status              <= 8'd0;
        r_last_erased_sector  <= 12'd0;
        r_have_erased         <= 1'b0;

        if (QE_INIT_ENABLE != 0) begin
            // hu: QE-init aktív — WREN tranzakció indítása
            // en: QE-init active — start WREN transaction
            r_bit_cnt        <= 6'd7;     // 8 CMD bit, 7→0
            r_cmd            <= 8'h06;    // WREN
            r_clk_en         <= 1'b1;     // CLK aktív az init alatt
            qspi_cs_flash_n  <= 1'b0;     // CS# low — WREN tranzakció kezdődik
            qspi_dq_out      <= 4'b1110;  // 0x06 MSB=0 → DQ[0]=0
            qspi_dq_oe       <= 1'b1;
            r_init_done      <= 1'b0;
            r_init_phase     <= INIT_WREN;
            r_state          <= ST_CMD;   // egyből CMD küldés
        end else begin
            // hu: QE-init disabled — klasszikus IDLE-állapot reset után
            // en: QE-init disabled — classic IDLE state after reset
            r_bit_cnt        <= 6'd0;
            r_cmd            <= 8'd0;
            r_clk_en         <= 1'b0;
            qspi_cs_flash_n  <= 1'b1;
            qspi_dq_out      <= 4'hF;
            qspi_dq_oe       <= 1'b0;
            r_init_done      <= 1'b1;     // azonnal "kész" — IDLE-ben fogadja a CPU-kéréseket
            r_init_phase     <= INIT_DONE;
            r_state          <= ST_IDLE;
        end
    end else begin
        // hu: cpu_ready alapértelmezetten 0 (1-ciklusos pulzus)
        // en: cpu_ready defaults to 0 (1-cycle pulse)
        cpu_ready <= 1'b0;

        case (r_state)

        // --------------------------------------------------------
        // hu: ST_IDLE — kérésre vár
        // en: ST_IDLE — wait for request
        // --------------------------------------------------------
        ST_IDLE: begin
            r_clk_phase     <= 1'b0;
            r_clk_en        <= 1'b0;
            qspi_dq_oe      <= 1'b0;
            qspi_dq_out     <= 4'hF;
            qspi_cs_flash_n <= 1'b1;
            qspi_cs_psram_n <= 1'b1;

            if (cpu_re | cpu_we) begin
                // hu: Szegmens dekódolás cpu_addr[23:20] alapján
                // en: Segment decode from cpu_addr[23:20]
                case (cpu_addr[23:20])
                    `SEG_CODE: begin
                        if (cpu_re) begin
                            // hu: Flash olvasás — CODE. A flash-cím a
                            //     CODE_BASE_OFFSET fölé tolva, hogy a config-
                            //     flash bitstream-je (0x0-tól) és a CIL-T0 app
                            //     ne ütközzön. Default 0 → sim-paritás (a régi
                            //     {4'h0, cpu_addr[19:0]} viselkedés). Mindkét
                            //     operandus 24-bit, r_addr 24-bit → nincs trunc.
                            // en: Flash read — CODE. Flash address shifted
                            //     above CODE_BASE_OFFSET so the config-flash
                            //     bitstream (from 0x0) and the CIL-T0 app do
                            //     not collide. Default 0 → sim parity (the old
                            //     {4'h0, cpu_addr[19:0]} behaviour). Both
                            //     operands 24-bit, r_addr 24-bit → no trunc.
                            r_cmd            <= `QSPI_CMD_FLASH_READ;
                            r_addr           <= CODE_BASE_OFFSET[23:0]
                                                + {4'h0, cpu_addr[19:0]};
                            r_is_write       <= 1'b0;
                            r_device         <= 1'b0;
                            qspi_cs_flash_n  <= 1'b0;
                            r_shift_out      <= 32'd0;
                            r_bit_cnt        <= 6'd7;   // hu: 8 CMD bit, 7→0
                            r_clk_phase      <= 1'b0;
                            r_clk_en         <= 1'b1;
                            qspi_dq_oe       <= 1'b1;
                            // hu: Első CMD bit előre berakva (0x6B bit[7]=0 → DQ[0]=0)
                            // en: Pre-load first CMD bit (0x6B bit[7]=0 → DQ[0]=0)
                            qspi_dq_out      <= 4'b1110;  // DQ[3:1]=111, DQ[0]=0 (0x6B MSB=0)
                            r_state          <= ST_CMD;
                        end else begin
                            // hu: F2 — Flash CODE írás: erase+program szekvencia.
                            //     A szegmens-cím a CODE_BASE_OFFSET fölé tolva
                            //     (mint olvasásnál). need_erase: ha új szektor
                            //     (vagy reset óta első írás) → WREN+erase előbb.
                            // en: F2 — Flash CODE write: erase+program sequence.
                            //     Segment address shifted above CODE_BASE_OFFSET
                            //     (as for reads). need_erase: new sector (or first
                            //     write since reset) → WREN+erase first.
                            r_addr      <= w_flash_waddr;
                            r_shift_out <= cpu_wdata;
                            r_is_write  <= 1'b1;
                            r_device    <= 1'b0;
                            if (w_need_erase) begin
                                r_fw_step            <= FW_WREN_E;
                                r_last_erased_sector <= w_wsector;
                                r_have_erased        <= 1'b1;
                            end else begin
                                r_fw_step            <= FW_WREN_P;
                            end
                            launch_flash_cmd(`QSPI_CMD_FLASH_WREN);
                        end
                    end

                    `SEG_DATA: begin
                        if (cpu_re) begin
                            // hu: Flash olvasás — DATA
                            // en: Flash read — DATA
                            r_cmd            <= `QSPI_CMD_FLASH_READ;
                            r_addr           <= {4'h1, cpu_addr[19:0]};
                            r_is_write       <= 1'b0;
                            r_device         <= 1'b0;
                            qspi_cs_flash_n  <= 1'b0;
                            r_shift_out      <= 32'd0;
                            r_bit_cnt        <= 6'd7;
                            r_clk_phase      <= 1'b0;
                            r_clk_en         <= 1'b1;
                            qspi_dq_oe       <= 1'b1;
                            qspi_dq_out      <= 4'b1110;  // DQ[0]=0 (0x6B MSB=0)
                            r_state          <= ST_CMD;
                        end else begin
                            // hu: F2 — Flash DATA írás: erase+program szekvencia.
                            //     A DATA szegmens flash-címe {4'h1, addr[19:0]}.
                            // en: F2 — Flash DATA write: erase+program sequence.
                            //     DATA segment flash address is {4'h1, addr[19:0]}.
                            r_addr      <= w_flash_waddr;
                            r_shift_out <= cpu_wdata;
                            r_is_write  <= 1'b1;
                            r_device    <= 1'b0;
                            if (w_need_erase) begin
                                r_fw_step            <= FW_WREN_E;
                                r_last_erased_sector <= w_wsector;
                                r_have_erased        <= 1'b1;
                            end else begin
                                r_fw_step            <= FW_WREN_P;
                            end
                            launch_flash_cmd(`QSPI_CMD_FLASH_WREN);
                        end
                    end

                    `SEG_STACK: begin
                        if (cpu_re) begin
                            // hu: PSRAM olvasás — STACK (cpu_re prioritás egyidejű re+we esetén)
                            // en: PSRAM read — STACK (cpu_re priority on concurrent re+we)
                            r_cmd            <= `QSPI_CMD_PSRAM_READ;
                            r_addr           <= {4'h0, cpu_addr[19:0]};
                            r_is_write       <= 1'b0;
                            r_device         <= 1'b1;
                            qspi_cs_psram_n  <= 1'b0;
                            r_shift_out      <= 32'd0;
                            r_bit_cnt        <= 6'd7;
                            r_clk_phase      <= 1'b0;
                            r_clk_en         <= 1'b1;
                            qspi_dq_oe       <= 1'b1;
                            qspi_dq_out      <= 4'b1111;  // DQ[0]=1 (0xEB MSB=1)
                            r_state          <= ST_CMD;
                        end else begin
                            // hu: PSRAM írás
                            // en: PSRAM write
                            r_cmd            <= `QSPI_CMD_PSRAM_WRITE;
                            r_addr           <= {4'h0, cpu_addr[19:0]};
                            r_is_write       <= 1'b1;
                            r_device         <= 1'b1;
                            r_shift_out      <= cpu_wdata;
                            qspi_cs_psram_n  <= 1'b0;
                            r_bit_cnt        <= 6'd7;
                            r_clk_phase      <= 1'b0;
                            r_clk_en         <= 1'b1;
                            qspi_dq_oe       <= 1'b1;
                            qspi_dq_out      <= 4'b1110;  // DQ[0]=0 (0x38 MSB=0)
                            r_state          <= ST_CMD;
                        end
                    end

                    default: begin
                        // hu: Érvénytelen szegmens — NOP, cpu_ready azonnal
                        // en: Invalid segment — NOP, immediate cpu_ready
                        cpu_ready <= 1'b1;
                    end
                endcase
            end
        end

        // --------------------------------------------------------
        // hu: ST_CMD — 8 bites parancs küldés SPI módban (DQ[0])
        //     r_clk_phase toggle: 0→1 rising, 1→0 falling
        //     Setup: falling edge-en (r_clk_phase 1→0)
        //     Sample (slave): rising edge-en (r_clk_phase 0→1)
        //     r_bit_cnt csökkentés: falling edge-en (r_clk_phase=1, most válik 0-vá)
        // en: ST_CMD — 8-bit command send in SPI mode (DQ[0])
        //     r_clk_phase toggle: 0→1 rising, 1→0 falling
        //     Setup: on falling edge (r_clk_phase 1→0)
        //     Sample (slave): on rising edge (r_clk_phase 0→1)
        //     r_bit_cnt decrement: on falling edge (r_clk_phase=1, about to go 0)
        // --------------------------------------------------------
        ST_CMD: begin
            r_clk_phase <= ~r_clk_phase;

            if (!r_clk_phase) begin
                // hu: Ez a rising edge (r_clk_phase 0→1 lesz)
                //     Semmi dolgunk — a slave mintavételez
                // en: This is the rising edge (r_clk_phase 0→1)
                //     Nothing to do — slave samples
            end else begin
                // hu: Ez a falling edge (r_clk_phase 1→0 lesz)
                //     Setup: r_cmd[r_bit_cnt] bitje → DQ[0]
                //     DQ[3:2]=1,1 (WP#/HOLD# inaktív), DQ[1]=1 (MISO idle)
                // en: This is the falling edge (r_clk_phase 1→0)
                //     Setup: r_cmd[r_bit_cnt] bit → DQ[0]
                //     DQ[3:2]=1,1 (WP#/HOLD# inactive), DQ[1]=1 (MISO idle)
                if (r_bit_cnt == 6'd0) begin
                    // hu: Utolsó CMD bit — elágazás az init fázis alapján.
                    //     INIT_WREN/INIT_WRSR_CMD: F2.7 Sub5 QE-init lépések
                    //     (CS# spacing vagy 8-bit data SPI). INIT_DONE: normál
                    //     fetch flow (ADDR/PSRAM Quad ADDR átmenet).
                    // en: Last CMD bit — branch on init phase. INIT_WREN /
                    //     INIT_WRSR_CMD: F2.7 Sub5 QE-init steps (CS# spacing
                    //     or 8-bit SPI data). INIT_DONE: normal fetch flow
                    //     (transition to ADDR / PSRAM Quad ADDR).
                    case (r_init_phase)
                        INIT_WREN: begin
                            // hu: WREN CMD küldve → CS# spacing (4 ciklus
                            //     > tSHSL_min 30 ns ISSI IS25LP128-on)
                            // en: WREN CMD sent → CS# spacing (4 cycles
                            //     > tSHSL_min 30 ns on ISSI IS25LP128)
                            r_bit_cnt <= 6'd3;
                            r_state   <= ST_INIT_CS_HI;
                        end
                        INIT_WRSR_CMD: begin
                            // hu: WRSR CMD küldve → 8-bit data byte küldés
                            //     SPI módban (0x40 = QE bit, SR bit 6).
                            // en: WRSR CMD sent → send 8-bit data byte in SPI
                            //     mode (0x40 = QE bit, SR bit 6).
                            r_shift_out <= 32'h0000_0040;
                            r_bit_cnt   <= 6'd7;
                            qspi_dq_out <= 4'b1110;  // 0x40 MSB=0 → DQ[0]=0
                            r_state     <= ST_INIT_DATA_SPI;
                        end
                        default: begin
                            // hu: INIT_DONE — normál fetch flow.
                            //     A következő fázis: ADDR, 24 SPI bit (Flash)
                            //     vagy 6 Quad CLK (PSRAM)
                            // en: INIT_DONE — normal fetch flow.
                            //     Next phase: ADDR, 24 SPI bits (Flash) or 6
                            //     Quad CLKs (PSRAM)
                            if (r_device == 1'b0) begin
                                r_bit_cnt <= 6'd23;
                            end else begin
                                r_bit_cnt <= 6'd5;
                            end
                            r_state <= ST_ADDR;
                            // hu: Setup az ADDR első nibble/bit
                            // en: Setup the first ADDR nibble/bit
                            if (r_device == 1'b0) begin
                                qspi_dq_out <= {3'b111, r_addr[23]};
                            end else begin
                                qspi_dq_out <= r_addr[23:20];
                            end
                        end
                    endcase
                end else begin
                    // hu: Következő CMD bit setup
                    // en: Setup next CMD bit
                    r_bit_cnt <= r_bit_cnt - 6'd1;
                    qspi_dq_out <= {3'b111, r_cmd[r_bit_cnt - 1]};
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_ADDR — Cím küldés
        //     Flash: SPI mód, 24 CLK (r_bit_cnt: 23→0, 1 bit/CLK)
        //     PSRAM: Quad mód, 6 CLK (r_bit_cnt: 5→0, 4 bit/CLK)
        // en: ST_ADDR — Address send
        //     Flash: SPI mode, 24 CLKs (r_bit_cnt: 23→0, 1 bit/CLK)
        //     PSRAM: Quad mode, 6 CLKs (r_bit_cnt: 5→0, 4 bits/CLK)
        // --------------------------------------------------------
        ST_ADDR: begin
            r_clk_phase <= ~r_clk_phase;

            if (r_clk_phase) begin
                // hu: Falling edge — bit_cnt csökkentés és következő bit setup
                // en: Falling edge — decrement bit_cnt and setup next bit
                if (r_bit_cnt == 6'd0) begin
                    // hu: ADDR utolsó CLK falling edge — átmenet
                    // en: ADDR last CLK falling edge — transition
                    if (r_is_write) begin
                        // hu: Írás — nincs DUMMY, egyből DATA_WR
                        // en: Write — no DUMMY, directly to DATA_WR
                        r_bit_cnt   <= 6'd7;   // hu: 8 nibble
                        r_state     <= ST_DATA_WR;
                        qspi_dq_out <= r_shift_out[31:28];
                    end else begin
                        // hu: Olvasás — DUMMY fázis
                        // en: Read — DUMMY phase
                        qspi_dq_oe <= 1'b0;
                        qspi_dq_out <= 4'hF;
                        if (r_device == 1'b0) begin
                            // hu: Flash: 8 dummy CLK
                            r_bit_cnt <= `QSPI_DUMMY_FLASH - 6'd1;
                        end else begin
                            // hu: PSRAM: 6 dummy CLK
                            r_bit_cnt <= `QSPI_DUMMY_PSRAM - 6'd1;
                        end
                        r_state <= ST_DUMMY;
                    end
                end else begin
                    r_bit_cnt <= r_bit_cnt - 6'd1;
                    if (r_device == 1'b0) begin
                        // hu: Flash SPI: következő bit (addr[r_bit_cnt-1])
                        // en: Flash SPI: next bit
                        qspi_dq_out <= {3'b111, r_addr[r_bit_cnt - 1]};
                    end else begin
                        // hu: PSRAM Quad: következő nibble
                        // en: PSRAM Quad: next nibble
                        // hu: r_bit_cnt=5: addr[23:20] már kirakva, most r_bit_cnt=4 → addr[19:16]
                        // en: r_bit_cnt=5: addr[23:20] already set, now r_bit_cnt=4 → addr[19:16]
                        case (r_bit_cnt - 6'd1)
                            6'd4: qspi_dq_out <= r_addr[19:16];
                            6'd3: qspi_dq_out <= r_addr[15:12];
                            6'd2: qspi_dq_out <= r_addr[11:8];
                            6'd1: qspi_dq_out <= r_addr[7:4];
                            6'd0: qspi_dq_out <= r_addr[3:0];
                            default: qspi_dq_out <= 4'h0;
                        endcase
                    end
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_DUMMY — Dummy ciklusok (bus turnaround, DQ Hi-Z)
        //     r_bit_cnt: (dummy_count-1)→0, csökkentés minden FALLING edge-én.
        //     Az átmenet ST_DATA_RD-be az utolsó RISING edge-én (r_bit_cnt=0)
        //     történik, r_clk_phase=1-gyel belépve (DATA_RD-ből nézve 0 lesz).
        //     DATA_RD-be lépve r_bit_cnt=7 (8 adat CLK).
        // en: ST_DUMMY — Dummy cycles (bus turnaround, DQ Hi-Z)
        //     r_bit_cnt: (dummy_count-1)→0, decrement on every FALLING edge.
        //     Transition to ST_DATA_RD on last RISING edge (r_bit_cnt=0),
        //     entering with r_clk_phase=1 (seen as 0 from DATA_RD perspective).
        //     DATA_RD starts with r_bit_cnt=7 (8 data CLKs).
        // --------------------------------------------------------
        ST_DUMMY: begin
            r_clk_phase <= ~r_clk_phase;

            if (!r_clk_phase) begin
                // hu: Rising edge — r_bit_cnt=0 esetén DATA_RD-be lépés
                // en: Rising edge — transition to DATA_RD when r_bit_cnt=0
                if (r_bit_cnt == 6'd0) begin
                    r_bit_cnt  <= 6'd7;
                    r_shift_in <= 32'd0;
                    r_state    <= ST_DATA_RD;
                end
            end else begin
                // hu: Falling edge — r_bit_cnt csökkentés
                // en: Falling edge — decrement r_bit_cnt
                if (r_bit_cnt != 6'd0) begin
                    r_bit_cnt <= r_bit_cnt - 6'd1;
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_DATA_RD — 32-bit adat olvasás (Quad, 4 bit/CLK)
        //     r_bit_cnt: 7→0, minden rising edge-en mintavételez.
        //     r_bit_cnt=0-nál: utolsó nibble mintázás, CLK gating és ST_DONE.
        //     CS# deassert kizárólag ST_DONE-ban (HW-helyes, W25Q-kompatibilis).
        // en: ST_DATA_RD — 32-bit data read (Quad, 4 bits/CLK)
        //     r_bit_cnt: 7→0, sample on every rising edge.
        //     At r_bit_cnt=0: sample last nibble, gate CLK, go to ST_DONE.
        //     CS# deassert only in ST_DONE (HW-correct, W25Q-compatible).
        // --------------------------------------------------------
        ST_DATA_RD: begin
            r_clk_phase <= ~r_clk_phase;

            if (!r_clk_phase) begin
                // hu: Rising edge (r_clk_phase 0→1) — mintavétel
                // en: Rising edge (r_clk_phase 0→1) — sample
                r_shift_in <= {r_shift_in[27:0], qspi_dq_in};

                if (r_bit_cnt == 6'd0) begin
                    // hu: Utolsó nibble mintázva — CLK gating, DONE
                    // en: Last nibble sampled — gate CLK, DONE
                    r_clk_en <= 1'b0;
                    r_state  <= ST_DONE;
                end else begin
                    r_bit_cnt <= r_bit_cnt - 6'd1;
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_DATA_WR — 32-bit adat írás (Quad, 4 bit/CLK)
        //     8 QSPI CLK, r_shift_out felső 4 bitje → DQ[3:0]
        //     Setup: falling edge-en
        //     Utolsó nibble rising edge-én: CS# azonnal deassert,
        //     hogy a slave while-loop ne érzékelje aktívnak.
        // en: ST_DATA_WR — 32-bit data write (Quad, 4 bits/CLK)
        //     8 QSPI CLKs, r_shift_out upper 4 bits → DQ[3:0]
        //     Setup: on falling edge
        //     On last nibble rising edge: CS# immediately deasserted
        //     so slave while-loop does not see it active.
        // --------------------------------------------------------
        ST_DATA_WR: begin
            r_clk_phase <= ~r_clk_phase;

            if (r_clk_phase) begin
                // hu: Falling edge — következő nibble setup
                // en: Falling edge — setup next nibble
                if (r_bit_cnt == 6'd0) begin
                    // hu: Utolsó nibble kirakva — CS# azonnal deassert, DONE
                    // en: Last nibble sent — CS# immediately deasserted, DONE
                    qspi_cs_psram_n <= 1'b1;
                    r_clk_en        <= 1'b0;
                    r_state         <= ST_DONE;
                end else begin
                    r_bit_cnt   <= r_bit_cnt - 6'd1;
                    r_shift_out <= {r_shift_out[27:0], 4'h0};
                    qspi_dq_out <= r_shift_out[27:24];
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_DONE — CS# deassert, cpu_ready=1 pulzus, → ST_IDLE
        // en: ST_DONE — CS# deassert, cpu_ready=1 pulse, → ST_IDLE
        // --------------------------------------------------------
        ST_DONE: begin
            qspi_cs_flash_n <= 1'b1;
            qspi_cs_psram_n <= 1'b1;
            qspi_dq_oe      <= 1'b0;
            qspi_dq_out     <= 4'hF;
            r_clk_en        <= 1'b0;
            r_clk_phase     <= 1'b0;
            cpu_ready       <= 1'b1;
            if (!r_is_write) begin
                cpu_rdata <= r_shift_in;
            end
            r_state <= ST_IDLE;
        end

        // --------------------------------------------------------
        // hu: ST_INIT_CS_HI — F2.7 Sub5 QE-init: CS# high spacing két
        //     SPI tranzakció között (WREN után, WRSR data után). 4 ciklus
        //     (~80 ns @ 50 MHz) > tSHSL_min (30 ns ISSI IS25LP128). A
        //     spacing végén r_init_phase alapján: WREN befejezve →
        //     WRSR CMD indítás; WRSR_DAT befejezve → init kész, ST_IDLE.
        // en: ST_INIT_CS_HI — F2.7 Sub5 QE-init: CS# high spacing between
        //     two SPI transactions (after WREN, after WRSR data). 4 cycles
        //     (~80 ns @ 50 MHz) > tSHSL_min (30 ns ISSI IS25LP128). At end:
        //     INIT_WREN done → start WRSR CMD; INIT_WRSR_DAT done → init
        //     complete, ST_IDLE.
        // --------------------------------------------------------
        ST_INIT_CS_HI: begin
            qspi_cs_flash_n <= 1'b1;
            r_clk_en        <= 1'b0;
            r_clk_phase     <= 1'b0;
            qspi_dq_oe      <= 1'b0;
            qspi_dq_out     <= 4'hF;

            if (r_bit_cnt == 6'd0) begin
                case (r_init_phase)
                    INIT_WREN: begin
                        // hu: WREN befejezve → WRSR CMD indítás
                        // en: WREN done → start WRSR CMD
                        r_init_phase    <= INIT_WRSR_CMD;
                        r_cmd           <= 8'h01;     // WRSR
                        r_bit_cnt       <= 6'd7;
                        qspi_cs_flash_n <= 1'b0;
                        r_clk_en        <= 1'b1;
                        qspi_dq_oe      <= 1'b1;
                        qspi_dq_out     <= 4'b1110;   // 0x01 MSB=0 → DQ[0]=0
                        r_state         <= ST_CMD;
                    end
                    INIT_WRSR_DAT: begin
                        // hu: WRSR DATA befejezve → QE-init lefutott
                        // en: WRSR DATA done → QE-init complete
                        r_init_phase <= INIT_DONE;
                        r_init_done  <= 1'b1;
                        r_state      <= ST_IDLE;
                    end
                    default: r_state <= ST_IDLE;
                endcase
            end else begin
                r_bit_cnt <= r_bit_cnt - 6'd1;
            end
        end

        // --------------------------------------------------------
        // hu: ST_INIT_DATA_SPI — F2.7 Sub5 QE-init: 8 bites data byte
        //     küldés SPI módban (DQ[0]) a WRSR-hez. 8 SPI clock,
        //     r_shift_out alsó 8 bitjéből bit 7→0 sorrendben.
        //     Setup falling edge, sample (slave) rising edge — azonos
        //     mintával mint ST_CMD.
        // en: ST_INIT_DATA_SPI — F2.7 Sub5 QE-init: 8-bit data byte send
        //     in SPI mode (DQ[0]) for the WRSR transaction. 8 SPI clocks,
        //     bits 7→0 from the low byte of r_shift_out. Setup on falling
        //     edge, slave samples on rising — same pattern as ST_CMD.
        // --------------------------------------------------------
        ST_INIT_DATA_SPI: begin
            r_clk_phase <= ~r_clk_phase;

            if (!r_clk_phase) begin
                // hu: Rising edge — slave mintavételez
                // en: Rising edge — slave samples
            end else begin
                // hu: Falling edge — következő bit setup vagy átmenet
                // en: Falling edge — setup next bit or transition
                if (r_bit_cnt == 6'd0) begin
                    // hu: Utolsó data bit kiküldve → CS# spacing, majd init kész
                    // en: Last data bit sent → CS# spacing, then init complete
                    r_init_phase <= INIT_WRSR_DAT;
                    r_bit_cnt    <= 6'd3;
                    r_state      <= ST_INIT_CS_HI;
                end else begin
                    r_bit_cnt   <= r_bit_cnt - 6'd1;
                    qspi_dq_out <= {3'b111, r_shift_out[r_bit_cnt - 1]};
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_FW_CMD — F2 flash-write: 8-bit CMD küldés SPI módban (DQ[0]),
        //     azonos mintával mint ST_CMD/ST_INIT_DATA_SPI. Az utolsó bit után
        //     az r_fw_step alapján ágazik: WREN → CS-spacing; ERASE/PROGRAM →
        //     ADDR; RDSR → status-olvasás (DQ release).
        // en: ST_FW_CMD — F2 flash-write: 8-bit CMD send in SPI mode (DQ[0]),
        //     same pattern as ST_CMD/ST_INIT_DATA_SPI. After the last bit it
        //     branches on r_fw_step: WREN → CS-spacing; ERASE/PROGRAM → ADDR;
        //     RDSR → status read (release DQ).
        // --------------------------------------------------------
        ST_FW_CMD: begin
            r_clk_phase <= ~r_clk_phase;

            if (r_clk_phase) begin
                // hu: Falling edge — következő bit setup vagy átmenet
                // en: Falling edge — setup next bit or transition
                if (r_bit_cnt == 6'd0) begin
                    case (r_fw_step)
                        FW_ERASE, FW_PROGRAM: begin
                            // hu: 24-bit cím küldés SPI módban
                            // en: send 24-bit address in SPI mode
                            r_bit_cnt   <= 6'd23;
                            qspi_dq_out <= {3'b111, r_addr[23]};
                            r_state     <= ST_FW_ADDR;
                        end
                        FW_POLL_E, FW_POLL_P: begin
                            // hu: RDSR — DQ elengedése, 8 status bit olvasás MISO-n
                            // en: RDSR — release DQ, read 8 status bits on MISO
                            qspi_dq_oe <= 1'b0;
                            qspi_dq_out <= 4'hF;
                            r_bit_cnt  <= 6'd7;
                            r_status   <= 8'd0;
                            r_state    <= ST_FW_RDSR_RD;
                        end
                        default: begin
                            // hu: WREN (FW_WREN_E/FW_WREN_P) — nincs addr/data,
                            //     CS# spacing, majd al-szekvenszer léptetés.
                            // en: WREN — no addr/data, CS# spacing, then advance.
                            r_bit_cnt <= 6'd3;
                            r_state   <= ST_FW_CS_HI;
                        end
                    endcase
                end else begin
                    r_bit_cnt   <= r_bit_cnt - 6'd1;
                    qspi_dq_out <= {3'b111, r_cmd[r_bit_cnt - 1]};
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_FW_ADDR — 24-bit cím küldés SPI módban (erase/program).
        //     Az utolsó bit után: ERASE → CS-spacing; PROGRAM → 32-bit adat.
        // en: ST_FW_ADDR — send 24-bit address in SPI mode (erase/program).
        //     After last bit: ERASE → CS-spacing; PROGRAM → 32-bit data.
        // --------------------------------------------------------
        ST_FW_ADDR: begin
            r_clk_phase <= ~r_clk_phase;

            if (r_clk_phase) begin
                if (r_bit_cnt == 6'd0) begin
                    if (r_fw_step == FW_PROGRAM) begin
                        // hu: 32-bit adat küldés SPI módban (MSB előre)
                        // en: send 32-bit data in SPI mode (MSB first)
                        r_bit_cnt   <= 6'd31;
                        qspi_dq_out <= {3'b111, r_shift_out[31]};
                        r_state     <= ST_FW_DATA;
                    end else begin
                        // hu: ERASE — nincs adat, CS-spacing
                        // en: ERASE — no data, CS-spacing
                        r_bit_cnt <= 6'd3;
                        r_state   <= ST_FW_CS_HI;
                    end
                end else begin
                    r_bit_cnt   <= r_bit_cnt - 6'd1;
                    qspi_dq_out <= {3'b111, r_addr[r_bit_cnt - 1]};
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_FW_DATA — 32-bit adat küldés SPI módban (Page Program),
        //     MSB előre (big-endian: r_shift_out[31] = a legalacsonyabb
        //     flash-cím bájtjának MSB-je). Az utolsó bit után CS-spacing.
        // en: ST_FW_DATA — send 32-bit data in SPI mode (Page Program),
        //     MSB first (big-endian: r_shift_out[31] = MSB of the lowest
        //     flash-address byte). After last bit → CS-spacing.
        // --------------------------------------------------------
        ST_FW_DATA: begin
            r_clk_phase <= ~r_clk_phase;

            if (r_clk_phase) begin
                if (r_bit_cnt == 6'd0) begin
                    r_bit_cnt <= 6'd3;
                    r_state   <= ST_FW_CS_HI;
                end else begin
                    r_bit_cnt   <= r_bit_cnt - 6'd1;
                    qspi_dq_out <= {3'b111, r_shift_out[r_bit_cnt - 1]};
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_FW_RDSR_RD — 8-bit status olvasás MISO-n (DQ[1]), MSB előre,
        //     rising edge-en mintavétel (mint a DATA_RD). Az utolsó (8.) bit a
        //     WIP (status[0]). Olvasás után CS-spacing, a WIP-döntés a
        //     CS_HI-ban (poll-again vagy léptetés).
        // en: ST_FW_RDSR_RD — read 8 status bits on MISO (DQ[1]), MSB first,
        //     sampled on rising edge (like DATA_RD). The last (8th) bit is WIP
        //     (status[0]). After read → CS-spacing; the WIP decision is in
        //     CS_HI (poll-again or advance).
        // --------------------------------------------------------
        ST_FW_RDSR_RD: begin
            r_clk_phase <= ~r_clk_phase;

            if (!r_clk_phase) begin
                // hu: Rising edge — MISO (DQ[1]) mintavétel
                // en: Rising edge — sample MISO (DQ[1])
                r_status <= {r_status[6:0], qspi_dq_in[1]};

                if (r_bit_cnt == 6'd0) begin
                    r_clk_en  <= 1'b0;
                    r_bit_cnt <= 6'd3;
                    r_state   <= ST_FW_CS_HI;
                end else begin
                    r_bit_cnt <= r_bit_cnt - 6'd1;
                end
            end
        end

        // --------------------------------------------------------
        // hu: ST_FW_CS_HI — CS# spacing két SPI tranzakció között (4 ciklus),
        //     majd az r_fw_step al-szekvenszer léptetése. A WIP-poll lépéseknél
        //     (FW_POLL_E/FW_POLL_P) a status[0] dönt: WIP=1 → újabb RDSR, WIP=0
        //     → következő lépés. A FW_POLL_P WIP=0 a teljes írás vége → ST_DONE.
        // en: ST_FW_CS_HI — CS# spacing between two SPI transactions (4 cycles),
        //     then advance the r_fw_step sub-sequencer. On WIP-poll steps
        //     (FW_POLL_E/FW_POLL_P) status[0] decides: WIP=1 → another RDSR,
        //     WIP=0 → next step. FW_POLL_P WIP=0 ends the whole write → ST_DONE.
        // --------------------------------------------------------
        ST_FW_CS_HI: begin
            qspi_cs_flash_n <= 1'b1;
            r_clk_en        <= 1'b0;
            r_clk_phase     <= 1'b0;
            qspi_dq_oe      <= 1'b0;
            qspi_dq_out     <= 4'hF;

            if (r_bit_cnt == 6'd0) begin
                case (r_fw_step)
                    FW_WREN_E: begin
                        r_fw_step <= FW_ERASE;
                        launch_flash_cmd(`QSPI_CMD_FLASH_ERASE);
                    end
                    FW_ERASE: begin
                        r_fw_step <= FW_POLL_E;
                        launch_flash_cmd(`QSPI_CMD_FLASH_RDSR);
                    end
                    FW_POLL_E: begin
                        if (r_status[0]) begin
                            // hu: erase még folyamatban → újabb RDSR
                            // en: erase still in progress → another RDSR
                            launch_flash_cmd(`QSPI_CMD_FLASH_RDSR);
                        end else begin
                            // hu: erase kész → WREN a program előtt
                            // en: erase done → WREN before program
                            r_fw_step <= FW_WREN_P;
                            launch_flash_cmd(`QSPI_CMD_FLASH_WREN);
                        end
                    end
                    FW_WREN_P: begin
                        r_fw_step <= FW_PROGRAM;
                        launch_flash_cmd(`QSPI_CMD_FLASH_PROGRAM);
                    end
                    FW_PROGRAM: begin
                        r_fw_step <= FW_POLL_P;
                        launch_flash_cmd(`QSPI_CMD_FLASH_RDSR);
                    end
                    default: begin   // FW_POLL_P
                        if (r_status[0]) begin
                            // hu: program még folyamatban → újabb RDSR
                            // en: program still in progress → another RDSR
                            launch_flash_cmd(`QSPI_CMD_FLASH_RDSR);
                        end else begin
                            // hu: program kész → teljes flash-write vége
                            // en: program done → whole flash-write complete
                            r_state <= ST_DONE;
                        end
                    end
                endcase
            end else begin
                r_bit_cnt <= r_bit_cnt - 6'd1;
            end
        end

        default: begin
            r_state <= ST_IDLE;
        end

        endcase
    end
end

endmodule
