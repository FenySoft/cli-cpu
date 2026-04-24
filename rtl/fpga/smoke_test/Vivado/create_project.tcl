# hu: CLI-CPU smoke-teszt — Vivado projekt auto-generáló TCL script.
#     Létrehoz egy teljes Vivado projektet a led_blink.v + led_blink.xdc
#     fájlokból, lefuttatja a szintézist, implementációt és bitstream
#     generálást. Az eredmény egy .bit fájl, ami JTAG-en feltölthető.
# en: CLI-CPU smoke test — Vivado project auto-generation TCL script.
#     Creates a full Vivado project from led_blink.v + led_blink.xdc,
#     runs synthesis, implementation and bitstream generation. Output
#     is a .bit file ready to upload via JTAG.
#
# Használat / Usage:
#   Batch mód (parancssor):
#     vivado -mode batch -source create_project.tcl
#   GUI mód (Vivado-n belül):
#     Tools → Run Tcl Script → create_project.tcl
#
# Futási idő: ~5-10 perc egy modern gépen.

# =============================================================
# Konfiguráció / Configuration
# =============================================================

set project_name "led_blink"
set project_dir  [file dirname [file normalize [info script]]]
set build_dir    "$project_dir/build"

# A7-Lite XC7A200T — FBG484 package, -2 speed grade
set part "xc7a200tfbg484-2"

# Forrás fájlok
# led_blink.v megosztott az OpenXC7 build-del — egy szinttel feljebb van
# led_blink.v is shared with the OpenXC7 build — one level up
set rtl_files [list "$project_dir/../led_blink.v"]
set xdc_files [list "$project_dir/led_blink.xdc"]

# Top module neve (a led_blink.v-ben definiált)
set top_module "led_blink"

# =============================================================
# Projekt létrehozása / Project creation
# =============================================================

# Ha van korábbi build, ne vesszen el véletlenül a felhasználói munkája
# — csak akkor töröljük, ha a script újrafutáskor újragenerál mindent.
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
update_compile_order -fileset sources_1

set_property top $top_module [current_fileset]

# =============================================================
# Szintézis / Synthesis
# =============================================================

puts "INFO: Szintézis indul..."
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
# Kész / Done
# =============================================================

set bitfile "$build_dir/$project_name.runs/impl_1/$top_module.bit"
puts ""
puts "=========================================================="
puts "INFO: Build SIKERES"
puts "INFO: Bitstream: $bitfile"
puts ""
puts "Feltöltéshez / To program:"
puts "  1. Vivado GUI → Open Hardware Manager → Open target → Auto Connect"
puts "  2. Program device → válaszd ezt a .bit fájlt"
puts "=========================================================="
