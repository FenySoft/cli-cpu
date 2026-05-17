# hu: CLI-CPU F2.7 Sub5 — OpenXC7 (Yosys + nextpnr-xilinx + fasm) Makefile
#     a teljes `cilcpu_a7lite_board` top-ra. A smoke_test/OpenXC7/Makefile
#     mintáját követi, kibővítve a board.v teljes RTL forrásfa-listájával
#     és a `cilcpu_defines.vh` include path-szal.
# en: CLI-CPU F2.7 Sub5 — OpenXC7 (Yosys + nextpnr-xilinx + fasm) Makefile
#     for the full `cilcpu_a7lite_board` top. Mirrors
#     smoke_test/OpenXC7/Makefile, extended with the board.v full RTL
#     source tree and the `cilcpu_defines.vh` include path.
#
#  >>> OpenXC7 STARTUPE2 KORLÁT — OLVASD EL a README-hu.md Sub5 szakaszt.
#      A `cilcpu_a7lite_board` STARTUPE2 + 4x IOBUF primitivet peldanyosit.
#      Az IOBUF az nextpnr-xilinx/prjxray flow-ban tamogatott. A STARTUPE2
#      (config-bank startup blokk, user CCLK a USRCCLKO-n) az nextpnr-xilinx
#      + prjxray-db flow-ban NEM megbizhatoan tamogatott (a STARTUP site
#      fuzzing hianyos a prjxray-db artix7-ben). EZERT az OpenXC7 path
#      Sub5-ben BEST-EFFORT; az ELSODLEGES Sub5 path a Vivado. Ezt a
#      korlatot nyiltan kimondjuk a README-ben (single-layer-trust elv:
#      a korlatot kimondani kell, nem elkenni).
#  >>> OpenXC7 STARTUPE2 LIMITATION — see README.md Sub5 section.
#      IOBUF is supported in the nextpnr-xilinx/prjxray flow. STARTUPE2
#      (config-bank startup block, user CCLK via USRCCLKO) is NOT reliably
#      supported (incomplete STARTUP site fuzzing in prjxray-db artix7).
#      OpenXC7 is therefore BEST-EFFORT in Sub5; the PRIMARY Sub5 path is
#      Vivado. The limitation is stated openly in the README.
#
# Hasznalat / Usage:
#   make all       # teljes build: .v -> .json -> .fasm -> .frames -> .bit
#   make clean     # generalt fajlok torlese
#   make chipdb    # csak a chipdb.bin generalasa (~5-10 perc xc7a200t-re)
#   make check-env # toolchain elerhetoseg
#
# Kovetelmenyek / Requirements:
#   - Ubuntu 22.04 (vagy kompatibilis) WSL2-ben
#   - OpenXC7 snap package telepitve (/snap/bin/ elerheto)
#   - Python 3 (pypy3 gyorsabb, de opcionalis)

# =============================================================
# Projekt konfiguracio / Project configuration
# =============================================================

PROJECT := cilcpu_a7lite
TOP     := cilcpu_a7lite_board
FAMILY  := artix7
PART    := xc7a200tfbg484-2

# hu: Teljes RTL forrasfa — a rtl/tb/Makefile `test_a7lite_board_fib`
#     VERILOG_SOURCES listajaval AZONOS, a `sim_stubs/` NELKUL
#     (a `synth_xilinx` a beepitett Xilinx cell modelljeit hasznalja).
#     A `cilcpu_core.v` a reszegysegei UTAN sorrendben.
# en: Full RTL source tree — IDENTICAL to the rtl/tb/Makefile
#     `test_a7lite_board_fib` VERILOG_SOURCES list, WITHOUT `sim_stubs/`.
SRC_DIR  := ../../src
FPGA_DIR := ..
RTL_SRCS := \
	$(SRC_DIR)/cilcpu_alu.v \
	$(SRC_DIR)/cilcpu_decoder.v \
	$(SRC_DIR)/cilcpu_microcode.v \
	$(SRC_DIR)/cilcpu_stack_cache.v \
	$(SRC_DIR)/cilcpu_qspi_controller.v \
	$(SRC_DIR)/cilcpu_core.v \
	$(FPGA_DIR)/uart_tx.v \
	$(FPGA_DIR)/decimal_printer.v \
	$(FPGA_DIR)/cilcpu_a7lite_top.v \
	$(FPGA_DIR)/cilcpu_a7lite_board.v

# hu: `cilcpu_defines.vh` include path a Yosys read_verilog-hoz.
# en: `cilcpu_defines.vh` include path for the Yosys read_verilog.
INC_DIR := $(SRC_DIR)
XDC     := $(PROJECT).xdc

