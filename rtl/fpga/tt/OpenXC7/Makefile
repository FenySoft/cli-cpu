# hu: CLI-CPU F2.8.6 — OpenXC7 (Yosys + nextpnr-xilinx + fasm) Makefile a
#     `cilcpu_tt_board` (Tiny Tapeout tt_um ekvivalens) A7-Lite top-ra.
#     A `rtl/fpga/OpenXC7/Makefile` (a7lite_board) mintáját követi.
#
#  >>> ELŐNY az a7lite_board-hoz képest: a tt_board NEM példányosít STARTUPE2-t
#      (a QSPI a qspi-pmod-ra megy a JP1-en, sima IOBUF I/O — nem az onboard
#      config-flash-re). Az OpenXC7 STARTUPE2-korlátja (lásd a7lite README Sub5)
#      ITT NEM érvényes → az OpenXC7 flow VÁRHATÓAN TELJESEN MŰKÖDIK (csak IOBUF).
#  >>> ADVANTAGE over a7lite_board: tt_board has NO STARTUPE2 (QSPI goes to the
#      qspi-pmod via JP1, plain IOBUF I/O). The OpenXC7 STARTUPE2 limitation
#      does NOT apply here → the OpenXC7 flow is EXPECTED TO FULLY WORK.
#
# Használat / Usage:
#   make all       # .v -> .json -> .fasm -> .frames -> .bit
#   make chipdb    # csak a chipdb.bin (~5-10 perc, egyszeri)
#   make check-env # toolchain elérhetőség
#   make clean
#
# Követelmények: Ubuntu 22.04 WSL2 + OpenXC7 snap (/snap/bin/), Python 3.
# A bitstream az onboard config-flash-re kerül (openFPGALoader); a CIL-T0
# programot a host UART-on tölti a qspi-pmod-ra (boot-over-UART) — NINCS
# write_cfgmem app-beágyazás (eltérés az a7lite-tól).

# =============================================================
PROJECT := cilcpu_tt
TOP     := cilcpu_tt_board
FAMILY  := artix7
PART    := xc7a200tfbg484-2

# hu: rtl/fpga/tt/OpenXC7/ → rtl/src = ../../../src ; rtl/fpga = ../../..
# en: rtl/fpga/tt/OpenXC7/ → rtl/src = ../../../src ; rtl/fpga = ../../..
SRC_DIR  := ../../../src
FPGA_DIR := ../..

# hu: Teljes RTL forrásfa — a rtl/tb/Makefile `test_tt_board` VERILOG_SOURCES
#     listájával AZONOS, sim_stubs NÉLKÜL (FPGA-n a Xilinx unisims adja az
#     IOBUF-ot). Dependency-sorrend: a részegységek a példányosítók ELŐTT.
# en: Full RTL source tree — IDENTICAL to rtl/tb/Makefile `test_tt_board`
#     VERILOG_SOURCES, WITHOUT sim_stubs (Xilinx unisims provide IOBUF on FPGA).
RTL_SRCS := \
	$(SRC_DIR)/cilcpu_alu.v \
	$(SRC_DIR)/cilcpu_decoder.v \
	$(SRC_DIR)/cilcpu_microcode.v \
	$(SRC_DIR)/cilcpu_stack_cache.v \
	$(SRC_DIR)/cilcpu_qspi_controller.v \
	$(SRC_DIR)/cilcpu_divider.v \
	$(SRC_DIR)/cilcpu_multiplier.v \
	$(SRC_DIR)/cilcpu_core.v \
	$(SRC_DIR)/cilcpu_fifo.v \
	$(SRC_DIR)/cilcpu_mailbox.v \
	$(SRC_DIR)/cilcpu_gpio.v \
	$(SRC_DIR)/cilcpu_trace.v \
	$(SRC_DIR)/cilcpu_uart_loader.v \
	$(SRC_DIR)/cilcpu_boot_ctrl.v \
	$(FPGA_DIR)/uart_rx.v \
	$(FPGA_DIR)/uart_tx.v \
	$(FPGA_DIR)/decimal_printer.v \
	$(SRC_DIR)/cilcpu_soc.v \
	$(FPGA_DIR)/cilcpu_tt_top.v \
	$(FPGA_DIR)/cilcpu_tt_board.v

INC_DIR := $(SRC_DIR)
XDC     := $(FPGA_DIR)/cilcpu_tt_a7lite.xdc

