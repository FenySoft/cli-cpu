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

# hu: Közös sub-make hívás template. A SIM_BUILD targetenként külön
#     könyvtár (sim_build/<target>) — különben a cocotb a megosztott
#     sim_build/-ben a korábbi target lefordított binárisát húzná újra:
#     a bináris frissebb, mint a .v források, így a make target-váltáskor
#     nem fordít újra, és rossz toplevel-lel futna. A sim_build/ a
#     .gitignore-ban van, így a per-target alkönyvtárak nem szennyezik a fát.
# en: Common sub-make invocation template. SIM_BUILD is per-target
#     (sim_build/<target>) — otherwise cocotb would reuse the previous
#     target's compiled binary from the shared sim_build/: the binary is
#     newer than the .v sources, so make skips the rebuild on a target
#     switch and would run with the wrong toplevel. sim_build/ is in
#     .gitignore, so the per-target subdirs do not pollute the tree.
SUBMAKE = PATH="$(PWD)/../.venv/bin:$$PATH" $(MAKE) -f Makefile.sim.local SIM_BUILD=$(PWD)/sim_build/$@

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

# hu: F2.7 — szekvenciális előjeles osztó (cilcpu_divider) standalone teszt.
# en: F2.7 — standalone sequential signed divider (cilcpu_divider) test.
test_divider:
	$(SUBMAKE) MODULE=test_divider TOPLEVEL=cilcpu_divider VERILOG_SOURCES="$(PWD)/../src/cilcpu_divider.v"

# hu: F2.6-prep — szekvenciális szorzó (cilcpu_multiplier) standalone teszt.
#     A kombinációs ALU-szorzó (cilcpu_alu.v ALU_MUL) helyett shift-add
#     többciklusú szorzó — terület-megtakarítás + ISA-spec megfelelés.
# en: F2.6-prep — standalone sequential multiplier (cilcpu_multiplier) test.
#     Replaces the combinational ALU multiplier (cilcpu_alu.v ALU_MUL) with
#     a multi-cycle shift-add multiplier — area saving + ISA-spec alignment.
test_multiplier:
	$(SUBMAKE) MODULE=test_multiplier TOPLEVEL=cilcpu_multiplier VERILOG_SOURCES="$(PWD)/../src/cilcpu_multiplier.v"

# hu: F2.7 Sub5 — QSPI Controller QE-init sequence verifikáció.
#     QE_INIT_ENABLE=1 mellett a controller reset után WREN+WRSR-t küld.
# en: F2.7 Sub5 — QSPI Controller QE-init sequence verification.
#     With QE_INIT_ENABLE=1, the controller emits WREN+WRSR after reset.
test_qspi_qe_init:
	$(SUBMAKE) MODULE=test_qspi_qe_init TOPLEVEL=cilcpu_qspi_controller \
		LOCAL_COMPILE_ARGS="-GQE_INIT_ENABLE=1" \
		VERILOG_SOURCES="$(PWD)/../src/cilcpu_qspi_controller.v"

# hu: Sub5.A — CODE_BASE_OFFSET paraméterezett QSPI controller teszt.
#     EGYETLEN forrás: a 256 (= 0x000100) érték a Verilator generic-be
#     (-GCODE_BASE_OFFSET=) ÉS a cocotb env-be (QSPI_CODE_BASE_OFFSET)
#     egyszerre kerül — a kettő MINDIG egyezzen. (Decimális érték: a
#     Verilog `'h` literál a shellben aposztróf-hibát dob.) A default
#     `test_qspi_controller` (offszet 0) változatlanul fut, ott a
#     test_30/test_31 skip-el (sim-paritás).
# en: Sub5.A — CODE_BASE_OFFSET parameterized QSPI controller test.
#     SINGLE source: the value 256 (= 0x000100) goes to BOTH the
#     Verilator generic (-GCODE_BASE_OFFSET=) AND the cocotb env
#     (QSPI_CODE_BASE_OFFSET) — the two must ALWAYS match. (Decimal
#     value: a Verilog `'h` literal breaks the shell on the apostrophe.)
#     The default `test_qspi_controller` (offset 0) runs unchanged;
#     test_30/test_31 skip there (sim parity).
# hu: TESTCASE-szel CSAK a két offszet-tesztet futtatjuk: a többi 29
#     teszt CODE-fixture-je szándékosan offszet-0-ra van rakva (a
#     default konfig verifikációja), nem-0 offszettel értelemszerűen
#     nem stimmelne — azok a `test_qspi_controller`-ben zöldek.
# en: TESTCASE runs ONLY the two offset tests: the other 29 tests'
#     CODE fixtures are intentionally placed at offset 0 (default-config
#     verification) and would not match under a non-zero offset — they
#     stay green under `test_qspi_controller`.
test_qspi_controller_offset:
	QSPI_CODE_BASE_OFFSET=256 \
	$(SUBMAKE) MODULE=test_qspi_controller TOPLEVEL=cilcpu_qspi_controller \
		TESTCASE=test_30_code_base_offset_applied,test_31_code_base_offset_addr_zero \
		LOCAL_COMPILE_ARGS="-GCODE_BASE_OFFSET=256" \
		VERILOG_SOURCES="$(PWD)/../src/cilcpu_qspi_controller.v"