# hu: Sub5.A — CODE_BASE_OFFSET az FPGA-build app-bázisa. EGYETLEN
#     FORRÁS-elv: ennek egyeznie kell a Vivado create_project.tcl
#     CODE_BASE_OFFSET=32'hC00000 generic-jével ÉS a write_cfgmem.tcl
#     CODE_BASE_OFFSET_HEX=0x00C00000 konstansával. 0xC00000 = 12 MB,
#     a ~9,9 MB XC7A200T bitstream FÖLÉ (config-flash 0x0-tól tölti).
#     Yosys-ban `chparam -set` a top-modulra a synth ELŐTT.
# en: Sub5.A — CODE_BASE_OFFSET, the FPGA-build app base. SINGLE-SOURCE
#     principle: must match the Vivado create_project.tcl
#     CODE_BASE_OFFSET=32'hC00000 generic AND the write_cfgmem.tcl
#     CODE_BASE_OFFSET_HEX=0x00C00000 constant. 0xC00000 = 12 MB, ABOVE
#     the ~9.9 MB XC7A200T bitstream (config-flash loads from 0x0).
#     Yosys `chparam -set` on the top module BEFORE synth.
CODE_BASE_OFFSET := 12582912

# =============================================================
# OpenXC7 toolchain eleresi utak / tool paths
# =============================================================

NEXTPNR_XILINX_DIR        := /snap/openxc7/current/opt/nextpnr-xilinx
NEXTPNR_XILINX_PYTHON_DIR := $(NEXTPNR_XILINX_DIR)/python
PRJXRAY_DB_DIR            := $(NEXTPNR_XILINX_DIR)/external/prjxray-db

PYTHON := python3

CHIPDB   := ./chipdb
DBPART   := $(shell echo $(PART) | sed -e 's/-[0-9a-zA-Z]*$$//')
CHIPBIN  := $(CHIPDB)/$(DBPART).bin

# =============================================================
# Szabalyok / Rules
# =============================================================

.PHONY: all clean pnrclean chipdb check-env

all: $(PROJECT).bit

# --- Yosys szintezis: .v -> .json ---
# hu: -I$(INC_DIR) a `cilcpu_defines.vh`-hoz; synth_xilinx a board.v
#     STARTUPE2/IOBUF-jat a beepitett Xilinx cell-ekre mappeli.
# en: -I$(INC_DIR) for `cilcpu_defines.vh`; synth_xilinx maps board.v
#     STARTUPE2/IOBUF to the built-in Xilinx cells.
# hu: `chparam -set CODE_BASE_OFFSET` a `synth_xilinx` ELŐTT, hogy az
#     app-bázis a bitstream fölé kerüljön (Sub5.A, lásd fent).
# en: `chparam -set CODE_BASE_OFFSET` BEFORE `synth_xilinx` so the app
#     base lands above the bitstream (Sub5.A, see above).
$(PROJECT).json: $(RTL_SRCS)
	yosys -p "read_verilog -I$(INC_DIR) $(RTL_SRCS); chparam -set CODE_BASE_OFFSET $(CODE_BASE_OFFSET) $(TOP); synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $@"

# --- Chipdb generalas (egyszer futtatodik) ---
$(CHIPBIN):
	@mkdir -p $(CHIPDB)
	@echo "INFO: Chipdb generalasa $(DBPART)-ra, ez ~5-10 percig tart (egyszeri muvelet)..."
	$(PYTHON) $(NEXTPNR_XILINX_PYTHON_DIR)/bbaexport.py --device $(PART) --bba $(DBPART).bba
	bbasm -l $(DBPART).bba $(CHIPBIN)
	rm -f $(DBPART).bba

chipdb: $(CHIPBIN)

# --- nextpnr-xilinx P&R: .json -> .fasm ---
# hu: Itt bukhat el a STARTUPE2 binding (lasd README-hu.md Sub5 korlat).
# en: STARTUPE2 binding may fail here (see README.md Sub5 limitation).
$(PROJECT).fasm: $(PROJECT).json $(CHIPBIN) $(XDC)
	nextpnr-xilinx --chipdb $(CHIPBIN) --xdc $(XDC) --json $(PROJECT).json --fasm $@

# --- fasm2frames: .fasm -> .frames ---
$(PROJECT).frames: $(PROJECT).fasm
	fasm2frames --part $(PART) --db-root $(PRJXRAY_DB_DIR)/$(FAMILY) $< > $@

# --- xc7frames2bit: .frames -> .bit ---
$(PROJECT).bit: $(PROJECT).frames
	xc7frames2bit \
		--part_file $(PRJXRAY_DB_DIR)/$(FAMILY)/$(PART)/part.yaml \
		--part_name $(PART) \
		--frm_file $< \
		--output_file $@
	@echo ""
	@echo "========================================================"
	@echo "INFO: OpenXC7 build KESZ — $(PROJECT).bit"
	@echo "INFO: Meret: `stat -c %s $@` byte"
	@echo "INFO: App-binaris flash-be agyazas: lasd README-hu.md Sub5"
	@echo "      (xc7frames2bit utan kulon flash-image, openFPGALoader)"
	@echo "========================================================"

# --- Takaritas ---
clean:
	rm -f *.bit *.frames *.fasm *.json

pnrclean:
	rm -f *.bit *.frames *.fasm

check-env:
	@echo "yosys:          `which yosys`"
	@echo "nextpnr-xilinx: `which nextpnr-xilinx`"
	@echo "bbasm:          `which bbasm`"
	@echo "fasm2frames:    `which fasm2frames`"
	@echo "xc7frames2bit:  `which xc7frames2bit`"
	@echo "openFPGALoader: `which openFPGALoader`"
	@echo "prjxray-db:     $(PRJXRAY_DB_DIR)"
	@echo "part:           $(PART) (db: $(DBPART))"
