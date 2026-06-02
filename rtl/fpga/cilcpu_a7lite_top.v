// hu: CLI-CPU F2.7 Sub1 — MicroPhase A7-Lite XC7A200T top-level wrapper.
//     Egyetlen Nano core (cilcpu_core) a board-ra integrálva: 50 MHz clock,
//     KEY1 reset, KEY2 start gomb, két status LED (halt / trap), QSPI flash
//     pass-through. Sub1 hatókör: a wrapper FSM betölt egy fix paramétert és
//     elindítja a core-t — a tényleges program a QSPI flash-ben (cocotb-ben
//     a flash slave coroutine).
// en: CLI-CPU F2.7 Sub1 — MicroPhase A7-Lite XC7A200T top-level wrapper.
//     Single Nano core (cilcpu_core) integrated with the board: 50 MHz clock,
//     KEY1 reset, KEY2 start button, two status LEDs (halt / trap), QSPI
//     flash pass-through. Sub1 scope: the wrapper FSM loads one fixed
//     argument and starts the core — actual program lives on QSPI flash
//     (cocotb provides a flash slave coroutine).

`include "cilcpu_defines.vh"

`default_nettype none

module cilcpu_a7lite_top #(
    // hu: Boot konfiguráció — Sub1-ben fixen drótozva, Sub3-ban
    //     paraméterezhető a Fibonacci(N=20) demóhoz.
    // en: Boot configuration — wired fixed in Sub1, will be parameterized
    //     in Sub3 for the Fibonacci(N=20) demo.
    // hu: A paramétereket méret-nélküli `integer`-rel deklaráljuk, hogy a
    //     command-line `-Gname=value` override (Verilator) ne dobjon
    //     WIDTHTRUNC hibát. A wrapper-en belül szükség szerint slice-eljük
    //     a megfelelő méretű mezőkre.
    // en: Parameters are declared as untyped `integer` so the command-line
    //     `-Gname=value` override does not raise WIDTHTRUNC.
    //     The wrapper slices each parameter to the right width as needed.
    parameter integer BOOT_PC          = 32'h00000008,
    parameter integer BOOT_ARG_COUNT   = 32'd1,
    parameter integer BOOT_LOCAL_COUNT = 32'd0,
    parameter integer BOOT_ARG_VALUE   = 32'd5,

    // hu: Debounce számláló bit-szélesség. FPGA-n 22 bit (~84 ms @ 50 MHz),
    //     cocotb sim-ben felülírva 4-re a gyors verifikációhoz.
    // en: Debounce counter bit-width. FPGA: 22 bits (~84 ms @ 50 MHz),
    //     cocotb sim overrides to 4 for fast verification.
    parameter integer DEBOUNCE_BITS   = 22,

    // hu: UART baud-osztó. FPGA: 50 MHz / 115200 = 434, sim-ben 8-ra
    //     felülírjuk (Sub2).
    // en: UART baud divider. FPGA: 50 MHz / 115200 = 434, overridden to 8
    //     in sim (Sub2).
    parameter integer CLOCKS_PER_BAUD = 434,

    // hu: Sub5.A — CODE szegmens flash-bázis offszet. Sim default 0
    //     (cocotb flash-paritás); FPGA-n a Vivado `set_property generic`
    //     / OpenXC7 `-G` a config-flash bitstream FÖLÉ (0xC00000 = 12 MB)
    //     állítja, hogy a ~9,9 MB XC7A200T bitstream és a CIL-T0 app ne
    //     ütközzön az IS25L128F-en. Áthajtva a `cilcpu_core`-ba.
    // en: Sub5.A — CODE segment flash base offset. Sim default 0 (cocotb
    //     flash parity); on FPGA Vivado `set_property generic` / OpenXC7
    //     `-G` sets it ABOVE the config-flash bitstream (0xC00000 = 12 MB)
    //     so the ~9.9 MB XC7A200T bitstream and the CIL-T0 app do not
    //     collide on the IS25L128F. Forwarded to `cilcpu_core`.
    parameter integer CODE_BASE_OFFSET = 0,

    // hu: F2.7 Sub5 — flash QE-bit init engedélyezése a QSPI controllerben
    //     (a `cilcpu_core`-on át a `cilcpu_qspi_controller`-be hajtva).
    //     Default 0 → sim-paritás; FPGA-n a Vivado generic 1-re állítja.
    // en: F2.7 Sub5 — flash QE-bit init enable for the QSPI controller
    //     (forwarded through `cilcpu_core` to `cilcpu_qspi_controller`).
    //     Default 0 → sim parity; on FPGA Vivado generic sets it to 1.
    parameter integer QE_INIT_ENABLE = 0
) (
    // hu: Board-szintű I/O / en: Board-level I/O
    input  wire        i_clk_50m,        // J19 — 50 MHz aktív oszcillátor
    input  wire        i_rst_btn_n,      // KEY1 (AA1) — active low reset
    input  wire        i_start_btn_n,    // KEY2 (W1)  — active low start

    output wire        o_led1_n,         // D6 (M18) — halt indikátor (active low)
    output wire        o_led2_n,         // D5 (N18) — trap indikátor (active low)
    output wire        o_uart_tx,        // V2 — UART TX (a CH340-en a host felé)

    // hu: QSPI flash pass-through — Sub4-ben kerül XDC-vel a board flash-re.
    // en: QSPI flash pass-through — Sub4 binds these to the board flash via XDC.
    output wire        qspi_clk,
    output wire        qspi_cs_flash_n,
    output wire        qspi_cs_psram_n,
    output wire [3:0]  qspi_dq_out,
    input  wire [3:0]  qspi_dq_in,
    output wire        qspi_dq_oe
);

    // ============================================================
    // hu: Reset szinkronizer — async assert, sync deassert (3-stage)
    // en: Reset synchronizer — async assert, sync deassert (3-stage)
    // ============================================================
    reg [2:0] r_rst_sync;
    always @(posedge i_clk_50m or negedge i_rst_btn_n) begin
        if (!i_rst_btn_n)
            r_rst_sync <= 3'b000;
        else
            r_rst_sync <= {r_rst_sync[1:0], 1'b1};
    end
    wire core_rst_n = r_rst_sync[2];

    // ============================================================
    // hu: Start gomb — 2-stage CDC sync + debounce + edge detect
    // en: Start button — 2-stage CDC sync + debounce + edge detect
    // ============================================================
    reg [1:0] r_start_sync;
    always @(posedge i_clk_50m or negedge core_rst_n) begin
        if (!core_rst_n)
            r_start_sync <= 2'b11;
        else
            r_start_sync <= {r_start_sync[0], i_start_btn_n};
    end
    wire start_raw_n = r_start_sync[1];

    reg [DEBOUNCE_BITS-1:0] r_db_cnt;
    reg                     r_start_stable;
    reg                     r_start_stable_d;

    always @(posedge i_clk_50m or negedge core_rst_n) begin
        if (!core_rst_n) begin
            r_db_cnt         <= {DEBOUNCE_BITS{1'b0}};
            r_start_stable   <= 1'b1;
            r_start_stable_d <= 1'b1;
        end else begin
            r_start_stable_d <= r_start_stable;
            if (start_raw_n == r_start_stable) begin
                r_db_cnt <= {DEBOUNCE_BITS{1'b0}};
            end else if (&r_db_cnt) begin
                r_start_stable <= start_raw_n;
                r_db_cnt       <= {DEBOUNCE_BITS{1'b0}};
            end else begin
                r_db_cnt <= r_db_cnt + {{(DEBOUNCE_BITS-1){1'b0}}, 1'b1};
            end
        end
    end

    // hu: Falling edge a stabil jelen → start_pulse
    // en: Falling edge on stable signal → start_pulse
    wire start_pulse = r_start_stable_d & ~r_start_stable;

    // ============================================================
    // hu: Boot FSM — KEY2 lenyomásra elindítja a core-t, push-olja az
    //     argumentumokat és átmegy futás módba. Ha a core halt-ol vagy
    //     trap-el, latch-eljük a státuszt és felgyújtjuk a megfelelő LED-et.
    // en: Boot FSM — on KEY2 press, starts the core, pushes arguments,
    //     and switches to RUN. On halt/trap, latches status and lights
    //     the appropriate LED.
    // ============================================================
    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_INIT      = 3'd1;
    localparam [2:0] S_ARG_WAIT  = 3'd2;
    localparam [2:0] S_ARG_DRV   = 3'd3;
    localparam [2:0] S_RUN       = 3'd4;
    localparam [2:0] S_PRINT_REQ = 3'd5;   // Sub2: indítja a printer-t
    localparam [2:0] S_PRINT_WAIT = 3'd6;  // Sub2: várja a printer leesését
    localparam [2:0] S_DONE      = 3'd7;

    reg  [2:0]  r_boot_state;
    reg  [4:0]  r_boot_arg_idx;
    reg         r_boot_start_pulse;
    reg  [31:0] r_boot_arg_data;
    reg         r_boot_arg_valid;

    wire        core_halt;
    wire        core_trap;
    wire [7:0]  core_trap_code;
    wire [23:0] core_pc;
    wire [31:0] core_return_value;
    wire        core_boot_arg_ready;

    // hu: Printer interfész regiszterek (Sub2)
    // en: Printer interface registers (Sub2)
    reg  [31:0] r_print_value;
    reg         r_print_signed;
    reg         r_print_start;
    wire        w_print_busy;

    always @(posedge i_clk_50m or negedge core_rst_n) begin
        if (!core_rst_n) begin
            r_boot_state       <= S_IDLE;
            r_boot_arg_idx     <= 5'd0;
            r_boot_start_pulse <= 1'b0;
            r_boot_arg_data    <= 32'd0;
            r_boot_arg_valid   <= 1'b0;
            r_print_value      <= 32'd0;
            r_print_signed     <= 1'b0;
            r_print_start      <= 1'b0;
        end else begin
            r_boot_start_pulse <= 1'b0;
            r_boot_arg_valid   <= 1'b0;
            r_print_start      <= 1'b0;

            case (r_boot_state)
                S_IDLE: begin
                    if (start_pulse) begin
                        r_boot_state       <= S_INIT;
                        r_boot_start_pulse <= 1'b1;
                        r_boot_arg_idx     <= 5'd0;
                    end
                end
                S_INIT: begin
                    if (BOOT_ARG_COUNT[7:0] == 8'd0)
                        r_boot_state <= S_RUN;
                    else
                        r_boot_state <= S_ARG_WAIT;
                end
                S_ARG_WAIT: begin
                    if (core_boot_arg_ready) begin
                        // hu: Sub1-ben minden argumentumra azonos érték.
                        //     Sub3-ban argumentum-tömb paraméter lép be.
                        // en: In Sub1 all args use the same value.
                        //     Sub3 will introduce an argument array param.
                        r_boot_arg_data  <= BOOT_ARG_VALUE[31:0];
                        r_boot_arg_valid <= 1'b1;
                        r_boot_state     <= S_ARG_DRV;
                    end
                end
                S_ARG_DRV: begin
                    r_boot_arg_idx <= r_boot_arg_idx + 5'd1;
                    if ((r_boot_arg_idx + 5'd1) >= BOOT_ARG_COUNT[4:0])
                        r_boot_state <= S_RUN;
                    else
                        r_boot_state <= S_ARG_WAIT;
                end
                S_RUN: begin
                    if (core_halt) begin
                        // hu: halt → printer beállítása signed return_value-val
                        r_print_value  <= core_return_value;
                        r_print_signed <= 1'b1;
                        r_boot_state   <= S_PRINT_REQ;
                    end else if (core_trap) begin
                        // hu: trap → printer beállítása unsigned trap_code-dal
                        r_print_value  <= {24'd0, core_trap_code};
                        r_print_signed <= 1'b0;
                        r_boot_state   <= S_PRINT_REQ;
                    end
                end
                S_PRINT_REQ: begin
                    r_print_start <= 1'b1;
                    r_boot_state  <= S_PRINT_WAIT;
                end
                S_PRINT_WAIT: begin
                    // hu: Várjuk meg, amíg a printer befejezi (busy 0,
                    //     start már alacsony).
                    // en: Wait for the printer to finish (busy 0, start
                    //     already low).
                    if (!w_print_busy && !r_print_start)
                        r_boot_state <= S_DONE;
                end
                S_DONE: begin
                    // hu: Latched, hold állapot — KEY1 reset oldja fel.
                    // en: Latched, hold state — KEY1 reset clears.
                end
                default: r_boot_state <= S_IDLE;
            endcase
        end
    end

    // ============================================================
    // hu: Latched halt / trap riport — LED-ek tartottak resetig
    // en: Latched halt / trap report — LEDs hold until reset
    // ============================================================
    reg r_halted;
    reg r_trapped;

    always @(posedge i_clk_50m or negedge core_rst_n) begin
        if (!core_rst_n) begin
            r_halted  <= 1'b0;
            r_trapped <= 1'b0;
        end else begin
            if (core_halt)
                r_halted <= 1'b1;
            if (core_trap)
                r_trapped <= 1'b1;
        end
    end

    // ============================================================
    // hu: Nano core példányosítás
    // en: Nano core instantiation
    // ============================================================
    // hu: F1a — a Core külső-memória-master busza a lokális QSPI controllerhez.
    // en: F1a — the Core's external-memory master bus to the local QSPI ctrl.
    wire [23:0] w_xmem_addr;
    wire        w_xmem_re;
    wire [31:0] w_xmem_rdata;
    wire        w_xmem_ready;
    wire        w_xmem_busy;

    cilcpu_core u_core (
        .clk                (i_clk_50m),
        .rst_n              (core_rst_n),
        .i_boot_pc          (BOOT_PC[23:0]),
        .i_boot_arg_count   (BOOT_ARG_COUNT[7:0]),
        .i_boot_local_count (BOOT_LOCAL_COUNT[7:0]),
        .i_boot_start       (r_boot_start_pulse),
        .i_boot_arg_data    (r_boot_arg_data),
        .i_boot_arg_valid   (r_boot_arg_valid),
        .o_boot_arg_ready   (core_boot_arg_ready),
        .o_halt             (core_halt),
        .o_trap             (core_trap),
        .o_trap_code        (core_trap_code),
        .o_pc               (core_pc),
        .o_return_value     (core_return_value),
        .o_xmem_addr        (w_xmem_addr),
        .o_xmem_re          (w_xmem_re),
        .i_xmem_rdata       (w_xmem_rdata),
        .i_xmem_ready       (w_xmem_ready),
        .i_xmem_busy        (w_xmem_busy),
        // hu: MMIO-master busz (F2.8 #6.2) — az MMIO wrapper-periféria (#6.5)
        //     egyelőre nincs integrálva ezen a board-on, így a kimenetek
        //     nyitva, az i_mmio_rdata 0-ra fogva. A jelenlegi single-core Fib
        //     boot nem használ 0xF szegmensű LDIND/STIND-et → viselkedés-semleges.
        // en: MMIO master bus (F2.8 #6.2) — the MMIO wrapper peripherals
        //     (#6.5) are not yet integrated on this board, so outputs are left
        //     open and i_mmio_rdata is tied to 0. The current single-core Fib
        //     boot uses no 0xF-segment LDIND/STIND → behavior-neutral.
        .o_mmio_addr        (),
        .o_mmio_wdata       (),
        .o_mmio_we          (),
        .o_mmio_re          (),
        .i_mmio_rdata       (32'd0),
        // hu: F3 — on-chip SRAM load-write port LEKÖTVE. Ez a LEGACY F2.7
        //     wrapper (közvetlen core+QSPI, NINCS loader/copy-engine), így nincs
        //     útja a programot az on-chip SRAM-ba juttatni → az egységes-SRAM
        //     core ezen a board-on NEM futtatható. F3-ban a SoC-alapú
        //     `cilcpu_tt_board` váltja ki (loader + copy-engine). Lásd a
        //     test_a7lite_* skip-jét.
        // en: F3 — on-chip SRAM load-write port TIED OFF. This is the LEGACY F2.7
        //     wrapper (direct core+QSPI, NO loader/copy engine), so it has no way
        //     to populate the on-chip SRAM → the unified-SRAM core cannot run on
        //     this board. Superseded by the SoC-based `cilcpu_tt_board` in F3.
        .i_ld_we            (1'b0),
        .i_ld_addr          (14'd0),
        .i_ld_wdata         (32'd0)
    );

    // hu: F1a — QSPI controller a Core-ból kiemelve a board-topra. A Core
    //     read-only mestere (cpu_we=0); a flash QE-init + CODE_BASE_OFFSET
    //     generic-ek mostantól ide kötve. A qspi_* pinek innen jönnek.
    // en: F1a — QSPI controller moved out of the Core to the board top. The Core
    //     is a read-only master (cpu_we=0); the flash QE-init + CODE_BASE_OFFSET
    //     generics bind here now. The qspi_* pins originate here.
    cilcpu_qspi_controller #(
        .CODE_BASE_OFFSET (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE   (QE_INIT_ENABLE)
    ) u_qspi (
        .clk             (i_clk_50m),
        .rst_n           (core_rst_n),
        .cpu_addr        (w_xmem_addr),
        .cpu_wdata       (32'd0),
        .cpu_rdata       (w_xmem_rdata),
        .cpu_re          (w_xmem_re),
        .cpu_we          (1'b0),
        .cpu_ready       (w_xmem_ready),
        .cpu_busy        (w_xmem_busy),
        .qspi_clk        (qspi_clk),
        .qspi_cs_flash_n (qspi_cs_flash_n),
        .qspi_cs_psram_n (qspi_cs_psram_n),
        .qspi_dq_out     (qspi_dq_out),
        .qspi_dq_in      (qspi_dq_in),
        .qspi_dq_oe      (qspi_dq_oe)
    );

    // ============================================================
    // hu: Decimális printer — halt/trap értéket ASCII-decimálisban küldi
    //     ki UART-on (8N1 @ CLOCKS_PER_BAUD baud). Egy belső uart_tx-et
    //     vezérel, és \r\n terminátorral zárja a sort.
    // en: Decimal printer — sends halt/trap value as ASCII decimal over
    //     UART (8N1 @ CLOCKS_PER_BAUD baud). Drives an internal uart_tx
    //     and terminates the line with \r\n.
    // ============================================================
    decimal_printer #(
        .CLOCKS_PER_BAUD (CLOCKS_PER_BAUD)
    ) u_printer (
        .clk     (i_clk_50m),
        .rst_n   (core_rst_n),
        .i_value (r_print_value),
        .i_signed(r_print_signed),
        .i_start (r_print_start),
        .o_busy  (w_print_busy),
        .o_tx    (o_uart_tx)
    );

    // ============================================================
    // hu: LED kimenetek — A7-Lite LED-jei active-low (anód VCC, katód
    //     az FPGA pin-en); a LED akkor világít, ha a pin logikai 0.
    // en: LED outputs — A7-Lite LEDs are active-low (anode on VCC,
    //     cathode on the FPGA pin); the LED lights when the pin is 0.
    // ============================================================
    assign o_led1_n = ~r_halted;
    assign o_led2_n = ~r_trapped;

endmodule

`default_nettype wire