# hu: F2.5a top-level core — 5 részegység + cilcpu_core
# en: F2.5a top-level core — 5 submodules + cilcpu_core
# hu: F2.8 #6.5b-F1a — a QSPI controller a Core-ból kiemelve; a test_core a
#     tb_core fixture-t (core + qspi_controller) példányosítja, így a meglévő
#     QSPI flash harness változatlanul fut.
# en: F2.8 #6.5b-F1a — QSPI controller moved out of the Core; test_core uses the
#     tb_core fixture (core + qspi_controller) so the existing QSPI flash harness
#     runs unchanged.
test_core:
	$(SUBMAKE) MODULE=test_core TOPLEVEL=tb_core VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/tb_core.v"

# hu: F2.5b golden vector harness — cocotb vs C# szim trace JSONL.
#     A C# Runner DLL-nek le kell fordulva lennie:
#     `dotnet build src/CilCpu.Sim.Runner/CilCpu.Sim.Runner.csproj`
# en: F2.5b golden vector harness — cocotb vs C# tracer JSONL.
#     The C# Runner DLL must be built first.
test_core_golden:
	$(SUBMAKE) MODULE=test_core_golden TOPLEVEL=tb_core VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/tb_core.v"

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
		LOCAL_COMPILE_ARGS="-GDEBOUNCE_BITS=4 -GCLOCKS_PER_BAUD=8" \
		VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../fpga/cilcpu_a7lite_top.v"

# hu: F2.7 Sub3 — FibonacciIterative(20) = 6765 end-to-end demó.
#     A wrapper-be N=20 boot arg, a Math.FibonacciIterative CIL-T0 bináris a
#     flash-en, UART-on "6765\r\n". A rekurzív Math.Fibonacci ismert
#     mély-mélységi bug-ot trigger-el a Sub5 frame manager-ben — Sub3-hoz az
#     iteratív verziót használjuk, ami csak loop-ot, LDLOC/STLOC, BLT/BR-t
#     használ (a core-ban már 100% fedett opkódok).
# en: F2.7 Sub3 — FibonacciIterative(20) = 6765 end-to-end demo.
#     Wrapper booted with N=20, Math.FibonacciIterative CIL-T0 on flash,
#     UART echoes "6765\r\n". The recursive Math.Fibonacci hits a known
#     deep-recursion bug in the Sub5 frame manager — Sub3 uses the iterative
#     variant which only relies on loop, LDLOC/STLOC, BLT/BR (all 100%
#     covered in the core).
test_a7lite_fib:
	$(SUBMAKE) MODULE=test_a7lite_fib TOPLEVEL=cilcpu_a7lite_top \
		LOCAL_COMPILE_ARGS="-GDEBOUNCE_BITS=4 -GCLOCKS_PER_BAUD=8 -GBOOT_ARG_VALUE=20 -GBOOT_LOCAL_COUNT=4" \
		VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../fpga/cilcpu_a7lite_top.v"

