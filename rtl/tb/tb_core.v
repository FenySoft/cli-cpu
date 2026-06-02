// hu: CLI-CPU F2.8 #6.5b-F1a — Core unit-teszt fixture. A QSPI controller F1a-ban
//     a Core-ból a SoC/board szintre került; a Core mostantól eszköz-agnosztikus
//     külső-memória-master portot (o_xmem_*/i_xmem_*) ad. Ez a fixture újraköti a
//     Core-t egy cilcpu_qspi_controller-rel, és kivezeti a régi qspi_* pineket +
//     a boot/státusz portokat NÉVAZONOSAN a régi cilcpu_core-éval — így a meglévő
//     cocotb harness (qspi_flash_driver / boot_and_run / reset_dut) változatlanul
//     vezérli a test_core / test_core_golden teszteket. A Core read-only xmem
//     interfésze így a valódi QSPI controlleren át tesztelt.
// en: CLI-CPU F2.8 #6.5b-F1a — Core unit-test fixture. In F1a the QSPI controller
//     moved out of the Core to the SoC/board level; the Core now exposes a
//     device-agnostic external-memory master (o_xmem_*/i_xmem_*). This fixture
//     rewires the Core with a cilcpu_qspi_controller and exposes the old qspi_*
//     pins + boot/status ports with the SAME names as the old cilcpu_core — so
//     the existing cocotb harness (qspi_flash_driver / boot_and_run / reset_dut)
//     drives the test_core / test_core_golden tests unchanged. The Core's
//     read-only xmem interface is thus exercised through the real QSPI ctrl.

`default_nettype none

module tb_core #(
    parameter integer CODE_BASE_OFFSET = 0,
    parameter integer QE_INIT_ENABLE   = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Boot konfiguráció (névazonos a cilcpu_core-ral)
    input  wire [23:0] i_boot_pc,
    input  wire [7:0]  i_boot_arg_count,
    input  wire [7:0]  i_boot_local_count,
    input  wire        i_boot_start,
    input  wire [31:0] i_boot_arg_data,
    input  wire        i_boot_arg_valid,
    output wire        o_boot_arg_ready,

    // hu: Státusz
    output wire        o_halt,
    output wire        o_trap,
    output wire [7:0]  o_trap_code,
    output wire [23:0] o_pc,
    output wire [31:0] o_return_value,

    // hu: QSPI pinek (a fixture-beli controllerből — a harness ezeket hajtja)
    output wire        qspi_clk,
    output wire        qspi_cs_flash_n,
    output wire        qspi_cs_psram_n,
    output wire [3:0]  qspi_dq_out,
    input  wire [3:0]  qspi_dq_in,
    output wire        qspi_dq_oe,

    // hu: A Core MMIO-master busza átvezetve — a test_core MMIO-tesztjei
    //     (test_55/56) közvetlenül ezeket hajtják/olvassák.
    // en: The Core's MMIO master bus passed through — test_core's MMIO tests
    //     (test_55/56) drive/read these directly.
    output wire [31:0] o_mmio_addr,
    output wire [31:0] o_mmio_wdata,
    output wire        o_mmio_we,
    output wire        o_mmio_re,
    input  wire [31:0] i_mmio_rdata
);

    // hu: Core ↔ QSPI controller külső-memória-master busz
    // en: Core ↔ QSPI controller external-memory master bus
    wire [23:0] w_xmem_addr;
    wire        w_xmem_re;
    wire [31:0] w_xmem_rdata;
    wire        w_xmem_ready;
    wire        w_xmem_busy;

    cilcpu_core u_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_boot_pc          (i_boot_pc),
        .i_boot_arg_count   (i_boot_arg_count),
        .i_boot_local_count (i_boot_local_count),
        .i_boot_start       (i_boot_start),
        .i_boot_arg_data    (i_boot_arg_data),
        .i_boot_arg_valid   (i_boot_arg_valid),
        .o_boot_arg_ready   (o_boot_arg_ready),
        .o_halt             (o_halt),
        .o_trap             (o_trap),
        .o_trap_code        (o_trap_code),
        .o_pc               (o_pc),
        .o_return_value     (o_return_value),
        .o_xmem_addr        (w_xmem_addr),
        .o_xmem_re          (w_xmem_re),
        .i_xmem_rdata       (w_xmem_rdata),
        .i_xmem_ready       (w_xmem_ready),
        .i_xmem_busy        (w_xmem_busy),
        // hu: MMIO-master átvezetve a fixture portjaira (test_55/56)
        .o_mmio_addr        (o_mmio_addr),
        .o_mmio_wdata       (o_mmio_wdata),
        .o_mmio_we          (o_mmio_we),
        .o_mmio_re          (o_mmio_re),
        .i_mmio_rdata       (i_mmio_rdata),
        // hu: F3 — a core-tesztek backdoor-poke-kal töltik az r_sram-ot, a
        //     load-write portot lekötjük.
        // en: F3 — the core tests backdoor-poke r_sram; tie off the load port.
        .i_ld_we            (1'b0),
        .i_ld_addr          (14'd0),
        .i_ld_wdata         (32'd0)
    );

    cilcpu_qspi_controller #(
        .CODE_BASE_OFFSET (CODE_BASE_OFFSET),
        .QE_INIT_ENABLE   (QE_INIT_ENABLE)
    ) u_qspi (
        .clk             (clk),
        .rst_n           (rst_n),
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

endmodule

`default_nettype wire
