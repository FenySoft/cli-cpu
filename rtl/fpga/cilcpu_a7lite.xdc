# hu: CLI-CPU F2.7 — XDC constraint fájl MicroPhase A7-Lite XC7A200T-hez.
#     Top module: cilcpu_a7lite_top. Sub1: clock + KEY-ek + LED-ek.
#     A QSPI flash pinek a Sub4-ben kerülnek bekötésre (STARTUPE2 +
#     dedicated config bank).
# en: CLI-CPU F2.7 — XDC constraint file for MicroPhase A7-Lite XC7A200T.
#     Top module: cilcpu_a7lite_top. Sub1: clock + KEYs + LEDs.
#     QSPI flash pins will be added in Sub4 (STARTUPE2 + dedicated config bank).
#
# Pin mapping forrás / Pin mapping source:
#   docs/A7-Lite/A7-Lite-hu.md
#   MicroPhase fpga-docs: A7-LITE_R11.pdf

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
# hu: QSPI flash pinek — Sub4-ben véglegesítve
#     A config flash a Xilinx dedicated config bank-jában van
#     (CCLK, D00, D01, D02, D03 — user módban a STARTUPE2 primitíven át
#     érhetők el). Sub1-ben placeholder, hogy a build-flow elköteleződjön.
# en: QSPI flash pins — finalized in Sub4. The config flash sits in the
#     Xilinx dedicated config bank (CCLK, D00..D03 — accessible in user mode
#     via the STARTUPE2 primitive). Placeholder in Sub1 to commit the flow.
# =============================================================

# hu: Sub4-ben aktiválva — addig a porton OBUF/IBUF default mehetnek a Vivado-tól.
# en: Activated in Sub4 — until then OBUF/IBUF defaults from Vivado are fine.
# set_property -dict { PACKAGE_PIN ?  IOSTANDARD LVCMOS33 } [get_ports qspi_clk]
# set_property -dict { PACKAGE_PIN ?  IOSTANDARD LVCMOS33 } [get_ports qspi_cs_flash_n]
# set_property -dict { PACKAGE_PIN ?  IOSTANDARD LVCMOS33 } [get_ports qspi_cs_psram_n]
# set_property -dict { PACKAGE_PIN ?  IOSTANDARD LVCMOS33 } [get_ports {qspi_dq_out[0] qspi_dq_out[1] qspi_dq_out[2] qspi_dq_out[3]}]
# set_property -dict { PACKAGE_PIN ?  IOSTANDARD LVCMOS33 } [get_ports {qspi_dq_in[0] qspi_dq_in[1] qspi_dq_in[2] qspi_dq_in[3]}]

# =============================================================
# hu: Bitstream konfiguráció — A7-Lite QSPI flash 3.3V, x4 bus, 33 MHz
# en: Bitstream configuration — A7-Lite QSPI flash 3.3V, x4 bus, 33 MHz
# =============================================================

set_property CONFIG_VOLTAGE 3.3                     [current_design]
set_property CFGBVS VCCO                            [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4        [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33         [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE        [current_design]
