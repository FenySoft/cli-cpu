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
    parameter [23:0] BOOT_PC          = 24'h000008,
    parameter [7:0]  BOOT_ARG_COUNT   = 8'd1,
    parameter [7:0]  BOOT_LOCAL_COUNT = 8'd0,
    parameter [31:0] BOOT_ARG_VALUE   = 32'd5,

    // hu: Debounce számláló bit-szélesség. FPGA-n 22 bit (~84 ms @ 50 MHz),
    //     cocotb sim-ben felülírva 4-re a gyors verifikációhoz.
    // en: Debounce counter bit-width. FPGA: 22 bits (~84 ms @ 50 MHz),
    //     cocotb sim overrides to 4 for fast verification.
    parameter integer DEBOUNCE_BITS   = 22
) (
    // hu: Board-szintű I/O / en: Board-level I/O
    input  wire        i_clk_50m,        // J19 — 50 MHz aktív oszcillátor
    input  wire        i_rst_btn_n,      // KEY1 (AA1) — active low reset
    input  wire        i_start_btn_n,    // KEY2 (W1)  — active low start

    output wire        o_led1_n,         // D6 (M18) — halt indikátor (active low)
    output wire        o_led2_n,         // D5 (N18) — trap indikátor (active low)

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
    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_INIT     = 3'd1;
    localparam [2:0] S_ARG_WAIT = 3'd2;
    localparam [2:0] S_ARG_DRV  = 3'd3;
    localparam [2:0] S_RUN      = 3'd4;
    localparam [2:0] S_DONE     = 3'd5;

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

    always @(posedge i_clk_50m or negedge core_rst_n) begin
        if (!core_rst_n) begin
            r_boot_state       <= S_IDLE;
            r_boot_arg_idx     <= 5'd0;
            r_boot_start_pulse <= 1'b0;
            r_boot_arg_data    <= 32'd0;
            r_boot_arg_valid   <= 1'b0;
        end else begin
            r_boot_start_pulse <= 1'b0;
            r_boot_arg_valid   <= 1'b0;

            case (r_boot_state)
                S_IDLE: begin
                    if (start_pulse) begin
                        r_boot_state       <= S_INIT;
                        r_boot_start_pulse <= 1'b1;
                        r_boot_arg_idx     <= 5'd0;
                    end
                end
                S_INIT: begin
                    if (BOOT_ARG_COUNT == 8'd0)
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
                        r_boot_arg_data  <= BOOT_ARG_VALUE;
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
                    if (core_halt | core_trap)
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
    cilcpu_core u_core (
        .clk                (i_clk_50m),
        .rst_n              (core_rst_n),
        .i_boot_pc          (BOOT_PC),
        .i_boot_arg_count   (BOOT_ARG_COUNT),
        .i_boot_local_count (BOOT_LOCAL_COUNT),
        .i_boot_start       (r_boot_start_pulse),
        .i_boot_arg_data    (r_boot_arg_data),
        .i_boot_arg_valid   (r_boot_arg_valid),
        .o_boot_arg_ready   (core_boot_arg_ready),
        .o_halt             (core_halt),
        .o_trap             (core_trap),
        .o_trap_code        (core_trap_code),
        .o_pc               (core_pc),
        .o_return_value     (core_return_value),
        .qspi_clk           (qspi_clk),
        .qspi_cs_flash_n    (qspi_cs_flash_n),
        .qspi_cs_psram_n    (qspi_cs_psram_n),
        .qspi_dq_out        (qspi_dq_out),
        .qspi_dq_in         (qspi_dq_in),
        .qspi_dq_oe         (qspi_dq_oe)
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
