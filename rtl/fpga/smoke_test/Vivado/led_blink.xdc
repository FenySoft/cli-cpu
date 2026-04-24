# hu: CLI-CPU smoke-teszt — XDC constraint fájl MicroPhase A7-Lite XC7A200T-hez
# en: CLI-CPU smoke test — XDC constraint file for MicroPhase A7-Lite XC7A200T
#
# Pin mapping forrás / Pin mapping source:
#   docs/A7-Lite/A7-Lite-hu.md
#   MicroPhase fpga-docs: A7-Lite_Reference_Manual.md

# =============================================================
# 50 MHz órajel / Clock
# =============================================================

set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports i_clk_50m]
create_clock -period 20.000 -name sys_clk -waveform {0 10} -add [get_ports i_clk_50m]

# =============================================================
# User LED-ek / User LEDs
# =============================================================

set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33 } [get_ports o_led1]
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33 } [get_ports o_led2]

# =============================================================
# Bitstream konfiguráció / Bitstream configuration
# =============================================================

# hu: A7-Lite QSPI flash 3.3V feszültségen, x4 bus, 33 MHz config rate.
#     A board-on az FPGA konfiguráció bankje (bank 0) 3.3V-on megy,
#     így CFGBVS = VCCO szükséges.
# en: A7-Lite QSPI flash runs at 3.3V, x4 bus, 33 MHz config rate.
#     Config bank (bank 0) uses 3.3V, so CFGBVS = VCCO is required.

set_property CONFIG_VOLTAGE 3.3                     [current_design]
set_property CFGBVS VCCO                            [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4        [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33         [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE        [current_design]
