# hu: CLI-CPU smoke-teszt — OpenXC7 (Yosys + nextpnr-xilinx + fasm) Makefile.
#     MicroPhase A7-Lite XC7A200T board-ra. Párhuzamos build a Vivado
#     verzióval — ugyanazt a led_blink.v-t szintetizálja, de zárt AMD
#     toolchain helyett open source pipeline-nal.
# en: CLI-CPU smoke test — OpenXC7 (Yosys + nextpnr-xilinx + fasm) Makefile.
#     MicroPhase A7-Lite XC7A200T. Parallel build to the Vivado version —
#     synthesizes the same led_blink.v, but through the open source
#     pipeline instead of the closed AMD toolchain.
#
# Használat / Usage:
#   make all       # teljes build: .v → .json → .fasm → .frames → .bit
#   make clean     # generált fájlok törlése
#   make chipdb    # csak a chipdb.bin generálása (~5-10 perc xc7a200t-re)
#
# Követelmények / Requirements:
#   - Ubuntu 22.04 (vagy kompatibilis) WSL2-ben
#   - OpenXC7 snap package telepítve (/snap/bin/ elérhető)
#   - Python 3 (pypy3 gyorsabb, de opcionális)

# =============================================================
# Projekt konfiguráció / Project configuration
# =============================================================

PROJECT := led_blink
TOP     := led_blink
FAMILY  := artix7
PART    := xc7a200tfbg484-2

# Top Verilog: egy szinttel feljebb (shared a Vivado build-del)
TOP_VERILOG := ../$(TOP).v
XDC         := $(PROJECT).xdc

# =============================================================
# OpenXC7 toolchain elérési utak / tool paths
# =============================================================

NEXTPNR_XILINX_DIR        := /snap/openxc7/current/opt/nextpnr-xilinx
NEXTPNR_XILINX_PYTHON_DIR := $(NEXTPNR_XILINX_DIR)/python
PRJXRAY_DB_DIR            := $(NEXTPNR_XILINX_DIR)/external/prjxray-db

# pypy3 gyorsabb a chipdb generáláshoz, de python3 is működik
PYTHON := python3

# Chipdb a lokális alkönyvtárban (egyszer generálódik, ~5-10 perc)
CHIPDB   := ./chipdb
DBPART   := $(shell echo $(PART) | sed -e 's/-[0-9a-zA-Z]*$$//')
CHIPBIN  := $(CHIPDB)/$(DBPART).bin

# =============================================================
# Szabályok / Rules
# =============================================================

.PHONY: all clean pnrclean chipdb

all: $(PROJECT).bit

# --- Yosys szintézis: .v → .json ---
$(PROJECT).json: $(TOP_VERILOG)
	yosys -p "synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $@" $<

# --- Chipdb generálás (egyszer futtatódik) ---
$(CHIPBIN):
	@mkdir -p $(CHIPDB)
	@echo "INFO: Chipdb generálása $(DBPART)-ra, ez ~5-10 percig tart (egyszeri művelet)..."
	$(PYTHON) $(NEXTPNR_XILINX_PYTHON_DIR)/bbaexport.py --device $(PART) --bba $(DBPART).bba
	bbasm -l $(DBPART).bba $(CHIPBIN)
	rm -f $(DBPART).bba

chipdb: $(CHIPBIN)

# --- nextpnr-xilinx P&R: .json → .fasm ---
$(PROJECT).fasm: $(PROJECT).json $(CHIPBIN) $(XDC)
	nextpnr-xilinx --chipdb $(CHIPBIN) --xdc $(XDC) --json $(PROJECT).json --fasm $@

# --- fasm2frames: .fasm → .frames ---
$(PROJECT).frames: $(PROJECT).fasm
	fasm2frames --part $(PART) --db-root $(PRJXRAY_DB_DIR)/$(FAMILY) $< > $@

# --- xc7frames2bit: .frames → .bit ---
$(PROJECT).bit: $(PROJECT).frames
	xc7frames2bit \
		--part_file $(PRJXRAY_DB_DIR)/$(FAMILY)/$(PART)/part.yaml \
		--part_name $(PART) \
		--frm_file $< \
		--output_file $@
	@echo ""
	@echo "========================================================"
	@echo "INFO: OpenXC7 build KÉSZ — $(PROJECT).bit"
	@echo "INFO: Méret: `stat -c %s $@` byte"
	@echo "========================================================"

# --- Takarítás ---
clean:
	rm -f *.bit *.frames *.fasm *.json

pnrclean:
	rm -f *.bit *.frames *.fasm

# Segéd target: környezet ellenőrzés
.PHONY: check-env
check-env:
	@echo "yosys:         `which yosys`"
	@echo "nextpnr-xilinx: `which nextpnr-xilinx`"
	@echo "bbasm:         `which bbasm`"
	@echo "fasm2frames:   `which fasm2frames`"
	@echo "xc7frames2bit: `which xc7frames2bit`"
	@echo "prjxray-db:    $(PRJXRAY_DB_DIR)"
	@echo "part:          $(PART) (db: $(DBPART))"
