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

# hu: Venv Python és cocotb makefiles elérési útvonal.
#     A .venv shebang törött (régi repo útvonal), ezért közvetlenül a
#     python3.13 + PYTHONPATH kombináción keresztül futtatjuk.
# en: Venv Python and cocotb makefiles path.
#     The .venv shebang is broken (old repo path), so we use
#     python3.13 + PYTHONPATH directly.
VENV_PY     ?= /usr/local/bin/python3.13
VENV_SITE   ?= $(PWD)/../../rtl/.venv/lib/python3.13/site-packages
COCOTB_MAKEFILES ?= $(shell PYTHONPATH="$(VENV_SITE)" $(VENV_PY) -c \
	"from cocotb_tools.config import main; import sys; sys.argv=['c','--makefiles']; main()" 2>/dev/null \
	|| echo "$(VENV_SITE)/cocotb_tools/makefiles")

export PYTHONPATH := $(VENV_SITE)

include $(COCOTB_MAKEFILES)/Makefile.sim

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

test_stack_cache:
	$(MAKE) MODULE=test_stack_cache TOPLEVEL=cilcpu_stack_cache VERILOG_SOURCES="$(PWD)/../src/cilcpu_stack_cache.v"

test_qspi_controller:
	$(MAKE) MODULE=test_qspi_controller TOPLEVEL=cilcpu_qspi_controller VERILOG_SOURCES="$(PWD)/../src/cilcpu_qspi_controller.v"

.PHONY: test_alu test_sram test_decoder test_microcode test_stack_cache test_qspi_controller
