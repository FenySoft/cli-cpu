# hu: CLI-CPU F2.7 Sub5 — XDC constraint OpenXC7 (nextpnr-xilinx) build-hez
#     a teljes `cilcpu_a7lite_board` top-ra, MicroPhase A7-Lite XC7A200T.
#     Az OpenXC7/nextpnr-xilinx egyszerubb szintaxis: nincs -dict, a clock
#     constraint command-line/SDC-szeruen kezelt, nincs bitstream property.
# en: CLI-CPU F2.7 Sub5 — XDC constraint for the OpenXC7 (nextpnr-xilinx)
#     build of the full `cilcpu_a7lite_board` top, MicroPhase A7-Lite
#     XC7A200T. OpenXC7/nextpnr-xilinx uses simpler syntax: no -dict, the
#     clock constraint is SDC-like, no bitstream properties.
#
# Pin mapping source: docs/A7-Lite/A7-Lite-hu.md ; Xilinx UG475 (FBG484)
#
#  >>> STARTUPE2 / QSPI KORLAT: a CCLK pin a STARTUPE2 primitiven keresztul
#      hajtott. Az nextpnr-xilinx STARTUPE2 binding NEM megbizhatoan
#      tamogatott (lasd README-hu.md Sub5). Ha a P&R itt elbukik, az a
#      dokumentalt OpenXC7-korlat, NEM XDC-hiba. A QSPI DQ/CS pinek IOBUF-on
#      keresztul mennek (tamogatott), de a CCLK STARTUPE2 fuggo.

# 50 MHz orajel / Clock — J19
set_property LOC J19 [get_ports i_clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports i_clk_50m]
create_clock -period 20.000 -name sys_clk [get_ports i_clk_50m]

# Push-buttonok / Push-buttons — KEY1 reset (AA1), KEY2 start (W1)
set_property LOC AA1 [get_ports i_rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports i_rst_btn_n]

set_property LOC W1 [get_ports i_start_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports i_start_btn_n]

# User LED-ek (active low) / User LEDs — D6 (M18), D5 (N18)
set_property LOC M18 [get_ports o_led1_n]
set_property IOSTANDARD LVCMOS33 [get_ports o_led1_n]

set_property LOC N18 [get_ports o_led2_n]
set_property IOSTANDARD LVCMOS33 [get_ports o_led2_n]

# UART TX / UART TX — V2 (CH340 USB-UART bridge)
set_property LOC V2 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]

# QSPI flash (IS25L128F) — Xilinx dedikalt config bank pinek / config bank
#   CCLK (E8) NINCS itt — a STARTUPE2 hajtja a USRCCLKO-n keresztul.
#   FCS_B (T19), D00..D03 (P22, R22, P21, R21).
set_property LOC T19 [get_ports o_qspi_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports o_qspi_cs_n]

set_property LOC P22 [get_ports {io_qspi_dq[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_qspi_dq[0]}]

set_property LOC R22 [get_ports {io_qspi_dq[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_qspi_dq[1]}]

set_property LOC P21 [get_ports {io_qspi_dq[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_qspi_dq[2]}]

set_property LOC R21 [get_ports {io_qspi_dq[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_qspi_dq[3]}]
