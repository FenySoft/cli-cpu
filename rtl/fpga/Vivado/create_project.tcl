# hu: CLI-CPU F2.7 Sub5 — Vivado projekt auto-generáló TCL a teljes
#     `cilcpu_a7lite_board` top-ra. A smoke_test/Vivado/create_project.tcl
#     mintáját követi, de a teljes RTL forrásfát szintetizálja
#     (cilcpu_core + 5 részegység + a7lite_top + board.v + uart_tx +
#     decimal_printer), az IS25L128F QSPI config flash-re drótozva.
#     Szintézis → implementation → write_bitstream → write_cfgmem.
# en: CLI-CPU F2.7 Sub5 — Vivado project auto-generation TCL for the full
#     `cilcpu_a7lite_board` top. Mirrors smoke_test/Vivado/create_project.tcl
#     but synthesizes the complete RTL source tree (cilcpu_core + its 5
#     sub-modules + a7lite_top + board.v + uart_tx + decimal_printer),
#     bound to the IS25L128F QSPI config flash. Synthesis → implementation
#     → write_bitstream → write_cfgmem.
#
# Használat / Usage:
#   Batch mód (parancssor):
#     vivado -mode batch -source create_project.tcl
#   GUI mód (Vivado-n belül):
#     Tools -> Run Tcl Script -> create_project.tcl
#
# Az alkalmazás-binárist (CIL-T0 .t0) a write_cfgmem.tcl ágyazza a
# config image-be — futtasd azt a write_bitstream UTÁN.
# The application binary (CIL-T0 .t0) is embedded by write_cfgmem.tcl —
# run it AFTER write_bitstream.
#
# Futási idő: ~15-30 perc egy modern gépen (teljes core, nem smoke).

# =============================================================
# Konfiguráció / Configuration
# =============================================================

set project_name "cilcpu_a7lite"
set project_dir  [file dirname [file normalize [info script]]]
set build_dir    "$project_dir/build"
set fpga_dir     "$project_dir/.."
set src_dir      "$fpga_dir/../src"

# A7-Lite XC7A200T — FBG484 package, -2 speed grade
# (a smoke_test-tel BIT-AZONOS part string)
set part "xc7a200tfbg484-2"

# hu: Top module — a board-szintű (FPGA) wrapper, NEM a sim-friendly top.
# en: Top module — the board-level (FPGA) wrapper, NOT the sim-friendly top.
set top_module "cilcpu_a7lite_board"

# hu: Teljes RTL forrásfa — a rtl/tb/Makefile `test_a7lite_board_fib`
#     VERILOG_SOURCES listájával AZONOS, a `sim_stubs/` NÉLKÜL
#     (FPGA-n a Xilinx 'unisims' adja a STARTUPE2 + IOBUF primitíveket).
#     A `cilcpu_core.v` a részegységei UTÁN, mert instanciálja őket.
# en: Full RTL source tree — IDENTICAL to the rtl/tb/Makefile
#     `test_a7lite_board_fib` VERILOG_SOURCES list, WITHOUT `sim_stubs/`
#     (on FPGA the Xilinx 'unisims' provide STARTUPE2 + IOBUF).
#     `cilcpu_core.v` after its sub-modules since it instantiates them.
set rtl_files [list \
    "$src_dir/cilcpu_alu.v" \
    "$src_dir/cilcpu_decoder.v" \
    "$src_dir/cilcpu_microcode.v" \
    "$src_dir/cilcpu_stack_cache.v" \
    "$src_dir/cilcpu_qspi_controller.v" \
    "$src_dir/cilcpu_divider.v" \
    "$src_dir/cilcpu_multiplier.v" \
    "$src_dir/cilcpu_core.v" \
    "$fpga_dir/uart_tx.v" \
    "$fpga_dir/decimal_printer.v" \
    "$fpga_dir/cilcpu_a7lite_top.v" \
    "$fpga_dir/cilcpu_a7lite_board.v" \
]

# hu: `cilcpu_defines.vh` az src/ alatt — include path-ként adjuk hozzá.
# en: `cilcpu_defines.vh` lives under src/ — added as an include path.
set inc_dir  "$src_dir"
set xdc_files [list "$fpga_dir/cilcpu_a7lite.xdc"]

# =============================================================
# Projekt létrehozása / Project creation
# =============================================================

if {[file exists "$build_dir/$project_name.xpr"]} {
    puts "INFO: Meglévő projekt felülírása: $build_dir"
    file delete -force "$build_dir"
}

create_project $project_name $build_dir -part $part -force

# =============================================================
# Források hozzáadása / Add sources
# =============================================================

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_files