# hu: F2.7 Sub4 — board-szintű wrapper smoke tesztek (`cilcpu_a7lite_board`).
#     A board.v a `cilcpu_a7lite_top` köré rakja a STARTUPE2-t és IOBUF-okat.
#     Verilator-hoz mellékelt sim stub fájlt is fordítjuk
#     (`fpga/sim_stubs/xilinx_primitives_sim.v`), és a `+define+CILCPU_SIM_BOARD`
#     makróval a board.v split debug portokat expose-ol az inout helyett
#     (multi-driver konfliktust elkerülve).
# en: F2.7 Sub4 — board-level wrapper smoke tests (`cilcpu_a7lite_board`).
#     board.v wraps STARTUPE2 + IOBUFs around `cilcpu_a7lite_top`. A
#     Verilator sim stub file is compiled in
#     (`fpga/sim_stubs/xilinx_primitives_sim.v`), and `+define+CILCPU_SIM_BOARD`
#     makes board.v expose split debug ports instead of an inout bus
#     (sidesteps multi-driver conflicts).
test_a7lite_board:
	$(SUBMAKE) MODULE=test_a7lite_board TOPLEVEL=cilcpu_a7lite_board \
		LOCAL_COMPILE_ARGS="-GDEBOUNCE_BITS=4 -GCLOCKS_PER_BAUD=8 -GBOOT_ARG_VALUE=5 -DCILCPU_SIM_BOARD" \
		VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../fpga/cilcpu_a7lite_top.v \
$(PWD)/../fpga/cilcpu_a7lite_board.v \
$(PWD)/../fpga/sim_stubs/xilinx_primitives_sim.v"

# hu: F2.7 Sub4 — board-szintű Fibonacci(20) end-to-end teszt. Ugyanaz a
#     toolchain mint a `test_a7lite_fib`, de a board wrapper-en át (STARTUPE2
#     CCLK + IOBUF DQ stubokkal). Bizonyítja, hogy a board.v szintű hozzáadás
#     nem regresszió.
# en: F2.7 Sub4 — board-level Fibonacci(20) end-to-end test. Same toolchain
#     as `test_a7lite_fib` but routed through the board wrapper (STARTUPE2
#     CCLK + IOBUF DQ stubs). Proves the board.v layer is not a regression.
test_a7lite_board_fib:
	$(SUBMAKE) MODULE=test_a7lite_board_fib TOPLEVEL=cilcpu_a7lite_board \
		LOCAL_COMPILE_ARGS="-GDEBOUNCE_BITS=4 -GCLOCKS_PER_BAUD=8 -GBOOT_ARG_VALUE=20 -GBOOT_LOCAL_COUNT=4 -DCILCPU_SIM_BOARD" \
		VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../fpga/cilcpu_a7lite_top.v \
$(PWD)/../fpga/cilcpu_a7lite_board.v \
$(PWD)/../fpga/sim_stubs/xilinx_primitives_sim.v"

# hu: F2.7 Sub2 — UART transmitter standalone teszt.
#     CLOCKS_PER_BAUD=8 a sim-ben (FPGA default: 434 = 50 MHz / 115200 baud).
# en: F2.7 Sub2 — standalone UART transmitter test.
#     CLOCKS_PER_BAUD=8 in sim (FPGA default: 434 = 50 MHz / 115200 baud).
test_uart_tx:
	$(SUBMAKE) MODULE=test_uart_tx TOPLEVEL=uart_tx \
		LOCAL_COMPILE_ARGS="-GCLOCKS_PER_BAUD=8" \
		VERILOG_SOURCES="$(PWD)/../fpga/uart_tx.v"

# hu: F2.8.1 — UART receiver (8N1, bit-közép mintavétel, 2-FF sync).
# en: F2.8.1 — UART receiver (8N1, bit-center sampling, 2-FF sync).
test_uart_rx:
	$(SUBMAKE) MODULE=test_uart_rx TOPLEVEL=uart_rx \
		LOCAL_COMPILE_ARGS="-GCLOCKS_PER_BAUD=8" \
		VERILOG_SOURCES="$(PWD)/../fpga/uart_rx.v"

# hu: F2.8.3a — generikus szinkron FIFO (a Mailbox építőeleme).
# en: F2.8.3a — generic synchronous FIFO (Mailbox building block).
test_fifo:
	$(SUBMAKE) MODULE=test_fifo TOPLEVEL=cilcpu_fifo VERILOG_SOURCES="$(PWD)/../src/cilcpu_fifo.v"

# hu: F2.8.3 — Mailbox (inbox/outbox FIFO + MMIO + IRQ).
# en: F2.8.3 — Mailbox (inbox/outbox FIFO + MMIO + IRQ).
test_mailbox:
	$(SUBMAKE) MODULE=test_mailbox TOPLEVEL=cilcpu_mailbox VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_fifo.v \
