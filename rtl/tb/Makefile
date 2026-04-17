# hu: CLI-CPU cocotb tesztek Makefile — Verilator backend.
# en: CLI-CPU cocotb tests Makefile — Verilator backend.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES = $(PWD)/../src/cilcpu_alu.v

# hu: Az aktuális teszt modul — `make MODULE=test_alu` vagy `make test_alu`
# en: Current test module — `make MODULE=test_alu` or `make test_alu`
MODULE ?= test_alu
TOPLEVEL ?= cilcpu_alu

# hu: Verilator extra flagek — a `include path az src/ könyvtárra
# en: Verilator extra flags — include path for src/ directory
EXTRA_ARGS += --trace -I$(PWD)/../src

COCOTB_CONFIG ?= $(shell python3 -c "import os,cocotb;print(os.path.join(os.path.dirname(os.path.dirname(cocotb.__file__)),'..','..','..','bin','cocotb-config'))" 2>/dev/null || echo cocotb-config)
include $(shell $(COCOTB_CONFIG) --makefiles)/Makefile.sim

# hu: Kényelmi targetok — `make test_alu` közvetlenül futtatható
# en: Convenience targets — `make test_alu` runs directly
test_alu:
	$(MAKE) MODULE=test_alu TOPLEVEL=cilcpu_alu VERILOG_SOURCES="$(PWD)/../src/cilcpu_alu.v"

test_sram:
	$(MAKE) MODULE=test_sram TOPLEVEL=cilcpu_sram VERILOG_SOURCES="$(PWD)/../src/cilcpu_sram.v"

test_decoder:
	$(MAKE) MODULE=test_decoder TOPLEVEL=cilcpu_decoder VERILOG_SOURCES="$(PWD)/../src/cilcpu_decoder.v"

test_microcode:
	$(MAKE) MODULE=test_microcode TOPLEVEL=cilcpu_microcode VERILOG_SOURCES="$(PWD)/../src/cilcpu_microcode.v"

.PHONY: test_alu test_sram test_decoder test_microcode
