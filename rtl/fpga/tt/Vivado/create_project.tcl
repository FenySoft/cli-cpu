# hu: CLI-CPU F2.8.6 — Vivado projekt auto-generáló TCL a `cilcpu_tt_board`
#     (Tiny Tapeout tt_um ekvivalens) A7-Lite top-ra. A
#     `rtl/fpga/Vivado/create_project.tcl` (a7lite_board) mintáját követi.
#     Eltérések: top = cilcpu_tt_board, a teljes tt forrásfa, a
#     cilcpu_tt_a7lite.xdc, és NINCS write_cfgmem (a program a qspi-pmod-on van,
#     nem a config-flash-en). NINCS STARTUPE2 (a QSPI clk sima I/O pin).
# en: CLI-CPU F2.8.6 — Vivado project auto-generation TCL for the
#     `cilcpu_tt_board` A7-Lite top. Mirrors the a7lite_board tcl. Differences:
#     top = cilcpu_tt_board, the full tt source tree, cilcpu_tt_a7lite.xdc, and
#     NO write_cfgmem (the program lives on the qspi-pmod, not the config flash).
#     NO STARTUPE2 (the QSPI clk is a plain I/O pin).
#
# Használat / Usage:
#   vivado -mode batch -source create_project.tcl

set project_name "cilcpu_tt"
set project_dir  [file dirname [file normalize [info script]]]
set build_dir    "$project_dir/build"
# hu: rtl/fpga/tt/Vivado/ → rtl/fpga = ../.. ; rtl/src = ../../../src
set fpga_dir     "$project_dir/../.."
set src_dir      "$fpga_dir/../src"

set part "xc7a200tfbg484-2"
set top_module "cilcpu_tt_board"

# hu: Teljes RTL forrásfa — a rtl/tb/Makefile `test_tt_board` listájával AZONOS,
#     sim_stubs NÉLKÜL (FPGA-n a Xilinx unisims adja az IOBUF-ot).
set rtl_files [list \
    "$src_dir/cilcpu_alu.v" \
    "$src_dir/cilcpu_decoder.v" \
    "$src_dir/cilcpu_microcode.v" \
    "$src_dir/cilcpu_stack_cache.v" \
    "$src_dir/cilcpu_qspi_controller.v" \
    "$src_dir/cilcpu_divider.v" \
    "$src_dir/cilcpu_multiplier.v" \
    "$src_dir/cilcpu_core.v" \
    "$src_dir/cilcpu_fifo.v" \
    "$src_dir/cilcpu_mailbox.v" \
    "$src_dir/cilcpu_gpio.v" \
    "$src_dir/cilcpu_trace.v" \
    "$src_dir/cilcpu_uart_loader.v" \
    "$src_dir/cilcpu_boot_ctrl.v" \
    "$fpga_dir/uart_rx.v" \
    "$fpga_dir/uart_tx.v" \
    "$fpga_dir/decimal_printer.v" \
    "$src_dir/cilcpu_soc.v" \
    "$fpga_dir/cilcpu_tt_top.v" \
    "$fpga_dir/cilcpu_tt_board.v" \
]

set inc_dir  "$src_dir"
set xdc_files [list "$fpga_dir/cilcpu_tt_a7lite.xdc"]

if {[file exists "$build_dir/$project_name.xpr"]} {
    puts "INFO: Meglévő projekt felülírása: $build_dir"
    file delete -force "$build_dir"
}
create_project $project_name $build_dir -part $part -force

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_files
set_property include_dirs [list $inc_dir] [get_filesets sources_1]
update_compile_order -fileset sources_1
set_property top $top_module [current_fileset]

# hu: FPGA generic-ek. CODE_BASE_OFFSET=0 (a program a qspi-pmod-on, nincs
#     config-flash-ütközés). QE_INIT_ENABLE=1 (W25Q128 Quad-read QE-init).
#     CLOCKS_PER_BAUD=434 (115200). BOOT_AUTODETECT=0 (boot-over-UART; 1 →
#     autonóm flash-boot a Pmod-flash-ből).
# en: FPGA generics. CODE_BASE_OFFSET=0 (program on the qspi-pmod, no config-
#     flash collision). QE_INIT_ENABLE=1. CLOCKS_PER_BAUD=434. BOOT_AUTODETECT=0.
set_property generic { \
    CODE_BASE_OFFSET=32'h0 \
    QE_INIT_ENABLE=32'd1 \
    CLOCKS_PER_BAUD=434 \
    BOOT_AUTODETECT=32'd0 \
} [current_fileset]

puts "INFO: Szintézis indul (cilcpu_tt_board)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "ERROR: Szintézis sikertelen" }

puts "INFO: Implementation + bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "ERROR: Implementation sikertelen" }

open_run impl_1
set rpt "$build_dir/timing_summary.rpt"
report_timing_summary -file $rpt

# hu: Utilization riport — a tile-becsléshez NEM ez kell (az Sky130/F2.6), de a
#     FPGA-erőforrás (LUT/FF/IOBUF) hasznos sanity-check.
# en: Utilization report — NOT for the tile estimate (that's Sky130/F2.6), but
#     FPGA resource (LUT/FF/IOBUF) is a useful sanity check.
set urpt "$build_dir/utilization.rpt"
report_utilization -file $urpt

set bitfile "$build_dir/$project_name.runs/impl_1/$top_module.bit"
puts ""
puts "=========================================================="
puts "INFO: Build SIKERES — $bitfile"
puts "INFO: Timing:      $rpt  (sys_clk WNS >= 0 ?)"
puts "INFO: Utilization: $urpt"
puts ""
puts "Kovetkezo: openFPGALoader-rel a config-flash-re, majd boot-over-UART"
puts "a qspi-pmod-ra (NINCS write_cfgmem — a program nem a config-flash-en van)."
puts "=========================================================="
