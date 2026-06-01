# hu: CLI-CPU F2.8.6 — XDC a `cilcpu_tt_board` (Tiny Tapeout tt_um ekvivalens)
#     MicroPhase A7-Lite XC7A200T build-jéhez. A QSPI a mole99/qspi-pmod-ra megy
#     a JP1 PMOD-headeren át (sima IOBUF I/O) — NEM az onboard config-flash-re,
#     ezért NINCS STARTUPE2. Top module: cilcpu_tt_board.
# en: CLI-CPU F2.8.6 — XDC for the `cilcpu_tt_board` (Tiny Tapeout tt_um
#     equivalent) MicroPhase A7-Lite XC7A200T build. The QSPI goes to the
#     mole99/qspi-pmod via the JP1 PMOD header (plain IOBUF I/O) — NOT the
#     onboard config flash, so there is NO STARTUPE2. Top module: cilcpu_tt_board.
#
# Pin mapping forrás / Pin mapping source:
#   - A7-Lite hivatalos referencia-manual (clk/KEY/LED/UART):
#     https://fpga-docs.microphase.cn/en/latest/DEV_BOARD/A7-LITE/A7-Lite_Reference_Manual.html
#   - JP1 GPIO1_x → FPGA pin: A7-Lite weboldali JP1 pinout-tábla
#   - QSPI uio → JP1 leképezés: a felhasználó adapter-mappingje + mole99/qspi-pmod
#     (https://github.com/mole99/qspi-pmod) FIX pinout

# =============================================================
# hu: 50 MHz órajel — J19
# en: 50 MHz clock — J19
# =============================================================
set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports i_clk_50m]
create_clock -period 20.000 -name sys_clk -waveform {0 10} -add [get_ports i_clk_50m]

# =============================================================
# hu: Reset — KEY1 (AA1), aszinkron a CDC-sync-hez
# en: Reset — KEY1 (AA1), asynchronous for the CDC sync
# =============================================================
set_property -dict { PACKAGE_PIN AA1  IOSTANDARD LVCMOS33  PULLUP true } [get_ports i_rst_btn_n]
set_input_delay -clock sys_clk 0 [get_ports i_rst_btn_n]
set_false_path -from [get_ports i_rst_btn_n]

# =============================================================
# hu: UART — CH340 USB-UART bridge. RX = U2 (host → loader), TX = V2 (eredmény).
# en: UART — CH340 USB-UART bridge. RX = U2 (host → loader), TX = V2 (result).
# =============================================================
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports i_uart_rx]
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_uart_tx]
set_input_delay  -clock sys_clk 0 [get_ports i_uart_rx]
set_false_path   -from [get_ports i_uart_rx]
set_output_delay -clock sys_clk 0 [get_ports o_uart_tx]

# =============================================================
# hu: User LED-ek (active low) — halt = M18, trap = N18
# en: User LEDs (active low) — halt = M18, trap = N18
# =============================================================
set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_led1_n]
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33  DRIVE 8 } [get_ports o_led2_n]
set_output_delay -clock sys_clk 0 [get_ports {o_led1_n o_led2_n}]

# =============================================================
# hu: QSPI uio busz → JP1 GPIO1_0..3 P/N (a mole99/qspi-pmod 8 jel-pinje).
#     A qspi-pmod a JP1 PMOD-headerbe dugva (adapteren át: 3.3V a JP1 pin 29-ről,
#     GND a pin 12/30-ról; az adatvonalak módosítás nélkül).
#       io_qspi[0] uio0 CS0 cs_flash  = GPIO1_0P F13
#       io_qspi[1] uio1 SD0 DQ0       = GPIO1_1P E13
#       io_qspi[2] uio2 SD1 DQ1       = GPIO1_2P D14
#       io_qspi[3] uio3 SCK clk       = GPIO1_3P E16
#       io_qspi[4] uio4 SD2 DQ2       = GPIO1_0N F14
#       io_qspi[5] uio5 SD3 DQ3       = GPIO1_1N E14
#       io_qspi[6] uio6 CS1 cs_psram  = GPIO1_2N D15
#       io_qspi[7] uio7 CS2 RAM B     = GPIO1_3N D16
# en: QSPI uio bus → JP1 GPIO1_0..3 P/N (the mole99/qspi-pmod's 8 signal pins).
#     The qspi-pmod plugs into the JP1 PMOD header (via the adapter: 3.3V from
#     JP1 pin 29, GND from pin 12/30; data lines unmodified). Mapping as above.
# =============================================================
set_property -dict { PACKAGE_PIN F13  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[0]}]
set_property -dict { PACKAGE_PIN E13  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[1]}]
set_property -dict { PACKAGE_PIN D14  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[2]}]
set_property -dict { PACKAGE_PIN E16  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[3]}]
set_property -dict { PACKAGE_PIN F14  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[4]}]
set_property -dict { PACKAGE_PIN E14  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[5]}]
set_property -dict { PACKAGE_PIN D15  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[6]}]
set_property -dict { PACKAGE_PIN D16  IOSTANDARD LVCMOS33  DRIVE 8 SLEW FAST } [get_ports {io_qspi[7]}]