$(PWD)/../src/cilcpu_mailbox.v"

# hu: F2.8.4 — GPIO MMIO (in/out/oe, 2-FF input sync).
# en: F2.8.4 — GPIO MMIO (in/out/oe, 2-FF input sync).
test_gpio:
	$(SUBMAKE) MODULE=test_gpio TOPLEVEL=cilcpu_gpio VERILOG_SOURCES="$(PWD)/../src/cilcpu_gpio.v"

# hu: F2.8.5 — Trace MUX (konfigurálható belső-jel kimenet).
# en: F2.8.5 — Trace MUX (configurable internal-signal output).
test_trace:
	$(SUBMAKE) MODULE=test_trace TOPLEVEL=cilcpu_trace VERILOG_SOURCES="$(PWD)/../src/cilcpu_trace.v"

# hu: F2.8 #6.5 — SoC wrapper (cilcpu_soc): core + MMIO-dekód + mailbox/gpio/
#     trace. A test_soc.py a test_core boot-harness-ét importálja (a soc
#     boot/qspi/státusz portjai névazonosak a core-éval).
# en: F2.8 #6.5 — SoC wrapper (cilcpu_soc): core + MMIO decode + mailbox/gpio/
#     trace. test_soc.py imports the test_core boot harness (the soc's
#     boot/qspi/status ports share the core's names).
test_soc:
	$(SUBMAKE) MODULE=test_soc TOPLEVEL=cilcpu_soc LOCAL_COMPILE_ARGS="-GUART_CLOCKS_PER_BAUD=8" VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../src/cilcpu_fifo.v \
$(PWD)/../src/cilcpu_mailbox.v \
$(PWD)/../src/cilcpu_gpio.v \
$(PWD)/../src/cilcpu_trace.v \
$(PWD)/../src/cilcpu_uart_loader.v \
$(PWD)/../src/cilcpu_boot_ctrl.v \
$(PWD)/../fpga/uart_rx.v \
$(PWD)/../src/cilcpu_soc.v"
# hu: megj. — a cilcpu_qspi_controller.v már a fenti listában; a cilcpu_soc
#     (F1a) maga példányosítja a controllert, (F1b) az uart_rx + uart_loader-t is.

# hu: F2.8.6 — Tiny Tapeout tt_um ekvivalens top (cilcpu_soc + eredmény-printer
#     a 24-pin TT interfészre). A SoC összes forrása + uart_rx (loader) +
#     uart_tx/decimal_printer (eredmény) + cilcpu_tt_top.
# en: F2.8.6 — Tiny Tapeout tt_um equivalent top (cilcpu_soc + result printer
#     on the 24-pin TT interface). All SoC sources + uart_rx (loader) +
#     uart_tx/decimal_printer (result) + cilcpu_tt_top.
test_tt_top:
	$(SUBMAKE) MODULE=test_tt_top TOPLEVEL=cilcpu_tt_top LOCAL_COMPILE_ARGS="-GCLOCKS_PER_BAUD=8" VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../src/cilcpu_fifo.v \
$(PWD)/../src/cilcpu_mailbox.v \
$(PWD)/../src/cilcpu_gpio.v \
$(PWD)/../src/cilcpu_trace.v \
$(PWD)/../src/cilcpu_uart_loader.v \
$(PWD)/../src/cilcpu_boot_ctrl.v \
$(PWD)/../fpga/uart_rx.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../src/cilcpu_soc.v \
$(PWD)/../fpga/cilcpu_tt_top.v"

# hu: F2.8.6 — A7-Lite board top a tt_top köré (cilcpu_tt_board). A QSPI a
#     qspi-pmod-ra megy a JP1-en (IOBUF) — sim módban (+DCILCPU_SIM_BOARD) split
#     debug portok a uio inout busz helyett. Nincs STARTUPE2 (a clk sima I/O pin).
# en: F2.8.6 — A7-Lite board top around tt_top (cilcpu_tt_board). QSPI goes to
#     the qspi-pmod via JP1 (IOBUF) — in sim (+DCILCPU_SIM_BOARD) split debug
#     ports instead of the uio inout bus. No STARTUPE2 (clk is a plain I/O pin).
test_tt_board:
	$(SUBMAKE) MODULE=test_tt_board TOPLEVEL=cilcpu_tt_board LOCAL_COMPILE_ARGS="-GCLOCKS_PER_BAUD=8 -DCILCPU_SIM_BOARD" VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../src/cilcpu_fifo.v \
