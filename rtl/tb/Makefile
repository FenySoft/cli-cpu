# hu: CLI-CPU cocotb tesztek Makefile — Verilator backend.
# en: CLI-CPU cocotb tests Makefile — Verilator backend.
#
# hu: A target-ek a `Makefile.sim.local`-t hívják sub-make-en át,
#     a venv bin-jét a PATH elejére helyezve. A parent Makefile NEM
#     include-olja a Makefile.sim-et — különben a `cocotb-config` shell
#     parancs a parent shell PATH-án (system) keresődik és hibázik
#     (system python3 a 3.14-re mutat, cocotb csak a 3.13 venv-en van).
# en: The targets call `Makefile.sim.local` via sub-make, prepending the
#     venv bin to PATH. The parent Makefile does NOT include Makefile.sim
#     directly, otherwise the `cocotb-config` shell command would be looked
#     up on the parent shell PATH (system) and fail (system python3 points
#     to 3.14, cocotb only lives in the 3.13 venv).

VENV_PY ?= /usr/local/bin/python3.13

# hu: Közös sub-make hívás template
# en: Common sub-make invocation template
SUBMAKE = PATH="$(PWD)/../.venv/bin:$$PATH" $(MAKE) -f Makefile.sim.local

test_alu:
	$(SUBMAKE) MODULE=test_alu TOPLEVEL=cilcpu_alu VERILOG_SOURCES="$(PWD)/../src/cilcpu_alu.v"

test_decoder:
	$(SUBMAKE) MODULE=test_decoder TOPLEVEL=cilcpu_decoder VERILOG_SOURCES="$(PWD)/../src/cilcpu_decoder.v"

test_microcode:
	$(SUBMAKE) MODULE=test_microcode TOPLEVEL=cilcpu_microcode VERILOG_SOURCES="$(PWD)/../src/cilcpu_microcode.v"

test_stack_cache:
	$(SUBMAKE) MODULE=test_stack_cache TOPLEVEL=cilcpu_stack_cache VERILOG_SOURCES="$(PWD)/../src/cilcpu_stack_cache.v"

test_qspi_controller:
	$(SUBMAKE) MODULE=test_qspi_controller TOPLEVEL=cilcpu_qspi_controller VERILOG_SOURCES="$(PWD)/../src/cilcpu_qspi_controller.v"

# hu: F2.5a top-level core — 5 részegység + cilcpu_core
# en: F2.5a top-level core — 5 submodules + cilcpu_core
test_core:
	$(SUBMAKE) MODULE=test_core TOPLEVEL=cilcpu_core VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_core.v"

# hu: F2.5b golden vector harness — cocotb vs C# szim trace JSONL.
#     A C# Runner DLL-nek le kell fordulva lennie:
#     `dotnet build src/CilCpu.Sim.Runner/CilCpu.Sim.Runner.csproj`
# en: F2.5b golden vector harness — cocotb vs C# tracer JSONL.
#     The C# Runner DLL must be built first.
test_core_golden:
	$(SUBMAKE) MODULE=test_core_golden TOPLEVEL=cilcpu_core VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_core.v"

# hu: F2.7 Sub1 — A7-Lite top-level wrapper cocotb tesztek.
#     A wrapper a `cilcpu_core`-t veszi körül clock/reset szinkronizerrel,
#     KEY2 start gombbal (debouncer-rel), boot szekvenszer FSM-mel és
#     halt/trap LED kimenettel. Sim-ben DEBOUNCE_BITS=4-re csökkentve
#     (FPGA default: 22 = ~84 ms).
# en: F2.7 Sub1 — A7-Lite top-level wrapper cocotb tests.
#     The wrapper wraps `cilcpu_core` with a clock/reset synchronizer, a
#     KEY2 start button (with debouncer), a boot sequencer FSM, and
#     halt/trap LED outputs. In sim DEBOUNCE_BITS=4 (FPGA default: 22 = ~84 ms).
test_a7lite_top:
	$(SUBMAKE) MODULE=test_a7lite_top TOPLEVEL=cilcpu_a7lite_top \
		LOCAL_COMPILE_ARGS="-GDEBOUNCE_BITS=4" \
		VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../fpga/cilcpu_a7lite_top.v"

.PHONY: test_alu test_decoder test_microcode test_stack_cache test_qspi_controller test_core test_core_golden test_a7lite_top
