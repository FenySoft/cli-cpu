// hu: CLI-CPU smoke-teszt — 50 MHz órajel-számláló, két LED villogtatás
//     eltérő ütemben. A Vivado → A7-Lite 200T FPGA bring-up end-to-end
//     flow-ját validálja (synthesis + implementation + bitstream + JTAG
//     programozás), mielőtt a valódi Nano core-t szintetizálnánk.
// en: CLI-CPU smoke test — 50 MHz clock counter blinking two LEDs at
//     different rates. Validates the end-to-end Vivado → A7-Lite 200T
//     FPGA bring-up flow (synthesis + implementation + bitstream + JTAG
//     programming) before synthesizing the real Nano core.
//
// Várt viselkedés / Expected behavior:
//   LED1 (M18): ~0.75 Hz (50 MHz / 2^26) — lassabb villogás
//   LED2 (N18): ~1.5  Hz (50 MHz / 2^25) — kétszer gyorsabb
//
// Megjegyzés az aktivitási szintről / Note on activity level:
//   A MicroPhase A7-Lite LED-ek active-low-k (schematic ellenőrzendő).
//   Ha fordítva világítanak a vártnál, invertáld az o_led1/o_led2 jelet.

`timescale 1ns / 1ps

module led_blink (
    input  wire i_clk_50m,
    output wire o_led1,
    output wire o_led2
);

    reg [24:0] counter = 25'd0;

    always @(posedge i_clk_50m) begin
        counter <= counter + 1'b1;
    end

    assign o_led1 = counter[24];
    assign o_led2 = counter[23];

endmodule
