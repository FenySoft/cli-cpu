// hu: CLI-CPU F2.7 Sub4 — Xilinx 7-series primitive sim stubok (Verilator).
//     A valódi STARTUPE2 és IOBUF primitivek a Xilinx 'unisims' library-ben
//     élnek, amelyet a Verilator alapból nem lát. Ez a fájl behavioral
//     ekvivalenseket ad, csak szimulációra — Vivado/OpenXC7 buildkor NEM
//     fordul be (a `cilcpu_a7lite_board.v` Verilog-szintaxisa változatlan, de
//     a szintézis a saját 'unisims' verzióját használja).
// en: CLI-CPU F2.7 Sub4 — Xilinx 7-series primitive sim stubs (Verilator).
//     The real STARTUPE2 and IOBUF primitives live in the Xilinx 'unisims'
//     library, which Verilator does not know about. This file provides
//     behavioral equivalents for simulation only — it is NOT compiled by
//     Vivado/OpenXC7 (the `cilcpu_a7lite_board.v` source is unchanged; the
//     synthesizer uses its own 'unisims' models).

`default_nettype none

// ============================================================
// hu: STARTUPE2 — XC7-széria startup és config bank hozzáférés.
//     A CLI-CPU csak az USRCCLKO-t (user CCLK output) használja, hogy a
//     QSPI config flash CLK-ját user módban hajtsa. A többi port no-op.
// en: STARTUPE2 — XC7-series startup and config bank access.
//     CLI-CPU uses only USRCCLKO (user CCLK output) to drive the QSPI
//     config flash CLK in user mode. Other ports are no-ops.
// ============================================================

module STARTUPE2 #(
    parameter PROG_USR      = "FALSE",
    parameter SIM_CCLK_FREQ = 0.0
) (
    output wire CFGCLK,
    output wire CFGMCLK,
    output wire EOS,
    output wire PREQ,
    input  wire CLK,
    input  wire GSR,
    input  wire GTS,
    input  wire KEYCLEARB,
    input  wire PACK,
    input  wire USRCCLKO,
    input  wire USRCCLKTS,
    input  wire USRDONEO,
    input  wire USRDONETS
);
    // hu: Sim-ben EOS azonnal '1' (config kész). A CCLK kimenetet a
    //     felölelő `cilcpu_a7lite_board` exponálja sim-only port-on.
    // en: In sim, EOS asserts immediately (config done). The CCLK output is
    //     exposed by the enclosing `cilcpu_a7lite_board` on a sim-only port.
    assign CFGCLK  = 1'b0;
    assign CFGMCLK = 1'b0;
    assign EOS     = 1'b1;
    assign PREQ    = 1'b0;

    // hu: UNUSED ack a Verilator linthez — minden nem hajtott bemenet
    // en: UNUSED ack for Verilator lint — explicitly mark undriven inputs
    wire _unused_startup_ = &{1'b0, CLK, GSR, GTS, KEYCLEARB, PACK,
                              USRCCLKO, USRCCLKTS, USRDONEO, USRDONETS, 1'b0};
endmodule

// ============================================================
// hu: IOBUF — kétirányú I/O puffer. T='1' → IO tri-state, I figyelmen
//     kívül; T='0' → IO = I. Az O mindig követi az IO-t (a slave is hajtja).
// en: IOBUF — bidirectional I/O buffer. T='1' → IO tri-state, I ignored;
//     T='0' → IO = I. O always follows IO (slave can drive too).
// ============================================================

module IOBUF #(
    parameter         DRIVE      = 12,
    parameter         IBUF_LOW_PWR = "TRUE",
    parameter [1023:0] IOSTANDARD = "DEFAULT",
    parameter         SLEW       = "SLOW"
) (
    output wire O,
    inout  wire IO,
    input  wire I,
    input  wire T
);
    assign IO = T ? 1'bz : I;
    assign O  = IO;
endmodule

`default_nettype wire
