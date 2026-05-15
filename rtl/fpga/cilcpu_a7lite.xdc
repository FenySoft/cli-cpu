# hu: CLI-CPU F2.7 — XDC constraint fájl MicroPhase A7-Lite XC7A200T-hez.
#     Top module: cilcpu_a7lite_board (Sub4-től). A board-szintű wrapper
#     a `cilcpu_a7lite_top`-ot kötögeti az IS25L128F QSPI config flash-re
#     egy STARTUPE2 primitív (CCLK) és négy IOBUF (DQ[3:0]) segítségével.
# en: CLI-CPU F2.7 — XDC constraint file for MicroPhase A7-Lite XC7A200T.
#     Top module: cilcpu_a7lite_board (from Sub4). The board-level wrapper
#     binds `cilcpu_a7lite_top` to the IS25L128F QSPI config flash via a
#     STARTUPE2 primitive (CCLK) and four IOBUFs (DQ[3:0]).
#
# Pin mapping forrás / Pin mapping source:
#   docs/A7-Lite/A7-Lite-hu.md
#   MicroPhase fpga-docs: A7-LITE_R11.pdf
#   Xilinx UG475 (7-series Package and Pinout), FBG484 dedicated config pins

# =============================================================
# hu: 50 MHz órajel — J19 (aktív oszcillátor)
# en: 50 MHz clock — J19 (active oscillator)
# =============================================================

set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports i_clk_50m]
create_clock -period 20.000 -name sys_clk -waveform {0 10} -add [get_ports i_clk_50m]

# =============================================================
# hu: Push-button-ok — KEY1 = reset, KEY2 = start
# en: Push-buttons — KEY1 = reset, KEY2 = start
# =============================================================

set_property -dict { PACKAGE_PIN AA1  IOSTANDARD LVCMOS33  PULLUP true } [get_ports i_rst_btn_n]
set_property -dict { PACKAGE_PIN W1   IOSTANDARD LVCMOS33  PULLUP true } [get_ports i_start_btn_n]

# hu: Aszinkron bemenet — set_false_path a CDC szinkronizerhez
# en: Asynchronous input — set_false_path for the CDC synchronizer
set_input_delay -clock sys_clk 0 [get_ports {i_rst_btn_n i_start_btn_n}]
set_false_path -from [get_ports {i_rst_btn_n i_start_btn_n}]

# =============================================================
# hu: User LED-ek (active low) — D6, D5
# en: User LEDs (active low) — D6, D5
# =============================================================

set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_led1_n]
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_led2_n]

set_output_delay -clock sys_clk 0 [get_ports {o_led1_n o_led2_n}]

# =============================================================
# hu: UART TX — CH340 USB-UART bridge, V2 az FPGA UART_TX pinje
# en: UART TX — CH340 USB-UART bridge, V2 is the FPGA UART_TX pin
# =============================================================

set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_uart_tx]
set_output_delay -clock sys_clk 0 [get_ports o_uart_tx]

# =============================================================
# hu: QSPI flash (IS25L128F) — Xilinx dedikált config bank pinek
#     A CCLK fizikai pinje (E8) NEM kerül XDC-be: a STARTUPE2 primitív
#     hajtja a USRCCLKO-n keresztül (lásd cilcpu_a7lite_board.v).
#     A FCS_B / D00..D03 pinek FBG484 csomagon fixek.
# en: QSPI flash (IS25L128F) — Xilinx dedicated config bank pins.
#     The CCLK physical pin (E8) is NOT in the XDC: STARTUPE2 drives it
#     through USRCCLKO (see cilcpu_a7lite_board.v). FCS_B / D00..D03
#     are fixed in the FBG484 package.
# =============================================================

set_property -dict { PACKAGE_PIN T19  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports o_qspi_cs_n]
set_property -dict { PACKAGE_PIN P22  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi_dq[0]}]
set_property -dict { PACKAGE_PIN R22  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi_dq[1]}]
set_property -dict { PACKAGE_PIN P21  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi_dq[2]}]
set_property -dict { PACKAGE_PIN R21  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi_dq[3]}]

# =============================================================
# hu: QSPI CLK virtuális generált órajel — STARTUPE2 USRCCLKO-n keresztül.
#     A `cilcpu_qspi_controller` egy /2 osztóval (50 MHz → 25 MHz) gated
#     CLK-ot generál, ezt a Vivado/OpenXC7-nek deklarálni kell a STA-hoz.
#     A IS25L128F max 80 MHz @ Fast Read Quad (0x6B); 25 MHz lazán fér bele.
# en: QSPI CLK virtual generated clock — through STARTUPE2 USRCCLKO.
#     The `cilcpu_qspi_controller` generates a /2 gated CLK (50 MHz → 25 MHz),
#     declared here for Vivado/OpenXC7 STA. IS25L128F supports max 80 MHz
#     @ Fast Read Quad (0x6B); 25 MHz fits comfortably.
# =============================================================

create_generated_clock -name qspi_sck \
    -source [get_pins -hier -filter {NAME =~ */u_startupe2/USRCCLKO}] \
    -divide_by 2 \
    [get_pins -hier -filter {NAME =~ */u_startupe2/USRCCLKO}]

# hu: IS25L128F datasheet — Fast Read Quad I/O (0x6B):
#     tV (CLK low → output valid)   max ~7 ns
#     tCLQH (output hold from CLK)  min ~1.5 ns
#     tIS (input setup before CLK)  min 2 ns
#     tIH (input hold after CLK)    min 2 ns
#     Becsült PCB trace delay: ~0.5 ns. A Sub5-ben mérjük és pontosítjuk.
# en: IS25L128F datasheet — Fast Read Quad I/O (0x6B):
#     tV (CLK low → output valid)   max ~7 ns
#     tCLQH (output hold from CLK)  min ~1.5 ns
#     tIS (input setup before CLK)  min 2 ns
#     tIH (input hold after CLK)    min 2 ns
#     Estimated PCB trace delay: ~0.5 ns. Measured and tightened in Sub5.

# hu: A DQ vonalak bemenetként a flash által hajtottak — clock-to-output
# en: DQ lines as inputs are driven by the flash — clock-to-output
set_input_delay  -clock qspi_sck -min 1.5 [get_ports {io_qspi_dq[*]}]
set_input_delay  -clock qspi_sck -max 7.5 [get_ports {io_qspi_dq[*]}]

# hu: A DQ vonalak kimenetként mi hajtjuk őket — setup/hold a flash felé
# en: DQ lines as outputs are driven by us — setup/hold to the flash
set_output_delay -clock qspi_sck -min -2.0 [get_ports {io_qspi_dq[*] o_qspi_cs_n}]
set_output_delay -clock qspi_sck -max  2.5 [get_ports {io_qspi_dq[*] o_qspi_cs_n}]

# =============================================================
# hu: Bitstream konfiguráció — A7-Lite QSPI flash 3.3V, x4 bus, 33 MHz
# en: Bitstream configuration — A7-Lite QSPI flash 3.3V, x4 bus, 33 MHz
# =============================================================

set_property CONFIG_VOLTAGE 3.3                     [current_design]
set_property CFGBVS VCCO                            [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4        [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33         [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE        [current_design]
