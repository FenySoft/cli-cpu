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

module cilcpu_qspi_controller (
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
        // hu: Reset — minden regiszter törlése
        // en: Reset — clear all registers
        r_state          <= ST_IDLE;
        r_bit_cnt        <= 6'd0;
        r_cmd            <= 8'd0;
        r_addr           <= 24'd0;
        r_shift_out      <= 32'd0;
        r_shift_in       <= 32'd0;
        r_clk_phase      <= 1'b0;
        r_is_write       <= 1'b0;
        r_device         <= 1'b0;
        r_clk_en         <= 1'b0;
        cpu_ready        <= 1'b0;
        cpu_rdata        <= 32'd0;
        qspi_cs_flash_n  <= 1'b1;
        qspi_cs_psram_n  <= 1'b1;
        qspi_dq_out      <= 4'hF;
        qspi_dq_oe       <= 1'b0;
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
                            // hu: Flash olvasás — CODE
                            // en: Flash read — CODE
                            r_cmd            <= `QSPI_CMD_FLASH_READ;
                            r_addr           <= {4'h0, cpu_addr[19:0]};
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
                            // hu: Flash-be írás elutasítva — cpu_ready azonnal
                            // en: Flash write rejected — immediate cpu_ready
                            cpu_ready <= 1'b1;
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
                            // hu: Flash-be írás elutasítva
                            // en: Flash write rejected
                            cpu_ready <= 1'b1;
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
                    // hu: Utolsó bit — átmenet ST_ADDR-ba
                    // en: Last bit — transition to ST_ADDR
                    // hu: A következő fázis beállítása: ADDR, 24 SPI bit (Flash) vagy 6 Quad CLK (PSRAM)
                    // en: Setup next phase: ADDR, 24 SPI bits (Flash) or 6 Quad CLKs (PSRAM)
                    if (r_device == 1'b0) begin
                        // hu: Flash — SPI ADDR (24 bit, 1 bit/CLK)
                        // en: Flash — SPI ADDR (24 bits, 1 bit/CLK)
                        r_bit_cnt <= 6'd23;
                    end else begin
                        // hu: PSRAM — Quad ADDR (24 bit, 4 bit/CLK = 6 CLK)
                        // en: PSRAM — Quad ADDR (24 bits, 4 bits/CLK = 6 CLKs)
                        r_bit_cnt <= 6'd5;
                    end
                    r_state <= ST_ADDR;
                    // hu: Setup az ADDR első nibble/bit
                    // en: Setup the first ADDR nibble/bit
                    if (r_device == 1'b0) begin
                        // hu: Flash SPI ADDR: bit[23] → DQ[0]
                        qspi_dq_out <= {3'b111, r_addr[23]};
                    end else begin
                        // hu: PSRAM Quad ADDR: addr[23:20] → DQ[3:0]
                        qspi_dq_out <= r_addr[23:20];
                    end
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

        default: begin
            r_state <= ST_IDLE;
        end

        endcase
    end
end

endmodule