# hu: FPGA generic-ek. CODE_BASE_OFFSET=0 — a program a qspi-pmod-on van (NEM a
#     config-flash-en), nincs bitstream-ütközés. QE_INIT_ENABLE=1 — a W25Q128
#     Quad-read (0x6B) QE-bitjének RTL-init-je. CLOCKS_PER_BAUD=434 (115200 baud).
#     BOOT_AUTODETECT=0 — boot-over-UART (a host tölt); 1 → autonóm flash-boot a
#     Pmod-flash-ből (ha érvényes header). A Yosys chparam-mal állítjuk.
# en: FPGA generics. CODE_BASE_OFFSET=0 — the program is on the qspi-pmod (NOT
#     the config flash), no bitstream collision. QE_INIT_ENABLE=1 — RTL init of
#     the W25Q128 Quad-read (0x6B) QE bit. CLOCKS_PER_BAUD=434. BOOT_AUTODETECT=0
#     — boot-over-UART; 1 → autonomous flash-boot from the Pmod flash.
CODE_BASE_OFFSET := 0
QE_INIT_ENABLE   := 1
CLOCKS_PER_BAUD  := 434
BOOT_AUTODETECT  := 0

NEXTPNR_XILINX_DIR        := /snap/openxc7/current/opt/nextpnr-xilinx
NEXTPNR_XILINX_PYTHON_DIR := $(NEXTPNR_XILINX_DIR)/python
PRJXRAY_DB_DIR            := $(NEXTPNR_XILINX_DIR)/external/prjxray-db
PYTHON   := python3
CHIPDB   := ./chipdb
DBPART   := $(shell echo $(PART) | sed -e 's/-[0-9a-zA-Z]*$$//')
CHIPBIN  := $(CHIPDB)/$(DBPART).bin

.PHONY: all clean pnrclean chipdb check-env
all: $(PROJECT).bit

# --- Yosys szintézis: .v -> .json ---
$(PROJECT).json: $(RTL_SRCS)
	yosys -p "read_verilog -I$(INC_DIR) $(RTL_SRCS); \
		chparam -set CODE_BASE_OFFSET $(CODE_BASE_OFFSET) -set QE_INIT_ENABLE $(QE_INIT_ENABLE) -set CLOCKS_PER_BAUD $(CLOCKS_PER_BAUD) -set BOOT_AUTODETECT $(BOOT_AUTODETECT) $(TOP); \
		synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $@"

$(CHIPBIN):
	@mkdir -p $(CHIPDB)
	@echo "INFO: Chipdb generalas $(DBPART)-ra (~5-10 perc, egyszeri)..."
	$(PYTHON) $(NEXTPNR_XILINX_PYTHON_DIR)/bbaexport.py --device $(PART) --bba $(DBPART).bba
	bbasm -l $(DBPART).bba $(CHIPBIN)
	rm -f $(DBPART).bba
chipdb: $(CHIPBIN)

$(PROJECT).fasm: $(PROJECT).json $(CHIPBIN) $(XDC)
	nextpnr-xilinx --chipdb $(CHIPBIN) --xdc $(XDC) --json $(PROJECT).json --fasm $@

$(PROJECT).frames: $(PROJECT).fasm
	fasm2frames --part $(PART) --db-root $(PRJXRAY_DB_DIR)/$(FAMILY) $< > $@

$(PROJECT).bit: $(PROJECT).frames
	xc7frames2bit --part_file $(PRJXRAY_DB_DIR)/$(FAMILY)/$(PART)/part.yaml \
		--part_name $(PART) --frm_file $< --output_file $@
	@echo "INFO: OpenXC7 build KESZ — $(PROJECT).bit (`stat -c %s $@` byte)"
	@echo "INFO: openFPGALoader -b a7-lite $(PROJECT).bit  (vagy a megfelelo board target)"

clean:
	rm -f *.bit *.frames *.fasm *.json
pnrclean:
	rm -f *.bit *.frames *.fasm
check-env:
	@echo "yosys:          `which yosys`"
	@echo "nextpnr-xilinx: `which nextpnr-xilinx`"
	@echo "fasm2frames:    `which fasm2frames`"
	@echo "xc7frames2bit:  `which xc7frames2bit`"
	@echo "openFPGALoader: `which openFPGALoader`"
	@echo "part:           $(PART) (db: $(DBPART))"
	@echo "STARTUPE2:       NINCS (tt_board) -> OpenXC7 teljes tamogatas"