# =============================================================
# hu: QSPI generált órajel — a SCK (io_qspi[3], a controller /2 gated clkja).
#     A `cilcpu_qspi_controller` 50 MHz / 2 = 25 MHz-et hajt a SCK-ra; a STA-hoz
#     deklaráljuk. Az IS25/W25Q max 80 MHz @ 0x6B, az APS6404L max ~84 MHz @ QSPI
#     — 25 MHz bőven belefér. A pontos input/output delay-finomítás (a Pmod-trace
#     + chip datasheet alapján) a tényleges Vivado/OpenXC7 build timing-zárásakor
#     történik (mint az F2.7 Sub5-nél a config-flash-nél).
# en: QSPI generated clock — the SCK (io_qspi[3], the controller's /2 gated clk).
#     The `cilcpu_qspi_controller` drives 25 MHz on SCK; declared for STA.
#     IS25/W25Q max 80 MHz @ 0x6B, APS6404L max ~84 MHz @ QSPI — 25 MHz fits.
#     The exact input/output delay tuning (from the Pmod trace + chip datasheet)
#     is done during the actual Vivado/OpenXC7 build timing closure (as in F2.7
#     Sub5 for the config flash).
# =============================================================
create_generated_clock -name qspi_sck \
    -source [get_ports i_clk_50m] \
    -divide_by 2 \
    [get_ports {io_qspi[3]}]

# hu: DQ (io_qspi[1,2,4,5]) bemenetként a memória hajtja; kimenetként mi.
#     Konzervatív 25 MHz-es ablak; a build-kor finomítandó.
# en: DQ (io_qspi[1,2,4,5]) as inputs driven by the memory; as outputs by us.
#     Conservative 25 MHz window; to be refined at build time.
set_input_delay  -clock qspi_sck -min 1.0 [get_ports {io_qspi[1] io_qspi[2] io_qspi[4] io_qspi[5]}]
set_input_delay  -clock qspi_sck -max 7.5 [get_ports {io_qspi[1] io_qspi[2] io_qspi[4] io_qspi[5]}]
set_output_delay -clock qspi_sck -min -2.5 [get_ports {io_qspi[0] io_qspi[1] io_qspi[2] io_qspi[4] io_qspi[5] io_qspi[6] io_qspi[7]}]
set_output_delay -clock qspi_sck -max  2.5 [get_ports {io_qspi[0] io_qspi[1] io_qspi[2] io_qspi[4] io_qspi[5] io_qspi[6] io_qspi[7]}]

# =============================================================
# hu: Bitstream konfiguráció — a bitstream az onboard config-flash-en marad
#     (a CIL-T0 program a qspi-pmod-on van, NEM a config-flash-en → nincs
#     CODE_BASE_OFFSET ütközés, a default 0 használható).
# en: Bitstream configuration — the bitstream stays on the onboard config flash
#     (the CIL-T0 program is on the qspi-pmod, NOT the config flash → no
#     CODE_BASE_OFFSET collision, the default 0 can be used).
# =============================================================
set_property CONFIG_VOLTAGE 3.3                     [current_design]
set_property CFGBVS VCCO                            [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE        [current_design]
