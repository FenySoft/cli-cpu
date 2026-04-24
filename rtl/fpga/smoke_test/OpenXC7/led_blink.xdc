# hu: CLI-CPU smoke-teszt — XDC constraint fájl OpenXC7 (nextpnr-xilinx) build-hez
#     MicroPhase A7-Lite XC7A200T board-ra. Az OpenXC7/nextpnr-xilinx
#     egyszerűbb szintaxist használ mint a Vivado — nincs -dict, nincs
#     create_clock (a nextpnr automatikusan kezeli), nincs bitstream
#     konfigurációs property (azok command-line argumentumok).
# en: CLI-CPU smoke test — XDC constraint file for OpenXC7 (nextpnr-xilinx)
#     build targeting the MicroPhase A7-Lite XC7A200T. OpenXC7 uses simpler
#     syntax than Vivado — no -dict, no create_clock (handled by nextpnr
#     automatically), no bitstream configuration properties (those are
#     command-line arguments).
#
# Pin mapping source: docs/A7-Lite/A7-Lite-hu.md

# 50 MHz órajel / Clock
set_property LOC J19 [get_ports i_clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports i_clk_50m]

# User LED-ek / User LEDs
set_property LOC M18 [get_ports o_led1]
set_property IOSTANDARD LVCMOS33 [get_ports o_led1]

set_property LOC N18 [get_ports o_led2]
set_property IOSTANDARD LVCMOS33 [get_ports o_led2]