$(PWD)/../src/cilcpu_mailbox.v \
$(PWD)/../src/cilcpu_gpio.v \
$(PWD)/../src/cilcpu_trace.v \
$(PWD)/../src/cilcpu_uart_loader.v \
$(PWD)/../src/cilcpu_boot_ctrl.v \
$(PWD)/../fpga/uart_rx.v \
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v \
$(PWD)/../src/cilcpu_soc.v \
$(PWD)/../fpga/cilcpu_tt_top.v \
$(PWD)/../fpga/cilcpu_tt_board.v"

# hu: F2.8 #6.5b-F1b — UART boot-loader FSM (WRITE/BOOT keret-parser).
# en: F2.8 #6.5b-F1b — UART boot-loader FSM (WRITE/BOOT frame parser).
test_uart_loader:
	$(SUBMAKE) MODULE=test_uart_loader TOPLEVEL=cilcpu_uart_loader VERILOG_SOURCES="$(PWD)/../src/cilcpu_uart_loader.v"

# hu: F2.8 #6.5b-F1c — flash auto-detect boot controller (AUTODETECT=1).
# en: F2.8 #6.5b-F1c — flash auto-detect boot controller (AUTODETECT=1).
test_boot_ctrl:
	$(SUBMAKE) MODULE=test_boot_ctrl TOPLEVEL=cilcpu_boot_ctrl LOCAL_COMPILE_ARGS="-GAUTODETECT=1" VERILOG_SOURCES="$(PWD)/../src/cilcpu_boot_ctrl.v"

# hu: F2.8 #6.5b-F1c.2 — SoC autonóm flash-boot (BOOT_AUTODETECT=1). Ugyanaz a
#     forráslista mint a test_soc, csak a generic eltér.
# en: F2.8 #6.5b-F1c.2 — SoC autonomous flash boot (BOOT_AUTODETECT=1). Same
#     source list as test_soc, only the generic differs.
test_soc_autoboot:
	$(SUBMAKE) MODULE=test_soc_autoboot TOPLEVEL=cilcpu_soc LOCAL_COMPILE_ARGS="-GBOOT_AUTODETECT=1 -GUART_CLOCKS_PER_BAUD=8" VERILOG_SOURCES="\
$(PWD)/../src/cilcpu_alu.v \
$(PWD)/../src/cilcpu_decoder.v \
$(PWD)/../src/cilcpu_microcode.v \
$(PWD)/../src/cilcpu_stack_cache.v \
$(PWD)/../src/cilcpu_qspi_controller.v \
$(PWD)/../src/cilcpu_divider.v \
$(PWD)/../src/cilcpu_multiplier.v \
$(PWD)/../src/cilcpu_core.v \
$(PWD)/../src/cilcpu_fifo.v \
$(PWD)/../src/cilcpu_mailbox.v \
$(PWD)/../src/cilcpu_gpio.v \
$(PWD)/../src/cilcpu_trace.v \
$(PWD)/../src/cilcpu_uart_loader.v \
$(PWD)/../src/cilcpu_boot_ctrl.v \
$(PWD)/../fpga/uart_rx.v \
$(PWD)/../src/cilcpu_soc.v"

# hu: F2.7 Sub2 — 32-bit decimal printer (uart_tx-et példányosít).
# en: F2.7 Sub2 — 32-bit decimal printer (instantiates uart_tx).
test_decimal_printer:
	$(SUBMAKE) MODULE=test_decimal_printer TOPLEVEL=decimal_printer \
		LOCAL_COMPILE_ARGS="-GCLOCKS_PER_BAUD=8" \
		VERILOG_SOURCES="\
$(PWD)/../fpga/uart_tx.v \
$(PWD)/../fpga/decimal_printer.v"

.PHONY: test_alu test_decoder test_microcode test_stack_cache test_qspi_controller test_qspi_controller_offset test_divider test_multiplier test_qspi_qe_init test_core test_core_golden test_a7lite_top test_uart_tx test_uart_rx test_fifo test_mailbox test_gpio test_trace test_soc test_soc_autoboot test_uart_loader test_boot_ctrl test_decimal_printer test_a7lite_fib test_a7lite_board test_a7lite_board_fib test_tt_top test_tt_board