# hu: `cilcpu_defines.vh` include könyvtár a szintézis és sim filesethez
# en: `cilcpu_defines.vh` include dir for synth and sim filesets
set_property include_dirs [list $inc_dir] [get_filesets sources_1]

update_compile_order -fileset sources_1
set_property top $top_module [current_fileset]

# =============================================================
# hu: FPGA paraméter-override-ok a top-level generikre
#     (a sim Verilator -G<...> override-ok FPGA-megfelelői).
#     DEBOUNCE_BITS=22  -> ~84 ms @ 50 MHz fizikai gomb pergésmentesítés
#     CLOCKS_PER_BAUD=434 -> 50 MHz / 115200 baud (CH340 UART)
#     BOOT_ARG_VALUE=20 + BOOT_LOCAL_COUNT=4 -> FibonacciIterative(20)
#     BOOT_PC=0x08, BOOT_ARG_COUNT=1 -> a .t0 belépési pontja a 8-byte
#     method header után (lásd a board.v default-jait, ezek ráadásul a
#     modul-default-ok, az override csak explicitté teszi).
# en: FPGA parameter overrides for the top-level generics (FPGA
#     counterparts of the sim Verilator -G<...> overrides).
# =============================================================

# hu: Sub5.A — CODE_BASE_OFFSET. EZ AZ EGYETLEN FORRÁS az FPGA-buildhez:
#     a CIL-T0 app flash-bázisa. A `write_cfgmem.tcl` PONTOSAN erre az
#     offszetre ágyazza a `.t0`-t (lásd ott a CODE_BASE_OFFSET_HEX
#     konstanst — a kettő MINDIG egyezzen). Érték: 0xC00000 = 12 MB,
#     a ~9,9 MB XC7A200T bitstream FÖLÉ (config-flash 0x0-tól tölti a
#     bitstream-et). CODE-ablak 20-bit = 1 MB → app [0xC00000..0xCFFFFF]
#     < 0x1000000 (16 MB IS25L128F). ~2,1 MB tartalék a bitstream fölött.
# en: Sub5.A — CODE_BASE_OFFSET. THE SINGLE SOURCE for the FPGA build:
#     the CIL-T0 app flash base. `write_cfgmem.tcl` embeds the `.t0` at
#     EXACTLY this offset (see its CODE_BASE_OFFSET_HEX constant — the
#     two must ALWAYS match). Value: 0xC00000 = 12 MB, ABOVE the ~9.9 MB
#     XC7A200T bitstream (config-flash loads the bitstream from 0x0).
#     CODE window 20-bit = 1 MB → app [0xC00000..0xCFFFFF] < 0x1000000
#     (16 MB IS25L128F). ~2.1 MB margin above the bitstream.
set_property generic { \
    BOOT_PC=32'h00000008 \
    BOOT_ARG_COUNT=32'd1 \
    BOOT_LOCAL_COUNT=32'd4 \
    BOOT_ARG_VALUE=32'd20 \
    DEBOUNCE_BITS=22 \
    CLOCKS_PER_BAUD=434 \
    CODE_BASE_OFFSET=32'hC00000 \
    QE_INIT_ENABLE=32'd1 \
} [current_fileset]

# =============================================================
# Szintézis / Synthesis
# =============================================================

puts "INFO: Szintézis indul (teljes cilcpu_a7lite_board)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: Szintézis sikertelen"
}

# =============================================================
# Implementation + Bitstream
# =============================================================

puts "INFO: Implementation + bitstream generálás indul..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation sikertelen"
}

# =============================================================
# hu: Timing riport kiírása — a 50 MHz (sys_clk) WNS a kulcs metrika.
#     A timing-zárás elfogadása a felhasználó gépén/hardverén dől el.
# en: Dump timing report — the 50 MHz (sys_clk) WNS is the key metric.
#     Timing-closure acceptance is decided on the user's machine/hardware.
# =============================================================

open_run impl_1
set rpt "$build_dir/timing_summary.rpt"
report_timing_summary -file $rpt
puts "INFO: Timing summary: $rpt"

# =============================================================
# Kész / Done
# =============================================================

set bitfile "$build_dir/$project_name.runs/impl_1/$top_module.bit"
puts ""
puts "=========================================================="
puts "INFO: Build SIKERES"
puts "INFO: Bitstream: $bitfile"
puts "INFO: Timing:    $rpt  (ellenőrizd: sys_clk WNS >= 0)"
puts ""
puts "Következő lépés / Next step:"
puts "  vivado -mode batch -source write_cfgmem.tcl -tclargs <app.t0>"
puts "  (a CIL-T0 binárist a config image-be ágyazza)"
puts "=========================================================="
